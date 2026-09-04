#!/bin/sh
# L9 (Linux): run tests/sandbox/_probe.sh inside a throwaway debian:12 container.
#
#   tests/sandbox/docker.sh                   # local mode: HEAD of this repo
#   tests/sandbox/docker.sh --branch <name>   # remote mode: init.sh from GitHub
#   tests/sandbox/docker.sh --out <dir>       # where results.tsv / transcript.txt land
#
# Local mode ships `git archive HEAD` (committed content only, same rule as
# prepare.sh) into the container read-only at /src/dotfiles. The container gets
# what a fresh Debian user has and nothing more: curl (the README prerequisite),
# sudo without a password (the probe has no tty, and the Windows Sandbox user
# is an administrator too), and a non-root user named probe.
#
# No systemd here, so the linger / chezmoi update checks report SKIP; the fresh
# WSL launcher (wsl.sh) is the one that can earn those.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
branch=""; out=""; image="${CHEZMOI_PROBE_IMAGE:-debian:12}"
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) branch=$2; shift 2 ;;
        --branch=*) branch=${1#*=}; shift ;;
        --out) out=$2; shift 2 ;;
        --out=*) out=${1#*=}; shift ;;
        --image) image=$2; shift 2 ;;
        *) echo "docker.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done
command -v docker >/dev/null 2>&1 || { echo "docker.sh: docker not found" >&2; exit 2; }

out=${out:-$REPO/.gate/l9-linux}
mkdir -p "$out"
rm -f "$out/results.tsv" "$out/transcript.txt" "$out/treesitter.log" "$out"/*.log

work=$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-probe.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
cp "$REPO/tests/sandbox/_probe.sh" "$work/_probe.sh"
set -- -v "$work/_probe.sh:/src/_probe.sh:ro" -v "$out:/out"
if [ -z "$branch" ]; then
    mkdir -p "$work/dotfiles"
    git -C "$REPO" archive HEAD | tar -x -C "$work/dotfiles"
    # `chezmoi init --source <dir>` runs a built-in `git init` on a source tree
    # that has no .git, and that is a mkdir on a read-only mount (measured: the
    # first container run died right there). An empty repo is enough; chezmoi
    # then leaves the tree alone and the mount can stay read-only.
    git -C "$work/dotfiles" init -q
    set -- "$@" -v "$work/dotfiles:/src/dotfiles:ro"
    echo "docker.sh: local mode, commit $(git -C "$REPO" rev-parse --short HEAD), image $image"
else
    echo "docker.sh: remote mode, branch $branch, image $image"
fi
[ -t 1 ] && set -- -t "$@"

# The bootstrap is root's job and is not part of the dotfiles: it only makes
# the container look like a machine someone can log in to.
docker run --rm "$@" -e "PROBE_ARGS=${branch:+--branch $branch}" "$image" sh -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq sudo curl ca-certificates >/dev/null
useradd -m -s /bin/bash probe
echo "probe ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/probe
chmod 440 /etc/sudoers.d/probe
chown probe /out
exec su - probe -c "sh /src/_probe.sh $PROBE_ARGS"
'
