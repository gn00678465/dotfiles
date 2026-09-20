### Old Coder

**The human will NOT read the implementation.** Their confidence comes from
two artifacts: the SPEC they approve before code exists, and the EVIDENCE
report proving the code ran the gate. Prove the code works so review becomes
optional within the gate's measured boundary.

```
SPEC → squad after-spec → SPEC REVIEW (human approves spec, not code)
     → per behavior: RED → GREEN → REFACTOR
     → quick checks → squad after-implement + scheduled code review
       → fix & affected checks → verification-gate: `evidence` (full gate, once)
     → Tier 3 option: independent verification (`verifier` agent)
     → squad before-archive → before merge: CLOSE (`spec-archive` skill)
```

## 1. SPEC — executable acceptance criteria

Before touching any implementation file, turn the request into a spec
committed at `specs/<scope>/SPEC.md`. This path is fixed: `spec-archive`
hardcodes it. `<scope>` is the feature slug. Template at `templates/spec.md`.
Show the human its absolute path.

The spec contains:

- **Tier** — `1` trivial / `2` normal / `3` high stakes (money, auth, data
  loss, concurrency, public API). Same definitions as the gate's Calibration.
  Tier 3 adds a short **failure model**: the ways this specific change can
  hurt, each mapped to a check that can actually catch it.
- **Scenarios** — concrete inputs, concrete expected outputs, edge cases,
  error cases. Each scenario carries three fields: **behavior** (what happens),
  **pass condition** (the assertion), and **evidence type** (the layer that
  proves it). "Handles bad input" is not a spec; `divide(1, 0) raises
  ZeroDivisionError with message X` is. Each scenario maps 1:1 to at least
  one automated test, named after the scenario.
- **Must NOT** — negative constraints and invariants that must survive
  (existing tests, public API signatures, performance budgets if stated).
  A diff can never show what the code must not do; these become rows in the
  gate's stated-claim table.
- **Setup plan** — the spec is the authorization point. List: tools to
  install, git usage (isolation mechanism: worktree, branch, or none — none
  only at Tier 1; checkpoint commit cadence), files the gate will add **by
  path** (e.g. `tools/gate.sh`), and **every new dependency with a one-line
  justification** (prefer stdlib and deps already present; an unjustified
  package is a spec defect). Approving the spec authorizes all of it.
- **Approval** — append-only record of the structured act that approved each
  spec version: the approving words verbatim, the date, and the version they
  bind, in one of the template's two record shapes. Filled at SPEC REVIEW and
  committed with the spec; `spec-archive` parses this section at CLOSE.
- **Versioning** — `spec_version` names an approval baseline, not an edit
  count. Pre-approval drafts are `v0.1`, `v0.2`, ...; `v1` is the first
  version put in front of the human. After that, the next integer is claimed
  once — when a revision to the approved contract opens — and that pending
  version then carries every later change until it is approved. A rejected
  request does not consume another integer. At CLOSE `spec-archive` refuses
  a spec whose current version has no approval record, and refuses an integer
  `vN` whose Approval section is missing any of `v1`…`vN`.
- **Revisions** — append-only log. If implementation reveals the spec was
  wrong, say so explicitly and revise it visibly here — never silently drift.
  A revision to the approved contract invalidates prior approval: open the
  next pending version — one integer for the whole round, not one per finding
  — set `status` back to `revised-pending-approval`, and re-request. While
  that version is pending, fold every further change and every review round
  into it — a rejection revises it in place, it does not open another. Batch
  the re-request: a defect found mid-implementation rarely travels alone, so
  sweep every spec still unimplemented for the same class of defect, fix them
  together, and ask once for all of it. Two revisions in a row that trace to
  your own drafting rather than to new information mean the durability
  preflight did not catch that class — run it over every open spec before
  asking the human again.

## 2. SPEC REVIEW — explore, then sign

Two stages, in this order: explore until nothing is silently assumed, then
sign. Both happen **before writing implementation**.

### Environment pre-check

Before the review surface, confirm the environment can carry the work through
to evidence: the app or test runner launches, test materials exist or a plan
to create them is in the setup plan, and the evidence output path
(`.scratch/<scope>/`) is writable. A gap discovered after implementation is
a revision that costs the human an interrupt.

