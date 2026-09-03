#Requires -Version 7
# Neovim（走 mise）+ LazyVim starter。POSIX 版是 50-neovim.sh.tmpl，兩邊逐條對稱，
# 差別只有路徑。`before`，因為 git clone 拒絕非空目標，而 chezmoi 自己也管
# AppData\Local\nvim 底下的檔案：starter 必須先落地，chezmoi 再把我們的覆寫寫上去。
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
    # Write-Warning 而不是 Write-Error：在 $ErrorActionPreference = 'Stop' 之下
    # Write-Error 是**終止性**的，後面那行 exit 0 根本到不了，chezmoi 收到的是 1。
    # 這支是 run_onchange_before_，非零退出會在任何檔案被寫出來之前中止整個 apply
    # ——使用者連 PowerShell profile 都拿不到。POSIX 版是 `echo >&2; exit 0`，
    # 這裡要對稱。由 tests/cases/L7 的退出碼斷言釘住。
    Write-Warning 'chezmoi: mise not found, skipping neovim'
    exit 0
}

# yes 是 mise 的設定而不是 use 的旗標；chezmoi 無人值守跑這支腳本。
$env:MISE_YES = '1'
mise use --global neovim@0.12.5
if ($LASTEXITCODE -ne 0) { throw "mise use --global neovim@0.12.5 failed ($LASTEXITCODE)" }

# Windows 的 neovim standard-path（實測 nvim 0.12.5，見
# docs/research/windows-native-support.md）：
#   config = %LOCALAPPDATA%\nvim
#   data / state / log = %LOCALAPPDATA%\nvim-data   ← 三者同一個目錄
#   cache  = %TEMP%\nvim
# 所以要備份的是三個目錄，不是 POSIX 那邊的四個：state 與 data 在 Windows 上
# 是同一個路徑，備份兩次會把第一次的結果又搬進 .bak 裡。
$nvimConfig = Join-Path $env:LOCALAPPDATA 'nvim'
$nvimData   = Join-Path $env:LOCALAPPDATA 'nvim-data'
$nvimCache  = Join-Path $env:TEMP 'nvim'

# 我們自己的標記檔，不是 LazyVim 的。一旦這支腳本會搬東西，「目錄存在」就不再是
# 可用的守衛：重跑時（這是 run_onchange_，改了腳本就會重跑）既有的
# %LOCALAPPDATA%\nvim 是使用者自己的設定，不是外來的，不可以再被搬走重 clone。
# 刪掉這個檔案就是刻意要求下次 apply 重新 bootstrap。
$marker = Join-Path $nvimConfig '.chezmoi-lazyvim-starter'

function Backup-NvimDirectory {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    # Move-Item 在目標已存在且是目錄時，會把來源搬「進去」，靜靜地把上一份備份
    # 埋掉。跟 POSIX 的 `mv dir dir.bak` 同一個陷阱，處理方式也一樣：改用時間戳。
    $dest = "$Path.bak"
    if (Test-Path -LiteralPath $dest) {
        $dest = "$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
    Write-Output "chezmoi: backing up $Path -> $dest"
    Move-Item -LiteralPath $Path -Destination $dest
}

if (-not (Test-Path -LiteralPath $marker)) {
    # LazyVim 要乾淨的起點：既有的設定與外掛資料一律搬開，不合併。什麼都不刪。
    Backup-NvimDirectory $nvimConfig
    Backup-NvimDirectory $nvimData
    Backup-NvimDirectory $nvimCache

    Write-Output "chezmoi: cloning the LazyVim starter into $nvimConfig"
    git clone --depth 1 https://github.com/LazyVim/starter $nvimConfig
    if ($LASTEXITCODE -ne 0) { throw "git clone of the LazyVim starter failed ($LASTEXITCODE)" }

    Remove-Item -LiteralPath (Join-Path $nvimConfig '.git') -Recurse -Force
    New-Item -ItemType File -Path $marker -Force | Out-Null
}
