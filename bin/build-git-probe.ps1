# build-git-probe.ps1
# Initializes a fresh git repo at the supplied path with ~50 tracked files
# across src/, test/, and docs/, and creates an initial commit on master
# plus a feature branch with changes. This is the disposable probe used in
# the Git worktree experiment.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repo
)
$ErrorActionPreference = 'Stop'
if (Test-Path $Repo) { mavis-trash $Repo }
New-Item -ItemType Directory -Path $Repo -Force | Out-Null
Push-Location $Repo
try {
    git init -b master -q
    git config user.email "probe@workbuddy-rootcause-lab"
    git config user.name "WorkBuddy Root Cause Lab"
    git config core.autocrlf false
    # Create tracked files
    1..20 | ForEach-Object { New-Item -ItemType Directory -Path ("src/a" + $_.ToString('D2')) -Force | Out-Null }
    1..20 | ForEach-Object { New-Item -ItemType Directory -Path ("test/t" + $_.ToString('D2')) -Force | Out-Null }
    1..10 | ForEach-Object { New-Item -ItemType Directory -Path ("docs/d" + $_.ToString('D2')) -Force | Out-Null }
    1..20 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("src/a$($i)/main.txt") -Value ("A-$i master") -Encoding ASCII -NoNewline
    }
    1..20 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("test/t$($i)/spec.txt") -Value ("T-$i master") -Encoding ASCII -NoNewline
    }
    1..10 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("docs/d$($i)/note.txt") -Value ("D-$i master") -Encoding ASCII -NoNewline
    }
    # commit A on master
    git add -A 2>&1 | Out-Null
    git commit -q -m "commit-A: 50 tracked files on master"
    # create feature branch and modify
    git checkout -q -b feature/probe/multi-level
    1..20 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("src/a$($i)/main.txt") -Value ("A-$i feature") -Encoding ASCII -NoNewline
    }
    5..15 | ForEach-Object {
        $i = $_.ToString('D2')
        Set-Content -LiteralPath ("test/t$($i)/spec.txt") -Value ("T-$i feature") -Encoding ASCII -NoNewline
    }
    Set-Content -LiteralPath "docs/d01/note.txt" -Value "D-01 feature" -Encoding ASCII -NoNewline
    Set-Content -LiteralPath "docs/d05/note.txt" -Value "D-05 feature" -Encoding ASCII -NoNewline
    # add a new file
    Set-Content -LiteralPath "src/new01.txt" -Value "NEW feature" -Encoding ASCII -NoNewline
    Set-Content -LiteralPath "test/new01.txt" -Value "NEW feature test" -Encoding ASCII -NoNewline
    git add -A 2>&1 | Out-Null
    git commit -q -m "commit-B: feature changes (modify 26 + add 2)"
    # back to master for the experiment start state
    git checkout -q master
    Write-Output ("INITIALIZED: " + $Repo)
    Write-Output ("MASTER_HEAD=" + (git rev-parse HEAD))
    Write-Output ("FEATURE_HEAD=" + (git rev-parse feature/probe/multi-level))
} finally {
    Pop-Location
}
