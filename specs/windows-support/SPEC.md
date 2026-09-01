# SPEC — Native Windows support (Tier 3)

- `spec_version`: v5
- `status`: approved
- `tier`: 3 — the change performs privileged package installation and moves
  pre-existing Neovim configuration directories. A wrong path or a process
  that continues after an elevation failure can lose a user's working setup.
- `intent record`: user request on 2026-09-01; v4 selected the requested
  `powerlevel10k_rainbow` theme. User-provided Windows Sandbox measurement
  subsequently established the initial Windows PowerShell 5.1 interpreter and
  an App Installer-free environment as an executable failure boundary. This
  revision needs explicit approval of v5 before its additional test or product
  change is written.

## Scope

Add **native Windows 10/11 x64** support. WSL remains Linux. Windows on ARM is
out of scope until it has an architecture-matched Neovim and parser-compilation
test. Windows uses WinGet, not Homebrew; Linux and macOS retain their existing
apt + Homebrew flows and package list.

Windows Nvim support is restricted to the default application name
(`NVIM_APPNAME` unset) and the standard `LOCALAPPDATA` location below the
user's home directory. A customised application name or redirected
`LOCALAPPDATA` must fail before backup or clone instead of silently writing to
the wrong location.

Windows uses PowerShell 7 (`pwsh`) plus Oh My Posh, rather than zsh, Oh My Zsh,
or Powerlevel10k. The managed target is the PowerShell 7 current-user,
all-hosts profile at `$HOME\Documents\PowerShell\Profile.ps1`, so the prompt
loads in every `pwsh` host without changing a Windows PowerShell 5.1 profile.
chezmoi must add exactly one delimited managed block, preserving all unrelated
profile content. That block runs `oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression`. The requested bare
theme name is an Oh My Posh theme pointer; on a cache miss it requires network
access while the shell starts. `--strict` resolves the command from `PATH`
after a package-manager upgrade rather than preserving a stale absolute path.

The first chezmoi Windows provisioning script can run in **Windows PowerShell
5.1** before `Microsoft.PowerShell` installs `pwsh`; all provisioning
`.ps1.tmpl` scripts must therefore parse and execute their prerequisite path
under that interpreter. This does not make Windows PowerShell 5.1 the managed
interactive shell or profile target.

WinGet/App Installer is a prerequisite for the documented bootstrap. A
standard Windows 11 installation commonly provides it, but an intentionally
more-minimal image (such as the measured Windows Sandbox) may not. In that
case, README and the package script must fail before any package invocation,
name App Installer, and tell the user to install or repair it before rerunning.
Its absence is a supported, actionable preflight failure—not evidence that all
Windows 11 is unsupported.

## Scenarios

1. **Windows renders PowerShell rather than zsh configuration**: given chezmoi
   template data `os=windows, arch=amd64`, each Unix `.sh.tmpl` install script
   renders empty, each Windows `.ps1.tmpl` install script renders non-empty,
   and the Windows source state contains only the PowerShell 7/Oh My Posh
   profile artifacts—not `.zshrc`, `.p10k.zsh`, `.oh-my-zsh`, or its plugins.
   Automated test: `test_windows_renders_powershell_not_zsh_shell_config` in
   `tests/test_chezmoi_templates.py`.

2. **Unix shell rendering stays intact**: given template data for `linux` or
   `darwin`, the Windows PowerShell scripts and PowerShell profile modifier
   render empty; Linux retains its apt prerequisite and Linux/macOS retain the
   current Homebrew formula list (`mise fzf git-lfs ripgrep fd lazygit
   tree-sitter`), `.zshrc`, `.p10k.zsh`, Oh My Zsh, and the current plugin
   order.
   Automated test: `test_unix_renders_only_unix_scripts_and_zsh_config` in
   `tests/test_chezmoi_templates.py`.

