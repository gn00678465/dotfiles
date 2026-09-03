#!/usr/bin/env python3
"""Property-based tests for the ~/.codex/config.toml modify-template.

The L6 goldens pin ten hand-picked shapes. These properties cover the shapes
nobody thought of: the template is a line-oriented rewriter over arbitrary
user-authored TOML, and the Tier 3 risk (SPEC M4) is that some input shape makes
it corrupt a file it was only supposed to add two keys to.

Properties checked on every generated input:

  P0 differential     byte-for-byte identical to the sh+awk original at the base
                      ref. SPEC 2.6 demands identity, so this is the property that
                      actually states the porting contract; P1-P5 stay because
                      they still hold when the original eventually goes away.
  P1 idempotence      applying to the output again changes nothing
  P2 preservation     every line outside [tui] survives byte-identically, in order
  P3 exactly-once     exactly one status_line and one status_line_use_colors,
                      and both inside [tui]
  P4 TOML validity    if the input parsed, the output parses -- **scoped**: only
                      for inputs that meet the rewriter's documented assumption
                      that every managed key sits on one line, written as a bare
                      key, in a table declared as a plain [tui] header. The shapes
                      in KNOWN_LIMITATION below break that and turn valid TOML into
                      invalid TOML. **That list is the shapes we know about, not a
                      proof that there are no others** -- a fifth was found by
                      independent verification after the first four were written up
                      as if exhaustive. They are checked for P0 only. They are byte-identical
                      to the sh+awk original, i.e. inherited, not introduced.
  P5 managed values   the two managed keys hold exactly the values we manage

Runs several seeds, not one. A single hard-coded seed made this layer green by
luck once already: the generator finds a crashing shape at seeds 2, 3 and 4 but
not at 1, 5, 6 or 20260902.

P2 is deliberately implemented here from the property statement rather than
borrowed from the template -- a checker that shares the implementation's idea of
"inside [tui]" would agree with it about a bug.

Usage: tools/gate-properties.py [--cases N] [--seeds "S1 S2 ..."] [--base REF]
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


ADVERSARIAL = [
    "",                       # 空檔
    "\n",                     # 只有一個空行
    "[tui]\n",                # 空的 [tui]（曾經讓模板 nil pointer）
    "[tui]",                  # 空的 [tui]，且沒有結尾換行
    "[tui]\n[other]\nz = 1\n",
    "[tui]\n[tui.sub]\nx = 1\n",
    "[tui]\n   \n",
    "[tui]\nstatus_line = [\"X\"]\n   \n",
    "   [ tui ]\nstatus_line = [\"X\"]\n",
    "[other]\nz = 1\n",
    "# only a comment\n",
    "[tui]\n\n\n[other]\nz = 1\n",
]


# 這些形狀會讓「受管的 key 各佔一行、是 bare key、表頭是單純的 [tui]」這個前提失效，
# 於是合法的 TOML 進去、
# 不合法的 TOML 出來。它們與 base ref 的 awk 原版**逐位元組相同**，也就是說這是
# 沿用下來的既有缺陷而不是這次移植引入的，修掉它會改變 POSIX 端的行為
# （SPEC Must NOT #2 禁止）。這裡仍然把它們放進測試，但只驗 P0：
# 一旦哪天輸出與 awk 不一致了，那就是真的回歸，必須被抓到。
#
# **這份清單是「目前已知的」，不是「窮舉的」**：第五種是獨立驗證在前四種已經被
# 當成完整清單寫進文件之後才找到的。
KNOWN_LIMITATION = [
    # 受管的 status_line 本身就是一個 8 元素陣列；任何把它換行排版的工具或人
    # 都會踩到這一個。這是四種裡最容易發生的。
    '[tui]\nstatus_line = [\n  "a",\n  "b",\n]\nkeep = 1\n',
    "[[tui]]\nx = 1\n",          # array of tables
    '["tui"]\nkeep = 1\n',       # 加引號的表頭
    'tui = { status_line = "X" }\n',  # inline table
    '[tui]\n"status_line" = "X"\nkeep = 1\n',  # 加引號的 key（獨立驗證第三輪找到的第五種）
]


def apply_once(content: str, workdir: Path, n: int, source: Path = REPO) -> str:
    dest = workdir / f"d{n}"
    (dest / ".codex").mkdir(parents=True, exist_ok=True)
    (dest / ".codex" / "config.toml").write_text(content, encoding="utf-8")
    proc = subprocess.run(
        [
            "chezmoi",
            "--source", str(source),
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
    if text == "":
        # Python 的 "".split("\n") 給 [""]，會讓「空檔」憑空多出一行要保留。
        return out
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
    ap.add_argument("--cases", type=int, default=60)
    ap.add_argument("--seeds", type=str, default="1 2 3 4 5 6 20260902")
    ap.add_argument("--base", type=str, default=None,
                    help="base ref；它的來源樹會被解出來做 P0 差分比對")
    ap.add_argument("--base-src", type=Path, default=None,
                    help="已經解好的 base 來源樹目錄（給不在 git repo 裡跑的情形，例如 negative control）")
    args = ap.parse_args()

    workdir = Path(tempfile.mkdtemp(prefix="gate-props-"))
    base_src: Path | None = args.base_src
    if args.base and not base_src:
        base_src = workdir / "base"
        base_src.mkdir()
        rc = subprocess.run(
            f"git -C {REPO} archive {args.base} | tar -x -C {base_src}",
            shell=True, capture_output=True, text=True,
        )
        if rc.returncode != 0:
            print(f"gate-properties: 取不出 base ref {args.base}: {rc.stderr}", file=sys.stderr)
            return 1

    seeds = [int(x) for x in args.seeds.split()]
    violations = 0
    checked = 0
    try:
        n = 0
        for seed in seeds:
            rng = random.Random(seed)
            inputs = ([(i, False) for i in ADVERSARIAL]
                      + [(i, True) for i in KNOWN_LIMITATION]
                      + [(generate(rng), False) for _ in range(args.cases)])
            for inp, p0_only in inputs:
                n += 1
                checked += 1
                try:
                    out1 = apply_once(inp, workdir, n)
                    out2 = apply_once(out1, workdir, n + 1000000)
                    base_out = apply_once(inp, workdir, n + 2000000, base_src) if base_src else None
                except RuntimeError as e:
                    print(f"seed {seed} case {n}: runner failure: {e}", file=sys.stderr)
                    print(f"--- input ---\n{inp!r}", file=sys.stderr)
                    return 1

                problems = [] if p0_only else check(inp, out1)
                if out2 != out1 and not p0_only:
                    problems.append("P1 idempotence: 第二次套用改變了內容")
                if base_out is not None and base_out != out1:
                    problems.append(
                        "P0 differential: 與 base ref 的 awk 原版輸出不同\n"
                        f"      awk : {base_out!r}\n"
                        f"      新版: {out1!r}"
                    )

                if problems:
                    violations += 1
                    print(f"seed {seed} case {n} 違反:", file=sys.stderr)
                    for p in problems:
                        print(f"  - {p}", file=sys.stderr)
                    print(f"--- input ---\n{inp!r}", file=sys.stderr)
                    if violations >= 3:
                        break
            if violations >= 3:
                break
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    if violations:
        print(f"gate-properties: {violations} 個案例違反性質", file=sys.stderr)
        return 1
    diff = "P0-P5" if base_src else "P1-P5（沒給 --base，未做差分）"
    print(f"gate-properties: {len(seeds)} 個 seed x ({args.cases} 生成 + "
          f"{len(ADVERSARIAL)} 固定敵意輸入 + {len(KNOWN_LIMITATION)} 已知限制形狀，非窮舉) "
          f"= {checked} 個案例，{diff} 全部成立")
    print(f"  已知限制的 {len(KNOWN_LIMITATION)} 種形狀只驗 P0（與 awk 原版逐位元組相同）；"
          "它們會讓合法 TOML 變成不合法，是沿用自原實作的缺陷，見 evidence report")
    print(f"  seeds: {' '.join(str(x) for x in seeds)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
