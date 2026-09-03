# Evidence-First Reference Implementation

The reference implementation of the evidence-first contract — follow it when
no workflow tool fits. The human will NOT read the implementation. Their
confidence comes entirely from two artifacts: the **SPEC** they approve
before code exists (owned by this workflow), and the **EVIDENCE** report
proving the code ran the gate (owned by the `verification-gate` skill). This
file owns the front half of the loop; the skill owns the back half.

```
SPEC → SPEC REVIEW (human approves spec, not code)
     → per behavior: RED → GREEN → REFACTOR
     → verification-gate: `gate` (iterate while fixing) → `evidence` (final, once)
     → Tier 3 option: independent verification (`verifier` agent)
     → after merge: CLOSE (`spec-archive` skill)
```

## Phase 1 — SPEC

Before touching any implementation file, turn the request into **executable
acceptance criteria** in a spec file, committed to the repo at
`specs/<scope>/SPEC.md` — this path is fixed, not a suggestion: the
`spec-archive` skill hardcodes it, so a spec filed anywhere else cannot be
closed and, worse, its `--check` safety net reports clean forever instead of
flagging the miss. `<scope>` is the feature slug, and the only free part of
the path. Template at `templates/spec.md` beside this file. Show the human
its absolute path.

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
- **Approval** — append-only record of the structured act that approved each
  spec version: the approving words verbatim, the date, and the version they
  bind. Filled at SPEC REVIEW and committed with the spec.
- **Revisions** — append-only log. If implementation reveals the spec was
  wrong, say so explicitly and revise it visibly here — never silently drift.
  A revision invalidates prior approval: bump the version, set `status` back
  to `revised-pending-approval`, and re-request.

## Phase 2 — SPEC REVIEW

Two stages, in this order: explore until nothing is silently assumed, then
sign. Both happen **before writing implementation**.

### Review surface — render the spec for the human

Put the spec in front of the human as a rendered HTML review page whenever a
review surface is available — a wall of markdown in a terminal taxes human
attention and hides gaps. The surface is the `reviewable-html-workbench`
plugin (Claude Code and Codex both: block-anchored comment threads,
mechanical three-state turn-taking, a resolution gate that blocks edits
while any thread awaits a reply). Not installed? Suggest installing it and
fall back to plain terminal — never hand-roll a review page: an improvised
page burns tokens, has no comment channel back to you, and drifts from the
spec. When building the document model, declare `metadata.lang` (any
non-`ja` value, e.g. `zh-Hant`) — the plugin's review UI defaults to
Japanese on every machine, and this field is what switches its chrome to
English; the document body stays in whatever language you wrote. The surface changes only where the
conversation happens, never where authority lives: comments are exploration
INPUTs (one thread per scenario; every thread resolved = the frontier is
empty), and approval still lands as the verbatim quote committed into
`## Approval` — a web page is a capture interface, not a record.

### Exploration — empty the frontier first (recommended at Tier 2+)

