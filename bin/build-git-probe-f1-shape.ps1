# build-git-probe-f1-shape.ps1
#
# Creates a fresh disposable Git repository shaped like the F1 natural
# incident (2026-08-14): a large existing worktree with many tracked
# files, plus a tiny 3-path fast-forward delta on the feature branch.
#
# Shape:
#   - master has at least 150 tracked files
#   - at least 60 files under test-like nested directories
#       (test/t01/spec.txt, test/t02/spec.txt, ..., test/t60/spec.txt)
#   - feature branch changes ONLY 3 paths:
#       * 1 existing src-like file modified
#       * 1 existing test-like file modified
#       * 1 new test-like file added
#   - zero intentional deletes
#
# This mirrors the observed F1 merge structure: large existing worktree
# + tiny 3-path FF delta + many unrelated test files present.
#
# No production source content is copied. All text is synthetic.
#
# Usage:
#   .\build-git-probe-f1-shape.ps1 -Repo <path> [-BranchName feature/probe/f1-shape]
#
# Output (structured, for the orchestrator / parser to consume):
#   GIT_PROBE_F1_SHAPE_INIT_REPO=<path>
#   GIT_PROBE_F1_SHAPE_MASTER_HEAD=<sha>
#   GIT_PROBE_F1_SHAPE_FEATURE_HEAD=<sha>
#   GIT_PROBE_F1_SHAPE_BASE_TRACKED_COUNT=<n>      # >= 150 required
#   GIT_PROBE_F1_SHAPE_TEST_LIKE_COUNT=<n>         # >= 60 required
#   GIT_PROBE_F1_SHAPE_CHANGED_PATH_COUNT=<n>       # == 3 required
#   GIT_PROBE_F1_SHAPE_DELETED_PATH_COUNT=<n>       # == 0 required
#   GIT_PROBE_F1_SHAPE_ADDED_PATH_COUNT=<n>         # == 1 required
#   GIT_PROBE_F1_SHAPE_MODIFIED_PATH_COUNT=<n>      # == 2 required
#   GIT_PROBE_F1_SHAPE_VALID=YES|NO
#   GIT_PROBE_F1_SHAPE_BUILD_OK=YES|NO

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$BranchName = 'feature/probe/f1-shape'
)
# Resolve to an absolute path so check-worktree (which re-pushes into $Repo)
# is robust regardless of the caller's current location.
$Repo = [System.IO.Path]::GetFullPath($Repo)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

# Hard min shape constants.
$MIN_BASE_TRACKED = 150
$MIN_TEST_LIKE   = 60
$REQUIRED_CHANGED = 3
$REQUIRED_DELETED = 0
$REQUIRED_ADDED   = 1
$REQUIRED_MODIFIED = 2

# Refuse to use the real production path even as a build target.
if ($Repo -match [regex]::Escape($script:ProductionRepoPath)) {
    throw "refusing to build an F1-shape probe at the production path"
}

