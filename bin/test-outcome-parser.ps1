# test-outcome-parser.ps1
#
# Self-contained parser test for the worktree-checker output format.
# Injects a synthetic results file containing a fake WORKTREE_ONLY_LOSS
# record, runs the parser, and asserts the expected derived fields:
#   FIRST_NON_CLEAN_STEP
#   FIRST_NON_CLEAN_VERDICT
#   MISSING_TRACKED_COUNT
#   FIRST_MISSING_PATHS
#
# Run:
#   .\test-outcome-parser.ps1

[CmdletBinding()]
param(
    [string]$OutputFile = ''
)
$ErrorActionPreference = 'Stop'

# Use a unique GUID-owned temp directory. The test itself owns this directory;
# cleanup uses ordinary PowerShell Remove-Item ONLY against the exact GUID dir
# (never a parent dir, never a repository path). No mavis-trash / unrelated
# environment-utility dependency, so the deterministic parser regression no
# longer depends on an external binary.
$tmpRoot = Join-Path $env:TEMP ('workbuddy-rootcause-control\parser-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$synthFile = Join-Path $tmpRoot 'synthetic-results.txt'
try {

# Synthetic results: 4 clean steps + 1 step with WORKTREE_ONLY_LOSS.
$synth = @"
GIT_CYCLES_START repo=D:\fake\repo cycles=5 merge=True
GIT_CYCLES_EXPECTED_CHECK_COUNT=11
WORKTREE_CHECK_LABEL=step-1a-switch-to-feature
WORKTREE_CHECK_REPO=D:\fake\repo
WORKTREE_CHECK_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
WORKTREE_CHECK_BRANCH=feature/probe/multi-level
WORKTREE_CHECK_HEAD_TREE=1111111111111111111111111111111111111111
WORKTREE_CHECK_INDEX_TREE=1111111111111111111111111111111111111111
WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=YES
WORKTREE_CHECK_HEAD_PATH_COUNT=60
WORKTREE_CHECK_INDEX_PATH_COUNT=60
WORKTREE_CHECK_UNION_PATH_COUNT=60
WORKTREE_CHECK_PHYSICAL_PRESENT_COUNT=60
WORKTREE_CHECK_MISSING_COUNT=0
WORKTREE_CHECK_VERDICT label=step-1a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-1b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-1b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-2a-switch-to-feature
WORKTREE_CHECK_VERDICT label=step-2a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-2b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-2b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-3a-switch-to-feature
WORKTREE_CHECK_MISSING label=step-3a-switch-to-feature classification=WORKTREE_ONLY_LOSS path=src/a01/main.txt head=yes index=yes physical=no
WORKTREE_CHECK_MISSING label=step-3a-switch-to-feature classification=WORKTREE_ONLY_LOSS path=src/a02/main.txt head=yes index=yes physical=no
WORKTREE_CHECK_MISSING label=step-3a-switch-to-feature classification=WORKTREE_ONLY_LOSS path=test/t05/spec.txt head=yes index=yes physical=no
WORKTREE_CHECK_MISSING_COUNT=3
WORKTREE_CHECK_VERDICT label=step-3a-switch-to-feature value=WORKTREE_ONLY_LOSS
GIT_OPERATION_INTERFERENCE label=step-3a-switch-to-feature exit=0 target_reached=NO
GIT_CYCLES_ACTUAL_CHECK_COUNT=3
GIT_CYCLES_OK=NO
GIT_CYCLES_INTERFERENCE_STEP=step-3a-switch-to-feature
GIT_CYCLES_END
"@

"" | Set-Content $synthFile -Encoding UTF8
$synth | Add-Content $synthFile -Encoding UTF8

# ── Parser ──
# Reads the synthetic file and prints the derived fields.
#
# Tracks the *current* step (most recent WORKTREE_CHECK_LABEL line) and
# aggregates per-step stats: missing count, first-missing paths, verdict.
# At the end, scans step results for the first non-CLEAN step and prints
# its stats. This is the same logic the orchestrator / user prompt uses.
$lines = Get-Content $synthFile -Encoding UTF8
$firstNonCleanStep = ''
$firstNonCleanVerdict = ''
$missingCount = -1
$firstMissing = New-Object 'System.Collections.Generic.List[string]'

# stepResults is an ordered list of [stepLabel, verdict, missingCount, [paths]]
$currentStep = ''
$currentVerdict = ''
$currentMissing = 0
$currentPaths = New-Object 'System.Collections.Generic.List[string]'
$stepResults = New-Object 'System.Collections.Generic.List[object]'

function Flush-Step {
    param($Label, $Verdict, $Missing, $PathsList, $Sink)
    $Sink.Add([PSCustomObject]@{
        Label = $Label
        Verdict = $Verdict
        Missing = $Missing
        Paths = $PathsList
    })
}

foreach ($line in $lines) {
    if ($line -match '^WORKTREE_CHECK_LABEL=(\S+)') {
        # New step begins. If we were tracking a step, flush it.
        if ($currentStep) {
            Flush-Step $currentStep $currentVerdict $currentMissing $currentPaths $stepResults
        }
        $currentStep = $matches[1]
        $currentVerdict = ''
        $currentMissing = 0
        $currentPaths = New-Object 'System.Collections.Generic.List[string]'
    }
    elseif ($line -match '^WORKTREE_CHECK_VERDICT\s+label=(\S+)\s+value=(\S+)') {
        $currentVerdict = $matches[2]
    }
    elseif ($line -match '^WORKTREE_CHECK_MISSING_COUNT=(\d+)') {
        $currentMissing = [int]$matches[1]
    }
    elseif ($line -match '^WORKTREE_CHECK_MISSING\s+label=(\S+)\s+classification=(\S+)\s+path=(\S+)\s+') {
        if ($currentPaths.Count -lt 10) { $currentPaths.Add($matches[3]) | Out-Null }
    }
}
if ($currentStep) {
    Flush-Step $currentStep $currentVerdict $currentMissing $currentPaths $stepResults
}

# Find the first non-CLEAN step.
foreach ($s in $stepResults) {
    if ($s.Verdict -ne 'CLEAN') {
        $firstNonCleanStep = $s.Label
        $firstNonCleanVerdict = $s.Verdict
        $missingCount = $s.Missing
        $firstMissing = $s.Paths
        break
    }
}

Write-Output "PARSER_TEST_FILE=$synthFile"
Write-Output "PARSER_TEST_FIRST_NON_CLEAN_STEP=$firstNonCleanStep"
Write-Output "PARSER_TEST_FIRST_NON_CLEAN_VERDICT=$firstNonCleanVerdict"
Write-Output "PARSER_TEST_MISSING_TRACKED_COUNT=$missingCount"
Write-Output "PARSER_TEST_FIRST_MISSING_PATHS=" + ($firstMissing -join ',')

# ── Assertions ──
$fail = $false
if ($firstNonCleanStep -ne 'step-3a-switch-to-feature') {
    Write-Output "PARSER_TEST_ASSERTION_FAILED: expected FIRST_NON_CLEAN_STEP=step-3a-switch-to-feature, got '$firstNonCleanStep'"
    $fail = $true
}
if ($firstNonCleanVerdict -ne 'WORKTREE_ONLY_LOSS') {
    Write-Output "PARSER_TEST_ASSERTION_FAILED: expected FIRST_NON_CLEAN_VERDICT=WORKTREE_ONLY_LOSS, got '$firstNonCleanVerdict'"
    $fail = $true
}
if ($missingCount -ne 3) {
    Write-Output "PARSER_TEST_ASSERTION_FAILED: expected MISSING_TRACKED_COUNT=3, got '$missingCount'"
    $fail = $true
}
$expectedPaths = @('src/a01/main.txt','src/a02/main.txt','test/t05/spec.txt')
for ($i = 0; $i -lt $expectedPaths.Count; $i++) {
    if ($firstMissing[$i] -ne $expectedPaths[$i]) {
        Write-Output "PARSER_TEST_ASSERTION_FAILED: expected first-missing[$i]='$($expectedPaths[$i])', got '$($firstMissing[$i])'"
        $fail = $true
    }
}

if ($fail) {
    Write-Output "PARSER_TEST_RESULT=FAIL"
    exit 1
}
Write-Output "PARSER_TEST_RESULT=PASS"
} finally {
    # Cleanup: ordinary Remove-Item against the exact GUID-owned dir only.
    # Never delete a parent directory; never operate on repository paths.
    if (Test-Path $tmpRoot) { Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
