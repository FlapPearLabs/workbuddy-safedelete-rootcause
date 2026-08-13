# build-git-probe.ps1
# Creates a fresh disposable Git repository with REAL branch delta:
#   - 60 tracked files on master (commit A)
#   - feature branch with:
#       * 25+ tracked files modified
#       * 5 tracked files deleted
#       * 8 new tracked files added
#       * 4 tracked files renamed
#   - master HEAD != feature HEAD (asserted)
#
# Usage:
#   .\build-git-probe.ps1 -Repo <path> [-BranchName feature/probe/multi-level]
#
# Output: emits BRANCH_DELTA_VALID=YES/NO and the two HEADs.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$BranchName = 'feature/probe/multi-level'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

# Refuse to use the real production path even as a build target
if ($Repo -match [regex]::Escape($script:ProductionRepoPath)) {
    throw "refusing to build a probe at the production path"
}

# Clean start
if (Test-Path $Repo) { mavis-trash $Repo }
New-Item -ItemType Directory -Path $Repo -Force | Out-Null
Push-Location $Repo
try {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git init -b master 2>&1 | Out-Null
    git config user.email "probe@workbuddy-rootcause-lab.invalid"
    git config user.name "WorkBuddy Root-Cause Lab"
    git config core.autocrlf false
    git config core.quotepath off

    Write-Output "GIT_PROBE_INIT_REPO=$Repo"

    # 60 tracked files on master: 25 src/, 25 test/, 10 docs/
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
    git commit -m "commit-A: 60 tracked files on master (25 src, 25 test, 10 docs)"
    $masterHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_MASTER_HEAD=$masterHead"

    # Create feature branch
    git checkout -b $BranchName 2>&1 | Out-Null

    # Modify 25+ tracked files
    1..25 | ForEach-Object {
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

    # Delete 5 tracked files (use git rm so the deletion is recorded)
    git rm "test/t16/spec.txt" "test/t17/spec.txt" "test/t18/spec.txt" "test/t19/spec.txt" "test/t20/spec.txt"

    # Add 8 new tracked files
    1..8 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("src/new" + $i + ".txt") -Value ("NEW-feature-src-$i") -Encoding ASCII -NoNewline
        Set-Content -LiteralPath ("test/new" + $i + ".txt") -Value ("NEW-feature-test-$i") -Encoding ASCII -NoNewline
    }
    # Note: src/ and test/ get 8+8=16 new files

    # Rename 4 tracked files (use git mv)
    git mv "docs/d09/note.txt" "docs/d09/note-renamed.txt"
    git mv "docs/d10/note.txt" "docs/d10/note-renamed.txt"
    git mv "src/a24/main.txt" "src/a24/main-renamed.txt"
    git mv "src/a25/main.txt" "src/a25/main-renamed.txt"

    git add -A 2>&1 | Out-Null
    git commit -m "commit-B: feature changes (modify 48, delete 5, add 16, rename 4)"
    $featureHead = git rev-parse HEAD
    Write-Output "GIT_PROBE_FEATURE_HEAD=$featureHead"

    if ($masterHead -eq $featureHead) {
        Write-Output "BRANCH_DELTA_VALID=NO"
        throw "build-git-probe: master HEAD and feature HEAD are identical; branch delta invalid"
    } else {
        Write-Output "BRANCH_DELTA_VALID=YES"
    }
    Write-Output "GIT_PROBE_MASTER_FILE_COUNT=" + (git ls-files | Measure-Object).Count
    Write-Output "GIT_PROBE_FEATURE_FILE_COUNT=" + (git ls-files | Measure-Object).Count

    # Return to master for the experiment start state
    git checkout master 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP
} finally {
    Pop-Location
}
