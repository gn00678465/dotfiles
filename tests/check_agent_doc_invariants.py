#!/usr/bin/env python3
"""Cross-file invariants for the evidence-first contract machinery.

These documents promise each other things (status vocabularies, report
fields, shared tier/anti-gaming definitions); this check makes drift
between them a red exit instead of a silent divergence.

Fail closed — every failure path is explicit. Exit codes: 0 all
invariants hold; 1 an invariant is broken; 2 the check itself broke
(missing file, unreadable input). Stdlib only; runs anywhere python3 does.
Usage: tests/check_agent_doc_invariants.py [repo-root]
"""

import re
import sys
from pathlib import Path


def die(code: int, msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def read(file: Path) -> str:
    try:
        text = file.read_text(encoding="utf-8")
    except OSError as e:
        die(2, f"missing or unreadable file: {file} ({e})")
    if not text.strip():
        die(2, f"missing or empty file: {file}")
    return text


CHECKS = 0


def require(file: Path, desc: str, pattern: str) -> None:
    global CHECKS
    if pattern in read(file):
        CHECKS += 1
    else:
        die(1, f"{desc} — '{pattern}' not found in {file}")


def forbid(file: Path, desc: str, pattern: str) -> None:
    global CHECKS
    if pattern not in read(file):
        CHECKS += 1
    else:
        die(1, f"{desc} — '{pattern}' must not appear in {file}")


def agree(desc: str, *sites: tuple[Path, str]) -> None:
    """Cross-file equality: pull one value out of each file and require they
    match. `require` only proves a literal this checker already knows is
    present in one file; when the same value is spelled in prose here and in
    Python there, only comparing what each side actually says catches a
    one-sided edit."""
    global CHECKS
    seen: list[tuple[Path, str]] = []
    for file, pattern in sites:
        m = re.search(pattern, read(file))
        if m is None:
            die(1, f"{desc} — /{pattern}/ matched nothing in {file}")
        seen.append((file, m.group(1)))
    values = {v for _, v in seen}
    if len(values) != 1:
        detail = "; ".join(f"{f.name} says '{v}'" for f, v in seen)
        die(1, f"{desc} — sides disagree: {detail}")
    CHECKS += 1


def count_numbered_rules(file: Path, heading: str, expected: int) -> None:
    global CHECKS
    flag = False
    n = 0
    for line in read(file).splitlines():
        if line.startswith(heading):
            flag = True
            continue
        if line.startswith("## "):
            flag = False
        if flag and re.match(r"^[0-9]+\.", line):
            n += 1
    if n == expected:
        CHECKS += 1
    else:
        die(1, f"'{heading}' in {file} has {n} numbered rules, expected {expected}")


def main() -> None:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent.parent

    contract = root / ".chezmoitemplates/evidence-first-contract.md"
    protocol = root / ".chezmoitemplates/verifier-protocol.md"
    workflow = root / "dot_agents/workflow/evidence-first.md"
    spec_t = root / "dot_agents/workflow/templates/spec.md"
    verif_t = root / "dot_agents/workflow/templates/verification.md"
    skill = root / "dot_agents/skills/verification-gate/SKILL.md"
    evidence_t = root / "dot_agents/skills/verification-gate/assets/templates/evidence.md"
    archiver_skill = root / "dot_agents/skills/spec-archive/SKILL.md"
    archiver = root / "dot_agents/skills/spec-archive/scripts/spec-archive.py"

    # 1. Layer-status vocabulary: SKILL.md and the evidence template must
    #    carry the same five states — a status one side names and the other
    #    cannot record is exactly the drift this file exists to catch.
    for status in ("N-A", "UNAVAILABLE", "SUBSTITUTED", "NOT REACHED", "DEPENDENCY UNMET"):
        require(skill, "layer status vocabulary", status)
        require(evidence_t, "layer status vocabulary", status)

    # 2. Report fields the contract promises must exist in the template.
    require(contract, "contract override marker", "overridden by")
    require(evidence_t, "contract header field", "`contract`:")
    require(evidence_t, "override value in contract field", "overridden by")
    require(evidence_t, "headline roll-up field", "`headline`")

    # 3. Anti-gaming rules: same six on both sides of the split.
    count_numbered_rules(skill, "## Anti-Gaming Rules", 6)
    count_numbered_rules(workflow, "## Anti-Gaming Rules", 6)

    # 4. Tier 3 domain list: one definition, all carriers.
    for f in (contract, skill, workflow, spec_t):
        require(f, "tier 3 domain list", "money, auth, data")

    # 5. Structured approval: contract states the rule; workflow and spec
    #    template carry the artifact that satisfies it.
    require(contract, "structured approval rule", "structured act")
    require(workflow, "approval section reference", "`## Approval`")
    require(spec_t, "approval section", "## Approval")

    # 6. Handoff wiring: the workflow points at artifacts that must exist.
    require(workflow, "spec template reference", "templates/spec.md")
    require(workflow, "verification template reference", "templates/verification.md")
    require(verif_t, "declared-downgrade state", "not performed")
    require(protocol, "verifier fail-closed state", "blocked")
    require(contract, "gate handoff", "verification-gate")

    # 7. Close ritual: the workflow points at the spec-archive skill, the
    #    skill points at its script, and the terminal status exists
    #    everywhere it must.
    require(workflow, "close phase", "## Phase 6")
    require(workflow, "close skill reference", "spec-archive")
    require(archiver_skill, "skill points at script", "spec-archive.py")
    require(archiver, "forgotten-close detector", "--check")
    require(archiver, "terminal status flip", "shipped")
    require(spec_t, "terminal status in template", "shipped")

    # 8. Review surface: SPEC REVIEW renders the spec for the human, and the
    #    review UI language is declared rather than inherited from the
    #    plugin's Japanese default.
    require(workflow, "review surface", "Review surface")
    require(workflow, "review UI language declaration", "metadata.lang")

    # 9. Spec path: the workflow states where a spec lives and the archiver
    #    hardcodes the same root. Group 7 above wires the CLOSE ritual but
    #    never compares the two spellings of the path — so the workflow could
    #    call it a "suggested path" while the script treated it as fixed, and
    #    a spec filed elsewhere archived nowhere while `--check` still
    #    reported clean. Both halves are asserted here.
    agree("spec root",
          (contract, r"`([\w./-]+)/<scope>/SPEC\.md`"),
          (workflow, r"`([\w./-]+)/<scope>/SPEC\.md`"),
          (archiver, r'root / "([\w-]+)" / scope'),
          (archiver_skill, r"`([\w/-]+)/<scope>/` to"))
    forbid(workflow, "spec path stated as optional", "suggested path")

    # 10. Status vocabulary needs an owner per transition, not just a list.
    #     `shipped` always had one (the archiver's script); `approved` had
    #     none — the template listed it, the script refused anything else at
    #     CLOSE, and nothing told the human's counterpart to write it. A spec
    #     then carried a verbatim approval while still reading `draft`, and
    #     Phase 6 refused consent that had actually been given.
    require(workflow, "approval flips status", "flip `status`")
    require(workflow, "revision resets status", "revised-pending-approval")
    require(spec_t, "status transition owners", "revised-pending-approval")
    require(archiver, "archiver gates on approved", '!= "approved"')

    # 11. Artifact root and `scope` are derived by two parties. The root is
    #     one value spelled in two files; `scope` was inferred independently
    #     by the gate while the workflow spent it as if it were the spec's
    #     slug, so on any prefixed branch the evidence report filed under a
    #     name `specs/<scope>/` never used and Phase 5's "beside the evidence
    #     report" pointed somewhere else.
    agree("artifact root",
          (workflow, r"`([\w./-]+/)<scope>/verification\.md`"),
          (skill, r"`artifact_root`: default `([\w./-]+/)`"))
    require(workflow, "spec scope handed to the gate", "gate's `scope`")
    require(skill, "gate reuses the spec scope", "use that `<scope>` verbatim")

    # 12. The contract promises the report records ordering beside intent and
    #     RED. Intent had `intent_status` and RED had a section; ordering had
    #     only a mention inside `git_facts` as a fact that might be missing,
    #     so when it was available there was nowhere to state it.
    require(contract, "ordering promised to the human", "intent, ordering")
    require(skill, "gate gathers ordering", "| Ordering |")
    require(evidence_t, "ordering field exists", "`ordering`:")

    print(f"OK: {CHECKS} invariants hold")


if __name__ == "__main__":
    main()
