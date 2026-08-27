# Gate entry point

Persist one command that runs every layer in sequence and fails on the first
broken one (e.g. `tools/gate.sh`: tests → types → lint → suite health →
coverage → mutation → real execution). That order is not cosmetic: suite health
comes before coverage and mutation because both derive their numbers from suite
behaviour, so running them first yields a number that looks like evidence and
is not (SKILL.md, "Layer dependencies"). Start the script by deleting stale artifacts from previous
runs (old coverage data, report files) so no layer can accidentally read a
prior run's output — freshness by mechanism, not discipline. (Keep tool
databases that accumulate value, e.g. hypothesis's example store.) The "final
fresh run" IS this command; EVIDENCE cites it, and the human can rerun the
whole report with it. Pin dev-tool versions (requirements-dev.txt,
package.json devDependencies with exact versions, etc.) so the rerun uses the
same gate.

Gate code itself must fail closed (see the checker note in SKILL.md): `set -e`
at the top, no `|| true`, no `2>/dev/null`, and spell out the exit-code cases
of any command whose codes are ambiguous. The classic trap is a
must-find-nothing grep: rc 1 (no matches) is the only pass; rc 0 means the
forbidden pattern exists, and rc ≥ 2 means the check itself broke (unreadable
input, bad pattern) — both must fail the layer, or an unreadable file turns
into a vacuous pass. Prove each home-grown check can fail with a one-off
negative control (feed it a known-bad fixture; make its input unreadable) and
record the control in EVIDENCE's honest notes.

Keep the assurance boundary explicit: application coverage and mutation target
the subject under test; do not widen them across every orchestration script by
default. Protect home-grown tools in the gate's trust chain with targeted
negative controls for identified fail-open modes, and pin the failure reason,
not merely a non-zero status. A control proves only its named known-bad case,
not the whole tool. For the entry point itself, bind execution to completion:
maintain a fixed expected-layer manifest, record each layer only after its
commands succeed, and audit the manifest before printing success. Do not use a
heading as evidence that a layer ran, and do not rely on `set -e` through `&&`
or another conditional context; handle the command status explicitly.

## Why the manifest exists

The upstream project shipped a gate that certified a heading rather than the
work: the mutation call had been removed while its heading stayed, so the entry
point ran zero mutants, exited 0, and printed "all layers green". A manifest
audit is the fix — completion is recorded per layer only after its command
succeeds, and success is refused unless every expected layer is present.

## Reference pattern — fail-closed layer accounting

```sh
#!/bin/sh
# Fail-closed execution and completion accounting for the gate entry point.
GATE_EXPECTED_LAYERS="tests-coverage types lint-format supply-chain must-not-scans mutation-control mutation real-execution source-state"
GATE_COMPLETED_LAYERS=""

run_layer() {
  if [ "$#" -lt 2 ]; then
    echo "FAIL: run_layer requires a layer name and command" >&2
    return 2
  fi

  layer=$1
  shift

  case " $GATE_EXPECTED_LAYERS " in
    *" $layer "*) ;;
    *)
      echo "FAIL: unknown layer '$layer'" >&2
      return 2
      ;;
  esac

  case " $GATE_COMPLETED_LAYERS " in
    *" $layer "*)
      echo "FAIL: duplicate layer '$layer'" >&2
      return 2
      ;;
  esac

  printf '=== %s ===\n' "$layer"
  if "$@"; then
    GATE_COMPLETED_LAYERS="$GATE_COMPLETED_LAYERS $layer"
    return 0
  else
    rc=$?
    printf "FAIL: layer '%s' failed (rc=%s)\n" "$layer" "$rc" >&2
    return "$rc"
  fi
}

finish_gate() {
  missing=0
  for layer in $GATE_EXPECTED_LAYERS; do
    case " $GATE_COMPLETED_LAYERS " in
      *" $layer "*) ;;
      *)
        echo "FAIL: missing layer '$layer'" >&2
        missing=1
        ;;
    esac
  done

  if [ "$missing" -ne 0 ]; then
    return 1
  fi
  echo "=== gate: all layers green ==="
}
```

