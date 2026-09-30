# Per-machine overrides

A user keeps settings that only one machine needs in `~/.zshrc.local`.
chezmoi does not manage that file, so `chezmoi apply` and `chezmoi update`
never overwrite it. `.zshrc` sources it last, so it can override aliases,
environment variables, and `POWERLEVEL9K_*` settings.

## Sub-features

- `local-absent` starts cleanly with status 0 when the file does not exist.
- `local-sourced` applies the file's exports and aliases.
- `local-last` lets the file override settings from `.zshrc` and `.p10k.zsh`.
- `local-status` passes the file's last status through to the first prompt.

## How to get to it (user POV)

- Create or edit `~/.zshrc.local`, then open a new terminal.

## Driving it with zsh-probe

Preconditions:

- Baseline from `README.md`.

- **Absent.** Run `$P local "$RUN" absent` and
  `$P drive "$RUN" local-absent interactive`. `.out` is `RC=0`. `.err` is empty.
- **Sourced.** Run `$P local "$RUN" quiet` and
  `$P drive "$RUN" local-quiet interactive 'print -r -- "RC=$? LOCAL_MARK=$LOCAL_MARK"; alias ll'`.
  `.out` contains `RC=0 LOCAL_MARK=1` and `ll='ls -l'`.
- **Overrides p10k.** Write `typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet` to
  the run's `~/.zshrc.local` and run
  `$P drive "$RUN" local-p10k interactive 'print -r -- $POWERLEVEL9K_INSTANT_PROMPT'`.
  `.out` is `quiet`, although `.p10k.zsh` sets `verbose`.
- **Failing last line.** Run `$P local "$RUN" failing` and
  `$P drive "$RUN" local-failing interactive`. `.out` is `RC=1`. This is the
  user's own status and is expected.
- **Reset.** Run `$P local "$RUN" absent`.

## Gotchas

- The file cannot change `plugins=()` or `ZSH_THEME`. Oh My Zsh reads them
  before the file loads.
- Output from the file during startup triggers the p10k console-output
  warning. See `p10k-prompt.md`.
