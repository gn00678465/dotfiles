#!/bin/sh
# eval 的 scaffold 在 agent 的暫存 cwd 執行；案例目錄只能從 $0 推得。
set -eu
casedir=$(cd "$(dirname "$0")" && pwd)
sh "$casedir/../fixtures/build_home.sh" "$casedir/../fixtures" claude-main codex-main
