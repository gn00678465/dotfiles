# AGENTS.md

Chezmoi dotfiles source repository. Targets: Linux (Debian family and Arch,
with omarchy as the Arch reference), macOS, and native Windows.

## Daily dotfiles workflow

Keep shared configuration in this repository. Preserve user settings outside
the managed scope. Use templates for platform differences, as specified below.

Use `chezmoi -S <repo>` for this checkout. Replace `<repo>` with its absolute
path. The default source directory can point to a different checkout.
In the commands below, `<target>` is a destination path, such as `~/.zshrc`.

1. Inspect changes with `git diff` and `chezmoi -S <repo> status`.
   Use `chezmoi -S <repo> source-path <target>` to find its source file.
2. Edit the source file here, or use `chezmoi -S <repo> edit <target>`.
   For a new target, use `chezmoi -S <repo> add <target>`.
   To import local edits to a managed file, use
   `chezmoi -S <repo> re-add <target>`. This command skips templates;
   edit their source directly. Review the source diff after each import.
3. Inspect rendered content with `chezmoi -S <repo> cat <target>` and
   pending changes with `chezmoi -S <repo> diff`. Run the affected tests.
   Preview a full apply with `chezmoi -S <repo> apply --dry-run --verbose`.
4. Apply the requested scope with `chezmoi -S <repo> apply <target>`.
   Omit `<target>` only for a full apply, which can also run install scripts.
   The Windows host approval requirement below still applies.
   Check the remaining differences after apply.
5. Review `git diff` before committing and pushing the source changes
   within the user's requested scope. To receive changes, pull the source
   with Git, then repeat the preview and apply steps. `chezmoi update`
   combines pull and apply; the same apply restrictions apply to it.

To stop managing a file while keeping its local copy, use
`chezmoi -S <repo> forget <target>`.

## Required checks

Run `tests/check_agent_doc_invariants.py` after changes to the evidence-first
contract, `dot_agents/workflows/`, or the `verification-gate` and `spec-archive`
skills. It checks shared status values, report fields, tier definitions, and
anti-gaming rules. Exit code 1 means an invariant failed. Exit code 2 means
the check failed to run correctly.

Run `tests/spec_archive_test.py` after changes to the spec-archive script.
It checks cases that the script must reject.

## Platform selection

Use `.chezmoitemplates/platform.toml` as the only source of OS and
distribution decisions. Callers use
`{{- $p := includeTemplate "platform.toml" . | fromToml -}}` and read
`$p.os`, `$p.arch`, `$p.isWindows`, `$p.isPosix`, `$p.brewPrefix`,
`$p.distro`, or `$p.pkgManager`. Do not use `eq .chezmoi.os "..."` or
`.chezmoi.osRelease` elsewhere.

`$p.distro` is `.chezmoi.osRelease.id` on Linux and empty elsewhere.
`$p.pkgManager` is `pacman` when `$p.distro` is `arch`, `apt` on other Linux,
and empty on macOS and Windows. `$p.brewPrefix` is empty on Windows and Arch.
A non-empty `$p.brewPrefix` is the only signal that a platform uses Homebrew.
Guard Homebrew scripts and the `brew shellenv` lines with
`ne $p.brewPrefix ""`, not with `$p.isPosix`.

The partial defines `osOverride`, `archOverride`, and `distroOverride` for
tests. Use them to render all platforms on one host. No macOS hardware is
available. `tests/cases/L8` checks the OS overrides with Windows chezmoi.
`tests/sandbox/omarchy.sh` checks that real chezmoi on Arch reaches the same
`distro` and `pkgManager` values as the `os-arch` fixture.

Do not run chezmoi apply against the current Windows host's actual user
environment without explicit user approval. Template rendering, tests in
redirected environments, and Windows Sandbox tests are permitted.

Use `.chezmoitemplates/versions.toml` for values shared by POSIX and Windows
scripts: the neovim version, LazyVim starter URL, and marker filename.

