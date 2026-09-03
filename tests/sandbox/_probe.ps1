<#
    End-to-end check inside Windows Sandbox (test layer L9).

    The sandbox is the only place a real install is allowed to run: the host is
    off limits (see specs/windows-support/SPEC.md, Must NOT #1). Everything
    here runs against a throwaway machine.

    Launched by chezmoi-sandbox\sandbox.wsb as the LogonCommand, under Windows
    PowerShell 5.1 (the sandbox base image has no pwsh). ASCII only, for the
    same reason init.ps1 is: 5.1 decodes a BOM-less .ps1 with the ANSI code page
    and mangles anything else. See docs/research/windows-native-support.md 8.

    Two modes.

    Local (no -Branch): the source tree is the read-only mapped folder
    C:\src\dotfiles, put there by tests/sandbox/prepare.sh, and output goes to
    the mapped C:\out. This is what sandbox.wsb's LogonCommand runs.

    Remote (-Branch <name>): nothing is mapped and nothing is prepared. chezmoi
    clones the branch itself, and the expected-value checks read whatever
    `chezmoi source-path` reports instead of C:\src. Run it from inside a stock
    sandbox with one line:

      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/gn00678465/dotfiles/<branch>/tests/sandbox/_probe.ps1))) -Branch <branch>

    Output falls back to the desktop when C:\out is not mapped, and the whole
    results table is echoed to the console at the end -- closing the sandbox
    destroys the files, so the console is the only copy that survives.

    Nothing here is part of the installed dotfiles. In particular the winget
    bootstrap below exists only because the sandbox base image ships without
    App Installer; a real Windows 11 machine already has winget.
#>

param([string] $Branch)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# winget and chezmoi emit UTF-8. Windows PowerShell 5.1 decodes a native
# command's stdout using [Console]::OutputEncoding, which on a zh-TW machine is
# CP950 -- the first real L9 run recorded winget's output as mojibake in
# results.tsv, which made it unreadable. The try/catch is not defensive padding:
# in local mode this runs as a LogonCommand, which may have no console attached,
# and setting the property throws there. Say so rather than swallowing it.
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
} catch {
    Write-Host "probe: could not switch the console to UTF-8: $($_.Exception.Message)"
}

$remote = -not [string]::IsNullOrWhiteSpace($Branch)

