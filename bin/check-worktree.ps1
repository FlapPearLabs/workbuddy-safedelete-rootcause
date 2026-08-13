# check-worktree.ps1
# Comprehensive Git worktree integrity check. Emits a structured, machine-readable
# record of:
#   HEAD / INDEX / PHYSICAL state for every tracked file
#   Classifies each missing file as WORKTREE_ONLY_LOSS / INDEX_LOSS / HEAD_LOSS
#   git status (porcelain v1)
#   git fsck (no-reflogs)
#   git ls-files --error-unmatch for each missing path
#
# Usage:
#   .\check-worktree.ps1 -Repo <path> [-Label "step description"]
#
# Output: lines beginning with WORKTREE_CHECK_... for the orchestrator to parse.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$Label = ''
)
$ErrorActionPreference = 'Stop'
Push-Location $Repo
try {
    $tracked = @(git ls-files)
    Write-Output ("WORKTREE_CHECK_LABEL=" + $Label)
    Write-Output ("WORKTREE_CHECK_REPO=" + $Repo)
    Write-Output ("WORKTREE_CHECK_HEAD=" + (git rev-parse HEAD))
    Write-Output ("WORKTREE_CHECK_BRANCH=" + (git rev-parse --abbrev-ref HEAD))
    # HEAD tree: parse `git ls-tree HEAD` to get the root tree's SHA
    # `git ls-tree HEAD` outputs lines like: "040000 tree <sha>\t<name>"
    $lsTreeOut = git ls-tree HEAD
    $headTreeSha = ''
    foreach ($line in $lsTreeOut) {
        if ($line -match '^[0-7]{6}\s+tree\s+([0-9a-f]{40})\s') {
            $headTreeSha = $matches[1]
            break
        }
    }
    Write-Output ("WORKTREE_CHECK_HEAD_TREE=" + $headTreeSha)
    Write-Output ("WORKTREE_CHECK_INDEX_TREE=" + (git write-tree))
    Write-Output ("WORKTREE_CHECK_TRACKED_COUNT=" + $tracked.Count)

    $physical = 0
    $worktreeOnlyLoss = New-Object System.Collections.Generic.List[object]
    $indexOnlyLoss = New-Object System.Collections.Generic.List[object]
    $headOnlyLoss = New-Object System.Collections.Generic.List[object]
    $totalMissing = New-Object System.Collections.Generic.List[object]

    foreach ($f in $tracked) {
        $exists = Test-Path -LiteralPath $f
        if ($exists) { $physical++; continue }

        $totalMissing.Add($f) | Out-Null
        # Classify
        $headHas = $false
        $indexHas = $false
        try { $headHas = [bool](git ls-files --error-unmatch -- "$f" 2>$null) } catch {}
        try {
            $null = git show "HEAD:$f" 2>$null
            if ($LASTEXITCODE -eq 0) { $headHas = $true }
        } catch { $headHas = $false }
        try {
            $null = git show ":$f" 2>$null
            if ($LASTEXITCODE -eq 0) { $indexHas = $true }
        } catch { $indexHas = $false }
        if ($headHas -and $indexHas) {
            $worktreeOnlyLoss.Add([PSCustomObject]@{ Path = $f; Classification = 'WORKTREE_ONLY_LOSS' }) | Out-Null
        } elseif ($indexHas -and -not $headHas) {
            $indexOnlyLoss.Add([PSCustomObject]@{ Path = $f; Classification = 'INDEX_ONLY_LOSS' }) | Out-Null
        } elseif ($headHas -and -not $indexHas) {
            $headOnlyLoss.Add([PSCustomObject]@{ Path = $f; Classification = 'HEAD_ONLY_LOSS' }) | Out-Null
        } else {
            # Both missing: tracked file with no blob
            $worktreeOnlyLoss.Add([PSCustomObject]@{ Path = $f; Classification = 'TRACKED_BUT_BOTH_MISSING' }) | Out-Null
        }
    }
    Write-Output ("WORKTREE_CHECK_PHYSICAL_COUNT=" + $physical)
    Write-Output ("WORKTREE_CHECK_MISSING_COUNT=" + $totalMissing.Count)
    Write-Output ("WORKTREE_CHECK_WORKTREE_ONLY_LOSS_COUNT=" + $worktreeOnlyLoss.Count)
    Write-Output ("WORKTREE_CHECK_INDEX_ONLY_LOSS_COUNT=" + $indexOnlyLoss.Count)
    Write-Output ("WORKTREE_CHECK_HEAD_ONLY_LOSS_COUNT=" + $headOnlyLoss.Count)
    foreach ($m in $worktreeOnlyLoss) { Write-Output ("WORKTREE_CHECK_MISSING_WORKTREE_ONLY " + $m.Path) }
    foreach ($m in $indexOnlyLoss)   { Write-Output ("WORKTREE_CHECK_MISSING_INDEX_ONLY " + $m.Path) }
    foreach ($m in $headOnlyLoss)    { Write-Output ("WORKTREE_CHECK_MISSING_HEAD_ONLY " + $m.Path) }

    # git status (porcelain v1)
    $statusLines = git status --porcelain=v1 2>$null
    $dCount = 0; $mCount = 0; $uuCount = 0; $aCount = 0
    foreach ($line in $statusLines) {
        if ($line -match '^.D') { $dCount++ }
        elseif ($line -match '^D.') { $dCount++ }
        elseif ($line -match '^.M' -or $line -match '^M.') { $mCount++ }
        elseif ($line -match '^UU|^AA|^DD|^AU|^UA|^UD|^DU') { $uuCount++ }
        elseif ($line -match '^\?\?') { $aCount++ }
    }
    Write-Output ("WORKTREE_CHECK_STATUS_D=" + $dCount)
    Write-Output ("WORKTREE_CHECK_STATUS_M=" + $mCount)
    Write-Output ("WORKTREE_CHECK_STATUS_UU=" + $uuCount)
    Write-Output ("WORKTREE_CHECK_STATUS_UNTRACKED=" + $aCount)
    foreach ($line in $statusLines) { Write-Output ("WORKTREE_CHECK_STATUS_LINE " + $line) }

    # git fsck
    $fsck = git fsck --no-reflogs 2>&1 | Out-String
    $fsckHealthy = 'YES'
    if ($fsck -match 'error|missing object|broken') { $fsckHealthy = 'NO' }
    Write-Output ("WORKTREE_CHECK_FSCK_HEALTHY=" + $fsckHealthy)
    Write-Output ("WORKTREE_CHECK_FSCK_OUTPUT=" + ($fsck.Trim() -replace '\s+', ' '))

    # Final classification
    $verdict = 'CLEAN'
    if ($worktreeOnlyLoss.Count -gt 0) { $verdict = 'WORKTREE_ONLY_LOSS' }
    elseif ($indexOnlyLoss.Count -gt 0) { $verdict = 'INDEX_ONLY_LOSS' }
    elseif ($headOnlyLoss.Count -gt 0) { $verdict = 'HEAD_ONLY_LOSS' }
    Write-Output ("WORKTREE_CHECK_VERDICT=" + $verdict)
} finally {
    Pop-Location
}
