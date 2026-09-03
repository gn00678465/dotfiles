# AGENTS.md

Chezmoi dotfiles source repository.

## Contract invariants

`tests/check_agent_doc_invariants.py` guards the cross-file promises between
the evidence-first contract, the workflow reference (`dot_agents/workflow/`),
and the `verification-gate` / `spec-archive` skills (status vocabularies,
report fields, shared tier and anti-gaming definitions). Run it after editing
any of those files; rc 1 = invariant broken, rc 2 = the check itself broke.
`tests/spec_archive_test.py` holds the spec-archive script's persisted
negative controls — run it after touching that script.

## Install scripts (`.chezmoiscripts/`)

Linux **and macOS** are both targets. Keep them in sync:

- `10-install-packages` (apt, Linux only) holds OS prerequisites only: `zsh git curl` plus what the Homebrew installer needs. Do not add tools here.
- `30-install-brew-packages` (brew, both OS) is the single list for tools (`mise fzf git-lfs`, ...). New tools go here so macOS gets them too.
- `40-git-lfs` is `run_onchange_after_` on purpose: `git lfs install` must run after `create_empty_dot_gitconfig` so it writes `~/.gitconfig`, not chezmoi-owned `~/.config/git/config`.
- `50-neovim` installs neovim through mise (not brew, and pinned to an explicit version -- see the comment there before bumping) and clones the LazyVim starter into `~/.config/nvim` once, then deletes its `.git`. Any pre-existing `~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim` or `~/.cache/nvim` is moved to `.bak` first, never deleted; the `.chezmoi-lazyvim-starter` marker it leaves behind is what stops a re-run from doing that to the user's own config. It is `run_onchange_before_` on purpose: `git clone` refuses a non-empty target, so the starter must land before chezmoi applies the files it owns under `private_dot_config/nvim/` on top of it. Anything the source tree does not name stays the user's to edit in place -- nothing here is `exact`.
- `tree-sitter` in `30-install-brew-packages` is not a standalone tool: nvim-treesitter's `main` branch shells out to it to build every parser, so it is a LazyVim dependency. Do not prune it.
- Anything needing a brew binary inside a script must `eval "$(<prefix>/bin/brew shellenv)"` first; chezmoi runs scripts without the interactive shell PATH.
