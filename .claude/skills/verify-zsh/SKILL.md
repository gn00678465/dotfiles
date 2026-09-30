---
name: verify-zsh
description: >-
  Verify the zsh startup files this chezmoi repo manages (.zshrc, .zprofile,
  .p10k.zsh) by starting real zsh sessions against the current source in a
  throwaway HOME: login, interactive, session-inherited PATH, and a pty that
  reaches the powerlevel10k prompt. Use before and after any change to
  dot_zshrc.tmpl, dot_zprofile.tmpl, dot_p10k.zsh, or the Oh My Zsh externals,
  and when a user reports PATH, mise, first-prompt status, p10k warning, or
  ~/.zshrc.local problems. Complements tests/run.sh, which only renders and
  parses these files.
---

# Verify zsh startup

`tests/run.sh` proves the templates render and parse. It never starts a shell.
This skill starts one. The user of these files is a person opening a terminal,
an ssh session, or a `zsh -l -c` from a script. Drive those entry points.

Runtime driving covers the host's platform only. The shells source what is
installed here (Oh My Zsh, mise, omarchy's env-bootstrap on Arch). For another
platform, render with the fixtures and run `tests/run.sh L2 L4 L11`. Do not
report brew-platform runtime behavior as verified from an Arch host.

The helper is `scripts/zsh-probe.sh` in this skill's directory. Below it is
`$P`. Every command is POSIX sh and needs `chezmoi`, `zsh`, `git`, and
`script` (util-linux) on PATH.

```sh
P=.claude/skills/verify-zsh/scripts/zsh-probe.sh   # from the repo root
```

## Launch

```sh
RUN=$($P up)
```

`up` renders `~/.zshrc`, `~/.zprofile`, and `~/.p10k.zsh` from this checkout
with `chezmoi -S <repo> cat`, so it uses the host's real chezmoi config data
(`isWSL` and the rest). It copies `~/.oh-my-zsh` and `~/.cache/gitstatus` into a
new HOME under `${TMPDIR:-/tmp}/verify-zsh-home.*`, and prints the run
directory `.gate/verify-zsh/<stamp>-<id>/`. Nothing listens and nothing stays
running, so "ready" means `up` exited 0.

Each run has its own HOME, so runs can go in parallel. The real HOME is never
written. The one exception is chezmoi's own read of its config.

## Doctor

```sh
$P doctor "$RUN"
```

Read-only. It checks that the three files in the run's HOME still match what
the current source renders. `STALE` means you edited the source after `up`.
Run `down` and then `up` again. Do not copy the file in by hand. It also
checks that the Oh My Zsh copy exists and that HOME is not the real one, and
prints the zsh version. Run it first whenever a result looks wrong.

## Drive

The standard set, with PASS/FAIL per assertion and exit 1 on any FAIL:

```sh
$P check "$RUN"
```

One scenario at a time:

```sh
$P local "$RUN" absent|quiet|noisy|failing          # choose the ~/.zshrc.local variant
$P drive "$RUN" <label> <mode> ['<zsh command>']     # default command prints RC=$?
```

The modes are the ways a user reaches these files:

| mode | zsh flags | user entry point |
| --- | --- | --- |
| `interactive` | `-i -c` in a pty | a terminal emulator started with a clean env |
| `login-interactive` | `-l -i -c` in a pty | ssh, a tty login, `zsh -l` |
| `login` | `-l -c`, no terminal | `ssh host cmd`, a script that runs `zsh -lc` |
| `inherit` | `-i -c` in a pty | a terminal started inside a Hyprland/uwsm session, which already exports `~/.local/bin` and the mise shims |
| `pty` | `zsh -i` in a pty | a real terminal that draws the p10k prompt; sends the command, then `exit` |

Every mode starts from `env -i` with `PATH=/usr/local/bin:/usr/bin:/bin` and
the working directory set to the throwaway HOME. The `-c` modes keep stderr
in its own file and strip `\r` from stdout. `$?` at the start of the `-c`
command is the status the last startup line left behind. That is the status
p10k shows on the first prompt.

The feature map in `features/` lists each behavior and its recipe. Read
`features/README.md` before proving a feature. A proof covers every entry
point the map lists for that feature.

## Evidence

Every `drive` writes four files under `$RUN/evidence/`: `<label>.cmd` (mode,
command, and the `.zshrc.local` content used), `<label>.out`, `<label>.err`,
and `<label>.rc`. `check` adds `summary.txt`. `up` writes `source-rev`, the
commit and the `git diff --stat` of the zsh sources that the run rendered.

Proof standards:

- Drive a real shell in the mode the user uses. Reading the rendered file is
  not proof of runtime behavior.
- For a fix, keep a failing run from before the change and a passing run
  after it. Cite both run directories.
- A negative assertion needs a positive control in the same run. `check`
  proves p10k does warn on a noisy `.zshrc.local` before it trusts "no
  warning" on a clean start.
- A `pty` run that ends before the first prompt proves nothing about p10k. The
  helper waits for `p10k-instant-prompt-<user>.zsh` to appear, and the first
  pty run in a fresh HOME only warms that cache.

## Cleanup

```sh
$P down "$RUN"
```

It deletes the throwaway HOME under `${TMPDIR:-/tmp}` and refuses any other
path. Each live HOME takes about 18 MB. On this host `/tmp` is a 2 GB tmpfs
that other sessions share, and `tests/run.sh L6` once failed with `disk quota
exceeded` while two runs were still up. Run `down` before `tests/run.sh`. `$RUN/evidence/` stays. `.gate/` is gitignored and chezmoi ignores
dot-directories in the source, so evidence never reaches git or `$HOME`. Delete
old run directories by hand when they are no longer cited.

## Gotchas

- Do not place the throwaway HOME under `/home/<user>/`. mise reads
  `.config/mise/` from every ancestor of the working directory and picks up
  the real `~/.config/mise/config.toml`. Every shell then prints `[WARN]
  migrate` and trust prompts. The helper uses `/tmp` for this reason.
- Do not drive `zsh -i` without a terminal. p10k's gitstatus then fails
  `setopt monitor` and prints `gitstatus failed to initialize`, which no user
  sees. The helper runs every interactive mode under `script`.
- `typeset -U path` removes duplicates only when something assigns to the
  `path` array. `export PATH=...`, `brew shellenv`, and `mise activate` assign
  to the scalar and keep duplicates.
- The p10k first-prompt `$?` sometimes read 1 in earlier pty experiments,
  with the cause not found. If a pty run disagrees with `interactive`, repeat
  both before you report a regression.
