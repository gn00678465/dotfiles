---
name: tdd
description: >-
  RED→GREEN→REFACTOR per behavior with commit discipline. Write the test,
  watch it fail, implement, commit at green, refactor under frozen assertions.
  Works standalone or spec-driven from a playbook. Owns anti-gaming rules 1–4.
---

# TDD

Implement one behavior at a time through RED→GREEN→REFACTOR. Each cycle
produces a failing-test commit followed by a passing-implementation commit,
so verification can reconstruct the RED from git alone.

## Modes

The mode is determined by the inputs the caller provides.

| Input | Mode | Behavior list | Commit cadence |
|---|---|---|---|
| `spec_path` provided | spec-driven | SPEC Scenarios, each mapped 1:1 to a test | Declared in the SPEC's setup plan; requires `base_ref` |
| `spec_path` absent | standalone | From user description or diff | Default: one RED commit + one GREEN commit per behavior |

Both modes share the cycle below and the anti-gaming rules at the end.

## RED — prove each test can fail

Write the test for one behavior. **Run it and watch it fail** before writing
the implementation. A test you never saw fail proves nothing.

- If the module under test does not exist yet, create a stub that raises
  (e.g. `NotImplementedError`) so the test fails on behavior, not on import.
  A collection error is a weaker RED than an assertion failure.
- Related behaviors may share one RED run, as long as each new test is
  individually observed failing.
- If a new test passes immediately, it is either vacuous (fix it) or the
  behavior already exists. Do not assert which — **prove it**: break the
  implementation with a one-off throwaway mutant, watch the test fail,
  restore. Record it as pre-existing behavior kept as regression armor.
- **Commit the failing test before the implementation.** The gate later reads
  commit ordering as a git fact — tests committed before the code they cover
  turn TDD discipline into durable, checkable evidence instead of a claim.

## GREEN — minimal implementation

Write the least code that makes the failing test pass. Run at least the
affected tests; run the full suite too when it stays fast enough. Commit at
green. A partial run passing here does not stand in for the final gate.

## REFACTOR — clean up under green, assertions frozen

While the suite is green, improve names, extract duplication, simplify.
What is frozen is **behavioral assertions**, not test files wholesale:

- Implementation refactors touch no test files at all.
- Test-structure refactors (helpers, fixtures, dedup) are a **separate step**:
  assertions unchanged, suite green before and after, then rerun mutation to
  confirm the restructured tests still kill — a refactor that blunts the tests
  is a silent hole in the gate.
- Anything that requires editing an assertion is not refactoring — it is a
  behavior change and belongs back in the spec (with a Revisions entry and,
  if material, re-approval).

## Delegated implementation (Tier 2+ option)

The RED→GREEN→REFACTOR loop may run in an **implementor subagent** so its
tool output does not consume the orchestrator's context. The contract survives
this split by design — verification reads git, never the conversation — on
three conditions:

- **Per-step commit cadence.** Each behavior lands as a RED commit (tests
  only) followed by a GREEN commit (implementation only). In spec-driven mode
  this cadence is declared in the SPEC's setup plan so approval authorizes it.
  This turns anti-gaming rule 2 into a git-readable invariant.
- **Hand off commits, not narration.** The subagent receives the spec path
  (when available), the base ref, an isolated worktree, and the gate entry
  point — never the orchestrator's conversation. It returns a commit SHA per
  behavior; treat everything else as unverified narration.
- **Split only when it pays.** A subagent re-reads the spec and codebase from
  scratch, so total tokens go up; what the split buys is the orchestrator's
  context. Delegate multi-behavior Tier 2+ work; keep Tier 1 and
  single-behavior changes in-session.

On a gate failure, send the failing output back to the same subagent verbatim
(resume its context rather than re-briefing); after three rejected rounds,
escalate to the human.

## Anti-Gaming Rules (authoritative copy — rules 1–4)

Rules 5–6 live in `verification-gate/SKILL.md`.

1. **Never weaken a test to make it pass** — no broadened assertions, added
   skips, raised tolerances, or deleted failing tests. A wrong-looking test is
   a spec conversation; surface it.
2. **Never edit a test and the implementation in the same step to reach
   green.** Change one, run, then the other.
3. **Never mock the unit under test.** Mock boundaries (network, clock,
   filesystem), not logic.
4. **Never chase the coverage number.** Coverage detects untested code; it is
   not a target. Mutation testing exists to catch tests that assert nothing,
   including yours.
