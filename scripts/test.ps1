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
    $rawOutput = & $GodotPath @GodotArguments 2>&1
    $exitCode = $LASTEXITCODE
    $knownCertificateDiagnostic = $rawOutput -match 'Failed to read the root certificate store'
    $output = $rawOutput | Where-Object {
        $_ -notmatch 'Failed to read the root certificate store' -and
        $_ -notmatch 'get_system_ca_certificates'
    }
    $output | Write-Host
    if ($knownCertificateDiagnostic) {
        Write-Host 'NOTE: ignored the known sandboxed-Windows root certificate-store diagnostic.'
    }
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
Invoke-GodotCheck -Name 'Typed capability contract' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_capabilities_parser.gd'
)
Invoke-GodotCheck -Name 'Asynchronous capability transport' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_capabilities_client.gd'
)
Invoke-GodotCheck -Name 'Typed generation and response contract' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_generation_contract.gd'
)
Invoke-GodotCheck -Name 'Asynchronous generation and preview' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_generation_client.gd'
)
Invoke-GodotCheck -Name 'AI Motion dock state and lifecycle' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_ai_motion_dock.gd'
)
Invoke-GodotCheck -Name 'Focused editor UI component ownership' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_ui_components.gd'
)
Invoke-GodotCheck -Name 'MotionDraft persistence and provenance' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_motion_draft.gd'
)
Invoke-GodotCheck -Name 'KimodoSession persistence and legacy rejection' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_motion_session.gd'
)
Invoke-GodotCheck -Name 'Durable generated-take archive' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_take_archive.gd'
)
Invoke-GodotCheck -Name 'Undoable production-library acceptance' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_acceptance_service.gd'
)
Invoke-GodotCheck -Name 'Multiple take response contract' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_multiple_takes.gd'
)
Invoke-GodotCheck -Name 'Session-first multi-take dock lifecycle' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_motion_draft_dock.gd'
)
Invoke-GodotCheck -Name 'Editor plugin restart' -GodotArguments @(
    '--headless', '--editor', '--path', '.', '--quit'
)
Invoke-GodotCheck -Name 'SOMA-77 fixture contract' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_soma77_fixture.gd'
)
Invoke-GodotCheck -Name 'Native animation round trip' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_native_roundtrip.gd'
)
Invoke-GodotCheck -Name 'Generated preview native save' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_preview_native_save.gd'
)
Invoke-GodotCheck -Name 'Native runtime independence' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_native_runtime.gd'
)
Invoke-GodotCheck -Name 'Humanoid retarget and native reload' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_humanoid_retarget.gd'
)
Invoke-GodotCheck -Name 'Humanoid dock preview and save lifecycle' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_humanoid_dock_retarget.gd'
)
Invoke-GodotCheck -Name 'Jenny skinned-character retarget and reload' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_jenny_character_retarget.gd'
)
Invoke-GodotCheck -Name 'Versioned rig profiles and deterministic matching' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_rig_profile.gd'
)
Invoke-GodotCheck -Name 'Private Remy profile workflow when staged' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_private_remy_workflow.gd'
)
Invoke-GodotCheck -Name 'Generic variant anatomy, geometry and saved playback' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_rig_variants.gd'
)
Invoke-GodotCheck -Name 'Bounded evidence-based rig matching' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_rig_matching.gd'
)
Invoke-GodotCheck -Name 'Private universal Remy workflow when staged' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_private_remy_workflow.gd',
    '--', '--universal'
)
Invoke-GodotCheck -Name 'Private common-parent feasibility when staged' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_private_common_pelvis.gd'
)
Invoke-GodotCheck -Name 'Private import compatibility and actionable rejection when staged' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_private_variant_import.gd'
)
Invoke-GodotCheck -Name 'Private Jenny04 complete workflow when staged' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_private_jenny04_workflow.gd'
)
Invoke-GodotCheck -Name 'Dock skinned-character preview and save lifecycle' -GodotArguments @(
    '--headless', '--path', '.', '--script', 'res://tests/test_character_dock_retarget.gd'
)
Invoke-GodotCheck -Name 'Playback scene smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/fixtures/soma77_playback.tscn', '--quit-after', '5'
)
Invoke-GodotCheck -Name 'Native playback scene smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/native/soma77_native_playback.tscn', '--quit-after', '5'
)
Invoke-GodotCheck -Name 'Humanoid retarget playback smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/retargeting/humanoid_retarget_playback.tscn', '--quit-after', '5'
)
Invoke-GodotCheck -Name 'Jenny skinned-character playback smoke test' -GodotArguments @(
    '--headless', '--path', '.', '--scene',
    'res://tests/characters/jenny_retarget_playback.tscn', '--quit-after', '5'
)

Write-Host 'PASS: all Godot checks completed without engine or script errors.'
