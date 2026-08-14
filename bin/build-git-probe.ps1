# build-git-probe.ps1
#
# Creates a fresh disposable Git repository with REAL branch delta:
#   - 60 tracked files on master (commit A)
#   - feature branch with:
#       * 46 tracked files modified
#       * 5 tracked files deleted
#       * 16 new tracked files added
#       * 4 tracked files renamed
#   - master HEAD != feature HEAD (asserted)
#   - delta shape: modified>=40, deleted>=5, added>=16, renamed>=4 (asserted)
#
# Usage:
#   .\build-git-probe.ps1 -Repo <path> [-BranchName feature/probe/multi-level]
#
# Output (structured, for the orchestrator / parser to consume):
#   GIT_PROBE_INIT_REPO=<path>
#   GIT_PROBE_MASTER_HEAD=<sha>
#   GIT_PROBE_FEATURE_HEAD=<sha>
#   GIT_PROBE_MASTER_FILE_COUNT=<n>
#   GIT_PROBE_FEATURE_FILE_COUNT=<n>
#   GIT_PROBE_BRANCH_DELTA_VALID=YES|NO
#   GIT_PROBE_DELTA_MODIFIED=<n>
#   GIT_PROBE_DELTA_DELETED=<n>
#   GIT_PROBE_DELTA_ADDED=<n>
#   GIT_PROBE_DELTA_RENAMED=<n>
#   GIT_PROBE_DELTA_SHAPE_VALID=YES|NO
#   GIT_PROBE_BUILD_OK=YES|NO

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$BranchName = 'feature/probe/multi-level'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

# Refuse to use the real production path even as a build target.
if ($Repo -match [regex]::Escape($script:ProductionRepoPath)) {
    throw "refusing to build a probe at the production path"
}

# Hard min shape constants. If the actual delta is below these, FAIL BUILD.
$MIN_MODIFIED = 40
$MIN_DELETED  = 5
$MIN_ADDED    = 16
$MIN_RENAMED  = 4