3. **Windows provisions the equivalent toolchain and shell**: given a native
   Windows apply whose first script interpreter is Windows PowerShell 5.1 and
   whose `winget` command is available, the package script parses under that
   interpreter and invokes non-interactive, exact-ID WinGet
   installs from the `winget` source for `Microsoft.PowerShell`,
   `JanDeDobbeleer.OhMyPosh`, `jdx.mise`, `junegunn.fzf`,
   `BurntSushi.ripgrep.MSVC`, `sharkdp.fd`, `JesseDuffield.lazygit`, and
   `tree-sitter.tree-sitter-cli`; it invokes elevated, waited installs for
   `Git.Git`, `GitHub.GitLFS`, and `Microsoft.VisualStudio.2022.BuildTools`
   with `Microsoft.VisualStudio.Workload.VCTools`. The PowerShell and Oh My
   Posh packages use the same non-interactive agreement flags and remain
   user-scope operations. Given that `winget` is absent, it must stop before
   any package invocation with an error that names App Installer and says to
   rerun after installation or repair.
   Automated tests: `Test-WingetPackageContract`,
   `Test-WindowsPowerShell51BootstrapCompatibility`, and
   `Test-WingetPrerequisiteFailureIsVisible` in `tests/windows_support.ps1`.
   The existing package script already contains a preflight guard, so these
   new checks are regression armor: their RED evidence must be a temporary
   removal or 5.1-incompatible mutant of that guard/script, restored before
   the test-only checkpoint is committed.

4. **The PowerShell profile is idempotent and preserves user content**: given
   a missing or pre-existing `$HOME\Documents\PowerShell\Profile.ps1`, the
   Windows profile modifier creates the parent directory if needed and writes
   exactly one chezmoi-delimited block containing `oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression`; it preserves
   all text outside that block and never writes a Windows PowerShell 5.1 or
   all-users profile. The modifier must preserve this exact theme pointer, not
   silently use Oh My Posh's default theme. Bootstrap must not run
   `Set-ExecutionPolicy`; if the effective policy blocks profile execution, the
   health check must report that failure rather than claim a configured prompt.
   Automated tests: `Test-PwshProfileManagedBlockPreservesUserContent`,
   `Test-OhMyPoshThemeContract`, and `Test-ProfilePolicyFailureIsVisible` in
   `tests/windows_support.ps1`.

5. **Elevation failure stops the apply**: given the user rejects UAC or the
   elevated WinGet process returns a non-zero exit code, the package script
   throws and chezmoi cannot mark that script as successfully run or proceed to
   Neovim setup.
   Automated test: `Test-ElevationFailureStopsApply` in
   `tests/windows_support.ps1`.

6. **Git LFS is configured only after target files exist**: given the Windows
   package step has succeeded, the `run_onchange_after_` Windows script runs
   `git lfs install --skip-repo` after chezmoi has created `~/.gitconfig`, and
   does not mutate the current repository.
   Automated test: `Test-GitLfsRunsAfterTargetsApplied` in
   `tests/windows_support.ps1`.

7. **Neovim uses its actual Windows configuration location**: given the
   default Windows environment, chezmoi applies this repo's Nvim override at
   `%LOCALAPPDATA%\nvim\lua\plugins\completion.lua` (the same content as
   Linux/macOS). The bootstrap script checks that this is the path chezmoi owns
   before it moves anything.
   Automated test: `test_windows_nvim_target_path` in
   `tests/test_chezmoi_templates.py`.

8. **First LazyVim bootstrap preserves user data**: given no repo marker and
   pre-existing default Nvim config/data/cache paths, the Windows bootstrap
   moves `%LOCALAPPDATA%\nvim`, `%LOCALAPPDATA%\nvim-data`, and
   `%TEMP%\nvim` to distinct non-destructive backup paths; it moves the shared
   data/state directory exactly once, clones the LazyVim starter into the
   actual config directory, removes only the clone's `.git`, and writes its
   marker. It obtains the paths from the pinned Nvim runtime without sourcing
   the user's init file.
   Automated test: `Test-FirstBootstrapPreservesUniquePaths` in
   `tests/windows_support.ps1`.

