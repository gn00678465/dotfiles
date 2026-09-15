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
import subprocess
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


def code_blocks(file: Path) -> list[tuple[int, str, str]]:
    blocks, lang, start, body = [], None, 0, []
    for n, line in enumerate(read(file).splitlines(), 1):
        if lang is None:
            m = re.match(r"^```(bash|sh|powershell)\s*$", line)
            if m:
                lang, start, body = m.group(1), n, []
        elif line.startswith("```"):
            blocks.append((start, lang, "\n".join(body)))
            lang = None
        else:
            body.append(line)
    return blocks


def blocks_self_contained(file: Path) -> None:
    """Claude Code's Bash and PowerShell tools start a new shell per call, so
    a variable set by an earlier block is empty in the next one: a verify
    block then reports a changed tree that did not change, and `-F
    "$GITDIR/..."` reads a file under the git install directory instead."""
    global CHECKS
    sh_vars = ("GITDIR", "BEFORE_TREE", "BEFORE_INDEX")
    ps_vars = ("path", "BEFORE_TREE", "BEFORE_INDEX")
    for start, lang, body in code_blocks(file):
        if lang == "powershell":
            for v in ps_vars:
                if re.search(rf"\${v}\b(?!\s*=)", body, re.I) and \
                        not re.search(rf"^\s*\${v}\s*=", body, re.I | re.M):
                    die(1, f"{file}:{start} PowerShell block reads ${v} without setting it")
            # Windows PowerShell decodes native output with the console code
            # page (950 on zh-TW), which garbles a non-ASCII git dir path.
            rp = body.find("git rev-parse --absolute-git-dir")
            enc = body.find("[Console]::OutputEncoding")
            if rp >= 0 and not 0 <= enc < rp:
                die(1, f"{file}:{start} PowerShell block runs git rev-parse before setting UTF-8 OutputEncoding")
        else:
            for v in sh_vars:
                if re.search(rf"\$\{{?{v}\b", body) and not re.search(rf"\b{v}=", body):
                    die(1, f"{file}:{start} shell block reads ${v} without setting it")
    CHECKS += 1


def powershell_split_block(file: Path) -> None:
    """The split must not reach the real index or corrupt the patch: Windows
    PowerShell 5.1 re-encodes native output sent through `>` or a pipe, and a
    GIT_INDEX_FILE left in an interactive session redirects every later git
    command to the temporary index."""
    global CHECKS
    split = [b for _, lang, b in code_blocks(file)
             if lang == "powershell" and "GIT_INDEX_FILE" in b]
    if len(split) != 1:
        die(1, f"{file} needs exactly one PowerShell split block, found {len(split)}")
    body = split[0]
    if "--output=" not in body or re.search(r"git diff[^\n]*(>|\|)", body):
        die(1, f"{file} PowerShell split block must write the patch with git diff --output=")
    setenv = re.search(r"\$env:GIT_INDEX_FILE\s*=", body)
    if setenv is None or not setenv.start() < body.find("git read-tree"):
        die(1, f"{file} PowerShell split block must set GIT_INDEX_FILE before git read-tree")
    fin = body.find("finally")
    if fin < 0 or "Remove-Item Env:GIT_INDEX_FILE" not in body[fin:]:
        die(1, f"{file} PowerShell split block must clear GIT_INDEX_FILE in finally")
    for cmd in ("git diff", "git read-tree", "git apply", "git commit"):
        line = next((l for l in body.splitlines() if cmd in l), "")
        if "$LASTEXITCODE" not in line:
            die(1, f"{file} PowerShell split block does not check the exit code of {cmd}")
    CHECKS += 1


def reword_blocks(file: Path) -> None:
    """Claude Code's tools cannot drive an interactive editor, so rewording an
    older commit needs `git rebase -i` with both editors replaced. A todo list
    written with `rebase.abbreviateCommands` starts with `p`, not `pick`, and
    `-i` flattens merges, which would change more than the message. The
    rebase.autoStash, rebase.autoSquash and rebase.updateRefs settings (this
    repo's own git config sets the first two) would unstage the user's index,
    squash fixup! commits, or move other branches."""
    global CHECKS
    found = {"sh": 0, "powershell": 0}
    for start, lang, body in code_blocks(file):
        if "GIT_SEQUENCE_EDITOR" not in body:
            continue
        kind = "powershell" if lang == "powershell" else "sh"
        found[kind] += 1
        for needle in ("GIT_EDITOR", "git rebase -i --no-autostash --no-autosquash --no-update-refs",
                       "git rebase --abort", "--merges", "--format=%T"):
            if needle not in body:
                die(1, f"{file}:{start} reword block lacks {needle}")
        if "^pick" in body:
            die(1, f"{file}:{start} reword block hardcodes 'pick' in the todo edit")
        if kind == "powershell":
            fin = body.find("finally")
            if fin < 0 or "Env:GIT_SEQUENCE_EDITOR" not in body[fin:] or "Env:GIT_EDITOR" not in body[fin:]:
                die(1, f"{file}:{start} PowerShell reword block must clear both editors in finally")
            line = next((l for l in body.splitlines() if "git rebase -i" in l), "")
            after = body[body.find(line) + len(line):].lstrip()
            if "$LASTEXITCODE" not in line and not after.startswith("if ($LASTEXITCODE)"):
                die(1, f"{file}:{start} PowerShell reword block does not check git rebase -i exit code")
    if found != {"sh": 1, "powershell": 1}:
        die(1, f"{file} needs one POSIX and one PowerShell reword block, found {found}")
    CHECKS += 1