# Per the release-gate P4 rule, do NOT mavis-trash an old Git probe
# before the experiment. The caller must pass a fresh unique dir
# (e.g. work/native-runs/<ts-guid>/git-probe). If the caller passes
# a path that already exists, we refuse rather than trash, so the
# caller can detect the collision and pick a new name.
if (Test-Path $Repo) {
    throw "build-git-probe-f1-shape: target path already exists; per P4 use a fresh unique dir. Path: $Repo"
}
New-Item -ItemType Directory -Path $Repo -Force | Out-Null
Push-Location $Repo
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git init -b master 2>&1 | Out-Null
    git config user.email 'probe@workbuddy-rootcause-lab.invalid'
    git config user.name  'WorkBuddy Root-Cause Lab'
    git config core.autocrlf  $false
    git config core.quotepath $off

    Write-Output "GIT_PROBE_F1_SHAPE_INIT_REPO=$Repo"

    # ── master base: 80 src/ + 60 test/ + 20 docs/ = 160 tracked files ──
    # All synthetic; no production content.
    1..80 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("src/m" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("src/m" + $i + "/main.txt") -Value ("m" + $i + " master original") -Encoding ASCII -NoNewline
    }
    1..60 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("test/t" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("test/t" + $i + "/spec.txt") -Value ("t" + $i + " master original") -Encoding ASCII -NoNewline
    }
    1..20 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("docs/d" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("docs/d" + $i + "/note.txt") -Value ("d" + $i + " master original") -Encoding ASCII -NoNewline
    }
    git add -A 2>&1 | Out-Null
    git commit -m 'commit-A: 160 tracked files (80 src, 60 test, 20 docs) — F1-shape base' 2>&1 | Out-Null
    $masterHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_F1_SHAPE_MASTER_HEAD=$masterHead"
    Write-Output ("GIT_PROBE_F1_SHAPE_BASE_TRACKED_COUNT=" + (git ls-files | Measure-Object).Count)

    # Count test-like files (anything under test/).
    $testLikeCount = (git ls-files | Where-Object { $_ -like 'test/*' } | Measure-Object).Count
    Write-Output ("GIT_PROBE_F1_SHAPE_TEST_LIKE_COUNT=" + $testLikeCount)

    # ── feature branch: tiny 3-path delta ──
    git checkout -b $BranchName 2>&1 | Out-Null

    # 1) existing src-like file modified: src/m01/main.txt
    Set-Content -LiteralPath 'src/m01/main.txt' -Value 'm01 feature modified' -Encoding ASCII -NoNewline

    # 2) existing test-like file modified: test/t01/spec.txt
    Set-Content -LiteralPath 'test/t01/spec.txt' -Value 't01 feature modified' -Encoding ASCII -NoNewline

    # 3) new test-like file added: test/t61/spec.txt
    New-Item -ItemType Directory -Path 'test/t61' -Force | Out-Null
    Set-Content -LiteralPath 'test/t61/spec.txt' -Value 't61 feature added' -Encoding ASCII -NoNewline

    git add -A 2>&1 | Out-Null
    git commit -m 'commit-B: F1-shape delta (modify 2 + add 1; no deletes)' 2>&1 | Out-Null
    $featureHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_F1_SHAPE_FEATURE_HEAD=$featureHead"

    # ── shape assertion via `git diff --name-status` ──
    if ($masterHead -eq $featureHead) {
        Write-Output "GIT_PROBE_F1_SHAPE_VALID=NO"
        throw "build-git-probe-f1-shape: master HEAD and feature HEAD are identical; delta invalid"
    }

    $diffStatus = git diff --name-status ($masterHead + '...' + $featureHead) 2>&1
    $modified = 0; $deleted = 0; $added = 0
    foreach ($line in $diffStatus) {
        if ($line -match '^([A-Z])') {
            switch ($matches[1]) {
                'M' { $modified++ }
                'D' { $deleted++  }
                'A' { $added++    }
            }
        }
    }
    Write-Output ("GIT_PROBE_F1_SHAPE_CHANGED_PATH_COUNT=" + ($modified + $deleted + $added))
    Write-Output ("GIT_PROBE_F1_SHAPE_MODIFIED_PATH_COUNT=" + $modified)
    Write-Output ("GIT_PROBE_F1_SHAPE_DELETED_PATH_COUNT="  + $deleted)
    Write-Output ("GIT_PROBE_F1_SHAPE_ADDED_PATH_COUNT="    + $added)

    $baseOk = ((git ls-files | Measure-Object).Count -ge $MIN_BASE_TRACKED)
    $testOk = ($testLikeCount -ge $MIN_TEST_LIKE)
    $changedOk = (($modified + $deleted + $added) -eq $REQUIRED_CHANGED)
    $delOk = ($deleted -eq $REQUIRED_DELETED)
    $addOk = ($added -eq $REQUIRED_ADDED)
    $modOk = ($modified -eq $REQUIRED_MODIFIED)
    if ($baseOk -and $testOk -and $changedOk -and $delOk -and $addOk -and $modOk) {
        Write-Output "GIT_PROBE_F1_SHAPE_VALID=YES"
        Write-Output "GIT_PROBE_F1_SHAPE_BUILD_OK=YES"
    } else {
        Write-Output "GIT_PROBE_F1_SHAPE_VALID=NO"
        Write-Output "GIT_PROBE_F1_SHAPE_BUILD_OK=NO"
        throw ("build-git-probe-f1-shape: shape invalid (base=" + (git ls-files | Measure-Object).Count + ">=" + $MIN_BASE_TRACKED + " testLike=" + $testLikeCount + ">=" + $MIN_TEST_LIKE + " changed=" + ($modified + $deleted + $added) + "==" + $REQUIRED_CHANGED + " deleted=" + $deleted + "==" + $REQUIRED_DELETED + " added=" + $added + "==" + $REQUIRED_ADDED + " modified=" + $modified + "==" + $REQUIRED_MODIFIED + ")")
    }

    # ── REPAIR A: post-build physical baseline on master ──
    # Run check-worktree immediately after the final `git checkout master`
    # so the orchestrator can distinguish a build-phase loss (P1-1 CASE A)
    # from a first-cycle-checkout loss (P1-1 CASE B). A structurally valid
    # 3-path diff alone is NOT sufficient for WORKTREE_READY=YES.
    $prevEAP2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $null = git checkout master 2>&1 | Out-String
    $buildFinalCheckoutExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP2

    $buildFinalExpectedBranch = 'master'
    $buildFinalExpectedHead   = $masterHead
    $buildFinalActualBranch   = (git rev-parse --abbrev-ref HEAD 2>$null)
    $buildFinalActualHead     = (git rev-parse HEAD 2>$null)
    $buildFinalTargetReached  = if (($buildFinalActualBranch -eq 'master') -and ($buildFinalActualHead -eq $buildFinalExpectedHead)) { 'YES' } else { 'NO' }

    Write-Output ("BUILD_FINAL_CHECKOUT_EXIT=" + $buildFinalCheckoutExit)
    Write-Output ("BUILD_FINAL_EXPECTED_BRANCH=" + $buildFinalExpectedBranch)
    Write-Output ("BUILD_FINAL_ACTUAL_BRANCH=" + $buildFinalActualBranch)
    Write-Output ("BUILD_FINAL_EXPECTED_HEAD=" + $buildFinalExpectedHead)
    Write-Output ("BUILD_FINAL_ACTUAL_HEAD=" + $buildFinalActualHead)
    Write-Output ("BUILD_FINAL_TARGET_REACHED=" + $buildFinalTargetReached)

    # Full WORKTREE_CHECK_* record for the post-build master baseline.
    $buildFinalCheckOut = $null
    try {
        $buildFinalCheckOut = & "$PSScriptRoot\check-worktree.ps1" -Repo $Repo -Label 'build-final-master-baseline' 2>&1
    } catch {
        Write-Output ("WORKTREE_CHECK_SCRIPT_ERROR label=build-final-master-baseline type=" + $_.Exception.GetType().FullName + " message=" + $_.Exception.Message)
        $buildFinalCheckOut = @()
    }
    if ($buildFinalCheckOut) { foreach ($l in $buildFinalCheckOut) { Write-Output $l } }

    $finalVerdict = 'UNKNOWN'; $finalMissing = -1; $finalMatch = 'NO'; $finalFsck = 'NO'
    if ($buildFinalCheckOut) {
        foreach ($l in $buildFinalCheckOut) {
            if ($l -match '^WORKTREE_CHECK_VERDICT\s+label=build-final-master-baseline\s+value=(\S+)') { $finalVerdict = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_MISSING_COUNT=(\d+)') { $finalMissing = [int]$matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=(\S+)') { $finalMatch = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_FSCK_HEALTHY=(\S+)') { $finalFsck = $matches[1] }
        }
    }

    Write-Output ("GIT_PROBE_F1_SHAPE_FINAL_WORKTREE_VERDICT=" + $finalVerdict)
    Write-Output ("GIT_PROBE_F1_SHAPE_FINAL_MISSING_COUNT=" + $finalMissing)
    Write-Output ("GIT_PROBE_F1_SHAPE_FINAL_HEAD_INDEX_TREE_MATCH=" + $finalMatch)
    Write-Output ("GIT_PROBE_F1_SHAPE_FINAL_FSCK_HEALTHY=" + $finalFsck)

    # WORKTREE_READY=YES requires a clean physical master worktree on top of a
    # structurally valid 3-path diff. Otherwise the caller MUST NOT start cycles.
    $buildFinalReady = $false
    if (($buildFinalCheckoutExit -eq 0) -and
        ($buildFinalTargetReached -eq 'YES') -and
        ($finalVerdict -eq 'CLEAN') -and
        ($finalMissing -eq 0) -and
        ($finalMatch -eq 'YES') -and
        ($finalFsck -eq 'YES')) {
        $buildFinalReady = $true
    }
    Write-Output ("GIT_PROBE_F1_SHAPE_WORKTREE_READY=" + $(if ($buildFinalReady) { 'YES' } else { 'NO' }))
    if (-not $buildFinalReady) {
        # Localization signal: the build sequence itself left the master
        # worktree non-clean. Caller must treat this as BUILD_FINAL_WORKTREE_INTERFERENCE
        # and preserve evidence; do NOT start mutation cycles.
        Write-Output "GIT_PROBE_F1_SHAPE_BUILD_FINAL_WORKTREE_INTERFERENCE=YES"
    }

    $ErrorActionPreference = $prevEAP
} finally {
    Pop-Location
}