9. **Re-applying cannot overwrite a user’s post-bootstrap Nvim config**: given
   the repo marker already exists, the Windows bootstrap neither moves any Nvim
   directory nor clones again.
   Automated test: `Test-MarkerPreventsRebootstrap` in
   `tests/windows_support.ps1`.

10. **The installed toolchain and shell are useful in a normal session**: after a real
   Windows apply and a new ordinary `pwsh` session, PowerShell reports major
   version 7 or later, its current-user all-hosts profile loads without an
   error, and the configured `powerlevel10k_rainbow` theme resolves. That
   acceptance check must perform a cache-miss run on an isolated test account
   with network access and record the result; a pre-existing theme cache is not
   proof that first use works. `Get-Command` resolves `oh-my-posh`, `git`,
   `git-lfs`, `mise`, `fzf`, `rg`, `fd`, `lazygit`, and `tree-sitter`;
   `nvim --headless "+TSUpdate" +qa` and
   `nvim --headless "+checkhealth nvim-treesitter" +qa` exit successfully.
   Automated acceptance test: `Test-InstalledToolchainHealth -EndToEnd` in
   `tests/windows_support.ps1`, run only on an explicitly supplied Windows
   machine after a real apply; mocks and CI cannot substitute for this result.

11. **Documented first-run path works**: README supplies a Windows PowerShell
    first-run sequence that first checks `winget` availability before its first
    WinGet invocation. When absent, it must name App Installer and direct the
    user to install or repair it, then rerun. When present, it installs chezmoi
    from the exact WinGet ID and uses `chezmoi init --apply`, including branch
    selection, a new `pwsh` session, the UAC expectation for the C++ toolchain,
    and the fact that the requested theme pointer needs network access on a
    cache miss. It must give Nerd Font configuration as display guidance, not
    as a silently installed dependency.
    Automated test: `test_readme_windows_bootstrap_instructions` in
    `tests/test_chezmoi_templates.py`.

## Must NOT

- Must NOT run a Unix shell script, Homebrew command, apt command, zsh
  external, Oh My Zsh external, or Powerlevel10k artifact on native Windows.
- Must NOT deploy PowerShell artifacts to Linux/macOS, or change their zsh,
  Oh My Zsh, Powerlevel10k, or plugin-order contract.
- Must NOT alter Linux/macOS package ownership: OS prerequisites stay in
  `10-install-packages`, and shared Unix tools stay in
  `30-install-brew-packages`.
- Must NOT delete user Nvim config, data, state, cache, or a pre-existing
  backup. A marker only authorises removal of the `.git` created by the
  immediately preceding starter clone.
- Must NOT back up `%LOCALAPPDATA%\nvim-data` twice: pinned Nvim 0.12.5 uses it
  for both data and state.
- Must NOT overwrite or delete user content outside the chezmoi-delimited Oh My
  Posh block in `$HOME\Documents\PowerShell\Profile.ps1`; the modifier must
  converge to exactly one such block.
- Must NOT write a Windows PowerShell 5.1 profile, an all-users profile, or call
  `Set-ExecutionPolicy` / otherwise weaken execution policy.
- Must NOT use PowerShell 7-only syntax in any Windows provisioning `.ps1.tmpl`
  script before `Microsoft.PowerShell` has been installed.
- Must NOT invoke WinGet from the README bootstrap before it has checked that
  the `winget` command is available, or conceal an absent App Installer behind
  an unqualified command-not-found error.
- Must NOT classify an App Installer-free Sandbox as proof that normal Windows
  11 lacks WinGet or as a reason to withdraw Windows 10/11 x64 support.
- Must NOT use an Oh My Posh initialization command that embeds a versioned or
  absolute executable path; the managed block uses `--strict`.