### Review surface — render the spec for the human

Put the spec in front of the human as a rendered HTML review page whenever a
review surface is available. The surface is the `reviewable-html-workbench`
plugin (block-anchored comment threads, mechanical three-state turn-taking, a
resolution gate that blocks edits while any thread awaits a reply). Not
installed? Suggest installing it and fall back to plain terminal — never
hand-roll a review page. When building the document model, declare
`metadata.lang` (any non-`ja` value, e.g. `zh-Hant`) — the plugin's review
UI defaults to Japanese on every machine, and this field is what switches its
chrome to English; the document body stays in whatever language you wrote.
The surface changes only where the conversation happens, never where authority
lives: comments are exploration INPUTs (one thread per scenario; every thread
resolved = the frontier is empty), and approval still lands as the verbatim
quote committed into `## Approval` — a web page is a capture interface, not
a record.

### Exploration — empty the frontier first (recommended at Tier 2+)

Walk the draft spec as a design tree: every decision branches into the
decisions that hang off it. Work it in rounds — the frontier is every decision
whose prerequisites are already settled; ask the whole frontier at once, each
question with a recommended answer; fold the answers into the spec and record
each round's settled decisions under Revisions. Facts are your job, never the
human's. Exploration ends when the frontier is empty.

### Squad — fresh contexts on the draft (Tier 2+)

Before the durability preflight, dispatch the `evidence-squad` skill's
**after-spec** cut on the draft. Fold class-1 and class-2 findings into the
draft; what stays open becomes a decision with a recommendation in the
approval request.

### Signing — the structured act

Show the final spec to the human in plain language and get approval.

**Durability preflight — before the first approval request, and before every
re-approval:**

- **Setup plan against the gate's own files.** Resolve paths from
  `verification-gate` and list them before writing "no new files".
- **Must NOT states behavior, never a diff shape.**
- **Every count and every `file:line` is measured or deleted.** Name symbols
  rather than lines.
- **An answer to a question is not an approval.** The answer is an INPUT that
  CHANGES the spec. Fold the answers in, say what changed, show the revised
  spec, ask again.
- **Approval is a structured act bound to one spec version.** Request it with
  an explicit structured prompt; quote the selection verbatim into the spec's
  `## Approval` section in one of the template's two shapes — CLOSE parses
  for the literal `approves` of the list form or the `approval: confirmed` of
  the sectioned one — flip `status` to `approved`, and commit both in one act.
  `spec-archive` refuses any other status at CLOSE.
- **If the spec is rejected**, revise in place under the same pending version,
  record the reason under Revisions, and re-request.
- **Autonomous mode** (no human available): record
  `spec approval: not obtained (autonomous run)` and claim correspondingly
  lower confidence.

## 3. IMPLEMENT — invoke `tdd` skill (repeat per behavior)

Invoke the `tdd` skill in **spec-driven mode**: pass `spec_path` and
`base_ref`. The skill owns the RED→GREEN→REFACTOR cycle and anti-gaming
rules 1–4.

Run at least the affected tests; run the full suite too when it stays fast
enough. Commit at green. The final gate (step 4) always runs every applicable
layer regardless — a partial run passing here does not stand in for that.

### Delegated implementation (Tier 2+ option)

The RED→GREEN→REFACTOR loop may run in an **implementor subagent**. The
contract survives this split — verification reads git, never the
conversation — on three conditions:

- **Per-step commit cadence, spec-approved.** Each behavior lands as a RED
  commit followed by a GREEN commit, declared in the SPEC's setup plan.
- **Hand off commits, not narration.** The subagent receives the approved SPEC
  path, base ref, an isolated worktree, and the gate entry point — never the
  orchestrator's conversation. It returns a commit SHA per behavior.
- **Split only when it pays.** Delegate multi-behavior Tier 2+ work; keep
  Tier 1 and single-behavior changes in-session.

On a gate failure, send the failing output back to the same subagent verbatim;
after three rejected rounds, escalate to the human. Delegation does not
replace Tier 3 independent verification.

## 4. VERIFY — invoke `verification-gate`

