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
# It registers a throwaway distro named chezmoi-probe from the Debian image
# (`wsl --install Debian --name chezmoi-probe`), which needs wsl.exe interop,
# i.e. running from a WSL shell on the Windows host. The distro is unregistered
# at the end unless --keep is given. Any existing distro of that name is
# replaced without asking: the name is reserved for this.
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
command -v wsl.exe >/dev/null 2>&1 || { echo "wsl.sh: wsl.exe not found (needs WSL interop)" >&2; exit 2; }

# wsl.exe prints UTF-16 with NULs; every read of it goes through this.
w() { wsl.exe "$@" 2>&1 | tr -d '\0\r'; }
run_root() { wsl.exe -d "$NAME" -u root -- sh -c "$1"; }

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
echo "wsl.sh: registering $NAME from the Debian image (downloads it if needed)"
w --install Debian --name "$NAME" --no-launch

# Root's job, not the dotfiles': a user, passwordless sudo (no tty, same as
# the container), the README's curl, systemd on, and /src + /out pointing at
# the Windows folder. The terminate is what makes systemd=true take effect.
run_root "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq sudo curl ca-certificates >/dev/null
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
rc=0
wsl.exe -d "$NAME" -u probe -- sh /src/_probe.sh ${branch:+--branch "$branch"} || rc=$?

if [ "$keep" = 1 ]; then
    echo "wsl.sh: keeping distro $NAME (wsl.exe --unregister $NAME to remove it)"
else
    w --unregister "$NAME" >/dev/null
fi
echo "wsl.sh: probe exit $rc; results in $sandbox_wsl/out/results.tsv"
exit "$rc"