- Must NOT silently fall back to Oh My Posh's default theme, a local relative
  filename, or a different theme: the managed command names
  `powerlevel10k_rainbow` exactly.
- Must NOT treat an existing Oh My Posh theme cache as proof that the requested
  theme pointer works on a first shell start.
- Must NOT treat a WinGet invocation, UAC launch, or `tree-sitter` executable
  alone as proof that parser compilation works.
- Must NOT claim Windows ARM64 support or support for `NVIM_APPNAME` / redirected
  `LOCALAPPDATA` in this change.
- Must NOT add a new runtime plugin, package manager, or unpinned CI action.

## Failure model (Tier 3 only)

| Failure mode | Check that catches it |
| --- | --- |
| Windows renders zsh/Oh My Zsh/Powerlevel10k, or Unix renders PowerShell artifacts | Scenarios 1 and 2 template-rendering tests assert each platform’s complete shell source state. |
| A profile edit deletes custom user lines, leaves duplicate managed blocks, writes the wrong profile, or loses the requested theme | Scenario 4’s `Test-PwshProfileManagedBlockPreservesUserContent` and `Test-OhMyPoshThemeContract` check sentinel content, convergence, current-user all-hosts target, and the exact theme command. |
| Oh My Posh breaks after a package-manager upgrade because the profile stores an old absolute executable path | Scenario 4 asserts the exact `init pwsh --config 'powerlevel10k_rainbow' --strict` contract; Scenario 10 opens a fresh `pwsh` session after real apply. |
| The named theme is unavailable on first use because no cache exists and the machine has no network | Scenario 10 performs a cache-miss run on an isolated test account with network access; Scenario 11 documents that operational precondition. |
| A restricted execution policy is silently weakened or a blocked profile is reported as configured | Scenario 4’s `Test-ProfilePolicyFailureIsVisible` rejects policy mutation; Scenario 10 records the real `pwsh` result. |
| The initial script uses PowerShell 7-only syntax and fails before it can install PowerShell 7 | Scenario 3’s `Test-WindowsPowerShell51BootstrapCompatibility` runs the rendered prerequisite path with Windows PowerShell Desktop 5.1 in Windows CI or Sandbox. |
| App Installer is absent, so a bare `winget` bootstrap fails opaquely or starts a partial apply | Scenario 3’s `Test-WingetPrerequisiteFailureIsVisible` proves the script stops before installs; Scenario 11’s README test requires the matching preflight and recovery text. |
| A wrong Nvim target causes chezmoi to apply config under `~/.config/nvim` instead of the Nvim runtime path | Scenario 7 target-path test plus the bootstrap path assertion. |
| User config/data/cache is lost, nested in an older backup, or data/state is moved twice | Scenario 8 generated filesystem combinations, including occupied `.bak` names. |
| Marker regression overwrites a user-owned config on a rerun | Scenario 9 asserts marker-present runs make no move/clone calls. |
| Required machine-scope installation is cancelled or fails while setup continues | Scenario 5 observes `Start-Process -Verb RunAs -Wait -PassThru` and a thrown error for every non-zero/cancelled result. |
| `tree-sitter` CLI is installed but cannot compile a parser | Scenario 10 real Windows acceptance test. |
| Linux/macOS bootstrap changes while adding Windows | Scenario 2 template rendering and formula-set assertion. |

## Setup plan

- Tools to install: no persistent development dependency. Tests use the
  repository's existing chezmoi binary and Python 3 standard library locally;
  Windows behavioural tests use Windows PowerShell Desktop 5.1 and PowerShell
  7 provided by the `windows-latest` GitHub-hosted runner. A temporary
  PowerShell 7 installation through mise is authorised only if needed to run
  the same test harness locally; it must be reported in evidence. Actual
  `winget install` is authorised only in Windows Sandbox or CI, never on the
  adjacent Windows host.
