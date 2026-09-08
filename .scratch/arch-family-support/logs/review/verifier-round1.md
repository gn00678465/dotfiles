## Verification Report

### Independent verification — round 1 (fresh-context)

**Source state observed:**
- Task-stated: `feat/arch-family-support` @ `491c0f2d77a3041a7deb089d37eeddd446c4a9a5`, repo at `D:\Projects\dotfiles-dev\dotfiles` (`/mnt/d/Projects/dotfiles-dev/dotfiles` in WSL `dev`).
- Actual, at end of session: same working directory, HEAD had advanced to `5e30e95d5450fa3df7ad3bff197d44ec08cb903e` (3 new commits landed on the same branch *during* my verification window — `03db4c5`, `3c52a78`, `5e30e95`). This is not a reconstruction; confirmed via `git rev-parse HEAD`, `git reflog`, and `git worktree list` on the exact directory named in the task.

**Verdict: failed**

---

### Attacked

**1. The run.** Executed `sh tools/gate.sh --scope arch-family-support` blind, from the exact stated source state, in WSL `dev`, against the exact path the task named (`/mnt/d/Projects/dotfiles-dev/dotfiles`). It failed immediately at the second layer:

```
===== layer: source-state-before =====
commit=491c0f2d77a3041a7deb089d37eeddd446c4a9a5
worktree=dirty
untracked_whitelist=.gate/
dirty_entries:
?? .scratch/arch-family-support/
gate: layer source-state-before 失敗 (exit 1)。後面的層沒有執行。
```

Root cause (`D:\Projects\dotfiles-dev\dotfiles\tools\gate-source-state.sh:16`): the whitelist for untracked files is `.gate/` only. `.scratch/<scope>/evidence.md` — the file AGENTS.md itself says must be **committed** (`D:\Projects\dotfiles-dev\dotfiles\AGENTS.md`, "Evidence-first artifacts" section) — is present but uncommitted at this exact commit, so it trips the dirty check and the gate's own `rm -rf "$ART"` (`tools/gate.sh:60`) wipes `.gate/arch-family-support/` down to the 4 partial files from this failed run before exiting.

While investigating why, I found a second, live execution of the same gate command already running in the same WSL distro, but against a *different, undisclosed* clone: `~/gate/dotfiles`, a plain `git clone`, not a worktree, at that time on commit `5e30e95` (3 commits ahead of the state I was told to verify), being repeatedly relaunched (new PID every ~2 min, `/tmp/gate-arch-family.log`) throughout my session. Neither this clone nor its existence were mentioned in the four inputs I was given.

