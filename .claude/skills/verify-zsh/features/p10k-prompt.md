# p10k prompt

A user opening a terminal sees the powerlevel10k instant prompt, then the
full prompt. The first prompt shows no error status, and p10k prints no
console-output warning when startup is quiet.

## Sub-features

- `p10k-cache` writes the instant-prompt cache after the first prompt.
- `p10k-quiet` prints no console-output warning on a clean startup.
- `p10k-warns` prints the warning when startup writes to the console.
- `p10k-status` leaves status 0 for the first prompt.

## How to get to it (user POV)

- Open a new terminal (`pty`).

## Driving it with zsh-probe

Preconditions:

- Baseline from `README.md`.

- **Warm the cache.** Run `$P drive "$RUN" p10k-warmup pty true`. The run's
  HOME then contains `.cache/p10k-instant-prompt-<user>.zsh`.
- **Positive control.** Run `$P local "$RUN" noisy` and
  `$P drive "$RUN" p10k-noisy pty true`. `.out` contains
  `Console output during zsh initialization`.
- **Clean start.** Run `$P local "$RUN" absent` and
  `$P drive "$RUN" p10k-clean pty true`. `.out` does not contain that text.
- **First-prompt status.** Run `$P drive "$RUN" p10k-status interactive`.
  `.out` is `RC=0`. This is the status the prompt's status segment reads.

## Gotchas

- The first pty run in a fresh HOME only writes the cache. The warning never
  appears in that run, so a "no warning" result from it proves nothing.
- `.out` holds raw terminal output with escape sequences. Use `grep -a`.
- Earlier pty experiments sometimes read a first-prompt status of 1 with no
  identified cause. Repeat before you report it.