- Git isolation: the existing feature worktree; checkpoint commits in this
  cadence: approved SPEC, each RED behaviour, each corresponding GREEN
  behaviour, then gate tooling. For v5, the README preflight test must first
  fail against the current README and be committed before its documentation
  edit. The existing package-script preflight is regression armor: prove each
  new v5 check against a temporary mutant, restore it, and commit the test-only
  checkpoint without recasting the pre-existing v4 implementation as a v5
  GREEN change. The base ref is `0d72b8e` (`main`).
- Files the gate will add:
  `tests/test_chezmoi_templates.py`, `tests/windows_support.ps1`,
  `tests/mutate_windows_support.py`, `tools/gate.sh`, and
  `.github/workflows/windows-support.yml`.
- Files expected to change: Unix script templates and zsh/Oh My Zsh/
  Powerlevel10k source artifacts only to render on Linux/macOS; new Windows
  `.ps1.tmpl` script templates; a Windows PowerShell current-user all-hosts
  profile modifier; `.chezmoiignore`, `.chezmoiexternal.toml.tmpl`, the Nvim
  source-state layout/template, `README.md`, and both Windows research notes.
- New dependencies: none in the product. The CI workflow uses only the
  pinned official `actions/checkout` action at
  `11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2) to execute the
  repository-owned PowerShell test; it is pinned to prevent tag drift.
- Gate plan: run `tools/gate.sh` locally; the final report also records the
  Windows GitHub Actions run. A real Windows apply plus scenario 10’s health
  commands is mandatory acceptance evidence, not a claim made from mocked CI.

## Approval

Append-only. One entry per approved version: the approving words verbatim, the
date, and the `spec_version` they bind. An entry that cannot quote approval is
not approval.

- 2026-09-01 — `spec_version`: v4; approving words (verbatim): 「核准 SPEC v4」.
- 2026-09-01 — `spec_version`: v5; approving words (verbatim): 「v5 核准」.

## Revisions

Append-only.

- 2026-09-01 — exploration round 1: established native Windows x64 as the
  proposed scope; chose WinGet plus elevated Visual Studio Build Tools C++
  workload so Tree-sitter compilation is part of support; established the
  default Nvim path and the need for a separate Windows chezmoi target.
- 2026-09-01 — v2: relocated the SPEC to the workflow-required
  `specs/windows-support/SPEC.md` path and added a named automated test or
  acceptance command to every scenario before approval.
- 2026-09-01 — v3: added the missing native Windows shell contract:
  PowerShell 7 plus Oh My Posh, an idempotent current-user all-hosts profile
  block using `oh-my-posh init pwsh --strict`, source-state platform guards,
  policy and user-profile preservation constraints, and named verification.
- 2026-09-01 — v4: selected the requested Oh My Posh theme pointer,
  `powerlevel10k_rainbow`, and retained `--strict`; added exact-command tests,
  cache-miss network acceptance evidence, and first-run documentation and font
  guidance constraints.
- 2026-09-01 — v5: incorporated the user's clean Windows Sandbox measurement:
  Windows PowerShell Desktop 5.1 is the first provisioning interpreter;
  `winget`, `pwsh`, chezmoi, Git, and Nvim are absent when App Installer is
  deliberately excluded, while network is available. Added a PowerShell 5.1
  compatibility test, a no-side-effect App Installer/WinGet prerequisite
  failure test, and a matching README preflight. The current agent sandbox
  cannot independently execute the adjacent Windows host because WSL interop
  fails at a vsock bind, so Windows PowerShell 5.1 execution remains mandatory
  CI or Sandbox evidence. The already-present package-script guard will be
  tested as mutation-proven regression armor; README does not yet satisfy the
  new preflight and must show a normal RED. This material revision invalidates
  v4 approval for these additions. Historical compliance note: `40dd36f`
  committed v4's verbatim approval record before implementation, but its
  `status` remained `draft`; that is a workflow defect. v5's eventual approval
  must set `status: approved` in the same commit, and the final evidence must
  disclose the v4 status defect rather than treating it as confirmed intent.
