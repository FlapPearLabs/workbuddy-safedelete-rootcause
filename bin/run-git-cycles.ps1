# run-git-cycles.ps1
#
# Runs the Git A/B workload:
#   5 switch cycles (master <-> feature)
#   1 fast-forward merge
# Captures per-op records (exit code, expected/actual branch + HEAD, target
# reached) and per-step WORKTREE_CHECK_* records. Stops cleanly if a Git
# operation interferes (non-zero exit OR target branch/HEAD mismatch) but
# still records the post-op state via check-worktree before bailing.
#
# Evidence-localization repairs (2026-08-14):
#   REPAIR B: a step-0 pre-operation physical baseline (check-worktree with
#     label step-0-pre-operation-baseline) runs BEFORE any mutation. It is NOT
#     one of the 11 mutation checks. If it is not CLEAN, step-1a is never
#     executed and the broken state is classified PREEXISTING_NON_CLEAN
#     (so it cannot be falsely attributed to a mutation).
#   REPAIR C: the runner is wrapped in try/catch/finally and ALWAYS emits the
#     structured finalization markers (including GIT_CYCLES_END), even on
#     exception. A check-worktree failure is recorded (WORKTREE_CHECK_SCRIPT_ERROR)
#     and is never hidden.
#
# Usage:
#   .\run-git-cycles.ps1 -Repo <path> -Cycles 5 -OutputFile <path> [-Merge $true]
#
# Total expected mutation-check count for Cycles=5, Merge=$true is:
#   5 switch-to-feature + 5 switch-to-master + 1 merge = 11
# Plus exactly 1 baseline check (step-0-pre-operation-baseline) outside that count.
#
# For each checkout, the EXPECTED_HEAD is resolved from
# `git rev-parse <target branch>` BEFORE the operation. The op is
# declared TARGET_REACHED only if exit=0 AND actualBranch=expectedBranch
# AND actualHead=expectedHead.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][int]$Cycles,
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [bool]$Merge = $true,
    # Default branch name for the broad probe; F1-shape probe uses
    # 'feature/probe/f1-shape'. The branch is referenced both as the
    # checkout target and as the ff-merge source.
    [string]$BranchName = 'feature/probe/multi-level'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

# The OutputFile lives in a directory explicitly created by the caller
# (or by this script below); register its parent as an owned root.
if (Test-Path $OutputFile) { Remove-OwnedProbePath -Path $OutputFile -OwnedRoots @((Split-Path $OutputFile -Parent)) }
$OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null
"" | Set-Content $OutputFile -Encoding UTF8

function Record {
    param([string]$Line)
    Write-Output $Line
    Add-Content $OutputFile $Line -Encoding UTF8
}

# Compute expected checker count up-front so we can assert at the end.
# 5 switch-to-feature + 5 switch-to-master + 1 merge = 11.
$expectedChecks = (2 * $Cycles) + $(if ($Merge) { 1 } else { 0 })

# REPAIR B: distinguish mutation checks from the single pre-op baseline check.
# Canonical tokens: GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT /
# GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT (no legacy alias is emitted).
Record ("GIT_CYCLES_START repo=" + $Repo + " cycles=" + $Cycles + " merge=" + $Merge)
Record ("GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=" + $expectedChecks)
Record ("GIT_CYCLES_BASELINE_CHECK_COUNT=1")

$script:actualCheckCount = 0
$script:operationInterference = $false
$script:interferenceStep = ''
$script:aborted = $false
$script:abortStage = ''
$script:abortExceptionType = ''
$script:abortExceptionMessage = ''
$script:currentStage = ''

