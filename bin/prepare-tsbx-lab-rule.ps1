# prepare-tsbx-lab-rule.ps1
#
# Phase 2A of the WorkBuddy-native experiment: PREPARE the narrow lab rule
# in the live tsbx_rules.json so the kernel filter can pick it up on the
# next WorkBuddy startup.
#
# Hard rules (per the final release-gate spec):
#   - read original bytes; backup outside the WorkBuddy install dir
#     (under <LAB>/work/tsbx-backup/) to preserve byte-exact recovery
#   - parse JSON; reject if a duplicate lab rule already exists
#   - modify file_rules_user SEMANTICALLY (parse, mutate, re-serialize)
#   - write to a temp file in a safe staging dir, validate, then atomically
#     replace the target (Move-Item is atomic on the same volume)
#   - print new SHA, backup path, and the "RULE_PREPARED_RESTART_REQUIRED"
#     signal; do NOT run any Git probe in this phase
#
# Usage:
#   .\prepare-tsbx-lab-rule.ps1 -LabRoot <path> [-WorkbuddyInstall D:\WORKBUDDY]
#
# Outputs (lines for the orchestrator to grep):
#   TSBX_RULES_PRE_EDIT_SHA256=<sha>
#   TSBX_RULES_BACKUP_PATH=<path>
#   TSBX_RULES_BACKUP_SHA256=<sha>
#   TSBX_RULES_POST_EDIT_SHA256=<sha>
#   TSBX_RULES_LAB_RULE_PATH=<lab>\**
#   TSBX_RULES_LAB_RULE_TYPE=inherit_user
#   TSBX_RULES_RULE_PREPARED_RESTART_REQUIRED=YES
#   TSBX_RULES_PHASE2A_OK=YES
#
# Exits non-zero on any failure (and rolls back to the original bytes
# if the post-edit file is invalid).

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$LabRoot,
    [string]$WorkbuddyInstall = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not $WorkbuddyInstall) {
    $WorkbuddyInstall = Resolve-WorkbuddyInstallPath
    if (-not $WorkbuddyInstall) { throw "WorkBuddy install not found" }
}

$rulesPath = Join-Path $WorkbuddyInstall 'resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
if (-not (Test-Path $rulesPath)) {
    # Older installs may live at a different minor version.
    $candidates = Get-ChildItem (Join-Path $WorkbuddyInstall 'resources\app.asar.unpacked\cli\vendor\sandbox') -Directory -ErrorAction SilentlyContinue
    if ($candidates) {
        $alt = $candidates | Where-Object { Test-Path (Join-Path $_.FullName 'tsbx_rules.json') } | Select-Object -First 1
        if ($alt) { $rulesPath = Join-Path $alt.FullName 'tsbx_rules.json' }
    }
}
if (-not (Test-Path $rulesPath)) { throw "tsbx_rules.json not found under $WorkbuddyInstall" }

# Backup dir is OUTSIDE the WorkBuddy install (per spec).
$backupDir = Join-Path $LabRoot 'work\tsbx-backup'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $backupDir ("tsbx_rules.original." + $stamp + ".json")

# Read the original bytes (do NOT use Get-Content | ConvertFrom-Json; we
# want byte-exact preservation for restore).
$origBytes = [System.IO.File]::ReadAllBytes($rulesPath)
$origSha = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($origBytes)) -Algorithm SHA256).Hash
Write-Output ("TSBX_RULES_PRE_EDIT_SHA256=" + $origSha)

# Write the backup BEFORE we touch the live file.
[System.IO.File]::WriteAllBytes($backupPath, $origBytes)
$backupSha = (Get-FileHash $backupPath -Algorithm SHA256).Hash
if ($backupSha -ne $origSha) { throw "backup hash mismatch after write; aborting" }
Write-Output ("TSBX_RULES_BACKUP_PATH=" + $backupPath)
Write-Output ("TSBX_RULES_BACKUP_SHA256=" + $backupSha)

