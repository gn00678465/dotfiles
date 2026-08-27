# Gate Tooling by Ecosystem

Prefer whatever the project already uses (check package.json / pyproject.toml /
Makefile / CI config first). These are the defaults when nothing exists.

## Read this before the changed-line coverage rows

SKILL.md requires the changed-line coverage layer to **exit nonzero when its
threshold is missed**. Almost no ecosystem ships a command that does this.
What the tables below give you is a *coverage producer*; the gate needs a
producer plus a **gate step**, and the gate step is usually not free:

- **Native thresholds gate the wrong metric.** `--cov-fail-under`,
  `coverageMinimum*`, JaCoCo `check` rules and friends all gate *global*
  coverage — the number SKILL.md calls vanity. They are worth keeping as a
  floor, but they are not this layer.
- **The gate step is a diff-aware check over a machine-readable report.** Have
  the producer emit LCOV / Cobertura XML / JaCoCo XML, then fail the layer on
  the changed lines specifically. `diff-cover <report> --fail-under=100` covers
  the common report formats — confirm your installed version accepts the format
  you produced rather than assuming it, because an unrecognised report is
  exactly the fail-open this layer exists to prevent.
- **Where no such check exists, you write one, and the checker note applies in
  full**: fail closed, prove it can fail with a negative control (a synthetic
  report with a zero-hit line on a changed line must fail the layer), and
  persist it in `tools/`. A hand-rolled changed-line checker is a home-grown
  check, not a tool with earned failure behaviour.
- **A producer command that exits 0 is not a result.** If the row below hands
  you only a producer, the layer is not done when it runs clean.

The same split applies to the three counted sets in SKILL.md's changed-line
accounting: whatever you build must report added-executable-and-instrumented,
added-not-executable, and **added-executable-with-no-coverage-mapping**
separately. The third set is what a missing instrumentation path looks like,
and it is invisible in any single percentage.

## Python

| Layer | Tool | Command |
|---|---|---|
| Tests | pytest | `pytest -q` |
| Types | mypy | `mypy <pkg>` (or pyright) |
| Lint + format | ruff | `ruff check . && ruff format --check .` |
| Changed-line coverage | coverage.py + diff-cover | producer: `pytest --cov=<pkg> --cov-branch --cov-report=xml`. **Gate: `diff-cover coverage.xml --compare-branch=<base> --fail-under=100`.** `--cov-fail-under=<n>` is a useful global floor but gates the wrong metric; without either flag the layer prints a number and exits 0, so it can never fail |
| Mutation | mutmut (3+) | configure `[tool.mutmut] source_paths = ["src/"]` in pyproject.toml, then `mutmut run` (target one module with `mutmut run "my_module*"`); survivors = weak tests |
| Property-based | hypothesis | `@given(...)` strategies for invariants |

## JavaScript / TypeScript

| Layer | Tool | Command |
|---|---|---|
| Tests | vitest / jest | `npx vitest run` / `npx jest` |
| Types | tsc | `npx tsc --noEmit` |
| Lint | eslint | `npx eslint .` |
| Changed-line coverage | vitest/jest coverage (producer only) | producer: `npx vitest run --coverage --coverage.reporter=lcov`. **This command exits 0 whatever the coverage is** — "check touched files" is not a gate. Add a gate step over `coverage/lcov.info` (diff-cover if it accepts LCOV in your version, else a persisted checker) |
| Mutation | Stryker | `npx stryker run` (scope with `mutate: [<changed files>]` — full-project runs are slow) |
| Property-based | fast-check | `fc.assert(fc.property(...))` |

## Go

| Layer | Tool | Command |
|---|---|---|
| Tests | go test | `go test ./... -race` |
| Types | compiler | `go build ./...` |
| Lint | go vet + staticcheck | `go vet ./... && staticcheck ./...` |
| Changed-line coverage | built-in (producer only) | producer: `go test -coverprofile=c.out ./...`. `go tool cover -func=c.out` prints and **exits 0** — it is a report, not a gate. Convert to Cobertura (`gocover-cobertura`) for diff-cover, or gate `c.out` with a persisted checker |
| Mutation | (no mature default) | manual mutation, per `mutation.md` |
| Property-based | testing/quick or rapid | `rapid.Check(t, ...)` |

## Rust