Properties that matter: an unknown layer name is rc 2 (a typo cannot silently
drop a layer), a duplicate is rc 2, a layer is recorded only after its command
succeeds, a failure preserves the original return code and names the layer, and
`finish_gate` refuses to print success while any expected layer is missing.

`GATE_EXPECTED_LAYERS` above is one project's manifest, not a required set —
yours lists the layers *you* run, and `must-not-scans` is only in it because
that project had negative constraints expressible as a forbidden pattern (a
credential shape that must not appear in config, a debug flag that must not
ship). A project with no such constraint has no such layer, and drops it from
the manifest rather than shipping a scan of nothing. If you keep the layer,
give it real patterns and real paths — a `must_not_match` helper that exists
only to be self-tested guards nothing, and its green self-test reads in EVIDENCE
like a constraint was enforced.

## Reference pattern — must-find-nothing grep

```sh
# Must-find-nothing grep, fail closed: grep rc 1 (no matches) is the only
# pass; grep rc 0 = forbidden pattern present (return 1), grep rc >= 2 =
# the check itself broke (return 2, so the self-test can tell the two
# failure modes apart). Any nonzero return fails the gate under set -e.
must_not_match() {
  pattern=$1; shift
  # An empty path list is the fail-open trap: with no file operands grep reads
  # stdin, finds nothing in an empty or closed stream, and returns 1 — the pass
  # code. A caller whose file list came out empty (a glob that matched nothing,
  # a `git diff --name-only` with no hits) would score a silent pass on a scan
  # that inspected nothing. Refuse instead, with the broken-checker code.
  if [ "$#" -eq 0 ]; then
    echo "FAIL: no paths given to scan (fail closed): $pattern"; return 2
  fi
  if grep -rniE "$pattern" "$@"; then
    echo "FAIL: forbidden pattern present: $pattern"; return 1
  elif [ $? -ne 1 ]; then
    echo "FAIL: scan itself broke (fail closed): $pattern"; return 2
  fi
}
```

The empty-path guard is the general shape of the trap, not a quirk of grep:
**any checker that takes a work list can be handed an empty one, and "inspected
nothing" must never share an exit code with "found nothing".** Apply the same
guard to every home-grown check that iterates over files, mutants, or units.

## Self-tests to run before the real layers

These are negative controls for the entry point itself, and they belong at the
top of the script so a broken harness fails before it can print anything green.

**This list is a floor, not an inventory.** It covers the failure modes seen so
far; it does not enumerate the ways your harness can fail open. For each
home-grown check you write, ask what input makes it report a pass while
inspecting nothing — empty work list, absent input file, a filter that matched
zero items, a loop that never entered — and add a control for that. Copying
these three and stopping is how a known-good reference propagates an unknown
gap.

- **Orchestration self-test**: omitting a layer must be named and must not
  print green; a failing command must preserve its return code and stop the
  run; an unknown layer name must be rc 2; a duplicate layer must be rc 2; and
  — the positive control — a complete manifest must actually reach all-green,
  so the self-test cannot be a script that only ever fails.
- **Checker self-test**: a forbidden pattern present must fail; a clean tree
  must pass (otherwise the gate is one that can never pass); a nonexistent path
  must fail with the distinguishable rc 2; **an empty path list must fail with
  rc 2** — the scan that inspected nothing must not be able to report the same
  result as the scan that found nothing.
- **Source-state self-test**: the provenance computation must refuse to emit a
  state when the working tree is dirty or history is truncated, rather than
  emitting a degraded one. Control all three directions: a tree with an untracked
  product file must be refused; a tree whose only untracked content is the
  whitelisted paths must still emit a state (otherwise the check is one that can
  never pass on its first run); and a prefix that fails the admission
  test must be refused **even though it is listed** — control this with a
  throwaway untracked file inside a tracked source directory, which is the case
  a weaker "untracked and not in the diff" rule lets through. That control is
  what proves the admission test runs rather than the list being trusted.

