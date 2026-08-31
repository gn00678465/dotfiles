---
name: verification-gate
description: Use after code is written, when a change needs verifiable evidence instead of a claim that it works. Runs a constraint stack of executable layers (tests, types, lint, changed-line coverage, mutation, property-based tests, real execution, supply chain, suite health) against a change set, reconstructs RED for the new tests from the base ref, and ends with an evidence report the human can trust without opening a single source file. Use when the user asks to verify, prove, gate, or hand off finished work, or when the change touches money, auth, data loss, concurrency, or a public API. Not a code review skill — it does not read code looking for defects.
---

# Verification Gate

The human will NOT read your implementation. Their confidence comes entirely
from the **evidence report** you produce, proving the code ran the gate. Your
job is to make that report trustworthy enough that line-by-line review becomes
optional within the boundaries of what the gate actually measured.

This inverts the normal review model: **trust moves from inspection to
constraints.** Be honest about what that buys: the gate turns the constraints
the stated intent expresses into executable evidence — it cannot show the
stated intent expresses everything that matters, and it is not
self-authenticating, because a checker can be unsound and a mapping can claim
more than it demonstrates.

Upstream, `old-coder` closes the first gap with a spec the human approves
**before** code exists — the one artifact that breaks the
everything-authored-by-the-same-agent correlation. This skill runs after the
code is written, so that artifact may not exist. What replaces it is the
acquisition step below: read git for facts, ask the human once for intent, and
record honestly which of the two you got. Every shortcut you take against the
gate destroys the only basis of trust.

## Scope Boundary

This skill **does not review code**. It does not look for defects, does not
rank findings, and does not propose fixes. It runs checks and reports results.

One named exception: the **capability diff** in the supply-chain layer. It is
scoped mechanically so it cannot drift into review — read the *declared*
surface only (import/require/use statements, dependency manifests, build
scripts, CI permissions, declared platform capabilities), diff it against the
base ref, and report what the change started declaring. Do not read function
bodies, do not judge whether a capability is used correctly, and do not rank
what you find. An undeclared capability reached through reflection or dynamic
loading is outside this layer — say so in the structural blind spot rather than
going looking for it.

When a review workflow is also in play (a human reviewer, a PR review bot), the
division is fixed: the review workflow owns
finding defects and deciding what to fix; this skill owns demonstrating that
the resulting change holds up. Do not run two parallel workflows. This skill
never reads or writes another workflow's artifacts; a review workflow's output
is one valid *source* of stated intent, never a required input.

## Commands

- `scaffold`: create or repair the gate entry point and its helper scripts in
  the target repository. Writes to product paths — always confirm first.
- `gate`: run the layers against the change set and report results. Iterative;
  use while fixing. Does not write an evidence report.
- `evidence`: run the entry point once and write the evidence report from that
  single run. This is the final step.

If the user does not specify a command, infer it: no entry point in the repo →
`scaffold`; entry point exists and the user wants results → `gate`; the user
wants a report, a handoff, or "prove it" → `evidence`.

## Inputs

Resolve or ask for these before doing work:

- `change_set`: what to verify. Working tree, `<base>...HEAD`, a commit range,
  or a PR. Default: uncommitted changes if any exist, otherwise `main...HEAD`,
  then `master...HEAD`.
- `base`: the ref the change is measured against. Needed for the changed-unit
  list, the baseline run, and RED reconstruction.
- `intent`: what the change was supposed to do. See Acquisition.
- `tier`: `1`, `2`, or `3`. See Calibration. Infer and state it; the human may
  override.
- `entry_point`: the single command that reruns every layer. Default: discover
  it in the repo, otherwise `scaffold` one.
- `artifact_root`: default `.gate/`.
- `scope`: subfolder name under `artifact_root`. Infer from branch name, PR
  title, or a short sanitized summary of the change.
- `report_language`: default `auto`, meaning follow the user's prompt language.

## Acquisition

The gate runs at a point that may be far from where the code was written: a
later session, a different agent, a subagent whose context is gone, or the far
side of a context compaction. It therefore takes **nothing on trust from the
conversation.** This mirrors a rule the upstream skill already applies to its
verifier, which receives an exact source state and an approved spec as inputs
and is told: never your conversation.

### From git — facts, as far as the repository can supply them

Settle all of this before asking the human anything:

