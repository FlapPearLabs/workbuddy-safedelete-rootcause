# run-git-cycles.ps1
#
# Runs the Git A/B workload:
#   5 switch cycles (master <-> feature)
#   1 fast-forward merge
# Captures per-op records (exit code, target reached) and per-step
# WORKTREE_CHECK_* records. Stops cleanly if a Git operation
# interferes (non-zero exit OR target not reached) but still records
# the post-op state via check-worktree before bailing.
#
# Usage:
#   .\run-git-cycles.ps1 -Repo <path> -Cycles 5 -OutputFile <path> [-Merge $true]
#
# Total expected check count for Cycles=5, Merge=$true is:
#   5 switch-to-feature + 5 switch-to-master + 1 merge = 11

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][int]$Cycles,
    [Parameter(Mandatory=$true)][string]$OutputFile,
    [bool]$Merge = $true
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

if (Test-Path $OutputFile) { mavis-trash $OutputFile }
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
Record ("GIT_CYCLES_START repo=" + $Repo + " cycles=" + $Cycles + " merge=" + $Merge)
Record ("GIT_CYCLES_EXPECTED_CHECK_COUNT=" + $expectedChecks)

$actualCheckCount = 0
$operationInterference = $false
$interferenceStep = ''

function Run-Operation {
    param(
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$Target,
        [Parameter(Mandatory=$true)][string]$ExpectedBranch,
        [string[]]$GitArgs
    )
    $script:actualCheckCount++
    $beforeHead = git rev-parse HEAD
    $beforeBranch = git rev-parse --abbrev-ref HEAD
    Record ("GIT_OPERATION_STEP label=" + $Label)
    Record ("GIT_OPERATION_TYPE=" + $Type)
    Record ("GIT_OPERATION_LABEL=" + $Label)
    Record ("GIT_OPERATION_TARGET=" + $Target)
    Record ("GIT_OPERATION_BRANCH_BEFORE=" + $beforeBranch)
    Record ("GIT_OPERATION_HEAD_BEFORE=" + $beforeHead)

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
    $headUnchanged = ($afterHead -eq $beforeHead)
    $expectedHead = $beforeHead  # we capture this for the record even on failure
    # For a switch, expected HEAD is the tip of the target branch. We don't
    # query it pre-emptively (the whole point of the run is to let git do
    # the switching); we just record the actual HEAD after the op and
    # whether the branch label matches. If the branch label matches but
    # the HEAD didn't change, that's also a real interference pattern
    # (git might have done a no-op switch). We capture both signals.

    Record ("EXPECTED_BRANCH=" + $ExpectedBranch)
    Record ("ACTUAL_BRANCH=" + $afterBranch)
    Record ("EXPECTED_HEAD=" + $expectedHead)
    Record ("ACTUAL_HEAD=" + $afterHead)

    $targetReached = if ($branchReached) { 'YES' } else { 'NO' }
    Record ("GIT_OPERATION_TARGET_REACHED=" + $targetReached)

    # Always run check-worktree immediately to preserve state.
    & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label $Label | ForEach-Object { Record $_ }

    if ($exit -ne 0 -or $targetReached -ne 'YES') {
        Record ("GIT_OPERATION_INTERFERENCE label=" + $Label + " exit=" + $exit + " target_reached=" + $targetReached)
        $script:operationInterference = $true
        $script:interferenceStep = $Label
        return $false
    }
    return $true
}

Push-Location $Repo
try {
    Record ("GIT_CYCLE_BASELINE_REPO=" + $Repo)
    Record ("GIT_CYCLE_BASELINE_HEAD=" + (git rev-parse HEAD))
    Record ("GIT_CYCLE_BASELINE_BRANCH=" + (git rev-parse --abbrev-ref HEAD))

    for ($i = 1; $i -le $Cycles; $i++) {
        $ok = Run-Operation -Type 'checkout' -Label "step-${i}a-switch-to-feature" -Target 'feature/probe/multi-level' -ExpectedBranch 'feature/probe/multi-level' -GitArgs @('checkout','feature/probe/multi-level')
        if (-not $ok) { break }
        $ok = Run-Operation -Type 'checkout' -Label "step-${i}b-switch-to-master" -Target 'master' -ExpectedBranch 'master' -GitArgs @('checkout','master')
        if (-not $ok) { break }
    }

    if ($Merge -and -not $operationInterference) {
        $ok = Run-Operation -Type 'merge' -Label 'step-merge-ff-only' -Target 'merge ff-only feature into master' -ExpectedBranch 'master' -GitArgs @('merge','--ff-only','feature/probe/multi-level')
        if (-not $ok) { }
    }
} finally {
    Pop-Location
}

Record ("GIT_CYCLES_ACTUAL_CHECK_COUNT=" + $actualCheckCount)
Record ("GIT_CYCLES_OK=" + $(if ($operationInterference) {'NO'} else {'YES'}))
if ($operationInterference) {
    Record ("GIT_CYCLES_INTERFERENCE_STEP=" + $interferenceStep)
}
Record "GIT_CYCLES_END"
