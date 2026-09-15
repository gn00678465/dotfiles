#!/bin/sh
# 從 git 裡的 SPEC 推出 evidence report 標頭的 intent 欄位，印成可以逐字貼進報告的樣子。
#
#   tools/gate-intent.sh <scope>
#
# 這些欄位不是手填的：windows-support 的報告曾經把 spec_version 停在 v6 而 SPEC 已是
# v7，因為標頭是憑記憶寫的。現在標頭從這裡來，而 spec-archive 在 CLOSE 會拿報告引用的
# `spec_version: vN` 與 SPEC 比對，對不上就拒絕封存。
#
# SPEC 在 CLOSE 之後會從 specs/<scope>/ 搬到 specs/archive/<scope>/，兩個位置都找。
#
# exit 0：印出了欄位。`unconfirmed`／`absent` 也是 exit 0 —— 那是報告要如實記錄的
#         降級，不是 gate 的失敗（verification-gate 的 Intent status 一節）。
# exit 1：SPEC 存在但沒進版控、或解析不到 spec_version／status —— 結構壞了，fail closed。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

scope=${1:?usage: gate-intent.sh <scope>}

spec=""
for cand in "specs/$scope/SPEC.md" "specs/archive/$scope/SPEC.md"; do
    if [ -f "$cand" ]; then spec=$cand; break; fi
done

if [ -z "$spec" ]; then
    printf -- '- `intent_status`: absent\n'
    printf -- '- `intent_source`: 找不到 SPEC（specs/%s/SPEC.md 與 specs/archive/%s/SPEC.md 都不存在）\n' \
        "$scope" "$scope"
    exit 0
fi

if ! git ls-files --error-unmatch "$spec" >/dev/null 2>&1; then
    echo "gate-intent: $spec 沒有進版控 —— 標頭只能從 git 裡的 SPEC 推出" >&2
    exit 1
fi

# 核准前的草稿是 v0.1、v0.2，版號不一定是整數。只比對整數會把草稿截成 v0，
# 兩份不同草稿因此相等。
version=$(sed -n 's/^- `spec_version`: *\(v[0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p' "$spec" | head -1)
status=$(sed -n 's/^- `status`: *\([A-Za-z-]*\).*/\1/p' "$spec" | head -1)
tier=$(sed -n 's/^- `tier`: *\([0-9]\).*/\1/p' "$spec" | head -1)
if [ -z "$version" ] || [ -z "$status" ]; then
    echo "gate-intent: 解析不到 spec_version 或 status: $spec" >&2
    exit 1
fi

