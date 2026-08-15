# classify-run.ps1
#
# Deterministic result classifier for a bin/run-git-cycles.ps1 results file.
# Replaces the former ad-hoc parser embedded in the experiment Markdown.
#
# Classification priority (highest first):
#   1. checker exception (WORKTREE_CHECK_SCRIPT_ERROR)
#        -> RUN_CLASSIFICATION=INSTRUMENTATION_ERROR, LOSS=UNKNOWN
#   2. step record present without any WORKTREE_CHECK_VERDICT
#        -> RUN_CLASSIFICATION=CHECKER_ERROR, LOSS=UNKNOWN
#   3. pre-op baseline non-clean
#        -> RUN_CLASSIFICATION=PREEXISTING_NON_CLEAN, LOSS=NO
#           (never attributed to the mutation under test)
#   4. physical worktree loss / content divergence verdict
#        -> LOSS=YES (see mapping below)
#   5. index-only divergence / other state divergence (no physical loss)
#        -> LOSS=NO / UNKNOWN, verbatim verdict
#   6. git operation interference without physical loss
#        -> RUN_CLASSIFICATION=GIT_OPERATION_INTERFERENCE, LOSS=NO
#           (with NONZERO_GIT_EXIT / TARGET_NOT_REACHED detail flags)
#   7. all steps CLEAN and actual count == expected (11 for 5 cycles + 1 merge)
#        -> RUN_CLASSIFICATION=CLEAN, LOSS=NO
#   8. anything else (incomplete run, no markers)
#        -> RUN_CLASSIFICATION=INSTRUMENTATION_ERROR, LOSS=UNKNOWN
#
# WORKTREE_LOSS_REPRODUCED is YES ONLY for physical loss/divergence evidence:
#   WORKTREE_ONLY_LOSS            -> YES (classification WORKTREE_ONLY_LOSS)
#   INDEX_AND_WORKTREE_LOSS       -> YES (classification WORKTREE_ONLY_LOSS)
#   INDEX_ADDITION_PHYSICAL_MISSING -> YES (classification WORKTREE_ONLY_LOSS)
#   WORKTREE_CONTENT_DIVERGENCE   -> YES (classification WORKTREE_CONTENT_DIVERGENCE)
# The exact check-worktree verdict is preserved in WORKTREE_LOSS_FIRST_VERDICT.
#
# Usage:
#   .\classify-run.ps1 -ResultsFile <results.txt> [-OutcomeFile <outcome.txt>]
#
# Output (stdout, and to -OutcomeFile if supplied):
#   RUN_CLASSIFICATION=...
#   WORKTREE_LOSS_REPRODUCED=YES|NO|UNKNOWN
#   WORKTREE_LOSS_FIRST_STEP=...
#   WORKTREE_LOSS_FIRST_VERDICT=...
#   WORKTREE_LOSS_MISSING_TRACKED_COUNT=...
#   WORKTREE_LOSS_FIRST_MISSING_PATHS=...
#   GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=...
#   GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=...
#   GIT_CYCLES_ABORTED=...
#   PREEXISTING_NON_CLEAN=YES|NO
#   GIT_OPERATION_INTERFERENCE=YES|NO
#   NONZERO_GIT_EXIT=YES|NO
#   TARGET_NOT_REACHED=YES|NO
#   CHECKER_ERROR=YES|NO
#   INSTRUMENTATION_ERROR=YES|NO
#   CLASSIFY_RUN_END

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ResultsFile,
    [string]$OutcomeFile = ''
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ResultsFile)) { throw "classify-run: results file not found: $ResultsFile" }
$lines = @(Get-Content $ResultsFile)

function Emit([string]$Line) {
    Write-Output $Line
    if ($OutcomeFile) { Add-Content -LiteralPath $OutcomeFile $Line -Encoding UTF8 }
}

# ---------------------------------------------------------------------------
# Parse step records (WORKTREE_CHECK_LABEL ... WORKTREE_CHECK_VERDICT groups)
# ---------------------------------------------------------------------------
$stepResults = New-Object 'System.Collections.Generic.List[object]'
$currentStep = ''
$currentVerdict = ''
$currentMissing = 0
$currentPaths = New-Object 'System.Collections.Generic.List[string]'
$currentHasVerdict = $false

