# PATH

Every way a user starts zsh ends with `~/.local/bin`, the platform's tool
directories, and the mise shims on PATH, each listed once. On the Arch family,
omarchy's env-bootstrap also puts `omarchy-*` on PATH. On brew platforms,
`brew shellenv` adds the Homebrew prefix.

## Sub-features

- `path-local-bin` puts `~/.local/bin` on PATH in every mode.
- `path-platform` adds the brew prefix or runs omarchy's env-bootstrap.
- `path-unique` leaves no duplicate PATH entry in any mode.

## How to get to it (user POV)

- Open a terminal emulator (`interactive`).
- Open a terminal inside a Hyprland/uwsm session (`inherit`).
- Log in over ssh or on a tty, or run `zsh -l` (`login-interactive`).
- Run a command through `ssh host cmd` or `zsh -lc` (`login`).

## Driving it with zsh-probe

Preconditions:

- Baseline from `README.md`. `.zshrc.local` is `absent`.

- **Each entry point.** For each mode `interactive`, `inherit`,
  `login-interactive`, and `login`, run
  `$P drive "$RUN" path-<mode> <mode> 'print -r -- "$PATH"'`.
  Each `.out` contains `<HOME>/.local/bin`.
- **No duplicates.** For each label, run
  `tr ':' '\n' < "$RUN/evidence/path-<mode>.out" | sort | uniq -d`.
  The output is empty.
- **Platform tools.** On Arch, run
  `$P drive "$RUN" path-omarchy interactive 'print -r -- $OMARCHY_PATH; whence -p omarchy-version'`.
  `.out` shows an omarchy path and a resolved `omarchy-version`.
- **Proof.** `$P check "$RUN"` asserts the duplicate rule for all four modes
  and writes `summary.txt`.

## Gotchas

- `interactive` alone hides the login-shell duplicates, because `.zprofile`
  does not run. Always drive `login-interactive` and `login` too.
- `inherit` models a session PATH that already holds `~/.local/bin` at the
  end. `.zshrc` then prepends another copy unless it removes duplicates.
- `typeset -U path` does not remove duplicates from scalar `PATH=` assignments.
