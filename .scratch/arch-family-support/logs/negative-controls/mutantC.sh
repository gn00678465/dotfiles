#!/bin/sh
set -eu
f=/tmp/verify/mutant1/tests/sandbox/_probe.sh
sed -n '88,92p' "$f"
sed -i "91s#.*#if [ \$arch = 1 ] \&\& pacman -Q some-other-pkg >/dev/null 2>&1; then omarchy=1; fi#" "$f"
sed -n '88,92p' "$f"
