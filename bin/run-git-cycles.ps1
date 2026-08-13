# run-git-cycles.ps1
# Runs the Git A/B workload:
#   * 5 switch cycles (master <-> feature)
#   * 1 fast-forward merge
# Calls check-worktree.ps1 after every git operation, capturing per-step
# records that the orchestrator can parse.
#
# Usage:
#   .\run-git-cycles.ps1 -Repo <path> -Cycles 5 -OutputFile <path> [-Merge $true]

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
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null
"" | Set-Content $OutputFile -Encoding UTF8

function Record {
    param([string]$Line)
    Write-Output $Line
    Add-Content $OutputFile $Line -Encoding UTF8
}

Record "GIT_CYCLES_START repo=$Repo cycles=$Cycles merge=$Merge"
Push-Location $Repo
try {
    Record ("GIT_CYCLE_BASELINE_REPO=" + $Repo)
    Record ("GIT_CYCLE_BASELINE_HEAD=" + (git rev-parse HEAD))
    Record ("GIT_CYCLE_BASELINE_BRANCH=" + (git rev-parse --abbrev-ref HEAD))

    for ($i = 1; $i -le $Cycles; $i++) {
        Record ""
        Record "GIT_CYCLE_STEP step=switch-to-feature iteration=$i"
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        git checkout feature/probe/multi-level 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
        $h = git rev-parse HEAD
        $b = git rev-parse --abbrev-ref HEAD
        Record "GIT_CYCLE_STEP_AFTER_CHECKOUT_HEAD=$h"
        Record "GIT_CYCLE_STEP_AFTER_CHECKOUT_BRANCH=$b"
        & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label "step-${i}a-switch-to-feature" | ForEach-Object { Record $_ }

        Record ""
        Record "GIT_CYCLE_STEP step=switch-to-master iteration=$i"
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        git checkout master 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
        $h = git rev-parse HEAD
        $b = git rev-parse --abbrev-ref HEAD
        Record "GIT_CYCLE_STEP_AFTER_CHECKOUT_HEAD=$h"
        Record "GIT_CYCLE_STEP_AFTER_CHECKOUT_BRANCH=$b"
        & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label "step-${i}b-switch-to-master" | ForEach-Object { Record $_ }
    }

    if ($Merge) {
        Record ""
        Record "GIT_CYCLE_STEP step=ff-merge-feature-into-master"
        $beforeHead = git rev-parse HEAD
        Record "GIT_CYCLE_STEP_BEFORE_MERGE_HEAD=$beforeHead"
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $mergeOut = git merge --ff-only feature/probe/multi-level 2>&1 | Out-String
        $mergeExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        Record "GIT_CYCLE_STEP_MERGE_EXIT=$mergeExit"
        Record "GIT_CYCLE_STEP_MERGE_OUTPUT=" + ($mergeOut.Trim() -replace '\s+', ' ')
        $h = git rev-parse HEAD
        Record "GIT_CYCLE_STEP_AFTER_MERGE_HEAD=$h"
        & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label "step-merge-ff-only" | ForEach-Object { Record $_ }
    }
} finally {
    Pop-Location
}
Record "GIT_CYCLES_END"