## Install scripts (`.chezmoiscripts/`)

Wrap each complete script in a platform guard. On other platforms, render
it empty. Chezmoi skips empty scripts. A non-empty `.sh` on Windows stops
apply with `%1 is not a valid Win32 application`.
Do not use `.chezmoiignore` for platform isolation: it removes the script
from all platforms. See `docs/research/windows-native-support.md`, section 1.

Chezmoi runs `.ps1` through `pwsh -NoLogo -File` on Linux and Windows.
PowerShell scripts also need platform guards.

Keep the Windows `.ps1` interpreter configuration in `.chezmoi.toml.tmpl`.
The `[interpreters.ps1]` block permits scripts under `ExecutionPolicy Restricted`
for the spawned process only. It sets `-NoProfile` to prevent loading
the profile that this repository installs. Chezmoi writes rendered scripts
to `%TEMP%`. The configuration from `chezmoi init` applies to scripts in the
same `init --apply` run. Do not call `Set-ExecutionPolicy` from `init.ps1`.
See `docs/research/windows-native-support.md`, section 1.6.

Keep the POSIX and Windows scripts consistent:

- `05-wsl-user-runtime-dir`: Guard with `.isWSL`. Run
  `loginctl enable-linger` once so logind creates `/run/user/<uid>` at boot.
  WSL exports `XDG_RUNTIME_DIR` but does not create the directory through PAM.
  On chezmoi v2.72.0, this caused `update`, `git`, and `cd` to fail with
  `mkdir /run/user/1000: permission denied`; `apply` used a different path.
  Do not add an `XDG_RUNTIME_DIR` fallback to `.zshrc`. It would cover only
  processes started from zsh.
- `10-install-packages`: Install Linux OS prerequisites only. The apt branch
  installs `zsh git curl` and Homebrew installer requirements. The pacman
  branch installs `zsh git curl base-devel`. Do not add tools here.
- `30-install-brew-packages`: Keep the POSIX tool list here so Debian and
  macOS receive the same tools. Add new tools here, to
  `30-install-pacman-packages` for Arch, and to `30-install-winget-packages`
  for Windows.
- `30-install-pacman-packages`: The pacman tool list. It equals the brew list
  plus `neovim`, because Arch installs neovim through pacman. `tests/cases/L2`
  compares the two lists. All names are in the official `core` and `extra`
  repositories; do not add AUR packages. Both pacman scripts include
  `.chezmoitemplates/pacman-install.sh`, which runs only
  `pacman -S --needed --noconfirm`. Do not add `-Sy`, `-Syu`, `-R`, or
  `--overwrite`. A stale package database stops the script with a message.
  `tools/gate-pacman-ids.sh` resolves every name with `pacman -Si`.
- `30-install-winget-packages`: Do not add `Microsoft.PowerShell` or `Git.Git`.
  They belong in `init.ps1`: chezmoi needs git to clone and pwsh 7 to run scripts.
- `35-install-ps-modules`: Install Windows PowerShell Gallery modules that
  winget does not provide. The current module is PSFzf.
- `40-git-lfs`: Keep `run_onchange_after_` on both platforms.
  `git lfs install` must follow `create_empty_dot_gitconfig` so it writes
  `~/.gitconfig`, not the managed `~/.config/git/config`. The `brew shellenv`
  line renders only when `$p.brewPrefix` is non-empty; on Arch, git-lfs comes
  from pacman and is on PATH.
- `50-neovim`: Renders empty on Arch. Arch installs neovim through pacman,
  and omarchy supplies its LazyVim configuration in `~/.config/nvim` through
  the `omarchy-nvim` package. The script must not back up, move, or replace
  that directory. The managed `lua/plugins/completion.lua` is applied on top
  of it. The `versions.toml` neovim pin does not apply to Arch.
