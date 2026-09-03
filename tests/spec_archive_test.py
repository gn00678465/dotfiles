#!/usr/bin/env python3
"""Negative controls and happy path for the spec-archive skill's script.

Builds a throwaway git repo in a temp directory and asserts the exit-code
semantics the SKILL.md promises: refusals are rc 1, "cannot evaluate" is
rc 2, and the happy path is one atomic commit that flips status and moves
the spec. Every control feeds a known-bad state and expects red — a
checker is only trusted after it has been seen to fail.

Exit codes: 0 all assertions hold; 1 an assertion failed; 2 the harness
itself broke (git unavailable, temp repo setup failed). Stdlib only.
Usage: tests/spec_archive_test.py
Override the script under test with SPEC_ARCHIVE_UNDER_TEST (used by this
suite's own negative control — pointing it at a stub must go red).
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ARCHIVER = Path(os.environ.get(
    "SPEC_ARCHIVE_UNDER_TEST",
    Path(__file__).resolve().parent.parent
    / "dot_agents/skills/spec-archive/scripts/spec-archive.py",
))

FAILURES = 0
PASSES = 0


def harness(args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    except OSError as e:
        print(f"FAIL: harness cannot execute {args[0]} ({e})", file=sys.stderr)
        sys.exit(2)


def git(repo: Path, *args: str) -> None:
    r = harness(["git", *args], repo)
    if r.returncode != 0:
        print(f"FAIL: harness git {' '.join(args)} failed: {r.stderr.strip()}",
              file=sys.stderr)
        sys.exit(2)


def expect(desc: str, repo: Path, args: list[str], rc: int,
           stdout_has: str | None = None) -> subprocess.CompletedProcess:
    global FAILURES, PASSES
    r = harness([sys.executable, str(ARCHIVER), *args], repo)
    ok = r.returncode == rc and (stdout_has is None or stdout_has in r.stdout)
    if ok:
        PASSES += 1
        print(f"ok: {desc} (rc={r.returncode})")
    else:
        FAILURES += 1
        print(f"FAIL: {desc} — expected rc {rc}"
              + (f" and stdout containing '{stdout_has}'" if stdout_has else "")
              + f", got rc {r.returncode}\n  stdout: {r.stdout.strip()}"
              + f"\n  stderr: {r.stderr.strip()}", file=sys.stderr)
    return r


def check(desc: str, condition: bool) -> None:
    global FAILURES, PASSES
    if condition:
        PASSES += 1
        print(f"ok: {desc}")
    else:
        FAILURES += 1
        print(f"FAIL: {desc}", file=sys.stderr)


def main() -> None:
    if not ARCHIVER.is_file():
        print(f"FAIL: harness — no script at {ARCHIVER}", file=sys.stderr)
        sys.exit(2)

    with tempfile.TemporaryDirectory(prefix="spec-archive-test-") as tmp:
        repo = Path(tmp)
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "user.email", "test@test")
        git(repo, "config", "user.name", "test")

        spec = repo / "specs/foo/SPEC.md"
        spec.parent.mkdir(parents=True)
        spec.write_text("- `status`: draft\n\n## Approval\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "init")

        # Refusals (rc 1) and cannot-evaluate (rc 2), each a known-bad state.
        expect("unapproved spec is refused", repo, ["foo"], 1)
        spec.write_text(spec.read_text(encoding="utf-8")
                        .replace("draft", "approved"), encoding="utf-8")
        expect("dirty tree is refused", repo, ["foo"], 1)
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "approve")
        expect("missing spec cannot be evaluated", repo, ["bar"], 2)
        expect("--check on the default branch fails on an approved candidate",
               repo, ["--check"], 1, stdout_has="VIOLATION")
        git(repo, "checkout", "-q", "-b", "feat")
        expect("--check on a feature branch lists the candidate and passes",
               repo, ["--check"], 0, stdout_has="candidate")

        # Happy path: one atomic commit, status flipped, spec moved.
        expect("approved spec on a clean tree archives", repo, ["foo"], 0,
               stdout_has="archived")
        moved = repo / "specs/archive/foo/SPEC.md"
        check("spec moved to specs/archive/", moved.is_file())
        check("status flipped to shipped",
              "- `status`: shipped" in moved.read_text(encoding="utf-8"))
        log = harness(["git", "log", "--oneline", "-1"], repo)
        check("archive is one commit with the fixed message",
              "chore(spec): archive foo" in log.stdout)
        porcelain = harness(["git", "status", "--porcelain"], repo)
        check("tree is clean after archiving", porcelain.stdout.strip() == "")

        # Terminal-state refusals after the fact.
        expect("re-archiving is refused", repo, ["foo"], 1)
        baz = repo / "specs/baz/SPEC.md"
        baz.parent.mkdir(parents=True)
        baz.write_text("- `status`: shipped\n", encoding="utf-8")
        expect("--check goes red on shipped-but-not-moved", repo, ["--check"], 1,
               stdout_has="VIOLATION")

    if FAILURES:
        print(f"FAIL: {FAILURES} of {FAILURES + PASSES} assertions failed",
              file=sys.stderr)
        sys.exit(1)
    print(f"OK: {PASSES} assertions hold")


if __name__ == "__main__":
    main()
