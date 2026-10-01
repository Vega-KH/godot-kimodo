param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$Character
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$characterPath = (Resolve-Path -LiteralPath $Character).Path
if ([IO.Path]::GetExtension($characterPath) -ne '.glb') {
    throw 'This clean-install smoke harness imports one GLB character.'
}
& (Join-Path $PSScriptRoot 'package-addon.ps1') -Destination $Destination
$projectRoot = [IO.Path]::GetFullPath($Destination)
Copy-Item -LiteralPath (Join-Path $repoRoot 'tests/clean_project/project.godot.template') -Destination (Join-Path $projectRoot 'project.godot')
Copy-Item -LiteralPath (Join-Path $repoRoot 'tests/test_clean_project.gd') -Destination (Join-Path $projectRoot 'test_driver.gd')
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'models') | Out-Null
Copy-Item -LiteralPath $characterPath -Destination (Join-Path $projectRoot 'models/character.glb')
Write-Host "Clean project ready: $projectRoot"
Write-Host 'Only the smoke harness and privately supplied character were added to the add-on package.'
Write-Host 'Import with Godot --headless --editor --path <project> --quit, then run test_driver.gd.'