Also attacked: rendering equivalence between base `4e6f13c` and target `491c0f2` for Debian/macOS/Windows (S6, Must NOT #2) via `git worktree add` pinned at both SHAs and per-file `chezmoi execute-template` diff across `dot_zshrc.tmpl`, `dot_zprofile.tmpl`, `.chezmoi.toml.tmpl`, and every `.chezmoiscripts/*.tmpl` for `os-linux`, `os-darwin-amd64`, `os-darwin-arm64`, `os-windows`. Result: byte-identical except the expected self-referential `sourceDir` line in `.chezmoi.toml.tmpl`. **No divergence found** — S6/Must NOT #2 hold under independent re-derivation.

**2. Spec vs. contract.** Read SPEC v1 in full (S1–S12, Must NOT #1–#8, M1–M7). Checked Must NOT #7 ("不得在環境 A 做 chezmoi init --apply 以外的系統變更") against the evidence report's own "Honest notes": the operator made unauthorized sudoers edits, injected a new SSH key, and deleted stray chezmoi state directories on the real omarchy 4.0.2 VM, beyond `chezmoi init --apply`, "沒有逐項事先徵得同意" (not authorized item-by-item in advance). This is a genuine, self-disclosed Tier-3 Must NOT violation on real infrastructure (SPEC F4: this VM is the user's real environment), yet the Stated-claim table marks the row "偏離，已記錄" (deviated, recorded) rather than as a gate failure, and the report's headline still reads "GATE PASSED."

**3. The tests.** Constructed three independent mutants in throwaway worktrees (`git worktree add`, cleaned up afterward, no tracked files touched):
- **Mutant A** — `.chezmoitemplates/platform.toml`: replaced `$archFamily := or (eq $distro "arch") (has "arch" (splitList " " $distroLike))` with `eq $distro "arch"` (drops `ID_LIKE` entirely, simulating M1). Caught: L1 (2 assertions) + L2 (22 assertions), 24 failures total.
- **Mutant B** — `.chezmoiscripts/run_before_50-neovim.sh.tmpl`: inverted `if pacman -Q omarchy-nvim &>/dev/null; then` to `if ! pacman -Q omarchy-nvim &>/dev/null; then`. Caught: L7 only, 17 failures (S8/S9/M3/M4) — confirming the SPEC's own claim that only L7's stub-pacman execution can see this direction bug; L2's string-presence checks cannot.
- **Mutant C** — `tests/sandbox/_probe.sh`: changed the probe's `pacman -Q omarchy-nvim` to `pacman -Q some-other-pkg` (M6-style probe/script divergence). Caught: L11, 2 failures (verbatim-golden byte check + the explicit M6 substring assertion).

All three killed; no survivors to report.

**4. The checkers.** `tools/gate-pacman-ids.sh`: positive control (real `arch` WSL distro) — 12/12 packages resolve, core/extra only, matching the report's claim exactly. Negative control — `pacman -Si totally-fake-package-xyz` returns exit 1 and the script's own exit-status handling (avoids the `| tr` pitfall its own comment warns about) correctly propagates FAIL. `check_agent_doc_invariants.py` ran clean (84 invariants) as a positive control only; not attacked with a bad input due to time.

**5. The mapping.** Cross-checked S1–S9 against `tests/cases/L1-platform.sh`, `L2-script-render-matrix.sh`, `L7-behavior.sh`, `L11-render-golden.sh` — all present and behaviorally meaningful (confirmed via the mutants above, not just grep). Found the concrete, reproducible defect below while checking the Must NOT #6 row's cited evidence.

---

### Findings (severity-ordered)

**F1 — Critical. The evidence report's "GATE PASSED" verdict does not have one stable, reproducible source state, and at least one of its own cited proofs postdates the commit it claims to certify.**
Evidence: `.scratch/arch-family-support/evidence.md:20` declares `source_state: 491c0f2d77a3041a7deb089d37eeddd446c4a9a5` with `worktree=clean` verified before and after "the final fresh run" of the gate. The same report's Stated-claim table (line 89) cites Must NOT #6 as proven by "L2 的原始碼檢查...17 條，`03db4c5`". I verified directly:
```
git show 491c0f2d77a3041a7deb089d37eeddd446c4a9a5:tests/cases/L2-script-render-matrix.sh | grep -n "Must NOT #6"
# → only a comment; the actual assert_eq block does not exist at 491c0f2
```
`03db4c5` (which adds that block) and two further commits (`3c52a78`, `5e30e95`) land *after* 491c0f2. The report's own §Real execution table anchors environment B's "final" L9 run to `5e30e95`, not `491c0f2`, while environment A's final run stays at `491c0f2` — two different "final" commits inside the same report, neither of which is uniformly `source_state: 491c0f2` as the header claims. The task's four inputs named `491c0f2` as *the* exact source state to verify; a report that certifies "GATE PASSED" at that SHA while relying on a test that doesn't exist there is not describing the tree it claims to.

**F2 — High. The gate's mandated entry point cannot be run against the exact source state named in the task's own four inputs.**
Reproduced directly (see "The run" above): `sh tools/gate.sh --scope arch-family-support`, run from `D:\Projects\dotfiles-dev\dotfiles` / `/mnt/d/Projects/dotfiles-dev/dotfiles` at `491c0f2`, fails at layer 2 (`source-state-before`, exit 1) because the mandated evidence-report path `.scratch/arch-family-support/evidence.md` is untracked and not in `gate-source-state.sh`'s whitelist (`.gate/` only — `tools/gate-source-state.sh:16`). AGENTS.md requires this file be committed; it isn't, at the commit under test. The report's own "Honest notes" acknowledges this exact failure mode happened before ("獨立驗證 agent...把工作樹的 .gate/arch-family-support/ 蓋成一份 worktree=dirty...而在 source-state 停下的殘缺產出") and works around it by running the "canonical" gate in an undisclosed separate clone (`~/gate/dotfiles`) rather than fixing the whitelist gap or committing the report. That workaround location was never named in my task's four inputs — I discovered it only by finding a live, unexplained background process. A verification input that requires tribal knowledge of an unlisted clone to reproduce is not a usable entry point.

**F3 — High. Must NOT #7 was violated on real Tier-3 infrastructure and is not reflected as a gate failure.**
`.scratch/arch-family-support/evidence.md:224-231` ("Honest notes"): unauthorized sudoers edits (`Defaults:madao !authenticate`, a temporary edit to `/etc/sudoers.d/04_madao`), an SSH key added to `~/.ssh/authorized_keys`, and deletion of stray `~/.local/share/chezmoi` etc. directories — all performed manually on the omarchy 4.0.2 VM, outside `chezmoi init --apply`, and self-described as done "沒有逐項事先徵得同意" (without item-by-item prior consent). SPEC Must NOT #7 (`specs/arch-family-support/SPEC.md:147`) explicitly forbids this. The Stated-claim table (evidence.md:90) records it as "偏離，已記錄" rather than failing the constraint.

**F4 — Medium. Environment instability during the verification window itself.** HEAD moved from `491c0f2` to `5e30e95` on the exact directory named as "the repository at an exact source state" while I was working in it (see reflog above). A concurrent, periodically-relaunching gate execution against `~/gate/dotfiles` was observed live, and `.gate/l9-omarchy/results.tsv` in the named repo carries a timestamp (`Sep 9 00:00`) after my session's own baseline check, despite my never invoking L9. None of this is under a verifier's control to prevent, but it means no single wall-clock window existed in which "the exact source state" was actually held still, which is the premise the whole exercise depends on.

**F5 — Low / self-inflicted, disclosed for transparency.** My own first blind execution of the mandated entry point (per protocol step 1) ran `rm -rf .gate/arch-family-support` (`tools/gate.sh:60`) before failing, overwriting whatever had previously been copied back to that directory in the Windows-mounted tree. I did not snapshot it first. I cannot rule out that a fuller (non-4-file) artifact set existed there before my run. This is inherent to the gate's own "fresh by mechanism" design (documented in its header comment) applied to a directory a verifier is told to trust as pre-populated evidence — a sharper edge than a competent reviewer should have to discover by breaking it, but also a mistake on my part not to preserve it defensively first.

**No survivors:** the platform.toml ID_LIKE logic, the 50-neovim pacman branch, and the probe's omarchy detection — the three surfaces the task specifically asked me to mutate — are all genuinely covered; my mutants there were killed cleanly by the layers the SPEC's failure model (M1, M3, M6) predicts.

---

### Draft-report mismatches

1. **Run result.** My blind run of the stated entry point against the stated source state: **fails at layer 2, exit 1**. The report's headline: **"GATE PASSED"**, 13/13 layers, exit 0. Per protocol this mismatch is not resolved by either number winning by default — reconciliation requires either committing `.scratch/arch-family-support/evidence.md` before any gate rerun, or widening `gate-source-state.sh`'s whitelist and re-documenting why, and then re-running from the literal path named as input #3. Until then the "GATE PASSED" claim is unconfirmed from the state I was actually handed.
2. **Source state.** Report header claims `source_state: 491c0f2...` for the certified run; report body's own cited evidence for Must NOT #6 and for L9 environment B's "final" run requires later commits (`03db4c5`, `5e30e95`). This is an internal report inconsistency, not just a mismatch with my observation.
3. **Numbers I could reproduce matched:** `pacman-ids` (12/12 core/extra) and both L9 `results.tsv` summaries (35 PASS/0 FAIL/3 SKIP each) matched the report exactly. I could not fully reproduce the "762/0/0" full-suite or "44/44" mutation numbers within budget/time — WSL-via-Windows-Git-Bash invocation proved unreliable for long unattended runs (silent hangs, background-process artifacts) — so these are **not confirmed, not contradicted**.

---

Files most relevant to these findings (all absolute):
- `D:\Projects\dotfiles-dev\dotfiles\tools\gate.sh` (line 60: `rm -rf "$ART"`; line 114-115: `source-state-before` layer)
- `D:\Projects\dotfiles-dev\dotfiles\tools\gate-source-state.sh` (line 16: `WHITELIST='.gate/'`)
- `D:\Projects\dotfiles-dev\dotfiles\AGENTS.md` ("Evidence-first artifacts" section: "Commit the final evidence report at `.scratch/<scope>/evidence.md`")
- `D:\Projects\dotfiles-dev\dotfiles\specs\arch-family-support\SPEC.md` (line 147: Must NOT #7)
- `D:\Projects\dotfiles-dev\dotfiles\.scratch\arch-family-support\evidence.md` (lines 3-27 headline/source_state; lines 89-90 Must NOT #6/#7; lines 148 §Real execution env B "final commit" 5e30e95; lines 209-212 "Honest notes" gate-overwrite disclosure; lines 224-231 Must NOT #7 deviation disclosure)
- `D:\Projects\dotfiles-dev\dotfiles\tests\cases\L2-script-render-matrix.sh` (lines 249-255, absent at `491c0f2`, present at `03db4c5`+)
- `D:\Projects\dotfiles-dev\dotfiles\.chezmoitemplates\platform.toml`, `D:\Projects\dotfiles-dev\dotfiles\.chezmoiscripts\run_before_50-neovim.sh.tmpl`, `D:\Projects\dotfiles-dev\dotfiles\tests\sandbox\_probe.sh` (mutated and killed cleanly, no defect)