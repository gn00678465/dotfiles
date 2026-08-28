# Evidence-First Reference Implementation

The reference implementation of the evidence-first contract — follow it when
no workflow tool fits. The human will NOT read the implementation. Their
confidence comes entirely from two artifacts: the **SPEC** they approve
before code exists (owned by this workflow), and the **EVIDENCE** report
proving the code ran the gate (owned by the `verification-gate` skill). This
file owns the front half of the loop; the skill owns the back half. Do not
duplicate the gate's layers here, and never hand-roll an evidence report in
place of the skill.

```
SPEC → SPEC REVIEW (human approves spec, not code)
     → per behavior: RED → GREEN → REFACTOR
     → verification-gate: `gate` (iterate while fixing) → `evidence` (final, once)
     → Tier 3 option: independent verification (`verifier` agent)
```

## Phase 1 — SPEC

Before touching any implementation file, turn the request into **executable
acceptance criteria** in a spec file, committed to the repo (suggested path:
`specs/<scope>/SPEC.md`). Show the human its absolute path.

The spec contains:

- **Tier** — `1` trivial / `2` normal / `3` high stakes (money, auth, data
  loss, concurrency, public API). Same definitions as the gate's Calibration,
  so the tier you declare here is the tier the gate runs at. Tier 3 adds a
  short **failure model**: the ways this specific change can hurt, each mapped
  to a check that can actually catch it.
- **Scenarios** — Gherkin-style or a named test list. Concrete inputs,
  concrete expected outputs, edge cases, error cases. "Handles bad input" is
  not a spec; `divide(1, 0) raises ZeroDivisionError with message X` is. Each
  scenario maps 1:1 to at least one automated test, named after the scenario,
  so the evidence report's mapping is mechanical.
- **Must NOT** — negative constraints and invariants that must survive
  (existing tests, public API signatures, performance budgets if stated).
  A diff can never show what the code must not do; these become rows in the
  gate's stated-claim table, so write them down now.
- **Setup plan** — the spec is the authorization point. List: tools to
  install, git usage (isolation mechanism: worktree, branch, or none — none
  only at Tier 1; checkpoint commit cadence), files the gate will add **by
  path** (e.g. `tools/gate.sh`), and **every new dependency with a one-line
  justification** (prefer stdlib and deps already present; an unjustified
  package is a spec defect). Approving the spec authorizes all of it in one
  step.
- **Revisions** — append-only log. If implementation reveals the spec was
  wrong, say so explicitly and revise it visibly here — never silently drift.

## Phase 2 — SPEC REVIEW

Show the spec to the human in plain language and get approval **before
writing implementation**.

- **An answer to a question is not an approval.** If you asked the human to
  decide something, their answer is an INPUT that CHANGES the spec — any
  approval held before the question is approval of a document that no longer
  exists. Fold the answers in, say what changed, show the revised spec, ask
  again. If you cannot quote the words that approved THIS spec, you do not
  have approval.
- **If the spec is rejected**, revise the file in place, record the reason
  under Revisions, and re-request approval. Do not start a clean file — what
  the human turned down, and why, is the most useful thing in it.
- **Commit the spec at approval** (where repo conventions allow — the setup
  plan is where that was authorized). A committed spec makes later drift a
  literal `git diff`, and gives the gate its strongest intent source: a
  human-approved file with provenance, so intent status is `confirmed`
  instead of reconstructed.
- **Autonomous mode** (no human available): state the spec in your response
  and proceed, but the correlation-breaking review never happened — record
  `spec approval: not obtained (autonomous run)` and claim correspondingly
  lower confidence. The spec becomes the artifact reviewed after the fact.

## Phase 3 — IMPLEMENT (repeat per behavior)

### RED — prove each test can fail

Write the test for one behavior. **Run it and watch it fail** before writing
the implementation. A test you never saw fail proves nothing.

- If the module under test doesn't exist yet, create a stub that raises
  (e.g. `NotImplementedError`) so the test fails on behavior, not on import —
  a collection error is a weaker RED than an assertion failure.
- If a new test passes immediately, it is either vacuous (fix it) or the
  behavior already exists. Don't assert which — **prove it**: break the
  implementation with a one-off throwaway mutant, watch the test fail,
  restore. Record it as pre-existing behavior kept as regression armor.
- **Commit the failing test before the implementation** (under the
  spec-approved cadence). The gate later reads commit ordering as a git fact
  — tests committed before the code they cover turn your TDD discipline into
  durable, checkable evidence instead of a claim.