function Run-Operation {
    param(
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$ExpectedBranch,
        # ExpectedHeadOverride: a SHA to use as EXPECTED_HEAD, computed
        # BEFORE the op (e.g. by querying `git rev-parse <target branch>`).
        # If not supplied, falls back to the current HEAD before the op
        # (the old behavior, retained for compatibility).
        [string]$ExpectedHeadOverride = '',
        [string[]]$GitArgs
    )
    $script:actualCheckCount++
    $script:currentStage = $Label

    # Resolve the real expected head BEFORE the op. For a switch, this
    # is the tip of the target branch. For an ff-only merge, this is the
    # tip of the source branch (the merge moves HEAD to that tip).
    $expectedHead = ''
    if ($ExpectedHeadOverride) {
        $expectedHead = $ExpectedHeadOverride
    } else {
        $expectedHead = git rev-parse $Target 2>$null
        if ($LASTEXITCODE -ne 0) {
            $expectedHead = ''
        }
    }

    $beforeHead = git rev-parse HEAD
    $beforeBranch = git rev-parse --abbrev-ref HEAD
    Record ("GIT_OPERATION_STEP label=" + $Label)
    Record ("GIT_OPERATION_TYPE=" + $Type)
    Record ("GIT_OPERATION_LABEL=" + $Label)
    Record ("GIT_OPERATION_TARGET=" + $Target)
    Record ("GIT_OPERATION_BRANCH_BEFORE=" + $beforeBranch)
    Record ("GIT_OPERATION_HEAD_BEFORE=" + $beforeHead)
    Record ("GIT_OPERATION_EXPECTED_HEAD=" + $expectedHead)

    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $output = & git @GitArgs 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    $outTrim = ($output.Trim() -replace '\s+', ' ')
    if ($outTrim.Length -gt 200) { $outTrim = $outTrim.Substring(0, 200) + '...' }
    Record ("GIT_OPERATION_EXIT=" + $exit)
    Record ("GIT_OPERATION_OUTPUT=" + $outTrim)

    $afterHead = git rev-parse HEAD
    $afterBranch = git rev-parse --abbrev-ref HEAD
    Record ("GIT_OPERATION_BRANCH_AFTER=" + $afterBranch)
    Record ("GIT_OPERATION_HEAD_AFTER=" + $afterHead)

    $branchReached = ($afterBranch -eq $ExpectedBranch)
    $headReached   = if ($expectedHead) { ($afterHead -eq $expectedHead) } else { $true }
    Record ("EXPECTED_BRANCH=" + $ExpectedBranch)
    Record ("ACTUAL_BRANCH=" + $afterBranch)
    Record ("EXPECTED_HEAD=" + $expectedHead)
    Record ("ACTUAL_HEAD=" + $afterHead)

    $targetReached = if ($branchReached -and $headReached) { 'YES' } else { 'NO' }
    Record ("GIT_OPERATION_TARGET_REACHED=" + $targetReached)

    # REPAIR C: never let a check-worktree failure hide or trigger silent
    # mid-record exit. Record it, then stop further mutations.
    try {
        & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label $Label | ForEach-Object { Record $_ }
    } catch {
        Record ("WORKTREE_CHECK_SCRIPT_ERROR label=" + $Label + " type=" + $_.Exception.GetType().FullName + " message=" + $_.Exception.Message)
        $script:aborted = $true
        $script:abortStage = $Label
        $script:abortExceptionType = $_.Exception.GetType().FullName
        $script:abortExceptionMessage = $_.Exception.Message
        throw
    }

    if ($exit -ne 0 -or $targetReached -ne 'YES') {
        Record ("GIT_OPERATION_INTERFERENCE label=" + $Label + " exit=" + $exit + " target_reached=" + $targetReached + " branch_reached=" + $branchReached + " head_reached=" + $headReached)
        $script:operationInterference = $true
        $script:interferenceStep = $Label
        return $false
    }
    return $true
}

