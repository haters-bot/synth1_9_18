[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$ProjectFile = "synth1_9_18.gprj",
    [string]$Branch = "main",
    [string]$OutputRoot = "D:\FPGA\build_output",
    [string]$GowinSh = $env:GOWIN_SH,
    [ValidateSet("Signoff", "Fast", "Incremental")]
    [string]$BuildProfile = "Signoff",
    [switch]$SkipPull,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent $scriptRoot
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    # Windows PowerShell 5.1 turns native stderr redirected with 2>&1 into
    # ErrorRecord objects. Git writes normal progress messages to stderr, so
    # temporarily keep those records non-terminating and judge by the exit code.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $result = & git -C $ProjectRoot @Arguments 2>&1
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

function Resolve-GowinShell {
    param([string]$RequestedPath)

    $candidates = @()
    if ($RequestedPath) {
        $candidates += $RequestedPath
    }

    $command = Get-Command gw_sh.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }

    $candidates += @(
        "C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe",
        "D:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe",
        "E:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe"
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "gw_sh.exe was not found. Pass -GowinSh or set the GOWIN_SH environment variable."
}

function Copy-FilesByPattern {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDirectory,
        [string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    foreach ($pattern in $Patterns) {
        Get-ChildItem -LiteralPath $SourceDirectory -Filter $pattern -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $DestinationDirectory -Force
            }
    }
}

$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectPath = Join-Path $ProjectRoot $ProjectFile
if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "Project file not found: $projectPath"
}

Invoke-Git rev-parse --is-inside-work-tree | Out-Null
$dirtyState = @(Invoke-Git status --porcelain=v1)
if (($dirtyState.Count -gt 0) -and (-not $AllowDirty)) {
    throw "The repository is not clean. Commit, stash, or remove local changes before a reproducible build.`n$($dirtyState -join [Environment]::NewLine)"
}

if (-not $SkipPull) {
    Write-Host "[1/4] Updating origin/$Branch ..."
    Invoke-Git fetch origin $Branch | ForEach-Object { Write-Host $_ }
    Invoke-Git pull --ff-only origin $Branch | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "[1/4] Source update skipped."
}

$dirtyState = @(Invoke-Git status --porcelain=v1)
if (($dirtyState.Count -gt 0) -and (-not $AllowDirty)) {
    throw "The repository became dirty after synchronization.`n$($dirtyState -join [Environment]::NewLine)"
}

$commit = (Invoke-Git rev-parse --short=12 HEAD | Select-Object -First 1).Trim()
$fullCommit = (Invoke-Git rev-parse HEAD | Select-Object -First 1).Trim()
$currentBranch = (Invoke-Git branch --show-current | Select-Object -First 1).Trim()
$gowinShell = Resolve-GowinShell -RequestedPath $GowinSh

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$artifactName = "synth1_${commit}_${stamp}"
$artifactDirectory = Join-Path $OutputRoot $artifactName
$consoleLog = Join-Path $artifactDirectory "gowin_console.log"
$tclPath = Join-Path $env:TEMP "gowin_build_$PID.tcl"
$buildStarted = Get-Date

New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$tclProjectPath = $projectPath.Replace("\", "/")
$tclCommands = @(
    "open_project {$tclProjectPath}"
    # impl/ is intentionally not versioned, so make the required HDL dialect
    # explicit for clean clones and remote build machines.
    "set_option -verilog_std sysv2017"
    # R19/U21 are multiplexed CPU/SSPI package pins. Release both dedicated
    # functions so the visualization I2S outputs can use them as GPIO.
    "set_option -use_cpu_as_gpio 1"
    "set_option -use_sspi_as_gpio 1"
    "set_option -top_module top"
    # Keep timing-driven routing enabled in every profile. Fast only reduces
    # search effort; it does not turn timing checks into a functional build.
    "set_option -timing_driven 1"
    "set_option -correct_hold_violation 1"
)

switch ($BuildProfile) {
    "Signoff" {
        $tclCommands += @(
            "set_option -place_option 3"
            "set_option -route_option 2"
            "set_option -inc_place 0"
            "set_option -inc_pnr 0"
        )
    }
    "Fast" {
        $tclCommands += @(
            "set_option -place_option 0"
            "set_option -route_option 0"
            "set_option -inc_place 0"
            "set_option -inc_pnr 0"
        )
    }
    "Incremental" {
        $tclCommands += @(
            "set_option -place_option 3"
            "set_option -route_option 2"
            "set_option -inc_pnr auto"
        )
    }
}

$tclCommands += @(
    "run all"
    "run close"
    "exit"
)
$tclCommands | Set-Content -LiteralPath $tclPath -Encoding ASCII

Write-Host "[2/4] Building commit $commit with $gowinShell ..."
Write-Host "      Build profile: $BuildProfile"
try {
    Push-Location $ProjectRoot
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $gowinShell $tclPath 2>&1 | Tee-Object -FilePath $consoleLog
            $gowinExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $tclPath -Force -ErrorAction SilentlyContinue
}

if ($gowinExitCode -ne 0) {
    throw "Gowin exited with code $gowinExitCode. See $consoleLog"
}

$pnrDirectory = Join-Path $ProjectRoot "impl\pnr"
$synthesisDirectory = Join-Path $ProjectRoot "impl\gwsynthesis"
$bitstream = Get-ChildItem -LiteralPath $pnrDirectory -Filter *.fs -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $buildStarted.AddSeconds(-5) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $bitstream) {
    throw "No new .fs file was produced after $($buildStarted.ToString('s')). See $consoleLog"
}

Write-Host "[3/4] Collecting bitstream and reports ..."
Copy-FilesByPattern -SourceDirectory $pnrDirectory -DestinationDirectory (Join-Path $artifactDirectory "pnr") -Patterns @(
    "*.fs", "*.bin", "*.log", "*.html", "*.rpt"
)
Copy-FilesByPattern -SourceDirectory $synthesisDirectory -DestinationDirectory (Join-Path $artifactDirectory "synthesis") -Patterns @(
    "*.log", "*.html", "*.rpt"
)

$buildFinished = Get-Date
$metadata = [ordered]@{
    project             = "synth1_9_18"
    branch              = $currentBranch
    commit              = $fullCommit
    short_commit        = $commit
    host                = $env:COMPUTERNAME
    gowin_shell         = $gowinShell
    build_started       = $buildStarted.ToString("o")
    build_finished      = $buildFinished.ToString("o")
    duration_seconds    = [math]::Round(($buildFinished - $buildStarted).TotalSeconds, 1)
    build_profile       = $BuildProfile
    bitstream_file      = "pnr/$($bitstream.Name)"
    artifact_name       = $artifactName
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $artifactDirectory "build_metadata.json") -Encoding UTF8

$archivePath = Join-Path $OutputRoot "$artifactName.zip"
Compress-Archive -Path (Join-Path $artifactDirectory "*") -DestinationPath $archivePath -CompressionLevel Optimal -Force

$latest = [ordered]@{
    artifact_name = $artifactName
    archive_name  = [IO.Path]::GetFileName($archivePath)
    commit        = $fullCommit
    short_commit  = $commit
    created       = $buildFinished.ToString("o")
    build_profile = $BuildProfile
}
$latest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputRoot "latest.json") -Encoding UTF8

Write-Host "[4/4] Build package ready:"
Write-Host "  $archivePath"
Write-Host "  Commit: $commit"
Write-Host "  Duration: $($metadata.duration_seconds) s"

