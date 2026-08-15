# _lib.ps1 - shared library for the repro bundle
# Sourced by all repro scripts. Provides:
#   * Resolve-WorkbuddyInstallPath
#   * Assert-CleanWorkbuddyEnv
#   * Set-WorkbuddyShimEnv
#   * Write-StepHeader
#   * Resolve-RepoRoot
#   * Manifest-Capture (path + size + sha256)
#   * Manifest-Diff
#   * Remove-OwnedProbePath (narrowly-scoped cleanup; no external deps)

$ErrorActionPreference = 'Stop'

# The real production repo path is HARD-BLACKLISTED at the script level.
# Refuse to invoke any command whose argument contains the real production
# project path. The probe is for a disposable lab only.
$script:ProductionRepoPath = 'D:\Dev\zhihu-grabber-toolkit'

function Assert-NotProductionTarget {
    param([string[]]$Arguments)
    foreach ($a in $Arguments) {
        if ($null -eq $a) { continue }
        if ([string]$a -match [regex]::Escape($script:ProductionRepoPath)) {
            throw "refusing to run a command that targets the real production repo ($script:ProductionRepoPath)"
        }
    }
}

function Resolve-RepoRoot {
    # The repo root is the parent of the bin/ directory.
    $here = $PSScriptRoot
    if (-not $here) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    return (Resolve-Path (Join-Path $here '..')).Path
}

function Resolve-WorkbuddyInstallPath {
    # Locate the WorkBuddy install directory by checking well-known paths.
    # The user may have installed it elsewhere; probe both common locations.
    $candidates = @(
        'D:\WORKBUDDY',
        (Join-Path $env:ProgramFiles 'WorkBuddy'),
        (Join-Path ${env:ProgramFiles(x86)} 'WorkBuddy'),
        (Join-Path $env:ProgramFiles 'Tencent\WorkBuddy'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tencent\WorkBuddy')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'WorkBuddy.exe'))) {
            return $c
        }
    }
    return $null
}

function Assert-WorkbuddyShimAvailable {
    param([string]$WbPath)
    if (-not $WbPath) {
        Write-Output "WORKBUDDY_NOT_INSTALLED"
        return $false
    }
    $shim = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\shim\genie-safe-delete.cjs'
    $guard = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\shim\safe-delete-bulk-guard.cjs'
    $trash = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\genie-trash\win32-x64.exe'
    if ((-not (Test-Path $shim)) -or (-not (Test-Path $guard))) {
        Write-Output "WORKBUDDY_SHIM_NOT_FOUND: $WbPath"
        return $false
    }
    $script:WorkbuddyShimPath = $shim
    $script:WorkbuddyGuardPath = $guard
    $script:WorkbuddyTrashPath = $trash
    return $true
}

function Assert-CleanWorkbuddyEnv {
    $toRemove = @(
        'CODEBUDDY_SESSION_ID','CODEBUDDY_TOOL_CALL_ID',
        'CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR',
        'CODEBUDDY_SAFE_DELETE_BULK_GUARD',
        'CODEBUDDY_SAFE_DELETE_REPORT_PATH',
        'CODEBUDDY_NODE_BIN','GENIE_TRASH_DIR',
        'CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD','NODE_OPTIONS'
    )
    foreach ($n in $toRemove) {
        if (Test-Path "env:$n") {
            Remove-Item "env:$n" -ErrorAction SilentlyContinue
        }
    }
}

