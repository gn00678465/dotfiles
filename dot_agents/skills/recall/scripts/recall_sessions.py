#!/usr/bin/env python3
"""列出本機 Claude Code / Codex / Cursor 的 session，抽出使用者的需求內容。

每個 session 輸出一個區塊：session id、cwd、時間、使用者訊息 (已過濾系統注入
文字)、最後一則 assistant 文字，以及 Claude Code 的 ai-title。

只讀本機檔案，不上傳任何內容。Python 3.9+，只用標準函式庫。

用法範例:
  recall_sessions.py                          # 目前專案，近 7 天，所有來源
  recall_sessions.py --source claude --days 30 --project ~/Projects/foo
  recall_sessions.py --all --grep neovim --format json

退出碼: 0 正常; 2 參數或環境錯誤 (來源目錄不存在不算錯誤，只是沒有結果)。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

SOURCES = ("claude", "codex", "cursor")

# user 記錄裡由 CLI 注入、不是使用者親手輸入的文字。只看開頭的標籤。
# 前十個在 Claude Code 2.1.278 本機驗證過；其餘來自 Codex 的注入慣例。
# `<bash-input>` 與 `<pasted_content>` 是使用者親手輸入的內容，刻意保留。
# 含 <command-name> 的斜線指令段落另外處理 (見 slash_command_text)。
INJECTED_PREFIXES = (
    "<command-message>",
    "<command-args>",
    "<local-command-caveat>",
    "<local-command-stdout>",
    "<task-notification>",
    "<agent-message>",
    "<system-reminder>",
    "<tool-use-id>",
    "<bash-stdout>",
    "<bash-stderr>",
    "<environment_context>",
    "<user_instructions>",
    "<permissions",
    "<collaboration_mode>",
    "<recommended_plugins>",
    "<turn_context>",
    "<user_info>",
    "Base directory for this skill:",
    "This session is being continued from a previous conversation",
)

# 真正的使用者訊息後面有時會黏一段 <system-reminder>；整段拿掉，保留前面的文字。
SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)

# 斜線指令記錄：<command-name>/foo</command-name> 加 <command-args>使用者打的字</command-args>，
# 標籤順序不固定，<command-message> 是 CLI 加的顯示文字。args 是使用者親手輸入的需求。
COMMAND_NAME_RE = re.compile(r"<command-name>(.*?)</command-name>", re.DOTALL)
COMMAND_ARGS_RE = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)

# Cursor 格式未驗證。依序試這些欄位名，找不到就回報實際欄位。
CURSOR_ROLE_KEYS = ("role", "type", "author", "sender")
CURSOR_TEXT_KEYS = ("content", "text", "message", "parts")


# ---------------------------------------------------------------- 共用工具


def die(code: int, msg: str) -> None:
    print(f"recall_sessions: {msg}", file=sys.stderr)
    sys.exit(code)


def iter_jsonl_records(path: Path):
    """逐行讀 JSONL，壞行跳過，不整檔載入。"""
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                yield obj


def is_injected(text: str) -> bool:
    head = text.lstrip()[:120]
    return any(head.startswith(prefix) for prefix in INJECTED_PREFIXES)


def slash_command_text(text: str) -> str:
    """把斜線指令記錄還原成使用者輸入，例如 '/herdr <args>'；args 為空時只留指令名。"""
    name = COMMAND_NAME_RE.search(text)
    if name is None:
        return ""
    args = COMMAND_ARGS_RE.search(text)
    parts = [name.group(1).strip(), args.group(1).strip() if args else ""]
    return " ".join(part for part in parts if part)


def clean_user_text(text: str) -> str:
    """回傳可當作使用者需求的文字；整段是注入文字時回傳空字串。"""
    if not isinstance(text, str):
        return ""
    if "<command-name>" in text:
        return slash_command_text(text)
    if is_injected(text):
        return ""
    return SYSTEM_REMINDER_RE.sub("", text).strip()


def truncate(text: str, limit: int) -> str:
    text = text.strip()
    if limit <= 0 or len(text) <= limit:
        return text
    return text[:limit] + f" …[截斷 {len(text) - limit} 字元]"


def text_blocks(content) -> list:
    """把 message.content (字串或 block 陣列) 攤平成 text block 的字串清單。"""
    if isinstance(content, str):
        return [content]
    out = []
    if isinstance(content, list):
        for block in content:
            if isinstance(block, str):
                out.append(block)
            elif isinstance(block, dict):
                btype = block.get("type")
                if btype in (None, "text", "input_text", "output_text"):
                    text = block.get("text")
                    if isinstance(text, str):
                        out.append(text)
    return out


def mtime_of(path: Path):
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:
        return None


def iso(dt) -> str:
    if dt is None:
        return ""
    return dt.astimezone().strftime("%Y-%m-%d %H:%M")


def path_is_under(child: str, parent: Path) -> bool:
    try:
        c = Path(child).expanduser().resolve()
    except (OSError, RuntimeError, ValueError):
        return False
    return c == parent or parent in c.parents


def resolve_project(value) -> Path:
    if value:
        return Path(value).expanduser().resolve()
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if res.returncode == 0 and res.stdout.strip():
            return Path(res.stdout.strip()).resolve()
    except (subprocess.TimeoutExpired, OSError):
        pass
    return Path.cwd().resolve()


class MessageBuffer:
    """短對話全留；長對話留頭尾，中間以一則備註代替。"""

    def __init__(self, limit: int):
        self.limit = limit
        self.items = []
        self.total = 0

    def append(self, item) -> None:
        self.total += 1
        self.items.append(item)

    def finish(self) -> list:
        if self.limit <= 0 or len(self.items) <= self.limit:
            return self.items
        head = max(1, (self.limit * 2) // 3)
        tail = max(1, self.limit - head)
        omitted = len(self.items) - head - tail
        return (
            self.items[:head]
            + [{"ts": "", "text": f"[… 省略中間 {omitted} 則使用者訊息 …]", "omitted": omitted}]
            + self.items[-tail:]
        )


def new_session(source: str, path: Path) -> dict:
    return {
        "source": source,
        "id": path.stem,
        "title": "",
        "cwd": "",
        "file": str(path),
        "mtime": iso(mtime_of(path)),
        "started_at": "",
        "ended_at": "",
        "version": "",
        "is_subagent": False,
        "stats": {"user_turns": 0, "assistant_turns": 0, "tool_calls": 0},
        "user_messages": [],
        "last_assistant_text": "",
        "warnings": [],
    }


# ---------------------------------------------------------------- Claude Code


def claude_slug(project: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", str(project))


def find_claude_files(home: Path, include_subagents: bool) -> list:
    projects = home / "projects"
    if not projects.is_dir():
        return []
    files = list(projects.glob("*/*.jsonl"))
    if include_subagents:
        files.extend(projects.glob("*/*/subagents/*.jsonl"))
    return files


def parse_claude_session(path: Path, opts) -> dict:
    session = new_session("claude", path)
    messages = MessageBuffer(opts.max_messages)
    seen_assistant_ids = set()
    first_ts = last_ts = None
    sidechain_seen = None
    id_set = False

    for obj in iter_jsonl_records(path):
        ts = obj.get("timestamp")
        if isinstance(ts, str) and ts:
            first_ts = first_ts or ts
            last_ts = ts

        rtype = obj.get("type")
        if rtype == "ai-title":
            title = obj.get("aiTitle")
            if isinstance(title, str) and title.strip():
                session["title"] = title.strip()
            continue

        if "isSidechain" in obj:
            # 整個 session 是不是子代理，看第一筆帶旗標的記錄。主檔裡零星混入的
            # 子代理行只跳過該行，主線繼續。
            if sidechain_seen is None:
                sidechain_seen = bool(obj["isSidechain"])
                session["is_subagent"] = sidechain_seen
            if obj["isSidechain"] and not opts.include_subagents:
                continue

        if not session["cwd"] and isinstance(obj.get("cwd"), str):
            session["cwd"] = obj["cwd"]
        if not session["version"] and isinstance(obj.get("version"), str):
            session["version"] = obj["version"]
        if not id_set and isinstance(obj.get("sessionId"), str):
            id_set = True
            session["id"] = obj["sessionId"]
            if isinstance(obj.get("agentId"), str) and obj["agentId"]:
                session["id"] += "/" + obj["agentId"]

        message = obj.get("message")
        if rtype not in ("user", "assistant") or not isinstance(message, dict):
            continue

        if rtype == "user":
            if obj.get("isMeta") or obj.get("isCompactSummary"):
                continue
            texts = [clean_user_text(t) for t in text_blocks(message.get("content"))]
            texts = [t for t in texts if t]
            if not texts:
                continue
            session["stats"]["user_turns"] += 1
            messages.append({"ts": ts or "", "text": truncate("\n".join(texts), opts.max_chars)})
            continue

        # assistant：一次回應拆成多行，共用 message.id，統計回合以它去重。
        message_id = message.get("id") or obj.get("uuid")
        if message_id not in seen_assistant_ids:
            seen_assistant_ids.add(message_id)
            session["stats"]["assistant_turns"] += 1
        content = message.get("content")
        blocks = content if isinstance(content, list) else [{"type": "text", "text": content}]
        for block in blocks:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "tool_use":
                session["stats"]["tool_calls"] += 1
            elif btype == "text":
                text = block.get("text")
                if isinstance(text, str) and text.strip():
                    session["last_assistant_text"] = truncate(text, opts.max_chars)

    session["started_at"] = first_ts or ""
    session["ended_at"] = last_ts or ""
    session["user_messages"] = messages.finish()
    return session


def collect_claude(opts, projects, cutoff) -> list:
    home = Path(opts.claude_home).expanduser()
    out = []
    for path in find_claude_files(home, opts.include_subagents):
        mt = mtime_of(path)
        if mt is None or (cutoff and mt < cutoff):
            continue
        if projects is not None:
            slugs = {claude_slug(p) for p in projects}
            # 主檔在 projects/<slug>/，子代理檔在 projects/<slug>/<id>/subagents/。
            if path.parent.name not in slugs and path.parent.parent.parent.name not in slugs:
                continue
        session = parse_claude_session(path, opts)
        if projects is not None and session["cwd"]:
            if not any(path_is_under(session["cwd"], p) for p in projects):
                continue
        out.append((mt, session))
    return out


# ---------------------------------------------------------------- Codex


def find_codex_files(home: Path) -> list:
    files = []
    for sub in ("sessions", "archived_sessions"):
        root = home / sub
        if root.is_dir():
            files.extend(root.rglob("rollout-*.jsonl"))
    return files


def parse_codex_session(path: Path, opts) -> dict:
    session = new_session("codex", path)
    event_messages = MessageBuffer(opts.max_messages)
    item_messages = MessageBuffer(opts.max_messages)
    first_ts = last_ts = None

    for obj in iter_jsonl_records(path):
        ts = obj.get("timestamp")
        if isinstance(ts, str) and ts:
            first_ts = first_ts or ts
            last_ts = ts
        payload = obj.get("payload")
        if not isinstance(payload, dict):
            continue
        ltype = obj.get("type")

        if ltype == "session_meta":
            session["id"] = str(payload.get("id") or payload.get("session_id") or path.stem)
            session["cwd"] = payload.get("cwd") or ""
            session["version"] = str(payload.get("cli_version") or "")
            source = payload.get("source")
            if payload.get("thread_source") == "subagent" or (
                isinstance(source, dict) and "subagent" in source
            ):
                session["is_subagent"] = True
            continue

        ptype = payload.get("type")
        if ltype == "event_msg":
            text = payload.get("message")
            if not isinstance(text, str) or not text.strip():
                continue
            if ptype == "user_message":
                text = clean_user_text(text)
                if text:
                    session["stats"]["user_turns"] += 1
                    event_messages.append({"ts": ts or "", "text": truncate(text, opts.max_chars)})
            elif ptype == "agent_message":
                session["stats"]["assistant_turns"] += 1
                session["last_assistant_text"] = truncate(text, opts.max_chars)
            continue

        if ltype != "response_item":
            continue
        if ptype == "message":
            role = payload.get("role")
            texts = text_blocks(payload.get("content"))
            if role == "user":
                texts = [clean_user_text(t) for t in texts]
                texts = [t for t in texts if t]
                if texts:
                    item_messages.append({"ts": ts or "", "text": truncate("\n".join(texts), opts.max_chars)})
            elif role == "assistant":
                joined = "\n".join(t for t in texts if t.strip())
                if joined.strip():
                    session["last_assistant_text"] = truncate(joined, opts.max_chars)
        elif ptype in ("function_call", "custom_tool_call", "local_shell_call"):
            # local_shell_call 的指令在 payload.action，不在 arguments；這裡只計數。
            session["stats"]["tool_calls"] += 1

    # event_msg 是 CLI 記的使用者輸入，最乾淨；沒有時退回 response_item。
    if event_messages.total:
        session["user_messages"] = event_messages.finish()
    else:
        session["stats"]["user_turns"] = item_messages.total
        session["user_messages"] = item_messages.finish()
    session["started_at"] = first_ts or ""
    session["ended_at"] = last_ts or ""
    return session


def collect_codex(opts, projects, cutoff) -> list:
    home = Path(opts.codex_home).expanduser()
    out = []
    for path in find_codex_files(home):
        mt = mtime_of(path)
        if mt is None or (cutoff and mt < cutoff):
            continue
        session = parse_codex_session(path, opts)
        if session["is_subagent"] and not opts.include_subagents:
            continue
        if projects is not None and not any(
            path_is_under(session["cwd"], p) for p in projects if session["cwd"]
        ):
            continue
        out.append((mt, session))
    return out


# ---------------------------------------------------------------- Cursor


def cursor_slug(project: Path) -> str:
    return str(project).lstrip("/").replace("\\", "-").replace("/", "-")


def find_cursor_files(home: Path) -> list:
    projects = home / "projects"
    if not projects.is_dir():
        return []
    return list(projects.glob("*/agent-transcripts/*/*.jsonl"))


def cursor_role_and_text(obj: dict):
    role = None
    for key in CURSOR_ROLE_KEYS:
        value = obj.get(key)
        if isinstance(value, str) and value:
            role = value.lower()
            break
    text = ""
    for key in CURSOR_TEXT_KEYS:
        value = obj.get(key)
        if isinstance(value, dict):
            value = value.get("content", value.get("text"))
        if isinstance(value, (str, list)):
            joined = "\n".join(t for t in text_blocks(value) if t)
            if joined.strip():
                text = joined
                break
    return role, text


def parse_cursor_session(path: Path, opts) -> dict:
    session = new_session("cursor", path)
    session["cwd"] = path.parent.parent.parent.name
    messages = MessageBuffer(opts.max_messages)
    observed_fields = set()
    records = 0
    recognised = 0

    for obj in iter_jsonl_records(path):
        records += 1
        observed_fields.update(k for k in obj.keys() if isinstance(k, str))
        ts = obj.get("timestamp") or obj.get("createdAt") or obj.get("created_at") or ""
        if not isinstance(ts, str):
            ts = str(ts)
        role, text = cursor_role_and_text(obj)
        if not role or not text:
            continue
        if role in ("user", "human"):
            text = clean_user_text(text)
            if text:
                recognised += 1
                session["stats"]["user_turns"] += 1
                messages.append({"ts": ts, "text": truncate(text, opts.max_chars)})
        elif role in ("assistant", "ai", "agent"):
            recognised += 1
            session["stats"]["assistant_turns"] += 1
            session["last_assistant_text"] = truncate(text, opts.max_chars)

    if records and not recognised:
        session["warnings"].append(
            "Cursor 記錄格式未知，沒有抽出任何訊息。實際欄位: "
            + ", ".join(sorted(observed_fields))
        )
    session["observed_fields"] = sorted(observed_fields)
    session["user_messages"] = messages.finish()
    return session


def collect_cursor(opts, projects, cutoff) -> list:
    home = Path(opts.cursor_home).expanduser()
    out = []
    slugs = None if projects is None else {cursor_slug(p) for p in projects}
    for path in find_cursor_files(home):
        mt = mtime_of(path)
        if mt is None or (cutoff and mt < cutoff):
            continue
        if slugs is not None and path.parent.parent.parent.name not in slugs:
            continue
        out.append((mt, parse_cursor_session(path, opts)))
    return out


# ---------------------------------------------------------------- 輸出


def matches_keywords(session: dict, keywords) -> bool:
    if not keywords:
        return True
    haystack = "\n".join(
        [session["title"], session["cwd"], session["last_assistant_text"]]
        + [m["text"] for m in session["user_messages"]]
    ).lower()
    return any(k.lower() in haystack for k in keywords)


def render_markdown(sessions: list) -> str:
    if not sessions:
        return "沒有符合條件的 session。\n"
    lines = []
    for s in sessions:
        heading = f"## [{s['source']}] {s['id']}"
        if s["title"]:
            heading += f" — {s['title']}"
        lines.append(heading)
        lines.append(f"- cwd: {s['cwd'] or '(未知)'}")
        span = " → ".join(t for t in (s["started_at"], s["ended_at"]) if t)
        lines.append(f"- 時間: {span or '(未知)'}；檔案修改 {s['mtime']}")
        st = s["stats"]
        lines.append(
            f"- 回合: user {st['user_turns']} / assistant {st['assistant_turns']} / 工具呼叫 {st['tool_calls']}"
            + (" / 子代理" if s["is_subagent"] else "")
        )
        lines.append(f"- 檔案: {s['file']}")
        for w in s["warnings"]:
            lines.append(f"- 警告: {w}")
        lines.append("")
        lines.append("### 使用者訊息")
        if not s["user_messages"]:
            lines.append("(無)")
        for i, m in enumerate(s["user_messages"], 1):
            stamp = f" [{m['ts']}]" if m.get("ts") else ""
            lines.append(f"{i}.{stamp} {m['text']}")
        lines.append("")
        lines.append("### 最後一則 assistant 文字")
        lines.append(s["last_assistant_text"] or "(無)")
        lines.append("")
    return "\n".join(lines)


def parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", choices=SOURCES + ("all",), default="all",
                   help="來源 (預設 all)")
    scope = p.add_mutually_exclusive_group()
    scope.add_argument("--project", action="append", default=[],
                       help="專案路徑，可重複；預設是目前 git 根目錄或 cwd")
    scope.add_argument("--all", action="store_true", help="不限專案")
    p.add_argument("--days", type=int, default=7,
                   help="只看檔案 mtime 在最近 N 天內的 session；0 表示不限 (預設 7)")
    p.add_argument("--grep", action="append", default=[],
                   help="關鍵字過濾，可重複，不分大小寫；任一命中即保留")
    p.add_argument("--format", choices=("markdown", "json"), default="markdown")
    p.add_argument("--include-subagents", action="store_true", help="包含子代理 session")
    p.add_argument("--limit", type=int, default=0, help="最多輸出幾個 session，0 表示不限")
    p.add_argument("--max-chars", type=int, default=1500, help="每則訊息保留的字元數")
    p.add_argument("--max-messages", type=int, default=40,
                   help="每個 session 保留的使用者訊息數，超過時留頭尾")
    p.add_argument("--claude-home", default=os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude"))
    p.add_argument("--codex-home", default=os.environ.get("CODEX_HOME", "~/.codex"))
    p.add_argument("--cursor-home", default=os.environ.get("CURSOR_HOME", "~/.cursor"))
    return p.parse_args(argv)


def main(argv=None) -> int:
    opts = parse_args(argv)
    if opts.days < 0:
        die(2, "--days 不能是負數")

    projects = None if opts.all else [resolve_project(v) for v in (opts.project or [None])]
    cutoff = None
    if opts.days > 0:
        cutoff = datetime.now(tz=timezone.utc) - timedelta(days=opts.days)

    collectors = {"claude": collect_claude, "codex": collect_codex, "cursor": collect_cursor}
    wanted = SOURCES if opts.source == "all" else (opts.source,)
    found = []
    for name in wanted:
        found.extend(collectors[name](opts, projects, cutoff))

    found.sort(key=lambda item: item[0], reverse=True)
    sessions = [s for _, s in found if matches_keywords(s, opts.grep)]
    if opts.limit > 0:
        sessions = sessions[: opts.limit]

    if opts.format == "json":
        print(json.dumps({
            "scope": {
                "sources": list(wanted),
                "projects": None if projects is None else [str(p) for p in projects],
                "days": opts.days,
                "keywords": opts.grep,
            },
            "sessions": sessions,
        }, ensure_ascii=False, indent=2))
    else:
        sys.stdout.write(render_markdown(sessions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