| Fact | How |
|---|---|
| Change set | `git diff <base>...HEAD`, or the working tree diff |
| Changed units | derive from the diff: added/modified/deleted functions, methods, branches, exported symbols, config keys, endpoints, migration steps |
| Intent as recorded at the time | `git log <base>..HEAD` — commit messages are timestamped, authored when the code was written, and outside any transcript |
| Ordering | whether test files were committed before the implementation they cover |
| Baseline | check out `base` in a worktree and run the suite: which tests already failed before this change |
| Source state | `git rev-parse HEAD`, or a source-tree hash when git is absent |
| Spec provenance | `git log --diff-filter=A -- <path>` for any spec-like file, to see when it entered history |

None of this requires the original session. Compaction, subagent boundaries,
and session changes do not affect it. What *does* affect it is the repository
itself, so check that before leaning on it rather than after: `base` must
resolve to a commit that exists locally (`git cat-file -e <base>^{commit}`), and
history must not be truncated (`git rev-parse --is-shallow-repository`, and no
grafts). A shallow CI checkout, an unfetched base branch, or a repository with
no commits yet each silently removes the baseline, the ordering fact, and RED
reconstruction — the three facts the report leans on hardest. Fetch what is
missing (`git fetch --unshallow`, `git fetch origin <base>`) before downgrading
anything; a fetchable fact is not a missing one.

### Git facts status

Record one of these in the report header. Never promote one silently:

- `complete` — every fact in the table above was established from this
  repository.
- `partial` — the repository exists but could not supply some of them, and
  fetching did not fix it. Name each missing fact and its consequence:
  - no **baseline** → the suite layer cannot claim "zero NEW failures". It may
    report its own absolute pass/fail count and nothing more, and the Gate table
    says so; a pre-existing failure and one this change introduced are
    indistinguishable without the base run.
  - no **ordering** → whether the tests preceded the implementation is unknown,
    which is not the same as "no".
  - no reachable **base** → RED reconstruction is `not performed`, and Table 1's
    changed-unit list falls back to whatever diff is available (typically the
    working tree), a narrower claim than `<base>...HEAD`.
- `unavailable` — not a git repository. See Setup: stop before claiming any
  provenance.

Like intent status, `partial` does not block the gate: the executable layers ask
whether the code is self-consistent, and that needs no history. What degrades is
every claim measured **against the base**, and the report names which ones.

The statuses interact, and truncated history is the case where it bites: the
source-state computation is required to refuse a truncated repository rather
than emit a weakened state (`references/entry-point.md`), so a shallow checkout
is normally `git_facts: partial` **and** `reproducibility: not reproducible` at
once — and the second of those may not be presented as a passed gate. That is
the reason fetching is the first move here and not the last resort.

### From the human — intent and authority

Ask **once**, after git has been read, and ask with the derived answer already
filled in so the human is confirming rather than composing:

> From git, this change does A, B, C. The commit messages say "<...>".
> What was this change supposed to accomplish? Is there a spec, issue, or PR I
> should read instead? Are there constraints it must **not** violate?

A confirmation, a correction, or a path are all useful replies. Record the
reply verbatim in the report.

This question is not a formality. A human can spot a missing claim without
reading a single line of code — "you said it handles retry, what about the
timeout path?" — and it is the only mechanism in this skill that breaks the
correlation between the code's author and the intent it is checked against.

Prefer artifacts the human points at over anything reconstructed: a spec file
in the repo, `gh issue view <n>`, `gh pr view <n>`. An issue or PR body is
human-authored, timestamped, attributable, and outside the agent's context — a
stronger source than anything in a transcript.

### Never from the conversation

Do not treat conversation history, a compaction summary, or a subagent's return
message as the intent record. When context is thin an agent does not fail, it
**reconstructs**, and a reconstruction is indistinguishable from the real thing
in the finished report. Worse, the reconstruction is derived from the code that
was already written, so it describes what the code does rather than what it
should do, and every mapped row passes trivially.

If the conversation is the only lead, write it down as a proposal, show it to
the human, and use their answer. Unconfirmed, it is not intent.

### Intent status

Record one of these in the report header. Never promote one silently:

- `confirmed` — the human confirmed the intent this run, or pointed at a spec,
  issue, or PR that states it.
- `unconfirmed` — non-interactive run (CI, cron, headless). Intent derived from
  git only.
- `absent` — git yields no usable intent and no one is available to ask.

`unconfirmed` and `absent` do not block the gate. Every executable layer runs
regardless; those layers ask whether the code is self-consistent, which needs no
intent at all. What degrades is the mapping, and the report says so — the same
honest downgrade the upstream skill records as
`spec approval: not obtained (autonomous run)`.