def main() -> None:
    global CHECKS
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else \
        Path(__file__).resolve().parent.parent

    contract = root / ".chezmoitemplates/evidence-first-contract.md"
    protocol = root / ".chezmoitemplates/verifier-protocol.md"
    workflow = root / "dot_agents/workflows/evidence-first.md"
    spec_t = root / "dot_agents/workflows/templates/spec.md"
    verif_t = root / "dot_agents/workflows/templates/verification.md"
    skill = root / "dot_agents/skills/verification-gate/SKILL.md"
    evidence_t = root / "dot_agents/skills/verification-gate/assets/templates/evidence.md"
    archiver_skill = root / "dot_agents/skills/spec-archive/SKILL.md"
    archiver = root / "dot_agents/skills/spec-archive/scripts/spec-archive.py"
    commit_skill = root / "dot_agents/skills/commit/SKILL.md"
    entry_point_ref = root / "dot_agents/skills/verification-gate/references/entry-point.md"
    docs = root / "docs/evidence-first.md"
    squad_skill = root / "dot_agents/skills/evidence-squad/SKILL.md"

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

    # 13. CLOSE reads the evidence report's `spec_version` from git and
    #     refuses a mismatch — a promise the workflow and the skill both
    #     state, so the script must actually carry the check, and the
    #     evidence header's quoting form must be the one the script parses.
    require(workflow, "close checks evidence version", "`spec_version`")
    require(archiver_skill, "skill states the evidence version gate", "`spec_version: vN`")
    require(archiver, "archiver parses the evidence version", "EVIDENCE_VERSION_RE")
    require(archiver, "archiver refuses a version mismatch", "ev_version != v.group(1)")

    # 13b. CLOSE also reads the Phase 5 verdict and, at tier 2 and 3, the
    #      three squad records; the workflow, the archiver skill and the
    #      archiver must all name that gate.
    require(workflow, "workflow dispatches the squad", "`evidence-squad`")
    require(workflow, "workflow says CLOSE reads the verdict", "`blocked` do not ship")
    require(archiver_skill, "skill states the verdict gate", "`final_verdict`")
    require(archiver_skill, "skill states the squad gate", ".scratch/<scope>/squad/<cut>.md")
    require(archiver, "archiver parses the verdict", "VERDICT_RE")
    require(archiver, "archiver checks the squad records", "SQUAD_CUTS")

    # 13c. CLOSE also reads the spec's own Approval section (SPEC
    #      spec-version-bump R1/R2). Same pairing as 13 and 13b: the skill is
    #      what the agent running CLOSE reads, so a refusal the script makes
    #      and the skill does not name is a refusal nobody was told about.
    require(archiver_skill, "skill states the approval-record gate",
            "no structurally complete record")
    require(archiver, "archiver checks the approval records", "check_approval")

    # 14. SPEC global-agent-instructions S2: shortening the contract must not
    #     cost the properties it exists to guarantee. Each literal already
    #     holds today (this is regression armor, not a new behaviour) — proven
    #     non-vacuous once via a throwaway mutant on this same file, restored,
    #     per SKILL.md's "prove a negative control is itself non-vacuous".
    require(contract, "tests-first property survives", "committed before the implementation")
    require(contract, "RED property survives", "observed failing first")
    require(contract, "tier property survives", "Tier declared in the spec")
    require(contract, "anti-gaming property survives", "fix the implementation, never the test")
    require(contract, "degraded-evidence disclosure survives", "never silent")

    # 15. SPEC global-agent-instructions S3: a gate backed by a committed,
    #     approved spec that already authorizes this gate's intent/tier/setup
    #     must reuse it rather than re-asking; a standalone gate with no
    #     confirmable intent, or one needing authorization the spec never
    #     granted, still asks.
    require(skill, "gate reuses an already-authorized spec without re-asking",
            "already supplies intent, tier, and this gate's setup")
    require(skill, "gate still asks for unauthorized new work",
            "needs a dependency or authorization the spec did not grant")

    # 16. SPEC global-agent-instructions S4: the workflow names exactly where
    #     the final evidence report is committed before CLOSE, and warns
    #     against leaving both of spec-archive's candidate paths tracked —
    #     the archiver treats that as ambiguous and refuses to guess.
    require(workflow, "final evidence commit path stated", "`.scratch/<scope>/evidence.md`")
    require(workflow, "ambiguous-evidence warning", "never track both at once")

    # 17. SPEC global-agent-instructions S5: CLOSE happens before merge
    #     everywhere it is described. The top-level diagram once said
    #     "after merge: CLOSE", contradicting Phase 6's own heading.
    forbid(workflow, "stale after-merge CLOSE timing removed", "after merge: CLOSE")
    require(workflow, "CLOSE timing consistent with Phase 6", "before merge: CLOSE")

    # 18. SPEC global-agent-instructions S6: the commit skill must not ask to
    #     help run a command it already ran, and must not force an atomic
    #     split purely because commit types differ when the groups cannot be
    #     built or reverted independently anyway.
    forbid(commit_skill, "no re-ask after commit already ran",
           "是否需要協助執行上述 commit 指令")
    require(commit_skill, "reports the already-run commit instead",
            "commit 已完成，附上 commit SHA")
    forbid(commit_skill, "no forced split on type difference alone",
           "即使 score ≤ 8 也應進入步驟 4")

    # 18b. The split rule is a direction, not a keyword. A string check for
    #      "無法各自建置或獨立還原" passed while the text said the opposite of
    #      what it means, so pin the direction and the two ways to invert it:
    #      groups that cannot stand alone stay in one commit, and the score
    #      picks analysis depth only.
    require(commit_skill, "inseparable groups stay in one commit",
            "無法各自建置或獨立還原 → 留在同一個提交")
    require(commit_skill, "score sizes the analysis, not the split",
            "只決定**分析深度**")
    forbid(commit_skill, "a high score alone does not force a split",
           "| `> 8` | 拆分 |")

    # 18c. Rewriting a message must not rewrite the tree: `--amend` without
    #      `--only` folds whatever sits in the index into the commit.
    require(commit_skill, "message-only amend keeps the index out",
            "git commit --amend --only -F")
    forbid(commit_skill, "no bare amend in the rewrite path",
           "git commit --amend -F ")

    # 18d. Writing a message is not committing: the skill must keep a path
    #      that delivers the text and stops.
    require(commit_skill, "message-only delivery path exists",
            "步驟 5a")

    # 18e. Every commit-skill code block runs alone in a fresh shell.
    blocks_self_contained(commit_skill)

    # 18f. The PowerShell channel has its own atomic split, and stdin mode is
    #      ruled out: `-Command -` drops a here-string with no blank line after
    #      it and decodes Chinese with the console code page, both with rc=0.
    powershell_split_block(commit_skill)
    require(commit_skill, "stdin script mode is ruled out", "`powershell -Command -`")
    # A Ctrl+C during a hook left the group committed on Windows while the
    # shell reported an interruption; the report must come from git, not the shell.
    require(commit_skill, "interrupted split checks git log before reporting",
            "被 Ctrl+C 中斷")

    # A POSIX block that turns on `set -e` or sets a trap must scope them to a
    # subshell: pasted into an interactive bash, a failing step closed the
    # terminal, and after success a later unrelated failure did.
    for start, lang, body in code_blocks(commit_skill):
        if lang != "powershell" and re.search(r"^\s*(set -e|trap )", body, re.M):
            lines = [l for l in body.splitlines() if l.strip()]
            if not (lines[0].startswith("(") and lines[-1].strip().startswith(")")):
                die(1, f"{commit_skill}:{start} shell block with set -e/trap is not wrapped in ( ... )")
    CHECKS += 1

    # 18g. Rewording an older commit is an executable block, not prose.
    reword_blocks(commit_skill)
    # A root target has no `<sha>^`; the block stops, and the agent must
    # report that instead of improvising a `--root` rewrite.
    require(commit_skill, "root-commit target stops the reword block", "目標是根提交")
    require(commit_skill, "reword block states its git version floor", "git 2.38")
    forbid(commit_skill, "no unexecutable interactive-rebase instruction",
           "以互動式 rebase 只改那一筆的訊息")
    # Claude Code's PowerShell tool refused the whole reword block, reading
    # `-replace '\\', '/'` as a Remove-Item target. Git's sh takes backslashes.
    forbid(commit_skill, "no backslash literal that trips the PowerShell tool's path guard",
           "-replace '\\\\'")

    # 19. SPEC global-agent-instructions S8: GREEN may run the affected tests
    #     first (full suite only when it stays fast); the final gate always
    #     runs every applicable layer regardless. The subjective "needs a
    #     paragraph to explain, split it" complexity-budget criterion is
    #     dropped as a named layer rather than kept unenforceable.
    forbid(workflow, "GREEN no longer demands the full suite unconditionally",
           "not just the new test")
    require(workflow, "GREEN may run affected tests first",
            "Run at least the affected tests")
    forbid(skill, "complexity budget layer removed from the gate skill", "Complexity budget")
    forbid(evidence_t, "complexity budget row removed from the evidence template",
           "Complexity budget")

    # 20. Gate 修正輪次 2/2, group B: S3's exception (an authorized spec is
    #     reused, not re-confirmed) was only wired into the Acquisition
    #     section. Five other unconditional "always confirm/ask" spots in the
    #     same skill still contradict it.
    require(skill, "scaffold reuses spec-authorized paths",
            "unless the committed, approved spec's Setup plan already authorizes these paths")
    require(skill, "inputs reuse an already-authorized spec before asking",
            "Resolve these from a committed, approved spec when it already supplies them")
    require(skill, "tier reuses the spec's declared tier before inferring",
            "Use the committed, approved spec's declared tier when one exists")
    require(skill, "entry-point writes reuse spec authorization",
            "unless the committed, approved spec's Setup plan already authorizes this entry point by path")
    require(skill, "toolchain setup reuses spec-authorized tools",
            "unless the committed, approved spec's Setup plan already authorizes the tools to install")

    # 21. Gate 修正輪次 2/2, group C: the skill and the entry-point reference
    #     must say, in so many words, that intent/tier/version come from the
    #     committed spec, and that intent_source must carry the exact
    #     backtick-quoted `spec_version: vN` form the archiver's regex parses.
    require(skill, "skill states intent/tier/version derive from the committed spec",
            "derive `intent_status`, the tier, and the version citation from that spec")
    require(skill, "skill states the parseable intent_source form", "`spec_version: vN`")
    require(entry_point_ref, "entry-point states intent/tier/version derive from the committed spec",
            "derive `intent`, `tier`, and the evidence header's version citation from it")
    require(evidence_t, "evidence template documents the intent_source version-citation form",
            "spec_version: vN")

    # 22. Gate 修正輪次 2/2, group D: the commit skill's 注意事項 section still
    #     carried the old unconditional split rule this SPEC replaced in
    #     group 18 — a leftover that contradicts the new one right next to it.
    forbid(commit_skill, "no leftover unconditional type-split rule in 注意事項",
           "當提交符合一或多種提交類型時，應盡可能切成多個提交")

    # 23. Gate 修正輪次 2/2, group E: docs/evidence-first.md must name this
    #     scope's own gate entry point (it only named tools/gate.sh) and carry
    #     the same ambiguous-evidence-path warning group 16 put in the
    #     reference workflow.
    require(docs, "docs name this scope's gate entry point", "gate-agent-instructions.py")
    require(docs, "docs carry the ambiguous-evidence-path warning", "不得同時追蹤兩個路徑")

    # 24. Gate 修正輪次 2/2, group A: the gate entry point itself must refuse
    #     an unreachable --base (rc=2) before running any layer, and must
    #     never print a passing headline in that case. This is the entry
    #     point's own behaviour, checked by actually invoking it — the doc
    #     invariants above assert what the docs promise, this asserts the
    #     script keeps that promise.
    gate_script = root / "tools/gate-agent-instructions.py"
    if not gate_script.is_file():
        die(2, f"missing gate entry point: {gate_script}")
    r = subprocess.run(
        [sys.executable, str(gate_script), "--base", "0" * 40],
        cwd=root, capture_output=True, text=True, encoding="utf-8",
    )
    if r.returncode != 2:
        die(1, f"gate-agent-instructions.py --base <unreachable> exited {r.returncode}, "
               f"expected 2 (fail closed before running any layer)")
    if "all layers green" in r.stdout:
        die(1, "gate-agent-instructions.py printed a passing headline "
               "despite an unreachable --base")
    CHECKS += 1

    # 25. Two wordings told an agent to spend an integer version per finding,
    #     and an agent followed them: a spec went v1 to v6 in three hours for
    #     four approvals. What this check does is block their VERBATIM return
    #     — nothing more. It does not prove the three documents agree, and a
    #     rephrasing walks past it; that limit is on record in the scope's
    #     evidence report rather than hidden behind the check's name.
    forbid(squad_skill, "the class-2 wording that ordered a bump has not returned",
           "the version is bumped")
    forbid(workflow, "the Revisions wording that ordered a bump has not returned",
           "bump the version, set")

    print(f"OK: {CHECKS} invariants hold")


if __name__ == "__main__":
    main()
