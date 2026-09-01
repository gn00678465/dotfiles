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

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected Actual: $Actual"
    }
}

function Render-WindowsTemplate {
    param([Parameter(Mandatory)] [string]$Path)

    $overrideDataPath = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-support-" + [guid]::NewGuid() + ".json")
    try {
        [System.IO.File]::WriteAllText($overrideDataPath, '{"chezmoi":{"os":"windows","arch":"amd64"}}')
        return (& chezmoi execute-template --override-data-file $overrideDataPath --file $Path | Out-String).TrimEnd("`r", "`n")
    } finally {
        if (Test-Path -LiteralPath $overrideDataPath) {
            Remove-Item -LiteralPath $overrideDataPath -Force
        }
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

function Test-WingetPrerequisiteFailureIsVisible {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_10-install-packages.ps1.tmpl"
    $rendered = Render-WindowsTemplate -Path $scriptPath
    $script:wingetPreflightInvoked = $false
    $failure = $null

    function Get-Command {
        return $null
    }

    function winget {
        $script:wingetPreflightInvoked = $true
        throw "test: package invocation reached"
    }

    try {
        & ([scriptblock]::Create($rendered))
    } catch {
        $failure = $_
    }

    if ($null -eq $failure) {
        throw "Missing winget must stop the package script."
    }
    Assert-Contains -Actual $failure.Exception.Message -Expected "App Installer" -Message "Missing winget must name the recovery prerequisite."
    Assert-Contains -Actual $failure.Exception.Message -Expected "run chezmoi apply again" -Message "Missing winget must tell the user how to retry."
    Assert-Equal -Actual $script:wingetPreflightInvoked -Expected $false -Message "Missing winget must not invoke package installation."
}

function Test-WindowsPowerShell51BootstrapCompatibility {
    if ($PSVersionTable.PSEdition -ne "Desktop" -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw "This test must run in Windows PowerShell Desktop 5.1."
    }

    Test-WingetPrerequisiteFailureIsVisible
}

function Test-ElevationFailureStopsApply {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_10-install-packages.ps1.tmpl"
    $content = [System.IO.File]::ReadAllText($scriptPath)

    Assert-Contains -Actual $content -Expected '$null -eq $process -or $process.ExitCode -ne 0' -Message "Cancelled or failed elevation must be observable."
    Assert-Contains -Actual $content -Expected 'throw "chezmoi: elevated WinGet install failed or was cancelled for $Id"' -Message "Elevation failure must stop chezmoi."
}

function Test-PwshProfileManagedBlockPreservesUserContent {
    $templatePath = Join-Path $Repository ".chezmoiscripts/run_onchange_after_45-powershell-profile.ps1.tmpl"
    $testHome = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-support-" + [guid]::NewGuid())
    $profilePath = Join-Path $testHome "Documents/PowerShell/Profile.ps1"
    $beginMarker = "# >>> chezmoi oh-my-posh >>>"
    $endMarker = "# <<< chezmoi oh-my-posh <<<"

    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
        [System.IO.File]::WriteAllText($profilePath, "Write-Host 'user content'`n")
        $rendered = Render-WindowsTemplate -Path $templatePath
        $script = $rendered.Replace('$HOME', '$testHome')

        & ([scriptblock]::Create($script))
        $first = [System.IO.File]::ReadAllText($profilePath)
        & ([scriptblock]::Create($script))
        $second = [System.IO.File]::ReadAllText($profilePath)

        Assert-Contains -Actual $first -Expected "Write-Host 'user content'" -Message "Profile modifier must retain user content."
        Assert-Contains -Actual $first -Expected "oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression" -Message "Profile must use the selected strict theme init."
        Assert-Equal -Actual ([regex]::Matches($first, [regex]::Escape($beginMarker)).Count) -Expected 1 -Message "Profile must contain one begin marker."
        Assert-Equal -Actual ([regex]::Matches($first, [regex]::Escape($endMarker)).Count) -Expected 1 -Message "Profile must contain one end marker."
        Assert-Equal -Actual $second -Expected $first -Message "Profile modifier must converge on a second run."
    } finally {
        if (Test-Path -LiteralPath $testHome) {
            Remove-Item -LiteralPath $testHome -Recurse -Force
        }
    }
}

function Test-ProfilePolicyFailureIsVisible {
    $templatePath = Join-Path $Repository ".chezmoiscripts/run_onchange_after_45-powershell-profile.ps1.tmpl"
    $rendered = Render-WindowsTemplate -Path $templatePath

    if ($rendered.Contains("Set-ExecutionPolicy")) {
        throw "Profile bootstrap must not weaken execution policy."
    }
    Assert-Contains -Actual $rendered -Expected '$ErrorActionPreference = "Stop"' -Message "Profile write failures must be visible."
}

function Test-GitLfsRunsAfterTargetsApplied {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_after_40-git-lfs.ps1.tmpl"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Windows Git LFS script is missing: $scriptPath"
    }

    $content = Render-WindowsTemplate -Path $scriptPath
    Assert-Contains -Actual $content -Expected "git lfs install --skip-repo" -Message "Git LFS must avoid mutating the current repository."
}

function Test-FirstBootstrapPreservesUniquePaths {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Windows Nvim bootstrap script is missing: $scriptPath"
    }

    $content = Render-WindowsTemplate -Path $scriptPath
    foreach ($required in @(
        "NVIM_APPNAME",
        "LOCALAPPDATA",
        ".chezmoi-lazyvim-starter",
        "nvim-data",
        "nvim --clean --headless",
        "git clone --depth 1 https://github.com/LazyVim/starter",
        'Remove-Item -LiteralPath (Join-Path $configPath ''.git'') -Recurse -Force',
        'Move-Item -LiteralPath $Path -Destination $destination'
    )) {
        Assert-Contains -Actual $content -Expected $required -Message "Nvim first-bootstrap safety contract is incomplete."
    }
}

function Test-MarkerPreventsRebootstrap {
    $scriptPath = Join-Path $Repository ".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl"
    $content = Render-WindowsTemplate -Path $scriptPath

    Assert-Contains -Actual $content -Expected 'if (-not (Test-Path -LiteralPath $markerPath))' -Message "Marker must be the rerun boundary."
    Assert-Contains -Actual $content -Expected 'Move-Item -LiteralPath $Path -Destination $destination' -Message "Moves must occur only inside the marker guard."
}

foreach ($name in $Test) {
    & $name
    Write-Host "PASS $name"
}
