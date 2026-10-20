#Requires -Version 7
# apm-go 走 mise 的 github backend。POSIX 版是 56-apm-go.sh.tmpl，兩邊逐條對稱。
# mise 把兩段設定寫進全域的 ~/.config/mise/config.toml：
#   [tools]    "github:gn00678465/apm-go" = { version = "<前綴>", prerelease = true }
#   [settings] minimum_release_age_excludes = [..., "github:gn00678465/apm-go"]
# tool 後面的中括號是 `mise use` 帶 tool option 的寫法；mise 以 TOML 解析它，
# 所以 prerelease = true 寫進去的是布林值。
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
    (Join-Path $env:ProgramFiles 'GitHub CLI')
)) {
    if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}


if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    # Write-Warning + exit 0，與 50-neovim 相同：缺 mise 只跳過這一項。
    Write-Warning 'chezmoi: mise not found, skipping apm-go'
    exit 0
}

# yes 是 mise 的設定而不是 use 的旗標；chezmoi 無人值守跑這支腳本。
$env:MISE_YES = '1'
$backend = 'github:gn00678465/apm-go'

# 要在 mise use 之前：解析版本時排除就得生效，否則發布未滿 24h 的版本會被略過。
# mise settings add 不檢查重複，所以先看一下。
$excludes = mise settings get minimum_release_age_excludes
if ($LASTEXITCODE -ne 0) { throw "mise settings get minimum_release_age_excludes failed ($LASTEXITCODE)" }
if (-not ($excludes -join "`n").Contains("`"$backend`"")) {
    mise settings add minimum_release_age_excludes $backend
    if ($LASTEXITCODE -ne 0) { throw "mise settings add minimum_release_age_excludes $backend failed ($LASTEXITCODE)" }
}

$tool = "${backend}[prerelease=true]@0.4"
mise use --global $tool
if ($LASTEXITCODE -ne 0) { throw "mise use --global $tool failed ($LASTEXITCODE)" }
