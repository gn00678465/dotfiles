# SPEC — <task name> (Tier <1|2|3>)

- `spec_version`: <!-- v1, v2, ... — bump on every content change; a bump
  invalidates prior approval -->
- `status`: <!-- draft | approved | revised-pending-approval -->
- `tier`: <!-- 1 trivial / 2 normal / 3 high stakes (money, auth, data loss,
  concurrency, public API) — same definitions as the gate's Calibration; the
  tier declared here is the tier the gate runs at -->

## Scenarios

Concrete inputs, concrete expected outputs, edge cases, error cases.
"Handles bad input" is not a scenario; `divide(1, 0) raises
ZeroDivisionError with message X` is. Each scenario maps 1:1 to at least one
automated test named after it, so the evidence report's mapping is
mechanical.

- <scenario name>: given <concrete input>, expect <concrete output>

## Must NOT

Negative constraints and invariants that must survive (existing tests,
public API signatures, performance budgets if stated). A diff can never show
what the code must not do; these become rows in the gate's stated-claim
table.

- Must NOT: <constraint>

## Failure model (Tier 3 only)

The ways this specific change can hurt, each mapped to a check that can
actually catch it. Delete this section at Tier 1–2.

| Failure mode | Check that catches it |
|---|---|
| <e.g. race condition on X> | <e.g. stress test Y under -race> |

## Setup plan

The spec is the authorization point — approving it authorizes everything
listed here in one step.

- Tools to install: <list | none>
- Git isolation: <worktree | branch | none (Tier 1 only)>; checkpoint commit
  cadence: <e.g. at spec approval and each GREEN/REFACTOR>
- Files the gate will add, by path: <e.g. `tools/gate.sh`>
- New dependencies, each with a one-line justification (prefer stdlib and
  deps already present; an unjustified package is a spec defect):
  <list | none>

## Approval

Append-only. One entry per approved version: the approving words verbatim,
the date, and the `spec_version` they bind. An entry you cannot quote is an
approval you do not have — an answer to a question is not one.

- <date> — approves <spec_version> — "<verbatim approving words>"
- <!-- or: `approval: not obtained (autonomous run)` -->

## Revisions

Append-only. If implementation reveals the spec was wrong, revise visibly
here — never silently drift. What the human turned down, and why, stays on
record. Exploration rounds land here too: one entry per round, listing the
decisions that round settled.

- <date> — exploration round <n>: <decisions settled>
- <date> — <what changed and why>