# Parse JSON via node (deterministic, no PowerShell string concat). The
# node helper does:
#   1. read original bytes
#   2. JSON.parse
#   3. reject if file_rules_user already contains an entry whose path
#      === <lab>\\** and type === "inherit_user"
#   4. append the new entry to file_rules_user
#   5. JSON.stringify with stable indent
#   6. write to a temp file in a safe staging dir
#   7. read temp back, JSON.parse, verify the entry is present
#   8. fs.renameSync(temp, target) (atomic on same volume)
#
# We do this with a Node one-liner so we don't have to ship a separate
# .js file. The script is intentionally minimal and self-contained.

$labRulePath = ($LabRoot.TrimEnd('\','/')) + '\\**'
$nodeScript = @"
const fs = require('fs');
const path = require('path');
const targetPath = process.argv[2];
const backupPath = process.argv[3];
const stagingPath = process.argv[4];
const labRulePath = process.argv[5];

const origBytes = fs.readFileSync(targetPath);
const origText  = origBytes.toString('utf8');
let obj;
try { obj = JSON.parse(origText); } catch (e) {
    console.error('JSON_PARSE_FAILED: ' + e.message);
    process.exit(11);
}

if (!Array.isArray(obj.file_rules_user)) {
    console.error('FIELD_NOT_ARRAY: file_rules_user');
    process.exit(12);
}

const dup = obj.file_rules_user.find(e => e && e.path === labRulePath && e.type === 'inherit_user');
if (dup) {
    console.error('DUPLICATE_LAB_RULE: ' + labRulePath);
    process.exit(13);
}

obj.file_rules_user.push({ path: labRulePath, type: 'inherit_user' });

const newText = JSON.stringify(obj, null, 4) + '\n';
fs.writeFileSync(stagingPath, newText);

// Validate the staged file by re-parsing.
let verify;
try { verify = JSON.parse(fs.readFileSync(stagingPath, 'utf8')); } catch (e) {
    console.error('STAGED_PARSE_FAILED: ' + e.message);
    process.exit(14);
}
const found = (verify.file_rules_user || []).find(e => e && e.path === labRulePath && e.type === 'inherit_user');
if (!found) {
    console.error('STAGED_VERIFY_MISSING: ' + labRulePath);
    process.exit(15);
}

// Atomic replace on the same volume.
fs.renameSync(stagingPath, targetPath);
console.log('STAGED_OK');
"@

# Save the helper alongside the script (not into the WorkBuddy install).
$nodeHelperPath = Join-Path $PSScriptRoot '_prepare-tsbx-lab-rule.cjs'
"" | Set-Content $nodeHelperPath -Encoding UTF8
$nodeScript | Add-Content $nodeHelperPath -Encoding UTF8

# Staging dir is the lab's work dir (outside WorkBuddy install).
$stagingDir = Join-Path $LabRoot 'work\tsbx-staging'
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
$stagingPath = Join-Path $stagingDir ("tsbx_rules.staged." + $stamp + ".json")
if (Test-Path $stagingPath) { mavis-trash $stagingPath }

$nodeBin = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeBin) { throw "node not found on PATH" }

$prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$nodeOut = & $nodeBin $nodeHelperPath $rulesPath $backupPath $stagingPath $labRulePath 2>&1 | Out-String
$nodeExit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($nodeExit -ne 0) {
    # Roll back: restore the original bytes.
    [System.IO.File]::WriteAllBytes($rulesPath, $origBytes)
    mavis-trash $nodeHelperPath
    if (Test-Path $stagingPath) { mavis-trash $stagingPath }
    throw "prepare-tsbx-lab-rule: node helper failed (exit=$nodeExit): $nodeOut. Live file restored from in-memory original bytes."
}

# Verify the post-edit hash.
$postSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
Write-Output ("TSBX_RULES_POST_EDIT_SHA256=" + $postSha)
Write-Output ("TSBX_RULES_LAB_RULE_PATH=" + $labRulePath)
Write-Output ("TSBX_RULES_LAB_RULE_TYPE=inherit_user")
Write-Output "TSBX_RULES_RULE_PREPARED_RESTART_REQUIRED=YES"
Write-Output "TSBX_RULES_PHASE2A_OK=YES"

# Clean up helper and staging file (the staged file was already moved
# atomically into place; mavis-trash the helper so it doesn't ship).
mavis-trash $nodeHelperPath
if (Test-Path $stagingPath) { mavis-trash $stagingPath }
