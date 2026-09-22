#!/bin/sh
set -eu
casedir=$(cd "$(dirname "$0")" && pwd)
sh "$casedir/../fixtures/build_home.sh" "$casedir/../fixtures" claude-main claude-stale
