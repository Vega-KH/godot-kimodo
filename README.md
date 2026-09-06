# Kimodo Motion Studio for Godot

An open-source Godot 4.7 editor extension for authoring humanoid animation
with the local `kimodo-godot-server` backend.

The project is at an early development milestone. Its current vertical slice
loads a recorded MMCP SOMA-77 animation from memory, validates the imported
skeleton and tracks headlessly, and provides a skeleton-only playback scene.

## Reference environment

- Godot 4.7.2 stable (`ed1daf0bf`)
- Windows development executable:
  `C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe`
- Backend: <https://github.com/Vega-KH/kimodo-godot-server>

## Automated check

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/test_soma77_fixture.gd
```

See [the fixture guide](tests/fixtures/README.md) for provenance and manual
playback instructions.

Run the complete Goal 4 checks, including plugin startup and a short playback
scene run, with:

```powershell
& .\scripts\test.ps1
```

## License

Original extension code is MIT licensed. Model, backend, and test-fixture
provenance are recorded separately; no model weights are included.

