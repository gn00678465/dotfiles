#!/bin/sh
# Gate layer for SPEC archlinux-support S17 / M5: every pacman package name the
# source installs must resolve in the official repos. `pacman -Si` is
# read-only. The pacman analogue of gate-supply-chain.py's winget ID check.
#
#   tools/gate-pacman-ids.sh [--distro <name>]
#
# Runs pacman directly when this host is Arch; otherwise through the `omarchy`
# WSL distro (wsl.exe interop, from Git Bash or another WSL distro). When
# neither is reachable it prints SKIPPED and exits 0 -- the same shape as the
# winget check -- so the evidence report records UNAVAILABLE instead of a pass.
# Any other failure (a name that does not resolve, a render error) is exit 1.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

DISTRO=omarchy
while [ $# -gt 0 ]; do
    case "$1" in
        --distro) DISTRO=$2; shift 2 ;;
        --distro=*) DISTRO=${1#*=}; shift ;;
        *) echo "gate-pacman-ids: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The lists come from the rendered scripts, the same way L2/L11 read them, so
# a package added to a script is checked here without anyone editing this file.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/gate-pacman.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
# Each script must render, and each must yield a list: a render failure or a
# missing `for pkg in` line is a hard failure, not an empty contribution to a
# merged list (that shape let one whole script go unverified).
render_list() { # script
    if ! _out=$(chezmoi --source "$REPO" --config "$REPO/tests/fixtures/os-arch.toml" \
            --destination "$TMP/dest" --persistent-state "$TMP/state.boltdb" --no-tty \
            execute-template < "$REPO/.chezmoiscripts/$1" 2>&1); then
        echo "gate-pacman-ids: render failed for $1: $_out" >&2
        return 1
    fi
    _list=$(printf '%s\n' "$_out" | sed -n 's/^for pkg in \(.*\); do$/\1/p' | head -1)
    [ -n "$(printf '%s' "$_list" | tr -d ' ')" ] || { echo "gate-pacman-ids: no 'for pkg in' list in $1" >&2; return 1; }
    printf '%s' "$_list"
}
pre=$(render_list run_onchange_before_10-install-packages.sh.tmpl) || exit 1
tools=$(render_list run_onchange_before_30-install-pacman-packages.sh.tmpl) || exit 1
pkgs=$(printf '%s\n' $pre $tools | LC_ALL=C sort -u | tr '\n' ' ')

WSL=""
if command -v pacman >/dev/null 2>&1; then
    where="this host"
else
    for _c in /mnt/c/Windows/system32/wsl.exe /c/Windows/system32/wsl.exe; do
        [ -x "$_c" ] && { WSL=$_c; break; }
    done
    [ -n "$WSL" ] || WSL=$(command -v wsl.exe 2>/dev/null || true)
    if [ -z "$WSL" ] || ! "$WSL" --list --quiet 2>/dev/null | tr -d '\0\r' | grep -qx "$DISTRO"; then
        echo "SKIPPED: no pacman on this host and no WSL distro named $DISTRO -- package names NOT verified"
        exit 0
    fi
    where="WSL distro $DISTRO"
fi
# Git Bash rewrites POSIX-looking arguments of native executables; the
# override is scoped to the wsl.exe call (see tests/sandbox/omarchy.sh).
pacman_si() {
    if [ -n "$WSL" ]; then
        MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$WSL" -d "$DISTRO" -- pacman -Si "$1"
    else
        pacman -Si "$1"
    fi
}

echo "pacman -Si via $where; packages:$(printf ' %s' $pkgs)"
rc=0
for p in $pkgs; do
    # The exit status must be pacman's own. `pacman_si | tr` would return tr's
    # status and turn every unknown name into an "ok" (the negative control
    # caught exactly that), so strip wsl.exe's NUL/CR bytes in a second step.
    if raw=$(pacman_si "$p" 2>&1); then
        out=$(printf '%s' "$raw" | tr -d '\0\r')
        repo=$(printf '%s\n' "$out" | sed -n 's/^Repository *: *//p' | head -1)
        ver=$(printf '%s\n' "$out" | sed -n 's/^Version *: *//p' | head -1)
        # SPEC F4 / AGENTS.md: official core/extra only, no AUR and no third-party
        # repo (omarchy's own pkgs.omarchy.org is enabled on that machine, so a
        # name resolving there would otherwise pass unnoticed).
        case "$repo" in
            core|extra) printf 'ok   %-16s %s %s\n' "$p" "$repo" "$ver" ;;
            *) printf 'FAIL %-16s repository "%s" is not core/extra\n' "$p" "$repo"; rc=1 ;;
        esac
    else
        printf 'FAIL %-16s %s\n' "$p" "$(printf '%s' "$raw" | tr -d '\0\r' | head -1)"
        rc=1
    fi
done
[ "$rc" -eq 0 ] && echo "all pacman package names resolve"
exit "$rc"
