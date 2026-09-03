<#
    End-to-end check inside Windows Sandbox (test layer L9).

    The sandbox is the only place a real install is allowed to run: the host is
    off limits (see specs/windows-support/SPEC.md, Must NOT #1). Everything
    here runs against a throwaway machine.

    Launched by chezmoi-sandbox\sandbox.wsb as the LogonCommand, under Windows
    PowerShell 5.1 (the sandbox base image has no pwsh). ASCII only, for the
    same reason init.ps1 is: 5.1 decodes a BOM-less .ps1 with the ANSI code page
    and mangles anything else. See docs/research/windows-native-support.md 8.

    Inputs   C:\src        read-only, prepared by tests/sandbox/prepare.sh
    Outputs  C:\out        writable: transcript.txt and results.tsv

    Nothing here is part of the installed dotfiles. In particular the winget
    bootstrap below exists only because the sandbox base image ships without
    App Installer; a real Windows 11 machine already has winget.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Force -Path 'C:\out' | Out-Null
Start-Transcript -Path 'C:\out\transcript.txt' -Force | Out-Null

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

function Update-ProbePath {
    $dirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:LOCALAPPDATA 'mise\shims'),
        (Join-Path $env:ProgramFiles 'PowerShell\7'),
        (Join-Path $env:ProgramFiles 'Git\cmd')
    )
    foreach ($d in $dirs) {
        if ((Test-Path -LiteralPath $d) -and (($env:PATH -split ';') -notcontains $d)) {
            $env:PATH = "$d;$env:PATH"
        }
    }
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
# Run the repo's own bootstrap, exactly as a user would, but against the local
# source tree instead of GitHub (the branch under test is not pushed).
$repo = 'C:\src\dotfiles'
Check 'source tree is present' {
    if (-not (Test-Path (Join-Path $repo '.chezmoiscripts'))) { throw "missing $repo" }
    'ok'
}

Check 'init.ps1 installs pwsh 7, git and chezmoi' {
    # Reuse init.ps1's package list without its `chezmoi init <github user>` tail,
    # so the sandbox installs from C:\src rather than from the remote.
    foreach ($id in @('Microsoft.PowerShell', 'Git.Git', 'twpayne.chezmoi')) {
        Update-ProbePath
        $cmd = @{ 'Microsoft.PowerShell' = 'pwsh'; 'Git.Git' = 'git'; 'twpayne.chezmoi' = 'chezmoi' }[$id]
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { continue }
        winget install --exact --id $id --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { throw "winget install $id -> $LASTEXITCODE" }
    }
    Update-ProbePath
    'installed'
}

Check 'chezmoi init --apply completes' {
    Update-ProbePath
    # --source points at the read-only mapped folder; chezmoi writes only to
    # the destination and to its own state under %LOCALAPPDATA%.
    & chezmoi init --apply --source $repo 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "chezmoi init --apply -> $LASTEXITCODE" }
    'applied'
}

Update-ProbePath

# ---------------------------------------------------------------- tools
foreach ($t in @('mise', 'fzf', 'rg', 'fd', 'lazygit', 'git-lfs', 'tree-sitter', 'oh-my-posh', 'zig', 'nvim')) {
    $name = $t
    Check "tool on PATH: $name" {
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $c) { throw 'not found' }
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
    $n = @(Get-Content -LiteralPath $target | Where-Object { $_ -match 'config/powershell/profile\.ps1' }).Count
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
    $j = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json
    if ($j.statusLine.command -notlike '*cc-statusline.exe') { throw $j.statusLine.command }
    $j.statusLine.command
}

Check 'codex config.toml has the managed [tui] keys' {
    $p = Join-Path $HOME '.codex\config.toml'
    $c = Get-Content -Raw -LiteralPath $p
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
Check 'nvim-treesitter builds a parser (SPEC M12)' {
    $job = Start-Job -ScriptBlock {
        & nvim --headless '+Lazy! sync' '+qa' 2>&1 | Out-String
        & nvim --headless '+TSInstall! lua' '+qa' 2>&1 | Out-String
    }
    if (-not (Wait-Job $job -Timeout 900)) {
        Stop-Job $job; throw 'timed out after 15 minutes'
    }
    Receive-Job $job | Out-File 'C:\out\treesitter.log'
    $parser = Join-Path $env:LOCALAPPDATA 'nvim-data\site\parser\lua.so'
    $parser2 = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy\nvim-treesitter\parser\lua.so'
    if ((Test-Path $parser) -or (Test-Path $parser2)) { return 'lua parser built' }
    throw 'no lua parser produced -- see C:\out\treesitter.log'
}

# ---------------------------------------------------------------- report
$summary = "PASS={0} FAIL={1}" -f `
    (@($results | Where-Object { $_ -like 'PASS*' }).Count), `
    (@($results | Where-Object { $_ -like 'FAIL*' }).Count)
[void]$results.Add("SUMMARY`t$summary`t")
$results | Out-File -FilePath 'C:\out\results.tsv' -Encoding utf8
Write-Host ''
Write-Host "probe: $summary"
Write-Host 'probe: results in C:\out\results.tsv, transcript in C:\out\transcript.txt'
Stop-Transcript | Out-Null
