param(
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $packageRoot) {
    throw 'Choose a new, empty package directory; existing destinations are never overwritten.'
}
New-Item -ItemType Directory -Path $packageRoot | Out-Null
$addonSource = Join-Path $repoRoot 'addons/kimodo_motion'
$addonTarget = Join-Path $packageRoot 'addons/kimodo_motion'
New-Item -ItemType Directory -Path $addonTarget -Force | Out-Null
$files = Get-ChildItem -LiteralPath $addonSource -Recurse -File
foreach ($file in $files) {
    if ($file.Extension -notin @('.gd', '.uid', '.cfg', '.md')) {
        throw "Unexpected add-on asset; review the package allowlist: $($file.FullName)"
    }
    $relative = [IO.Path]::GetRelativePath($addonSource, $file.FullName)
    $target = Join-Path $addonTarget $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $packageRoot 'LICENSE')
Write-Host "Packaged only addons/kimodo_motion and LICENSE in $packageRoot"
Write-Host 'No tests, models, animations, Python environments, weights, or credentials are included.'
