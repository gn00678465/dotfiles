#!/bin/sh
# 在目前目錄組出假的 agent 家目錄，給 recall 的 eval 案例用。
#
#   build_home.sh <fixtures-dir> <fixture-name>...
#
# 專案路徑就是目前目錄 (eval 時是 agent 的 cwd)。產物：./fixture-home/claude、
# ./fixture-home/codex、./fixture-home/cursor。fixture 內的 __PROJ__ 換成目前目錄的
# 絕對路徑。名稱含 stale 的檔案 mtime 設成 30 天前，其餘為現在。
#
# eval 的 scaffold 在暫存 cwd 執行，案例目錄要從 $0 推得，所以本檔的路徑由呼叫端傳入。
set -eu
fixtures=$1
shift
proj=$PWD
home=$PWD/fixture-home
# Claude Code 的 slug：路徑中非英數字元換成 -
claude_slug=$(printf '%s' "$proj" | sed 's/[^A-Za-z0-9]/-/g')
# Cursor 的 slug：去掉開頭 /，/ 換成 -
cursor_slug=$(printf '%s' "$proj" | sed 's|^/||; s|/|-|g')

place() { # src dest
    mkdir -p "$(dirname "$2")"
    sed "s|__PROJ__|$proj|g" "$1" > "$2"
    case "$1" in
        *stale*) touch -d '30 days ago' "$2" ;;
    esac
}

for name in "$@"; do
    src=$fixtures/$name.jsonl
    case "$name" in
        claude-main)
            place "$src" "$home/claude/projects/$claude_slug/aaaaaaaa-0000-4000-8000-000000000001.jsonl" ;;
        claude-stale)
            place "$src" "$home/claude/projects/$claude_slug/cccccccc-0000-4000-8000-000000000003.jsonl" ;;
        codex-main)
            place "$src" "$home/codex/sessions/2026/09/20/rollout-2026-09-20T03-00-00-main.jsonl" ;;
        cursor-unknown)
            place "$src" "$home/cursor/projects/$cursor_slug/agent-transcripts/11111111-aaaa-4bbb-8ccc-000000000001/11111111-aaaa-4bbb-8ccc-000000000001.jsonl" ;;
        *) echo "unknown fixture: $name" >&2; exit 2 ;;
    esac
done
echo "fixture home: $home"
echo "project: $proj"
