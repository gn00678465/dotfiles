#!/usr/bin/env python3
"""Archive a shipped spec — the mechanical executor of evidence-first Phase 6.

    spec-archive.py <scope>   flip status to `shipped`, move
                              specs/<scope>/ to specs/archive/<scope>/,
                              commit — one atomic act
    spec-archive.py --check   list approved specs still in the active
                              directory (a CLOSE not done yet); fail on a
                              shipped spec that never moved, and on the
                              default branch on any approved spec

CLOSE also reads the gate's evidence report from git: it must be committed
at `.scratch/<scope>/evidence.md` or `.gate/<scope>/evidence.md`, and its
header must carry `spec_version: vN` equal to the spec's own — the report
was produced against this spec version, or it is not this change's
evidence.

CLOSE also reads, beside that report, `verification.md` when Phase 5 ran:
a `final_verdict` of `failed` or `blocked` does not ship. At tier 2 and 3
it reads the three squad records `.scratch/<scope>/squad/<cut>.md`
(`after-spec`, `after-implement`, `before-archive`): each committed, every
finding bullet carrying `class 1|2|3`, no class-1 finding without
`status: fixed`, `after-spec` last committed no later than the approval
commit and `after-implement` no later than the evidence report.

Fail closed. Exit codes: 0 done / nothing pending; 1 refused (not
approved, dirty tree, already archived, shipped-but-not-moved, evidence
missing / uncommitted / bound to another spec_version, verdict failed or
blocked, squad record missing / uncommitted / unclassed / out of order);
2 the script could not even evaluate (not a git repo, no spec, unparseable
status, spec_version, tier or final_verdict, git command failed). Stdlib
only; runs anywhere python3 does.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

STATUS_RE = re.compile(r"^(\s*-\s*`status`:\s*)([A-Za-z-]+)\b", re.MULTILINE)
# Pre-approval drafts are `v0.1`, `v0.2` (evidence-first Phase 1), so a version
# is not always an integer. Matching only the integer broke both regexes below,
# differently, and both failures were reachable:
#   * this one truncated `v0.2` to `v0`. `gate-intent.sh` truncated the same
#     way, so an evidence header quoting `spec_version: v0` against a `v0.2`
#     spec compared equal and CLOSE archived it — a false match, exit 0.
#   * the evidence one wanted the integer immediately before the closing
#     backtick, so a header that kept the dots matched nothing and CLOSE exited
#     2 — unusable rather than wrong.
# Which one you hit depended on whether the header had already been truncated
# upstream. Neither is acceptable, and only comparing whole versions avoids both.
SPEC_VERSION_RE = re.compile(r"^\s*-\s*`spec_version`:\s*(v\d+(?:\.\d+)*)\b",
                             re.MULTILINE)
# The evidence header quotes the version it was produced against as
# `spec_version: vN` (the gate's intent layer prints it in that form).
EVIDENCE_VERSION_RE = re.compile(r"`spec_version:\s*(v\d+(?:\.\d+)*)`")
EVIDENCE_CANDIDATES = (".scratch/{scope}/evidence.md", ".gate/{scope}/evidence.md")
TIER_RE = re.compile(r"^\s*-\s*`tier`:\s*([123])\b", re.MULTILINE)
VERDICT_RE = re.compile(r"^\s*-\s*`final_verdict`:\s*(passed|failed|blocked|not performed)\b",
                        re.MULTILINE)
SQUAD_CUTS = ("after-spec", "after-implement", "before-archive")
SQUAD_PATH = ".scratch/{scope}/squad/{cut}.md"
# A squad finding is a bullet that opens with its severity: `- [HIGH] ...`.
FINDING_RE = re.compile(r"^\s*-\s*\[")
CLASS_RE = re.compile(r"\bclass\s*([123])\b")
FIXED_RE = re.compile(r"\bstatus:\s*fixed\b")


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


# --- Approval records (SPEC spec-version-bump §2) ---------------------------
# Two record shapes are load-bearing in this repo and both must parse: the
# template's list form, and the sectioned form `windows-support` uses. Three
# real-world traps decide the shape of this code — a numbered heading
# (`## 8. Approval record`), records that are not in ascending order, and a
# same-version `decision: confirmed` note sitting beside the real approval.
# So: parse to a SET of versions, and let the heading shape exclude the note.
VERSION_TOKEN = r"v[0-9]+(?:\.[0-9]+)*"
POSITIVE_INTEGER_VERSION_RE = re.compile(r"v[1-9][0-9]*")
APPROVAL_HEADING_RE = re.compile(r"^#{2,}[ \t]*(?:\d+\.[ \t]*)?Approval\b[^\n]*$",
                                 re.MULTILINE)
# A quote with at least one non-space character. `global-agent-instructions`
# uses ASCII quotes, the others use 「」; both are in git, so both parse.
_QUOTE = r"(?:「[^」\n]*[^\s」][^」\n]*」|\"[^\"\n]*[^\s\"][^\"\n]*\")"
APPROVAL_LIST_RE = re.compile(
    rf"^[ \t]*-[ \t]*(\d{{4}}-\d{{2}}-\d{{2}})[ \t]*[—–-][ \t]*approves[ \t]+"
    rf"({VERSION_TOKEN})(?![0-9.])[^\n]*?{_QUOTE}", re.MULTILINE)
# `### v5 的兩項選擇 — <date>` does not match: the date must follow the version
# token directly. That is what keeps a decision note out of the approval set.
APPROVAL_SECTION_HEAD_RE = re.compile(
    rf"^#{{3,}}[ \t]*({VERSION_TOKEN})(?![0-9.])[ \t]*[—–-][ \t]*"
    rf"(\d{{4}}-\d{{2}}-\d{{2}})[ \t]*$", re.MULTILINE)


def _without_noise(text: str) -> str:
    """Fenced code and HTML comments are not records. The spec template ships
    a commented-out placeholder inside its own Approval section, so without
    this every freshly-created spec would look approved."""
    text = re.sub(r"^```.*?^```", "", text, flags=re.MULTILINE | re.DOTALL)
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def approval_section(text: str, rel: str) -> str | None:
    """The section runs to the next heading of the same level or higher, so
    the `###` records inside a `## Approval` stay in."""
    heads = list(APPROVAL_HEADING_RE.finditer(text))
    if not heads:
        return None
    if len(heads) > 1:
        die(2, f"{rel}: more than one Approval section — structure is ambiguous")
    head = heads[0]
    level = len(head.group(0)) - len(head.group(0).lstrip("#"))
    nxt = re.compile(rf"^#{{1,{level}}}[ \t]", re.MULTILINE).search(text, head.end())
    return text[head.end():nxt.start() if nxt else len(text)]


def approved_versions(section: str) -> set[str]:
    found = {m.group(2) for m in APPROVAL_LIST_RE.finditer(section)}
    for m in APPROVAL_SECTION_HEAD_RE.finditer(section):
        version, date = m.group(1), m.group(2)
        nxt = re.compile(r"^#{2,}[ \t]", re.MULTILINE).search(section, m.end())
        body = section[m.end():nxt.start() if nxt else len(section)]
        if not re.search(r"\bapproval:\s*confirmed\b", body):
            continue
        if not re.search(rf"version bound:\s*{re.escape(version)}(?![0-9.])", body):
            continue
        if not re.search(rf"date:\s*{re.escape(date)}\b", body):
            continue
        if not (re.search(r"^[ \t]*>[ \t]*\S", body, re.MULTILINE)
                or re.search(_QUOTE, body)):
            continue
        found.add(version)
    return found


def check_approval(text: str, rel: str, version: str) -> None:
    """R1 completeness, then R2 continuity. R1 first: when both fire the
    message names the version being archived, not an ancestor."""
    section = approval_section(_without_noise(text), rel)
    found = approved_versions(section) if section is not None else set()
    if version not in found:
        die(1, f"{rel}: no complete approval record for {version} in the "
               f"Approval section — an approved spec ships with the words that "
               f"approved THIS version")
    if POSITIVE_INTEGER_VERSION_RE.fullmatch(version):
        for i in range(1, int(version[1:])):
            if f"v{i}" not in found:
                die(1, f"{rel}: approval sequence incomplete — no record for "
                       f"v{i}, but the spec is at {version}. An integer version "
                       f"is spent only on a version the human approved")


def read_status(spec: Path) -> tuple[str, str]:
    try:
        text = spec.read_text(encoding="utf-8")
    except OSError as e:
        die(2, f"cannot read {spec}: {e}")
    m = STATUS_RE.search(text)
    if m is None:
        die(2, f"cannot parse the `status` line in {spec}")
    return text, m.group(2)


def evidence_version(root: Path, scope: str) -> tuple[str, str]:
    """Locate the committed evidence report and return (path, spec_version)."""
    tracked: list[str] = []
    untracked: list[str] = []
    for pattern in EVIDENCE_CANDIDATES:
        rel = pattern.format(scope=scope)
        if not (root / rel).is_file():
            continue
        r = run(["git", "ls-files", "--error-unmatch", rel], cwd=root)
        (tracked if r.returncode == 0 else untracked).append(rel)
    if not tracked:
        where = " or ".join(p.format(scope=scope) for p in EVIDENCE_CANDIDATES)
        hint = f" (present but not committed: {', '.join(untracked)})" if untracked else ""
        die(1, f"no committed evidence report for `{scope}` at {where}{hint} — "
               "the gate's `evidence` precedes CLOSE")
    if len(tracked) > 1:
        die(1, f"ambiguous evidence: {', '.join(tracked)} are both committed")
    rel = tracked[0]
    try:
        text = (root / rel).read_text(encoding="utf-8")
    except OSError as e:
        die(2, f"cannot read {rel}: {e}")
    header = text.split("\n## ", 1)[0]
    m = EVIDENCE_VERSION_RE.search(header)
    if m is None:
        die(2, f"cannot find `spec_version: vN` in the header of {rel}")
    return rel, m.group(1)


def is_tracked(root: Path, rel: str) -> bool:
    return run(["git", "ls-files", "--error-unmatch", rel], cwd=root).returncode == 0


def last_commit(root: Path, rel: str) -> str:
    r = run(["git", "log", "-1", "--format=%H", "--", rel], cwd=root)
    if r.returncode != 0 or not r.stdout.strip():
        die(2, f"cannot find the last commit of {rel}")
    return r.stdout.strip()


def is_ancestor(root: Path, a: str, b: str) -> bool:
    """True when commit a is b or reachable from b (a is no later than b)."""
    return run(["git", "merge-base", "--is-ancestor", a, b], cwd=root).returncode == 0


def check_verdict(root: Path, ev_rel: str) -> None:
    """Phase 5 is optional; when its aggregate exists it must not say failed."""
    rel = (Path(ev_rel).parent / "verification.md").as_posix()
    if not (root / rel).is_file():
        return
    if not is_tracked(root, rel):
        die(1, f"{rel} is present but not committed — the verdict ships beside the evidence")
    try:
        text = (root / rel).read_text(encoding="utf-8")
    except OSError as e:
        die(2, f"cannot read {rel}: {e}")
    m = VERDICT_RE.search(text)
    if m is None:
        die(2, f"cannot parse the `final_verdict` line in {rel}")
    if m.group(1) in ("failed", "blocked"):
        die(1, f"{rel} records `final_verdict: {m.group(1)}` — a state whose "
               "verification did not pass does not ship")


def check_squad(root: Path, scope: str, spec_rel: str, ev_rel: str, tier: int) -> None:
    """Tier 2 and 3 run all three squad cuts; each leaves a committed record."""
    if tier == 1:
        return
    approval = run(["git", "log", "-1", "--format=%H", "-S`status`: approved", "--", spec_rel],
                   cwd=root)
    if approval.returncode != 0 or not approval.stdout.strip():
        die(2, f"cannot find the commit that approved {spec_rel}")
    approval_commit = approval.stdout.strip()
    evidence_commit = last_commit(root, ev_rel)
    for cut in SQUAD_CUTS:
        rel = SQUAD_PATH.format(scope=scope, cut=cut)
        if not (root / rel).is_file():
            die(1, f"no squad record for the `{cut}` cut at {rel} — "
                   f"tier {tier} runs all three cuts before CLOSE")
        if not is_tracked(root, rel):
            die(1, f"{rel} is present but not committed")
        try:
            text = (root / rel).read_text(encoding="utf-8")
        except OSError as e:
            die(2, f"cannot read {rel}: {e}")
        for line in text.splitlines():
            if not FINDING_RE.match(line):
                continue
            c = CLASS_RE.search(line)
            if c is None:
                die(1, f"{rel}: finding without a class: {line.strip()[:80]}")
            if c.group(1) == "1" and FIXED_RE.search(line) is None:
                die(1, f"{rel}: class-1 finding still open: {line.strip()[:80]}")
        committed = last_commit(root, rel)
        if cut == "after-spec" and not is_ancestor(root, committed, approval_commit):
            die(1, f"{rel} was last committed after the approval commit — "
                   "the after-spec cut precedes approval")
        if cut == "after-implement" and not is_ancestor(root, committed, evidence_commit):
            die(1, f"{rel} was last committed after the evidence report — "
                   "the after-implement cut precedes `evidence`")


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

    v = SPEC_VERSION_RE.search(text)
    if v is None:
        die(2, f"cannot parse the `spec_version` line in {spec.relative_to(root)}")
    ev_path, ev_version = evidence_version(root, scope)
    if ev_version != v.group(1):
        die(1, f"{ev_path} records `spec_version: {ev_version}`, the spec is "
               f"{v.group(1)} — rerun the gate's `evidence` against the approved spec")
    t = TIER_RE.search(text)
    if t is None:
        die(2, f"cannot parse the `tier` line in {spec.relative_to(root)}")
    # After tier, before the verdict: the fixtures that pin the evidence and
    # tier messages die earlier and keep their own reasons.
    check_approval(text, spec.relative_to(root).as_posix(), v.group(1))
    check_verdict(root, ev_path)
    check_squad(root, scope, spec.relative_to(root).as_posix(), ev_path, int(t.group(1)))

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
