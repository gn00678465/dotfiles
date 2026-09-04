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

version=$(sed -n 's/^- `spec_version`: *\(v[0-9][0-9]*\).*/\1/p' "$spec" | head -1)
status=$(sed -n 's/^- `status`: *\([A-Za-z-]*\).*/\1/p' "$spec" | head -1)
tier=$(sed -n 's/^- `tier`: *\([0-9]\).*/\1/p' "$spec" | head -1)
if [ -z "$version" ] || [ -z "$status" ]; then
    echo "gate-intent: 解析不到 spec_version 或 status: $spec" >&2
    exit 1
fi

# Approval 一節：從標題含 Approval 的 `## ` 開始，到下一個 `## ` 為止。
# 每一版一筆，形式是 `### vN — <date>`（本 repo）或 `approves vN`（範本）。
approval=$(awk '/^## /{inblk = ($0 ~ /Approval/)} inblk' "$spec")
approved=$(printf '%s\n' "$approval" \
    | grep -oE '^### v[0-9]+|approves v[0-9]+' \
    | grep -oE 'v[0-9]+' | sort -t v -k2,2n -u | tr '\n' ' ' | sed 's/ $//')

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
