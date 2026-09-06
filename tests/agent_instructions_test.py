#!/usr/bin/env python3
"""Cross-platform render checks for the shared global-agent-instructions template.

`.chezmoitemplates/agent-instructions.md` (plus the evidence-first contract it
includes) is the single source for both `~/.claude/CLAUDE.md` and
`~/.codex/AGENTS.md`. SPEC `global-agent-instructions` S1 requires: the two
entry points render identically per platform, the contract appears exactly
once, and the rendered word count stays at or under the stated budget so the
persistent instructions stay readable.

This is a home-grown check, so it carries its own negative control: it proves
its word-counting function actually flags an over-budget input before trusting
it on the real render.

Fail closed. Exit codes: 0 all checks hold; 1 a check failed; 2 the check
itself broke (chezmoi missing, a fixture or entry point missing, chezmoi
itself errored). Stdlib only.

Usage: tests/agent_instructions_test.py [repo-root]
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

WORD_LIMIT = 600
FIXTURES = ("os-linux.toml", "os-darwin-amd64.toml", "os-windows.toml")
ENTRY_POINTS = ("dot_claude/CLAUDE.md.tmpl", "dot_codex/AGENTS.md.tmpl")
CONTRACT_MARKER = "<!-- evidence-first:contract -->"

CHECKS = 0


def die(code: int, msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def word_count(text: str) -> int:
    return len(text.split())


def render(chezmoi: str, root: Path, fixture: str, rel_path: str, tmp: Path) -> str:
    cfg = root / "tests" / "fixtures" / fixture
    if not cfg.is_file():
        die(2, f"missing fixture: {cfg}")
    src = root / rel_path
    if not src.is_file():
        die(2, f"missing entry point: {src}")
    dest = tmp / fixture / rel_path.replace("/", "_") / "dest"
    dest.mkdir(parents=True, exist_ok=True)
    state = dest.parent / "state.boltdb"
    with src.open("rb") as f:
        r = subprocess.run(
            [chezmoi, "--source", str(root), "--config", str(cfg),
             "--destination", str(dest), "--persistent-state", str(state),
             "--no-tty", "execute-template"],
            stdin=f, capture_output=True, text=True, encoding="utf-8",
        )
    if r.returncode != 0:
        die(2, f"chezmoi execute-template failed for {rel_path} ({fixture}): {r.stderr.strip()}")
    return r.stdout


def main() -> None:
    global CHECKS
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent.parent

    chezmoi = shutil.which("chezmoi")
    if chezmoi is None:
        die(2, "chezmoi not found on PATH")

    # 負向控制：先證明 word_count 真的會抓到超過上限的輸入，才信任它套在真正
    # 算繪出來的內容上——不然「沒超過上限」跟「這個函式從來沒抓過任何東西」
    # 看起來一模一樣。
    if word_count(" ".join(["x"] * (WORD_LIMIT + 1))) <= WORD_LIMIT:
        die(2, "negative control failed: word_count did not flag an over-budget synthetic input")
    CHECKS += 1

    with tempfile.TemporaryDirectory(prefix="agent-instructions-test-") as tmp_s:
        tmp = Path(tmp_s)
        for fixture in FIXTURES:
            rendered: dict[str, str] = {}
            for ep in ENTRY_POINTS:
                text = render(chezmoi, root, fixture, ep, tmp)
                rendered[ep] = text

                n = word_count(text)
                if n > WORD_LIMIT:
                    die(1, f"{ep} rendered under {fixture} is {n} words, "
                           f"over the {WORD_LIMIT}-word ceiling")
                CHECKS += 1

                marker_count = text.count(CONTRACT_MARKER)
                if marker_count != 1:
                    die(1, f"{ep} rendered under {fixture} carries the contract "
                           f"{marker_count} times, expected exactly 1")
                CHECKS += 1

            claude_text, codex_text = (rendered[ep] for ep in ENTRY_POINTS)
            if claude_text != codex_text:
                die(1, f"Claude and Codex entry points diverge under {fixture} "
                       "even though both are supposed to share one template")
            CHECKS += 1

    print(f"OK: {CHECKS} checks hold")


if __name__ == "__main__":
    main()
