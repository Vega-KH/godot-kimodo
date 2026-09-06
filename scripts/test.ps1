param(
    [string]$GodotPath = 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot console executable not found: $GodotPath"
}

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$GodotArguments
    )

    Write-Host "==> $Name"
    $output = & $GodotPath @GodotArguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | Write-Host
    $text = $output -join "`n"
    if ($exitCode -ne 0) {
        throw "$Name exited with code $exitCode"
    }
    if ($text -match '(?m)^(SCRIPT ERROR|ERROR:)') {
        throw "$Name emitted a Godot error"
    }
}

Invoke-GodotCheck -Name 'Editor plugin startup' -GodotArguments @(
    '--headless', '--editor', '--path', '.', '--quit'
)
Invoke-GodotCheck -Name 'SOMA-77 fixture contract' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_soma77_fixture.gd'
)
Invoke-GodotCheck -Name 'Native animation round trip' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_native_roundtrip.gd'
)
Invoke-GodotCheck -Name 'Native runtime independence' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_native_runtime.gd'
)
Invoke-GodotCheck -Name 'Playback scene smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/fixtures/soma77_playback.tscn', '--quit-after', '5'
)
Invoke-GodotCheck -Name 'Native playback scene smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/native/soma77_native_playback.tscn', '--quit-after', '5'
)

Write-Host 'PASS: all Godot checks completed without engine or script errors.'