## Calibration

Scale effort to blast radius, and say which tier you chose:

- **Tier 1 — trivial** (typo, comment, config value): full suite + lint. No new
  tests required, but state why the change is untestable or already covered.
- **Tier 2 — normal** (bug fix, small feature): every always-on layer, plus both
  mapping tables. Bug fixes MUST carry a test that fails against the base ref —
  the fix is not done until yesterday's bug is tomorrow's regression test.
- **Tier 3 — high stakes** (money, auth, data loss, concurrency, public API):
  start with a short **failure model**: list the ways this specific change can
  hurt (race condition, partial write, hostile input, overflow, unbounded
  growth, failed rollback…), and for each mode add a layer that can actually
  catch it — race/stress tests for concurrency, fuzzing for parsers, rollback
  rehearsal for migrations, benchmarks for latency budgets, API-compatibility
  checks for public libraries, contract tests for service boundaries,
  logging/metric assertions where silent production failure is a mode (full
  menu in `references/layers.md`). Mutation and coverage cannot substitute for
  these; the generic gate is the floor, not the ceiling. Then: property-based
  tests + mutation testing (tool-based if available) + adversarial pass — one
  explicit step trying to break the implementation with hostile inputs before
  declaring done. Failure modes deliberately not covered go in EVIDENCE as
  known limits. The adversarial pass shares the blind spots of whoever runs it.

## The Layers

Run every applicable layer. Scale to the task (see "Calibration"), but never
skip a layer silently — if a layer doesn't apply or a tool is unavailable,
record that in the evidence report with the reason.

**Layer dependencies — some layers are only meaningful after another one
passes.** The layer list is not a flat set, and running a dependent layer first
produces a number that looks like evidence and is not:

- **Mutation and changed-line coverage both rest on suite determinism.** A
  flaky suite inflates the mutation kill score (see the attribution note below)
  and makes coverage of a given line vary between runs. **Order suite health
  before both**, and treat the dependency as real: if suite health is
  `SUBSTITUTED` or `UNAVAILABLE`, neither dependent layer may report a bare
  number — each must state that its result rests on determinism that was never
  demonstrated, and what that leaves unproven.
- **Under a fail-first entry point this ordering has teeth**: a failing suite
  health layer leaves mutation and coverage `NOT REACHED`. That is the correct
  outcome, not a gap to work around by reordering.
- The general rule: when layer B's verdict is derived from layer A's subject
  rather than from its own inspection, B runs after A and inherits A's status.
  Say so in EVIDENCE where it applies.

| Layer | What it catches | How |
|---|---|---|
| Full test suite | regressions | project's test command, zero NEW failures (baseline note below) |
| Static types | whole classes of bugs | tsc / mypy / etc., zero new errors |
| Lint + format | latent bugs, drift | project's linter, zero new warnings |
| Coverage on changed lines | untested code paths | every changed/added **executable** line executed by a test; branch coverage where the tool supports it. Global % is vanity — changed-line coverage is the constraint. Define the fraction explicitly (see below) and **make the layer exit nonzero when its threshold is missed** — a layer that prints a percentage and exits 0 is a report, not a gate layer, and it will sit there green while coverage falls. Most ecosystems ship no command that does this; see `references/layers.md` |
| Mutation testing | tests that assert nothing | **prefer the project's mutation tool** (mutmut, cosmic-ray, Stryker, PIT…), which generates mutants from the syntax tree and cannot silently skip one. No tool available? Manual mutation, per `references/mutation.md` — introduce 3–5 plausible bugs one at a time; the suite must kill every one; restore after. A hand-rolled runner must **prove it executed each mutant**: a runner that can report a kill it never ran inflates the score and no red gate will ever surface it |
| Property-based tests | edge cases you didn't imagine | for parsing, math, serialization, anything with invariants (round-trip, idempotence, ordering) — add hypothesis/fast-check properties |
| Complexity budget | unmaintainable output | new functions small and single-purpose; if a function needs a paragraph to explain, split it |
| Real execution | "passes tests, doesn't run" | actually run the app/CLI/endpoint once on a realistic input, not only the test harness |
| Supply chain & secrets | vulnerable/unnecessary deps, leaked credentials | when the dependency set changed: audit it (pip-audit / npm audit / govulncheck / cargo-audit) and check licenses; scan the diff for secrets; every new dependency must trace back to a justification in the intent record. Also eyeball the capability diff: did the change start using network / subprocess / filesystem / env it didn't before? |
| Suite health | flaky or order-dependent tests | run the suite in randomized order (pytest-randomly etc.); repeat suspected flakes. Every EVIDENCE number rests on the suite being deterministic — a flaky suite quietly invalidates the report |

