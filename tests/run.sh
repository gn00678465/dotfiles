#!/bin/sh
# 這個 repo 的測試入口。純 POSIX sh + chezmoi。
#
#   tests/run.sh            # 跑全部
#   tests/run.sh L1 L3      # 只跑指定層
#
# 輸出是 TAP。退出碼非零代表有 case 失敗。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export REPO

command -v chezmoi >/dev/null 2>&1 || { echo "1..0 # SKIP chezmoi not found" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tests.XXXXXX")
export TMP
trap 'rm -rf "$TMP"' EXIT INT TERM

. "$REPO/tests/lib.sh"

if [ $# -gt 0 ]; then
    selected="$*"
else
    selected=""
fi

for case_file in "$REPO"/tests/cases/*.sh; do
    [ -e "$case_file" ] || continue
    base=$(basename "$case_file" .sh)
    layer=${base%%-*}
    if [ -n "$selected" ]; then
        match=0
        for want in $selected; do [ "$want" = "$layer" ] && match=1; done
        [ "$match" = 1 ] || continue
    fi
    CURRENT_CASE=$layer
    . "$case_file"
done

printf '1..%d\n' "$TESTS_RUN"
printf '# run %d, failed %d, skipped %d\n' "$TESTS_RUN" "$TESTS_FAILED" "$TESTS_SKIPPED"
[ "$TESTS_FAILED" -eq 0 ]
