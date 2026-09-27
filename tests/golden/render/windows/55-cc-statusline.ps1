#Requires -Version 7
# cc-statusline（Claude Code 的 statusLine）走 mise，再複製到
# dot_claude/modify_settings.json 寫進 statusLine.command 的固定路徑。
# POSIX 版是 55-cc-statusline.sh.tmpl，兩邊逐條對稱。
# 用複製而不是指向 mise 的目錄：`mise where` 帶版本號，`mise upgrade` 會刪掉舊版本
# 目錄，而 mise 在 Windows 上把 `latest` 寫成一般檔案，不是可用的路徑。
# `run_`：使用者刪掉 binary 後，下一次 apply 會裝回來；雜湊相同時什麼都不做。
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


if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    # Write-Warning + exit 0，與 50-neovim 相同：缺 mise 只跳過這一項。
    Write-Warning 'chezmoi: mise not found, skipping cc-statusline'
    exit 0
}

# yes 是 mise 的設定而不是 use 的旗標；chezmoi 無人值守跑這支腳本。
$env:MISE_YES = '1'
$tool = 'github:gn00678465/StatusLine@2.2.0'
mise use --global $tool
if ($LASTEXITCODE -ne 0) { throw "mise use --global $tool failed ($LASTEXITCODE)" }

$where = mise where $tool
if ($LASTEXITCODE -ne 0) { throw "mise where $tool failed ($LASTEXITCODE)" }
$src = Join-Path $where 'cc-statusline.exe'
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "$src not found after mise install" }

$destDir = Join-Path $HOME '.claude\cc-statusline'
$dest = Join-Path $destDir 'cc-statusline.exe'

# 前幾次換下來的舊檔。當時仍在執行的那一份刪不掉，就留到下一次。
Get-ChildItem -LiteralPath $destDir -Filter 'cc-statusline.exe.old-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

if ((Test-Path -LiteralPath $dest) -and
    (Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dest).Hash) {
    exit 0
}

# Claude Code 每秒執行一次這個 exe。Windows 不能覆寫執行中的 exe，但可以改名：
# 先把新檔放到同目錄，再把舊檔改名移開，最後把新檔改名成目標。
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$tmp = "$dest.new"
Copy-Item -LiteralPath $src -Destination $tmp -Force
if (Test-Path -LiteralPath $dest) {
    Move-Item -LiteralPath $dest -Destination "$dest.old-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
Move-Item -LiteralPath $tmp -Destination $dest