Changed-line accounting — "changed lines" is three sets, not one, and
collapsing them hides the dangerous case:

1. **executable and instrumented** — the diff's added lines that the coverage
   tool reports on. This is the denominator of the reported fraction.
2. **not executable** — comments, blank lines, declarations, type-only
   constructs, attributes. Excluded, and their count recorded.
3. **executable but carrying no coverage mapping** — added lines the tool
   emitted nothing for. **These must be listed separately and must never be
   folded into set 2.** Set 2 is a property of the language; set 3 is a hole in
   the instrument, and it looks identical in the final percentage. A
   cross-language boundary is the usual cause (see `references/layers.md`).

Report all three counts. A non-empty set 3 caps what the layer can claim, and
the report says so.

You will need a classifier to split sets 1 and 2, and no ecosystem ships one
that is both correct and available — macro continuations, attributes,
multi-line signatures, generated code and derive expansions are all ambiguous
from the source text alone. **Resolve every ambiguity into set 3, never into
set 2.** Exclude only what is plainly non-executable (comments, blanks,
imports, bare delimiters); anything else that carries no coverage mapping stays
in set 3 and fails the layer. That direction is deliberate: guessing "not
executable" hides a hole in the instrument, while guessing "unmapped" costs you
a line to explain. State the classifier's rule in EVIDENCE — it is a home-grown
check, so the checker note applies and it needs its negative control.

Baseline note — on a repo with pre-existing failures, record the baseline
first (which tests already fail, verbatim) and hold the line at zero NEW
failures. Fixing unrelated pre-existing failures is scope creep: surface them,
don't silently "improve" them.

Mutation caveat — **kills are attributed to whichever test fails first**, so a
7/7 kill score validates the suite as a whole, not every layer in it. In Tier 3,
rerun the mutants against the property suite alone before claiming the
properties verify anything; survivors there mean the invariants have blind
spots (a common one: a one-sided invariant like "never exceeds limit" cannot
catch fail-closed bugs — pair it with the opposite bound).

Attribution note — **a mutation tool's maturity does not transfer to its
verdict, so mutation tools do not get the off-the-shelf exemption.** Every other
checker's verdict is a direct function of what it inspected: `tsc` reports zero
errors because it type-checked the code. A mutation tool's `caught` is
second-order — it means *the suite failed while this mutant was applied*, and
the tool then attributes that failure to the mutant. The tool is behaving
correctly when it does this. If the suite failed for any other reason — a flaky
test, contention between the tool's parallel jobs, a stale build artifact, a
timeout — `caught` is still reported and the attribution is still wrong. No
amount of tool maturity fixes that, because the unsound component is the
inference, not the tool.

Two mechanisms produce this, and they fail differently. A **flaky suite** runs
one way only — a spurious failure turns a survivor into a kill, never the
reverse — so it inflates the score and can never surface as a red gate; the
layer stays green precisely because it is broken. **Shared build or working
state between the tool's parallel jobs** is worse: a job can test a binary
another job built, which manufactures kills *and* misses, so the entire
classification stops meaning anything rather than merely reading high. Give each
job its own build directory (see `references/entry-point.md`) — and note that a
well-meaning "send tool output to `artifact_root`" is a common way to destroy
that isolation.

**Before accepting a kill, check that the mutation could plausibly have caused
the failure you are looking at.** "A test failed" and "this mutation made the
test fail" are different claims, and the second is the one the score rests on.
Read the failure: an arithmetic overflow reported in a file containing no
arithmetic of that kind, an assertion failure whose line number is a struct
literal, a panic in code the mutant cannot reach — each is a causal
impossibility and marks the run as contaminated, not the mutant as caught. This
check catches what scope-matching cannot, and it is the easier one to skip
because a contaminated failure looks specific and convincing.

Three controls, all recorded in EVIDENCE:

1. **Baseline under load** (the one that matters). The unmutated baseline must
   pass repeatedly **under the same concurrency the mutation run uses** — not
   the sequential single-process run the suite-health layer does. One baseline
   failure invalidates the whole round's score; report it as such rather than
   reporting the score. This is cheap and it targets the actual mechanism.
