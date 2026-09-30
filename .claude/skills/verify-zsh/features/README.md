# zsh startup verification map

This directory is the maintained source for verifying what a user gets from
the managed `.zshrc`, `.zprofile`, and `.p10k.zsh`. Read this index, then use
the matching feature file as the recipe.

## Baseline preconditions

- Run from the repo root with `P=.claude/skills/verify-zsh/scripts/zsh-probe.sh`.
- `RUN=$($P up)` created the run from the current source.
- `$P doctor "$RUN"` prints no `STALE` or `FAIL` line.
- `~/.zshrc.local` in the run's HOME is `absent` unless a recipe says otherwise.
- Never drive the real HOME. Never run `chezmoi apply` to verify.

## Driving conventions

- Every action is `$P drive "$RUN" <label> <mode> '<zsh command>'`. Use a
  label that names the feature and the entry point, such as `path-login`.
- Treat modes as user entry points. The table in `../SKILL.md` maps each one.
- Assert on `$RUN/evidence/<label>.out`, `.err`, and `.rc`, not on the
  rendered file.
- Set `.zshrc.local` only through `$P local`, so the `.cmd` file records it.

## Proof and skip reporting

- Cite the run directory and the labels for every claim.
- A fix needs a failing run before the change and a passing run after it.
- Behavior that depends on another platform (brew on Debian or macOS) is not
  reachable from this host. Report it as unverified at runtime, and cite the
  render tests (`tests/run.sh L2 L4 L11`) instead.
- Do not report an entry point as verified through a different mode.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the
user-visible behavior. It then uses exactly four H2 sections in this order:
`Sub-features`, `How to get to it (user POV)`, `Driving it with zsh-probe`,
and `Gotchas`.

## Features

- [PATH](./path.md) covers `~/.local/bin`, platform tool paths, and duplicate
  entries across login, interactive, and session-inherited shells.
- [mise activation](./mise.md) covers the hook in interactive shells and the
  shims in non-interactive login shells.
- [Per-machine overrides](./zshrc-local.md) covers `~/.zshrc.local`.
- [p10k prompt](./p10k-prompt.md) covers instant prompt, the first-prompt
  status, and the console-output warning.
