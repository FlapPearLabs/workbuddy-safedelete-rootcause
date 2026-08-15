# test-classify-run.ps1
#
# Deterministic tests for bin/classify-run.ps1 using synthetic run-git-cycles
# results files. Covers every classification branch:
#   CLEAN / WORKTREE_ONLY_LOSS / WORKTREE_CONTENT_DIVERGENCE /
#   PREEXISTING_NON_CLEAN / GIT_OPERATION_INTERFERENCE /
#   INSTRUMENTATION_ERROR / CHECKER_ERROR /
#   NONZERO_GIT_EXIT / TARGET_NOT_REACHED / INDEX_ONLY_DIVERGENCE
#
# Run:
#   .\test-classify-run.ps1
# Output:
#   CLASSIFY_RUN_TEST=PASS|FAIL

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$tmpRoot = Join-Path $env:TEMP ('workbuddy-rootcause-control\classify-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$fail = $false

function Run-Case {
    param(
        [string]$Name,
        [string]$Body,
        [hashtable]$Expect
    )
    $resultsFile = Join-Path $tmpRoot ($Name + '.txt')
    $outcomeFile = Join-Path $tmpRoot ($Name + '-outcome.txt')
    $Body | Set-Content -LiteralPath $resultsFile -Encoding UTF8
    & "$PSScriptRoot\classify-run.ps1" -ResultsFile $resultsFile -OutcomeFile $outcomeFile | Out-Null
    $outcome = Get-Content $outcomeFile
    foreach ($k in $Expect.Keys) {
        $pattern = '^' + $k + '=(.*)$'
        $m = $outcome | Select-String -Pattern $pattern | Select-Object -First 1
        if (-not $m) {
            Write-Output ("CASE_FAILED=" + $Name + " token " + $k + " missing")
            $script:fail = $true
            continue
        }
        if ($m.Matches[0].Groups[1].Value -ne $Expect[$k]) {
            Write-Output ("CASE_FAILED=" + $Name + " " + $k + " expected=" + $Expect[$k] + " got=" + $m.Matches[0].Groups[1].Value)
            $script:fail = $true
        }
    }
    Write-Output ("CASE_OK=" + $Name)
}

# Shared step block: 11 CLEAN steps helper text for clean cases.
$clean11 = @'
GIT_CYCLES_START repo=D:\fake\repo cycles=5 merge=True
GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=11
WORKTREE_CHECK_LABEL=step-1a-switch-to-feature
WORKTREE_CHECK_HEAD_PATH_COUNT=60
WORKTREE_CHECK_MISSING_COUNT=0
WORKTREE_CHECK_VERDICT label=step-1a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-1b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-1b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-2a-switch-to-feature
WORKTREE_CHECK_VERDICT label=step-2a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-2b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-2b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-3a-switch-to-feature
WORKTREE_CHECK_VERDICT label=step-3a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-3b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-3b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-4a-switch-to-feature
WORKTREE_CHECK_VERDICT label=step-4a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-4b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-4b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-5a-switch-to-feature
WORKTREE_CHECK_VERDICT label=step-5a-switch-to-feature value=CLEAN
WORKTREE_CHECK_LABEL=step-5b-switch-to-master
WORKTREE_CHECK_VERDICT label=step-5b-switch-to-master value=CLEAN
WORKTREE_CHECK_LABEL=step-merge-ff-only
WORKTREE_CHECK_VERDICT label=step-merge-ff-only value=CLEAN
GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=11
GIT_CYCLES_ABORTED=NO
GIT_CYCLES_OK=YES
GIT_CYCLES_END
'@ + "`n"   # ensure a trailing newline so `+ @'...'@` appends land on fresh lines

# 1) CLEAN
Run-Case -Name 'case1-clean' -Body $clean11 -Expect @{
    'RUN_CLASSIFICATION' = 'CLEAN'
    'WORKTREE_LOSS_REPRODUCED' = 'NO'
    'GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT' = '11'
    'GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT' = '11'
}

# 2) WORKTREE_ONLY_LOSS at step-3a
$lossBody = $clean11.Replace(
    'WORKTREE_CHECK_LABEL=step-3a-switch-to-feature',
    'WORKTREE_CHECK_LABEL=step-3a-switch-to-feature
WORKTREE_CHECK_MISSING label=step-3a-switch-to-feature classification=WORKTREE_ONLY_LOSS path=src/a01/main.txt head=yes index=yes physical=no
WORKTREE_CHECK_MISSING label=step-3a-switch-to-feature classification=WORKTREE_ONLY_LOSS path=test/t05/spec.txt head=yes index=yes physical=no
WORKTREE_CHECK_MISSING_COUNT=2'
).Replace(
    'WORKTREE_CHECK_VERDICT label=step-3a-switch-to-feature value=CLEAN',
    'WORKTREE_CHECK_VERDICT label=step-3a-switch-to-feature value=WORKTREE_ONLY_LOSS'
)
Run-Case -Name 'case2-loss' -Body $lossBody -Expect @{
    'RUN_CLASSIFICATION' = 'WORKTREE_ONLY_LOSS'
    'WORKTREE_LOSS_REPRODUCED' = 'YES'
    'WORKTREE_LOSS_FIRST_STEP' = 'step-3a-switch-to-feature'
    'WORKTREE_LOSS_FIRST_VERDICT' = 'WORKTREE_ONLY_LOSS'
    'WORKTREE_LOSS_MISSING_TRACKED_COUNT' = '2'
    'WORKTREE_LOSS_FIRST_MISSING_PATHS' = 'src/a01/main.txt,test/t05/spec.txt'
}

# 3) WORKTREE_CONTENT_DIVERGENCE -> YES
$cdBody = $clean11.Replace(
    'WORKTREE_CHECK_VERDICT label=step-2a-switch-to-feature value=CLEAN',
    'WORKTREE_CHECK_VERDICT label=step-2a-switch-to-feature value=WORKTREE_CONTENT_DIVERGENCE'
)
Run-Case -Name 'case3-content-divergence' -Body $cdBody -Expect @{
    'RUN_CLASSIFICATION' = 'WORKTREE_CONTENT_DIVERGENCE'
    'WORKTREE_LOSS_REPRODUCED' = 'YES'
    'WORKTREE_LOSS_FIRST_STEP' = 'step-2a-switch-to-feature'
}

# 4) git op interference without physical loss -> NO / GIT_OPERATION_INTERFERENCE
$intBody = $clean11 + @'
GIT_OPERATION_STEP label=step-1a-switch-to-feature
GIT_OPERATION_TYPE=checkout
GIT_OPERATION_EXIT=128
GIT_OPERATION_TARGET_REACHED=NO
GIT_OPERATION_INTERFERENCE label=step-1a-switch-to-feature exit=128 target_reached=NO branch_reached=NO head_reached=NO
'@
Run-Case -Name 'case4-interference' -Body $intBody -Expect @{
    'RUN_CLASSIFICATION' = 'GIT_OPERATION_INTERFERENCE'
    'WORKTREE_LOSS_REPRODUCED' = 'NO'
    'GIT_OPERATION_INTERFERENCE' = 'YES'
    'NONZERO_GIT_EXIT' = 'YES'
    'TARGET_NOT_REACHED' = 'YES'
}

# 5) preexisting non-clean -> PREEXISTING_NON_CLEAN / NO
$preBody = @'
GIT_CYCLES_START repo=D:\fake\repo cycles=5 merge=True
GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=11
GIT_CYCLES_PREOP_BASELINE_VERDICT=WORKTREE_ONLY_LOSS
GIT_CYCLES_PREOP_BASELINE_MISSING_COUNT=4
GIT_OPERATION_INTERFERENCE stage=preop-baseline classification=PREEXISTING_NON_CLEAN verdict=WORKTREE_ONLY_LOSS missing=4
GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=0
GIT_CYCLES_ABORTED=NO
GIT_CYCLES_OK=NO
GIT_CYCLES_END
'@
Run-Case -Name 'case5-preexisting' -Body $preBody -Expect @{
    'RUN_CLASSIFICATION' = 'PREEXISTING_NON_CLEAN'
    'WORKTREE_LOSS_REPRODUCED' = 'NO'
    'PREEXISTING_NON_CLEAN' = 'YES'
}

# 6) checker exception -> INSTRUMENTATION_ERROR / UNKNOWN
$chkBody = $clean11 + @'
WORKTREE_CHECK_SCRIPT_ERROR label=step-4a-switch-to-feature type=System.Exception message=boom
GIT_CYCLES_ABORT stage=step-4a-switch-to-feature type=System.Exception message=boom
GIT_CYCLES_ABORTED=YES
'@
Run-Case -Name 'case6-checker-throw' -Body $chkBody -Expect @{
    'RUN_CLASSIFICATION' = 'INSTRUMENTATION_ERROR'
    'WORKTREE_LOSS_REPRODUCED' = 'UNKNOWN'
    'INSTRUMENTATION_ERROR' = 'YES'
}

# 7) step present without verdict -> CHECKER_ERROR / UNKNOWN
$mvBody = $clean11 + @'
WORKTREE_CHECK_LABEL=step-5b-switch-to-master
WORKTREE_CHECK_HEAD_PATH_COUNT=60
WORKTREE_CHECK_MISSING_COUNT=0
'@
Run-Case -Name 'case7-missing-verdict' -Body $mvBody -Expect @{
    'RUN_CLASSIFICATION' = 'CHECKER_ERROR'
    'WORKTREE_LOSS_REPRODUCED' = 'UNKNOWN'
    'CHECKER_ERROR' = 'YES'
}

# 8) INDEX_ONLY_DIVERGENCE (no physical loss) -> verbatim / NO
$ioBody = $clean11.Replace(
    'WORKTREE_CHECK_VERDICT label=step-3b-switch-to-master value=CLEAN',
    'WORKTREE_CHECK_VERDICT label=step-3b-switch-to-master value=INDEX_ONLY_DIVERGENCE'
)
Run-Case -Name 'case8-index-only' -Body $ioBody -Expect @{
    'RUN_CLASSIFICATION' = 'INDEX_ONLY_DIVERGENCE'
    'WORKTREE_LOSS_REPRODUCED' = 'NO'
    'WORKTREE_LOSS_FIRST_STEP' = 'step-3b-switch-to-master'
}

# 9) incomplete run (expected 11, actual 8, no markers) -> INSTRUMENTATION_ERROR / UNKNOWN
$incBody = $clean11.Replace('GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=11', 'GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=8')
Run-Case -Name 'case9-incomplete' -Body $incBody -Expect @{
    'RUN_CLASSIFICATION' = 'INSTRUMENTATION_ERROR'
    'WORKTREE_LOSS_REPRODUCED' = 'UNKNOWN'
    'GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT' = '8'
}

# 10) interference with exit=0 but target not reached -> TARGET_NOT_REACHED=YES, NONZERO=NO
$tgtBody = $clean11 + @'
GIT_OPERATION_STEP label=step-1a-switch-to-feature
GIT_OPERATION_TYPE=checkout
GIT_OPERATION_EXIT=0
GIT_OPERATION_TARGET_REACHED=NO
GIT_OPERATION_INTERFERENCE label=step-1a-switch-to-feature exit=0 target_reached=NO branch_reached=NO head_reached=NO
'@
Run-Case -Name 'case10-target-not-reached' -Body $tgtBody -Expect @{
    'RUN_CLASSIFICATION' = 'GIT_OPERATION_INTERFERENCE'
    'WORKTREE_LOSS_REPRODUCED' = 'NO'
    'NONZERO_GIT_EXIT' = 'NO'
    'TARGET_NOT_REACHED' = 'YES'
}

# Cleanup only the test's own GUID dir (scoped; see Remove-OwnedProbePath doc).
if (Test-Path -LiteralPath $tmpRoot) { [System.IO.Directory]::Delete($tmpRoot, $true) }

if ($fail) {
    Write-Output "CLASSIFY_RUN_TEST=FAIL"
    exit 1
}
Write-Output "CLASSIFY_RUN_TEST=PASS"
