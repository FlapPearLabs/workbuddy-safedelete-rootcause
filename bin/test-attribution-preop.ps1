# test-attribution-preop.ps1
#
# Offline deterministic regression test for the attribution logic (REPAIR B / D).
#
# Synthetic case (does NOT require actual WorkBuddy corruption):
#   1. create a clean tiny Git repo with a few tracked files
#   2. intentionally remove ONE tracked physical file BEFORE run-git-cycles
#   3. run the cycle harness
#   4. assert:
#        - PREOP baseline != CLEAN
#        - no step-1a mutation is executed
#        - classification = PREEXISTING_NON_CLEAN
#        - runner always finalizes (GIT_CYCLES_END emitted)
#
# This guards against falsely attributing an already-broken worktree to a
# mutation operation (step-1a), which was the P1-2 localization gap.
#
# Run:
#   .\test-attribution-preop.ps1

[CmdletBinding()]
param(
    [string]$BranchName = 'feature/probe/attribution-test'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

# Refuse to run against the production repo even indirectly.
if ($PSScriptRoot -match [regex]::Escape($script:ProductionRepoPath)) {
    throw "refusing to run attribution test under the production path"
}

$tmpRoot = Join-Path $env:TEMP ('workbuddy-rootcause-attribution-' + [guid]::NewGuid().ToString('N'))
if (Test-Path $tmpRoot) { Remove-Item $tmpRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
$repo = Join-Path $tmpRoot 'tiny-repo'

# 1) clean tiny repo
New-Item -ItemType Directory -Path $repo -Force | Out-Null
Push-Location $repo
try {
    git init -b master 2>&1 | Out-Null
    git config user.email 'probe@workbuddy-rootcause-lab.invalid'
    git config user.name  'WorkBuddy Root-Cause Lab'
    git config core.autocrlf  $false
    Set-Content -LiteralPath 'a.txt' -Value 'a' -Encoding ASCII -NoNewline
    Set-Content -LiteralPath 'b.txt' -Value 'b' -Encoding ASCII -NoNewline
    Set-Content -LiteralPath 'c.txt' -Value 'c' -Encoding ASCII -NoNewline
    git add -A 2>&1 | Out-Null
    git commit -m 'tiny base commit' 2>&1 | Out-Null

    # 2) intentionally remove ONE tracked physical file (simulate pre-existing loss)
    Remove-Item -LiteralPath 'b.txt' -Force
} finally {
    Pop-Location
}

# 3) run the cycle harness against the pre-broken repo
$outFile = Join-Path $tmpRoot 'cycles-out.txt'
$repo = [System.IO.Path]::GetFullPath($repo)
& "$PSScriptRoot\run-git-cycles.ps1" -Repo $repo -Cycles 5 -OutputFile $outFile -Merge $false -BranchName $BranchName 2>&1 | Out-Null

$lines = Get-Content $outFile -Encoding UTF8
$preopVerdictLine = $lines | Where-Object { $_ -match '^GIT_CYCLES_PREOP_BASELINE_VERDICT=' }
$preopVerdict = if ($preopVerdictLine) { ($preopVerdictLine -split '=', 2)[1] } else { 'MISSING' }
$hasStep1a = ($lines | Where-Object { $_ -match '^GIT_OPERATION_STEP label=step-1a-switch-to-feature' }).Count -gt 0
$hasPreexisting = ($lines | Where-Object { $_ -match 'classification=PREEXISTING_NON_CLEAN' }).Count -gt 0
$hasEnd = ($lines | Where-Object { $_ -match '^GIT_CYCLES_END' }).Count -gt 0

Write-Output "ATTRIBUTION_TEST_REPO=$repo"
Write-Output "ATTRIBUTION_TEST_PREOP_BASELINE_VERDICT=$preopVerdict"
Write-Output ("ATTRIBUTION_TEST_STEP1A_EXECUTED=" + $(if ($hasStep1a) {'YES'} else {'NO'}))
Write-Output ("ATTRIBUTION_TEST_PREEXISTING_CLASSIFICATION=" + $(if ($hasPreexisting) {'YES'} else {'NO'}))
Write-Output ("ATTRIBUTION_TEST_CYCLES_END_EMITTED=" + $(if ($hasEnd) {'YES'} else {'NO'}))

$fail = $false
if ($preopVerdict -eq 'CLEAN' -or $preopVerdict -eq 'MISSING') {
    Write-Output "ATTRIBUTION_TEST_ASSERTION_FAILED: expected PREOP baseline != CLEAN, got '$preopVerdict'"
    $fail = $true
}
if ($hasStep1a) {
    Write-Output "ATTRIBUTION_TEST_ASSERTION_FAILED: step-1a mutation must NOT be executed on a pre-broken worktree"
    $fail = $true
}
if (-not $hasPreexisting) {
    Write-Output "ATTRIBUTION_TEST_ASSERTION_FAILED: expected classification=PREEXISTING_NON_CLEAN"
    $fail = $true
}
if (-not $hasEnd) {
    Write-Output "ATTRIBUTION_TEST_ASSERTION_FAILED: GIT_CYCLES_END was not emitted (runner did not finalize)"
    $fail = $true
}

# Cleanup the temp repo (do NOT touch any tracked repo).
if (Test-Path $tmpRoot) { Remove-Item $tmpRoot -Recurse -Force }

if ($fail) { Write-Output "ATTRIBUTION_TEST_RESULT=FAIL"; exit 1 }
Write-Output "ATTRIBUTION_TEST_RESULT=PASS"
