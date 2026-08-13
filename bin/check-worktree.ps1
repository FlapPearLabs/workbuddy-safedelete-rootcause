# check-worktree.ps1
# Verifies that every tracked file in HEAD is present in the working tree.
# Outputs TRACKED_COUNT, PHYSICAL_COUNT, MISSING_TRACKED_FILES.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repo
)
$ErrorActionPreference = 'Stop'
Push-Location $Repo
try {
    $tracked = @(git ls-files)
    $physical = 0
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($f in $tracked) {
        if (Test-Path -LiteralPath $f) {
            $physical++
        } else {
            $missing.Add($f) | Out-Null
        }
    }
    Write-Output ("REPO=" + $Repo)
    Write-Output ("TRACKED_COUNT=" + $tracked.Count)
    Write-Output ("PHYSICAL_COUNT=" + $physical)
    Write-Output ("MISSING_COUNT=" + $missing.Count)
    if ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-Output ("MISSING_FILE: " + $_) }
    }
    $fsck = git fsck --no-reflogs 2>&1 | Out-String
    $fsckHealthy = 'YES'
    if ($fsck -match 'error|missing|broken') { $fsckHealthy = 'NO' }
    Write-Output ("FSCK_HEALTHY=" + $fsckHealthy)
    Write-Output ("FSCK_OUTPUT=" + $fsck.Trim())
    $status = git status --short 2>&1 | Out-String
    $dCount = 0; $mCount = 0; $uuCount = 0
    foreach ($line in ($status -split "`n")) {
        if ($line -match '^\s*D\s+') { $dCount++ }
        elseif ($line -match '^\s*M\s+') { $mCount++ }
        elseif ($line -match '^UU|^AA|^DD|^AU|^UA|^UD|^DU') { $uuCount++ }
    }
    Write-Output ("GIT_STATUS_D_LINES=" + $dCount)
    Write-Output ("GIT_STATUS_M_LINES=" + $mCount)
    Write-Output ("GIT_STATUS_UU_LINES=" + $uuCount)
    $worktreeLoss = ($missing.Count -gt 0)
    Write-Output ("WORKTREE_ONLY_LOSS=" + $worktreeLoss)
} finally {
    Pop-Location
}
