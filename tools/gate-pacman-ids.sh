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
render_list() { # script
    chezmoi --source "$REPO" --config "$REPO/tests/fixtures/os-arch.toml" \
        --destination "$TMP/dest" --persistent-state "$TMP/state.boltdb" --no-tty \
        execute-template < "$REPO/.chezmoiscripts/$1" \
        | sed -n 's/^for pkg in \(.*\); do$/\1/p' | head -1
}
pkgs="$(render_list run_onchange_before_10-install-packages.sh.tmpl) $(render_list run_onchange_before_30-install-pacman-packages.sh.tmpl)"
pkgs=$(printf '%s\n' $pkgs | LC_ALL=C sort -u | tr '\n' ' ')
[ -n "$(printf '%s' "$pkgs" | tr -d ' ')" ] || { echo "gate-pacman-ids: rendered package lists are empty" >&2; exit 1; }

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
        printf 'ok   %-16s %s %s\n' "$p" "$repo" "$ver"
    else
        printf 'FAIL %-16s %s\n' "$p" "$(printf '%s' "$raw" | tr -d '\0\r' | head -1)"
        rc=1
    fi
done
[ "$rc" -eq 0 ] && echo "all pacman package names resolve"
exit "$rc"