| Layer | Tool | Command |
|---|---|---|
| Tests | cargo | `cargo test` |
| Types | compiler | `cargo check` |
| Lint | clippy | `cargo clippy -- -D warnings` |
| Changed-line coverage | cargo-llvm-cov (producer only) | producer: `cargo llvm-cov --lcov --output-path target/lcov.info`, then gate that LCOV. Bare `cargo llvm-cov` prints a table and **exits 0**. `--branch` needs nightly (`-Z coverage-options=branch`); on a pinned stable toolchain record branch coverage as `UNAVAILABLE` rather than dropping the layer. See "Cross-language boundaries" below before trusting a Rust-only profile |
| Mutation | cargo-mutants | `cargo mutants --file <changed file>` |
| Property-based | proptest | `proptest!` macros |

## Java

| Layer | Tool | Command |
|---|---|---|
| Tests | JUnit 5 via Maven / Gradle | `./mvnw test` / `./gradlew test` |
| Types | javac via Maven / Gradle | `./mvnw compile` / `./gradlew classes` |
| Lint + format | Checkstyle + Spotless | `./mvnw checkstyle:check spotless:check` / `./gradlew check spotlessCheck` |
| Changed-line coverage | JaCoCo (producer only) | producer: `./mvnw verify` / `./gradlew test jacocoTestReport`. **Inspecting a report by eye is not a gate layer.** Gate the emitted `jacoco.xml` with diff-cover or a persisted checker; a JaCoCo `check` rule is a global floor, not this layer |
| Mutation | PIT | `./mvnw test-compile org.pitest:pitest-maven:mutationCoverage` / `./gradlew pitest`; scope changed packages or classes |
| Property-based | jqwik | write `@Property` tests; the normal JUnit test command runs them |

## Scala

| Layer | Tool | Command |
|---|---|---|
| Tests | MUnit / ScalaTest via sbt | `sbt test` |
| Types | Scala compiler | `sbt "compile" "Test / compile"` |
| Lint + format | Scalafix + Scalafmt | `sbt scalafmtCheckAll "scalafixAll --check"` |
| Changed-line coverage | scoverage (producer only) | producer: `sbt clean coverage test coverageReport`, which emits Cobertura XML. **Inspecting it by eye is not a gate layer** — gate the XML with diff-cover or a persisted checker. `coverageMinimum*` settings are a global floor, not this layer |
| Mutation | Stryker4s | `sbt stryker`; scope `mutate` to changed source files when the full project is slow |
| Property-based | ScalaCheck | define `Properties` or framework-integrated properties; `sbt test` runs them |

## SQL

SQL has no portable test runner or type checker. Configure the actual dialect,
use the project's migration/query framework, and validate against a disposable
instance of the same database engine used in production.

| Layer | Tool | Command |
|---|---|---|
| Tests | project/database-native tests | run the project's test command (`dbt test` for dbt), including migrations, constraints, and result-set assertions |
| Parse + schema checks | SQLFluff + target database | `sqlfluff parse --dialect <dialect> <changed.sql>`, then prepare, explain, or execute each changed statement against the disposable database |
| Lint + format | SQLFluff | `sqlfluff lint --dialect <dialect> .`; apply rule fixes with `sqlfluff fix` (`sqlfluff format` handles layout only) |
| Changed-statement coverage | claim-to-test mapping (no tool) | no coverage instrument exists here, so the layer is a persisted checker over an explicit inventory: map every changed statement, predicate branch, constraint, and migration direction to an integration test, and **exit nonzero on any unmapped item**. A mapping kept in prose is a report, not a gate |
| Mutation | manual | use the manual procedure in `mutation.md` to alter predicates, joins, aggregates, constraints, and migration steps; every mutant must fail a test |
| Property-based | host-language generator + target database | generate rows and assert schema, query, and round-trip invariants through the project test runner |

## Emacs Lisp

| Layer | Tool | Command |
|---|---|---|
| Tests | ERT | `emacs -Q --batch -L . -l ert -l <test-file> -f ert-run-tests-batch-and-exit` |
| Compile checks | byte compiler | `emacs -Q --batch -L . --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile <files>` |
| Lint | package-lint + checkdoc | run `package-lint-batch-and-exit` and `checkdoc` in batch mode over every changed `.el` file |
| Changed-form coverage | testcover / undercover.el (producer only) | instrument changed files in the batch ERT runner; undercover can emit LCOV. **Verifying by inspection is not a gate** — gate the emitted report and exit nonzero on any unexercised changed form |
| Mutation | no mature default | use the manual mutation procedure in `mutation.md` on changed defuns and run the ERT suite for each mutant |
| Property-based | deterministic ERT generators | generate inputs in an `ert-deftest`, pin the random seed, and assert invariants |

