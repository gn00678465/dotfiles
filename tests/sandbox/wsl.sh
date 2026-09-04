#!/bin/sh
# L9 (Linux): run tests/sandbox/_probe.sh inside a *fresh* WSL distro.
#
#   tests/sandbox/wsl.sh                   # local mode: HEAD of this repo
#   tests/sandbox/wsl.sh --branch <name>   # remote mode: init.sh from GitHub
#   tests/sandbox/wsl.sh --keep            # do not unregister the distro afterwards
#
# This is the launcher that can prove the WSL-specific fixes: unlike the
# container it boots with systemd (wsl.conf [boot] systemd=true), so WSL
# exports XDG_RUNTIME_DIR=/run/user/<uid> to every process without creating
# the directory -- the exact state that broke `chezmoi update` -- and the
# 05-wsl-user-runtime-dir script has a logind to talk to.
#
# It registers a throwaway distro named chezmoi-probe with `wsl --import`
# from a debian:12 rootfs exported by docker -- not `wsl --install Debian`:
# that one, called from inside WSL, took the calling distro's own Windows
# interop down with it (binfmt WSLInterop gone, every .exe "exec format
# error", measured) and needed root to put back. Import touches neither the
# Store nor the WSL install. It needs wsl.exe interop and docker, i.e. a WSL
# shell on the Windows host with Docker Desktop. The distro is unregistered at
# the end unless --keep is given. Any existing distro of that name is replaced
# without asking: the name is reserved for this.
#
# Local mode reuses prepare.sh's folder under the Windows user profile: the
# source tree at C:\Users\<you>\chezmoi-sandbox\src\dotfiles is what the distro
# sees as /src/dotfiles, and results land next to the Windows Sandbox ones in
# chezmoi-sandbox\out.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
NAME=chezmoi-probe
branch=""; keep=0
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) branch=$2; shift 2 ;;
        --branch=*) branch=${1#*=}; shift ;;
        --keep) keep=1; shift ;;
        *) echo "wsl.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done
command -v docker >/dev/null 2>&1 || { echo "wsl.sh: docker not found (the rootfs comes from debian:12)" >&2; exit 2; }
# The system32 binary, not whatever `wsl.exe` resolves to: the Store version
# also sits on PATH as an app-execution alias under WindowsApps, which is a
# reparse point WSL interop cannot exec ("MZ: not found", measured).
WSL=/mnt/c/Windows/system32/wsl.exe
[ -x "$WSL" ] || WSL=$(command -v wsl.exe 2>/dev/null || true)
[ -n "$WSL" ] || { echo "wsl.sh: wsl.exe not found (needs WSL interop)" >&2; exit 2; }
# Run wsl.exe from a Windows-visible cwd: from a directory inside a WSL
# distro's own filesystem it warns "Failed to translate" on every call.
cd /mnt/c

# wsl.exe prints UTF-16 with NULs; every read of it goes through this.
w() { "$WSL" "$@" 2>&1 | tr -d '\0\r'; }
run_root() { "$WSL" -d "$NAME" -u root -- sh -c "$1"; }

