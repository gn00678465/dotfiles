#Requires -Version 7
# chezmoi 全權管理 ~/.config/powershell/profile.ps1，這支腳本只負責把 pwsh 真正會
# 載入的那個 profile 接到它上面。
#
# 為什麼不讓 chezmoi 直接管 $PROFILE 那個檔案：$PROFILE 落在 Documents 已知資料夾
# 底下，而 Documents 可以被 OneDrive 轉向（轉向後是
# ~\OneDrive\Documents\PowerShell\...）。chezmoi 的 target 路徑由來源檔名決定、
# 不能用模板算，所以來源樹沒辦法同時對上這兩種機器。這裡改成執行期問 pwsh 自己，
# 一條路徑同時涵蓋兩種情形。
$ErrorActionPreference = 'Stop'

# CurrentUserAllHosts（profile.ps1）而不是 CurrentUserCurrentHost
# （Microsoft.PowerShell_profile.ps1）：Windows Terminal、VS Code 的整合終端機、
# 裸 pwsh.exe 是不同的 host，只有 AllHosts 三者都會載入。
$target = $PROFILE.CurrentUserAllHosts

# 把「讓 pwsh 真正載入的 profile 去 source 我們管的那一份」這件事做到冪等。
# 呼叫端必須先設好 $target —— 也就是那個 profile 的實際路徑。
#
# 路徑不在這裡決定，是為了讓這段邏輯可以被測到：真正的 $PROFILE 指向使用者的
# Documents（還可能被 OneDrive 轉向），拿它來跑測試就等於寫使用者的檔案。
# 由呼叫端注入之後，tests/cases/L7 只要把 $target 指到暫存檔就能驗同一份邏輯。
$loader = '. "$HOME/.config/powershell/profile.ps1"'

$parent = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

# 每次 apply 都會跑到這裡。已經有那一行就什麼都不做，否則 profile 會愈長愈長。
$existing = if (Test-Path -LiteralPath $target) { @(Get-Content -LiteralPath $target) } else { @() }
if ($existing | Where-Object { $_.Trim() -eq $loader }) { return }

Write-Output "chezmoi: adding the dotfiles loader to $target"

# 一行一次 Add-Content。實測 `Add-Content -Value <多元素陣列>` 與
# `<陣列> | Add-Content` 在這裡都會把整批併成「用空白分隔的一行」，
# 於是上面那個「已經有了嗎」的比對永遠不成立，每次 apply 都再追加一次。
if ($existing.Count -gt 0) {
    Add-Content -LiteralPath $target -Value ''
}
Add-Content -LiteralPath $target -Value '# Added by chezmoi (dotfiles). The real config lives in the file below.'
Add-Content -LiteralPath $target -Value $loader

