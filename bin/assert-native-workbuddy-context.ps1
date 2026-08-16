# assert-native-workbuddy-context.ps1
#
# Asserts that the current PowerShell process is executing inside the
# same WorkBuddy-native execution chain as the R1/R2 native runs (i.e. a
# process spawned under a real WorkBuddy tool-call session). This does NOT
# directly observe kernel-filter attachment state; it records process
# ancestry and session-id presence as evidence of the execution context.
#
# This is NOT the same as `REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE=True`,
# which only proves the WorkBuddy install + Node shim is on disk.
# A shim that is on disk is not the same as a shim that is active
# in the current process ancestry.
#
# This probe is safe: it does NOT dump command lines (which can
# contain secrets), it only reads parent process IDs and image
# names via CIM.
#
# Output (lines for the orchestrator / parser to grep):
#   WORKBUDDY_NATIVE_CONTEXT_PROBE_START
#   CURRENT_PID=<pid>
#   CURRENT_NAME=<image name>
#   CODEBUDDY_SESSION_ID_PRESENT=YES|NO
#   CODEBUDDY_SESSION_ID_LENGTH=<n>             (length only, not the value)
#   ANCESTRY_CHAIN pid=<n> name=<image>
#   ANCESTRY_REACHED_WORKBUDDY=<image>          (or NONE)
#   WORKBUDDY_NATIVE_ANCESTRY_CONFIRMED=YES|NO|UNKNOWN
#   ANCESTRY_API_AVAILABLE=YES|NO
#   WORKBUDDY_NATIVE_CONTEXT_PROBE_END
#
# Classification:
#   YES   - CODEBUDDY_SESSION_ID is set AND parent chain reaches
#           one of: sandbox-cli.exe, sandbox-cli-gc.exe, WorkBuddy.exe
#   UNKNOWN - inside WorkBuddy UI / tool-call but ancestry API unavailable
#   NO    - plain external shell (no session id, no WorkBuddy ancestor)
#
# Usage:
#   .\assert-native-workbuddy-context.ps1 -OutputFile <path>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference = 'Stop'
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null
"" | Set-Content $OutputFile -Encoding UTF8

function Record {
    param([string]$Line)
    Write-Output $Line
    Add-Content $OutputFile $Line -Encoding UTF8
}

Record "WORKBUDDY_NATIVE_CONTEXT_PROBE_START timestamp=$(Get-Date -Format 'o')"

# 1) Current process.
$currentPid = $PID
$currentName = '<unknown>'
try {
    $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $currentPid) -ErrorAction SilentlyContinue
    if ($proc) {
        $currentName = $proc.Name
    } else {
        # Fallback: use Get-Process (which is always available even when
        # CIM is blocked).
        try {
            $gp = Get-Process -Id $currentPid -ErrorAction SilentlyContinue
            if ($gp) { $currentName = $gp.ProcessName + '.exe' }
        } catch { }
    }
} catch { }
Record ("CURRENT_PID=" + $currentPid)
Record ("CURRENT_NAME=" + $currentName)

# 2) CODEBUDDY_SESSION_ID check.
$sessionId = $env:CODEBUDDY_SESSION_ID
$sessionPresent = if ($sessionId) { 'YES' } else { 'NO' }
Record ("CODEBUDDY_SESSION_ID_PRESENT=" + $sessionPresent)
Record ("CODEBUDDY_SESSION_ID_LENGTH=" + $(if ($sessionId) { $sessionId.Length } else { 0 }))

# 3) Parent chain walk.
$workbuddyAnchors = @('sandbox-cli.exe','sandbox-cli-gc.exe','WorkBuddy.exe')
$ancestryApi = 'NO'
$reached = 'NONE'
$chain = @()
try {
    $ppid = $currentPid
    $safety = 0
    while ($ppid -and $safety -lt 32) {
        # Prefer CIM; fall back to Get-Process if CIM is unavailable.
        $p = $null
        try {
            $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ppid) -ErrorAction SilentlyContinue
        } catch { $p = $null }
        if (-not $p) {
            try {
                $gp = Get-Process -Id $ppid -ErrorAction SilentlyContinue
                if ($gp) { $p = [PSCustomObject]@{ ProcessId = $gp.Id; Name = $gp.ProcessName + '.exe'; ParentProcessId = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ppid) -ErrorAction SilentlyContinue).ParentProcessId } }
            } catch { $p = $null }
        }
        if (-not $p) { break }
        $ancestryApi = 'YES'
        $chain += [PSCustomObject]@{ Pid = $p.ProcessId; Name = $p.Name }
        Record ("ANCESTRY_CHAIN pid=" + $p.ProcessId + " name=" + $p.Name)
        if ($workbuddyAnchors -contains $p.Name) {
            $reached = $p.Name
            break
        }
        $ppid = [int]$p.ParentProcessId
        if ($ppid -le 0) { break }
        $safety++
    }
} catch {
    $ancestryApi = 'NO'
}
Record ("ANCESTRY_API_AVAILABLE=" + $ancestryApi)
Record ("ANCESTRY_REACHED_WORKBUDDY=" + $reached)

# 4) Classification.
$classification = 'NO'
if ($sessionPresent -eq 'YES' -and $reached -ne 'NONE') {
    $classification = 'YES'
} elseif ($sessionPresent -eq 'YES' -and $ancestryApi -eq 'NO') {
    # Inside a session (session id set) but ancestry API failed.
    # We cannot prove the WorkBuddy ancestor.
    $classification = 'UNKNOWN'
} elseif ($sessionPresent -eq 'NO' -and $reached -ne 'NONE') {
    # Parent reaches WorkBuddy but no session id — odd; treat as UNKNOWN
    # so the operator is forced to check manually.
    $classification = 'UNKNOWN'
} else {
    $classification = 'NO'
}
Record ("WORKBUDDY_NATIVE_ANCESTRY_CONFIRMED=" + $classification)

Record "WORKBUDDY_NATIVE_CONTEXT_PROBE_END"