2. **Per-job isolation, asserted rather than assumed.** Confirm the tool is not
   sharing a build directory across concurrent jobs, and record how you
   confirmed it. Contention messages in the tool's own logs are the cheapest
   evidence that it is.
3. **Sample re-verification of kills.** Re-apply a sample of the `caught`
   mutants one at a time, at the same source state and with the same test
   command, and confirm a test fails *for a reason the mutation can explain*.
   State the sample size and be honest about its power: at a misattribution rate
   of a few percent a sample of five finds nothing most of the time, so this
   control supports the first two and does not replace them.

If the mutation layer is run twice for any reason, compare the `caught` and
`missed` sets. **Sets that differ between runs mean the layer is
nondeterministic and its score is not evidence** — that comparison is the most
sensitive check available, and worth doing once when the layer is first built.

Checker note — the gate is only as trustworthy as its checkers, and the
dangerous checker failure is fail-open: nothing crashes, the layer prints pass.
Off-the-shelf tools (pytest, mypy, tsc…) have earned their failure behavior —
**with one exception, mutation tools, for the reason in the attribution note
below**; home-grown checks — grep gates, custom scripts, the manual mutation runner —
have not, so two rules apply to them: (1) **fail closed** — a crash, an
unreadable input, an unexpected exit code, or an item silently skipped inside
gate code is a hard failure of the layer, never a pass; no `|| true`, no
`2>/dev/null`, no bare fallthrough. (2) **Prove it can fail before trusting
its pass**: run it once against a known-bad input (a negative control) and
watch it fail — the RED principle applied to checkers, exactly like the
throwaway mutant for an immediately-passing test. Record the control in
EVIDENCE. Be precise about what that buys: **a negative control proves one
known-bad case reaches the checker's failure path. It does not prove the
checker recognizes every violation of the constraint it claims to enforce.**
A grep gate can fail closed perfectly and still guard a spelling rather than
a behavior. When the gate's coverage is narrower than the rule it serves, say
so where the rule is written, rather than letting the rule imply more.

Prove a negative control is itself non-vacuous the same way you prove a test:
temporarily remove or break the defence it validates, and watch the control go
red. A control that passes with the defence removed is measuring nothing —
this is a one-time proof, not a permanent extra layer.

Equivalent-mutant note — with a mutation tool, a survivor is not automatically
a failure: some mutants are semantically equivalent to the original and cannot
be killed. Classify such survivors as "equivalent, because <reason>" in
EVIDENCE rather than adding a meaningless test to kill them — that would
violate anti-gaming rule 4. Before reporting any survivor as a real gap,
construct a concrete input on which the original and the mutant diverge; if you
cannot, it is equivalent. Hand-written mutants (the manual procedure) get no
such excuse: you chose them, so choose real bugs.

## Reconstructing RED

**A test you never saw fail proves nothing — it may be testing nothing.** The
original session watched its tests go red before writing the implementation;
this gate runs afterwards and cannot. Git makes it recoverable:

1. Create a worktree at `base`.
2. Copy in the test files added by this change, along with any new fixtures or
   helpers they need.
3. Run those tests. **They must fail.**
4. Record which failed, and how.

If a test passes against the base ref, it is either vacuous (fix it) or the
behavior already exists. **Don't just assert which — prove it**: break the
implementation with a one-off throwaway mutant, watch the test fail, restore.
Then record it as pre-existing behavior kept as regression armor.

Caveats, recorded when they apply:

- A test that fails on import or collection is a weaker RED than an assertion
  failure. Note it rather than counting it the same.
- Tests *modified* rather than added cannot be replayed this way. Handle them
  case by case and say so.
- **A fresh worktree contains no gitignored content**, so the gate often
  cannot run there until dependencies are rebuilt. Two outcomes are acceptable
  — rebuild and run there, or record why reconstruction was not possible.
  Never report green from a tree that never ran the suite.
