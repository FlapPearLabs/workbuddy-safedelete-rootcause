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
# R2 LOCALIZATION INSTRUMENTATION
# -------------------------------
# This builder now emits FOUR physical checkpoints (A/B/C/D) so the exact
# CLEAN->NON_CLEAN transition can be localized inside the build sequence:
#
#   A: after commit-A on master, before creating the feature branch
#   B: after `git checkout -b <feature>`, before the 3-path edits
#   C: after commit-B + shape assertion, before `git checkout master`
#   D: after the final `git checkout master`
#
# Each checkpoint runs bin/check-worktree.ps1 and records physical state
# (HEAD=yes/index=yes/PHYSICAL=no is exactly the bug under investigation,
# so GIT tree/index presence does NOT prove physical file presence).
#
# The builder STOPS at the first non-CLEAN checkpoint (or at the first
# instrumentation error) and preserves evidence; it does NOT keep mutating
# the synthetic repo to accumulate more failures.
#
# Usage:
#   .\build-git-probe-f1-shape.ps1 -Repo <path> [-BranchName feature-probe-f1shape]
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
#   <CHECKPOINT_A/B/C/D fields>
#   <FINAL_CHECKOUT fields>
#   FIRST_KNOWN_NON_CLEAN_CHECKPOINT=
#   FIRST_CLEAN_TO_NONCLEAN_INTERVAL=
#   LOSS_LOCALIZED_TO_FINAL_CHECKOUT_INTERVAL=
#   WORKTREE_INTERFERENCE=
#   CLASSIFICATION=

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$BranchName = 'feature-probe-f1shape'
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

