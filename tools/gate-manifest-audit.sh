#!/bin/sh
# 執行完整性稽核：比對「應該跑的層」與「真的留下記號的層」。
#
#   tools/gate-manifest-audit.sh <manifest-file> <ran-file>
#
# 印出一段標題不算跑過一層，`set -e` 串 `&&` 也不算處理了狀態碼。這支腳本是
# gate.sh 唯一承認的「跑完了」定義。抽成獨立檔案是為了它自己能被驗證：
# tests/harness_test.py 餵缺項、重複、末行無換行的輸入進來，每一條都配一個
# 拔掉修正的 mutant 當控制項。
#
# fail closed：讀不到任何一個輸入、任何一邊有對方沒有的項目，都是失敗。
set -eu

[ $# -eq 2 ] || { echo "usage: gate-manifest-audit.sh <manifest> <ran>" >&2; exit 2; }
manifest=$1
ran=$2

[ -r "$manifest" ] || { echo "gate-manifest-audit: 讀不到 manifest: $manifest" >&2; exit 1; }
[ -r "$ran" ] || { echo "gate-manifest-audit: 讀不到執行記號: $ran" >&2; exit 1; }

# `read` 在沒有結尾換行時讀得到內容卻回非零，迴圈因此漏掉最後一行：manifest 是
# "a\nb" 而 ran 只有 "a" 時，舊版從來沒檢查過 b，照樣印「2 層全部留下執行記號」
# 並以 0 結束 —— 正好在它存在的那件事上 fail open。
missing=""
while IFS= read -r layer || [ -n "$layer" ]; do
    [ -n "$layer" ] || continue
    if ! grep -qxF "$layer" "$ran"; then
        missing="$missing $layer"
    fi
done < "$manifest"

extra=""
while IFS= read -r layer || [ -n "$layer" ]; do
    [ -n "$layer" ] || continue
    if ! grep -qxF "$layer" "$manifest"; then
        extra="$extra $layer"
    fi
done < "$ran"

# 重複項：grep -qxF 只答「在不在」，兩邊各有幾個它都說在。下面的層數也會跟著虛報
# （manifest 寫兩次 a，計數是 2，相異層只有 1）。重複沒有正當用途，直接拒絕。
dup=""
for f in "$manifest" "$ran"; do
    d=$(grep -v '^$' "$f" | sort | uniq -d)
    [ -n "$d" ] && dup="$dup$(printf '%s' "$d" | sed "s|^|$f: |")
"
done
if [ -n "$dup" ]; then
    echo "gate-manifest-audit: 有重複的層名稱:" >&2
    printf '%s\n' "$dup" >&2
    exit 1
fi

rc=0
if [ -n "$missing" ]; then
    echo "gate-manifest-audit: 這些層沒有留下執行記號:$missing" >&2
    rc=1
fi
if [ -n "$extra" ]; then
    echo "gate-manifest-audit: 有不在 manifest 裡的層留下記號:$extra" >&2
    rc=1
fi
[ "$rc" -eq 0 ] || exit 1

# 相異層數，不是行數。上面已經拒絕重複，這裡兩者相等；分開算是為了讓這個數字
# 的意義不依賴上面那道檢查還在。
n=$(sort "$manifest" | grep -v '^$' | uniq | grep -c .)
echo "gate-manifest-audit: $n 層全部留下執行記號"
