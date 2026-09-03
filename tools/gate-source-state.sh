#!/bin/sh
# 印出來源狀態：commit SHA + 工作樹是否乾淨。
#
# gate.sh 在最後一次完整執行的「前」與「後」各叫一次；兩次不同就代表這次跑出來的
# 每一個數字描述的是一棵已經不存在的樹，整輪作廢。
#
# 未追蹤的檔案一律視為髒。唯一的豁免是下面這份白名單，而且它會被原樣印進 evidence
# report —— 讀者看不到的豁免等於無法定價的豁免。白名單裡沒有任何產品路徑。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO"

# 白名單：gate 自己的產出目錄。除此之外任何未追蹤的檔案都讓來源狀態變髒。
WHITELIST='.gate/'

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "gate-source-state: 不是 git repository" >&2
    exit 1
fi

# 淺 clone 會讓 baseline、ordering、RED 重建三件事同時消失，這裡直接拒絕，
# 而不是吐一個看起來正常、實際上被削弱過的狀態。
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "gate-source-state: 淺 clone，拒絕產出來源狀態" >&2
    exit 1
fi

sha=$(git rev-parse HEAD)

dirty=$(git status --porcelain | grep -v "^?? $WHITELIST" || true)
if [ -n "$dirty" ]; then
    state="dirty"
else
    state="clean"
fi

printf 'commit=%s\n' "$sha"
printf 'worktree=%s\n' "$state"
printf 'untracked_whitelist=%s\n' "$WHITELIST"
if [ -n "$dirty" ]; then
    printf 'dirty_entries:\n%s\n' "$dirty"
fi

[ "$state" = "clean" ]