## Projects that span several ecosystems

The tables above assume one project maps to one table. Many do not — a Rust
core behind a Node package, a Python service with a TypeScript front end, a JVM
service with SQL migrations. The tables do not compose on their own, so make
the split explicit rather than inventing a merge:

- **One layer per ecosystem, suffixed by it.** `tests-rust` and `tests-node`,
  not one `tests`. Put both in the entry point's expected-layer manifest, and
  let EVIDENCE's Gate table carry one row each. Two rows is the honest shape;
  a single row that averages two ecosystems is not.
- **A layer fails if any of its ecosystems fails.** No partial credit, and
  never a row that reads pass because the other half of it passed.
- **Never merge scores across ecosystems.** Coverage fractions from two
  instruments may be added only if both count the same thing the same way —
  they usually do not, and mutation scores never do (killed/total from
  `cargo-mutants` and from Stryker are different quantities). Report them side
  by side. If a single number is genuinely required, define the arithmetic in
  EVIDENCE and say what it obscures.
- **Pin each ecosystem's dev tools in that ecosystem's own manifest**
  (`Cargo.toml` / `package.json` / `requirements-dev.txt`), and have
  `toolchain` in EVIDENCE list every one of them. A verification-only
  dependency belongs next to the entry point, not in the product manifest.

### Cross-language boundaries (FFI, N-API, JNI, cgo, WASM)

When one language calls into another, **the coverage instrument of the calling
side does not see the called side, and the instrument of the called side does
not see what the caller drove.** A native library exercised only through its
own unit tests will report the paths its callers actually use as uncovered — or,
worse, the calling side's tests will execute native code that no profile ever
records, and the number looks normal.

So: the coverage producer must instrument the callee **and** run the caller's
tests through it in the same profiling session (build the native artifact with
coverage instrumentation, point the profile output at `artifact_root`, run both
suites, then merge the raw profiles into one report). If you cannot do that,
the layer is `SUBSTITUTED`, and EVIDENCE states which side of the boundary went
unmeasured — never a plain pass.

Sanity check before trusting the number: a profile that shows the binding entry
points as uncovered while the caller's tests demonstrably pass through them is
not a coverage finding, it is a broken collector.

## Extended layer menu (any ecosystem)

Always-on layers live in SKILL.md's table; these are picked per task by the
Tier 3 failure model (or when the domain plainly calls for them).

| Layer | Tools | When |
|---|---|---|
| Dependency audit | pip-audit / npm audit / govulncheck / cargo-audit | whenever the dependency set changed |
| License check | pip-licenses / license-checker / go-licenses / cargo-license | when adding deps to redistributable code |
| Secret scan | gitleaks (language-agnostic) | on the diff before committing |
| Capability diff | declared-surface diff (imports/requires/uses, dependency manifests, build scripts, CI permissions), or semgrep rules | always cheap: did the change start **declaring** network / subprocess / filesystem / env access it didn't before? An agent-added capability nobody asked for is a red flag. Scoped to the declared surface on purpose — see SKILL.md's Scope Boundary; reading function bodies to judge how a capability is used is review, not this layer, and a capability reached dynamically is a blind-spot entry rather than something to go hunting for |
| Suite health | pytest-randomly (py) / `vitest --sequence.shuffle` (ts) / `go test -shuffle=on` / `cargo test -- --shuffle` (nightly) | randomized order per run; repeat suspected flakes |
| API compatibility | griffe (py) / api-extractor (ts) / apidiff (go) / cargo-semver-checks (rust) | when a public API is touched |
| Concurrency | `go test -race` / ThreadSanitizer (C/C++/Rust) / loom (rust) / threading stress + rerun (py) | Tier 3, when the failure model names races |
| Performance | pytest-benchmark / hyperfine / criterion | only when the stated intent states a budget |
| UI checks | axe-core (accessibility) / Playwright screenshot diff (visual regression) / Lighthouse (perf & a11y budgets) | when the change touches user-facing UI — backend layers say nothing about a broken layout or an unreadable contrast |
| Version matrix | tox / nox / CI matrix | when the project claims support for multiple language or platform versions — one version green is not evidence for the others |
| Observability | assert critical paths emit logs/metrics (capture in tests or grep) | when the failure model includes "fails silently in production" — passing all tests but breaking invisibly is still a failure |

New dependencies are an intent matter first, a tool matter second: each one
needs a one-line justification in the intent record, and EVIDENCE records the
final dependency diff so the human can see exactly what was pulled in.
