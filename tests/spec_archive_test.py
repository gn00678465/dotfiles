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
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARCHIVER = Path(os.environ.get(
    "SPEC_ARCHIVE_UNDER_TEST",
    ROOT / "dot_agents/skills/spec-archive/scripts/spec-archive.py",
))
EVIDENCE_TEMPLATE = ROOT / "dot_agents/skills/verification-gate/assets/templates/evidence.md"

FIELD_LINE_RE = re.compile(r"^-\s*`([\w_]+)`:.*$", re.MULTILINE)

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
           stdout_has: str | None = None,
           stderr_has: str | None = None) -> subprocess.CompletedProcess:
    global FAILURES, PASSES
    r = harness([sys.executable, str(ARCHIVER), *args], repo)
    ok = (r.returncode == rc
          and (stdout_has is None or stdout_has in r.stdout)
          and (stderr_has is None or stderr_has in r.stderr))
    if ok:
        PASSES += 1
        print(f"ok: {desc} (rc={r.returncode})")
    else:
        FAILURES += 1
        print(f"FAIL: {desc} — expected rc {rc}"
              + (f" and stdout containing '{stdout_has}'" if stdout_has else "")
              + (f" and stderr containing '{stderr_has}'" if stderr_has else "")
              + f", got rc {r.returncode}\n  stdout: {r.stdout.strip()}"
              + f"\n  stderr: {r.stderr.strip()}", file=sys.stderr)
    return r


def real_evidence_header(spec_version: str) -> str:
    """Build a header from the actual evidence template rather than a
    hand-written string (SPEC global-agent-instructions S4): every field name
    comes from `assets/templates/evidence.md` itself, so a future reshuffle of
    that template breaks this test before it breaks CLOSE in production.
    `intent_source`'s value follows the exact shape `tools/gate-intent.sh`
    emits — the backtick-wrapped `spec_version: vN` embedded in prose is what
    the archiver's regex actually greps for."""
    text = EVIDENCE_TEMPLATE.read_text(encoding="utf-8")
    header = text.split("\n## ", 1)[0]
    lines: list[str] = []
    for line in header.splitlines():
        m = re.match(r"^(-\s*`([\w_]+)`:)", line)
        if not m:
            continue
        field = m.group(2)
        if field == "intent_source":
            lines.append(f"{m.group(1)} 已提交的 SPEC `specs/foo/SPEC.md`"
                         f"（`spec_version: {spec_version}`、`status: approved`）")
        else:
            lines.append(f"{m.group(1)} test-value")
    return "\n".join(lines) + "\n"


# --- Approval fixtures (SPEC spec-version-bump §2) ---------------------------
# The two record shapes the parser must accept, built here rather than pasted
# as literals so a change to §2's definition breaks these fixtures first.

def approvals(*versions: str, date: str = "2026-09-15") -> str:
    """List form: `- <date> — approves <version> — 「<words>」`."""
    body = "\n".join(f"- {date} — approves {v} — 「核准 SPEC {v}」"
                     for v in versions)
    return f"## Approval\n\n{body}\n"


def sectioned(*versions: str, date: str = "2026-09-15", words: bool = True,
              confirmed: bool = True, heading: str = "## Approval",
              decoy: str | None = None) -> str:
    """Sectioned form: `### vN — <date>` plus the fields §2 requires."""
    out = [heading, ""]
    if decoy is not None:
        out += [f"### {decoy} 的兩項選擇 — {date}", "",
                "- **decision: confirmed**", f"- date: {date}", ""]
    for v in versions:
        out += [f"### {v} — {date}", "",
                "- **approval: confirmed**" if confirmed else "- **decision: confirmed**",
                f"- version bound: {v}", f"- date: {date}"]
        if words:
            out += ["- verbatim words:", "", f"  > 核准 SPEC {v}"]
        out.append("")
    return "\n".join(out) + "\n"


# The template's own Approval section: prose plus placeholders, never empty.
# S1 feeds this verbatim — "blank section" was the wrong input description.
TEMPLATE_APPROVAL = """## Approval

Append-only. One entry per approved version: the approving words verbatim,
the date, and the `spec_version` they bind. An entry you cannot quote is an
approval you do not have — an answer to a question is not one.

- <date> — approves <spec_version> — "<verbatim approving words>"
- <!-- or: `approval: not obtained (autonomous run)` -->
"""


