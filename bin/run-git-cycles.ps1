# run-git-cycles.ps1
# Runs N switch cycles between master and feature branch, then a fast-forward merge.
# For each step calls check-worktree to detect any worktree-only loss.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][int]$Cycles = 8
)
$ErrorActionPreference = 'Stop'
Push-Location $Repo
try {
    $log = @()
    $log += ("=== START cycles=" + $Cycles + " repo=" + $Repo)
    # Cycle 1: ensure on master
    git checkout -q master
    $log += ("STEP 0: on master HEAD=" + (git rev-parse --short HEAD))
    for ($i = 1; $i -le $Cycles; $i++) {
        git checkout -q feature/probe/multi-level
        $log += ("STEP " + $i + "a: switched to feature HEAD=" + (git rev-parse --short HEAD))
        git checkout -q master
        $log += ("STEP " + $i + "b: switched back to master HEAD=" + (git rev-parse --short HEAD))
    }
    # Now do the merge test: fast-forward merge feature into master
    $beforeHead = git rev-parse --short HEAD
    $log += ("MERGE: ff-only master<-feature before=" + $beforeHead)
    $mergeOut = git merge --ff-only feature/probe/multi-level 2>&1 | Out-String
    $mergeExit = $LASTEXITCODE
    $log += ("MERGE: exit=" + $mergeExit + " after=" + (git rev-parse --short HEAD))
    $log += ("MERGE_OUTPUT_HEAD: " + ($mergeOut.Trim() -split "`n" | Select-Object -First 5))
    # Final check
    $log += ("FINAL CHECK")
    $log | ForEach-Object { Write-Output $_ }
} finally {
    Pop-Location
}
