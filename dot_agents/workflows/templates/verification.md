# Independent Verification — <task name>

Orchestrator-owned aggregate, written to `.gate/<scope>/verification.md`
beside the gate's evidence report — never into it. Per-round reports below
are the verifier's verbatim output; everything else is the orchestrator's.

- `final_source_state`: <!-- SHA | tree hash — the state that ships -->
- `final_verdict`: <!-- passed | failed | blocked | not performed. A state no
  verifier saw is `not performed`, whatever earlier rounds concluded —
  declare the downgrade, never inherit a previous verdict -->
- `rounds_run`: <!-- n (cap m); rounds beyond the cap approved by: <verbatim
  quote | n-a> -->
- `verifier`: <!-- host / model family; fresh context per round: yes | no.
  Correlation broken: task context. Not broken: model, when builder and
  verifier share one -->
- `inputs_given`: <!-- task contract, approved SPEC @ <version>, source
  state, entry point — and nothing else; disclose any contamination -->
- `canary`: <!-- caught | MISSED — that round's verdict is void | not run -->

## Rounds

| Round | Source state | Verdict | Behavioural findings | Description/mapping findings |
|---|---|---|---|---|
| 1 | <SHA> | <passed \| failed \| blocked> | <n, listed below> | <n, listed below> |

## Grading record

The human grades material or disputed findings; the builder may propose.
Behavioural → fix, then re-verify in a NEW verifier context. Description /
mapping → fix and disclose, no new round.

- <finding> — graded <behavioural | description> by <human | proposed,
  undisputed> — <resolution>

## Fixed after the last verified state (therefore unverified)

- <list | none>

## Per-round reports (verifier's verbatim output)

<!-- append each round's report unmodified; the verifier protocol owns its
format -->
