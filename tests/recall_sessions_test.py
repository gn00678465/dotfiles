#!/usr/bin/env python3
"""recall skill 解析腳本的最小測試。

用 tests/fixtures/recall/ 的手寫 JSONL 在暫存目錄組出 Claude / Codex / Cursor 的
家目錄，跑 dot_agents/skills/recall/scripts/recall_sessions.py，檢查：

- Claude 一次回應拆成多行、共用 message.id 時，回合數只算一次。
- user 記錄裡的注入文字 (command-name、system-reminder 等) 全部被過濾；
  黏在真正訊息後面的 <system-reminder> 被剪掉，前面的文字保留。
- 子代理檔與 isSidechain 記錄預設跳過，加 --include-subagents 才出現。
- 專案過濾、mtime 天數視窗、關鍵字過濾、Markdown 與 JSON 輸出。
- Codex 的 session_meta、user_message、local_shell_call 與子代理判定。
- Cursor 未知格式不當機，並回報實際欄位。

fixture 裡的 __PROJ__ / __OTHER__ 在複製時代換成暫存專案路徑，目錄名用腳本
自己的 slug 函式算，所以 Windows 上也能跑。

退出碼: 0 全部成立; 1 有檢查失敗; 2 測試本身跑不起來。只用標準函式庫。

用法: tests/recall_sessions_test.py [repo-root]
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CHECKS = 0


def die(code: int, msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def check(cond: bool, msg: str) -> None:
    global CHECKS
    if not cond:
        die(1, msg)
    CHECKS += 1


def load_module(script: Path):
    # 不寫 __pycache__：它會落在 dot_agents/ 裡，被 chezmoi 當成受管檔案 (L3 golden)。
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("recall_sessions", script)
    if spec is None or spec.loader is None:
        die(2, f"cannot import {script}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def place(src: Path, dest: Path, subst: dict, age_days: int = 0) -> None:
    text = src.read_text(encoding="utf-8")
    for key, value in subst.items():
        text = text.replace(key, json.dumps(value)[1:-1])
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, encoding="utf-8")
    stamp = time.time() - age_days * 86400
    os.utime(dest, (stamp, stamp))


def run(script: Path, homes: dict, *args: str) -> dict:
    cmd = [sys.executable, str(script),
           "--claude-home", str(homes["claude"]),
           "--codex-home", str(homes["codex"]),
           "--cursor-home", str(homes["cursor"]),
           "--format", "json", *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        die(1, f"script exited {r.returncode} for {args}: {r.stderr.strip()}")
    try:
        return json.loads(r.stdout)
    except ValueError as exc:
        die(1, f"script printed invalid JSON for {args}: {exc}")
    return {}


def by_source(data: dict) -> dict:
    out: dict = {}
    for s in data["sessions"]:
        out.setdefault(s["source"], []).append(s)
    return out


def main() -> None:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent.parent
    script = root / "dot_agents" / "skills" / "recall" / "scripts" / "recall_sessions.py"
    fixtures = root / "tests" / "fixtures" / "recall"
    if not script.is_file():
        die(2, f"missing script: {script}")
    if not fixtures.is_dir():
        die(2, f"missing fixtures: {fixtures}")
    mod = load_module(script)

    # 負向控制：先證明過濾函式真的會擋注入文字、也真的會放行一般文字，
    # 不然「fixture 裡沒有漏出注入文字」跟「過濾器什麼都擋掉」看起來一樣。
    check(mod.clean_user_text("<system-reminder>x</system-reminder>") == "",
          "negative control: clean_user_text did not drop a bare system-reminder")
    check(mod.clean_user_text("一般需求") == "一般需求",
          "negative control: clean_user_text altered plain text")
    for prefix in mod.INJECTED_PREFIXES:
        check(mod.is_injected(f"  {prefix}payload") is True,
              f"is_injected missed prefix {prefix!r}")
    check(mod.is_injected("<bash-input>ls</bash-input>") is False,
          "is_injected must keep <bash-input>: the user typed it")
    # 斜線指令：標籤順序不固定；<command-args> 是使用者打的字，空的時候只留指令名。
    check(mod.clean_user_text(
        "<command-message>herdr</command-message>\n<command-name>/herdr</command-name>\n"
        "<command-args>接續上次的工作</command-args>") == "/herdr 接續上次的工作",
        "slash command with args must become '/name args'")
    check(mod.clean_user_text(
        "<command-name>/reload-skills</command-name>\n            "
        "<command-message>reload-skills</command-message>\n            "
        "<command-args></command-args>") == "/reload-skills",
        "slash command with empty args must keep the command name")
    check(mod.clean_user_text("<command-args>lone</command-args>") == "",
          "a lone <command-args> segment without <command-name> is still dropped")

    with tempfile.TemporaryDirectory(prefix="recall-test-") as tmp_s:
        tmp = Path(tmp_s).resolve()
        proj = tmp / "proj"
        other = tmp / "other"
        proj.mkdir()
        other.mkdir()
        subst = {"__PROJ__": str(proj), "__OTHER__": str(other)}
        homes = {"claude": tmp / "claude", "codex": tmp / "codex", "cursor": tmp / "cursor"}

        cp = homes["claude"] / "projects"
        slug = mod.claude_slug(proj)
        main_id = "aaaaaaaa-0000-4000-8000-000000000001"
        place(fixtures / "claude-main.jsonl", cp / slug / f"{main_id}.jsonl", subst)
        place(fixtures / "claude-subagent.jsonl",
              cp / slug / main_id / "subagents" / "agent-77.jsonl", subst)
        place(fixtures / "claude-stale.jsonl",
              cp / slug / "cccccccc-0000-4000-8000-000000000003.jsonl", subst, age_days=30)
        place(fixtures / "claude-other.jsonl",
              cp / mod.claude_slug(other) / "bbbbbbbb-0000-4000-8000-000000000002.jsonl", subst)

        cx = homes["codex"] / "sessions" / "2026" / "09" / "20"
        place(fixtures / "codex-main.jsonl", cx / "rollout-2026-09-20T03-00-00-main.jsonl", subst)
        place(fixtures / "codex-subagent.jsonl",
              homes["codex"] / "archived_sessions" / "rollout-2026-09-20T03-30-00-sub.jsonl", subst)

        cu = homes["cursor"] / "projects" / mod.cursor_slug(proj) / "agent-transcripts"
        place(fixtures / "cursor-unknown.jsonl",
              cu / "11111111-aaaa-4bbb-8ccc-000000000001" / "11111111-aaaa-4bbb-8ccc-000000000001.jsonl", subst)
        place(fixtures / "cursor-role.jsonl",
              cu / "22222222-aaaa-4bbb-8ccc-000000000002" / "22222222-aaaa-4bbb-8ccc-000000000002.jsonl", subst)

        # ---- 預設範圍：目前專案、7 天、所有來源
        data = run(script, homes, "--project", str(proj))
        srcs = by_source(data)
        check(sorted(srcs) == ["claude", "codex", "cursor"], f"expected all three sources, got {sorted(srcs)}")

        claude = srcs["claude"]
        check([s["id"] for s in claude] == [main_id],
              f"claude should list only the fresh main session, got {[s['id'] for s in claude]}")
        s = claude[0]
        check(s["title"] == "Neovim completion 改用 blink", f"ai-title not picked up: {s['title']!r}")
        check(s["cwd"] == str(proj), f"cwd mismatch: {s['cwd']!r}")
        check(s["version"] == "2.1.278", f"version mismatch: {s['version']!r}")
        check(s["stats"]["assistant_turns"] == 2,
              f"assistant rows sharing message.id must count once; got {s['stats']['assistant_turns']}")
        check(s["stats"]["tool_calls"] == 2, f"tool_calls mismatch: {s['stats']['tool_calls']}")
        texts = [m["text"] for m in s["user_messages"]]
        check(texts == [
            "請把 neovim 的 completion 設定改成用 blink",
            "/reload-skills",
            "/herdr dotfiles 建立一個 recall skill",
            "然後也把 lazy.nvim 鎖版本",
            "先確認測試會過",
            "<bash-input>git status</bash-input>",
            '<pasted_content id="ab12">貼上的需求：改 keymap</pasted_content>',
        ], f"user messages after filtering are wrong: {texts}")
        check(s["stats"]["user_turns"] == 7, f"user_turns mismatch: {s['stats']['user_turns']}")
        check(s["last_assistant_text"] == "blink 已換好，lazy-lock.json 也更新了。",
              f"last assistant text wrong: {s['last_assistant_text']!r}")
        check(s["started_at"].startswith("2026-09-20T01:00:00") and s["ended_at"].startswith("2026-09-20T01:05:01"),
              f"time span wrong: {s['started_at']} → {s['ended_at']}")
        check(s["is_subagent"] is False, "main session flagged as subagent")

        codex = srcs["codex"]
        check([c["id"] for c in codex] == ["019a0000-0000-7000-8000-000000000004"],
              f"codex should list only the non-subagent session, got {[c['id'] for c in codex]}")
        c = codex[0]
        check(c["cwd"] == str(proj), f"codex cwd wrong: {c['cwd']!r}")
        check([m["text"] for m in c["user_messages"]] == ["幫我把 CI 的 lint 步驟改成 ruff"],
              f"codex user messages wrong: {[m['text'] for m in c['user_messages']]}")
        check(c["stats"]["tool_calls"] == 2, f"codex tool_calls wrong: {c['stats']['tool_calls']}")
        check(c["last_assistant_text"] == "ci.yml 已改成 ruff check。",
              f"codex last assistant text wrong: {c['last_assistant_text']!r}")

        cursor = {u["id"]: u for u in srcs["cursor"]}
        unknown = cursor["11111111-aaaa-4bbb-8ccc-000000000001"]
        check(unknown["user_messages"] == [] and unknown["warnings"],
              "cursor unknown format must yield no messages and a warning")
        check("kind" in unknown["observed_fields"] and "payload" in unknown["observed_fields"],
              f"cursor warning must list observed fields, got {unknown['observed_fields']}")
        role = cursor["22222222-aaaa-4bbb-8ccc-000000000002"]
        check([m["text"] for m in role["user_messages"]] == ["把 README 的安裝章節翻成英文"],
              f"cursor role/content heuristic failed: {role['user_messages']}")
        check(role["last_assistant_text"] == "翻好了，請看 README.md。",
              f"cursor assistant text wrong: {role['last_assistant_text']!r}")

        # ---- 子代理
        data = run(script, homes, "--project", str(proj), "--include-subagents", "--source", "claude")
        ids = sorted(s["id"] for s in data["sessions"])
        check(ids == [main_id, f"{main_id}/agent-77"],
              f"--include-subagents should add the subagent file as <session>/<agent>, got {ids}")
        sub = next(s for s in data["sessions"] if s["id"] == f"{main_id}/agent-77")
        check(sub["is_subagent"] is True and sub["user_messages"][0]["text"] == "子代理任務：找出所有 keymap 檔",
              "subagent session content wrong")
        main = next(s for s in data["sessions"] if s["id"] == main_id)
        check(any(m["text"] == "子代理的提示，不是使用者輸入" for m in main["user_messages"]),
              "inline isSidechain row must appear only with --include-subagents")

        data = run(script, homes, "--project", str(proj), "--include-subagents", "--source", "codex")
        check(len(data["sessions"]) == 2, "codex --include-subagents should list both sessions")

        # ---- 天數視窗與 --all
        data = run(script, homes, "--project", str(proj), "--days", "0", "--source", "claude")
        ids = sorted(s["id"] for s in data["sessions"])
        check("cccccccc-0000-4000-8000-000000000003" in ids and len(ids) == 2,
              f"--days 0 should include the stale session, got {ids}")

        data = run(script, homes, "--all", "--source", "claude")
        ids = sorted(s["id"] for s in data["sessions"])
        check("bbbbbbbb-0000-4000-8000-000000000002" in ids,
              f"--all should include the other project, got {ids}")
        check(data["scope"]["projects"] is None, "--all must report projects=null in scope")

        # ---- 關鍵字與 limit
        data = run(script, homes, "--project", str(proj), "--grep", "RUFF")
        check([s["source"] for s in data["sessions"]] == ["codex"],
              f"--grep is case-insensitive and keeps only matches, got {[s['source'] for s in data['sessions']]}")
        data = run(script, homes, "--project", str(proj), "--grep", "blink", "--grep", "ruff")
        check(sorted(s["source"] for s in data["sessions"]) == ["claude", "codex"],
              "several --grep values should OR together")
        data = run(script, homes, "--project", str(proj), "--limit", "1")
        check(len(data["sessions"]) == 1, "--limit 1 should keep one session")

        # ---- 直接給 session id：前綴比對，且時間視窗自動放開
        data = run(script, homes, "--project", str(proj), "--session", "cccccccc")
        check([s["id"][:8] for s in data["sessions"]] == ["cccccccc"] and data["scope"]["days"] == 0,
              f"--session must match by prefix and lift the day window, got {data['scope']} "
              f"{[s['id'] for s in data['sessions']]}")
        data = run(script, homes, "--project", str(proj), "--session", "cccccccc", "--days", "7")
        check(data["sessions"] == [], "an explicit --days still applies together with --session")
        data = run(script, homes, "--all", "--source", "codex", "--session", "019a0000")
        check(len(data["sessions"]) == 1 and data["sessions"][0]["source"] == "codex",
              "--session works for codex ids")

        # ---- 頭尾截斷
        data = run(script, homes, "--project", str(proj), "--source", "claude", "--max-messages", "3")
        msgs = data["sessions"][0]["user_messages"]
        check(len(msgs) == 4 and msgs[2].get("omitted") == 4 and msgs[0]["text"].startswith("請把")
              and msgs[-1]["text"].startswith("<pasted_content"),
              f"head/tail trimming wrong: {[m['text'][:12] for m in msgs]}")

        # ---- Markdown 輸出
        cmd = [sys.executable, str(script), "--claude-home", str(homes["claude"]),
               "--codex-home", str(homes["codex"]), "--cursor-home", str(homes["cursor"]),
               "--project", str(proj), "--source", "claude"]
        r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
        check(r.returncode == 0, f"markdown run failed: {r.stderr.strip()}")
        check(f"## [claude] {main_id} — Neovim completion 改用 blink" in r.stdout,
              "markdown heading must carry source, id and title")
        check("### 使用者訊息" in r.stdout and "1. [2026-09-20T01:00:00.000Z] 請把 neovim" in r.stdout,
              "markdown must number user messages with timestamps")
        check("<command-name>" not in r.stdout and "system-reminder" not in r.stdout,
              "markdown output leaked injected text")

        # ---- 來源目錄不存在：不是錯誤，只是空結果
        empty = {k: tmp / "nowhere" / k for k in homes}
        data = run(script, empty, "--all")
        check(data["sessions"] == [], "missing source directories must yield an empty list, not an error")

    print(f"OK: {CHECKS} checks hold")


if __name__ == "__main__":
    main()
