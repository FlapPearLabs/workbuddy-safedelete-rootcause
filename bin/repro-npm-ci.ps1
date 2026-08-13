# repro-npm-ci.ps1
# Deterministic npm ci A/B repro.
# Phase 1: clear all WorkBuddy env vars. Run npm ci. Capture full state.
# Phase 2: set WorkBuddy shim env. Run npm ci. Capture full state and error markers.
#   (The shim only affects Node processes; npm itself spawns Node workers that
#   inherit the env, so npm's own child fs.rmSync calls are intercepted.)
# Phase 3: capture before/after file manifest diff to prove partial-mutation ordering.
#
# Usage:
#   .\repro-npm-ci.ps1 -Probe <path> -WorkbuddyInstall <path> -OutputFile <path>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Probe,
    [Parameter(Mandatory=$true)][string]$WorkbuddyInstall,
    [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

if (Test-Path $OutputFile) { mavis-trash $OutputFile }
# Resolve to absolute path so the relative path doesn't shift when this
# script's CWD changes (Push-Location $Probe later in the script).
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null
"" | Set-Content $OutputFile -Encoding UTF8

function Record([string]$Line) {
    Write-Output $Line
    Add-Content $OutputFile $Line -Encoding UTF8
}

if (-not (Test-Path (Join-Path $Probe 'package.json'))) {
    throw "probe not initialized: $Probe/package.json missing"
}
if (-not (Test-Path (Join-Path $Probe 'package-lock.json'))) {
    throw "probe not initialized: $Probe/package-lock.json missing"
}

$probeNodeModules = Join-Path $Probe 'node_modules'
if (Test-Path $probeNodeModules) { mavis-trash $probeNodeModules }

Record ("NPM_CI_PROBE=" + $Probe)
Record ("NPM_CI_WORKBUDDY_INSTALL=" + $WorkbuddyInstall)

# Helper to count files in a directory
function Count-FilesInDir([string]$Dir) {
    if (-not (Test-Path $Dir)) { return 0 }
    return (Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count
}

# ============================================================================
# PHASE 1 — NORMAL (clean env, no shim)
# ============================================================================
Record ""
Record "==== PHASE 1: NORMAL (no WorkBuddy shim) ===="
Assert-CleanWorkbuddyEnv
$env:NPM_CONFIG_LOGLEVEL = 'error'

Record "NPM_CI_PHASE1_ENV_CLEAN=yes"
$before1 = Count-FilesInDir $Probe
Record ("NPM_CI_PHASE1_BEFORE_FILE_COUNT=" + $before1)

Push-Location $Probe
try {
    Record "NPM_CI_PHASE1_INSTALL_CMD=npm install --no-audit --no-fund"
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $phase1InstallOut = & npm.cmd install --no-audit --no-fund 2>&1 | Out-String
    $phase1InstallExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Record ("NPM_CI_PHASE1_INSTALL_EXIT=" + $phase1InstallExit)
    $phase1Manifest = Get-ManifestForDir $probeNodeModules
    Record ("NPM_CI_PHASE1_INSTALL_MANIFEST_FILE_COUNT=" + $phase1Manifest.Count)

    $phase1ManifestPath = Join-Path $Probe '_manifest_phase1.txt'
    $phase1Manifest | ForEach-Object { "$($_.Path)|$($_.Size)|$($_.Sha256)" } | Set-Content $phase1ManifestPath -Encoding UTF8

    Record "NPM_CI_PHASE1_CI_CMD=npm ci --no-audit --no-fund"
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $phase1Out = & npm.cmd ci --no-audit --no-fund 2>&1 | Out-String
    $phase1Exit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Record ("NPM_CI_PHASE1_CI_EXIT=" + $phase1Exit)
    $phase1OutTrim = ($phase1Out.Trim() -split "`n" | Select-Object -First 3) -join ' | '
    Record ("NPM_CI_PHASE1_CI_OUTPUT_HEAD=" + $phase1OutTrim)

    $phase1PostManifest = Get-ManifestForDir $probeNodeModules
    $phase1Diff = Compare-Manifest $phase1Manifest $phase1PostManifest
    Write-ManifestDiff 'PHASE1_DIFF (post-ci vs pre-ci)' $phase1Diff
    Record ("NPM_CI_PHASE1_POST_FILE_COUNT=" + $phase1PostManifest.Count)
    Record ("NPM_CI_PHASE1_CRITICAL_PARSE5=" + (Test-Path (Join-Path $Probe 'node_modules/parse5/dist/index.js')))
    Record ("NPM_CI_PHASE1_CRITICAL_ENTITIES_ESCAPE=" + (Test-Path (Join-Path $Probe 'node_modules/entities/dist/escape.js')))
} finally {
    Pop-Location
}

# ============================================================================
# PHASE 2 — WORKBUDDY SHIM (env vars set, shim active)
# ============================================================================
Record ""
Record "==== PHASE 2: WORKBUDDY SHIM (env + shim active) ===="
$shimAvailable = Assert-WorkbuddyShimAvailable -WbPath $WorkbuddyInstall
if (-not $shimAvailable) {
    Record "NPM_CI_PHASE2_RESULT=SKIPPED_WORKBUDDY_NOT_INSTALLED"
} else {
    $shimReportPath = Join-Path $env:TEMP ("workbuddy-rootcause-control\npm-ci-shim-report-" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".jsonl")
    $shimStateDir = Join-Path $env:TEMP ("workbuddy-rootcause-control\npm-ci-shim-state-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    # Only create the parent dir; the report file itself is written by the shim.
    New-Item -ItemType Directory -Force -Path (Split-Path $shimReportPath) | Out-Null
    New-Item -ItemType Directory -Force -Path $shimStateDir | Out-Null
    # If a stale report file or state dir exists from a prior run, remove it.
    if (Test-Path -PathType Leaf $shimReportPath) { mavis-trash $shimReportPath }
    if (Test-Path $shimStateDir) { mavis-trash $shimStateDir }
    New-Item -ItemType Directory -Force -Path $shimStateDir | Out-Null

    # Reset node_modules to a fresh install state under the shim
    if (Test-Path $probeNodeModules) { mavis-trash $probeNodeModules }
    Assert-CleanWorkbuddyEnv
    Set-WorkbuddyShimEnv -WbPath $WorkbuddyInstall -StateDir $shimStateDir -ReportPath $shimReportPath
    Record "NPM_CI_PHASE2_SHIM_INJECTED=yes"
    $before2 = Count-FilesInDir $Probe
    Record ("NPM_CI_PHASE2_BEFORE_FILE_COUNT=" + $before2)

    Push-Location $Probe
    try {
        Record "NPM_CI_PHASE2_INSTALL_CMD=npm install --no-audit --no-fund"
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $phase2InstallOut = & npm.cmd install --no-audit --no-fund 2>&1 | Out-String
        $phase2InstallExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        Record ("NPM_CI_PHASE2_INSTALL_EXIT=" + $phase2InstallExit)
        $phase2Manifest = Get-ManifestForDir $probeNodeModules
        Record ("NPM_CI_PHASE2_INSTALL_MANIFEST_FILE_COUNT=" + $phase2Manifest.Count)

        $phase2ManifestPath = Join-Path $Probe '_manifest_phase2.txt'
        $phase2Manifest | ForEach-Object { "$($_.Path)|$($_.Size)|$($_.Sha256)" } | Set-Content $phase2ManifestPath -Encoding UTF8

        Record "NPM_CI_PHASE2_CI_CMD=npm ci --no-audit --no-fund"
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $phase2Out = & npm.cmd ci --no-audit --no-fund 2>&1 | Out-String
        $phase2Exit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        Record ("NPM_CI_PHASE2_CI_EXIT=" + $phase2Exit)
        $phase2OutTrim = ($phase2Out.Trim() -split "`n" | Select-Object -First 5) -join ' | '
        Record ("NPM_CI_PHASE2_CI_OUTPUT_HEAD=" + $phase2OutTrim)

        if ($phase2Out -match 'SAFE_DELETE_BULK_CONFIRM_REQUIRED') {
            $marker = ($phase2Out | Select-String -Pattern 'SAFE_DELETE_BULK_CONFIRM_REQUIRED' -SimpleMatch | Select-Object -First 1).ToString()
            Record "NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes"
            Record ("NPM_CI_PHASE2_BULK_GUARD_MARKER=" + $marker)
        } else {
            Record "NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=no"
        }

        $phase2PostManifest = Get-ManifestForDir $probeNodeModules
        $phase2Diff = Compare-Manifest $phase2Manifest $phase2PostManifest
        Write-ManifestDiff 'PHASE2_DIFF (post-ci vs pre-ci)' $phase2Diff
        Record ("NPM_CI_PHASE2_POST_FILE_COUNT=" + $phase2PostManifest.Count)
        Record ("NPM_CI_PHASE2_CRITICAL_PARSE5=" + (Test-Path (Join-Path $Probe 'node_modules/parse5/dist/index.js')))
        Record ("NPM_CI_PHASE2_CRITICAL_ENTITIES_ESCAPE=" + (Test-Path (Join-Path $Probe 'node_modules/entities/dist/escape.js')))

        # Capture the shim trash report. Wait for the npm process to fully exit and
        # the shim to flush its report file before reading.
        $shimReportCopy = Join-Path (Split-Path $OutputFile) ('shim-report-' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.jsonl')
        $captured = $false
        $captureTries = 0
        $captureReason = 'unknown'
        for ($wait = 0; $wait -lt 50; $wait++) {
            $captureTries++
            Start-Sleep -Milliseconds 200
            if (Test-Path $shimReportPath) {
                # Also check that npm process has exited (file not locked)
                $locked = $false
                try {
                    [System.IO.File]::Open($shimReportPath, 'Open', 'Read', 'Read') | Out-Null
                } catch {
                    $locked = $true
                    $captureReason = 'locked: ' + $_.Exception.Message
                }
                if (-not $locked) {
                    try {
                        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                        Copy-Item $shimReportPath $shimReportCopy -Force -ErrorAction Stop
                        $ErrorActionPreference = $prevEAP
                        $captured = $true
                        break
                    } catch {
                        $ErrorActionPreference = $prevEAP
                        $captureReason = 'copy_failed: ' + $_.Exception.Message
                        # file still locked; try again
                    }
                }
            } else {
                $captureReason = 'source_missing'
            }
        }
        Record ("NPM_CI_PHASE2_SHIM_REPORT_TRIES=" + $captureTries)
        Record ("NPM_CI_PHASE2_SHIM_REPORT_REASON=" + $captureReason)
        if ($captured -and (Test-Path $shimReportCopy)) {
            $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            Get-Content $shimReportCopy | ForEach-Object {
                try {
                    $j = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($j) {
                        $line = "NPM_CI_PHASE2_SHIM_TRASH_EVENT " + $j.timestamp + " op=" + $j.operation + " runtime=" + $j.runtime + " path=" + $j.path
                        Record $line
                    } else {
                        Record ("NPM_CI_PHASE2_SHIM_RAW " + $_)
                    }
                } catch {
                    Record ("NPM_CI_PHASE2_SHIM_RAW " + $_)
                }
            }
            $ErrorActionPreference = $prevEAP
        } else {
            Record "NPM_CI_PHASE2_SHIM_REPORT=could_not_capture"
        }
    } finally {
        Pop-Location
        Assert-CleanWorkbuddyEnv
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Record ""
Record "==== SUMMARY ===="
Record "NPM_CI_PHASE1_RESULT=ok-or-fail"
Record "NPM_CI_PHASE2_RESULT=ok-or-blocked"
Record "NPM_CI_END"
