# AGENTS.md

Chezmoi dotfiles source repository.

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature-slug>/` in this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, with label strings equal to their names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Install scripts (`.chezmoiscripts/`)

Linux **and macOS** are both targets. Keep them in sync:

- `10-install-packages` (apt, Linux only) holds OS prerequisites only: `zsh git curl` plus what the Homebrew installer needs. Do not add tools here.
- `30-install-brew-packages` (brew, both OS) is the single list for tools (`mise fzf git-lfs`, ...). New tools go here so macOS gets them too.
- `40-git-lfs` is `run_onchange_after_` on purpose: `git lfs install` must run after `create_empty_dot_gitconfig` so it writes `~/.gitconfig`, not chezmoi-owned `~/.config/git/config`.
- `50-neovim` installs neovim through mise (not brew, and pinned to an explicit version -- see the comment there before bumping) and clones the LazyVim starter into `~/.config/nvim` once, then deletes its `.git`. It is `run_onchange_before_` on purpose: `git clone` refuses a non-empty target, so the starter must land before chezmoi applies the files it owns under `private_dot_config/nvim/` on top of it. Anything the source tree does not name stays the user's to edit in place -- nothing here is `exact`.
- Anything needing a brew binary inside a script must `eval "$(<prefix>/bin/brew shellenv)"` first; chezmoi runs scripts without the interactive shell PATH.
