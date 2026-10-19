#Requires -Version 7
# gh-stack（gh 的 stacked PR 擴充，`gh stack`），釘在 versions.toml 的 tag。
# POSIX 版是 57-gh-stack.sh.tmpl，兩邊逐條對稱。gh 本身由 30-install-winget-packages 裝。
# `run_`，與 55-cc-statusline 相同：使用者移除後，下一次 apply 會裝回來。
# `gh extension install` 不需要先 `gh auth login`。
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
    (Join-Path $env:ProgramFiles 'GitHub CLI')
)) {
    if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}


if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    # Write-Warning + exit 0，與 50-neovim 相同：缺 gh 只跳過這一項。
    Write-Warning 'chezmoi: gh not found, skipping gh-stack'
    exit 0
}

$repo = 'github/gh-stack'
$pin = 'v0.2.1'

# 非 TTY 的 `gh extension list` 每列是以 tab 分隔的 NAME、REPO、VERSION；binary 擴充的
# VERSION 就是 release tag。一個擴充都沒有時退出碼是 1，這裡不算錯誤。
$list = gh extension list 2>$null
$current = ''
$other = ''
foreach ($line in @($list)) {
    $fields = "$line" -split "`t"
    if ($fields[0] -ne 'gh stack') { continue }
    if ($fields.Count -ge 2 -and $fields[1] -eq $repo) {
        $current = if ($fields.Count -ge 3) { $fields[2] } else { '' }
    }
    else {
        $other = if ($fields.Count -ge 2) { $fields[1] } else { '?' }
    }
}

if ($other) {
    # `gh stack` 已由別的擴充提供。那是使用者的，不移除。
    Write-Warning "chezmoi: gh stack is provided by $other, skipping $repo"
    exit 0
}
if ($current -eq $pin) { exit 0 }

# 已安裝時 install 只會警告並保留舊版，所以換 pin 要先移除。
if ($current) {
    gh extension remove stack
    if ($LASTEXITCODE -ne 0) { throw "gh extension remove stack failed ($LASTEXITCODE)" }
}
gh extension install $repo --pin $pin
if ($LASTEXITCODE -ne 0) { throw "gh extension install $repo --pin $pin failed ($LASTEXITCODE)" }
