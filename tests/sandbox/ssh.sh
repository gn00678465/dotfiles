#!/bin/sh
# L9 (Arch family over ssh): run tests/sandbox/_probe.sh on a machine reachable
# by ssh -- the ISO-installed omarchy VM (SPEC arch-family-support S11).
#
#   tests/sandbox/ssh.sh <user@host>                  # local mode: HEAD of this repo
#   tests/sandbox/ssh.sh <user@host> --branch <name>  # remote mode: init.sh from GitHub
#
# Same shape as omarchy.sh, with ssh where that one has wsl.exe: the source
# tree goes in through a pipe (tar | ssh tar), the probe runs, and /out comes
# back through a pipe. The launcher never touches $HOME on the target and
# never runs pacman; the probe's `chezmoi init --apply` is the only system
# change (Must NOT #7). Preconditions on the target: an Arch-family
# /etc/os-release, key authentication (every call is BatchMode), and either
# root or passwordless sudo for <user> -- the install scripts run pacman
# without a tty, and so does this launcher when it creates /src and /out.
# "Passwordless" is checked with `sudo -n -v`, the exact call the scripts
# make to prime the credential cache. `sudo -v` asks for a password whenever
# any rule for the user lacks the NOPASSWD tag, and omarchy ships one such
# rule in /etc/sudoers.d/50-asdcontrol (`ALL=(ALL) !/usr/bin/asdcontrol`), so
# a NOPASSWD: ALL entry passes `sudo -n true` but still fails `sudo -v`
# (measured on the VM). What works is a drop-in with
#   Defaults:<user> !authenticate
# which turns password checks off for that user altogether; remove it after
# the run.
# Results land in .gate/l9-ssh/<host>/.
#
# Connection budget: omarchy's ufw has `22/tcp LIMIT IN` (measured), i.e. at
# most 6 new connections per 30 seconds from one address, after which the
# rest are dropped and time out. Windows OpenSSH has no ControlMaster, so the
# work is packed into as few sessions as possible: preflight, root setup,
# transfer, run -- four before the long probe -- and one export afterwards.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
target=""; branch=""
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) branch=$2; shift 2 ;;
        --branch=*) branch=${1#*=}; shift ;;
        -*) echo "ssh.sh: unknown argument: $1" >&2; exit 2 ;;
        *) [ -z "$target" ] || { echo "ssh.sh: one target only" >&2; exit 2; }; target=$1; shift ;;
    esac
done
[ -n "$target" ] || { echo "usage: tests/sandbox/ssh.sh <user@host> [--branch <name>]" >&2; exit 2; }
command -v ssh >/dev/null 2>&1 || { echo "ssh.sh: ssh not found" >&2; exit 2; }

# Commands go in through stdin, like omarchy.sh: the remote login shell never
# re-parses a script it reads from stdin.
run_user() { printf '%s\n' "$1" | ssh -o BatchMode=yes "$target" sh; }

# Session 1: every precondition in one round trip.
preflight=$(run_user '
. /etc/os-release 2>/dev/null
printf "id=%s %s\n" "$ID" "${ID_LIKE:-}"
printf "user=%s\n" "$(id -un)"
if [ "$(id -u)" = 0 ]; then echo sudo=root
elif sudo -n -v 2>/dev/null; then echo sudo=nopasswd
else echo sudo=none; fi
' 2>&1) || { echo "ssh.sh: cannot reach $target non-interactively (BatchMode): $preflight" >&2; exit 2; }
distro_id=$(printf '%s\n' "$preflight" | sed -n 's/^id=//p')
user=$(printf '%s\n' "$preflight" | sed -n 's/^user=//p')
sudo_state=$(printf '%s\n' "$preflight" | sed -n 's/^sudo=//p')
case " $distro_id " in
    *" arch "*) ;;
    *) echo "ssh.sh: $target reports ID/ID_LIKE '$distro_id', not the Arch family" >&2; exit 2 ;;
esac
case "$sudo_state" in
    root) SUDO="" ;;
    nopasswd) SUDO="sudo -n" ;;
    *) echo "ssh.sh: user $user on $target cannot 'sudo -v' without a password (every sudoers rule for the user must be NOPASSWD); the install scripts cannot run pacman without a tty" >&2; exit 2 ;;
esac

host=${target#*@}
OUT="$REPO/.gate/l9-ssh/$host"
mkdir -p "$OUT"
rm -f "$OUT"/results.tsv "$OUT"/transcript.txt "$OUT"/*.log

if [ -z "$branch" ]; then
    echo "ssh.sh: local mode, commit $(git -C "$REPO" rev-parse --short HEAD), target $target, user $user"
else
    echo "ssh.sh: remote mode, branch $branch, target $target, user $user"
fi

# Session 2: root's work. /src and /out are replaced only when a previous run
# of this launcher made them (marker file); anything else there is a hard
# stop, never an rm -rf.
setup=$(printf '%s\n' "
for d in /src /out; do
    if [ -e \"\$d\" ] && [ ! -e \"\$d/.chezmoi-probe\" ]; then echo \"FOREIGN \$d\"; exit 3; fi
done
rm -rf /src /out && mkdir -p /src/dotfiles /out \
  && touch /src/.chezmoi-probe /out/.chezmoi-probe && chown -R '$user' /src /out
" | ssh -o BatchMode=yes "$target" "$SUDO sh" 2>&1) || {
    echo "ssh.sh: refusing to set up /src and /out on $target: $setup" >&2
    exit 2
}

# Session 3: the probe and (local mode) the committed tree, as one tar stream.
# Committed content only (git archive): what runs is this commit, not the
# working tree.
stage=$(mktemp -d "${TMPDIR:-/tmp}/ssh-probe.XXXXXX")
trap 'rm -rf "$stage"' EXIT INT TERM
cp "$REPO/tests/sandbox/_probe.sh" "$stage/_probe.sh"
if [ -z "$branch" ]; then
    mkdir -p "$stage/dotfiles"
    git -C "$REPO" archive HEAD | tar -x -C "$stage/dotfiles"
fi
tar -c -C "$stage" . | ssh -o BatchMode=yes "$target" 'tar -x -C /src'

# Session 4: the probe. -t is deliberately absent: it must see no tty,
# exactly like the WSL and container launchers, so anything that would prompt
# is a FAIL.
rc=0
ssh -n -o BatchMode=yes "$target" "env LANG=C.UTF-8 LC_ALL=C.UTF-8 sh /src/_probe.sh ${branch:+--branch $branch}" || rc=$?

# Session 5, minutes later: /out. Through a file, not a pipe: a pipe's status
# is the local tar's.
if ! ssh -n -o BatchMode=yes "$target" 'tar -c -C /out .' > "$OUT/out.tar"; then
    echo "ssh.sh: exporting /out from $target failed" >&2
    rm -f "$OUT/out.tar"
    exit 2
fi
tar -x -C "$OUT" -f "$OUT/out.tar" && rm -f "$OUT/out.tar"
[ -s "$OUT/results.tsv" ] || { echo "ssh.sh: no results.tsv came back" >&2; exit 2; }
echo "ssh.sh: probe exit $rc; results in $OUT/results.tsv"
exit "$rc"
