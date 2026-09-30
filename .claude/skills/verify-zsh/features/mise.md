# mise activation

Tools installed with mise resolve in every shell. Interactive shells run the
mise hook through the Oh My Zsh `mise` plugin. Non-interactive login shells get
the mise shims from `.zprofile`.

## Sub-features

- `mise-hook` defines `_mise_hook` and sets `MISE_SHELL=zsh` in interactive shells.
- `mise-shims` puts `~/.local/share/mise/shims` on PATH in `zsh -lc`.
- `mise-binary` resolves `mise` itself in both.

## How to get to it (user POV)

- Open a terminal and run a mise-managed tool (`interactive`).
- Run `ssh host <tool>` or a script with `zsh -lc <tool>` (`login`).

## Driving it with zsh-probe

Preconditions:

- Baseline from `README.md`.
- `mise` is installed on the host (`/usr/bin/mise` on Arch, brew elsewhere).

- **Interactive hook.** Run
  `$P drive "$RUN" mise-interactive interactive 'whence -w _mise_hook; whence -p mise; print -r -- $MISE_SHELL'`.
  `.out` contains `_mise_hook: function`, a mise path, and `zsh`.
- **Login shims.** Run
  `$P drive "$RUN" mise-login login 'print -r -- "$PATH"; whence -p mise'`.
  `.out` contains `<HOME>/.local/share/mise/shims`.
- **Clean stderr.** Both `.err` files are empty.

## Gotchas

- The throwaway HOME has no mise tools installed. Prove activation with the
  hook and the shims directory, not by running a mise-managed tool.
- A `[WARN] migrate` or trust prompt in `.err` means mise read a real config.
  Check that the run's HOME is under `/tmp`.
