# Evidence Report — <task name> (Tier <1|2|3>)

- `headline`: <!-- one line, derived mechanically — never composed. In order:
  `BLOCKED at <layer>` when any Gate row failed (everything behind it is NOT
  REACHED); `NOT PRESENTABLE AS PASSED — <not reproducible | SUBSTITUTED
  layer presented in its place>` when either applies; otherwise `GATE PASSED`
  plus one qualifier per degraded status (reproducibility degraded, git_facts
  partial, intent unconfirmed/absent, any DEPENDENCY UNMET row). The weakest
  link names the headline; a reader who reads nothing else reads this -->
- `command`: `evidence`
- `contract`: <!-- applied | overridden by <path> | n-a (routine change) —
  whether an evidence-first contract governed this change; an override is
  never silent -->
- `scope`: <!-- artifact subfolder name -->
- `change_set`: <!-- working tree | <base>...HEAD | commit range | PR -->
- `base`: <!-- comparison ref -->
- `report_language`: <!-- auto | en | zh-TW | ... -->
- `intent_status`: <!-- confirmed | unconfirmed | absent -->
- `intent_source`: <!-- human reply (verbatim) | spec file path | issue/PR ref |
  commit messages only -->
- `ordering`: <!-- tests-first | implementation-first | mixed | unknown —
  whether each new test file was committed before the implementation it
  covers. One of the three facts the report leans on hardest, beside Baseline
  and RED; `unknown` is a declared downgrade, never a pass -->
- `git_facts`: <!-- complete | partial | unavailable — when partial, list each
  fact the repository could not supply (baseline / ordering / reachable base)
  and say what it cost. Fetch first: a fetchable fact is not a missing one -->
- `source_state`: <!-- commit SHA | no git: sha256 tree hash --> — persist the
  computation as a script (e.g. `tools/source_state.sh`); a hash recipe written
  in prose is working-directory-sensitive and will fail to reproduce. When Git
  exists, derive the tree hash from version-controlled inputs, fail on relevant
  staged, unstaged, deleted, or non-ignored untracked files, and never hash
  ambient ignored build artifacts. Checked before **and after** the final run,
  and the two must be **identical** — a difference voids the run; rerun rather
  than reporting it
- `source_state_exclusions`: <!-- the verbatim whitelist of verifier paths the
  source-state check excuses (entry-point dir, artifact_root), or "none — the
  verifier is committed". Never a product path, never a blanket rule -->
- `toolchain`: <!-- pinned versions file, e.g. requirements-dev.txt; when no
  pin file is possible, the verbatim `--version` output of every tool in the
  gate, and `reproducibility: degraded` -->
- `entry_point`: <!-- single command that reruns every layer -->
- `reproducibility`: <!-- reproducible | degraded | not reproducible. Degraded
  covers versions that could not be pinned or an entry point that could not be
  persisted — name which, and what it costs. A source state that could not be
  established at all is `not reproducible`, which may never be presented as a
  passed gate; a source state that *changed* across the run is neither, it
  voids the run -->
- `changed_unit_command`: <!-- the command that produced the changed-unit list -->
- `changed_unit_granularity`: <!-- symbol | path | module — what that command
  actually resolved to. `path` is acceptable when no symbol-level extractor
  exists for the ecosystem; leaving it unstated is not, because a path-level
  diff command and a real symbol extraction look identical in this header -->

## Baseline

Tests already failing at `base`, recorded verbatim before this change was
measured. The suite layer holds the line at zero NEW failures against this list.

<!-- verbatim list, or "none — base was green", or "unavailable — <reason>":
     with no baseline the suite layer may report only its own absolute
     pass/fail count, because a pre-existing failure and one this change
     introduced are indistinguishable. Say that in the Gate table too -->

## Changed unit → Test

Rows are derived from the diff, not chosen. Include deletions. Pure renames,
moves, and formatting collapse into one `n-a` row.
At `path` or `module` granularity, state here what that leaves unmapped — e.g.
"rows are files; individual functions within a changed file are not
individually mapped".
Status is one of: **pass / fail / unverified / n-a**. A row mapped to
"skipped: <reason>" must carry unverified or n-a — never pass.

| Changed unit | Test | Status |
|---|---|---|
| <file>::<function/branch/symbol> | <test file>::<test name> | pass |
| deleted: <symbol> | <what shows nothing depended on it> | pass \| unverified |
| renames / moves / formatting (<n> files) | — | n-a |

## Stated claim → Test

Rows come from the intent record. Negative constraints live here — a diff can
never tell you what the code must not do. Omit this table entirely when
`intent_status` is `absent`, and say why.

| Claim | Test | Status |
|---|---|---|
| <what the change was supposed to do> | <test file>::<test name> | pass |
| Must NOT: <negative constraint> | <test / layer / skipped: reason> | pass \| unverified |

## RED reconstruction

