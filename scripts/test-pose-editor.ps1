param(
    [string]$GodotPath = 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe',
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
$poseRepo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path ([IO.Path]::GetTempPath()) ('kimodo-pose-editor-' + [guid]::NewGuid().ToString('N'))
}
& (Join-Path $PSScriptRoot 'package-addon.ps1') -Destination $Destination
$poseProject = [IO.Path]::GetFullPath($Destination)
$probeDirectory = Join-Path $poseProject 'addons/editor_pose_probe'
New-Item -ItemType Directory -Path $probeDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $poseRepo 'tests/editor_pose_probe.gd') -Destination (Join-Path $probeDirectory 'plugin.gd')
@'
[plugin]
name="Pose editor integration probe"
description="Isolated editor acceptance harness"
author="Kimodo Motion Studio"
version="1.0"
script="plugin.gd"
'@ | Set-Content -LiteralPath (Join-Path $probeDirectory 'plugin.cfg')
@'
config_version=5
[application]
config/name="Isolated Pose Editor Check"
[editor_plugins]
enabled=PackedStringArray("res://addons/kimodo_motion/plugin.cfg", "res://addons/editor_pose_probe/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $poseProject 'project.godot')
$poseArguments = @('--editor', '--path', ('"' + $poseProject + '"'), '--quit-after', '600')
$poseProcess = Start-Process -FilePath $GodotPath -ArgumentList $poseArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $poseProject 'editor-test.stdout.log') -RedirectStandardError (Join-Path $poseProject 'editor-test.stderr.log')
$poseExit = $poseProcess.ExitCode
$poseOutput = @(Get-Content -LiteralPath (Join-Path $poseProject 'editor-test.stdout.log')) + @(Get-Content -LiteralPath (Join-Path $poseProject 'editor-test.stderr.log'))
$poseOutput | Write-Host
$poseText = $poseOutput -join "`n"
if ($poseExit -ne 0 -or $poseText -match '(?m)^(SCRIPT ERROR|ERROR:)' -or $poseText -match 'Orphan|ObjectDB instances leaked|resources still in use at exit' -or $poseText -notmatch 'PASS: actual editor native pose keys') {
    throw "Actual editor pose test failed; isolated outputs retained in $poseProject"
}
Write-Host "Isolated editor artifacts retained in $poseProject"