# Per the release-gate P4 rule, do NOT mavis-trash an old Git probe
# before the experiment. The caller must pass a fresh unique dir
# (e.g. work/native-runs/<ts-guid>/git-probe). If the caller passes
# a path that already exists, we refuse rather than trash, so the
# caller can detect the collision and pick a new name.
if (Test-Path $Repo) {
    throw "build-git-probe: target path already exists; per P4 use a fresh unique dir. Path: $Repo"
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

    Write-Output "GIT_PROBE_INIT_REPO=$Repo"

    # ── 60 tracked files on master: 25 src/, 25 test/, 10 docs/ ──
    1..25 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("src/a" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("src/a" + $i + "/main.txt") -Value ("A-$i master original") -Encoding ASCII -NoNewline
    }
    1..25 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("test/t" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("test/t" + $i + "/spec.txt") -Value ("T-$i master original") -Encoding ASCII -NoNewline
    }
    1..10 | ForEach-Object {
        $i = $_.ToString('D2')
        New-Item -ItemType Directory -Path ("docs/d" + $i) -Force | Out-Null
        Set-Content -LiteralPath ("docs/d" + $i + "/note.txt") -Value ("D-$i master original") -Encoding ASCII -NoNewline
    }
    git add -A 2>&1 | Out-Null
    git commit -m 'commit-A: 60 tracked files on master (25 src, 25 test, 10 docs)' 2>&1 | Out-Null
    $masterHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_MASTER_HEAD=$masterHead"

    # ── feature branch ──
    git checkout -b $BranchName 2>&1 | Out-Null

    # 46 modified tracked files: 23 src (skip a24/a25 because those are renames)
    #                          + 15 test
    #                          + 8 docs
    1..23 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("src/a" + $i + "/main.txt") -Value ("A-$i feature modified") -Encoding ASCII -NoNewline
    }
    1..15 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("test/t" + $i + "/spec.txt") -Value ("T-$i feature modified") -Encoding ASCII -NoNewline
    }
    1..8 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("docs/d" + $i + "/note.txt") -Value ("D-$i feature modified") -Encoding ASCII -NoNewline
    }

    # 5 deleted tracked files.
    git rm "test/t16/spec.txt" "test/t17/spec.txt" "test/t18/spec.txt" "test/t19/spec.txt" "test/t20/spec.txt" 2>&1 | Out-Null

    # 16 new tracked files: 8 in src/ + 8 in test/.
    1..8 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("src/new" + $i + ".txt") -Value ("NEW-feature-src-$i") -Encoding ASCII -NoNewline
        Set-Content -LiteralPath ("test/new" + $i + ".txt") -Value ("NEW-feature-test-$i") -Encoding ASCII -NoNewline
    }

    # 4 renames.
    git mv "docs/d09/note.txt"  "docs/d09/note-renamed.txt"  2>&1 | Out-Null
    git mv "docs/d10/note.txt"  "docs/d10/note-renamed.txt"  2>&1 | Out-Null
    git mv "src/a24/main.txt"   "src/a24/main-renamed.txt"   2>&1 | Out-Null
    git mv "src/a25/main.txt"   "src/a25/main-renamed.txt"   2>&1 | Out-Null

    git add -A 2>&1 | Out-Null
    git commit -m 'commit-B: feature changes (modify 46, delete 5, add 16, rename 4)' 2>&1 | Out-Null
    $featureHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_FEATURE_HEAD=$featureHead"

    # ── branch delta assertion ──
    if ($masterHead -eq $featureHead) {
        Write-Output "GIT_PROBE_BRANCH_DELTA_VALID=NO"
        throw "build-git-probe: master HEAD and feature HEAD are identical; branch delta invalid"
    } else {
        Write-Output "GIT_PROBE_BRANCH_DELTA_VALID=YES"
    }

    Write-Output ("GIT_PROBE_MASTER_FILE_COUNT=" + (git ls-files | Measure-Object).Count)
    Write-Output ("GIT_PROBE_FEATURE_FILE_COUNT=" + (git ls-files | Measure-Object).Count)

    # ── delta shape assertion (P1-3B) ─────────────────────────────────
    # `git diff --name-status master...feature` output:
    #   M<TAB>path
    #   D<TAB>path
    #   A<TAB>path
    #   R<TAB>score<TAB>old<TAB>new   (we count 1 per R line, regardless of score)
    #   C<TAB>score<TAB>...           (we count as added)
    $diffStatus = git diff --name-status ($masterHead + '...' + $featureHead) 2>&1
    $modified = 0; $deleted = 0; $added = 0; $renamed = 0
    foreach ($line in $diffStatus) {
        if ($line -match '^([A-Z])') {
            $code = $matches[1]
            switch ($code) {
                'M' { $modified++ }
                'D' { $deleted++  }
                'A' { $added++    }
                'R' { $renamed++  }
                'C' { $added++    }
            }
        }
    }
    Write-Output ("GIT_PROBE_DELTA_MODIFIED=" + $modified)
    Write-Output ("GIT_PROBE_DELTA_DELETED="  + $deleted)
    Write-Output ("GIT_PROBE_DELTA_ADDED="    + $added)
    Write-Output ("GIT_PROBE_DELTA_RENAMED="  + $renamed)

    $shapeValid = ($modified -ge $MIN_MODIFIED) -and ($deleted -ge $MIN_DELETED) -and ($added -ge $MIN_ADDED) -and ($renamed -ge $MIN_RENAMED)
    if ($shapeValid) {
        Write-Output "GIT_PROBE_DELTA_SHAPE_VALID=YES"
        Write-Output "GIT_PROBE_BUILD_OK=YES"
    } else {
        Write-Output "GIT_PROBE_DELTA_SHAPE_VALID=NO"
        Write-Output "GIT_PROBE_BUILD_OK=NO"
        throw "build-git-probe: delta shape invalid (modified=$modified>=$MIN_MODIFIED, deleted=$deleted>=$MIN_DELETED, added=$added>=$MIN_ADDED, renamed=$renamed>=$MIN_RENAMED)"
    }

    # Return to master so the experiment starts from a known state.
    git checkout master 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP
} finally {
    Pop-Location
}