New tests replayed against `base`. A test that passed there is either vacuous
or covers pre-existing behavior — say which.

| Test | Result at base | Note |
|---|---|---|
| <test file>::<test name> | failed (assertion) | — |
| <test file>::<test name> | failed (collection error) | weaker RED than an assertion failure |
| <test file>::<test name> | passed | pre-existing behavior, kept as regression armor |

<!-- or: "not performed — <reason>" -->
<!-- or: "NOT EVIDENCE (base lacks the platform under test) — every new test
     failed at collection because the project/package/toolchain itself is
     absent at base, which demonstrates nothing about whether any of them can
     fail when the behaviour breaks. <n>/<total> failed this way." Then record
     the substitute if one was run: per-test throwaway mutant against HEAD,
     which shows the test can fail but not that it failed before the code
     existed. -->

## Gate (final fresh run)

All numbers below come from one run of `entry_point` executed after the last
code edit. Paste actual numbers, never adjectives. This rule scopes to this
table: Baseline and RED reconstruction are runs against the base ref and cannot
come from it. Diagnostics from earlier runs belong in Honest notes, marked as
not from the final run — never in a cell here.

Every row carries the threshold that decides it. A row may read `PASS` **only**
when its Result satisfies its own Threshold cell, and a Threshold you cannot
state is a sign the layer is a report rather than a gate layer — fix the layer,
do not leave the cell empty. Order the rows so any layer that depends on
another (see SKILL.md's layer dependencies) comes after it.

| Layer | Command | Threshold (what makes this pass) | Result |
|---|---|---|---|
| Tests | <cmd> | 0 new failures vs baseline | <N> passed, 0 failed (baseline: <N> pre-existing) |
| Types | <cmd> | 0 new errors | 0 errors |
| Lint | <cmd> | 0 new warnings | 0 warnings |
| Suite health | <cmd> | randomized order, 0 flakes — **runs before mutation and coverage** | randomized order (seed <n>), all passed |
| Changed-line coverage | <producer cmd> + <gate cmd> | every changed executable line covered; 0 unmapped | <covered>/<executable> changed executable lines; <n> not executable; **<n> executable with no coverage mapping** (list any misses; an unmapped count above zero caps what this layer can claim) |
| Mutation | <tool or "manual"> | 0 surviving mutants that are not classified equivalent | <killed>/<total> killed; <n> survivors, each classified; baseline-under-load and kill-sample controls in Negative controls |
| Property-based | <cmd> | all properties hold | <N> properties, <examples/property> examples each |
| Complexity budget | <how checked> | <stated budget> | <observed> |
| Real execution | <cmd> | <expected observable behaviour> | <observed output> |
| Supply chain | <cmd> | 0 known vulns; every new dep justified | 0 known vulns; new deps: none (or list, each ↔ justification) |

## Negative controls

Home-grown checks are only trusted after being seen to fail. One line each.

- <check> — fed <known-bad input>, failed as expected with <observed failure>
- <check> — proved non-vacuous by removing <defence> and watching the control go red
- Mutation baseline under load — unmutated baseline run <n> times at the
  mutation tool's own concurrency, <n>/<n> passed (any failure invalidates the
  round's score rather than lowering it)
- Mutation kill sample — <n> of <total> `caught` mutants re-applied individually,
  <n>/<n> confirmed a failing test; sample power stated, not implied
- (or "none — no home-grown checks in this gate")

## Layers not run as specified

Split by status, because they mean different things to a reader:

- **N-A (this project has no such surface):** <layer — why it does not exist here>
- **UNAVAILABLE (tool missing):** <layer — which tool, nothing run in its place>
- **SUBSTITUTED:** <layer — what ran instead, and what that cannot detect>
- **NOT REACHED (gate stopped at an earlier failing layer):** <layers — and
  which layer stopped the run>
- **DEPENDENCY UNMET (ran, but the layer it rests on did not pass):** <layer —
  which prerequisite was `SUBSTITUTED`/`UNAVAILABLE`/failed, and what that
  leaves unproven about this layer's number>
- (or "none")

`SUBSTITUTED` may never be written as a pass. Neither may `NOT REACHED`: a
blocked gate is a finished run with a failing outcome, and every layer behind
the failure is unmeasured, not clean.

## Dismissed concerns

Fixes are self-evidencing; dismissals are not. One line each:

- <concern> — dismissed because <the command / file:line / test that disproves
  it>. <If the argument is "no alternative exists": which call sites it covers,
  and which it does not.>
- (or "none — every concern was fixed or accepted as a known limit")

## Structural blind spot

- <the layer this project cannot run at all, e.g. "the suite never exercises the
  container runtime, so nothing here is evidence about deployment behavior">

## Honest notes

- <failures hit during the run and how they were resolved; environment changes
  made during setup; isolated-tree vs landing-tree differences; anything
  reducing confidence>