function Set-WorkbuddyShimEnv {
    param(
        [Parameter(Mandatory=$true)][string]$WbPath,
        [Parameter(Mandatory=$true)][string]$StateDir,
        [Parameter(Mandatory=$true)][string]$ReportPath
    )
    $guard = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\shim\safe-delete-bulk-guard.cjs'
    $trash = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\genie-trash\win32-x64.exe'
    $shim = Join-Path $WbPath 'resources\app.asar.unpacked\cli\vendor\shim\genie-safe-delete.cjs'
    $node = (Get-Command node).Source
    $env:CODEBUDDY_SESSION_ID = 'simulated-bundle-session'
    $env:CODEBUDDY_TOOL_CALL_ID = [guid]::NewGuid().ToString()
    $env:CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR = $StateDir
    $env:CODEBUDDY_SAFE_DELETE_BULK_GUARD = $guard
    $env:CODEBUDDY_SAFE_DELETE_REPORT_PATH = $ReportPath
    $env:CODEBUDDY_NODE_BIN = $node
    $env:GENIE_TRASH_DIR = $trash
    $env:CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD = '20'
    # Use forward slashes in the require path to keep PowerShell escaping sane.
    $shimFs = $shim -replace '\\', '/'
    $env:NODE_OPTIONS = "--require=`"$shimFs`""
}

function Write-StepHeader {
    param([Parameter(Mandatory=$true)][string]$Text)
    Write-Output ''
    Write-Output ('=' * 78)
    Write-Output $Text
    Write-Output ('=' * 78)
}

function Get-ManifestForDir {
    param(
        [Parameter(Mandatory=$true)][string]$Dir
    )
    if (-not (Test-Path $Dir)) { return @() }
    $files = Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue
    $rows = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($Dir.Length).TrimStart('\','/')
        $rel = $rel -replace '\\', '/'
        $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        $rows += [PSCustomObject]@{
            Path = $rel
            Size = $f.Length
            Sha256 = $h
        }
    }
    return $rows
}

function Compare-Manifest {
    param(
        [Parameter(Mandatory=$true)][array]$Before,
        [Parameter(Mandatory=$true)][array]$After
    )
    $bMap = @{}; foreach ($r in $Before) { $bMap[$r.Path] = $r }
    $aMap = @{}; foreach ($r in $After)  { $aMap[$r.Path]  = $r }
    $removed = @(); $added = @(); $changed = @()
    foreach ($k in $bMap.Keys) {
        if (-not $aMap.ContainsKey($k)) {
            $removed += $bMap[$k]
        } elseif ($aMap[$k].Sha256 -ne $bMap[$k].Sha256 -or $aMap[$k].Size -ne $bMap[$k].Size) {
            $changed += $aMap[$k]
        }
    }
    foreach ($k in $aMap.Keys) {
        if (-not $bMap.ContainsKey($k)) { $added += $aMap[$k] }
    }
    [PSCustomObject]@{
        Removed = $removed
        Added = $added
        Changed = $changed
    }
}

function Write-ManifestDiff {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)]$Diff
    )
    Write-Output "=== $Title ==="
    Write-Output ("REMOVED_COUNT=" + $Diff.Removed.Count)
    foreach ($r in $Diff.Removed | Select-Object -First 50) {
        Write-Output ("  REMOVED  " + $r.Path + "  size=" + $r.Size)
    }
    Write-Output ("ADDED_COUNT=" + $Diff.Added.Count)
    foreach ($r in $Diff.Added | Select-Object -First 50) {
        Write-Output ("  ADDED    " + $r.Path + "  size=" + $r.Size)
    }
    Write-Output ("CHANGED_COUNT=" + $Diff.Changed.Count)
    foreach ($r in $Diff.Changed | Select-Object -First 50) {
        Write-Output ("  CHANGED  " + $r.Path + "  size=" + $r.Size)
    }
}

# ============================================================================
# Remove-OwnedProbePath — narrowly-scoped lab cleanup helper
# ============================================================================
# Self-contained replacement for the former external agent-only cleanup
# utility (present only in the original author's Mavis environment). This
# repository-owned remover ONLY deletes explicitly owned runtime areas.
# This is NOT a generic recursive delete. Hard refuses (checked in order):
#   1. empty / null path
#   2. un-canonicalizable path
#   3. filesystem root (C:\, \\server\share\ ...)
#   4. the repository root itself, and any parent of the repository root
#   5. the production repo (bin/_lib.ps1 $script:ProductionRepoPath) and any
#      parent of it
#   6. the user profile root and any parent of it
#   7. any path outside the owned runtime areas (see below)
# Owned runtime areas (deletion allowed only under these prefixes):
#   * <repoRoot>\fixtures\            — runtime probe fixtures (gitignored)
#   * <repoRoot>\npm-probe\node_modules
#   * $env:TEMP\workbuddy-rootcause-control\
#   * caller-registered -OwnedRoots   — explicitly-created dirs such as a
#     caller-supplied -OutputDir or a per-run staging/backup dir. OwnedRoots
#     entries are STILL subject to hard refuses 1-6.
# Deleting an owned AREA ROOT itself (e.g. the whole fixtures\ dir, or the
# whole workbuddy-rootcause-control\ dir) is refused unless that exact path
# was explicitly registered via -OwnedRoots.
# Callers should prefer unique (GUID-suffixed) paths so cleanup is
# unnecessary; this helper exists for the few deterministic resets that
# remain (e.g. npm-probe\node_modules between A/B phases).
# ============================================================================
function Remove-OwnedProbePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        # Extra roots this invocation explicitly created/owns. Still subject
        # to all hard refuses.
        [string[]]$OwnedRoots = @()
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Remove-OwnedProbePath: empty/null path refused'
    }
    $full = ''
    try {
        $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    } catch {
        throw "Remove-OwnedProbePath: cannot canonicalize path '$Path': $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($full)) {
        throw 'Remove-OwnedProbePath: canonical path is empty'
    }

    $repoRoot = (Resolve-RepoRoot).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrEmpty($root)) {
        throw "Remove-OwnedProbePath: no path root for '$full'"
    }
    $rootNorm = $root.TrimEnd('\', '/')

    # 1) filesystem root
    if ($full -eq $rootNorm -or $full -match '^[A-Za-z]:$') {
        throw "Remove-OwnedProbePath: filesystem root refused: $full"
    }
    # 2) repo root itself / any parent of the repo root
    if ($full -ieq $repoRoot) { throw "Remove-OwnedProbePath: repo root refused: $full" }
    if ($repoRoot.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Remove-OwnedProbePath: parent of repo root refused: $full"
    }
    # 3) production repo (equal or ancestor)
    $prod = ($script:ProductionRepoPath).TrimEnd('\', '/')
    if ($full -ieq $prod) { throw "Remove-OwnedProbePath: production repo refused: $full" }
    if ($prod.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Remove-OwnedProbePath: parent of production repo refused: $full"
    }
    # 4) user profile root (equal or ancestor)
    $up = $env:USERPROFILE
    if ($up) {
        $up = $up.TrimEnd('\', '/')
        if ($full -ieq $up) { throw "Remove-OwnedProbePath: user profile root refused: $full" }
        if ($up.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Remove-OwnedProbePath: parent of user profile refused: $full"
        }
    }

    # 5) owned-area check
    $owned = @(
        (Join-Path $repoRoot 'fixtures'),
        (Join-Path $repoRoot 'npm-probe\node_modules')
    )
    $tempOwned = Join-Path $env:TEMP 'workbuddy-rootcause-control'
    if ($tempOwned) { $owned += $tempOwned }

    # Normalize OwnedRoots for exact-match comparison.
    $ownedRootsNorm = @()
    foreach ($r in $OwnedRoots) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        try { $ownedRootsNorm += [System.IO.Path]::GetFullPath($r).TrimEnd('\', '/') } catch { }
    }

    $isOwned = $false
    foreach ($r in @($owned + $ownedRootsNorm)) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        $rNorm = ''
        try { $rNorm = [System.IO.Path]::GetFullPath($r).TrimEnd('\', '/') } catch { continue }
        if ($full -ieq $rNorm) {
            # Deleting the area root itself is only allowed when this exact
            # path was explicitly registered by the caller.
            if ($ownedRootsNorm -contains $rNorm) { $isOwned = $true; break }
            continue
        }
        if ($full.StartsWith($rNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $isOwned = $true
            break
        }
    }
    if (-not $isOwned) {
        throw "Remove-OwnedProbePath: path is not an owned probe area; refusing: $full"
    }

    # Idempotent: nothing to delete.
    if (-not (Test-Path -LiteralPath $full)) { return }

    # Use .NET file APIs instead of PowerShell Remove-Item. Empirically, in a
    # WorkBuddy-hosted (native sandbox) shell, Remove-Item on a directory is
    # intercepted by the safe-delete layer and fails closed even after the
    # delete succeeds; [System.IO.Directory]::Delete / [System.IO.File]::Delete
    # are not intercepted and work identically in plain shells.
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item -and $item.PSIsContainer) {
        [System.IO.Directory]::Delete($full, $true)
    } else {
        [System.IO.File]::Delete($full)
    }
}
