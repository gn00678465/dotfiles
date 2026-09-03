#!/usr/bin/env python3
"""Archive a shipped spec — the mechanical executor of evidence-first Phase 6.

    spec-archive.py <scope>   flip status to `shipped`, move
                              specs/<scope>/ to specs/archive/<scope>/,
                              commit — one atomic act
    spec-archive.py --check   list approved specs still in the active
                              directory (a CLOSE not done yet); fail on a
                              shipped spec that never moved, and on the
                              default branch on any approved spec

Fail closed. Exit codes: 0 done / nothing pending; 1 refused (not
approved, dirty tree, already archived, shipped-but-not-moved); 2 the
script could not even evaluate (not a git repo, no spec, unparseable
status, git command failed). Stdlib only; runs anywhere python3 does.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

STATUS_RE = re.compile(r"^(\s*-\s*`status`:\s*)([A-Za-z-]+)\b", re.MULTILINE)


def die(code: int, msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    except OSError as e:
        die(2, f"cannot execute {args[0]}: {e}")


def repo_root() -> Path:
    r = run(["git", "rev-parse", "--show-toplevel"])
    if r.returncode != 0:
        die(2, "not inside a git repository")
    return Path(r.stdout.strip())


def read_status(spec: Path) -> tuple[str, str]:
    try:
        text = spec.read_text(encoding="utf-8")
    except OSError as e:
        die(2, f"cannot read {spec}: {e}")
    m = STATUS_RE.search(text)
    if m is None:
        die(2, f"cannot parse the `status` line in {spec}")
    return text, m.group(2)


def archive(root: Path, scope: str) -> None:
    src = root / "specs" / scope
    dst = root / "specs" / "archive" / scope
    spec = src / "SPEC.md"
    if dst.exists():
        die(1, f"already archived: {dst.relative_to(root)}")
    if not spec.is_file():
        die(2, f"no spec at {spec.relative_to(root)}")

    text, status = read_status(spec)
    if status == "shipped":
        die(1, "status is already `shipped`; a spec ships once")
    if status != "approved":
        die(1, f"status is `{status}`, not `approved` — an unapproved spec does not ship")

    porcelain = run(["git", "status", "--porcelain"], cwd=root)
    if porcelain.returncode != 0:
        die(2, f"git status failed: {porcelain.stderr.strip()}")
    if porcelain.stdout.strip():
        die(1, "working tree not clean — archiving must be one atomic commit")

    # All checks passed; mutate. The status flip is the spec's one final
    # mutation — after this commit the file is an immutable intent record.
    spec.write_text(STATUS_RE.sub(lambda m: m.group(1) + "shipped", text, count=1),
                    encoding="utf-8")
    dst.parent.mkdir(parents=True, exist_ok=True)
    for cmd in (
        ["git", "add", str(spec)],
        ["git", "mv", str(src), str(dst)],
        ["git", "commit", "-m", f"chore(spec): archive {scope}"],
    ):
        r = run(cmd, cwd=root)
        if r.returncode != 0:
            die(2, f"`{' '.join(cmd[:2])}` failed: {(r.stderr or r.stdout).strip()}")
    print(f"archived: specs/archive/{scope}/ (status: shipped)")


def on_default_branch(root: Path) -> bool:
    # origin/HEAD names the default branch once a remote exists; a local-only
    # repo has none, and `main` is the convention this contract assumes.
    head = run(["git", "symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD"], cwd=root)
    default = head.stdout.strip().split("/", 1)[-1] if head.returncode == 0 else "main"
    cur = run(["git", "branch", "--show-current"], cwd=root)
    return cur.returncode == 0 and cur.stdout.strip() == default


def check(root: Path) -> None:
    specs_dir = root / "specs"
    violations = 0
    pending: list[Path] = []
    for spec in sorted(specs_dir.glob("*/SPEC.md")) if specs_dir.is_dir() else []:
        if spec.parent.name == "archive":
            continue
        _, status = read_status(spec)
        if status == "shipped":
            print(f"VIOLATION: `shipped` but still in the active directory: "
                  f"{spec.relative_to(root)}")
            violations += 1
        elif status == "approved":
            pending.append(spec)
    for p in pending:
        print(f"candidate: {p.relative_to(root)} (approved — archive before merging)")
    if pending and on_default_branch(root):
        # The close belongs to the branch that shipped the change; an approved
        # spec that reached the default branch skipped it.
        print("VIOLATION: approved spec on the default branch — close was skipped")
        violations += len(pending)
    if not pending and violations == 0:
        print("check: nothing pending")
    sys.exit(1 if violations else 0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("scope", nargs="?", help="feature slug under specs/")
    parser.add_argument("--check", action="store_true",
                        help="list forgotten closes instead of archiving")
    args = parser.parse_args()
    if args.check == bool(args.scope):
        parser.error("exactly one of <scope> or --check is required")
    root = repo_root()
    if args.check:
        check(root)
    else:
        archive(root, args.scope)


if __name__ == "__main__":
    main()