function Flush-Step {
    param($Label, $Verdict, $Missing, $Paths, $HasVerdict, $Sink)
    $Sink.Add([PSCustomObject]@{
        Label = $Label
        Verdict = $Verdict
        Missing = $Missing
        Paths = $Paths
        HasVerdict = $HasVerdict
    })
}

foreach ($line in $lines) {
    if ($line -match '^WORKTREE_CHECK_LABEL=(\S+)') {
        if ($currentStep) {
            Flush-Step $currentStep $currentVerdict $currentMissing $currentPaths $currentHasVerdict $stepResults
        }
        $currentStep = $matches[1]
        $currentVerdict = ''
        $currentMissing = 0
        $currentPaths = New-Object 'System.Collections.Generic.List[string]'
        $currentHasVerdict = $false
    }
    elseif ($line -match '^WORKTREE_CHECK_VERDICT\s+label=(\S+)\s+value=(\S+)') {
        $currentVerdict = $matches[2]
        $currentHasVerdict = $true
    }
    elseif ($line -match '^WORKTREE_CHECK_MISSING_COUNT=(\d+)') {
        $currentMissing = [int]$matches[1]
    }
    elseif ($line -match '^WORKTREE_CHECK_MISSING\s+label=(\S+)\s+classification=(\S+)\s+path=(\S+)\s+') {
        if ($currentPaths.Count -lt 10) { $currentPaths.Add($matches[3]) | Out-Null }
    }
}
if ($currentStep) {
    Flush-Step $currentStep $currentVerdict $currentMissing $currentPaths $currentHasVerdict $stepResults
}

# ---------------------------------------------------------------------------
# Parse run-level markers
# ---------------------------------------------------------------------------
$expectedMutation = 0
$actualMutation = -1
$aborted = 'NO'
foreach ($line in $lines) {
    if ($line -match '^GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=(\d+)') { $expectedMutation = [int]$matches[1] }
    elseif ($line -match '^GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=(\d+)') { $actualMutation = [int]$matches[1] }
    elseif ($line -match '^GIT_CYCLES_ABORTED=(\S+)') { $aborted = $matches[1] }
}
$checkerErrors = @($lines | Where-Object { $_ -match '^WORKTREE_CHECK_SCRIPT_ERROR' })
$preopLines = @($lines | Where-Object { $_ -match '^GIT_OPERATION_INTERFERENCE stage=preop-baseline classification=PREEXISTING_NON_CLEAN' })
$interferenceLines = @($lines | Where-Object { $_ -match '^GIT_OPERATION_INTERFERENCE' -and $_ -notmatch 'stage=preop-baseline classification=PREEXISTING_NON_CLEAN' })
$anyNonzeroExit = @($lines | Where-Object { $_ -match '^GIT_OPERATION_EXIT=([1-9][0-9]*)' }).Count -gt 0
$anyTargetNotReached = @($lines | Where-Object { $_ -match '^GIT_OPERATION_TARGET_REACHED=NO' }).Count -gt 0

# ---------------------------------------------------------------------------
# Classify
# ---------------------------------------------------------------------------
$classification = 'CLEAN'
$loss = 'NO'
$firstNonClean = $null
$firstLoss = $null