- `50-neovim`: Install neovim through mise at the version in
  `versions.toml`. Read the script's version comment before an update.
  Clone the LazyVim starter from `main` once into `~/.config/nvim`, then
  remove its `.git`. This clone has no pinned ref or checksum, as on POSIX
  before Windows support. It and the `.oh-my-zsh` tarball are exceptions
  to the external download pinning rule.
- `50-neovim`: Before installation, move existing `~/.config/nvim`,
  `~/.local/share/nvim`, `~/.local/state/nvim`, and `~/.cache/nvim` to `.bak`.
  Do not delete them. The `.chezmoi-lazyvim-starter` marker prevents repeated
  backups of the user's configuration. Windows backs up three directories:
  `stdpath("state")` and `stdpath("log")` share `stdpath("data")`.
- `50-neovim`: Keep `run_before_` on both platforms. The clone must precede
  managed files under `private_dot_config/nvim/` because git requires an
  empty target. Plain `run_` also restores neovim after user removal.
  `run_onchange_` would require clearing both `scriptState` and `entryState`
  to repeat an unchanged script. Do not use `exact`; unmanaged files remain
  available for the user to edit.
- `60-pwsh-profile`: Resolve `$PROFILE.CurrentUserAllHosts` at run time and
  write a one-line loader there. Documents can be redirected to OneDrive;
  the target cannot be computed by a chezmoi path template. Keep the logic
  in `.chezmoitemplates/pwsh-profile-loader.ps1` so tests need no real profile.

Before a Windows script uses an installed binary, include
`.chezmoitemplates/windows-path.ps1`. The process PATH does not reflect
tools installed by a preceding script.

Before a script uses a brew binary, run
`eval "$(<prefix>/bin/brew shellenv)"`. Chezmoi scripts do not inherit
the interactive shell PATH.

On Arch, `dot_zshrc.tmpl` and `dot_zprofile.tmpl` load omarchy's
`default/bash/env-bootstrap` instead of `brew shellenv`. It uses POSIX sh
syntax and sets `OMARCHY_PATH` and PATH. Do not load `default/bash/rc`; it is
bash-only. `/etc/omarchy.conf` is read first because a dev-link install keeps
omarchy in `~/.local/share/omarchy` instead of `/usr/share/omarchy`.
`~/.config/git/config` is fully managed on all platforms; on omarchy, this
replaces the file that the omarchy installer wrote.

Keep `init.ps1` and `tests/sandbox/_probe.ps1` ASCII-only, including comments.
Windows PowerShell 5.1 reads BOM-less scripts with the ANSI code page;
incorrectly decoded comments can cause parse errors. Scripts under
`.chezmoiscripts/` use pwsh 7, which reads UTF-8.

Keep `tree-sitter-cli` in the brew package list. LazyVim's nvim-treesitter
`main` branch runs `tree-sitter build` for each parser. Since version 0.27,
the `tree-sitter` formula supplies only the library. Without the CLI,
LazyVim installs mason's prebuilt binary, which requires glibc 2.39 and
fails on Debian 12 with glibc 2.36. The brew bottle uses brew's glibc.
Mason places its bin directory first on PATH inside nvim. An existing mason
copy at `~/.local/share/nvim/mason/packages/tree-sitter-cli` must be removed
before nvim can use brew's copy.

Keep `BrechtSanders.WinLibs.POSIX.UCRT` (gcc) in the Windows package list.
LazyVim also needs a C compiler. The nvim-treesitter requirement check
rejected zig even with version 0.16.0 on PATH. Do not restore `zig.zig`
as its compiler. See `docs/research/windows-native-support.md`, section 10.1.

Keep LF checkout rules in `.gitattributes`. Git for Windows with
`core.autocrlf=true` otherwise checks out CRLF, which chezmoi copies into
managed files. The `modify_` templates compare literal lines and do not
remove CR. `tests/cases/L3` checks this with `git check-attr eol`.

## `modify_` files

Keep both sources as modify-templates, starting with
`{{- /* chezmoi:modify-template */ -}}`. Chezmoi renders them on all platforms.
Do not convert them to shell scripts: chezmoi executes those, which fails
on Windows.