CI must exercise the real path, not the degraded one — if the source-state
check needs full history, configure the checkout to fetch it rather than
letting CI run a weakened variant of the gate.

## The verifier's own footprint

The gate writes files the gate then has to account for. On the first run the
entry point, its helpers, and `artifact_root` are all untracked, and the
source-state check above is required to refuse exactly that. Do not loosen the
check to escape this. Instead:

- The source-state script carries an **explicitly enumerated whitelist** of
  path prefixes. Do not treat the enumeration as fixed by this document —
  enumerate it from **the tree you are actually in**, and admit a prefix only
  when it satisfies the test below.
- **The admission test, which is the actual rule:** an excused prefix must
  contain **no tracked files at all** — `git ls-files -- <prefix>` returns
  nothing — and must not appear in the change set's diff. Check both per prefix
  inside the script; do not assert them in prose.
  The tracked-file clause is the load-bearing one, and "untracked and not in
  the diff" is **not** a sufficient substitute for it: a stray untracked file
  dropped into a product source directory satisfies both of those and is still
  product code the build will compile. A directory that holds even one tracked
  file is part of the subject, so nothing under it is excusable — which is
  exactly what separates `crates/<pkg>/src/` from `.gate/` without anyone
  having to enumerate either by hand.
- Prefixes that commonly qualify, as **examples and not a closed set**: the
  entry-point directory; `artifact_root`; agent and tool configuration
  directories the repository does not track (`.agents/`, `.claude/`, `.codex/`,
  editor and local-tooling directories). The set differs per machine and per
  repo — a list copied from here rather than derived from the tree will refuse
  a legitimate run or excuse an illegitimate one, and the first failure mode is
  the one you will hit: the gate blocking on its own installation.
- EVIDENCE prints the whitelist verbatim beside `source_state`, one line per
  prefix with the reason it passed the admission test. An excusal a reader
  cannot see is an excusal they cannot price.
- Never substitute a blanket "ignore untracked files", never excuse a product
  path, and never extend a prefix to reach a path the change itself touches.
- Committing the verifier before the run is the other acceptable resolution,
  and the cleaner one when the repo will keep the gate.

One worked instance, for shape rather than as a universal recipe — a Rust
cdylib loaded by Node under napi-rs, where the host-default coverage report
fails with missing objects: `cargo llvm-cov show-env --sh --target <triple>
--coverage-target-only` to export the instrumentation environment, rebuild the
native callee inside it, run the caller's test suite in that same environment,
then merge the raw profiles into one report. The target-triple pinning is the
part that is easy to miss and the part that makes the objects resolve. Your
toolchain will differ; what transfers is that the callee is rebuilt under the
profile environment and the caller's suite runs inside it, not beside it.

Point every tool's incidental output — coverage profiles, caches, intermediate
reports — into `artifact_root` before running it. Instrumented binaries and
coverage runners in particular drop raw profile files next to whatever they
load, which lands them in product paths.

**Redirect output; never redirect a directory the tool isolates per job.** A
build or target directory is not incidental output — it is working state, and
some tools keep one per parallel worker on purpose. Pointing them all at one
path under `artifact_root` looks tidy and silently removes the isolation. The
observed case: a mutation runner given a single shared `CARGO_TARGET_DIR` while
running four parallel jobs, so mutants executed binaries other mutants had just
built. 412 of its 414 logs recorded contention on that one build directory, and
three comparison-operator mutants were recorded as killed by an arithmetic
overflow that only a *different* mutant could produce. Before redirecting
anything, ask whether the tool runs jobs concurrently against that path; if it
does, give each job its own, and redirect only the reports.

Check the source state **twice**: once before the layers and once after the
final layer. A provenance check that runs only at the start certifies a tree
that the run itself may have changed by the time the report is written.
