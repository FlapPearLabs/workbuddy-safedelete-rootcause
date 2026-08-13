# repro-all.ps1
# Runs the four minimal reproducers (env probe, Node fs.rm, npm ci, Git) in
# both normal and WorkBuddy-simulated modes and writes results to
# .\report\results-normal.txt and .\report\results-workbuddy.txt.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'
$lab = (Resolve-Path "$PSScriptRoot\..").Path
$report = "$lab\report"
New-Item -ItemType Directory -Path $report -Force | Out-Null

$wb = 'D:\WORKBUDDY'
$shim = Join-Path $wb 'resources\app.asar.unpacked\cli\vendor\shim\genie-safe-delete.cjs'
$guard = Join-Path $wb 'resources\app.asar.unpacked\cli\vendor\shim\safe-delete-bulk-guard.cjs'
$node = (Get-Command node).Source
$stateDir = Join-Path $env:TEMP 'workbuddy-rootcause-control\state-bundle'
$reportJsonl = Join-Path $env:TEMP 'workbuddy-rootcause-control\report-bundle.jsonl'
New-Item -ItemType Directory -Force -Path (Split-Path $reportJsonl) | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Save env-clear helper
function Clear-WorkbuddyEnv {
    foreach ($n in @('CODEBUDDY_SESSION_ID','CODEBUDDY_TOOL_CALL_ID',
                     'CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR',
                     'CODEBUDDY_SAFE_DELETE_BULK_GUARD',
                     'CODEBUDDY_SAFE_DELETE_REPORT_PATH',
                     'CODEBUDDY_NODE_BIN','GENIE_TRASH_DIR',
                     'CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD','NODE_OPTIONS')) {
        if (Test-Path "env:$n") { Remove-Item "env:$n" -ErrorAction SilentlyContinue }
    }
}
function Set-WorkbuddyEnv {
    param([string]$StateDir,[string]$Report,[string]$Guard,[string]$Shim,[string]$Node,[string]$Wb)
    $env:CODEBUDDY_SESSION_ID = 'simulated-bundle-session'
    $env:CODEBUDDY_TOOL_CALL_ID = [guid]::NewGuid().ToString()
    $env:CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR = $StateDir
    $env:CODEBUDDY_SAFE_DELETE_BULK_GUARD = $Guard
    $env:CODEBUDDY_SAFE_DELETE_REPORT_PATH = $Report
    $env:CODEBUDDY_NODE_BIN = $Node
    $env:GENIE_TRASH_DIR = Join-Path $Wb 'resources\app.asar.unpacked\cli\vendor\genie-trash'
    $env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD = '20'
    $env:NODE_OPTIONS = "--require=`"$($Shim -replace '\\','/')`""
}

# Build probe fixtures if missing
$small = "$lab\node-delete-probe\small"
$large = "$lab\node-delete-probe\large"
& "$lab\bin\build-fixture.ps1" $small 5 | Out-Null
& "$lab\bin\build-fixture.ps1" $large 40 | Out-Null

# NORMAL mode
Clear-WorkbuddyEnv
$normalOut = & "$lab\bin\run-bundle.ps1" -Lab $lab -Mode normal
$normalOut | Set-Content "$report\results-normal.txt" -Encoding UTF8

# WORKBUDDY mode
Set-WorkbuddyEnv -StateDir $stateDir -Report $reportJsonl -Guard $guard -Shim $shim -Node $node -Wb $wb
$workbuddyOut = & "$lab\bin\run-bundle.ps1" -Lab $lab -Mode workbuddy
$workbuddyOut | Set-Content "$report\results-workbuddy.txt" -Encoding UTF8

Clear-WorkbuddyEnv

Write-Output "Wrote:"
Write-Output "  $report\results-normal.txt"
Write-Output "  $report\results-workbuddy.txt"
if (Test-Path $reportJsonl) {
    Copy-Item $reportJsonl "$report\report-bundle.jsonl" -Force
    Write-Output "  $report\report-bundle.jsonl"
}
