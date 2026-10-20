#Requires -Version 7
# neovim 有比 versions.toml 更新的 stable 版時通知使用者。POSIX 版是
# 90-neovim-update-check.sh.tmpl，兩邊逐條對稱。pin 是刻意的（見 50-neovim），
# 所以這支只回報，不升級任何東西。
#
# 每次 apply 都會跑，所以噪音要有上限：
#   - 網路查詢一天最多一次（看快取檔的修改時間）；
#   - 桌面通知每個上游版本只跳一次（notified 檔），之後的 apply 只在輸出裡印一行；
#   - 網路不通、沒有 powershell.exe 或任何其他錯誤一律安靜地 exit 0。這支腳本
#     不可以讓 apply 失敗。
# 想再看一次通知就刪掉狀態目錄。
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


$pinned = '0.12.6'
$semver = '^[0-9]+\.[0-9]+\.[0-9]+$'
$stateDir = Join-Path $env:LOCALAPPDATA 'chezmoi-neovim-check'
$cache = Join-Path $stateDir 'latest'
$notified = Join-Path $stateDir 'notified'

try {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $latest = ''
    $fresh = $false
    if (Test-Path -LiteralPath $cache) {
        $latest = (Get-Content -LiteralPath $cache -Raw).Trim()
        $fresh = (Get-Item -LiteralPath $cache).LastWriteTime -gt (Get-Date).AddDays(-1)
    }
    if (-not $latest -or -not $fresh) {
        # 用 git 而不是 GitHub API：沒有 JSON 要解析、沒有 rate limit，git 本來就是前提。
        # 最大的 vX.Y.Z tag 就是最新的 stable；stable、nightly 這兩個 tag 不符合樣式。
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GIT_HTTP_LOW_SPEED_LIMIT = '1000'
        $env:GIT_HTTP_LOW_SPEED_TIME = '10'
        $tags = git ls-remote --tags --refs https://github.com/neovim/neovim 'v*' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $versions = @($tags | ForEach-Object { ($_ -split 'refs/tags/v', 2)[1] } |
                Where-Object { $_ -match $semver })
            if ($versions.Count) {
                # 以 [version] 排序，0.12.10 才會大於 0.12.9。
                $latest = $versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
                Set-Content -LiteralPath $cache -Value $latest -NoNewline
            }
        }
    }

    # 這個值會進到下面的通知指令裡；不管快取檔或遠端給了什麼，只收數字與點。
    if ($latest -notmatch $semver) { exit 0 }
    if ([version]$latest -le [version]$pinned) { exit 0 }

    [Console]::Error.WriteLine("chezmoi: neovim $latest is available (pinned $pinned in .chezmoitemplates/versions.toml)")

    if ((Test-Path -LiteralPath $notified) -and
        (Get-Content -LiteralPath $notified -Raw).Trim() -eq $latest) {
        exit 0
    }
    if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) { exit 0 }

    # toast 要 Windows PowerShell 5.1 才載得到，理由見 windows-toast.ps1。
    # -EncodedCommand 收 UTF-16LE 的 base64，免掉跨 process 的引號問題。
    $title = 'Neovim update available'
    $body = "neovim $latest is out; dotfiles pin $pinned in .chezmoitemplates/versions.toml"
    $toast = "`$ToastTitle = '$title'; `$ToastBody = '$body'`n" + @'
# Windows toast notification. Runs under Windows PowerShell 5.1 (powershell.exe),
# not pwsh 7: pwsh 7 runs on .NET (Core), which has no WinRT projection, so the
# ToastNotificationManager type below cannot be loaded there.
# The caller sets $ToastTitle and $ToastBody and passes the whole script through
# -EncodedCommand. Keep this partial ASCII-only: 5.1 is the reader.
# The AppId is the one Windows PowerShell registers for itself; without a
# registered AppId, Show() silently displays nothing.
$ErrorActionPreference = 'Stop'
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$text = $xml.GetElementsByTagName('text')
[void]$text.Item(0).AppendChild($xml.CreateTextNode($ToastTitle))
[void]$text.Item(1).AppendChild($xml.CreateTextNode($ToastBody))
$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
'@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($toast))
    powershell.exe -NoProfile -NonInteractive -EncodedCommand $enc *> $null
    # 真的顯示了才記下這個版本，失敗的話下一次 apply 再試。
    if ($LASTEXITCODE -eq 0) {
        Set-Content -LiteralPath $notified -Value $latest -NoNewline
    }
}
catch {
    exit 0
}
exit 0