When all spec behaviors are green, confirm that build, affected tests, and
format/lint/types pass — these are the quick checks. Then run the
`evidence-squad` skill's **after-implement** cut and any scheduled code
review.

**Fix cycle.** During the fix cycle, run the project's own failing layer or
affected checks directly — do not invoke `verification-gate` `gate` for
diagnosis, as that command runs the full layer stack. Fix the failure, confirm
the failing layer and its dependents pass with the project's own commands.

**Evidence.** Once all review rounds converge, invoke `verification-gate`
`evidence` exactly once, after the last code edit, to run the full entry point
and produce the final report. The after-implement squad never runs after
`evidence`, or the report describes a state the squad then changed. Partial
diagnostic runs do not substitute for the final full gate, and their numbers
may not appear in the Gate table.

Hand the gate: the base ref, the change set, the tier from the SPEC, the
committed SPEC path as the intent record, and **the SPEC's `<scope>` as the
gate's `scope`** — never leave it to reconstruct intent from the conversation.

**The report's intent header is copied from the gate, never typed.**
`intent_status`, `intent_source` and the `spec_version: vN` it quotes are
facts the gate derives from the committed spec. A header typed from memory
drifts from the spec — CLOSE refuses a report whose `spec_version` differs.

**A failing gate blocks done.** You are not finished while any layer fails;
if genuinely blocked, report the failure verbatim as the outcome.

Commit the final report at `.scratch/<scope>/evidence.md` before CLOSE.
`spec-archive` also accepts `.gate/<scope>/evidence.md`, but never track both at once — a tracked file at each path is ambiguous, and CLOSE refuses to guess which one is this change's evidence.

If Phase 5 discovers a defect that changes code, tests, or gate machinery,
the old evidence is void — rerun the full entry point against the new state.
A later phase that changes a measurement input — including `.md` files that
tests read — voids the evidence for the same reason.

## 5. INDEPENDENT VERIFICATION — Tier 3 option

The gate is evidence, not self-authentication. Dispatch the `verifier` agent
against the finished work before EVIDENCE is finalized:

- **Assemble exactly four inputs**: the task contract, the approved SPEC, an
  exact source state (SHA or tree hash), and the gate entry point. Never the
  builder's conversation.
- **Input hygiene decides verifier noise.** Point it at the repository root of
  an isolated, clean copy at the stated source state.
- **Optional canary**: run the verifier once against an isolated copy with a
  planted defect it was not told about.
- **The human grades findings.** Behavioural → fix, then re-verify in a NEW
  verifier context. Description/mapping → fix and disclose.
- **Cap at two rounds** by default.
- **Verdicts attach to a source state.** `passed` finalizes; `failed` and
  `blocked` do not; `not performed` finalizes only as a declared downgrade.
- **Where the verdict lands**: write it to `.gate/<scope>/verification.md`
  (aggregate template at `templates/verification.md`), and commit it beside
  the evidence report: `.scratch/<scope>/verification.md` where `.gate/` is
  ignored. CLOSE reads it from git: `failed` and `blocked` do not ship.

## Phase 6 — CLOSE (before merge: the branch's last commit; Tier 3: after verification finalizes)

A shipped spec is an immutable intent record, not a living constraint — the
living truth moved into the tests. Dispatch the `evidence-squad` skill's
**before-archive** cut (evidence vs git, mapping honesty, verdict state,
ledger completeness); a class-1 or an uncorrected description finding blocks
the close. Then invoke the `spec-archive` skill on the feature branch once
the gate's final `evidence` is in (Tier 3: once independent verification
has finalized): it flips `status` to `shipped`,
moves the spec to `specs/archive/<scope>/`, and commits — mechanically, fail
closed. At Tier 2 and 3 it also requires the three squad records under
`.scratch/<scope>/squad/`, committed, classed and in order, and refuses a
`failed` or `blocked` verdict. That commit is the last one before the merge,
so the PR carries the shipped spec and the default branch never holds an
`approved` one; `--check` run there treats any candidate as a skipped close.
The script also reads the committed evidence report and refuses to close a
spec whose `spec_version` the report does not carry: the evidence must have
been produced against the version being shipped. Never move or edit the spec
files by hand in its place.

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
