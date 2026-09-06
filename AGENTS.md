# AGENTS.md

Chezmoi dotfiles source repository. Targets: Linux, macOS, and native Windows.

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

Use `.chezmoitemplates/platform.toml` as the only source of OS decisions.
Callers use `{{- $p := includeTemplate "platform.toml" . | fromToml -}}`
and read `$p.os`, `$p.arch`, `$p.isWindows`, `$p.isPosix`, or `$p.brewPrefix`.
Do not use `eq .chezmoi.os "..."` elsewhere.

The partial defines `osOverride` and `archOverride` for tests.
Use them to render all three platforms on Linux. No macOS hardware is
available. `tests/cases/L8` checks the overrides with Windows chezmoi.

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
- `10-install-packages`: Install Linux OS prerequisites only:
  `zsh git curl` and Homebrew installer requirements. Do not add tools here.
- `30-install-brew-packages`: Keep the POSIX tool list here so Linux and
  macOS receive the same tools. Add new tools here and to
  `30-install-winget-packages` for Windows.
- `30-install-winget-packages`: Do not add `Microsoft.PowerShell` or `Git.Git`.
  They belong in `init.ps1`: chezmoi needs git to clone and pwsh 7 to run scripts.
- `35-install-ps-modules`: Install Windows PowerShell Gallery modules that
  winget does not provide. The current module is PSFzf.
- `40-git-lfs`: Keep `run_onchange_after_` on both platforms.
  `git lfs install` must follow `create_empty_dot_gitconfig` so it writes
  `~/.gitconfig`, not the managed `~/.config/git/config`.
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
| L11 | Exact rendered output for `init.ps1`, `_probe.ps1`, and Windows scripts |

L4, L7, and L8 skip without WSL interop. The other listed layers do not
require it.

L9 tests installation in a disposable environment. See
`tests/sandbox/README.md`:

- Windows: Run `_probe.ps1` in Windows Sandbox. Local mode uses `prepare.sh`
  and `sandbox.wsb` to test an unpushed tree. Remote mode uses `irm | iex`
  inside Sandbox to test a pushed branch. Only printed output remains
  after Sandbox closes.
- Linux: Run `_probe.sh` through `docker.sh` or `wsl.sh`.
  Docker uses `debian:12` without systemd, so linger and `chezmoi update`
  checks skip. The fresh `chezmoi-probe` WSL distro uses systemd to test
  the runtime directory fix. Both Linux probes also test a second apply,
  `chezmoi git`, and neovim removal and reinstallation.

`tools/gate.sh` runs the suite, repeated and shuffled suite runs, property
cases, hand-written mutants, external and winget ID resolution, changed-line
coverage, and source-state checks before and after execution.

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
