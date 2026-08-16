# repro-all.ps1
# Master orchestrator. One-click reproducible A/B repro of:
#   1. Environment + shim injection probe
#   2. Node fs.rmSync small (5 files) and large (40 files) under NORMAL and SHIM
#   3. npm ci A/B with full pre/post file manifest
#   4. Git probe A/B with master != feature delta and per-step integrity check
#
# The WorkBuddy-NATIVE sandbox phase (Mode C) is NOT executed by this script.
# This process is not spawned through the WorkBuddy-native execution chain of
# a real tool-call session; the full native sandbox context (incl. any kernel
# sandbox attachment) is not present here. Native execution is the
# responsibility of the WorkBuddy session; see
# report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md.
#
# Usage:
#   .\repro-all.ps1                          # auto-detect WorkBuddy install
#   .\repro-all.ps1 -WorkbuddyInstall "D:\Custom\WorkBuddy"
#   .\repro-all.ps1 -Cycles 5
#   .\repro-all.ps1 -OutputDir <path>
[CmdletBinding()]
param(
    [string]$WorkbuddyInstall = '',
    [int]$Cycles = 5,
    [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$repoRoot = Resolve-RepoRoot
# Default OutputDir is unique (timestamp + GUID) so a fresh run never
# collides with a previous run's output.
if (-not $OutputDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $guid8 = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $OutputDir = Join-Path $repoRoot ("work\repro-run-" + $stamp + "-" + $guid8)
}
# Always convert to absolute path so that downstream Push-Location calls in
# child scripts don't pollute the relative resolution of $results / $OutputDir.
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
# SAFETY CONTRACT: never delete an existing caller-supplied OutputDir. If the
# selected OutputDir already exists (from a prior run or a user-chosen path),
# refuse to start rather than recursively deleting it.
if (Test-Path $OutputDir) {
    throw "repro-all: OutputDir already exists; refusing to delete existing output. Use a fresh unique -OutputDir. Path: $OutputDir"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$results = Join-Path $OutputDir 'results.txt'
"" | Set-Content $results -Encoding UTF8
function Log {
    param([string]$Line)
    Write-Output $Line
    Add-Content $results $Line -Encoding UTF8
}

# Print header
Log "REPRO_ALL_START timestamp=$(Get-Date -Format 'o')"
Log "REPRO_ALL_REPO_ROOT=$repoRoot"
Log "REPRO_ALL_OUTPUT_DIR=$OutputDir"

# ============================================================================
# Locate WorkBuddy install
# ============================================================================
if (-not $WorkbuddyInstall) {
    $WorkbuddyInstall = Resolve-WorkbuddyInstallPath
}
Log "REPRO_ALL_WORKBUDDY_INSTALL=$WorkbuddyInstall"

# Detect which phases can run
$wbShimAvailable = Assert-WorkbuddyShimAvailable -WbPath $WorkbuddyInstall
Log "REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE=$wbShimAvailable"

$nodeBin = (Get-Command node -ErrorAction SilentlyContinue).Source
$npmBin = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
$gitBin = (Get-Command git -ErrorAction SilentlyContinue).Source
Log "REPRO_ALL_NODE=$nodeBin"
Log "REPRO_ALL_NPM=$npmBin"
Log "REPRO_ALL_GIT=$gitBin"

# Resolve probe dirs (runtime)
$nodeDeleteSmall = Join-Path $repoRoot 'fixtures\node-delete\small'
$nodeDeleteLarge = Join-Path $repoRoot 'fixtures\node-delete\large'
$npmProbe = Join-Path $repoRoot 'npm-probe'
$gitProbeNormal = Join-Path $repoRoot 'fixtures\git-probe-normal'
$gitProbeShim = Join-Path $repoRoot 'fixtures\git-probe-shim'

# Reset only the RUNTIME-generated artifacts. The committed fixtures under
# npm-probe/ (package.json, package-lock.json) are preserved; only node_modules
# is wiped and regenerated.
#
# Per P4, do NOT delete an old Git probe before the experiment — the
# F1 natural incident may depend on WorkBuddy's own delete path. The probe
# scripts now refuse to start if the target path already exists, so the
# repro-all orchestrator must use a unique dir each time it runs.
$probeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$probeGuid  = [guid]::NewGuid().ToString('N').Substring(0,8)
$nodeDeleteSmall = Join-Path $repoRoot ("fixtures\node-delete\small-" + $probeStamp + "-" + $probeGuid)
$nodeDeleteLarge = Join-Path $repoRoot ("fixtures\node-delete\large-" + $probeStamp + "-" + $probeGuid)
$gitProbeNormal  = Join-Path $repoRoot ("fixtures\git-probe-normal-" + $probeStamp + "-" + $probeGuid)
$gitProbeShim    = Join-Path $repoRoot ("fixtures\git-probe-shim-" + $probeStamp + "-" + $probeGuid)
# Per P4, the probe scripts refuse to start if the target path already
# exists. So the build-git-probe*.ps1 scripts will create the dirs
# themselves via New-Item -Force. We do NOT pre-create the dirs here.
foreach ($d in @($nodeDeleteSmall, $nodeDeleteLarge, $gitProbeNormal, $gitProbeShim)) {
    if (Test-Path $d) {
        throw "repro-all: probe dir already exists; per P4 use a fresh unique dir. Path: $d"
    }
}
$npmNodeModules = Join-Path $npmProbe 'node_modules'
if (Test-Path $npmNodeModules) { Remove-OwnedProbePath $npmNodeModules }
# NOTE: npm-probe/_manifest_phase1.txt and _manifest_phase2.txt are
# overwritten by bin/repro-npm-ci.ps1 on every run (Set-Content), so no
# cleanup is needed here; they are owned files of the npm-probe fixture.

# ============================================================================
# PHASE 0 — Environment probe
# ============================================================================
Log ""
Log "==== PHASE 0: ENVIRONMENT + SHIM INJECTION PROBE ===="
Log "PHASE0_MODE=normal"
Assert-CleanWorkbuddyEnv
$env:NODE_OPTIONS = ''
$probeOut = & node (Join-Path $PSScriptRoot 'probe-shim.cjs') 2>&1
$probeOut | ForEach-Object { Log "PHASE0_PROBE $_" }
Log "PHASE0_DONE"

# ============================================================================
# PHASE 1 — Node fs.rmSync small + large (NORMAL vs SHIM)
# ============================================================================
Log ""
Log "==== PHASE 1: NODE fs.rmSync A/B ===="

Log "--- PHASE 1A: NORMAL small ---"
& (Join-Path $PSScriptRoot 'build-fixture.ps1') -Root $nodeDeleteSmall -Count 5 | ForEach-Object { Log "PHASE1A_FIXTURE $_" }
Assert-CleanWorkbuddyEnv
$env:NODE_OPTIONS = ''
& node (Join-Path $PSScriptRoot 'repro-node-delete.mjs') normal small $nodeDeleteSmall 2>&1 | ForEach-Object { Log "PHASE1A $_" }

Log "--- PHASE 1B: NORMAL large ---"
& (Join-Path $PSScriptRoot 'build-fixture.ps1') -Root $nodeDeleteLarge -Count 40 | ForEach-Object { Log "PHASE1B_FIXTURE $_" }
Assert-CleanWorkbuddyEnv
$env:NODE_OPTIONS = ''
& node (Join-Path $PSScriptRoot 'repro-node-delete.mjs') normal large $nodeDeleteLarge 2>&1 | ForEach-Object { Log "PHASE1B $_" }

if ($wbShimAvailable) {
    Log "--- PHASE 1C: SHIM small ---"
    & (Join-Path $PSScriptRoot 'build-fixture.ps1') -Root $nodeDeleteSmall -Count 5 | ForEach-Object { Log "PHASE1C_FIXTURE $_" }
    $shimReport = Join-Path $OutputDir 'shim-report-node.jsonl'
    $shimState = Join-Path $OutputDir 'shim-state-node'
    New-Item -ItemType Directory -Force -Path $shimState | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $shimReport) | Out-Null
    Set-WorkbuddyShimEnv -WbPath $WorkbuddyInstall -StateDir $shimState -ReportPath $shimReport
    & node (Join-Path $PSScriptRoot 'repro-node-delete.mjs') shim small $nodeDeleteSmall 2>&1 | ForEach-Object { Log "PHASE1C $_" }
    if (Test-Path $shimReport) { Get-Content $shimReport | ForEach-Object { Log "PHASE1C_SHIM_REPORT $_" } }
    Assert-CleanWorkbuddyEnv

    Log "--- PHASE 1D: SHIM large ---"
    & (Join-Path $PSScriptRoot 'build-fixture.ps1') -Root $nodeDeleteLarge -Count 40 | ForEach-Object { Log "PHASE1D_FIXTURE $_" }
    $shimReport2 = Join-Path $OutputDir 'shim-report-node-large.jsonl'
    $shimState2 = Join-Path $OutputDir 'shim-state-node-large'
    New-Item -ItemType Directory -Force -Path $shimState2 | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $shimReport2) | Out-Null
    Set-WorkbuddyShimEnv -WbPath $WorkbuddyInstall -StateDir $shimState2 -ReportPath $shimReport2
    & node (Join-Path $PSScriptRoot 'repro-node-delete.mjs') shim large $nodeDeleteLarge 2>&1 | ForEach-Object { Log "PHASE1D $_" }
    if (Test-Path $shimReport2) { Get-Content $shimReport2 | ForEach-Object { Log "PHASE1D_SHIM_REPORT $_" } }
    Assert-CleanWorkbuddyEnv
} else {
    Log "PHASE1_SHIM=SKIPPED_WORKBUDDY_NOT_INSTALLED"
}

# ============================================================================
# PHASE 2 — npm ci A/B
# ============================================================================
Log ""
Log "==== PHASE 2: npm ci A/B ===="
$npmOut = Join-Path $OutputDir 'npm-ci.txt'
if ($wbShimAvailable) {
    & (Join-Path $PSScriptRoot 'repro-npm-ci.ps1') -Probe $npmProbe -WorkbuddyInstall $WorkbuddyInstall -OutputFile $npmOut 2>&1 | ForEach-Object { Log "PHASE2 $_" }
    Get-Content $npmOut | ForEach-Object { Log "PHASE2_DETAIL $_" }
} else {
    Log "PHASE2=SKIPPED_WORKBUDDY_NOT_INSTALLED"
    Log "PHASE2_NOTE=cannot run shim phase without WorkBuddy install; npm ci NORMAL only"
    Assert-CleanWorkbuddyEnv
    $env:NODE_OPTIONS = ''
    Push-Location $npmProbe
    try {
        if (Test-Path (Join-Path $npmProbe 'node_modules')) { Remove-OwnedProbePath (Join-Path $npmProbe 'node_modules') }
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & npm.cmd install --no-audit --no-fund 2>&1 | Out-Null
        $ciOut = & npm.cmd ci --no-audit --no-fund 2>&1 | Out-String
        $ciExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        Log "PHASE2_NORMAL_CI_EXIT=$ciExit"
        Log "PHASE2_NORMAL_CI_OUTPUT_HEAD=" + (($ciOut.Trim() -split "`n" | Select-Object -First 3) -join ' | ')
    } finally { Pop-Location }
}

# ============================================================================
# PHASE 3 — Git A/B (NORMAL vs SHIM-ONLY)
# ============================================================================
Log ""
Log "==== PHASE 3: GIT PROBE A/B (NORMAL vs SHIM-ONLY) ===="
Log "PHASE3_NOTE=SHIM-ONLY reproduces the Node shim environment (env+NODE_OPTIONS) without the full WorkBuddy-native execution chain; the Node shim alone did not reproduce Bug B."

$gitOutNormal = Join-Path $OutputDir 'git-cycles-normal.txt'
$gitOutShim = Join-Path $OutputDir 'git-cycles-shim.txt'

Log "--- PHASE 3A: NORMAL (no env) ---"
Assert-CleanWorkbuddyEnv
$env:NODE_OPTIONS = ''
& (Join-Path $PSScriptRoot 'build-git-probe.ps1') -Repo $gitProbeNormal 2>&1 | ForEach-Object { Log "PHASE3A_BUILD $_" }
& (Join-Path $PSScriptRoot 'run-git-cycles.ps1') -Repo $gitProbeNormal -Cycles $Cycles -OutputFile $gitOutNormal -Merge $true 2>&1 | ForEach-Object { Log "PHASE3A_CYCLES $_" }
Get-Content $gitOutNormal | ForEach-Object { Log "PHASE3A_DETAIL $_" }

if ($wbShimAvailable) {
    Log "--- PHASE 3B: SHIM-ONLY (env+NODE_OPTIONS, non-native execution chain) ---"
    $shimReport3 = Join-Path $OutputDir 'shim-report-git.jsonl'
    $shimState3 = Join-Path $OutputDir 'shim-state-git'
    New-Item -ItemType Directory -Force -Path $shimState3 | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $shimReport3) | Out-Null
    Set-WorkbuddyShimEnv -WbPath $WorkbuddyInstall -StateDir $shimState3 -ReportPath $shimReport3
    & (Join-Path $PSScriptRoot 'build-git-probe.ps1') -Repo $gitProbeShim 2>&1 | ForEach-Object { Log "PHASE3B_BUILD $_" }
    & (Join-Path $PSScriptRoot 'run-git-cycles.ps1') -Repo $gitProbeShim -Cycles $Cycles -OutputFile $gitOutShim -Merge $true 2>&1 | ForEach-Object { Log "PHASE3B_CYCLES $_" }
    Get-Content $gitOutShim | ForEach-Object { Log "PHASE3B_DETAIL $_" }
    Assert-CleanWorkbuddyEnv
} else {
    Log "PHASE3_SHIM=SKIPPED_WORKBUDDY_NOT_INSTALLED"
}

# ============================================================================
# PHASE 4 — WorkBuddy NATIVE (must be executed by the user inside WorkBuddy)
# ============================================================================
Log ""
Log "==== PHASE 4: WORKBUDDY NATIVE SANDBOX (Mode C) ===="
Log "PHASE4_RESULT=NOT_EXECUTED_REQUIRES_WORKBUDDY_PARENT"
Log "PHASE4_REASON=This phase requires the WorkBuddy-native execution chain (a real WorkBuddy tool-call session); this process does not run inside that chain. See report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md."

Log ""
Log "REPRO_ALL_DONE timestamp=$(Get-Date -Format 'o')"
Log "REPRO_ALL_OUTPUT=$results"