# 1) checker exception -> INSTRUMENTATION_ERROR / UNKNOWN
if ($checkerErrors.Count -gt 0) {
    $classification = 'INSTRUMENTATION_ERROR'
    $loss = 'UNKNOWN'
}
# 2) step present without a verdict -> CHECKER_ERROR / UNKNOWN
# NOTE: @(...) wrapper required — a single-object pipeline result has no
# usable .Count in Windows PowerShell 5.1.
elseif (@($stepResults | Where-Object { -not $_.HasVerdict }).Count -gt 0) {
    $classification = 'CHECKER_ERROR'
    $loss = 'UNKNOWN'
}
# 3) preexisting non-clean -> PREEXISTING_NON_CLEAN / NO (not attributed)
elseif ($preopLines.Count -gt 0) {
    $classification = 'PREEXISTING_NON_CLEAN'
    $loss = 'NO'
}
else {
    $firstNonClean = $stepResults | Where-Object { $_.Verdict -ne 'CLEAN' } | Select-Object -First 1

    # 4) physical loss / content divergence -> YES
    $lossMap = @{
        'WORKTREE_ONLY_LOSS' = 'WORKTREE_ONLY_LOSS'
        'INDEX_AND_WORKTREE_LOSS' = 'WORKTREE_ONLY_LOSS'
        'INDEX_ADDITION_PHYSICAL_MISSING' = 'WORKTREE_ONLY_LOSS'
        'WORKTREE_CONTENT_DIVERGENCE' = 'WORKTREE_CONTENT_DIVERGENCE'
    }
    $firstLoss = $stepResults | Where-Object { $_.Verdict -and $lossMap.ContainsKey($_.Verdict) } | Select-Object -First 1
    if ($firstLoss) {
        $classification = $lossMap[$firstLoss.Verdict]
        $loss = 'YES'
    }
    # 5) non-loss divergence verdicts (verbatim; no physical loss)
    elseif ($firstNonClean) {
        $classification = $firstNonClean.Verdict
        $loss = if ($firstNonClean.Verdict -eq 'OTHER_STATE_DIVERGENCE') { 'UNKNOWN' } else { 'NO' }
    }
    # 6) git operation interference without physical loss
    elseif ($interferenceLines.Count -gt 0) {
        $classification = 'GIT_OPERATION_INTERFERENCE'
        $loss = 'NO'
    }
    # 7) all CLEAN, count matches
    elseif ($stepResults.Count -gt 0 -and ($actualMutation -eq $expectedMutation)) {
        $classification = 'CLEAN'
        $loss = 'NO'
    }
    # 8) incomplete / unclassifiable
    else {
        $classification = 'INSTRUMENTATION_ERROR'
        $loss = 'UNKNOWN'
    }
}

$detailStep = if ($firstLoss) { $firstLoss.Label } elseif ($firstNonClean) { $firstNonClean.Label } else { '' }
$detailVerdict = if ($firstLoss) { $firstLoss.Verdict } elseif ($firstNonClean) { $firstNonClean.Verdict } else { '' }
$detailMissing = if ($firstLoss) { $firstLoss.Missing } elseif ($firstNonClean) { $firstNonClean.Missing } else { -1 }
$detailPaths = if ($firstLoss) { $firstLoss.Paths } elseif ($firstNonClean) { $firstNonClean.Paths } else { @() }

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
if ($OutcomeFile) {
    New-Item -ItemType Directory -Path (Split-Path $OutcomeFile) -Force | Out-Null
    "" | Set-Content -LiteralPath $OutcomeFile -Encoding UTF8
}
Emit ("RUN_CLASSIFICATION=" + $classification)
Emit ("WORKTREE_LOSS_REPRODUCED=" + $loss)
Emit ("WORKTREE_LOSS_FIRST_STEP=" + $detailStep)
Emit ("WORKTREE_LOSS_FIRST_VERDICT=" + $detailVerdict)
Emit ("WORKTREE_LOSS_MISSING_TRACKED_COUNT=" + $detailMissing)
Emit ("WORKTREE_LOSS_FIRST_MISSING_PATHS=" + ($detailPaths -join ','))
Emit ("GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=" + $expectedMutation)
Emit ("GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=" + $actualMutation)
Emit ("GIT_CYCLES_ABORTED=" + $aborted)
Emit ("PREEXISTING_NON_CLEAN=" + $(if ($preopLines.Count -gt 0) { 'YES' } else { 'NO' }))
Emit ("GIT_OPERATION_INTERFERENCE=" + $(if ($interferenceLines.Count -gt 0) { 'YES' } else { 'NO' }))
Emit ("NONZERO_GIT_EXIT=" + $(if ($anyNonzeroExit) { 'YES' } else { 'NO' }))
Emit ("TARGET_NOT_REACHED=" + $(if ($anyTargetNotReached) { 'YES' } else { 'NO' }))
Emit ("CHECKER_ERROR=" + $(if ($classification -eq 'CHECKER_ERROR') { 'YES' } else { 'NO' }))
Emit ("INSTRUMENTATION_ERROR=" + $(if ($classification -eq 'INSTRUMENTATION_ERROR') { 'YES' } else { 'NO' }))
Emit "CLASSIFY_RUN_END"
