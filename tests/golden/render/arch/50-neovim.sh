#!/bin/zsh
# The LazyVim starter config on the pacman platforms. neovim itself is a pacman
# package (30-install-pacman-packages); the versions.toml pin does not apply
# here. Same `before` / `run_` reasoning as the Debian branch of this template.
set -euo pipefail

# omarchy ships its own LazyVim config through the omarchy-nvim package and
# puts it in ~/.config/nvim at useradd time. That config must stay exactly where
# it is (theme hot-reload, omarchy's plugins), so on such a machine this script
# does nothing: no backup, no clone, no marker. The check is at run time rather
# than render time because both omarchy flavours (WSL image with ID=arch,
# ISO install with ID=omarchy) and plain Arch reach this same rendering.
if pacman -Q omarchy-nvim &>/dev/null; then
  exit 0
fi

# The LazyVim starter is a template, not a tracked dependency: clone it once and
# drop its .git. Whatever chezmoi does not explicitly own under
# private_dot_config/nvim/ is then the user's to edit in place -- nothing here
# is `exact`, so chezmoi will not delete or revert it.
nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
nvim_data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
nvim_state="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
nvim_cache="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"

# Our own marker, not LazyVim's. Directory existence is not a usable guard once
# this script moves things aside: on a re-run (this is run_, it runs on every
# apply) an existing ~/.config/nvim is the user's own config, not a foreign one,
# and must not be backed up and re-cloned over. Delete this file to deliberately
# force a clean re-bootstrap on the next apply.
marker="$nvim_config/.chezmoi-lazyvim-starter"

# `mv dir dir.bak` moves dir *inside* dir.bak when dir.bak already exists, which
# silently buries the older backup. Fall back to a timestamp instead.
backup_dir() {
  [[ -e $1 ]] || return 0
  local dest="$1.bak"
  if [[ -e $dest ]]; then
    dest="$1.bak.$(date +%Y%m%d%H%M%S)"
  fi
  echo "chezmoi: backing up $1 -> $dest"
  mv "$1" "$dest"
}

if [[ ! -e $marker ]]; then
  # LazyVim wants a clean slate: any pre-existing config and plugin data is
  # moved aside rather than merged. Nothing is deleted.
  backup_dir "$nvim_config"
  backup_dir "$nvim_data"
  backup_dir "$nvim_state"
  backup_dir "$nvim_cache"

  echo "chezmoi: cloning the LazyVim starter into $nvim_config"
  git clone --depth 1 https://github.com/LazyVim/starter "$nvim_config"
  rm -rf "$nvim_config/.git"
  touch "$marker"
fi