Walk the draft spec as a design tree: every decision (the tier, each
scenario's boundaries, each Must NOT, each setup-plan choice) branches into
the decisions that hang off it. Work it in rounds — the frontier is every
decision whose prerequisites are already settled; ask the whole frontier at
once, each question with a recommended answer; fold the answers into the
spec and record each round's settled decisions under Revisions. Facts are
your job, never the human's: look up (or dispatch a subagent for) anything
the environment can answer, and put only decisions to the human. Exploration
ends when the frontier is empty — nothing left silently assumed. Bump the
spec version once at the end, not per round.

### Signing — the structured act

Show the final spec to the human in plain language and get approval.

- **An answer to a question is not an approval.** If you asked the human to
  decide something, their answer is an INPUT that CHANGES the spec — any
  approval held before the question is approval of a document that no longer
  exists. Fold the answers in, say what changed, show the revised spec, ask
  again. If you cannot quote the words that approved THIS spec, you do not
  have approval. The recommended-option shape makes this easy to get wrong:
  when the human picks the options you recommended, the spec looks unchanged
  and consent looks implied, and neither is true.
- **Approval is a structured act bound to one spec version, not a parsed
  phrase.** Request it with an explicit structured prompt whose question
  names the version being approved; quote the selection verbatim into the
  spec's `## Approval` section (words, date, version bound), flip `status`
  to `approved`, and commit both in one act (the setup plan is where that
  was authorized). The flip is not bookkeeping: `spec-archive` refuses any
  other status at CLOSE, so a spec approved but left at `draft` records
  consent it cannot act on. A committed,
  human-approved spec makes later drift a literal `git diff`, makes the
  gate's `intent_status: confirmed` mechanically readable from git, and
  survives compaction, which the conversation does not.
- **If the spec is rejected**, revise the file in place, record the reason
  under Revisions, and re-request approval. Do not start a clean file — what
  the human turned down, and why, is the most useful thing in it.
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
- Related behaviors may share one RED run, as long as each new test is
  individually observed failing.
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
  step**: assertions unchanged, suite green before and after, then rerun
  mutation to confirm the restructured tests still kill — a refactor that
  blunts the tests is a silent hole in the gate.
- Anything that requires editing an assertion is not refactoring — it is a
  behavior change and belongs back in SPEC (with a Revisions entry and, if
  material, re-approval).

### Delegated implementation (Tier 2+ option)

The RED→GREEN→REFACTOR loop may run in an **implementor subagent** so its
tool output does not consume the orchestrator's context. The contract
survives this split by design — verification reads git, never the
conversation — on three conditions:

- **Per-step commit cadence, spec-approved.** Each behavior lands as a RED
  commit (tests only) followed by a GREEN commit (implementation only),
  declared in the SPEC's setup plan so approval authorizes the cadence.
  This is what turns anti-gaming rule 2 (temporal, otherwise traceless)
  into a git-readable invariant.
- **Hand off commits, not narration.** The subagent receives the approved
  SPEC path, the base ref, an isolated worktree, and the gate entry point —
  never the orchestrator's conversation (the verifier's four-input shape).
  It returns a commit SHA per behavior; treat everything else it says as
  unverified narration and let the gate verify — RED reconstruction catches
  a vacuous test behind a claimed RED.
- **Split only when it pays.** A subagent re-reads the spec and codebase
  from scratch, so total tokens go up; what the split buys is the
  orchestrator's context. Delegate multi-behavior Tier 2+ work; keep Tier 1
  and single-behavior changes in-session.

On a gate failure, send the failing output back to the same subagent
verbatim (resume its context rather than re-briefing); after three rejected
rounds, escalate to the human. Delegation does not replace Tier 3
independent verification — implementor and orchestrator share a model, so
the verifier's fresh context stays necessary.

## Phase 4 — VERIFY (hand off to `verification-gate`)

When all spec behaviors are green, invoke the `verification-gate` skill. Do
not run the layers ad hoc and paste numbers — the skill owns the entry
point, the layer stack, and the report.

- Use `gate` iteratively while fixing failures; use `evidence` exactly once,
  after the last code edit, to produce the final report.
- Hand it: the base ref, the change set, the tier from the SPEC, the
  committed SPEC path as the intent record, and **the SPEC's `<scope>` as the
  gate's `scope`** — never leave it to reconstruct intent from the
  conversation. The gate otherwise infers `scope` from the branch name, which
  on a worktree or a prefixed branch differs from the SPEC's slug; the
  evidence report then files under a name that does not match
  `specs/<scope>/`, and Phase 5's "beside the evidence report" resolves to a
  different directory.
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
- **Input hygiene decides verifier noise.** Point it at the repository root
  (never a subdirectory) of an isolated, clean copy at the stated source
  state — a polluted tree (stale editable install, cached artifacts) or a
  partial checkout produces false positives that read like findings. The
  isolated copy also enforces "fixes nothing" by construction: the
  verifier's tools can write, the copy makes that harmless.
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
- **Where the verdict lands**: write it to `.gate/<scope>/verification.md`
  (aggregate template at `templates/verification.md` beside this file),
  beside the gate's evidence report — never into the report itself (the
  skill owns that file). Per-round reports are the verifier's verbatim
  output; the aggregate is yours. Deliver both to the human together.

## Phase 6 — CLOSE (before merge: the branch's last commit; Tier 3: after verification finalizes)

A shipped spec is an immutable intent record, not a living constraint — the
living truth moved into the tests. Invoke the `spec-archive` skill on the
feature branch once the gate's final `evidence` is in (Tier 3: once
independent verification has finalized): it flips `status` to `shipped`,
moves the spec to `specs/archive/<scope>/`, and commits — mechanically, fail
closed. That commit is the last one before the merge, so the PR carries the
shipped spec and the default branch never holds an `approved` one; `--check`
run there treats any candidate as a skipped close. Never move or edit the
spec files by hand in its place.

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