- **RED stops being evidence when every new test fails for the same structural
  reason.** When a change introduces a platform the base does not have — a new
  language, a new package, a new build system, a first module — the new tests
  fail at collection because the *project* is absent, not because the behaviour
  is. A wall of red then demonstrates nothing about whether a single one of
  those tests can fail when the behaviour breaks. Record the whole section as
  `NOT EVIDENCE (base lacks the platform under test)` rather than a table of
  passes; a mostly-collection-error table is the same finding in weaker form,
  so state the proportion.
  The substitute, when RED is unavailable this way: prove assertion power
  against **HEAD** instead — a one-off throwaway mutant per new test, watch the
  test fail, restore. That is a weaker claim (it shows the test can fail, not
  that it failed before the code existed) and EVIDENCE must label it as such.
  **Run it in an isolated copy, and say so.** A verification engagement almost
  always forbids modifying product code, and a mutant applied to the working
  tree violates that even when restored — a crash or an interrupt leaves the
  tree mutated. Applying mutants inside a worktree, a scratch clone, or the
  temporary copies a mutation tool manages for itself is **not** modifying
  product code, and is the only sanctioned form of this substitute. If you have
  no isolated copy available, the substitute is unavailable too: say so rather
  than touching the tree.

## Entry Point

Persist one command that runs every layer in sequence and fails on the first
broken one (e.g. `tools/gate.sh`). The "final fresh run" IS this command;
EVIDENCE cites it, and the human can rerun the whole report with it. The
contract — specified in full, with the manifest pattern and fail-closed shell
idioms, in `references/entry-point.md`:

- **Fresh by mechanism, not discipline**: the script starts by deleting stale
  artifacts from previous runs (keep tool databases that accumulate value);
  dev-tool versions are pinned so the rerun uses the same gate.
- **Fail closed**: `set -e`, no `|| true`, no `2>/dev/null`, ambiguous exit
  codes spelled out; execution bound to completion by a fixed expected-layer
  manifest audited before printing success — a heading is not evidence that a
  layer ran, and `set -e` through `&&` is not status handling.
- **Assurance boundary kept explicit**: application coverage and mutation
  target the subject under test, not every orchestration script by default.
- **The gate's own files must not fail the gate's own provenance check**: the
  source-state script excuses untracked verifier paths only through an
  enumerated whitelist (entry-point directory, `artifact_root` — never a
  product path, never a blanket "ignore untracked"), and EVIDENCE prints that
  whitelist verbatim next to `source_state`, because an excusal a reader
  cannot see is an excusal they cannot price. Committing the verifier first
  is the other acceptable resolution.
- **No droppings during the run**: tool output (profiles, caches,
  intermediate reports) points into `artifact_root`, and the source state is
  checked again **after** the final run — a provenance check that runs only
  at the start certifies a tree that no longer exists by the time the report
  is written.

The entry point and its helpers live in **product paths** (`tools/`), not
under `artifact_root` — a report citing a script that lives only in a scratch
directory or in the conversation is not reproducible. This is the one place
this skill writes outside its own artifact folder; confirm these writes with
the user.

## EVIDENCE — the only thing the human reads after code

End with a report the human can trust without opening a single source file
(template in `assets/templates/evidence.md`):

- The stated intent, with each claim mapped to the test that verifies it, and
  the changed-unit list, with each unit mapped to the test that exercises it.
- Each gate layer: the command run, and its actual result (pasted numbers,
  not adjectives). "All 47 tests pass, changed-line coverage 100% (31/31
  lines), 5/5 manual mutants killed" — never "tests look good".
- **Every number in the Gate table** must come from one final fresh run of the
  entry point, executed after the last code edit — results from mid-task runs
  are stale and must not be reported there. This rule scopes to the Gate table
  only: the baseline and the RED reconstruction are runs against the **base
  ref** by definition and can never come from it. Label them as the
  prerequisite runs they are. Diagnostics from earlier runs may appear in
  Honest notes if each is marked as not from the final run; they may never
  appear as a layer result.
- The report must be reproducible from the repo alone: every command it cites
  (including the mutation script) must exist as a persisted file in the repo,
  not in a scratch directory or only in the conversation. Reproducible means:
  dev-tool versions pinned or recorded, one entry-point command that reruns
  every layer, and the source state identified (commit SHA, or a source-tree
  hash when git is absent).
- Layers skipped, and why.
- Anything that failed and how it was resolved, honestly. A gate you passed on
  the first try and a gate you fixed your way through are equally fine; a gate
  you quietly weakened is the only failure.

### Reproducibility status

The report's entire claim is that a reader can rerun it. That claim has states,
and like intent status it is recorded rather than assumed:

- `reproducible` — all three hold: every cited command exists as a persisted
  file in the repo, dev-tool versions are pinned or recorded, and the source
  state was identified and **identical** before and after the final run.
