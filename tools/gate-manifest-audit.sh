#!/bin/sh
# 執行完整性稽核：比對「應該跑的層」與「真的留下記號的層」。
#
#   tools/gate-manifest-audit.sh <manifest-file> <ran-file>
#
# 印出一段標題不算跑過一層，`set -e` 串 `&&` 也不算處理了狀態碼。這支腳本是
# gate.sh 唯一承認的「跑完了」定義。抽成獨立檔案是為了它自己能被驗證：
# 餵一份缺項的 ran-file 進來，它必須紅（negative control）。
#
# fail closed：讀不到任何一個輸入、任何一邊有對方沒有的項目，都是失敗。
set -eu

[ $# -eq 2 ] || { echo "usage: gate-manifest-audit.sh <manifest> <ran>" >&2; exit 2; }
manifest=$1
ran=$2

[ -r "$manifest" ] || { echo "gate-manifest-audit: 讀不到 manifest: $manifest" >&2; exit 1; }
[ -r "$ran" ] || { echo "gate-manifest-audit: 讀不到執行記號: $ran" >&2; exit 1; }

missing=""
while IFS= read -r layer; do
    [ -n "$layer" ] || continue
    if ! grep -qxF "$layer" "$ran"; then
        missing="$missing $layer"
    fi
done < "$manifest"

extra=""
while IFS= read -r layer; do
    [ -n "$layer" ] || continue
    if ! grep -qxF "$layer" "$manifest"; then
        extra="$extra $layer"
    fi
done < "$ran"

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

n=$(grep -c . "$manifest")
echo "gate-manifest-audit: $n 層全部留下執行記號"
