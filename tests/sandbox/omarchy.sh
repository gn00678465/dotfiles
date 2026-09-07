#!/bin/sh
# L9 (Arch): run tests/sandbox/_probe.sh inside the user's `omarchy` WSL distro.
#
#   tests/sandbox/omarchy.sh                   # local mode: HEAD of this repo
#   tests/sandbox/omarchy.sh --branch <name>   # remote mode: init.sh from GitHub
#   tests/sandbox/omarchy.sh --distro <name>   # another Arch distro (default: omarchy)
#
# Unlike wsl.sh this is NOT a throwaway distro. It is the omarchy install the
# user keeps for verification and will rebuild afterwards (SPEC
# archlinux-support §6), so the launcher does as little as possible to it:
# copy the source tree and the probe in, run the probe, copy /out back. It
# never runs pacman itself and never touches $HOME; the probe's `chezmoi init
# --apply` is the only system change (Must NOT #8). Precondition: the distro's
# default user has passwordless sudo (omarchy's WSL image does), because the
# install scripts run pacman through sudo with no tty.
#
# No DrvFs mounts: the tree goes in through a pipe (git archive | tar) and the
# results come back the same way, so this runs from Git Bash on the host and
# from another WSL distro alike -- both only need wsl.exe.
#
# Results land in .gate/l9-omarchy/ (git-ignored): results.tsv, transcript.txt,
# install.log, treesitter.log and the apply logs.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
NAME=omarchy
branch=""
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) branch=$2; shift 2 ;;
        --branch=*) branch=${1#*=}; shift ;;
        --distro) NAME=$2; shift 2 ;;
        --distro=*) NAME=${1#*=}; shift ;;
        *) echo "omarchy.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The system32 binary, not whatever `wsl.exe` resolves to: the Store version
# also sits on PATH as an app-execution alias under WindowsApps, which WSL
# interop cannot exec (see wsl.sh).
WSL=""
for _c in /mnt/c/Windows/system32/wsl.exe /c/Windows/system32/wsl.exe; do
    [ -x "$_c" ] && { WSL=$_c; break; }
done
[ -n "$WSL" ] || WSL=$(command -v wsl.exe 2>/dev/null || true)
[ -n "$WSL" ] || { echo "omarchy.sh: wsl.exe not found (needs WSL interop)" >&2; exit 2; }
# Git Bash (MSYS) rewrites POSIX-looking arguments of native executables into
# Windows paths: `tar -x -C /src/dotfiles` reached the distro as
# `C:/Program Files/Git/src/dotfiles` (measured). Both variables are ignored
# outside MSYS. Scoped to wsl.exe: exporting them would break git and tar
# on the Git Bash side (`git -C /d/...` stops resolving, measured).
wslx() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "$WSL" "$@"; }
# wsl.exe prints UTF-16 with NULs; every read of it goes through this.
w() { wslx "$@" 2>&1 | tr -d '\0\r'; }
# Commands go in through stdin, not `sh -c '...'`: wsl.exe hands everything
# after `--` to the distro's login shell as one string, which expands `$ID`
# and `$@` before the inner sh ever runs (measured: `sh -c 'printf %s "$ID"'`
# printed nothing). A script on stdin is never re-parsed by that shell.
run_root() { printf '%s\n' "$1" | wslx -d "$NAME" -u root -- sh; }
run_user() { printf '%s\n' "$1" | wslx -d "$NAME" -- sh; }

w --list --quiet | grep -qx "$NAME" || { echo "omarchy.sh: no WSL distro named $NAME" >&2; exit 2; }
distro_id=$(run_user '. /etc/os-release && printf %s "$ID"' | tr -d '\0\r')
[ "$distro_id" = arch ] || { echo "omarchy.sh: $NAME reports ID=$distro_id, not arch" >&2; exit 2; }
user=$(run_user 'id -un' | tr -d '\0\r')
run_user 'sudo -n true' >/dev/null 2>&1 || {
    echo "omarchy.sh: user $user in $NAME has no passwordless sudo; the install scripts cannot run pacman without a tty" >&2
    exit 2
}

OUT="$REPO/.gate/l9-omarchy"
mkdir -p "$OUT"
rm -f "$OUT"/results.tsv "$OUT"/transcript.txt "$OUT"/*.log

if [ -z "$branch" ]; then
    echo "omarchy.sh: local mode, commit $(git -C "$REPO" rev-parse --short HEAD), distro $NAME, user $user"
else
    echo "omarchy.sh: remote mode, branch $branch, distro $NAME, user $user"
fi

# Root only creates the two directories the probe expects and hands them to
# the user; everything after this runs as the user. /src and /out are replaced
# only when a previous run of this launcher made them (marker file): this is
# the user's distro, not a throwaway rootfs, so a /src or /out that belongs to
# someone else is a hard stop, never an rm -rf.
_owned=$(run_root 'for d in /src /out; do if [ -e "$d" ] && [ ! -e "$d/.chezmoi-probe" ]; then echo "FOREIGN $d"; fi; done' | tr -d '\0\r')
if [ -n "$_owned" ]; then
    echo "omarchy.sh: refusing to replace a directory this launcher did not create: $_owned" >&2
    echo "omarchy.sh: remove it yourself inside $NAME, or point the probe elsewhere" >&2
    exit 2
fi
run_root "rm -rf /src /out && mkdir -p /src/dotfiles /out && touch /src/.chezmoi-probe /out/.chezmoi-probe && chown -R '$user' /src /out"
if [ -z "$branch" ]; then
    # Committed content only (git archive), like prepare.sh: what runs is this
    # commit, not the working tree.
    git -C "$REPO" archive HEAD | wslx -d "$NAME" -- tar -x -C /src/dotfiles
fi
wslx -d "$NAME" -- sh -c 'cat > /src/_probe.sh' < "$REPO/tests/sandbox/_probe.sh"

# LANG pinned to a locale every image has; wsl.exe forwards the caller's LANG
# otherwise (see wsl.sh).
rc=0
wslx -d "$NAME" -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 sh /src/_probe.sh ${branch:+--branch "$branch"} || rc=$?

# Through a file, not a pipe: a pipe's status is the local tar's, and a sender
# that fails after emitting a valid archive would be reported as success.
if ! wslx -d "$NAME" -- tar -c -C /out . > "$OUT/out.tar"; then
    echo "omarchy.sh: exporting /out from $NAME failed" >&2
    rm -f "$OUT/out.tar"
    exit 2
fi
tar -x -C "$OUT" -f "$OUT/out.tar" && rm -f "$OUT/out.tar"
[ -s "$OUT/results.tsv" ] || { echo "omarchy.sh: no results.tsv came back" >&2; exit 2; }
echo "omarchy.sh: probe exit $rc; results in $OUT/results.tsv"
exit "$rc"
