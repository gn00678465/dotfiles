#!/usr/bin/env python3
"""Changed-line accounting for the verification gate.

There is no coverage instrument for this repo's languages: chezmoi Go templates,
POSIX/zsh shell and PowerShell all run without one here. So this script does NOT
gate on coverage -- it reports the three sets the evidence report has to keep
apart, so the reader can see exactly how large the uninstrumented region is:

  set 1  executable and instrumented    (always 0 here -- no instrument exists)
  set 2  not executable                 comments, blanks, delimiters
  set 3  executable, no coverage mapping

Every ambiguous line resolves into set 3, never set 2. Guessing "not executable"
hides a hole in the instrument; guessing "unmapped" only costs a line of
explanation. Set 3 being the whole of set 1+3 is the honest description of a
project with no coverage tool, and the evidence report records the coverage
layer as UNAVAILABLE rather than pretending otherwise.

Usage: tools/gate-changed-lines.py --base <ref>
Exit:  0 always for the accounting itself; 1 only if the diff cannot be read.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# 明顯不可執行的行。只列真的沒有疑義的：註解、空白、單獨的界定符。
# 任何其他東西都留在 set 3。
COMMENT_PREFIXES = ("#", "//", "--", "<#", "#>", ".SYNOPSIS", ".DESCRIPTION",
                    ".EXAMPLE", ".NOTES", ".PARAMETER")
DELIMITERS = {"{", "}", "(", ")", ")}", "}}", "]", "[", ");", "'@", "@'", "@(", "))"}

# 純資料／文件檔：整個檔案沒有可執行的行。
#
# .json **不在**這裡：chezmoi 的 modify-template 不能有 .tmpl 後綴，所以
# dot_claude/modify_settings.json 副檔名是 .json、內容卻是模板程式碼。
# 把整類 .json 當資料，等於把六行會被求值的模板 action 記進「不可執行」，
# 那正是這個腳本自己的政策禁止的方向（有疑義一律進 set 3）。
DATA_SUFFIXES = {".md", ".txt", ".tsv"}


def classify(path: str, line: str) -> str:
    stripped = line.strip()
    if not stripped:
        return "set2"
    if Path(path).suffix in DATA_SUFFIXES:
        return "set2"
    if stripped.startswith(COMMENT_PREFIXES):
        return "set2"
    if stripped in DELIMITERS:
        return "set2"
    # chezmoi 模板裡「整行只有一個註解 action」也算不可執行
    if stripped.startswith("{{- /*") or stripped.startswith("{{/*"):
        return "set2"
    return "set3"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    args = ap.parse_args()

    p = subprocess.run(
        ["git", "diff", "--unified=0", f"{args.base}...HEAD"],
        cwd=REPO, capture_output=True, text=True,
    )
    if p.returncode != 0:
        print(f"gate-changed-lines: 讀不到 diff: {p.stderr}", file=sys.stderr)
        return 1

    counts: dict[str, int] = defaultdict(int)
    per_file: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    current = ""
    for line in p.stdout.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
            continue
        if line.startswith("+") and not line.startswith("+++"):
            bucket = classify(current, line[1:])
            counts[bucket] += 1
            per_file[current][bucket] += 1

    # evidence report 自己也在 diff 裡，所以「含它」的總數每改一次報告就變。
    # 另外算一份不含 .scratch/ 的，報告引用那一份才會穩定。
    prod = {"set2": 0, "set3": 0}
    for f, c in per_file.items():
        if f.startswith(".scratch/"):
            continue
        prod["set2"] += c["set2"]
        prod["set3"] += c["set3"]

    total = counts["set2"] + counts["set3"]
    print(f"changed-line accounting vs {args.base}")
    print(f"  set 1  executable + instrumented : {counts['set1']}")
    print(f"  set 2  not executable            : {counts['set2']}")
    print(f"  set 3  executable, NO mapping    : {counts['set3']}")
    print(f"  total added lines                : {total}")
    print()
    print(f"  不含 .scratch/（evidence report 本身）的產品/測試數字："
          f"set2={prod['set2']} set3={prod['set3']} total={prod['set2'] + prod['set3']}")
    print()
    print("  set 3 是全部 —— 這個 repo 的三種語言（chezmoi Go template、"
          "POSIX/zsh shell、PowerShell）在這個環境裡都沒有覆蓋率工具。")
    print("  evidence report 因此把 coverage 那一層記成 UNAVAILABLE，"
          "改用 Table 1 的逐單元對應與 mutation 兩層去補。")
    print()
    for f in sorted(per_file):
        c = per_file[f]
        print(f"  {c['set3']:4d} set3  {c['set2']:4d} set2  {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
