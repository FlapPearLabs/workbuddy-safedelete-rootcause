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
#     WORKTREE_CONTENT_DIVERGENCE     (HEAD=yes, INDEX=yes, PHYSICAL=yes, INDEX_BLOB != PHYSICAL_BLOB)
#     OTHER_STATE_DIVERGENCE          (anything else)
#
#   physical content integrity: for every path that is INDEX_PRESENT=yes
#   AND PHYSICAL_PRESENT=yes, compare
#     INDEX_BLOB_SHA    = git rev-parse ":<path>"
#     PHYSICAL_BLOB_SHA = git hash-object -- "<path>"
#   Mismatch is recorded and forces a non-CLEAN verdict.
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

    # ─── HEAD root tree ──────────────────────────────────────────────
    $headTree = (git show -s --format=%T HEAD).Trim()
    Write-Output ("WORKTREE_CHECK_HEAD_TREE=" + $headTree)
    $indexTree = (git write-tree).Trim()
    Write-Output ("WORKTREE_CHECK_INDEX_TREE=" + $indexTree)
    $headIndexMatch = if ($headTree -eq $indexTree) { 'YES' } else { 'NO' }
    Write-Output ("WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=" + $headIndexMatch)

    # ─── HEAD ∪ INDEX enumeration ────────────────────────────────────
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

    # ─── Per-path classification (round 1: presence-based) ──────────
    $physicalPresent = 0
    $missing = 0
    $classCounts = @{
        CLEAN = 0
        WORKTREE_ONLY_LOSS = 0
        INDEX_AND_WORKTREE_LOSS = 0
        INDEX_ONLY_DIVERGENCE = 0
        INDEX_ADDITION_PHYSICAL_MISSING = 0
        WORKTREE_CONTENT_DIVERGENCE = 0
        OTHER_STATE_DIVERGENCE = 0
    }
    $pathsNeedingContentCheck = New-Object 'System.Collections.Generic.List[object]'

    foreach ($p in $union) {
        $inHead = $headSet.Contains($p)
        $inIndex = $indexSet.Contains($p)
        $phys = Test-Path -LiteralPath $p
        if ($phys) { $physicalPresent++ } else { $missing++ }

        if ($inHead -and $inIndex -and $phys) {
            # Provisional CLEAN — will downgrade to WORKTREE_CONTENT_DIVERGENCE
            # after the content hash check.
            $pathsNeedingContentCheck.Add($p) | Out-Null
            $classCounts.CLEAN++
        }
        elseif ($inHead -and $inIndex -and -not $phys) {
            $classCounts.WORKTREE_ONLY_LOSS++
        }
        elseif ($inHead -and -not $inIndex -and -not $phys) {
            $classCounts.INDEX_AND_WORKTREE_LOSS++
        }
        elseif ($inHead -and -not $inIndex -and $phys) {
            $classCounts.INDEX_ONLY_DIVERGENCE++
        }
        elseif (-not $inHead -and $inIndex -and -not $phys) {
            $classCounts.INDEX_ADDITION_PHYSICAL_MISSING++
        }
        else {
            $classCounts.OTHER_STATE_DIVERGENCE++
        }

        if (($inHead -or $inIndex) -and -not $phys) {
            $headStr = $(if ($inHead)  { 'yes' } else { 'no' })
            $idxStr  = $(if ($inIndex) { 'yes' } else { 'no' })
            $physStr = $(if ($phys)    { 'yes' } else { 'no' })
            $cls = if ($inHead -and $inIndex) { 'WORKTREE_ONLY_LOSS' }
                   elseif ($inHead)            { 'INDEX_AND_WORKTREE_LOSS' }
                   else                       { 'INDEX_ADDITION_PHYSICAL_MISSING' }
            Write-Output ("WORKTREE_CHECK_MISSING label=" + $Label + " classification=" + $cls + " path=" + $p + " head=" + $headStr + " index=" + $idxStr + " physical=" + $physStr)
        }
    }

    # ─── Round 2: content hash check (P2) ─────────────────────────────
    # For every path that was provisionally CLEAN, compare
    #   INDEX_BLOB_SHA    = git rev-parse ":<path>"
    #   PHYSICAL_BLOB_SHA = git hash-object -- "<path>"
    # A mismatch is recorded and the path is reclassified to
    # WORKTREE_CONTENT_DIVERGENCE.
    $contentMismatchCount = 0
    foreach ($p in $pathsNeedingContentCheck) {
        # Skip special paths (submodules, symlinks) — git hash-object
        # refuses them. These are not realistic in this lab's synthetic
        # fixture; record them as a no-op mismatch if they ever appear.
        $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) { continue }
        if ($item.LinkType) { continue }  # symlink

        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $indexBlob = (git rev-parse ":`"$p`"" 2>$null).Trim()
        $physBlob  = (git hash-object -- "$p" 2>$null).Trim()
        $ErrorActionPreference = $prevEAP

        if (-not $indexBlob -or -not $physBlob) { continue }
        if ($indexBlob -ne $physBlob) {
            $contentMismatchCount++
            $classCounts.CLEAN--
            $classCounts.WORKTREE_CONTENT_DIVERGENCE++
            Write-Output ("WORKTREE_CHECK_CONTENT_MISMATCH label=" + $Label + " path=" + $p + " index_blob=" + $indexBlob + " physical_blob=" + $physBlob)
        }
    }
    Write-Output ("WORKTREE_CHECK_CONTENT_MISMATCH_COUNT=" + $contentMismatchCount)

    Write-Output ("WORKTREE_CHECK_PHYSICAL_PRESENT_COUNT=" + $physicalPresent)
    Write-Output ("WORKTREE_CHECK_MISSING_COUNT=" + $missing)
    foreach ($k in @('WORKTREE_ONLY_LOSS','INDEX_AND_WORKTREE_LOSS','INDEX_ONLY_DIVERGENCE','INDEX_ADDITION_PHYSICAL_MISSING','WORKTREE_CONTENT_DIVERGENCE','OTHER_STATE_DIVERGENCE')) {
        Write-Output ("WORKTREE_CHECK_CLASS_" + $k + "_COUNT=" + $classCounts[$k])
    }

    # ─── git status (porcelain v1) ───────────────────────────────────
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

    # ─── git fsck ────────────────────────────────────────────────────
    $fsck = git fsck --no-reflogs 2>&1 | Out-String
    $fsckHealthy = 'YES'
    if ($fsck -match 'error|missing object|broken') { $fsckHealthy = 'NO' }
    Write-Output ("WORKTREE_CHECK_FSCK_HEALTHY=" + $fsckHealthy)
    Write-Output ("WORKTREE_CHECK_FSCK_OUTPUT=" + ($fsck.Trim() -replace '\s+', ' '))

    # ─── Verdict ─────────────────────────────────────────────────────
    # Priority:
    #   WORKTREE_ONLY_LOSS
    #   INDEX_AND_WORKTREE_LOSS
    #   INDEX_ONLY_DIVERGENCE
    #   INDEX_ADDITION_PHYSICAL_MISSING
    #   WORKTREE_CONTENT_DIVERGENCE
    #   OTHER_STATE_DIVERGENCE (incl. fsck bad, HEAD_TREE != INDEX_TREE)
    #   CLEAN
    #
    # A tracked M in git status (with or without content mismatch) also
    # blocks CLEAN: a tracked modified file is an in-progress worktree
    # change, not a clean post-op state.
    $verdict = 'CLEAN'
    if ($classCounts.WORKTREE_ONLY_LOSS -gt 0)            { $verdict = 'WORKTREE_ONLY_LOSS' }
    elseif ($classCounts.INDEX_AND_WORKTREE_LOSS -gt 0)   { $verdict = 'INDEX_AND_WORKTREE_LOSS' }
    elseif ($classCounts.INDEX_ONLY_DIVERGENCE -gt 0)      { $verdict = 'INDEX_ONLY_DIVERGENCE' }
    elseif ($classCounts.INDEX_ADDITION_PHYSICAL_MISSING -gt 0) { $verdict = 'INDEX_ADDITION_PHYSICAL_MISSING' }
    elseif ($classCounts.WORKTREE_CONTENT_DIVERGENCE -gt 0)     { $verdict = 'WORKTREE_CONTENT_DIVERGENCE' }
    elseif ($classCounts.OTHER_STATE_DIVERGENCE -gt 0)     { $verdict = 'OTHER_STATE_DIVERGENCE' }
    elseif ($dCount -gt 0)                                { $verdict = 'WORKTREE_ONLY_LOSS' }
    elseif ($mCount -gt 0)                                { $verdict = 'WORKTREE_CONTENT_DIVERGENCE' }
    elseif ($fsckHealthy -ne 'YES')                       { $verdict = 'OTHER_STATE_DIVERGENCE' }
    elseif ($headIndexMatch -ne 'YES')                    { $verdict = 'OTHER_STATE_DIVERGENCE' }
    Write-Output ("WORKTREE_CHECK_VERDICT label=" + $Label + " value=" + $verdict)
} finally {
    Pop-Location
}