The codex rewriter inherits limitations from the original `awk` version.
Each managed key must be a bare key on one line under a plain `[tui]` header.
Known inputs that produce invalid TOML include:

- A multiline `status_line` array. The managed array has eight elements.
- `[[tui]]` or `["tui"]` headers.
- An inline `tui = { ... }` table.
- A quoted `"status_line" =` key.

This list is not exhaustive. `KNOWN_LIMITATION` in `tools/gate-properties.py`
checks only byte identity with the original output for these cases.
It does not establish correct TOML handling.

Preserve these outputs in unrelated tasks. A user request to fix a listed
defect authorizes the corresponding behavior change. Update its tests and
this limitation list together. Other applicable approval requirements
still apply.

## Tests

For routine changes, run affected tests and the required checks above.
Run the full gate when the evidence-first contract applies or the user
requests full verification. Report checks that could not run.

`tests/run.sh` needs POSIX sh and chezmoi. Select layers with, for example,
`tests/run.sh L3 L6`.

| Layer | Check |
| --- | --- |
| L1 | Platform partial |
| L2 | Script render matrix |
| L3 | Managed targets and LF attributes |
| L4 | Syntax |
| L5 | Externals |
| L6 | Expected file output, including data preservation |
| L7 | Script behavior in a redirected environment |
| L8 | Platform overrides with Windows chezmoi |
| L11 | Exact rendered output for `init.ps1`, `_probe.ps1`, Windows scripts, and Arch zsh files |

L4, L7, and L8 skip without WSL interop. The other listed layers do not
require it. The `native-wsl` assertions in L2 need a Linux host.

L9 tests installation in a disposable environment. See
`tests/sandbox/README.md`:

- Arch: Run `tests/sandbox/omarchy.sh`. It runs `_probe.sh` inside the
  user's existing `omarchy` WSL distro, which is not disposable. The
  launcher copies the source tree in through a pipe, runs the probe, and
  copies `/out` back to `.gate/l9-omarchy/`. It never runs pacman itself.
  The probe does not remove packages on Arch.

- Windows: Run `_probe.ps1` in Windows Sandbox. Local mode uses `prepare.sh`
  and `sandbox.wsb` to test an unpushed tree. Remote mode uses `irm | iex`
  inside Sandbox to test a pushed branch. Only printed output remains
  after Sandbox closes.
- Linux: Run `_probe.sh` through `docker.sh` or `wsl.sh`.
  Docker uses `debian:12` without systemd, so linger and `chezmoi update`
  checks skip. The fresh `chezmoi-probe` WSL distro uses systemd to test
  the runtime directory fix. Both Linux probes also test a second apply,
  `chezmoi git`, and neovim removal and reinstallation.

`tools/gate.sh --scope <scope>` runs the suite, repeated and shuffled suite
runs, property cases, hand-written mutants, external, winget, and pacman
package name resolution, changed-line coverage, and source-state checks
before and after execution. The scope names `specs/<scope>/SPEC.md` and the
`.gate/<scope>/` output directory. It can be omitted only when `specs/` holds
one SPEC outside `archive/`.

`gate-intent.sh` derives `intent_status` and `intent_source` from the committed
SPEC. Copy these headers verbatim into the evidence report.
`spec-archive` rejects a report that does not quote the SPEC's `spec_version`.

Run every layer through `run_layer` to preserve its exit code instead of
`tee`'s. `gate-manifest-audit.sh` fails if a declared layer did not run.
Gate artifacts go in `.gate/<scope>/`, which git ignores.

## Evidence-first artifacts

Store specs at `specs/<scope>/SPEC.md`. The CLOSE step reads this fixed path.
Commit the final evidence report at `.scratch/<scope>/evidence.md`.
Keep it outside `specs/` because `spec-archive` moves the entire spec directory.
The `windows-support` report is the worked example of specification,
verification, evidence, and archive steps.