win_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
[ -n "$win_home" ] || { echo "wsl.sh: cannot read %USERPROFILE%" >&2; exit 2; }
sandbox_wsl=$(wslpath -u "$win_home")/chezmoi-sandbox
sandbox_win=$(wslpath -w "$sandbox_wsl" 2>/dev/null || printf '%s\\chezmoi-sandbox' "$win_home")
# Inside the new distro the same folder is under /mnt/c.
sandbox_in=$(printf '%s' "$sandbox_win" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|; s|\\|/|g')

if [ -z "$branch" ]; then
    mkdir -p "$sandbox_wsl/src" "$sandbox_wsl/out"
    CHEZMOI_SANDBOX_DIR="$sandbox_wsl" sh "$REPO/tests/sandbox/prepare.sh" >/dev/null
    echo "wsl.sh: local mode, commit $(git -C "$REPO" rev-parse --short HEAD)"
else
    mkdir -p "$sandbox_wsl/out"
    echo "wsl.sh: remote mode, branch $branch"
fi
mkdir -p "$sandbox_wsl/out"
cp "$REPO/tests/sandbox/_probe.sh" "$sandbox_wsl/_probe.sh"
rm -f "$sandbox_wsl/out/results.tsv" "$sandbox_wsl/out/transcript.txt" "$sandbox_wsl/out/treesitter.log"

if w --list --quiet | grep -qx "$NAME"; then
    echo "wsl.sh: replacing existing distro $NAME"
    w --unregister "$NAME" >/dev/null
fi
echo "wsl.sh: exporting a debian:12 rootfs from docker"
rootfs="$sandbox_wsl/rootfs.tar"
cid=$(docker create "${CHEZMOI_PROBE_IMAGE:-debian:12}")
docker export "$cid" > "$rootfs"
docker rm "$cid" >/dev/null
echo "wsl.sh: registering $NAME with wsl --import"
mkdir -p "$sandbox_wsl/distro"
w --import "$NAME" "$sandbox_win\\distro" "$sandbox_win\\rootfs.tar" --version 2
rm -f "$rootfs"

# Root's job, not the dotfiles': systemd (a docker rootfs has none; WSL boots
# it once wsl.conf says so), a user, passwordless sudo (no tty, same as the
# container), the README's curl, and /src + /out pointing at the Windows
# folder. The terminate is what makes systemd=true take effect.
run_root "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq systemd systemd-sysv dbus sudo curl ca-certificates >/dev/null
id probe >/dev/null 2>&1 || useradd -m -s /bin/bash probe
echo 'probe ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/probe
chmod 440 /etc/sudoers.d/probe
printf '[boot]\nsystemd=true\n[user]\ndefault=probe\n' > /etc/wsl.conf
mkdir -p /src /out
ln -sfn '$sandbox_in/src/dotfiles' /src/dotfiles
ln -sfn '$sandbox_in/_probe.sh' /src/_probe.sh
"
w --terminate "$NAME" >/dev/null
# /out is a bind to the Windows folder; a symlink would make the probe's
# writability test pass or fail on DrvFs semantics rather than on the mount.
run_root "mount --bind '$sandbox_in/out' /out 2>/dev/null || ln -sfn '$sandbox_in/out' /out; systemctl is-system-running --wait >/dev/null 2>&1 || true"

echo "wsl.sh: running the probe as user probe (systemd: $(run_root 'systemctl is-system-running 2>/dev/null || echo none' | tr -d '\r'))"
# LANG pinned to a locale the rootfs has: wsl.exe forwards the caller's LANG
# (en_US.UTF-8 here), which a docker rootfs has not generated, and every brew
# call then prints six `locale:` warnings into the result details.
rc=0
"$WSL" -d "$NAME" -u probe -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 sh /src/_probe.sh ${branch:+--branch "$branch"} || rc=$?

if [ "$keep" = 1 ]; then
    echo "wsl.sh: keeping distro $NAME (wsl.exe --unregister $NAME to remove it)"
else
    w --unregister "$NAME" >/dev/null
    rm -rf "$sandbox_wsl/distro"
fi
echo "wsl.sh: probe exit $rc; results in $sandbox_wsl/out/results.tsv"

# Measured twice: when the probe distro stops (terminate / unregister), the
# calling distro loses its Windows interop -- binfmt_misc's WSLInterop entry
# is gone and every .exe is "exec format error". binfmt_misc is shared across
# the WSL VM, and the stopping distro's /init unregisters the entry. Putting
# it back needs root, so say how instead of trying.
if ! "$WSL" --list --quiet >/dev/null 2>&1; then
    cat <<'HINT' >&2

wsl.sh: this distro's Windows interop went away with the probe distro (known
        WSL behaviour, see the comment above). Restore it with:

  sudo sh -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'

HINT
fi
exit "$rc"
