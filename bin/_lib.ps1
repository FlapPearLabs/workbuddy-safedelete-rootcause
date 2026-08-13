# _lib.ps1 - shared library for the repro bundle
# Sourced by all repro scripts. Provides:
#   * Resolve-WorkbuddyInstallPath
#   * Assert-CleanWorkbuddyEnv
#   * Set-WorkbuddyShimEnv
#   * Write-StepHeader
#   * Resolve-RepoRoot
#   * Manifest-Capture (path + size + sha256)
#   * Manifest-Diff

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