def make_spec(repo: Path, scope: str, version: str, approval: str,
              tier: int = 1, status: str = "approved",
              extra: str = "") -> None:
    d = repo / "specs" / scope
    d.mkdir(parents=True, exist_ok=True)
    (d / "SPEC.md").write_text(
        f"- `spec_version`: {version}\n- `tier`: {tier}\n"
        f"- `status`: {status}\n\n{approval}{extra}", encoding="utf-8")
    ev = repo / ".scratch" / scope
    ev.mkdir(parents=True, exist_ok=True)
    (ev / "evidence.md").write_text(
        real_evidence_header(version) + "\n## Baseline\n", encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", f"{scope} fixture")


def expect_refused(desc: str, repo: Path, args: list[str], rc: int,
                   stderr_has: str | None = None) -> None:
    """A refusal changes nothing. Exit code alone would pass for a checker
    that refuses *after* mutating, so pin the four observable effects."""
    scope = args[0]
    spec = repo / "specs" / scope / "SPEC.md"
    head = harness(["git", "rev-parse", "HEAD"], repo).stdout.strip()
    before = spec.read_text(encoding="utf-8") if spec.is_file() else None
    expect(desc, repo, args, rc, stderr_has=stderr_has)
    after = spec.read_text(encoding="utf-8") if spec.is_file() else None
    check(f"{desc} — HEAD unchanged",
          harness(["git", "rev-parse", "HEAD"], repo).stdout.strip() == head)
    check(f"{desc} — spec content unchanged", after == before)
    check(f"{desc} — source directory still present",
          (repo / "specs" / scope).is_dir())
    check(f"{desc} — archive directory not created",
          not (repo / "specs/archive" / scope).exists())


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
        spec.write_text("- `spec_version`: v2\n- `tier`: 1\n- `status`: draft\n\n"
                        + approvals("v1", "v2"),
                        encoding="utf-8")
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

        # Evidence gate: CLOSE reads the gate's committed evidence report and
        # refuses when it is missing, uncommitted, or bound to another spec
        # version — the header must come from git, not from memory.
        expect("archiving without a committed evidence report is refused",
               repo, ["foo"], 1, stderr_has="evidence")
        (repo / ".gitignore").write_text(".gate/\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "ignore gate artifacts")
        ignored = repo / ".gate/foo/evidence.md"
        ignored.parent.mkdir(parents=True)
        ignored.write_text("- `intent_source`: SPEC `spec_version: v2`\n",
                           encoding="utf-8")
        expect("an evidence report that is not tracked by git is refused",
               repo, ["foo"], 1, stderr_has="not committed")
        ignored.unlink()
        evidence = repo / ".scratch/foo/evidence.md"
        evidence.parent.mkdir(parents=True)
        evidence.write_text("- `intent_source`: SPEC `spec_version: v1`\n"
                            "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "evidence v1")
        expect("evidence bound to another spec_version is refused",
               repo, ["foo"], 1, stderr_has="spec_version")
        evidence.write_text("- `headline`: GATE PASSED\n\n## Baseline\n"
                            "`spec_version: v2` mentioned only in the body\n",
                            encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "evidence without version in header")
        expect("evidence whose header carries no spec_version cannot be evaluated",
               repo, ["foo"], 2, stderr_has="spec_version")
        evidence.write_text("- `intent_source`: SPEC `spec_version: v2`\n"
                            "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "evidence v2")
        qux = repo / "specs/qux/SPEC.md"
        qux.parent.mkdir(parents=True)
        qux.write_text("- `status`: approved\n", encoding="utf-8")
        (repo / ".scratch/qux").mkdir(parents=True)
        (repo / ".scratch/qux/evidence.md").write_text(
            "- `intent_source`: SPEC `spec_version: v1`\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "qux without spec_version")
        expect("a spec without a spec_version line cannot be evaluated",
               repo, ["qux"], 2, stderr_has="spec_version")

        # SPEC global-agent-instructions S4: fixtures built from the *real*
        # evidence template, not a hand-written snippet unrelated to it.
        header_fields = set(FIELD_LINE_RE.findall(
            EVIDENCE_TEMPLATE.read_text(encoding="utf-8").split("\n## ", 1)[0]))
        check("evidence template exposes the fields this harness relies on",
              {"headline", "intent_source", "source_state"} <= header_fields)

        quux = repo / "specs/quux/SPEC.md"
        quux.parent.mkdir(parents=True)
        quux.write_text("- `spec_version`: v3\n- `tier`: 1\n- `status`: approved\n\n"
                        + approvals("v1", "v2", "v3"),
                        encoding="utf-8")
        (repo / ".scratch/quux").mkdir(parents=True)
        (repo / ".scratch/quux/evidence.md").write_text(
            real_evidence_header("v3") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "quux via real template, matching version")
        expect("real-template evidence with a matching version archives",
               repo, ["quux"], 0, stdout_has="archived")

        corge = repo / "specs/corge/SPEC.md"
        corge.parent.mkdir(parents=True)
        corge.write_text("- `spec_version`: v4\n- `tier`: 1\n- `status`: approved\n\n## Approval\n",
                        encoding="utf-8")
        (repo / ".scratch/corge").mkdir(parents=True)
        (repo / ".scratch/corge/evidence.md").write_text(
            real_evidence_header("v5") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "corge via real template, mismatched version")
        expect("real-template evidence with a mismatched version is refused",
               repo, ["corge"], 1, stderr_has="spec_version")

        # Dotted draft versions (`v0.1`, `v0.2` — evidence-first Phase 1) must
        # compare whole. The two regexes failed differently before the fix:
        # SPEC_VERSION_RE truncated `v0.1` to `v0`, so two different drafts
        # compared equal; EVIDENCE_VERSION_RE wanted the integer immediately
        # before the closing backtick, so a dotted version did not match at all
        # and CLOSE exited 2. Neither ever archived these fixtures.
        # The assertions therefore pin the full message, not just rc: reverting
        # only SPEC_VERSION_RE still yields rc 1 with `spec_version` in stderr,
        # and would pass a check that stopped there while actually comparing
        # `v0` against `v0.1`. rc 1 rather than rc 2 separates "parsed, and the
        # versions differ" from "could not parse a version at all".
        grault = repo / "specs/grault/SPEC.md"
        grault.parent.mkdir(parents=True)
        grault.write_text("- `spec_version`: v0.2\n- `tier`: 1\n- `status`: approved\n\n"
                          + approvals("v0.2"),
                          encoding="utf-8")
        (repo / ".scratch/grault").mkdir(parents=True)
        grault_ev = repo / ".scratch/grault/evidence.md"
        grault_ev.write_text(real_evidence_header("v0.1") + "\n## Baseline\n",
                             encoding="utf-8")
        garply = repo / "specs/garply/SPEC.md"
        garply.parent.mkdir(parents=True)
        garply.write_text("- `spec_version`: v0.10\n- `tier`: 1\n- `status`: approved\n\n## Approval\n",
                          encoding="utf-8")
        (repo / ".scratch/garply").mkdir(parents=True)
        (repo / ".scratch/garply/evidence.md").write_text(
            real_evidence_header("v0.1") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "draft-versioned specs and their evidence")
        expect("evidence at v0.1 is refused for a spec at v0.2, both quoted whole",
               repo, ["grault"], 1,
               stderr_has="`spec_version: v0.1`, the spec is v0.2")
        expect("evidence at v0.1 is refused for a spec at v0.10, no prefix match",
               repo, ["garply"], 1,
               stderr_has="`spec_version: v0.1`, the spec is v0.10")
        # The severe case: a header already truncated upstream. Before the fix
        # `gate-intent.sh` emitted `v0` for any `v0.N` spec and the archiver
        # truncated the spec the same way, so the two compared equal and the
        # spec shipped — exit 0, spec moved. Which draft that `v0` was produced
        # against is unrecoverable: truncation destroyed the digits that would
        # tell them apart, and CLOSE archived on a comparison that could no
        # longer distinguish them. Verified against the pre-fix archiver.
        garply_ev = repo / ".scratch/garply/evidence.md"
        garply_ev.write_text(real_evidence_header("v0") + "\n## Baseline\n",
                             encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "garply evidence truncated to v0")
        expect("an upstream-truncated v0 header does not archive a v0.10 spec",
               repo, ["garply"], 1,
               stderr_has="`spec_version: v0`, the spec is v0.10")
        grault_ev.write_text(real_evidence_header("v0.2") + "\n## Baseline\n",
                             encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "grault evidence bumped to v0.2")
        expect("a dotted version that matches archives", repo, ["grault"], 0,
               stdout_has="archived")


        # Tier line: the contract declares it in the SPEC and the archiver
        # reads it to decide which squad cuts must be on record.
        plugh = repo / "specs/plugh/SPEC.md"
        plugh.parent.mkdir(parents=True)
        plugh.write_text("- `spec_version`: v1\n- `status`: approved\n\n## Approval\n",
                         encoding="utf-8")
        (repo / ".scratch/plugh").mkdir(parents=True)
        (repo / ".scratch/plugh/evidence.md").write_text(
            real_evidence_header("v1") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "plugh without a tier line")
        expect("a spec without a tier line cannot be evaluated",
               repo, ["plugh"], 2, stderr_has="tier")

        # Squad records (tier 2 and 3): all three cuts, committed, classed,
        # class-1 closed, after-spec before approval, after-implement before
        # the evidence report. `waldo` is approved before any squad record
        # exists, so its after-spec record can only ever be late.
        waldo = repo / "specs/waldo/SPEC.md"
        waldo.parent.mkdir(parents=True)
        waldo.write_text("- `spec_version`: v1\n- `tier`: 2\n- `status`: approved\n\n"
                         + approvals("v1"),
                         encoding="utf-8")
        (repo / ".scratch/waldo").mkdir(parents=True)
        (repo / ".scratch/waldo/evidence.md").write_text(
            real_evidence_header("v1") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "waldo tier 2 approved with evidence, no squad")
        expect("tier 2 without any squad record is refused",
               repo, ["waldo"], 1, stderr_has="after-spec")
        squad = repo / ".scratch/waldo/squad"
        squad.mkdir()
        # Ignored by git, so the tree stays clean and the record is the only
        # thing missing from the commit — a plain untracked file would trip
        # the dirty-tree refusal first.
        (repo / ".gitignore").write_text(".gate/\n.scratch/waldo/squad/after-spec.md\n",
                                         encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "waldo ignores its after-spec record")
        (squad / "after-spec.md").write_text(
            "# squad: after-spec\n\n- [HIGH] a.py:1 — no class here — evidence — rec\n",
            encoding="utf-8")
        expect("a squad record that is not committed is refused",
               repo, ["waldo"], 1, stderr_has="not committed")
        (repo / ".gitignore").write_text(".gate/\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "waldo after-spec, unclassed")
        expect("a squad finding without a class is refused",
               repo, ["waldo"], 1, stderr_has="without a class")
        (squad / "after-spec.md").write_text(
            "# squad: after-spec\n\n- [HIGH] a.py:1 — f — evidence — class 1 — rec — status: open\n",
            encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "waldo after-spec, class 1 open")
        expect("an open class-1 squad finding is refused",
               repo, ["waldo"], 1, stderr_has="still open")
        (squad / "after-spec.md").write_text(
            "# squad: after-spec\n\n- [HIGH] a.py:1 — f — evidence — class 1 — rec — status: fixed\n",
            encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "waldo after-spec, class 1 fixed")
        expect("an after-spec record committed after the approval is refused",
               repo, ["waldo"], 1, stderr_has="after the approval")

        # `fred` follows the order the workflow prescribes.
        fred = repo / "specs/fred/SPEC.md"
        fred.parent.mkdir(parents=True)
        fred.write_text("- `spec_version`: v1\n- `tier`: 3\n- `status`: draft\n\n"
                        + approvals("v1"),
                        encoding="utf-8")
        fsq = repo / ".scratch/fred/squad"
        fsq.mkdir(parents=True)
        (fsq / "after-spec.md").write_text(
            "# squad: after-spec\n\n- [LOW] b.py:2 — f — evidence — class 3 — rec\n",
            encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred draft and after-spec squad")
        fred.write_text(fred.read_text(encoding="utf-8").replace("draft", "approved"),
                        encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred approved")
        (repo / ".scratch/fred/evidence.md").write_text(
            real_evidence_header("v1") + "\n## Baseline\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred evidence")
        (fsq / "after-implement.md").write_text("# squad: after-implement\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred after-implement after evidence")
        expect("an after-implement record committed after the evidence is refused",
               repo, ["fred"], 1, stderr_has="after the evidence")
        (repo / ".scratch/fred/evidence.md").write_text(
            real_evidence_header("v1") + "\n## Baseline\nrerun\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred evidence rerun after the squad")
        expect("tier 3 with the before-archive record missing is refused",
               repo, ["fred"], 1, stderr_has="before-archive")
        (fsq / "before-archive.md").write_text("# squad: before-archive\n", encoding="utf-8")
        verification = repo / ".scratch/fred/verification.md"
        verification.write_text("- `final_verdict`: failed\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred before-archive and a failed verdict")
        expect("a committed verdict of failed is refused",
               repo, ["fred"], 1, stderr_has="final_verdict: failed")
        verification.write_text("- `final_verdict`: blocked\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred blocked verdict")
        expect("a committed verdict of blocked is refused",
               repo, ["fred"], 1, stderr_has="final_verdict: blocked")
        verification.write_text("- `headline`: no verdict line\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred verdict unparseable")
        expect("a verification file without a final_verdict cannot be evaluated",
               repo, ["fred"], 2, stderr_has="final_verdict")
        git(repo, "rm", "-q", "--cached", str(verification))
        (repo / ".gitignore").write_text(".gate/\n.scratch/fred/verification.md\n",
                                         encoding="utf-8")
        verification.write_text("- `final_verdict`: passed\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred verdict ignored by git")
        expect("a verification file that is not committed is refused",
               repo, ["fred"], 1, stderr_has="not committed")
        (repo / ".gitignore").write_text(".gate/\n", encoding="utf-8")
        verification.write_text("- `final_verdict`: not performed\n", encoding="utf-8")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "fred verdict not performed, committed")
        expect("tier 3 with all three records in order and a declared downgrade archives",
               repo, ["fred"], 0, stdout_has="archived")

        # --- SPEC spec-version-bump: approval-record completeness (R1) and
        # --- approval-sequence continuity (R2). Every refusal below is rc 0
        # --- against the base ref: the archiver never read the Approval
        # --- section, which is the hole this scope closes.
        make_spec(repo, "s1", "v3", TEMPLATE_APPROVAL)
        expect_refused("S1 template boilerplate is not an approval record",
                       repo, ["s1"], 1,
                       stderr_has="no complete approval record for v3")

        make_spec(repo, "s2", "v3", approvals("v2"))
        expect_refused("S2 an older version's record does not approve this one",
                       repo, ["s2"], 1,
                       stderr_has="no complete approval record for v3")

        make_spec(repo, "s3", "v1", sectioned("v1.2"))
        expect_refused("S3 `### v1.2` is not a record for v1",
                       repo, ["s3"], 1,
                       stderr_has="no complete approval record for v1")

        make_spec(repo, "s4", "v3", sectioned("v3", words=False))
        expect_refused("S4 a sectioned record without verbatim words is incomplete",
                       repo, ["s4"], 1,
                       stderr_has="no complete approval record for v3")

        make_spec(repo, "s5", "v3", TEMPLATE_APPROVAL,
                  extra="\n## Revisions\n\n"
                        "- 2026-09-15 — approves v3 — 「核准 SPEC v3」\n")
        expect_refused("S5 a record under Revisions is not in the Approval section",
                       repo, ["s5"], 1,
                       stderr_has="no complete approval record for v3")

        make_spec(repo, "s7", "v4", approvals("v1", "v2", "v4"))
        expect_refused("S7 a gap in the approval sequence is refused",
                       repo, ["s7"], 1, stderr_has="no record for v3")

        make_spec(repo, "s8", "v2", approvals("v2"))
        expect_refused("S8 the sequence starts at v1, not at the lowest record",
                       repo, ["s8"], 1, stderr_has="no record for v1")

        # R1 applies to every version; R2 only to positive integers. Both
        # halves are pinned so "dotted versions cannot archive" can never
        # become true by accident — Must NOT forbids that rule.
        make_spec(repo, "s9b", "v0.2", TEMPLATE_APPROVAL)
        expect_refused("S9b a dotted version still needs its own record",
                       repo, ["s9b"], 1,
                       stderr_has="no complete approval record for v0.2")
        make_spec(repo, "s9a", "v0.2", approvals("v0.2"))
        expect("S9a a dotted version with its own record archives",
               repo, ["s9a"], 0, stdout_has="archived")

        # GREEN-guard, not a RED: green at the base ref because the base
        # archiver does not parse the section at all. It pins the four §2
        # parsing rules a naive implementation gets wrong — a numbered
        # heading, non-ascending order, a same-version decoy carrying
        # `decision: confirmed`, and multiple records per version.
        make_spec(repo, "s6", "v3",
                  sectioned("v1", "v3", "v2",
                            heading="## 8. Approval record", decoy="v3"))
        expect("S6 numbered heading, unordered records and a decision decoy archive",
               repo, ["s6"], 0, stdout_has="archived")

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
