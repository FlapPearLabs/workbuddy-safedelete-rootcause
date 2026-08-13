# check-worktree.ps1
#
# Comprehensive Git worktree integrity check. Emits a structured, self-describing,
# machine-readable record of:
#
#   HEAD / INDEX / PHYSICAL state for every path in HEAD ∪ INDEX
#   Per-path classification into one of:
#     CLEAN
#     WORKTREE_ONLY_LOSS              (HEAD=yes, INDEX=yes, PHYSICAL=no)
#     INDEX_AND_WORKTREE_LOSS         (HEAD=yes, INDEX=no,  PHYSICAL=no)
#     INDEX_ONLY_DIVERGENCE           (HEAD=yes, INDEX=no,  PHYSICAL=yes)
#     INDEX_ADDITION_PHYSICAL_MISSING (HEAD=no,  INDEX=yes, PHYSICAL=no)
#     OTHER_STATE_DIVERGENCE          (anything else)
#
#   git status (porcelain v1)
#   git fsck (no-reflogs)
#   HEAD_TREE vs INDEX_TREE match
#
# Every emitted line that depends on a step carries a `label=<label>` token so
# that the consumer can group records by step without a separate index file.
#
# Usage:
#   .\check-worktree.ps1 -Repo <path> [-Label "step description"]
#
# Output: lines beginning with WORKTREE_CHECK_* for the orchestrator / parser.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [string]$Label = ''
)
$ErrorActionPreference = 'Stop'
Push-Location $Repo
try {
    Write-Output ("WORKTREE_CHECK_LABEL=" + $Label)
    Write-Output ("WORKTREE_CHECK_REPO=" + $Repo)
    Write-Output ("WORKTREE_CHECK_HEAD=" + (git rev-parse HEAD))
    Write-Output ("WORKTREE_CHECK_BRANCH=" + (git rev-parse --abbrev-ref HEAD))

    # ─── HEAD root tree (P1-1 fix) ──────────────────────────────────────
    # Previously: parsed `git ls-tree HEAD` and took the first tree entry
    # (which is the *root* tree only when the root has a single top-level
    # tree, and was always fragile). Use the canonical root-tree query.
    $headTree = (git show -s --format=%T HEAD).Trim()
    Write-Output ("WORKTREE_CHECK_HEAD_TREE=" + $headTree)

    # INDEX root tree
    $indexTree = (git write-tree).Trim()
    Write-Output ("WORKTREE_CHECK_INDEX_TREE=" + $indexTree)

    $headIndexMatch = if ($headTree -eq $indexTree) { 'YES' } else { 'NO' }
    Write-Output ("WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=" + $headIndexMatch)

    # ─── HEAD ∪ INDEX enumeration (P1-2 fix) ────────────────────────────
    $headPaths = @(git ls-tree -r --name-only HEAD)
    $indexPaths = @(git ls-files)
    $headSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $indexSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in $headPaths)  { [void]$headSet.Add($p) }
    foreach ($p in $indexPaths) { [void]$indexSet.Add($p) }
    $union = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $headSet)  { $union.Add($p) }
    foreach ($p in $indexSet) { if (-not $headSet.Contains($p)) { $union.Add($p) } }
    $union.Sort()

    Write-Output ("WORKTREE_CHECK_HEAD_PATH_COUNT=" + $headSet.Count)
    Write-Output ("WORKTREE_CHECK_INDEX_PATH_COUNT=" + $indexSet.Count)
    Write-Output ("WORKTREE_CHECK_UNION_PATH_COUNT=" + $union.Count)

    # ─── Per-path classification ────────────────────────────────────────
    $physicalPresent = 0
    $missing = 0
    $classCounts = @{
        CLEAN = 0
        WORKTREE_ONLY_LOSS = 0
        INDEX_AND_WORKTREE_LOSS = 0
        INDEX_ONLY_DIVERGENCE = 0
        INDEX_ADDITION_PHYSICAL_MISSING = 0
        OTHER_STATE_DIVERGENCE = 0
    }

    foreach ($p in $union) {
        $inHead = $headSet.Contains($p)
        $inIndex = $indexSet.Contains($p)
        $phys = Test-Path -LiteralPath $p
        if ($phys) { $physicalPresent++ } else { $missing++ }

        $cls = ''
        if ($inHead -and $inIndex -and $phys) {
            $cls = 'CLEAN'
        } elseif ($inHead -and $inIndex -and -not $phys) {
            $cls = 'WORKTREE_ONLY_LOSS'
        } elseif ($inHead -and -not $inIndex -and -not $phys) {
            $cls = 'INDEX_AND_WORKTREE_LOSS'
        } elseif ($inHead -and -not $inIndex -and $phys) {
            $cls = 'INDEX_ONLY_DIVERGENCE'
        } elseif (-not $inHead -and $inIndex -and -not $phys) {
            $cls = 'INDEX_ADDITION_PHYSICAL_MISSING'
        } else {
            # (-not $inHead -and -not $inIndex) shouldn't happen since $p was
            # drawn from the union; keep the slot for safety.
            $cls = 'OTHER_STATE_DIVERGENCE'
        }
        $classCounts[$cls]++

        if ($cls -ne 'CLEAN') {
            $headStr = $(if ($inHead)  { 'yes' } else { 'no' })
            $idxStr  = $(if ($inIndex) { 'yes' } else { 'no' })
            $physStr = $(if ($phys)    { 'yes' } else { 'no' })
            Write-Output ("WORKTREE_CHECK_MISSING label=" + $Label + " classification=" + $cls + " path=" + $p + " head=" + $headStr + " index=" + $idxStr + " physical=" + $physStr)
        }
    }

    Write-Output ("WORKTREE_CHECK_PHYSICAL_PRESENT_COUNT=" + $physicalPresent)
    Write-Output ("WORKTREE_CHECK_MISSING_COUNT=" + $missing)
    foreach ($k in @('WORKTREE_ONLY_LOSS','INDEX_AND_WORKTREE_LOSS','INDEX_ONLY_DIVERGENCE','INDEX_ADDITION_PHYSICAL_MISSING','OTHER_STATE_DIVERGENCE')) {
        Write-Output ("WORKTREE_CHECK_CLASS_" + $k + "_COUNT=" + $classCounts[$k])
    }

    # ─── git status (porcelain v1) ──────────────────────────────────────
    $statusLines = git status --porcelain=v1 2>$null
    $dCount = 0; $mCount = 0; $uuCount = 0; $aCount = 0
    foreach ($line in $statusLines) {
        if ($line -match '^.D' -or $line -match '^D.') { $dCount++ }
        elseif ($line -match '^.M' -or $line -match '^M.') { $mCount++ }
        elseif ($line -match '^UU|^AA|^DD|^AU|^UA|^UD|^DU') { $uuCount++ }
        elseif ($line -match '^\?\?') { $aCount++ }
    }
    Write-Output ("WORKTREE_CHECK_STATUS_D=" + $dCount)
    Write-Output ("WORKTREE_CHECK_STATUS_M=" + $mCount)
    Write-Output ("WORKTREE_CHECK_STATUS_UU=" + $uuCount)
    Write-Output ("WORKTREE_CHECK_STATUS_UNTRACKED=" + $aCount)
    foreach ($line in $statusLines) {
        Write-Output ("WORKTREE_CHECK_STATUS_LINE label=" + $Label + " " + $line)
    }

    # ─── git fsck ───────────────────────────────────────────────────────
    $fsck = git fsck --no-reflogs 2>&1 | Out-String
    $fsckHealthy = 'YES'
    if ($fsck -match 'error|missing object|broken') { $fsckHealthy = 'NO' }
    Write-Output ("WORKTREE_CHECK_FSCK_HEALTHY=" + $fsckHealthy)
    Write-Output ("WORKTREE_CHECK_FSCK_OUTPUT=" + ($fsck.Trim() -replace '\s+', ' '))

    # ─── Verdict (P1-4: label is on the verdict line itself) ────────────
    # CLEAN iff every path in the union is in (HEAD ∩ INDEX ∩ physical) AND
    # status has no D entries AND fsck is healthy AND HEAD_TREE == INDEX_TREE.
    $verdict = 'CLEAN'
    if ($classCounts.WORKTREE_ONLY_LOSS -gt 0)            { $verdict = 'WORKTREE_ONLY_LOSS' }
    elseif ($classCounts.INDEX_AND_WORKTREE_LOSS -gt 0)   { $verdict = 'INDEX_AND_WORKTREE_LOSS' }
    elseif ($classCounts.INDEX_ONLY_DIVERGENCE -gt 0)      { $verdict = 'INDEX_ONLY_DIVERGENCE' }
    elseif ($classCounts.INDEX_ADDITION_PHYSICAL_MISSING -gt 0) { $verdict = 'INDEX_ADDITION_PHYSICAL_MISSING' }
    elseif ($classCounts.OTHER_STATE_DIVERGENCE -gt 0)     { $verdict = 'OTHER_STATE_DIVERGENCE' }
    elseif ($dCount -gt 0)                                { $verdict = 'WORKTREE_ONLY_LOSS' }
    elseif ($fsckHealthy -ne 'YES')                       { $verdict = 'OTHER_STATE_DIVERGENCE' }
    elseif ($headIndexMatch -ne 'YES')                    { $verdict = 'OTHER_STATE_DIVERGENCE' }
    Write-Output ("WORKTREE_CHECK_VERDICT label=" + $Label + " value=" + $verdict)
} finally {
    Pop-Location
}
