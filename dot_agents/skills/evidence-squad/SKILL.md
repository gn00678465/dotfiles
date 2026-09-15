---
name: evidence-squad
description: >-
  Dispatch a bounded squad of 3–4 independent, read-only lenses at one of the
  evidence-first workflow's three point-cuts — after the spec draft, after the
  implementation is green, before the spec is archived — so findings one
  drafter cannot see about its own work reach the spec, the gate, or the close
  before the human does. Returns classed findings; adds no human stop; fixes
  nothing. Triggers: "deploy a squad", "evidence squad", "multi-lens review",
  "second opinion on this spec", "attack the draft", "squad before archive",
  「部署 squad」, 「多視角審查」, 「攻擊這份 spec」. Does NOT handle: the
  verification gate's layers (verification-gate), the independent verdict on
  a source state (the verifier agent), archiving (spec-archive), or any code
  or spec edit by the delegates.
---

# Evidence Squad

A single drafter cannot see its own spec's blind spots; this skill reads the
work with fresh contexts at three points and returns classed findings to the
orchestrator.

## The three point-cuts

| Cut | When | Question the squad answers | Where the findings go |
|---|---|---|---|
| **after spec** | Phase 2, a draft exists — `v0.x` before the first approval, the pending integer for a revision — before the durability preflight and the approval request | Does this draft cover the request's rules, the rules' input space, and the repo as it is? | Folded into the draft by the orchestrator. Anything that is a genuine decision rides the one approval request with a recommendation. |
| **after implement** | Phase 4, `verification-gate gate` passes every layer, before `evidence` | Does the code do what the spec says, all of it, and nothing else? | Class 1 → fix under the current version and re-run `gate`; class 2 → Revisions decision under the workflow's Versioning rule, batched re-approval; class 3 → Honest notes. |
| **before archive** | Phase 6, evidence written and any independent verification finalised, before `spec-archive` | Is the evidence true against git, and is closing this spec justified? | A class-1 finding or an uncorrected description finding blocks the close; otherwise `spec-archive` runs. |

Tier 1 skips all three cuts; Tier 2 and Tier 3 run all three. `spec-archive`
refuses to close a Tier 2 or 3 spec whose three records are not committed,
classed, and in order.

## Finding classes

Every finding is placed against the spec in one of three classes, and the
class fixes its disposition:

1. **Breaks a rule the spec states** (a scenario, a Must NOT) — a defect:
   fix under the current version, no new approval.
2. **Not in the spec, but a behaviour of this change** — a spec gap: it
   becomes a decision in Revisions under the workflow's Versioning rule — an
   unapproved draft and a pending revision both keep their number, so a
   review round never costs an integer — and it is put to the human once,
   batched with every other class-2 finding of the round.
3. **Outside this change** (pre-existing behaviour, dead code, another
   scope's defect) — it is recorded under Honest notes in the evidence
   report for the human to open a scope for; it is never fixed in passing.

A class-3 finding is reported but never blocks a cut unless a Must NOT
covers it. Without the class, class-2 and class-3 findings are placed by
improvisation each round, and a close fails on defects the spec never
claimed to fix.

## Lenses

Pick 3–4 per cut, complementary, never redundant. Each lens is a brief, not
a persona: the delegate is told what to look for and what evidence counts.

**After spec**
- *scope* — the draft against the original request and every approved
  change since: what it added that was not asked (appetite, no-gos), what it
  dropped, what it renamed. Cites the request's words.
- *input space* — every rule (decision, Must NOT) against its own
  dimensions: states it can fire in, orders its inputs can arrive in,
  nesting depths; names each empty cell. Cites the scenario table.
- *repo reality* — the draft's claims about existing code, reproduced: the
  reported defect at the base ref, prior attempts at the same job and why
  they died, wrong-by-default data, stale denormalisations. Cites file and
  commit.
- *test mapping* — can each scenario become a test that fails at the base
  ref; is each Must NOT a behaviour rather than a diff shape; is every count
  measured. Cites the scenario and the command that would measure it.

**After implement**
- *contract vs implementation* — each scenario's test against the code:
  assertions that cannot fail, weakened or skipped tests, a test and its
  implementation changed in one step, mocks over the unit under test.
- *live evidence* — the original reports and each scenario reproduced on
  the built artefact at the exact source state, not in the unit harness.
- *input space at code level* — the code's actual branches against the
  spec's cells: iteration order, insertion order, the state the code reads
  versus the state the rule names.
- *diff hygiene and scope* — hunks outside the spec, orphans the change
  made, files the setup plan did not list.

**Before archive**
- *evidence vs git* — every claim in the report checked against commits:
  RED before GREEN per behaviour, `spec_version` and `source_state` current,
  layers reported that actually ran.
- *mapping honesty* — scenario ↔ test mapping, over-claims, "seen red"
  claims per assertion.
- *verdict state* — `verification.md` consistent with the report; a
  `failed` or `blocked` verdict attached to the state being closed.
- *ledger completeness* — class-3 findings from earlier cuts recorded under
  Honest notes; no no-go quietly done.

## Dispatch

1. **Frame one question** from the table above and name the cut. A squad
   answers a question; it is not a vibe check.
2. **Give every delegate the same four inputs and nothing else**: the task
   contract (the request plus every approved change), the spec at its
   current version, an exact source state (SHA, or the draft's commit), and
   its lens brief. Never the orchestrator's conversation — the verifier
   agent's input shape, for the same reason: a delegate that reads the
   builder's reasoning inherits the builder's blind spot.
3. **Run them in parallel, read-only, fresh context.** Use the harness's
   subagent tool. A delegate may build and run; it edits nothing. Strong
   model tier for analytical lenses.
4. **Require non-fakeable output.** Each returns
   `[SEVERITY] file:line — finding — evidence — class 1|2|3 — recommendation`,
   then a verdict for its lens and an explicit concession of where the lens
   did not apply. A finding without a citation is dropped. A lens that
   concedes nothing is noise.
5. **Synthesise; never average.** Where two lenses disagree on a
   consequential point, adjudicate from the source, or dispatch one focused
   second-opinion delegate with the two positions and the same four inputs.
   What is still irreconcilable becomes a decision with a recommendation:
   at the after-spec cut it goes into the approval request; at the later
   cuts into the evidence report's honest notes. It never becomes a separate
   question to the human.
6. **Record and act.** Write the merged findings to
   `.scratch/<scope>/squad/<after-spec|after-implement|before-archive>.md`
   and commit it with the phase it belongs to. One bullet per finding,
   `- [SEVERITY] file:line — finding — evidence — class N — recommendation`,
   and `— status: fixed` appended to a class-1 bullet once it is fixed:
   `spec-archive` parses these. Then act by class; the orchestrator edits,
   the delegates never do.

## Invariants

Bounded (3–4) · four inputs, no conversation · read-only delegates ·
cited findings with a class · no averaging · no added human stop ·
never a gate in its own right.
