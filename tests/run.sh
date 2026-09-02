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

# TESTS_SHUFFLE=1 打亂 case 的執行順序。給 suite health 那一層用：每一個 case
# 都應該自己準備自己需要的狀態，順序一換就壞掉代表有隱藏的相依。
_case_list=$(ls "$REPO"/tests/cases/*.sh 2>/dev/null || true)
if [ "${TESTS_SHUFFLE:-0}" = "1" ] && command -v shuf >/dev/null 2>&1; then
    _case_list=$(printf '%s\n' "$_case_list" | shuf)
fi

for case_file in $_case_list; do
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