# Approval 一節：標題含 Approval 的 `##` 起，到下一個同級或更高階標題為止。紀錄的兩種
# 形式由 SPEC spec-version-bump §2 定義，兩種都在 git 裡：範本的清單式
# `- <date> — approves vN — 「原話」`，與 windows-support 的分節式 `### vN — <date>`
# 加上 approval/version bound/date/引文。這裡只把結構完整的紀錄列入集合。
#
# 舊版只 grep `^### v[0-9]+|approves v[0-9]+`：任何一行含 `### v5` 或 `approves v5`
# 都算一筆核准，不管它是不是紀錄。git 裡目前沒有因此誤判的檔案——實測
# `windows-support` 的 `### v5 的兩項選擇 — <date>` 決策小節確實命中，但它跟真正的
# v5 同版號，去重後集合不變；`global-agent-instructions:117` 的散文寫的是
# `approves <spec_version>`，沒有數字，舊式樣本來就不命中。本次改的是形狀而不是
# 已發生的誤判：五份真實 SPEC 的集合與判決在改寫前後逐位元組相同。
# 版號整段比對，不再截斷（`### v1.2` 不再讀成 v1）。
# 去重在 awk 裡做，排序把版號依 `.` 拆成數值鍵：舊的 `sort -t v -k2,2n -u` 只取 v 後面
# 一個數值鍵，會把 v0.1 與 v0.10 當成同一版去掉一筆。
#
# 這裡不判斷連續性（v1..vN 是否都有紀錄）：那是 CLOSE 的問題。gate 的 confirmed 只
# 回答「目前這個版號有沒有核准紀錄」，而且 unconfirmed 仍然 exit 0。
approved=$(awk '
function lvl(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
function quoted(s,   a, t, b, inner) {
    a = index(s, "「")
    if (a > 0) {
        t = substr(s, a + length("「")); b = index(t, "」")
        if (b > 0) { inner = substr(t, 1, b - 1); if (inner ~ /[^ \t]/) return 1 }
    }
    a = index(s, "\"")
    if (a > 0) {
        t = substr(s, a + 1); b = index(t, "\"")
        if (b > 0) { inner = substr(t, 1, b - 1); if (inner ~ /[^ \t]/) return 1 }
    }
    return 0
}
function emit(v) { if (!(v in seen)) { seen[v] = 1; print v } }
function validdate(s,   y, m, d, dim) {
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m < 1 || m > 12 || d < 1) return 0
    dim = 31
    if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
    if (m == 2) dim = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
    return d <= dim
}
function close_record() {
    if (rec && f_appr && f_bound && f_date && f_quote) emit(rec_ver)
    rec = 0; f_appr = 0; f_bound = 0; f_date = 0; f_quote = 0
}
{
    # 範本把核准佔位行包在 HTML 註解裡，那不是紀錄；圍欄程式碼同理。
    if (incomment) {
        p = index($0, "-->"); if (p == 0) next
        $0 = substr($0, p + 3); incomment = 0
    }
    while ((p = index($0, "<!--")) > 0) {
        q = index(substr($0, p), "-->")
        if (q == 0) { $0 = substr($0, 1, p - 1); incomment = 1; break }
        $0 = substr($0, 1, p - 1) substr($0, p + q + 2)
    }
}
/^(```|~~~)/ {
    if (!fence) { fence = 1; fencech = substr($0, 1, 3) }
    else if (substr($0, 1, 3) == fencech) fence = 0
    next
}
fence { next }
/^#+([ \t]|$)/ {
    l = lvl($0)
    if (inblk && l <= headlvl) { close_record(); inblk = 0 }
    if (!inblk) {
        if (l >= 2 && $0 ~ /^#+[ \t]*([0-9]+\.[ \t]*)?Approval([^A-Za-z0-9_]|$)/) {
            inblk = 1; headlvl = l
        }
        next
    }
    close_record()
    h = $0; sub(/^#+[ \t]*/, "", h)
    if (l >= 3 && match(h, /^v[0-9]+(\.[0-9]+)*/)) {
        rec_ver = substr(h, 1, RLENGTH); rest = substr(h, RLENGTH + 1)
        if (substr(rest, 1, 1) !~ /[[:alnum:]_.-]/ &&
            rest ~ /^[ \t]*(—|–|-)[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]*$/) {
            match(rest, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
            rec_date = substr(rest, RSTART, RLENGTH)
            if (validdate(rec_date)) rec = 1
        }
    }
    next
}
!inblk { next }
{
    if (match($0, /^[ \t]*-[ \t]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]*(—|–|-)[ \t]*approves[ \t]+v[0-9]+(\.[0-9]+)*/)) {
        tok = substr($0, RSTART, RLENGTH); tail = substr($0, RSTART + RLENGTH)
        match(tok, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
        dt = substr(tok, RSTART, RLENGTH)
        sub(/^.*approves[ \t]+/, "", tok)
        if (substr(tail, 1, 1) !~ /[[:alnum:]_.-]/ && validdate(dt) && quoted(tail)) emit(tok)
    }
    if (!rec) next
    if ($0 ~ /approval:[ \t]*confirmed([^A-Za-z0-9_]|$)/) f_appr = 1
    if (match($0, /version bound:[ \t]*v[0-9]+(\.[0-9]+)*/)) {
        tok = substr($0, RSTART, RLENGTH); nxt = substr($0, RSTART + RLENGTH, 1)
        sub(/^version bound:[ \t]*/, "", tok)
        if (tok == rec_ver && nxt !~ /[[:alnum:]_.-]/) f_bound = 1
    }
    if ($0 ~ ("date:[ \t]*" rec_date "([^0-9]|$)")) f_date = 1
    if ($0 ~ /^[ \t]*>[ \t]*[^ \t]/ || quoted($0)) f_quote = 1
}
END { close_record() }
' "$spec" | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | sed 's/^/v/' \
    | tr '\n' ' ' | sed 's/ $//')

case " $approved " in
    *" $version "*) recorded=yes ;;
    *) recorded=no ;;
esac
if [ "$recorded" = yes ] && { [ "$status" = approved ] || [ "$status" = shipped ]; }; then
    intent=confirmed
else
    intent=unconfirmed
fi

added=$(git log --diff-filter=A --follow --format=%h -- "$spec" | tail -1)
last=$(git log -1 --format='%h %s' -- "$spec")

printf -- '- `intent_status`: %s\n' "$intent"
printf -- '- `intent_source`: 已提交的 SPEC `%s`（`spec_version: %s`、`status: %s`、`tier: %s`；§Approval 記錄 %s；首次進入歷史 `%s`，最後一次改動 `%s`）\n' \
    "$spec" "$version" "$status" "${tier:-?}" "${approved:-無}" "$added" "$last"
if [ "$intent" = unconfirmed ]; then
    printf -- '- `intent_note`: '
    if [ "$recorded" = no ]; then
        printf '§Approval 沒有 %s 的核准記錄' "$version"
    else
        printf 'status 是 `%s`，不是 approved' "$status"
    fi
    printf '\n'
fi
