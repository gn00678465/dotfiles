# AGENTS.md

Chezmoi dotfiles source repository.

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, with label strings equal to their names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Contract invariants

`tests/check-agent-doc-invariants.sh` guards the cross-file promises between
the evidence-first contract, the workflow reference (`dot_agents/workflow/`),
and the `verification-gate` skill (status vocabularies, report fields, shared
tier and anti-gaming definitions). Run it after editing any of those files;
rc 1 = invariant broken, rc 2 = the check itself broke.

## Install scripts (`.chezmoiscripts/`)

Linux **and macOS** are both targets. Keep them in sync:

- `10-install-packages` (apt, Linux only) holds OS prerequisites only: `zsh git curl` plus what the Homebrew installer needs. Do not add tools here.
- `30-install-brew-packages` (brew, both OS) is the single list for tools (`mise fzf git-lfs`, ...). New tools go here so macOS gets them too.
- `40-git-lfs` is `run_onchange_after_` on purpose: `git lfs install` must run after `create_empty_dot_gitconfig` so it writes `~/.gitconfig`, not chezmoi-owned `~/.config/git/config`.
- Anything needing a brew binary inside a script must `eval "$(<prefix>/bin/brew shellenv)"` first; chezmoi runs scripts without the interactive shell PATH.
