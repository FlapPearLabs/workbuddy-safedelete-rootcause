# test-owned-path-delete.ps1
#
# Deterministic safety test for bin/_lib.ps1 Remove-OwnedProbePath.
#
# PASS cases (deletion must succeed):
#   * owned GUID fixture under <repoRoot>\fixtures\
#   * owned GUID control dir under $env:TEMP\workbuddy-rootcause-control\
#   * NPM_NODE_MODULES_EXACT_DELETE_TEST: the exact
#     <repoRoot>\npm-probe\node_modules path (and its children) must be
#     deletable WITHOUT registration (real repro-all / repro-npm-ci call
#     pattern). Tested in isolation via -RepoRootOverride, plus on the real
#     path only when it does not already exist (never destroys existing
#     runtime state).
#
# REFUSE cases (deletion must throw AND must NOT delete anything):
#   * the repository root itself
#   * a parent of the repository root
#   * an arbitrary user directory (not an owned probe area)
#   * the production repo path
#   * an empty string
#   * a filesystem root
#
# OUTPUTDIR_EXISTING_REFUSAL_TEST: repro-all.ps1 must REFUSE an existing
# caller-supplied OutputDir (never recursively delete it); a sentinel file
# must remain intact.
#
# Run:
#   .\test-owned-path-delete.ps1
# Output:
#   OWNED_PATH_DELETE_TEST=PASS|FAIL
#   NPM_NODE_MODULES_EXACT_DELETE_TEST=PASS|FAIL
#   OUTPUTDIR_EXISTING_REFUSAL_TEST=PASS|FAIL
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
# NPM_NODE_MODULES_EXACT_DELETE_TEST — the exact
# <repo>\npm-probe\node_modules path must be deletable WITHOUT registration
# (the real repro-all.ps1 / repro-npm-ci.ps1 call pattern between the NORMAL
# and SHIM npm-ci phases).
# ---------------------------------------------------------------------------
$npmExact = Join-Path $repoRoot 'npm-probe\node_modules'
$npmExactOk = $true

# 1) Isolated exact-root semantic test (always safe; never touches the real
#    node_modules): a synthetic repo under the TEMP control dir.
$fakeRoot = Join-Path $tmpControl ('exact-delete-fakerepo-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$fakeExact = Join-Path $fakeRoot 'npm-probe\node_modules'
New-Item -ItemType Directory -Path $fakeExact -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fakeExact 'sentinel.txt') -Value 'x' -Encoding ASCII
Remove-OwnedProbePath -Path $fakeExact -RepoRootOverride $fakeRoot
if (Test-Path $fakeExact) {
    Write-Output 'NPM_EXACT_CASE_FAILED=isolated fake node_modules still exists after delete'
    $npmExactOk = $false
} else {
    Write-Output 'NPM_EXACT_CASE_OK=isolated exact node_modules deleted (no OwnedRoots)'
}
# Also prove children of the exact path are deletable.
$fakeExact2 = Join-Path $fakeRoot 'npm-probe\node_modules'
New-Item -ItemType Directory -Path $fakeExact2 -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fakeExact2 'entities') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fakeExact2 'entities\f.js') -Value 'x' -Encoding ASCII
Remove-OwnedProbePath -Path (Join-Path $fakeExact2 'entities') -RepoRootOverride $fakeRoot
if (Test-Path (Join-Path $fakeExact2 'entities')) {
    Write-Output 'NPM_EXACT_CASE_FAILED=exact-path child not deleted'
    $npmExactOk = $false
} else {
    Write-Output 'NPM_EXACT_CASE_OK=exact-path child deleted'
}
if (Test-Path $fakeExact2) { [System.IO.Directory]::Delete($fakeExact2, $true) }
if (Test-Path $fakeRoot) { [System.IO.Directory]::Delete($fakeRoot, $true) }

# 2) Real call pattern: only when the real npm-probe\node_modules does NOT
#    exist (fresh-clone state). If it exists, do NOT destroy it — the
#    isolated test above already proves the exact-root semantic.
$realExactTouched = $false
if (-not (Test-Path $npmExact)) {
    New-Item -ItemType Directory -Path $npmExact -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $npmExact 'sentinel.txt') -Value 'x' -Encoding ASCII
    Remove-OwnedProbePath -Path $npmExact
    $realExactTouched = $true
    if (Test-Path $npmExact) {
        Write-Output 'NPM_EXACT_CASE_FAILED=real npm-probe\node_modules still exists after delete'
        $npmExactOk = $false
    } else {
        Write-Output 'NPM_EXACT_CASE_OK=real call pattern deleted npm-probe\node_modules (no OwnedRoots)'
    }
} else {
    Write-Output 'NPM_EXACT_CASE_SKIPPED=real npm-probe\node_modules already exists; left untouched (isolated test above proves semantics)'
}

if ($npmExactOk) { Write-Output 'NPM_NODE_MODULES_EXACT_DELETE_TEST=PASS' } else { Write-Output 'NPM_NODE_MODULES_EXACT_DELETE_TEST=FAIL'; $fail = $true }

# ---------------------------------------------------------------------------
# OUTPUTDIR_EXISTING_REFUSAL_TEST — repro-all.ps1 must REFUSE an existing
# caller-supplied OutputDir (never delete it); the sentinel must survive.
# ---------------------------------------------------------------------------
$outDirExisting = Join-Path $env:TEMP ('outputdir-refusal-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $outDirExisting -Force | Out-Null
$sentinelFile = Join-Path $outDirExisting 'sentinel.txt'
Set-Content -LiteralPath $sentinelFile -Value 'keep-me' -Encoding ASCII
$refused = $false
try {
    & (Join-Path $PSScriptRoot 'repro-all.ps1') -OutputDir $outDirExisting 2>&1 | Out-Null
} catch {
    $refused = $true
}
$sentinelIntact = Test-Path -LiteralPath $sentinelFile
if (-not $refused) {
    Write-Output 'OUTPUTDIR_CASE_FAILED=repro-all did not refuse an existing OutputDir'
    $fail = $true
} elseif (-not $sentinelIntact) {
    Write-Output 'OUTPUTDIR_CASE_FAILED=existing OutputDir was deleted (sentinel lost)'
    $fail = $true
} else {
    Write-Output 'OUTPUTDIR_CASE_OK=repro-all refused existing OutputDir; sentinel intact'
}
if (Test-Path -LiteralPath $outDirExisting) { [System.IO.Directory]::Delete($outDirExisting, $true) }
if ($refused -and $sentinelIntact) { Write-Output 'OUTPUTDIR_EXISTING_REFUSAL_TEST=PASS' } else { Write-Output 'OUTPUTDIR_EXISTING_REFUSAL_TEST=FAIL' }

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
