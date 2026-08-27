#!/bin/sh
# First-time install only. On a machine that already ran this, chezmoi init
# skips the clone (so --branch is ignored) and just re-applies; to switch
# branch there use: chezmoi cd && git checkout <branch>, then chezmoi apply.
#
# Usage:
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/gn00678465/dotfiles/main/init.sh)"
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/gn00678465/dotfiles/<branch>/init.sh)" -- --branch <branch>
#
# --branch <name> (alias: --ref): clone and check out that branch instead of the
# remote default (main). Fetch init.sh from the same branch so a branch that
# changes this script is installed with its own version. Note that a later
# `chezmoi update` keeps pulling that branch, not main.
set -e

branch=""
while [ $# -gt 0 ]; do
    case "$1" in
        --branch|--ref)
            [ $# -ge 2 ] || { echo "init.sh: $1 needs a value" >&2; exit 2; }
            branch="$2"; shift 2 ;;
        --branch=*|--ref=*)
            branch="${1#*=}"; shift ;;
        *)
            echo "init.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

set -- init --apply
[ -n "$branch" ] && set -- "$@" --branch "$branch"
set -- "$@" gn00678465

# setup chezmoi
# -b is required: the installer's BINDIR defaults to ./bin, relative to whatever
# directory this script runs in, and it never cd's to $HOME. Without it chezmoi
# lands somewhere that is not on PATH, and every later `chezmoi` call fails.
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin" "$@"
