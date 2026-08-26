#!/bin/sh
set -e

# setup chezmoi
# -b is required: the installer's BINDIR defaults to ./bin, relative to whatever
# directory this script runs in, and it never cd's to $HOME. Without it chezmoi
# lands somewhere that is not on PATH, and every later `chezmoi` call fails.
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply gn00678465
