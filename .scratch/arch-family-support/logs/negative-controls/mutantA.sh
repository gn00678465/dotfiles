#!/bin/sh
set -eu
f=/tmp/verify/mutant1/.chezmoitemplates/platform.toml
sed -i '40s#.*#{{- $archFamily := eq $distro "arch" -}}#' "$f"
sed -n '38,44p' "$f"
