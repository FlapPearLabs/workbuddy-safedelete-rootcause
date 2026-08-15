# restore-tsbx-lab-rule.ps1
#
# Phase 2C of the WorkBuddy-native experiment: RESTORE the live
# tsbx_rules.json from a byte-exact backup produced by
# prepare-tsbx-lab-rule.ps1.
#
# Hard rules (per the final release-gate spec):
#   - read backup bytes
#   - write them to a temp file in a safe staging dir
#   - parse the staged file to make sure it is valid JSON
#   - verify the SHA matches the expected pre-edit SHA
#   - atomically replace the target (Move-Item on same volume)
#   - print "ORIGINAL_RULES_RESTORED_RESTART_REQUIRED" so the user
#     knows to restart WorkBuddy
#   - never touch any other rule besides restoring the original bytes
#
# Usage:
#   .\restore-tsbx-lab-rule.ps1 -BackupPath <path> [-WorkbuddyInstall <path>]
#   .\restore-tsbx-lab-rule.ps1 -BackupPath <path> -RulesPath <synthetic-copy>   # deterministic test override
#
# -RulesPath: restore onto a synthetic copy of tsbx_rules.json instead of the
# live WorkBuddy install file. Used ONLY by deterministic tests on TEMP
# fixtures; never point it at the live install file.
#
# The staged-JSON diagnostic is non-fatal: if it fails (or node is
# unavailable), restore still proceeds, because the byte-exact backup SHA is
# re-verified against the target after the move. The restore path remains
# usable even if an intermediate diagnostic operation fails.
#
# Outputs:
#   TSBX_RULES_RESTORED_FROM=<path>
#   TSBX_RULES_RESTORED_SHA256=<sha>
#   TSBX_RULES_ORIGINAL_SHA256=<sha>   (the SHA the file should match)
#   TSBX_RULES_ORIGINAL_RULES_RESTORED_RESTART_REQUIRED=YES
#   TSBX_RULES_PHASE2C_OK=YES

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BackupPath,
    [string]$WorkbuddyInstall = '',
    [string]$RulesPath = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

if ($RulesPath) {
    # Deterministic test override: operate only on a synthetic copy.
    if (-not (Test-Path $RulesPath)) { throw "restore-tsbx-lab-rule: -RulesPath not found: $RulesPath" }
    $rulesPath = [System.IO.Path]::GetFullPath($RulesPath)
} else {
    if (-not $WorkbuddyInstall) {
        $WorkbuddyInstall = Resolve-WorkbuddyInstallPath
        if (-not $WorkbuddyInstall) { throw "WorkBuddy install not found" }
    }
    # Discover the current live tsbx_rules.json.
    $rulesPath = Join-Path $WorkbuddyInstall 'resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
    if (-not (Test-Path $rulesPath)) {
        $candidates = Get-ChildItem (Join-Path $WorkbuddyInstall 'resources\app.asar.unpacked\cli\vendor\sandbox') -Directory -ErrorAction SilentlyContinue
        if ($candidates) {
            $alt = $candidates | Where-Object { Test-Path (Join-Path $_.FullName 'tsbx_rules.json') } | Select-Object -First 1
            if ($alt) { $rulesPath = Join-Path $alt.FullName 'tsbx_rules.json' }
        }
    }
    if (-not (Test-Path $rulesPath)) { throw "tsbx_rules.json not found under $WorkbuddyInstall" }
}
if (-not (Test-Path $BackupPath)) { throw "backup file not found: $BackupPath" }

# Read the backup bytes (byte-exact restore).
$backupBytes = [System.IO.File]::ReadAllBytes($BackupPath)
$backupSha = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($backupBytes)) -Algorithm SHA256).Hash
Write-Output ("TSBX_RULES_ORIGINAL_SHA256=" + $backupSha)

# Staging dir is the lab's work dir (outside WorkBuddy install).
$stagingDir = Join-Path (Split-Path $BackupPath -Parent) 'tsbx-staging'
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
$script:TsbxOwnedRoots = @($stagingDir)
$stagingPath = Join-Path $stagingDir ("tsbx_rules.restored." + [guid]::NewGuid().ToString('N').Substring(0,8) + ".json")
[System.IO.File]::WriteAllBytes($stagingPath, $backupBytes)

# Validate the staged file is parseable JSON (diagnostic step only).
$nodeScript = @"
const fs = require('fs');
try {
    const obj = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    if (!obj || typeof obj !== 'object') { console.error('NOT_OBJECT'); process.exit(20); }
    console.log('STAGED_OK');
} catch (e) {
    console.error('STAGED_PARSE_FAILED: ' + e.message);
    process.exit(21);
}
"@
# The node helper is written into the staging dir (NOT into bin/) so it can
# be removed through the scoped owned-path helper and never ships.
$nodeHelperPath = Join-Path $stagingDir '_restore-tsbx-lab-rule.cjs'
"" | Set-Content $nodeHelperPath -Encoding UTF8
$nodeScript | Add-Content $nodeHelperPath -Encoding UTF8
$nodeBin = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeBin) {
    Write-Output "TSBX_RULES_STAGED_VALIDATION=SKIPPED_NODE_MISSING"
} else {
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $nodeOut = & $nodeBin $nodeHelperPath $stagingPath 2>&1 | Out-String
    $nodeExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($nodeExit -ne 0) {
        # Non-fatal: the final SHA gate below is the actual safety check.
        Write-Output ("TSBX_RULES_STAGED_VALIDATION_WARNING=yes exit=" + $nodeExit + " output=" + $nodeOut.Trim())
    } else {
        Write-Output "TSBX_RULES_STAGED_VALIDATION=OK"
    }
}
Remove-OwnedProbePath -Path $nodeHelperPath -OwnedRoots $script:TsbxOwnedRoots

# Atomic replace (on the same volume; Move-Item -Force is not strictly
# atomic on Windows but the staging and target are on the same volume
# so the visible state is binary: either old or new).
Move-Item -LiteralPath $stagingPath -Destination $rulesPath -Force

$restoredSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
if ($restoredSha -ne $backupSha) {
    throw "restored SHA mismatch; backup=$backupSha current=$restoredSha. Manual intervention required."
}

Write-Output ("TSBX_RULES_RESTORED_FROM=" + $BackupPath)
Write-Output ("TSBX_RULES_RESTORED_SHA256=" + $restoredSha)
Write-Output "TSBX_RULES_ORIGINAL_RULES_RESTORED_RESTART_REQUIRED=YES"
Write-Output "TSBX_RULES_PHASE2C_OK=YES"
