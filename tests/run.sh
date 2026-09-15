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
    _before=$TESTS_RUN
    _before_skipped=$TESTS_SKIPPED
    . "$case_file"
    printf '%s %s %s\n' "$layer" "$((TESTS_RUN - _before))" \
        "$((TESTS_SKIPPED - _before_skipped))" >> "$TMP/layer-counts"
done

# 這些層的環境前提寫在 AGENTS.md「Tests」那張表（沒有 WSL interop 就沒有 Windows
# 端的 chezmoi 可問），所以它們可以整層跳過。清單以外的層整層跳過代表它被停用了，
# 不是被環境擋住，紅。runner 不自己重算各層的前提：L8 的前提是 pwsh.exe + wslpath
# + Windows 端 chezmoi 一整條鏈，複製一份只會漂掉並在半套環境上假紅。
SKIP_ONLY_DECLARED='L4 L7 L8'

# 執行完整性：一個被選到卻一條斷言都沒貢獻的層，跟不存在是一樣的。
# 「檔案在不在」抓不到「檔案還在但被停用」（例如開頭插一行 return 0）——
# 獨立驗證用那個形狀讓一個 mutant 存活過。這裡改成問「它真的產出斷言了嗎」。
#
# 斷言數不等於量測數。`ok N # SKIP` 依 TAP 就是 ok（這是對的，不要改），於是整層
# 只有 SKIP 時，它既進了綠燈總數也滿足了上面那道守門。量測數 = 斷言數 − SKIP 數，
# 為零的層在這裡具名印出來，不被吸收進總數。
_skip_only=""
if [ -f "$TMP/layer-counts" ]; then
    while read -r _l _n _s; do
        _measured=$((_n - _s))
        if [ "$_n" -eq 0 ]; then
            TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
            printf 'not ok %d - [runner] 測試層 %s 一條斷言都沒有貢獻（等同不存在）\n' \
                "$TESTS_RUN" "$_l"
        elif [ "$_measured" -eq 0 ]; then
            _declared=0
            for _d in $SKIP_ONLY_DECLARED; do
                if [ "$_d" = "$_l" ]; then _declared=1; fi
            done
            if [ "$_declared" -eq 1 ]; then
                _skip_only="$_skip_only $_l"
                printf '# 層 %s 的 %d 條斷言全部是 SKIP：這一層沒有量測任何東西，\n' "$_l" "$_n"
                printf '#   它在這個環境裡不可能變紅。靠它支撐的主張要記成 UNAVAILABLE。\n'
            else
                TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
                printf 'not ok %d - [runner] 測試層 %s 的 %d 條斷言全部是 SKIP，而它沒有宣告過環境前提\n' \
                    "$TESTS_RUN" "$_l" "$_n"
            fi
        fi
    done < "$TMP/layer-counts"
fi

printf '1..%d\n' "$TESTS_RUN"
printf '# run %d, failed %d, skipped %d\n' "$TESTS_RUN" "$TESTS_FAILED" "$TESTS_SKIPPED"
printf '# skip-only 層（沒有量測任何東西）:%s\n' "${_skip_only:- 無}"
[ "$TESTS_FAILED" -eq 0 ]
