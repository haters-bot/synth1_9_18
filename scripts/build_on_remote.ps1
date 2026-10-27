[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteHost,
    [Parameter(Mandatory = $true)]
    [string]$RemoteUser,
    [string]$RemoteProjectRoot = "D:\FPGA\synth1_9_18",
    [string]$RemoteShare,
    [string]$Branch = "main",
    [ValidateSet("Signoff", "Fast", "Incremental")]
    [string]$BuildProfile = "Signoff"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
if (-not $RemoteShare) {
    $RemoteShare = "\\$RemoteHost\FPGA_Builds"
}

function Invoke-LocalGit {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    # Git reports normal fetch/push progress on stderr. Under Windows
    # PowerShell 5.1, redirected native stderr becomes ErrorRecord objects.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $result = & git -C $projectRoot @Arguments 2>&1
        $gitExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $result = @($result | ForEach-Object { $_.ToString() })
    if ($gitExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($result -join [Environment]::NewLine)"
    }
    return $result
}

$dirtyState = @(Invoke-LocalGit status --porcelain=v1)
if ($dirtyState.Count -gt 0) {
    throw "The local repository is not clean. Review and commit the intended source changes before starting a remote build.`n$($dirtyState -join [Environment]::NewLine)"
}

$currentBranch = (Invoke-LocalGit branch --show-current | Select-Object -First 1).Trim()
if ($currentBranch -ne $Branch) {
    throw "Current branch is '$currentBranch', expected '$Branch'."
}

$localCommit = (Invoke-LocalGit rev-parse HEAD | Select-Object -First 1).Trim()
Write-Host "[1/3] Pushing commit $($localCommit.Substring(0, 12)) ..."
Invoke-LocalGit push origin "HEAD:$Branch" | ForEach-Object { Write-Host $_ }

$escapedProjectRoot = $RemoteProjectRoot.Replace("'", "''")
$remotePowerShell = @"
Set-Location -LiteralPath '$escapedProjectRoot'
# Update before invoking the build script. If remote_build.ps1 itself changed,
# PowerShell must load the new file rather than continue an already parsed copy.
git fetch origin '$Branch'
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
git pull --ff-only origin '$Branch'
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
& .\scripts\remote_build.ps1 -Branch '$Branch' -BuildProfile '$BuildProfile' -SkipPull
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remotePowerShell))

Write-Host "[2/3] Starting build on $RemoteHost ..."
& ssh "$RemoteUser@$RemoteHost" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
if ($LASTEXITCODE -ne 0) {
    throw "Remote build failed with SSH exit code $LASTEXITCODE."
}

$latestPath = Join-Path $RemoteShare "latest.json"
if (-not (Test-Path -LiteralPath $latestPath -PathType Leaf)) {
    throw "Remote build completed, but latest.json is not accessible at $latestPath"
}

$latest = Get-Content -LiteralPath $latestPath -Raw | ConvertFrom-Json
if ($latest.commit -ne $localCommit) {
    throw "Remote artifact commit $($latest.commit) does not match local commit $localCommit."
}

Write-Host "[3/3] Fetching the verified build package ..."
& (Join-Path $scriptRoot "fetch_remote_build.ps1") -RemoteShare $RemoteShare

