<#
.SYNOPSIS
    Windows bootstrap for these dotfiles. The counterpart of init.sh.

.DESCRIPTION
    Installs only what has to exist before chezmoi can run itself: PowerShell 7,
    Git and chezmoi, via winget. Everything else is installed by chezmoi's own
    .chezmoiscripts -- do not add tools here.

    This script must run on a clean machine that only has Windows PowerShell 5.1,
    so it uses no pwsh-7-only syntax. Its single prerequisite is winget, which
    ships with the App Installer on Windows 11.

    Deliberately ASCII-only, comments included. Windows PowerShell 5.1 decodes a
    .ps1 without a BOM using the ANSI code page, so non-ASCII bytes in this file
    would be mangled -- and a mangled comment is a parse error, not just ugly
    output. Adding a BOM is the other fix, but a BOM breaks the
    `irm ... | iex` form below. Staying ASCII avoids both problems. Comments in
    the rest of this repo are not under that constraint.

.EXAMPLE
    irm https://raw.githubusercontent.com/gn00678465/dotfiles/main/init.ps1 | iex

.EXAMPLE
    Install a specific branch (for testing). Use the same branch name in the URL
    and in -Branch, so the script that runs is that branch's own init.ps1:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/gn00678465/dotfiles/<branch>/init.ps1))) -Branch <branch>

.NOTES
    Re-running this on a machine that already has the dotfiles does not re-clone,
    and -Branch is ignored. To switch branch there: chezmoi cd, git checkout
    <branch>, exit, chezmoi apply. Same behaviour as init.sh.
#>
param(
    [Alias('Ref')]
    [string] $Branch
)

$ErrorActionPreference = 'Stop'

# Same problem as .chezmoitemplates/windows-path.ps1, solved twice: this script
# is not rendered by chezmoi, so it cannot include that template. Keep the two in
# sync when either changes.
#
# Whatever winget just installed is not on this process's PATH -- on Windows the
# PATH is a snapshot taken when the process started -- so refresh after each one.
function Update-BootstrapPath {
    $dirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:ProgramFiles 'PowerShell\7'),
        (Join-Path $env:ProgramFiles 'Git\cmd')
    )
    foreach ($dir in $dirs) {
        if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

function Install-IfMissing {
    param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Command
    )

    Update-BootstrapPath
    if (Get-Command $Command -ErrorAction SilentlyContinue) { return }

    Write-Host "init: winget install $Id"
    # --source winget pins the source to the community repo, so a package that
    # also exists in msstore does not stop on a "which source?" prompt.
    winget install --exact --id $Id --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "init: winget install $Id failed with exit code $LASTEXITCODE"
    }
    Update-BootstrapPath
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw @'
init: winget not found. It ships with the App Installer on Windows 11. Install
App Installer from the Microsoft Store (or see
https://learn.microsoft.com/windows/package-manager/winget/) and re-run this.
'@
}

# pwsh 7 is not only the user's shell: it is also the interpreter chezmoi uses
# for .ps1 scripts (chezmoi's default for the ps1 extension is
# `pwsh -NoLogo -File`), so it has to exist before the first apply.
Install-IfMissing -Id 'Microsoft.PowerShell' -Command 'pwsh'
Install-IfMissing -Id 'Git.Git'              -Command 'git'
Install-IfMissing -Id 'twpayne.chezmoi'      -Command 'chezmoi'

# chezmoi creates symlinks under ~/.claude/skills. Creating a symlink on Windows
# needs SeCreateSymbolicLinkPrivilege, which a normal account only has with
# Developer Mode on. Probe for it now, so the user learns the reason here rather
# than from a failing apply.
$symlinkOk = $false
$probe = Join-Path $env:TEMP ('chezmoi-symlink-probe-' + [guid]::NewGuid().ToString())
try {
    New-Item -ItemType SymbolicLink -Path $probe -Target $env:TEMP -ErrorAction Stop | Out-Null
    $symlinkOk = $true
} catch {
    $symlinkOk = $false
}
if (Test-Path -LiteralPath $probe) {
    try { (Get-Item -LiteralPath $probe -Force).Delete() } catch { }
}
if (-not $symlinkOk) {
    Write-Warning @'
init: this account cannot create symlinks, so chezmoi apply will fail on the
~/.claude/skills links. Turn on Settings > System > For developers > Developer
Mode and re-run, or run this as Administrator.
'@
}

$chezmoiArgs = @('init', '--apply')
if ($Branch) { $chezmoiArgs += @('--branch', $Branch) }
$chezmoiArgs += 'gn00678465'

Write-Host "init: chezmoi $($chezmoiArgs -join ' ')"
& chezmoi @chezmoiArgs
if ($LASTEXITCODE -ne 0) {
    throw "init: chezmoi init --apply failed with exit code $LASTEXITCODE"
}
