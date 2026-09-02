#!/usr/bin/env python3
"""Property-based tests for the ~/.codex/config.toml modify-template.

The L6 goldens pin ten hand-picked shapes. These properties cover the shapes
nobody thought of: the template is a line-oriented rewriter over arbitrary
user-authored TOML, and the Tier 3 risk (SPEC M4) is that some input shape makes
it corrupt a file it was only supposed to add two keys to.

Properties checked on every generated input:

  P1 idempotence      applying to the output again changes nothing
  P2 preservation     every line outside [tui] survives byte-identically, in order
  P3 exactly-once     exactly one status_line and one status_line_use_colors,
                      and both inside [tui]
  P4 TOML validity    if the input parsed, the output parses
  P5 managed values   the two managed keys hold exactly the values we manage

P2 is deliberately implemented here from the property statement rather than
borrowed from the template -- a checker that shares the implementation's idea of
"inside [tui]" would agree with it about a bug.

Usage: tools/gate-properties.py [--cases N] [--seed S]
Exit:  0 all properties held, 1 any violation or any runner failure.
"""

from __future__ import annotations

import argparse
import random
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "tests" / "fixtures" / "native.toml"

MANAGED_KEYS = ("status_line", "status_line_use_colors")

TABLE_NAMES = [
    "tui",
    "mcp_servers.foo",
    "mcp_servers.bar-baz",
    "profiles.work",
    "history",
    "sandbox",
]
KEY_NAMES = ["model", "approval_policy", "verbose", "retries", "keep_me", "x"]
VALUES = ['"gpt-5"', '"on-request"', "true", "false", "42", '["a", "b"]', "0.5"]
COMMENTS = [
    "# my codex config",
    "# 中文註解也要活下來",
    "#",
    "#     indented-ish comment",
]


def generate(rng: random.Random) -> str:
    lines: list[str] = []

    for _ in range(rng.randint(0, 3)):
        lines.append(rng.choice(COMMENTS) if rng.random() < 0.5 else "")
    # top-level（第一個表頭之前）的 key
    for _ in range(rng.randint(0, 3)):
        lines.append(f"{rng.choice(KEY_NAMES)} = {rng.choice(VALUES)}")

    tables = rng.sample(TABLE_NAMES, rng.randint(0, len(TABLE_NAMES)))
    for name in tables:
        if lines and rng.random() < 0.7:
            lines.append("")
        # 表頭本身的空白排版也要能被正確辨識
        pad = " " * rng.randint(0, 2)
        lines.append(f"{pad}[{pad}{name}{pad}]")
        if rng.random() < 0.4:
            lines.append(rng.choice(COMMENTS))

        used: set[str] = set()
        for _ in range(rng.randint(0, 4)):
            k = rng.choice(KEY_NAMES)
            if k in used:
                continue
            used.add(k)
            lines.append(f"{k} = {rng.choice(VALUES)}")

        if name == "tui":
            # [tui] 裡有時候已經有受管的 key（值是錯的），有時候沒有
            for mk in MANAGED_KEYS:
                r = rng.random()
                if r < 0.45:
                    lines.append(f'{mk} = "STALE"' if mk == MANAGED_KEYS[0] else f"{mk} = false")
                elif r < 0.55:
                    # 故意重複一次
                    lines.append(f'{mk} = "STALE-1"' if mk == MANAGED_KEYS[0] else f"{mk} = false")
                    lines.append(f'{mk} = "STALE-2"' if mk == MANAGED_KEYS[0] else f"{mk} = true")
            if rng.random() < 0.3:
                lines.append("")

    text = "\n".join(lines)
    if text and rng.random() < 0.85:
        text += "\n"
    return text


def apply_once(content: str, workdir: Path, n: int) -> str:
    dest = workdir / f"d{n}"
    (dest / ".codex").mkdir(parents=True, exist_ok=True)
    (dest / ".codex" / "config.toml").write_text(content, encoding="utf-8")
    proc = subprocess.run(
        [
            "chezmoi",
            "--source", str(REPO),
            "--config", str(CONFIG),
            "--destination", str(dest),
            "--persistent-state", str(workdir / f"s{n}.boltdb"),
            "--no-tty",
            "apply", "--exclude=scripts,externals",
        ],
        capture_output=True, text=True,
    )
    noise = [
        line for line in (proc.stderr or "").splitlines()
        if line and "config file template has changed" not in line
    ]
    if proc.returncode != 0 or noise:
        raise RuntimeError(f"chezmoi apply failed: {proc.returncode} {noise}")
    return (dest / ".codex" / "config.toml").read_text(encoding="utf-8")


