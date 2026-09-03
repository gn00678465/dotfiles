# PowerShell 7 的實際設定。pwsh 真正載入的檔案是 $PROFILE（在 Documents 底下，
# 可能被 OneDrive 轉向），那個檔案由 .chezmoiscripts/run_after_60-pwsh-profile.ps1
# 在執行期建立，內容只有一行「. 這個檔案」。理由見該腳本的註解。
#
# 這是 dot_zshrc.tmpl 的對應物，段落順序也刻意對齊。

# ---- PATH ---------------------------------------------------------------
# winget 的 shim 目錄與 mise 的 shims。安裝器通常會自己寫進使用者 PATH，但那要
# 重新登入才生效；這裡補上，讓「裝完馬上開一個新終端機」就能用。
foreach ($dir in @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    (Join-Path $env:LOCALAPPDATA 'mise\shims')
)) {
    if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}

# ---- prompt -------------------------------------------------------------
# 對應 zsh 的 Powerlevel10k。主題檔由 .chezmoiexternal.toml.tmpl 釘版本 + sha256
# 抓下來，不用 $env:POSH_THEMES_PATH —— 那個變數在 Store 版的 oh-my-posh 上會指向
# 一個不存在的目錄（實測），靠它定位主題會在部分機器上直接壞掉。
$ompTheme = Join-Path $HOME '.config/oh-my-posh/powerlevel10k_rainbow.omp.json'
# 這些 Get-Command 守衛不是可有可無的禮貌：profile 在每次開 shell 時都會跑，
# 一個沒裝到的工具會讓使用者連一個能用的 shell 都拿不到。
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $ompTheme)) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# ---- 輸入體驗 -----------------------------------------------------------
# PSReadLine 是 pwsh 7 內建的，一個模組同時涵蓋 zsh 那邊的兩個外掛：
#   InlineView 的歷史預測 = zsh-autosuggestions
#   內建的語法著色         = zsh-syntax-highlighting
Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
Set-PSReadLineOption -HistoryNoDuplicates -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# PSFzf = fzf-tab。-TabExpansion 把 Tab 補全接到 fzf 上，這是 fzf-tab 的核心行為；
# 兩個 chord 對應 fzf 官方在 zsh 上的預設鍵位。
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' `
                    -PSReadlineChordReverseHistory 'Ctrl+r' `
                    -TabExpansion
}

# ---- mise ---------------------------------------------------------------
# zsh 那邊是 Oh My Zsh 的 mise 外掛代跑 `mise activate zsh`；pwsh 沒有外掛框架，
# 直接呼叫。
if (Get-Command mise -ErrorAction SilentlyContinue) {
    (mise activate pwsh) -join "`n" | Invoke-Expression
}
