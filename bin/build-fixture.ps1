# build-fixture.ps1
# Build a small or large fixture tree under the supplied root.
# Usage: build-fixture.ps1 <root> <count>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][int]$Count
)
$ErrorActionPreference = 'Stop'
if (Test-Path $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
New-Item -ItemType Directory -Path $Root -Force | Out-Null
1..$Count | ForEach-Object {
    $i = $_.ToString('D3')
    $f = Join-Path $Root ("file-{0}.txt" -f $i)
    Set-Content -LiteralPath $f -Value ("payload-{0}" -f $i) -Encoding ASCII
}
Write-Output ("BUILT {0} files under {1}" -f $Count, $Root)
