# run-bundle.ps1
# Single-mode bundle runner invoked by repro-all.ps1. Returns an array of
# strings (the textual results) so the caller can pipe to a results file.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Lab,
    [Parameter(Mandatory=$true)][ValidateSet('normal','workbuddy')][string]$Mode
)
$ErrorActionPreference = 'Continue'
$out = @()
$out += "=== MODE=$Mode ==="
$out += "TIMESTAMP=$(Get-Date -Format 'o')"

# Step 1: shim presence probe
$out += "--- Step 1: shim presence probe ---"
$probeOut = & node "$Lab\bin\probe-shim.cjs" 2>&1
$out += $probeOut

# Step 2: Node fs.rm small
$out += "--- Step 2: Node fs.rm (5 files < threshold 20) ---"
& "$Lab\bin\build-fixture.ps1" "$Lab\node-delete-probe\small" 5 | Out-Null
$smallOut = & node "$Lab\bin\repro-node-delete.mjs" $Mode small "$Lab\node-delete-probe\small" 2>&1
$out += $smallOut

# Step 3: Node fs.rm large
$out += "--- Step 3: Node fs.rm (40 files > threshold 20) ---"
& "$Lab\bin\build-fixture.ps1" "$Lab\node-delete-probe\large" 40 | Out-Null
$largeOut = & node "$Lab\bin\repro-node-delete.mjs" $Mode large "$Lab\node-delete-probe\large" 2>&1
$out += $largeOut

# Step 4: Git cycles (skip for now — heavy, recorded separately)
$out += "--- Step 4: Git worktree cycles ---"
$out += "(see results-*.txt's git section; check-worktree.ps1 output)"

$out