# Probe existence *before* creating anything: C:\ is writable inside the sandbox,
# so New-Item would happily invent an unmapped C:\out and the results would be
# thrown away when the sandbox closes.
$outDir = 'C:\out'
if (-not (Test-Path -LiteralPath $outDir)) {
    $outDir = Join-Path $env:USERPROFILE 'Desktop\chezmoi-probe'
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$transcriptPath = Join-Path $outDir 'transcript.txt'
$resultsPath    = Join-Path $outDir 'results.tsv'
$treesitterLog  = Join-Path $outDir 'treesitter.log'

Start-Transcript -Path $transcriptPath -Force | Out-Null
Write-Host ("probe: mode={0} outDir={1}" -f $(if ($remote) { "remote branch $Branch" } else { 'local' }), $outDir)

$results = New-Object System.Collections.ArrayList

function Add-Result {
    param([string] $Name, [string] $Status, [string] $Detail = '')
    $line = "{0}`t{1}`t{2}" -f $Status, $Name, ($Detail -replace "`r?`n", ' | ')
    Write-Host $line
    [void]$results.Add($line)
}

function Check {
    param([string] $Name, [scriptblock] $Test)
    try {
        $detail = & $Test
        if ($detail -is [array]) { $detail = $detail -join ' ' }
        Add-Result $Name 'PASS' "$detail"
    } catch {
        Add-Result $Name 'FAIL' $_.Exception.Message
    }
}

function Invoke-Streamed {
    # Print each line as it arrives AND keep it. The probe used to collect a
    # subprocess's whole output into a variable and print it when the command
    # finished, so the console sat silent for the minutes winget and
    # `chezmoi apply` take. From the outside that is indistinguishable from a
    # hang, and in remote mode killing the sandbox costs the whole 20-30 minute
    # run. What the caller gets back is unchanged -- only the timing of the
    # printing moves.
    param([scriptblock] $Command)
    $lines = New-Object System.Collections.ArrayList
    & $Command 2>&1 | ForEach-Object {
        $line = "$_"
        Write-Host $line
        [void]$lines.Add($line)
    }
    return ($lines -join "`n")
}

function Get-OutputTail {
    # A failure's detail is the only thing that survives remote mode: the
    # transcript dies with the sandbox. Carry the end of the command's output,
    # which is where the reason is.
    param([string] $Text, [int] $Lines = 30)
    if (-not $Text) { return '(no output)' }
    $all = @($Text -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    if ($all.Count -le $Lines) { return ($all -join "`n") }
    return (($all[($all.Count - $Lines)..($all.Count - 1)]) -join "`n")
}

function Update-ProbePath {
    # Windows PATH is a snapshot taken when the process starts. This probe starts
    # before anything is installed, so nothing winget adds to the real PATH is
    # visible to it. Re-read the authoritative values instead.
    #
    # [Environment]::GetEnvironmentVariable with a scope, rather than reading the
    # registry through the provider: it is the documented API for exactly this,
    # it expands REG_EXPAND_SZ, and it takes the provider's own semantics out of
    # a path that has already been wrong once.
    #
    # Everything here is reported, not just done. The third real L9 run rebuilt
    # the PATH, reported all ten tools as "not found", and said nothing at all
    # about why -- while the M12 check, which has to actually run nvim,
    # tree-sitter and gcc, passed. Whatever went wrong, silence is what made it
    # unreadable, so the outcome of this function is now a result line and a
    # check that can fail.
    $report = @()
    $collected = @()
    foreach ($scope in @('Machine', 'User')) {
        try {
            $value = [Environment]::GetEnvironmentVariable('Path', $scope)
            $entries = @()
            if ($value) { $entries = @($value -split ';' | Where-Object { $_.Trim() }) }
            $collected += $entries
            $report += ("{0}={1}" -f $scope.ToLowerInvariant(), $entries.Count)
        } catch {
            $report += ("{0}=ERROR({1})" -f $scope.ToLowerInvariant(), $_.Exception.Message)
        }
    }

    # One deliberate addition on top of the two scopes: mise's shim directory is
    # not on the real PATH by design -- `mise activate` puts it there from the
    # shell profile, and this probe loads no profile. nvim is a mise shim, so
    # without this the probe would report it missing for a reason that has
    # nothing to do with whether the install worked.
    $shims = Join-Path $env:LOCALAPPDATA 'mise\shims'
    $collected += $shims

    $before = @($env:PATH -split ';' | Where-Object { $_.Trim() }).Count
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $merged = New-Object System.Collections.ArrayList
    foreach ($d in (@($env:PATH -split ';') + $collected)) {
        $t = "$d".Trim()
        if (-not $t) { continue }
        if ($seen.Add($t.TrimEnd('\').ToLowerInvariant())) { [void]$merged.Add($t) }
    }
    $env:PATH = ($merged -join ';')
    $report += ("before={0} after={1}" -f $before, $merged.Count)
    $report += ("shims={0}" -f (Test-Path -LiteralPath $shims))

    # Set-Variable -Scope Global rather than $script:: this file is also run as a
    # scriptblock built by [scriptblock]::Create() from irm, and $script: does not
    # mean the same thing in both cases.
    Set-Variable -Name ProbePathReport -Scope Global -Value ($report -join ' ')
}

# ---------------------------------------------------------------- winget
# Sandbox has no App Installer. Pull the latest winget-cli release plus its
# dependency bundle and register them for this user.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'probe: bootstrapping winget (not part of the dotfiles)'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'

        $bundle = $rel.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
        $deps   = $rel.assets | Where-Object { $_.name -like 'DesktopAppInstaller_Dependencies.zip' } | Select-Object -First 1

        $bundlePath = Join-Path $env:TEMP $bundle.name
        Invoke-WebRequest $bundle.browser_download_url -OutFile $bundlePath

        if ($deps) {
            $zipPath = Join-Path $env:TEMP $deps.name
            Invoke-WebRequest $deps.browser_download_url -OutFile $zipPath
            $depDir = Join-Path $env:TEMP 'winget-deps'
            Expand-Archive -Path $zipPath -DestinationPath $depDir -Force
            foreach ($appx in (Get-ChildItem -Path (Join-Path $depDir 'x64') -Filter *.appx -ErrorAction SilentlyContinue)) {
                Add-AppxPackage -Path $appx.FullName -ErrorAction SilentlyContinue
            }
        }

        Add-AppxPackage -Path $bundlePath
        Start-Sleep -Seconds 5
        Update-ProbePath
    } catch {
        Add-Result 'winget bootstrap' 'FAIL' $_.Exception.Message
    }
}

Check 'winget is available' {
    $v = (winget --version) 2>&1
    if (-not $v) { throw 'winget not on PATH' }
    "$v"
}

# ---------------------------------------------------------------- install
# Run the repo's own bootstrap, exactly as a user would. Locally that means the
# mapped source tree (the branch under test may not be pushed); remotely it means
# letting chezmoi clone the branch, which is also what a real user's first run does.
$repo = 'C:\src\dotfiles'
if (-not $remote) {
    Check 'source tree is present' {
        if (-not (Test-Path (Join-Path $repo '.chezmoiscripts'))) { throw "missing $repo" }
        'ok'
    }
}

Write-Host ''
Write-Host 'probe: installing pwsh 7, git and chezmoi with winget'
Write-Host 'probe: this usually takes 2-5 minutes; output follows as it arrives'
Check 'init.ps1 installs pwsh 7, git and chezmoi' {
    # Reuse init.ps1's package list without its `chezmoi init <github user>` tail:
    # the init call below is the one under test, and it differs per mode.
    foreach ($id in @('Microsoft.PowerShell', 'Git.Git', 'twpayne.chezmoi')) {
        Update-ProbePath
        $cmd = @{ 'Microsoft.PowerShell' = 'pwsh'; 'Git.Git' = 'git'; 'twpayne.chezmoi' = 'chezmoi' }[$id]
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { continue }
        Write-Host "probe: winget install $id"
        [void](Invoke-Streamed { winget install --exact --id $id --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity })
        if ($LASTEXITCODE -ne 0) { throw "winget install $id -> $LASTEXITCODE" }
    }
    Update-ProbePath
    'installed'
}

Write-Host ''
Write-Host 'probe: running chezmoi init --apply -- this is the whole install'
Write-Host 'probe: this usually takes 5-15 minutes (winget packages, externals, LazyVim clone)'
Check 'chezmoi init --apply completes' {
    Update-ProbePath
    # Not $args: that is an automatic variable, and shadowing it inside a
    # scriptblock is a 5.1 footgun for no gain.
    if ($remote) {
        $cmArgs = @('init', '--apply', '--branch', $Branch, 'gn00678465')
    } else {
        # --source points at the read-only mapped folder; chezmoi writes only to
        # the destination and to its own state under %LOCALAPPDATA%.
        $cmArgs = @('init', '--apply', '--source', $repo)
    }
    Write-Host "probe: chezmoi $($cmArgs -join ' ')"
    # Invoke-Streamed also does the "$_" conversion: under 5.1 a native command's
    # stderr arrives as ErrorRecords, and formatting those wraps every line in a
    # CategoryInfo/FullyQualifiedErrorId block -- git's progress output turns into
    # pages of fake-looking errors. "$_" is the message alone.
    $out = Invoke-Streamed { & chezmoi @cmArgs }
    if ($LASTEXITCODE -ne 0) {
        throw ("chezmoi init --apply -> $LASTEXITCODE" + "`n" + (Get-OutputTail $out 30))
    }
    'applied'
}

Update-ProbePath

Check 'PATH rebuilt from Machine+User environment' {
    if (-not $global:ProbePathReport) { throw 'Update-ProbePath produced no report' }
    if ($global:ProbePathReport -match 'ERROR') { throw $global:ProbePathReport }
    $global:ProbePathReport
}

# In remote mode there is no C:\src to read expected values from; the clone
# chezmoi just made is the source tree, and only chezmoi knows where it put it.
if ($remote) {
    $sourcePath = (& chezmoi source-path) | Select-Object -First 1
    if ($sourcePath) { $repo = $sourcePath }
    Check 'source tree is present' {
        if (-not $sourcePath) { throw 'chezmoi source-path returned nothing' }
        if (-not (Test-Path (Join-Path $repo '.chezmoiscripts'))) { throw "missing $repo" }
        $repo
    }
}

# ---------------------------------------------------------------- tools
foreach ($t in @('mise', 'fzf', 'rg', 'fd', 'lazygit', 'git-lfs', 'tree-sitter', 'oh-my-posh', 'gcc', 'nvim')) {
    $name = $t
    Check "tool on PATH: $name" {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $c) {
            # SPEC v5 item 2 asks for the paths actually searched. "not found" on
            # its own cost a whole sandbox run to interpret.
            $all = @($env:PATH -split ';' | Where-Object { $_.Trim() })
            $likely = @($all | Where-Object { $_ -match 'WinGet|mise|WindowsApps|mingw' })
            throw ("not found; searched {0} PATH entries; likely dirs: {1}" -f `
                $all.Count, (($likely | Select-Object -First 6) -join ' '))
        }
        $c.Source
    }
}

# ---------------------------------------------------------------- files
Check 'managed pwsh profile exists' {
    $p = Join-Path $HOME '.config\powershell\profile.ps1'
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
    (Get-Item $p).Length.ToString() + ' bytes'
}

Check 'real $PROFILE has exactly one loader line' {
    $target = (& pwsh -NoProfile -NoLogo -Command '$PROFILE.CurrentUserAllHosts') | Select-Object -First 1
    if (-not (Test-Path -LiteralPath $target)) { throw "missing $target" }
    $n = @(Get-Content -LiteralPath $target -ErrorAction Stop | Where-Object { $_ -match 'config/powershell/profile\.ps1' }).Count
    if ($n -ne 1) { throw "loader line count = $n in $target" }
    $target
}

Check 'oh-my-posh theme downloaded' {
    $p = Join-Path $HOME '.config\oh-my-posh\powerlevel10k_rainbow.omp.json'
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
    (Get-FileHash -Path $p -Algorithm SHA256).Hash.ToLower()
}

Check 'cc-statusline.exe downloaded' {
    $p = Join-Path $HOME '.claude\cc-statusline\cc-statusline.exe'
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
    (Get-Item $p).Length.ToString() + ' bytes'
}

Check 'settings.json points at cc-statusline.exe' {
    $p = Join-Path $HOME '.claude\settings.json'
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
    $j = Get-Content -Raw -LiteralPath $p -ErrorAction Stop | ConvertFrom-Json
    if ($j.statusLine.command -notlike '*cc-statusline.exe') { throw $j.statusLine.command }
    $j.statusLine.command
}

Check 'codex config.toml has the managed [tui] keys' {
    $p = Join-Path $HOME '.codex\config.toml'
    # Without this guard the check reports PASS for a file that is not there.
    # $ErrorActionPreference is 'Continue', so a missing file leaves $c as $null,
    # and PowerShell's $null -match and $null -notmatch BOTH return $false --
    # so neither `throw` fires. The first real L9 run passed this check while
    # the apply had aborted before writing a single file.
    if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
    $c = Get-Content -Raw -LiteralPath $p -ErrorAction Stop
    if ($c -notmatch '(?m)^status_line_use_colors = true$') { throw 'status_line_use_colors missing' }
    if ($c -notmatch '(?m)^status_line = \[') { throw 'status_line missing' }
    'ok'
}

Check 'nvim config is the LazyVim starter with our marker' {
    $cfg = Join-Path $env:LOCALAPPDATA 'nvim'
    if (-not (Test-Path (Join-Path $cfg 'init.lua'))) { throw 'no init.lua' }
    if (-not (Test-Path (Join-Path $cfg '.chezmoi-lazyvim-starter'))) { throw 'no marker' }
    if (Test-Path (Join-Path $cfg '.git')) { throw '.git was not removed' }
    if (-not (Test-Path (Join-Path $cfg 'lua\plugins\completion.lua'))) { throw 'our override is missing' }
    $cfg
}

Check 'zsh-only files did NOT land' {
    foreach ($n in @('.zshrc', '.zprofile', '.p10k.zsh', '.oh-my-zsh')) {
        if (Test-Path -LiteralPath (Join-Path $HOME $n)) { throw "$n should not exist on Windows" }
    }
    'ok'
}

# Expected to fail on a stock sandbox: Developer Mode is off, so chezmoi cannot
# create the ~/.claude/skills symlinks. Recorded either way -- this is the check
# that tells us whether init.ps1's warning fires for a real reason.
Check 'claude skills symlinks' {
    $p = Join-Path $HOME '.claude\skills\commit-message'
    if (-not (Test-Path -LiteralPath $p)) { throw 'missing (expected without Developer Mode)' }
    'present'
}

# ---------------------------------------------------------------- M12
# The open question from the spec: can nvim-treesitter actually build a parser
# on Windows with zig as the C compiler? This is the only place it can be
# answered. Bounded, and a failure here is a finding, not a crash.
Write-Host ''
Write-Host 'probe: running nvim Lazy! sync + TSInstall lua (SPEC M12)'
Write-Host 'probe: this usually takes 5-15 minutes and is capped at 15; progress is reported every 30s'
Check 'nvim-treesitter builds a parser (SPEC M12)' {
    $job = Start-Job -ScriptBlock {
        & nvim --headless '+Lazy! sync' '+qa' 2>&1 | Out-String
        & nvim --headless '+TSInstall! lua' '+qa' 2>&1 | Out-String
    }
    # A job's output only arrives when it finishes, so this step cannot stream.
    # A heartbeat is the next best thing: without it this is 15 minutes of silence
    # and the operator cannot tell it from a hang. The timeout and the verdict
    # below are unchanged.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (($job.State -eq 'Running') -and ($sw.Elapsed.TotalSeconds -lt 900)) {
        Start-Sleep -Seconds 30
        Write-Host ("probe: still building the treesitter parser, {0:n0}s elapsed" -f $sw.Elapsed.TotalSeconds)
    }
    if (-not (Wait-Job $job -Timeout 1)) {
        Stop-Job $job; throw 'timed out after 15 minutes'
    }
    Receive-Job $job | Out-File $treesitterLog
    $parser = Join-Path $env:LOCALAPPDATA 'nvim-data\site\parser\lua.so'
    $parser2 = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy\nvim-treesitter\parser\lua.so'
    if ((Test-Path $parser) -or (Test-Path $parser2)) { return 'lua parser built' }
    throw "no lua parser produced -- see $treesitterLog"
}

# ---------------------------------------------------------------- report
$summary = "PASS={0} FAIL={1}" -f `
    (@($results | Where-Object { $_ -like 'PASS*' }).Count), `
    (@($results | Where-Object { $_ -like 'FAIL*' }).Count)
[void]$results.Add("SUMMARY`t$summary`t")
$results | Out-File -FilePath $resultsPath -Encoding utf8
Write-Host ''
Write-Host "probe: $summary"
Write-Host "probe: results in $resultsPath, transcript in $transcriptPath"

# Closing the sandbox destroys the files. Echo the whole table so the console --
# which the operator can still scroll and copy -- carries the same information.
# treesitter.log is the only record of what nvim actually did, and in remote mode
# it dies with the sandbox. Tail rather than full: a Lazy sync can run to
# thousands of lines and would push the results table out of the console buffer,
# which is the one thing that must stay readable.
if (Test-Path -LiteralPath $treesitterLog) {
    Write-Host ''
    Write-Host '--- treesitter.log (tail 200) ---'
    foreach ($line in (Get-Content -LiteralPath $treesitterLog -Tail 200 -ErrorAction Stop)) {
        Write-Host $line
    }
    Write-Host '--- end treesitter.log ---'
}

Write-Host ''
Write-Host '--- results.tsv (full) ---'
foreach ($line in $results) { Write-Host $line }
Write-Host '--- end results.tsv ---'
Stop-Transcript | Out-Null