### GREEN — minimal implementation

Write the least code that makes the failing test pass. Run the **full
suite**, not just the new test. Commit at green.

### REFACTOR — clean up under green, assertions frozen

While the suite is green, improve names, extract duplication, simplify.
What is frozen is **behavioral assertions**, not test files wholesale:

- Implementation refactors touch no test files at all.
- Test-structure refactors (helpers, fixtures, dedup) are a **separate
  step**: assertions unchanged, suite green before and after.
- Anything that requires editing an assertion is not refactoring — it is a
  behavior change and belongs back in SPEC (with a Revisions entry and, if
  material, re-approval).

## Phase 4 — VERIFY (hand off to `verification-gate`)

When all spec behaviors are green, invoke the `verification-gate` skill. Do
not run the layers ad hoc and paste numbers — the skill owns the entry
point, the layer stack, and the report.

- Use `gate` iteratively while fixing failures; use `evidence` exactly once,
  after the last code edit, to produce the final report.
- Hand it: the base ref, the change set, the tier from the SPEC, and the
  committed SPEC path as the intent record. Point it at the spec file rather
  than letting it reconstruct intent from the conversation.
- **A failing gate blocks done.** You are not finished while any layer
  fails; if genuinely blocked, report the failure verbatim as the outcome.

## Phase 5 — INDEPENDENT VERIFICATION (Tier 3 option)

The gate is evidence, not self-authentication: its checkers can be unsound,
its mappings can overclaim, and the spec can be incomplete. Where a spec gap
would be expensive, dispatch the `verifier` agent (installed for both Claude
Code and Codex) against the finished work before EVIDENCE is finalized. The
verifier's own conduct lives in its agent definition; these are the
orchestration rules on your side:

- **Assemble exactly four inputs**: the task contract (the original request
  plus every human-approved change since), the approved SPEC, an exact
  source state (SHA or tree hash), and the gate entry point. Never the
  builder's conversation. Provide the draft evidence report only after the
  verifier returns its blind results.
- **Optional canary**: run the verifier once against an isolated copy with a
  planted defect it was not told about — never plant in the candidate. A
  missed canary voids that verdict; a caught one is a floor, not a
  capability proof.
- **The human grades findings.** Behavioural (the code does the wrong thing,
  or a gate cannot fail) → fix, then re-verify in a NEW verifier context.
  Description/mapping (a document says something untrue about correct code)
  → fix and disclose, no new round. You may propose a grade; the human
  decides disputed or material ones — self-grading fails open.
- **Cap at two rounds** by default; more needs explicit human approval,
  recorded. The cap does not limit the spending; it makes the spending
  someone's decision.
- **Verdicts attach to a source state.** A state no verifier saw is
  `not performed`, whatever earlier rounds concluded. A behavioural fix made
  after the final round ships an unverified state: record the downgrade and
  keep the earlier rounds as history.
- **Four states**: `passed` finalizes; `failed` and `blocked` do not;
  `not performed` finalizes only as a declared downgrade.
- **Where the verdict lands**: write it to `.gate/<scope>/verification.md`,
  beside the gate's evidence report — never into the report itself (the
  skill owns that file). Deliver both to the human together.

## Anti-Gaming Rules (absolute, bind through every phase)

1. **Never weaken a test to make it pass** — no broadened assertions, added
   skips, raised tolerances, or deleted failing tests. A wrong-looking test
   is a spec conversation; surface it.
2. **Never edit a test and the implementation in the same step to reach
   green.** Change one, run, then the other.
3. **Never mock the unit under test.** Mock boundaries (network, clock,
   filesystem), not logic.
4. **Never chase the coverage number.** Coverage detects untested code; it is
   not a target. Mutation testing exists to catch tests that assert nothing,
   including yours.
5. **Never report a layer you didn't run.** An honest skip preserves trust;
   an invented result destroys the entire scheme.
6. **Failing gate blocks done.**

## Discipline notes

- Baseline: on a repo with pre-existing failures, record the baseline first
  and hold the line at zero NEW failures. Fixing unrelated pre-existing
  failures is scope creep — surface them, don't silently "improve" them.
- Isolation: do not mutate the user's working tree to do the work. Declare
  the mechanism (worktree / branch / none) in the SPEC's setup plan so the
  human vetoes it at approval rather than discovering it afterwards.
