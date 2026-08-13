# run-as-workbuddy.ps1
# Simulates the env vars WorkBuddy injects into spawned Node/cmd processes,
# then invokes the supplied command.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Continue'

# Sanity check: this wrapper does NOT talk to the real project. It is only
# used to run disposable probe commands under D:\Dev\workbuddy-rootcause-lab
# or %TEMP%\workbuddy-rootcause-control.
$here = (Resolve-Path $PSScriptRoot).Path
$repoRoot = (Resolve-Path "$here\..").Path
$projectBlacklist = 'D:\Dev\zhihu-grabber-toolkit'
$argJoined = ($Command + ' ' + ($Rest -join ' '))
if ($argJoined -match [regex]::Escape($projectBlacklist)) {
    Write-Error "run-as-workbuddy: refusing to run a command that targets the real project ($projectBlacklist)"
    exit 2
}

$stateDir = Join-Path $env:TEMP 'workbuddy-rootcause-control\state'
$report = Join-Path $env:TEMP 'workbuddy-rootcause-control\report.jsonl'
New-Item -ItemType Directory -Force -Path (Split-Path $report) | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$wb = 'D:\WORKBUDDY'
$shim = Join-Path $wb 'resources\app.asar.unpacked\cli\vendor\shim\genie-safe-delete.cjs'
$guard = Join-Path $wb 'resources\app.asar.unpacked\cli\vendor\shim\safe-delete-bulk-guard.cjs'
$node = (Get-Command node).Source

$env:CODEBUDDY_SESSION_ID = 'simulated-workbuddy-session'
$env:CODEBUDDY_TOOL_CALL_ID = [guid]::NewGuid().ToString()
$env:CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR = $stateDir
$env:CODEBUDDY_SAFE_DELETE_BULK_GUARD = $guard
$env:CODEBUDDY_NODE_BIN = $node
$env:CODEBUDDY_SAFE_DELETE_REPORT_PATH = $report
$env:GENIE_TRASH_DIR = Join-Path $wb 'resources\app.asar.unpacked\cli\vendor\genie-trash'
# Use forward slashes to keep backslashes from being eaten by escaping
$shimFs = $shim -replace '\\', '/'
$env:NODE_OPTIONS = "--require=`"$shimFs`""
$env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD = '20'

Write-Output "[run-as-workbuddy] SESSION_ID=$($env:CODEBUDDY_SESSION_ID)"
Write-Output "[run-as-workbuddy] TOOL_CALL_ID=$($env:CODEBUDDY_TOOL_CALL_ID)"
Write-Output "[run-as-workbuddy] NODE_OPTIONS=$($env:NODE_OPTIONS)"

& $Command @Rest
exit $LASTEXITCODE