# ─────────────────────────────────────────────────────────────────────────
# Invoke-WorktreeCheckpoint
#   Runs bin/check-worktree.ps1 for one named label and emits the
#   CHECKPOINT_<PREFIX>_* record. On a checker throw it sets
#   CHECK_STATUS=ERROR (never WORKTREE_INTERFERENCE=YES) and records the
#   sanitized exception type/message.
# ─────────────────────────────────────────────────────────────────────────
function Invoke-WorktreeCheckpoint {
    param(
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$RepoPath,
        [Parameter(Mandatory=$true)][ref]$Result
    )
    $out = $null
    $checkStatus = 'OK'
    $errType = ''
    $errMsg = ''
    try {
        $out = & "$PSScriptRoot\check-worktree.ps1" -Repo $RepoPath -Label $Label 2>&1
    } catch {
        $checkStatus = 'ERROR'
        $errType = $_.Exception.GetType().FullName
        # Sanitized: type + message only; never include command lines / secrets.
        $errMsg = $_.Exception.Message
    }

    # Echo the raw checker record for traceability (parser/offline re-use).
    if ($out) { foreach ($l in $out) { Write-Output $l } }

    $verdict = 'UNKNOWN'; $missing = -1; $match = 'NO'; $fsck = 'NO'; $branch = ''; $head = ''
    if ($checkStatus -eq 'OK') {
        foreach ($l in $out) {
            if ($l -match '^WORKTREE_CHECK_VERDICT\s+label=(\S+)\s+value=(\S+)') { $verdict = $matches[2] }
            elseif ($l -match '^WORKTREE_CHECK_MISSING_COUNT=(\d+)') { $missing = [int]$matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=(\S+)') { $match = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_FSCK_HEALTHY=(\S+)') { $fsck = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_BRANCH=(\S+)') { $branch = $matches[1] }
            elseif ($l -match '^WORKTREE_CHECK_HEAD=(\S+)') { $head = $matches[1] }
        }
    }

    Write-Output ($Prefix + "_LABEL=" + $Label)
    Write-Output ($Prefix + "_CHECK_STATUS=" + $checkStatus)
    if ($checkStatus -eq 'ERROR') {
        Write-Output ($Prefix + "_CHECK_ERROR_TYPE=" + $errType)
        Write-Output ($Prefix + "_CHECK_ERROR_MESSAGE=" + $errMsg)
        Write-Output ($Prefix + "_VERDICT=UNKNOWN")
        Write-Output ($Prefix + "_MISSING_COUNT=-1")
        Write-Output ($Prefix + "_HEAD_INDEX_TREE_MATCH=NO")
        Write-Output ($Prefix + "_FSCK_HEALTHY=NO")
        Write-Output ($Prefix + "_BRANCH=")
        Write-Output ($Prefix + "_HEAD=")
    } else {
        Write-Output ($Prefix + "_BRANCH=" + $branch)
        Write-Output ($Prefix + "_HEAD=" + $head)
        Write-Output ($Prefix + "_VERDICT=" + $verdict)
        Write-Output ($Prefix + "_MISSING_COUNT=" + $missing)
        Write-Output ($Prefix + "_HEAD_INDEX_TREE_MATCH=" + $match)
        Write-Output ($Prefix + "_FSCK_HEALTHY=" + $fsck)
    }

    $Result.Value = [PSCustomObject]@{
        CheckStatus = $checkStatus
        Verdict     = $verdict
        Missing     = $missing
        Match       = $match
        Fsck        = $fsck
        Branch      = $branch
        Head        = $head
        ErrType     = $errType
        ErrMsg      = $errMsg
    }
}

# Emit the standardized stop/localization markers exactly once.
function Emit-StopMarkers {
    param(
        [string]$FirstNonClean,
        [string]$Interval,
        [string]$LocalizedFinal,
        [string]$Interference,
        [string]$Classification
    )
    Write-Output ("FIRST_KNOWN_NON_CLEAN_CHECKPOINT=" + $FirstNonClean)
    Write-Output ("FIRST_CLEAN_TO_NONCLEAN_INTERVAL=" + $Interval)
    Write-Output ("LOSS_LOCALIZED_TO_FINAL_CHECKOUT_INTERVAL=" + $LocalizedFinal)
    Write-Output ("WORKTREE_INTERFERENCE=" + $Interference)
    Write-Output ("CLASSIFICATION=" + $Classification)
}

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

    # ── CHECKPOINT A: after commit-A on master, BEFORE feature branch ──
    $cpa = $null
    Invoke-WorktreeCheckpoint -Prefix 'CHECKPOINT_A' -Label 'build-master-after-commit-a' -RepoPath $Repo -Result ([ref]$cpa)
    if ($cpa.CheckStatus -eq 'ERROR') {
        Emit-StopMarkers -FirstNonClean 'A' -Interval 'UNKNOWN' -LocalizedFinal 'NO' -Interference 'UNKNOWN' -Classification 'INSTRUMENTATION_ERROR'
        $ErrorActionPreference = $prevEAP
        return
    }
    if ($cpa.Verdict -ne 'CLEAN') {
        # A non-CLEAN -> STOP. The loss happened at/before commit-A sequence.
        Emit-StopMarkers -FirstNonClean 'A' -Interval 'NOT_LOCALIZED_BEFORE_A' -LocalizedFinal 'NO' -Interference 'YES' -Classification 'BUILD_MASTER_AFTER_COMMIT_A_NON_CLEAN'
        $ErrorActionPreference = $prevEAP
        return
    }

    # ── feature branch: tiny 3-path delta ──
    # Capture the initial feature checkout explicitly (FEATURE_CHECKOUT_*).
    $featPrevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $null = git checkout -b $BranchName 2>&1 | Out-String
    $featureCheckoutExit = $LASTEXITCODE
    $ErrorActionPreference = $featPrevEAP

    $featureExpectedBranch = $BranchName
    $featureExpectedHead   = $masterHead
    $featureActualBranch   = (git rev-parse --abbrev-ref HEAD 2>$null)
    $featureActualHead     = (git rev-parse HEAD 2>$null)
    $featureTargetReached  = if (($featureActualBranch -eq $featureExpectedBranch) -and ($featureActualHead -eq $featureExpectedHead)) { 'YES' } else { 'NO' }

    Write-Output ("FEATURE_CHECKOUT_EXIT=" + $featureCheckoutExit)
    Write-Output ("FEATURE_CHECKOUT_EXPECTED_BRANCH=" + $featureExpectedBranch)
    Write-Output ("FEATURE_CHECKOUT_ACTUAL_BRANCH=" + $featureActualBranch)
    Write-Output ("FEATURE_CHECKOUT_EXPECTED_HEAD=" + $featureExpectedHead)
    Write-Output ("FEATURE_CHECKOUT_ACTUAL_HEAD=" + $featureActualHead)
    Write-Output ("FEATURE_CHECKOUT_TARGET_REACHED=" + $featureTargetReached)

    # ── CHECKPOINT B: after `git checkout -b`, BEFORE the 3-path edits ──
    $cpb = $null
    Invoke-WorktreeCheckpoint -Prefix 'CHECKPOINT_B' -Label 'build-feature-after-initial-checkout' -RepoPath $Repo -Result ([ref]$cpb)
    if ($cpb.CheckStatus -eq 'ERROR') {
        Emit-StopMarkers -FirstNonClean 'B' -Interval 'UNKNOWN' -LocalizedFinal 'NO' -Interference 'UNKNOWN' -Classification 'INSTRUMENTATION_ERROR'
        $ErrorActionPreference = $prevEAP
        return
    }
    if ($cpb.Verdict -ne 'CLEAN') {
        # A=CLEAN, B=NON_CLEAN -> localized to the initial feature checkout.
        Emit-StopMarkers -FirstNonClean 'B' -Interval 'INITIAL_FEATURE_CHECKOUT' -LocalizedFinal 'NO' -Interference 'YES' -Classification 'BUILD_FEATURE_INITIAL_CHECKOUT_NON_CLEAN'
        $ErrorActionPreference = $prevEAP
        return
    }

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

    # ── CHECKPOINT C: after commit-B + shape assertion, BEFORE `git checkout master` ──
    $cpc = $null
    Invoke-WorktreeCheckpoint -Prefix 'CHECKPOINT_C' -Label 'build-feature-pre-final-checkout' -RepoPath $Repo -Result ([ref]$cpc)
    if ($cpc.CheckStatus -eq 'ERROR') {
        Emit-StopMarkers -FirstNonClean 'C' -Interval 'UNKNOWN' -LocalizedFinal 'NO' -Interference 'UNKNOWN' -Classification 'INSTRUMENTATION_ERROR'
        $ErrorActionPreference = $prevEAP
        return
    }
    if ($cpc.Verdict -ne 'CLEAN') {
        # A=CLEAN, B=CLEAN, C=NON_CLEAN -> localized to feature edit/add/commit sequence.
        Emit-StopMarkers -FirstNonClean 'C' -Interval 'FEATURE_EDIT_ADD_COMMIT_SEQUENCE' -LocalizedFinal 'NO' -Interference 'YES' -Classification 'BUILD_FEATURE_EDIT_ADD_COMMIT_NON_CLEAN'
        $ErrorActionPreference = $prevEAP
        return
    }

    # ── FINAL CHECKOUT: `git checkout master` (only reached if A/B/C CLEAN) ──
    $finPrevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $null = git checkout master 2>&1 | Out-String
    $finalCheckoutExit = $LASTEXITCODE
    $ErrorActionPreference = $finPrevEAP

    $finalExpectedBranch = 'master'
    $finalExpectedHead   = $masterHead
    $finalActualBranch   = (git rev-parse --abbrev-ref HEAD 2>$null)
    $finalActualHead     = (git rev-parse HEAD 2>$null)
    $finalTargetReached  = if (($finalActualBranch -eq 'master') -and ($finalActualHead -eq $finalExpectedHead)) { 'YES' } else { 'NO' }

    Write-Output ("FINAL_CHECKOUT_EXIT=" + $finalCheckoutExit)
    Write-Output ("FINAL_CHECKOUT_EXPECTED_BRANCH=" + $finalExpectedBranch)
    Write-Output ("FINAL_CHECKOUT_ACTUAL_BRANCH=" + $finalActualBranch)
    Write-Output ("FINAL_CHECKOUT_EXPECTED_HEAD=" + $finalExpectedHead)
    Write-Output ("FINAL_CHECKOUT_ACTUAL_HEAD=" + $finalActualHead)
    Write-Output ("FINAL_CHECKOUT_TARGET_REACHED=" + $finalTargetReached)

    # ── CHECKPOINT D: immediately after the final checkout ──
    $cpd = $null
    Invoke-WorktreeCheckpoint -Prefix 'CHECKPOINT_D' -Label 'build-master-post-final-checkout' -RepoPath $Repo -Result ([ref]$cpd)
    if ($cpd.CheckStatus -eq 'ERROR') {
        Emit-StopMarkers -FirstNonClean 'D' -Interval 'UNKNOWN' -LocalizedFinal 'NO' -Interference 'UNKNOWN' -Classification 'INSTRUMENTATION_ERROR'
        $ErrorActionPreference = $prevEAP
        return
    }

    # WORKTREE_READY=YES requires a clean physical master worktree on top of a
    # structurally valid 3-path diff. A structurally valid diff alone is NOT enough.
    $finalReady = $false
    if (($finalCheckoutExit -eq 0) -and ($finalTargetReached -eq 'YES') -and
        ($cpd.Verdict -eq 'CLEAN') -and ($cpd.Missing -eq 0) -and
        ($cpd.Match -eq 'YES') -and ($cpd.Fsck -eq 'YES')) {
        $finalReady = $true
    }
    Write-Output ("GIT_PROBE_F1_SHAPE_WORKTREE_READY=" + $(if ($finalReady) { 'YES' } else { 'NO' }))

    if ($cpd.Verdict -ne 'CLEAN') {
        if (($finalCheckoutExit -eq 0) -and ($finalTargetReached -eq 'YES')) {
            # CASE 4 (desired): A/B/C CLEAN, final checkout reached, D non-CLEAN.
            Emit-StopMarkers -FirstNonClean 'D' -Interval 'FINAL_GIT_CHECKOUT_MASTER' -LocalizedFinal 'YES' -Interference 'YES' -Classification 'BUILD_FINAL_CHECKOUT_WORKTREE_ONLY_LOSS'
        } else {
            # Final checkout did not reach master cleanly; cannot attribute to it.
            Emit-StopMarkers -FirstNonClean 'D' -Interval 'FINAL_CHECKOUT_TARGET_NOT_REACHED' -LocalizedFinal 'NO' -Interference 'YES' -Classification 'BUILD_FINAL_CHECKOUT_NON_CLEAN_TARGET_UNREACHED'
        }
        Write-Output "GIT_PROBE_F1_SHAPE_BUILD_FINAL_WORKTREE_INTERFERENCE=YES"
        $ErrorActionPreference = $prevEAP
        return
    }

    # CASE 5: all A/B/C/D CLEAN -> the build did not reproduce the loss in this run.
    Write-Output "NATIVE_RERUN_NOT_REPRODUCED_IN_ONE_RUN=YES"
    Write-Output "GIT_PROBE_F1_SHAPE_BUILD_ALL_CHECKPOINTS_CLEAN=YES"

    $ErrorActionPreference = $prevEAP
} finally {
    Pop-Location
}
