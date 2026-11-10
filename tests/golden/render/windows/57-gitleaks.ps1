#Requires -Version 7
# gitleaks 走 mise 的 aqua backend（aqua 會驗證 release 的 checksum）。
# POSIX 版是 57-gitleaks.sh.tmpl，兩邊逐條對稱。
# mise 把它寫進全域的 ~/.config/mise/config.toml：
#   [tools]  "aqua:gitleaks/gitleaks" = "<版本>"
# `run_`，與 55-cc-statusline 相同：使用者移除後，下一次 apply 會裝回來。
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
    Write-Warning 'chezmoi: mise not found, skipping gitleaks'
    exit 0
}

# yes 是 mise 的設定而不是 use 的旗標；chezmoi 無人值守跑這支腳本。
$env:MISE_YES = '1'
$tool = 'aqua:gitleaks/gitleaks@8.30.1'
mise use --global $tool
if ($LASTEXITCODE -ne 0) { throw "mise use --global $tool failed ($LASTEXITCODE)" }