Push-Location $Repo
try {
    try {
        Record ("GIT_CYCLE_BASELINE_REPO=" + $Repo)
        Record ("GIT_CYCLE_BASELINE_HEAD=" + (git rev-parse HEAD))
        Record ("GIT_CYCLE_BASELINE_BRANCH=" + (git rev-parse --abbrev-ref HEAD))

        # REPAIR B: step-0 pre-operation physical baseline (NOT a mutation check).
        $preopLines = @()
        try {
            $preopLines = & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label 'step-0-pre-operation-baseline' 2>&1
        } catch {
            Record ("WORKTREE_CHECK_SCRIPT_ERROR label=step-0-pre-operation-baseline type=" + $_.Exception.GetType().FullName + " message=" + $_.Exception.Message)
            $script:aborted = $true
            $script:abortStage = 'step-0-pre-operation-baseline'
            $script:abortExceptionType = $_.Exception.GetType().FullName
            $script:abortExceptionMessage = $_.Exception.Message
            throw
        }
        $preopVerdict = 'UNKNOWN'; $preopMissing = -1; $preopMatch = 'NO'; $preopFsck = 'NO'
        foreach ($l in $preopLines) {
            if ($l -match '^WORKTREE_CHECK_VERDICT\s+label=step-0-pre-operation-baseline\s+value=(\S+)') { $preopVerdict = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_MISSING_COUNT=(\d+)') { $preopMissing = [int]$matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=(\S+)') { $preopMatch = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_FSCK_HEALTHY=(\S+)') { $preopFsck = $matches[1] }
            Record $l
        }
        Record ("GIT_CYCLES_PREOP_BASELINE_VERDICT=" + $preopVerdict)
        Record ("GIT_CYCLES_PREOP_BASELINE_MISSING_COUNT=" + $preopMissing)
        Record ("GIT_CYCLES_PREOP_BASELINE_HEAD_INDEX_TREE_MATCH=" + $preopMatch)
        Record ("GIT_CYCLES_PREOP_BASELINE_FSCK_HEALTHY=" + $preopFsck)

        $skipMutations = $false
        if ($preopVerdict -ne 'CLEAN') {
            # Do NOT attribute an already-broken worktree to step-1a.
            Record ("GIT_OPERATION_INTERFERENCE stage=preop-baseline classification=PREEXISTING_NON_CLEAN verdict=" + $preopVerdict + " missing=" + $preopMissing)
            $script:operationInterference = $true
            $script:interferenceStep = 'preop-baseline'
            $skipMutations = $true
        }

        if (-not $skipMutations) {
            for ($i = 1; $i -le $Cycles; $i++) {
                $featureTip = git rev-parse $BranchName 2>$null
                $ok = Run-Operation -Type 'checkout' -Label "step-${i}a-switch-to-feature" -Target $BranchName -ExpectedBranch $BranchName -ExpectedHeadOverride $featureTip -GitArgs @('checkout',$BranchName)
                if (-not $ok) { break }
                $masterTip = git rev-parse master 2>$null
                $ok = Run-Operation -Type 'checkout' -Label "step-${i}b-switch-to-master" -Target 'master' -ExpectedBranch 'master' -ExpectedHeadOverride $masterTip -GitArgs @('checkout','master')
                if (-not $ok) { break }
            }

            if ($Merge -and -not $script:operationInterference) {
                # For the ff-only merge, the expected post-merge HEAD is the
                # tip of the feature branch BEFORE the merge.
                $featureTipForMerge = git rev-parse $BranchName 2>$null
                $ok = Run-Operation -Type 'merge' -Label 'step-merge-ff-only' -Target 'merge ff-only feature into master' -ExpectedBranch 'master' -ExpectedHeadOverride $featureTipForMerge -GitArgs @('merge','--ff-only',$BranchName)
                if (-not $ok) { }
            }
        }
    }
    catch {
        # REPAIR C: structured abort capture. Preserve evidence, do not hide.
        $script:aborted = $true
        $script:abortStage = $script:currentStage
        $script:abortExceptionType = $_.Exception.GetType().FullName
        $script:abortExceptionMessage = $_.Exception.Message
        Record ("GIT_CYCLES_ABORT stage=" + $script:abortStage + " type=" + $script:abortExceptionType + " message=" + $script:abortExceptionMessage)
    }
}
finally {
    Pop-Location
}

# REPAIR C: finalization ALWAYS runs, regardless of success or failure.
Record ("GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=" + $expectedChecks)
Record ("GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=" + $script:actualCheckCount)
Record ("GIT_CYCLES_BASELINE_CHECK_COUNT=1")
Record ("GIT_CYCLES_ABORTED=" + $(if ($script:aborted) {'YES'} else {'NO'}))
Record ("GIT_CYCLES_ABORT_STAGE=" + $script:abortStage)
Record ("GIT_CYCLES_ABORT_EXCEPTION_TYPE=" + $script:abortExceptionType)
Record ("GIT_CYCLES_ABORT_EXCEPTION_MESSAGE=" + $script:abortExceptionMessage)
Record ("GIT_CYCLES_OK=" + $(if ($script:operationInterference -or $script:aborted) {'NO'} else {'YES'}))
if ($script:operationInterference) {
    Record ("GIT_CYCLES_INTERFERENCE_STEP=" + $script:interferenceStep)
}
Record "GIT_CYCLES_END"
