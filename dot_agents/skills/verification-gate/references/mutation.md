# Manual mutation procedure (any language, no tool)

**Reach for the project's mutation tool first.** A real tool generates mutants
from the syntax tree, so it cannot apply a mutant to code that has moved and it
cannot report a mutant it did not run.

That is not the same as being trustworthy about *kills*. A tool reports `caught`
when the suite failed while the mutant was applied, and attributes the failure
to the mutant; a flaky test, contention between the tool's own parallel jobs, or
a stale artifact produces the same `caught` with a wrong attribution. A flaky
test only inflates the score, so it can never make the gate red. Shared build
state between parallel jobs is worse — a job may test a binary another job
built, manufacturing both false kills and false misses, which leaves the whole
classification meaningless rather than merely optimistic.
**Tool-based runs therefore need the controls in SKILL.md's attribution note
too** — the unmutated baseline run repeatedly at the tool's own concurrency, and
a stated-size sample of kills re-verified one at a time. Both are cheap relative
to the mutation run itself.

Two notes on re-verifying a kill by hand, because getting this wrong produces a
false accusation rather than a finding: apply the mutant to the same source
state the tool used, and **run the same test command the tool ran**. Mutants are
frequently killed by tests in a *different* crate or package from the one they
mutate, so a re-check scoped to the mutated unit will show a survivor that the
full command kills. A disagreement between a tool run and a hand check is not
evidence about the tool until the scope of both is known to match.

A hand-written mutant list matched against source text is a second copy of the
code: it goes stale on every refactor of the thing it guards, and it fails in
the one direction no gate can catch. Use the procedure below when no tool exists
for the language, not as a default.

**A hand-rolled runner must prove it executed each mutant.** This is the sharp
edge, and the upstream project's own demo found it: two same-size mutants
written in the same second shared a bytecode cache, so the runner reported kills
for mutants it never executed. That class of defect can *only* inflate the
score, which means it can never surface as a red gate — the layer stays green
precisely because it is broken. Any runner written from this procedure needs a
guard of the equivalent kind (for CPython: disable bytecode writing, clear
`__pycache__` between mutants, and abort the run if it reappears), and EVIDENCE
should say which check proves execution.

Script this rather than hand-editing, and **persist the script in the repo**
(e.g. `tools/mutants.py`): it holds the original source, applies each mutant by
unique string replacement, runs the suite, and restores. Hand-editing N times
invites restore mistakes, and the EVIDENCE rule (all numbers from one final
fresh run) means you will run the mutants at least twice — a persisted script
makes the rerun free, the mutant list auditable, and the reported score
re-runnable by the human, which a scratch-directory script is not.

1. Pick the new/changed implementation code.
2. One at a time, introduce 3–5 plausible bugs, biased toward the logic that
   matters most:
   - flip a comparison (`<` → `<=`, `==` → `!=`)
   - off-by-one a loop bound or slice index
   - delete one branch of a conditional / remove an early return
   - swap `and`/`or`; negate a boolean
   - replace a returned value with a constant (`0`, `null`, `""`)
3. Run the test suite after each mutant. **Every mutant must make at least one
   test fail.** A surviving mutant means a missing or vacuous assertion — add
   the test that kills it, then continue.
4. Restore the original code (verify with `git diff` that only intended changes
   remain) and run the suite once more to confirm green.
5. Report as: "manual mutation: N/N killed".

## Exit-code discipline for a hand-rolled runner

Classify each mutant run by the test command's exit status, and treat anything
unexpected as an error that invalidates the round rather than as a result:

- test command reports failures → **killed**
- test command reports success → **survived**
- any other status (collection error, crash, timeout) → **ERROR**; the mutant
  proved nothing, and the round does not get reported as a score

## Negative control for the runner itself

The runner is a home-grown check, so the checker rules in SKILL.md apply to it.
Prove it can fail before trusting its pass: include a fixed control pair — one
mutant that must be killed and one deliberately equivalent mutant that must
survive — and assert the expected result of that pair on every run. A runner
that reports all-killed on the equivalent control is measuring nothing.
