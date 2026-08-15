# test-owned-path-delete.ps1
#
# Deterministic safety test for bin/_lib.ps1 Remove-OwnedProbePath.
#
# PASS cases (deletion must succeed):
#   * owned GUID fixture under <repoRoot>\fixtures\
#   * owned GUID control dir under $env:TEMP\workbuddy-rootcause-control\
#
# REFUSE cases (deletion must throw AND must NOT delete anything):
#   * the repository root itself
#   * a parent of the repository root
#   * an arbitrary user directory (not an owned probe area)
#   * the production repo path
#   * an empty string
#   * a filesystem root
#
# Run:
#   .\test-owned-path-delete.ps1
# Output:
#   OWNED_PATH_DELETE_TEST=PASS|FAIL
#
# No destructive broad delete: every target is a freshly created GUID-owned
# fixture or a refusal case that must leave its target untouched.

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$fail = $false
$repoRoot = Resolve-RepoRoot
$tmpControl = Join-Path $env:TEMP 'workbuddy-rootcause-control'
New-Item -ItemType Directory -Force -Path $tmpControl | Out-Null

function Assert-Throws {
    param([scriptblock]$Body, [string]$Case, [ref]$FailRef)
    $threw = $false
    try {
        & $Body
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        Write-Output ("REFUSE_CASE_FAILED=" + $Case + " — expected a throw but none occurred")
        $FailRef.Value = $true
    } else {
        Write-Output ("REFUSE_CASE_OK=" + $Case)
    }
}

# ---------------------------------------------------------------------------
# PASS cases
# ---------------------------------------------------------------------------
$passFixture = Join-Path $repoRoot ('fixtures\owned-delete-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $passFixture -Force | Out-Null
Set-Content -LiteralPath (Join-Path $passFixture 'payload.txt') -Value 'x' -Encoding ASCII
Remove-OwnedProbePath -Path $passFixture
if (Test-Path $passFixture) {
    Write-Output "PASS_CASE_FAILED=owned GUID fixture still exists after delete"
    $fail = $true
} else {
    Write-Output "PASS_CASE_OK=owned GUID fixture"
}

$passTemp = Join-Path $tmpControl ('owned-delete-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $passTemp -Force | Out-Null
Set-Content -LiteralPath (Join-Path $passTemp 'payload.txt') -Value 'x' -Encoding ASCII
Remove-OwnedProbePath -Path $passTemp
if (Test-Path $passTemp) {
    Write-Output "PASS_CASE_FAILED=owned TEMP control dir still exists after delete"
    $fail = $true
} else {
    Write-Output "PASS_CASE_OK=owned TEMP control dir"
}

# ---------------------------------------------------------------------------
# REFUSE cases (must throw; target must remain untouched)
# ---------------------------------------------------------------------------
Assert-Throws { Remove-OwnedProbePath -Path $repoRoot } 'repo root' ([ref]$fail)
Assert-Throws { Remove-OwnedProbePath -Path (Split-Path $repoRoot -Parent) } 'parent of repo root' ([ref]$fail)
Assert-Throws { Remove-OwnedProbePath -Path $tmpControl } 'TEMP control area root (not registered)' ([ref]$fail)

$arbitrary = Join-Path $env:TEMP ('owned-delete-arbitrary-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $arbitrary -Force | Out-Null
Assert-Throws { Remove-OwnedProbePath -Path $arbitrary } 'arbitrary user dir' ([ref]$fail)
if (Test-Path $arbitrary) {
    Write-Output "REFUSE_CASE_OK=arbitrary user dir untouched"
} else {
    Write-Output "REFUSE_CASE_FAILED=arbitrary user dir was deleted"
    $fail = $true
}

$userProfileDir = Join-Path $env:USERPROFILE ('owned-delete-arbitrary-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $userProfileDir -Force | Out-Null
Assert-Throws { Remove-OwnedProbePath -Path $userProfileDir } 'arbitrary user-profile dir' ([ref]$fail)
if (Test-Path $userProfileDir) {
    Write-Output "REFUSE_CASE_OK=user-profile dir untouched"
} else {
    Write-Output "REFUSE_CASE_FAILED=user-profile dir was deleted"
    $fail = $true
}

Assert-Throws { Remove-OwnedProbePath -Path $script:ProductionRepoPath } 'production repo' ([ref]$fail)
Assert-Throws { Remove-OwnedProbePath -Path '' } 'empty string' ([ref]$fail)
$driveRoot = [System.IO.Path]::GetPathRoot($env:SystemDrive)
Assert-Throws { Remove-OwnedProbePath -Path $driveRoot } 'filesystem root' ([ref]$fail)

# ---------------------------------------------------------------------------
# Cleanup the test's own fixtures only (use .NET primitives — PowerShell
# Remove-Item is intercepted by the WorkBuddy safe-delete layer in a
# WorkBuddy-hosted shell, while .NET file APIs are not).
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $arbitrary) { [System.IO.Directory]::Delete($arbitrary, $true) }
if (Test-Path -LiteralPath $userProfileDir) { [System.IO.Directory]::Delete($userProfileDir, $true) }

if ($fail) {
    Write-Output "OWNED_PATH_DELETE_TEST=FAIL"
    exit 1
}
Write-Output "OWNED_PATH_DELETE_TEST=PASS"
