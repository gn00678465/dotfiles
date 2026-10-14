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
