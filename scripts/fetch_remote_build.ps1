[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteShare,
    [string]$DestinationRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $DestinationRoot) {
    $DestinationRoot = Join-Path (Split-Path -Parent $scriptRoot) "build_results"
}

if (-not (Test-Path -LiteralPath $RemoteShare -PathType Container)) {
    throw "Remote build share is not accessible: $RemoteShare"
}

$latestPath = Join-Path $RemoteShare "latest.json"
if (-not (Test-Path -LiteralPath $latestPath -PathType Leaf)) {
    throw "latest.json was not found in $RemoteShare"
}

$latest = Get-Content -LiteralPath $latestPath -Raw | ConvertFrom-Json
$remoteArchive = Join-Path $RemoteShare $latest.archive_name
if (-not (Test-Path -LiteralPath $remoteArchive -PathType Leaf)) {
    throw "Build archive was not found: $remoteArchive"
}

New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
$localArchive = Join-Path $DestinationRoot $latest.archive_name
$extractDirectory = Join-Path $DestinationRoot $latest.artifact_name

Write-Host "[1/2] Copying $($latest.archive_name) ..."
Copy-Item -LiteralPath $remoteArchive -Destination $localArchive -Force

if (Test-Path -LiteralPath $extractDirectory) {
    Write-Host "[2/2] Build package was already extracted. Verifying existing files ..."
} else {
    Write-Host "[2/2] Extracting build package ..."
    Expand-Archive -LiteralPath $localArchive -DestinationPath $extractDirectory
}

$metadataPath = Join-Path $extractDirectory "build_metadata.json"
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "The copied package does not contain build_metadata.json"
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$bitstreamPath = Join-Path $extractDirectory ($metadata.bitstream_file -replace "/", "\")
if (-not (Test-Path -LiteralPath $bitstreamPath -PathType Leaf)) {
    throw "The copied package does not contain its declared bitstream: $bitstreamPath"
}

Write-Host "Remote build received:"
Write-Host "  Commit: $($metadata.short_commit)"
Write-Host "  Host: $($metadata.host)"
Write-Host "  Duration: $($metadata.duration_seconds) s"
Write-Host "  Bitstream: $bitstreamPath"