- `degraded` — the run can be repeated, but not to the same numbers. Name which
  of the three failed and what it costs:
  - **versions not pinnable** — no lockfile, a tool with no version flag, or the
    user forbade adding a pin file. Record the observed `--version` output
    verbatim for every tool in the gate. A recorded version is weaker than a
    pinned one: it documents what ran, it does not make the next run match.
  - **entry point not persisted** — the user forbade writing to product paths.
    Reproduce the script verbatim in the report and say the reader must recreate
    it before rerunning. A gate that exists only inside one report is not a gate.
- `not reproducible` — a cited command exists only in a scratch directory or in
  the conversation, or the source state could not be established at all. The
  Gate table then records what one machine observed once, which is not something
  another reader can obtain.

**A `not reproducible` report may not be presented as a passed gate.** Same rule
as `SUBSTITUTED`, for the same reason: the reader cannot tell it apart from a
claim. It is a finished run whose outcome is that the gate could not be made
rerunnable.

**A source state that changed across the run voids the run.** The check runs
before *and* after the final run precisely so this is detectable; when the two
differ, every number describes a tree that no longer exists. Do not annotate it
and do not downgrade it — find what wrote to the tree, fix that, and rerun.
This is the one failure this section deliberately offers no state for.

### The two mapping tables

**Table 1 — Changed unit → Test.** Rows are derived from the diff, not chosen.
Record the command that produced the changed-unit list **and the granularity it
achieved** — `symbol`, `path`, or `module`. Without the command the table
degrades into a narrative and loses the only property that makes it strong;
without the granularity the command can satisfy the field while quietly
delivering something far coarser than a changed *unit*. A path-level command is
an acceptable answer when no symbol-level extractor exists for the ecosystem —
it is not an acceptable answer to leave unlabelled, because `git diff
--name-status` and a real symbol extraction look identical in the header and
mean very different things about what the table covers. At `path` or `module`
granularity, say in the table what that leaves unmapped.
Include **deletions**: a removed function needs a row saying what shows nothing
depended on it. Pure renames, moves, and formatting are not units — collapse
them into one row marked `n-a`. Fillable at every intent status, `absent`
included.

**Table 2 — Stated claim → Test.** Rows come from the intent record. This is
where negative constraints live — a diff can never tell you what the code must
**not** do — along with Tier 3 failure-model rows. It carries confidence only
when intent status is `confirmed`; at `unconfirmed`, print it and label the
source as commit messages rather than human confirmation; at `absent`, omit it
and say why.

Status is one of: **pass / fail / unverified / n-a**. A row mapped to
"skipped: <reason>" must carry unverified or n-a — never pass.

### Layers not run as specified

Split by status, because they mean different things to a reader:

