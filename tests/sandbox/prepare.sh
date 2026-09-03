#!/bin/sh
# 把待測的來源樹與探針腳本放進 Windows Sandbox 的唯讀對應資料夾。
#
#   tests/sandbox/prepare.sh [sandbox-dir]
#
# 預設 sandbox-dir 是 /mnt/c/Users/$USER_WIN/chezmoi-sandbox，可以用第一個引數或
# CHEZMOI_SANDBOX_DIR 覆蓋。跑完之後由使用者自己按下 sandbox.wsb 啟動；
# 這支腳本不會去開那個視窗（啟動 Sandbox 會佔用對方的桌面）。
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SANDBOX=${1:-${CHEZMOI_SANDBOX_DIR:-}}

if [ -z "$SANDBOX" ]; then
    win_home=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' || true)
    [ -n "$win_home" ] || { echo "prepare: 給不出 sandbox 目錄，請用引數指定" >&2; exit 2; }
    SANDBOX="$(wslpath -u "$win_home")/chezmoi-sandbox"
fi

[ -d "$SANDBOX/src" ] || { echo "prepare: 找不到 $SANDBOX/src" >&2; exit 2; }

echo "prepare: 目標 $SANDBOX"
rm -rf "${SANDBOX:?}/src/dotfiles"
mkdir -p "$SANDBOX/src/dotfiles" "$SANDBOX/out"

# 用 git archive 而不是 cp：只帶已提交的內容，不含 .git 與任何本機殘留，
# sandbox 裡跑的就確定是這個 commit。
# -m：不還原 mtime。目標在 DrvFs（/mnt/c）上，utime 會被拒絕，
# 沒有 -m 的話 tar 會為了每個檔案報錯並以非零狀態結束。
git -C "$REPO" archive HEAD | tar -x -m -C "$SANDBOX/src/dotfiles"
cp "$REPO/tests/sandbox/_probe.ps1" "$SANDBOX/src/_probe.ps1"

# 之前那一輪的結果清掉，免得看到舊的還以為是新的。
rm -f "$SANDBOX/out/results.tsv" "$SANDBOX/out/transcript.txt" "$SANDBOX/out/treesitter.log"

cat <<MSG

prepare: 完成。commit $(git -C "$REPO" rev-parse --short HEAD)

接下來（由你操作，這支腳本不會自己開視窗）：

  1. 在 Windows 上按兩下 $(wslpath -w "$SANDBOX")\\sandbox.wsb
  2. 沙箱開機後 _probe.ps1 會自己跑（可能要 20-30 分鐘，treesitter 那段最久）
  3. 跑完後回報結果在  $SANDBOX/out/results.tsv

MSG
