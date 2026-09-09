#!/bin/sh
set -eu
f=/tmp/verify/mutant1/.chezmoiscripts/run_before_50-neovim.sh.tmpl
grep -n "pacman -Q omarchy-nvim" "$f"
sed -i 's/if pacman -Q omarchy-nvim &>\/dev\/null; then/if ! pacman -Q omarchy-nvim \&>\/dev\/null; then/' "$f"
grep -n "pacman -Q omarchy-nvim" "$f"