- **N-A (this project has no such surface)**
- **UNAVAILABLE (tool missing, nothing run in its place)**
- **SUBSTITUTED (something else ran — and what it cannot detect)**
- **NOT REACHED (the entry point stopped at an earlier failing layer)**
- **DEPENDENCY UNMET (ran, but the layer it rests on did not pass — which
  prerequisite was `SUBSTITUTED`/`UNAVAILABLE`/failed, and what that leaves
  unproven about this layer's number)**

One "skipped" list collapses five states a reader has to tell apart: there is
no such surface in this project, versus the surface exists but the tool was
missing and nothing ran, versus something else ran and here is what it cannot
detect, versus the layer was configured and available and the gate simply never
got to it, versus the layer ran but rests on a prerequisite that was never
demonstrated (the layer-dependencies rule made concrete). Those are very
different confidence claims and they read identically
as "skipped". The dangerous one is the third: **`SUBSTITUTED` may never be
written as a pass.** Two repeat runs in place of randomized order is not "suite health:
stable" — it is `SUBSTITUTED (2 repeat runs — cannot detect whole-suite order
dependence)`. A reader who cannot tell a substitute from the real layer reads
"found nothing" where the truth is "did not look with that instrument". `N-A`
is not a degraded run at all: three `N-A` layers describe the project, and
EVIDENCE should say so rather than leaving a reader to count absences.

**`NOT REACHED` and the failing gate.** The entry point stops at the first
broken layer (`references/entry-point.md`), so any gate that does its job
leaves later layers unrun. That is correct behaviour, not an incomplete report:
mark each one `NOT REACHED`, name the layer that stopped the run, and do not
reorder the entry point to get more layers in before the failure. A blocked
gate is a finished run with a failing outcome — it is complete when every
unreached layer is accounted for.

You **may** run later layers separately for information while fixing, and it is
often useful. Those numbers are not final-run numbers: they belong in Honest
notes, marked as such, and may never be written into the Gate table or used to
promote a `NOT REACHED` row. The Gate table stays a record of one run.

### Dismissals and the blind spot

**Why dismissals need a line each.** A fix carries its own evidence — the test
that now passes. A dismissal carries none: "not a real problem" is
indistinguishable from "did not check". Name the command, `file:line`, or test
that disproves the finding — say what you tried, not only what you found.

**Why name the blind spot.** A layer a project cannot run at all otherwise
reads as absent rather than accepted. Stating it converts a silent gap into a
known limit the reader can price in.

## Anti-Gaming Rules (absolute)

The gate only creates trust if it cannot be gamed. These are hard rules:

1. **Never weaken a test to make it pass.** Don't broaden assertions, add skips,
   raise tolerances, or delete a failing test. If a test seems wrong, that's an
   intent conversation — surface it, don't bury it.
2. **Never edit a test and the implementation in the same step to reach green.**
   Change one, run, then the other. Simultaneous edits let you accidentally
   redefine correctness to match your bug.
3. **Never mock the unit under test** or mock so much that the test only
   exercises the mocks. Mock boundaries (network, clock, filesystem), not logic.
4. **Never chase the coverage number.** Coverage is a detector of untested code,
   not a target. A test added only to touch lines, with no meaningful assertion,
   is gaming — mutation testing exists precisely to catch this, including yours.
5. **Never report a layer you didn't run.** An honest "skipped: no mutation tool
   in this environment, did manual mutation instead" preserves trust; an
   invented result destroys the entire scheme.
6. **Failing gate blocks done.** You are not finished while any layer fails.
   If you're genuinely blocked, report the failure verbatim as the outcome.

## Setup

**Isolation — do not mutate the user's working tree to do your work.** Use a
worktree for the baseline run and for RED reconstruction. Where the isolated
tree and the tree the change lands in differ by ignored or untracked content,
say so in EVIDENCE: a green run in a tree missing the landing tree's `.env` or
build outputs is not evidence about the landing tree.

If the project has no test runner, no linter, or no type checking, set up the
minimal standard toolchain for the language **first** (see
`references/layers.md`). A gate can't run on bare ground. Setup changes the
user's environment — packages, config files, lockfiles — so confirm it before
doing it, and record every environment change actually made in the evidence
report. If the user forbids adding tooling, fall back to manual layers (manual
mutation, manual execution) and record the reduced confidence honestly.

If the directory is not a git repository, say so and stop before claiming any
provenance: acquisition, the baseline, and RED reconstruction all rest on git.
Offer `git init` and identify the source state with a tree hash instead of a
SHA. Record it as `git_facts: unavailable`; a tree hash restores reproducibility
but nothing restores the base-relative facts, so the baseline, ordering, and RED
reconstruction stay unavailable rather than quietly absent.

## Artifacts

```text
.gate/<scope>/
  evidence.md      # the report
  baseline.md      # pre-existing failures at base, recorded verbatim
  red.md           # RED reconstruction results
```

Recommend adding `.gate/` to the target repository's `.gitignore` unless the
user wants the report committed; do not edit `.gitignore` unless asked. The
entry point and its helpers are **not** artifacts — they belong in `tools/`
and should be committed.

## Language Policy

Skill instructions, template field names, and status values are English.
Generated prose follows `report_language`: `auto` follows the user's prompt
language, explicit values such as `en`, `zh-TW`, or `ja` are allowed. Status
values stay English even inside a localized report.

## Completion Criteria

A verification gate run is complete only when:

- every applicable layer ran, or is recorded as `N-A` / `UNAVAILABLE` /
  `SUBSTITUTED` / `NOT REACHED` / `DEPENDENCY UNMET` with a reason;
- every number came from one fresh run of a persisted entry point;
- intent status, git facts status, and reproducibility status are each recorded
  and none was silently promoted;
- the source state was identical before and after that run;
- Table 1 covers the changed-unit list, deletions included;
- no row mapped to a skip is marked `pass`;
- the structural blind spot is named;
- nothing is claimed that a reader cannot rerun.

## Attribution

The layer stack, the checker and mutation rules, the anti-gaming rules, and the
evidence report structure are adapted from the `old-coder` skill
(https://github.com/AmazingAng/old-coder, MIT, Copyright (c) 2026 amazingang).
See `NOTICE.md`.