def outside_tui(text: str) -> list[str]:
    """輸入中不屬於 [tui] 區塊的行，照原順序。

    規則刻意寫得跟模板無關：遇到任何 `[...]` 表頭就重新判斷目前在哪個 table，
    表頭本身永遠算「外面」（它要被原樣保留）。
    """
    out: list[str] = []
    in_tui = False
    for line in text.split("\n"):
        stripped = line.lstrip(" \t")
        if stripped.startswith("["):
            name = stripped[1:].split("]")[0].strip(" \t")
            in_tui = name == "tui"
            out.append(line)
        elif not in_tui:
            out.append(line)
    return out


def managed_lines(text: str) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {k: [] for k in MANAGED_KEYS}
    in_tui = False
    for line in text.split("\n"):
        stripped = line.lstrip(" \t")
        if stripped.startswith("["):
            in_tui = stripped[1:].split("]")[0].strip(" \t") == "tui"
            continue
        key = stripped.split("=")[0].strip(" \t")
        if key in found and in_tui:
            found[key].append(line)
    return found


def check(inp: str, out: str) -> list[str]:
    problems: list[str] = []

    # P2 preservation
    want = outside_tui(inp)
    got = outside_tui(out)
    # 輸出可能在檔尾多出一個 [tui] 區塊；那個區塊的表頭會出現在 got 裡。
    # 比對方式：want 必須是 got 的子序列，且順序一致。
    it = iter(got)
    missing = [line for line in want if not any(line == g for g in it)]
    if missing:
        problems.append(f"P2 preservation: 這些 [tui] 以外的行不見了或順序變了: {missing[:3]}")

    # P3 exactly-once, inside [tui]
    ml = managed_lines(out)
    for k, occurrences in ml.items():
        if len(occurrences) != 1:
            problems.append(f"P3 exactly-once: {k} 在 [tui] 內出現 {len(occurrences)} 次")

    # P5 managed values
    if ml["status_line_use_colors"] and ml["status_line_use_colors"][0].strip() != "status_line_use_colors = true":
        problems.append(f"P5 managed value: {ml['status_line_use_colors'][0]!r}")
    if ml["status_line"] and not ml["status_line"].__getitem__(0).startswith('status_line = ["model-with-reasoning"'):
        problems.append(f"P5 managed value: {ml['status_line'][0]!r}")

    # P4 TOML validity
    try:
        tomllib.loads(inp)
    except tomllib.TOMLDecodeError:
        pass  # 輸入本來就不是合法 TOML，不要求輸出是
    else:
        try:
            parsed = tomllib.loads(out)
        except tomllib.TOMLDecodeError as e:
            problems.append(f"P4 validity: 輸入是合法 TOML，輸出不是: {e}")
        else:
            tui = parsed.get("tui", {})
            if tui.get("status_line_use_colors") is not True:
                problems.append("P4/P5: 解析後 tui.status_line_use_colors 不是 true")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=120)
    ap.add_argument("--seed", type=int, default=20260902)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    workdir = Path(tempfile.mkdtemp(prefix="gate-props-"))
    violations = 0
    try:
        for n in range(args.cases):
            inp = generate(rng)
            try:
                out1 = apply_once(inp, workdir, n)
                out2 = apply_once(out1, workdir, n + 100000)
            except RuntimeError as e:
                print(f"case {n}: runner failure: {e}", file=sys.stderr)
                print(f"--- input ---\n{inp}", file=sys.stderr)
                return 1

            problems = check(inp, out1)
            if out2 != out1:
                problems.append("P1 idempotence: 第二次套用改變了內容")

            if problems:
                violations += 1
                print(f"case {n} (seed={args.seed}) 違反:", file=sys.stderr)
                for p in problems:
                    print(f"  - {p}", file=sys.stderr)
                print(f"--- input ---\n{inp}\n--- output ---\n{out1}", file=sys.stderr)
                if violations >= 3:
                    break
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    if violations:
        print(f"gate-properties: {violations} 個案例違反性質", file=sys.stderr)
        return 1
    print(f"gate-properties: {args.cases} 個生成案例，P1-P5 全部成立 (seed={args.seed})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
