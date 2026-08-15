# test-tsbx-lab-rule.ps1
#
# Deterministic tests for bin/prepare-tsbx-lab-rule.ps1 and
# bin/restore-tsbx-lab-rule.ps1 against SYNTHETIC rules copies under a
# TEMP GUID fixture. The live WorkBuddy tsbx_rules.json is never touched.
#
# Coverage:
#   1. prepare on a synthetic rules file: backup created, rule appended,
#      post-edit SHA differs, RULE_PREPARED_RESTART_REQUIRED=YES
#   2. prepare with invalid JSON input: fails cleanly (rollback), leaves
#      no helper/staging residue
#   3. restore from the backup: byte-exact, RESTORED_SHA == ORIGINAL_SHA,
#      PHASE2C_OK=YES
#
# Run:
#   .\test-tsbx-lab-rule.ps1
# Output:
#   TSBX_RULES_TEST_RESULT=PASS|FAIL

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$tmpRoot = Join-Path $env:TEMP ('workbuddy-rootcause-control\tsbx-rule-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$labRoot = Join-Path $tmpRoot 'lab'
New-Item -ItemType Directory -Path $labRoot -Force | Out-Null
$rulesPath = Join-Path $tmpRoot 'tsbx_rules.json'

$fail = $false
$preparePs1 = Join-Path $PSScriptRoot 'prepare-tsbx-lab-rule.ps1'
$restorePs1 = Join-Path $PSScriptRoot 'restore-tsbx-lab-rule.ps1'

function Invoke-Prepare {
    param([string]$RulesFile, [ref]$OutRef)
    try {
        $o = & $preparePs1 -LabRoot $labRoot -RulesPath $RulesFile 2>&1 | Out-String
        $OutRef.Value = $o
        return 0
    } catch {
        $OutRef.Value = $_.Exception.Message
        return 1
    }
}

function Invoke-Restore {
    param([string]$Backup, [string]$RulesFile, [ref]$OutRef)
    try {
        $o = & $restorePs1 -BackupPath $Backup -RulesPath $RulesFile 2>&1 | Out-String
        $OutRef.Value = $o
        return 0
    } catch {
        $OutRef.Value = $_.Exception.Message
        return 1
    }
}

# --- synthetic original rules (byte-exact writes: no BOM, no trailing newline) ---
$origJson = "{`"default_action`":`"deny_write`",`"recyclebin_backup`":true,`"file_rules_user`":[]}"
[System.IO.File]::WriteAllText($rulesPath, $origJson, [System.Text.UTF8Encoding]::new($false))
$origSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash

# --- 1) prepare ---
$prepareOut = ''
$prepareExit = Invoke-Prepare $rulesPath ([ref]$prepareOut)
$postSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash

if ($prepareExit -ne 0) {
    Write-Output "TSBX_RULES_TEST_FAILED=prepare threw: $prepareOut"
    $fail = $true
} else {
    if ($prepareOut -notmatch 'RULE_PREPARED_RESTART_REQUIRED=YES') { Write-Output 'TSBX_RULES_TEST_FAILED=prepare missing RESTART_REQUIRED marker'; $fail = $true }
    if ($prepareOut -notmatch 'TSBX_RULES_PHASE2A_OK=YES') { Write-Output 'TSBX_RULES_TEST_FAILED=prepare missing PHASE2A_OK'; $fail = $true }
    if ($postSha -eq $origSha) { Write-Output 'TSBX_RULES_TEST_FAILED=prepare did not change the file'; $fail = $true }
    $backupPath = [regex]::Match($prepareOut, 'TSBX_RULES_BACKUP_PATH=(\S+)').Groups[1].Value
    if (-not $backupPath -or -not (Test-Path $backupPath)) { Write-Output 'TSBX_RULES_TEST_FAILED=backup missing'; $fail = $true }
    $ruleJson = Get-Content $rulesPath -Raw | ConvertFrom-Json
    $found = @($ruleJson.file_rules_user | Where-Object { $_.type -eq 'inherit_user' }).Count
    if ($found -ne 1) { Write-Output "TSBX_RULES_TEST_FAILED=lab rule not appended exactly once (found=$found)"; $fail = $true }

    if (-not $fail) {
        # --- 3) restore ---
        $restoreOut = ''
        $restoreExit = Invoke-Restore $backupPath $rulesPath ([ref]$restoreOut)
        $restoredSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
        if ($restoreExit -ne 0) {
            Write-Output "TSBX_RULES_TEST_FAILED=restore threw: $restoreOut"
            $fail = $true
        } elseif ($restoredSha -ne $origSha) {
            Write-Output "TSBX_RULES_TEST_FAILED=restore not byte-exact (restored=$restoredSha original=$origSha)"
            $fail = $true
        } elseif ($restoreOut -notmatch 'TSBX_RULES_PHASE2C_OK=YES') {
            Write-Output 'TSBX_RULES_TEST_FAILED=restore missing PHASE2C_OK'
            $fail = $true
        } else {
            Write-Output 'TSBX_RULES_TEST_OK=prepare+restore round-trip byte-exact'
        }
    }
}

# --- 2) prepare with invalid JSON input must fail cleanly ---
$badRules = Join-Path $tmpRoot 'tsbx_rules_bad.json'
$badContent = '{"default_action": "deny_write",'
[System.IO.File]::WriteAllText($badRules, $badContent, [System.Text.UTF8Encoding]::new($false))
$badOut = ''
$badExit = Invoke-Prepare $badRules ([ref]$badOut)
if ($badExit -eq 0) {
    Write-Output 'TSBX_RULES_TEST_FAILED=prepare accepted invalid JSON'
    $fail = $true
} else {
    $badAfter = [System.IO.File]::ReadAllText($badRules)
    if ($badAfter -ne $badContent) {
        Write-Output 'TSBX_RULES_TEST_FAILED=prepare mutated invalid input instead of rolling back'
        $fail = $true
    } else {
        Write-Output 'TSBX_RULES_TEST_OK=prepare rejected invalid JSON without mutating input'
    }
}

$helperResidue = Get-ChildItem (Join-Path $labRoot 'work\tsbx-staging') -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_prepare-tsbx-lab-rule.cjs' -or $_.Name -like '_restore-tsbx-lab-rule.cjs' }
if ($helperResidue) {
    Write-Output 'TSBX_RULES_TEST_FAILED=helper residue left in staging'
    $fail = $true
} else {
    Write-Output 'TSBX_RULES_TEST_OK=no helper residue in staging'
}

# Cleanup only the test's own GUID dir.
if (Test-Path -LiteralPath $tmpRoot) { [System.IO.Directory]::Delete($tmpRoot, $true) }

if ($fail) {
    Write-Output 'TSBX_RULES_TEST_RESULT=FAIL'
    exit 1
}
Write-Output 'TSBX_RULES_TEST_RESULT=PASS'
