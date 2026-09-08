#!/bin/sh
# L9 (Arch family over ssh): run tests/sandbox/_probe.sh on a machine reachable
# by ssh -- the ISO-installed omarchy VM (SPEC arch-family-support S11).
#
#   tests/sandbox/ssh.sh <user@host>                  # local mode: HEAD of this repo
#   tests/sandbox/ssh.sh <user@host> --branch <name>  # remote mode: init.sh from GitHub
#
# Same shape as omarchy.sh, with ssh where that one has wsl.exe: the source
# tree goes in through a pipe (git archive | ssh tar), the probe runs, and /out
# comes back through a pipe. The launcher never touches $HOME on the target and
# never runs pacman; the probe's `chezmoi init --apply` is the only system
# change (Must NOT #7). Preconditions on the target: an Arch-family
# /etc/os-release, and either root or passwordless sudo for <user> -- the
# install scripts run pacman without a tty, and so does this launcher when it
# creates /src and /out. Results land in .gate/l9-ssh/<host>/.
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
# re-parses a script it reads from stdin. `-n` on the runs that must not
# consume the launcher's stdin.
run_user() { printf '%s\n' "$1" | ssh -o BatchMode=yes "$target" sh; }
# Root's work on the target goes through sudo -n (or straight through when the
# user is root); the check below is what makes -n safe.
run_root() { printf '%s\n' "$1" | ssh -o BatchMode=yes "$target" "$SUDO sh"; }

run_user 'true' >/dev/null 2>&1 || { echo "ssh.sh: cannot reach $target non-interactively (BatchMode); set up key auth first" >&2; exit 2; }
distro_id=$(run_user '. /etc/os-release && printf "%s %s" "$ID" "${ID_LIKE:-}"')
case " $distro_id " in
    *" arch "*) ;;
    *) echo "ssh.sh: $target reports ID/ID_LIKE '$distro_id', not the Arch family" >&2; exit 2 ;;
esac
user=$(run_user 'id -un')
if [ "$user" = root ]; then
    SUDO=""
else
    run_user 'sudo -n true' >/dev/null 2>&1 || {
        echo "ssh.sh: user $user on $target has no passwordless sudo; the install scripts cannot run pacman without a tty" >&2
        exit 2
    }
    SUDO="sudo -n"
fi

host=${target#*@}
OUT="$REPO/.gate/l9-ssh/$host"
mkdir -p "$OUT"
rm -f "$OUT"/results.tsv "$OUT"/transcript.txt "$OUT"/*.log

if [ -z "$branch" ]; then
    echo "ssh.sh: local mode, commit $(git -C "$REPO" rev-parse --short HEAD), target $target, user $user"
else
    echo "ssh.sh: remote mode, branch $branch, target $target, user $user"
fi

# /src and /out are replaced only when a previous run of this launcher made
# them (marker file); anything else there is a hard stop, never an rm -rf.
_owned=$(run_root 'for d in /src /out; do if [ -e "$d" ] && [ ! -e "$d/.chezmoi-probe" ]; then echo "FOREIGN $d"; fi; done')
if [ -n "$_owned" ]; then
    echo "ssh.sh: refusing to replace a directory this launcher did not create: $_owned" >&2
    exit 2
fi
run_root "rm -rf /src /out && mkdir -p /src/dotfiles /out && touch /src/.chezmoi-probe /out/.chezmoi-probe && chown -R '$user' /src /out"
if [ -z "$branch" ]; then
    # Committed content only (git archive): what runs is this commit, not the
    # working tree.
    git -C "$REPO" archive HEAD | ssh -o BatchMode=yes "$target" 'tar -x -C /src/dotfiles'
fi
ssh -o BatchMode=yes "$target" 'cat > /src/_probe.sh' < "$REPO/tests/sandbox/_probe.sh"

# -t is deliberately absent: the probe must see no tty, exactly like the WSL
# and container launchers, so anything that would prompt is a FAIL.
rc=0
ssh -n -o BatchMode=yes "$target" "env LANG=C.UTF-8 LC_ALL=C.UTF-8 sh /src/_probe.sh ${branch:+--branch $branch}" || rc=$?

# Through a file, not a pipe: a pipe's status is the local tar's.
if ! ssh -n -o BatchMode=yes "$target" 'tar -c -C /out .' > "$OUT/out.tar"; then
    echo "ssh.sh: exporting /out from $target failed" >&2
    rm -f "$OUT/out.tar"
    exit 2
fi
tar -x -C "$OUT" -f "$OUT/out.tar" && rm -f "$OUT/out.tar"
[ -s "$OUT/results.tsv" ] || { echo "ssh.sh: no results.tsv came back" >&2; exit 2; }
echo "ssh.sh: probe exit $rc; results in $OUT/results.tsv"
exit "$rc"
