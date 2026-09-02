#Requires -Version 7
# `git lfs install` 是一次 `git config --global` 寫入。它必須在檔案套用之後才跑：
# create_empty_dot_gitconfig 到那時已經保證 ~/.gitconfig 存在，git 才會寫到那邊，
# 而不是寫進 chezmoi 管的 ~/.config/git/config。POSIX 版的 40-git-lfs 同理。
$ErrorActionPreference = 'Stop'

# chezmoi 跑腳本時不帶互動 shell 的 PATH（AGENTS.md 對 POSIX 端寫的
# `eval "$(brew shellenv)"` 就是同一個問題）。Windows 這邊還多一層：PATH 是
# process 啟動時的快照，所以同一次 apply 裡「前一支腳本剛用 winget 裝好的東西」
# 也不會出現在後一支腳本的 PATH 裡。這段是那兩件事共同的解法。
foreach ($dir in @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    (Join-Path $env:LOCALAPPDATA 'mise\shims')
    (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin')
    (Join-Path $env:ProgramFiles 'Git\cmd')
)) {
    if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}


if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) { exit 0 }

# --skip-repo：只寫全域的 filter 設定，絕不碰當前工作目錄的 repo。
git lfs install --skip-repo *> $null
