[CmdletBinding()]
param(
    [string[]]$Test = @("Test-WingetPackageContract")
)

$ErrorActionPreference = "Stop"
$Repository = Split-Path -Parent $PSScriptRoot

function Assert-Contains {
    param(
        [Parameter(Mandatory)] [string]$Actual,
        [Parameter(Mandatory)] [string]$Expected,
        [Parameter(Mandatory)] [string]$Message
    )

    if (-not $Actual.Contains($Expected)) {
        throw "$Message Missing: $Expected"
    }
}

function Test-WingetPackageContract {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_10-install-packages.ps1.tmpl"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Windows package script is missing: $scriptPath"
    }

    $content = [System.IO.File]::ReadAllText($scriptPath)
    foreach ($packageId in @(
        "Microsoft.PowerShell",
        "JanDeDobbeleer.OhMyPosh",
        "jdx.mise",
        "junegunn.fzf",
        "BurntSushi.ripgrep.MSVC",
        "sharkdp.fd",
        "JesseDuffield.lazygit",
        "tree-sitter.tree-sitter-cli",
        "Git.Git",
        "GitHub.GitLFS",
        "Microsoft.VisualStudio.2022.BuildTools",
        "Microsoft.VisualStudio.Workload.VCTools"
    )) {
        Assert-Contains -Actual $content -Expected $packageId -Message "WinGet package contract is incomplete."
    }

    foreach ($flag in @(
        "--id",
        "--exact",
        "--source",
        "winget",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )) {
        Assert-Contains -Actual $content -Expected $flag -Message "WinGet command must remain non-interactive and exact."
    }

    Assert-Contains -Actual $content -Expected "Start-Process" -Message "Machine-scope installs must elevate."
    Assert-Contains -Actual $content -Expected "-Verb RunAs" -Message "Machine-scope installs must request UAC."
    Assert-Contains -Actual $content -Expected "-Wait" -Message "Machine-scope installs must wait for completion."
    Assert-Contains -Actual $content -Expected "-PassThru" -Message "Machine-scope install exit codes must be checked."
}

function Test-ElevationFailureStopsApply {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_10-install-packages.ps1.tmpl"
    $content = [System.IO.File]::ReadAllText($scriptPath)

    Assert-Contains -Actual $content -Expected '$null -eq $process -or $process.ExitCode -ne 0' -Message "Cancelled or failed elevation must be observable."
    Assert-Contains -Actual $content -Expected 'throw "chezmoi: elevated WinGet install failed or was cancelled for $Id"' -Message "Elevation failure must stop chezmoi."
}

foreach ($name in $Test) {
    & $name
    Write-Host "PASS $name"
}
