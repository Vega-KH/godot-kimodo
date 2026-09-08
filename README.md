# Kimodo Motion Studio for Godot

An open-source Godot 4.7 editor extension for authoring humanoid animation
with the local `kimodo-godot-server` backend.

The project is at an early development milestone. Its current vertical slice
connects an editor dock asynchronously to a loopback MMCP backend, submits
typed text-to-motion requests, validates the returned SOMA-77 glTF, and plays
the result immediately in a line-skeleton preview. Recorded motion can also be
validated and baked into a self-contained native Godot scene and
`AnimationLibrary`. A saved SOMA-77 take can additionally be retargeted to a
distinct Godot `SkeletonProfileHumanoid` fixture with explicit rest correction.

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

See the [transport fixture guide](tests/fixtures/README.md) for provenance and
the [native fixture guide](tests/native/README.md) for baking, dependency, and
manual playback details. The [humanoid retarget guide](tests/retargeting/README.md)
records the 22-bone body map, ignored joints, generated A-pose fixture, and
side-by-side acceptance scene.

Run the complete offline suite, including capability transport failure cases,
plugin restart, native baking, and short playback scene runs, with:

```powershell
& .\scripts\test.ps1
```

## AI Motion dock

Enable **Kimodo Motion Studio** under **Project > Project Settings > Plugins**.
The **AI Motion** dock appears on the right and defaults to
`http://127.0.0.1:8000`. Start `kimodo-godot-server`, press **Connect**, and
confirm the summary reports `kimodo-soma-rp`, 30 fps, SOMA-77 (77 joints),
three constraint types, and six contact channels. Stop the backend and press
**Refresh** to exercise the recoverable error state; technical transport or
contract details are expandable without blocking the editor.

Once connected, enter a prompt and choose a frame count, denoising-step count,
and seed, then press **Generate**. The request runs asynchronously and can be
canceled. The default 100 denoising steps favors normal-quality previews; lower
values trade quality for speed. A valid response starts playing in the embedded
SOMA-77 preview with Pause/Play and Loop controls.

To keep a generated result, enter a project-relative directory beginning with
`res://` and a take name, then press **Save Native Take**. The dock creates a
self-contained `.tscn` plus `.res` `AnimationLibrary`, selects the scene in the
FileSystem dock, and adds a numeric suffix rather than overwriting an existing
take. Saving does not interrupt or transfer ownership of the temporary preview,
and a saved take remains usable after the backend stops.

The entire dock scrolls vertically when its contents exceed the available
editor height, including after the animation preview becomes visible.

For a lightweight connection-only check, start the server with
`--text-encoder-mode dummy`. For real prompt-driven generation on the reference
machine, double-click `start.bat` in the backend checkout. The equivalent
PowerShell command is:

```powershell
cd C:\code\godot-kimodo\kimodo-godot-server
$env:TEXT_ENCODER_DEVICE = 'cpu'
.\.venv\Scripts\kimodo-godot-server.exe `
  --host 127.0.0.1 --port 8000 --device cuda:0 --text-encoder-mode local
```

Wait for the server's `ready` message before connecting. The full encoder has
previously used about 28.5 GiB of total system memory, so close other
memory-heavy applications first.

The initial transport deliberately accepts only plain HTTP on IPv4 loopback
or `localhost`. Remote hosts and TLS are future explicit design decisions.

For a command-line live handshake against a running server:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/test_live_capabilities.gd -- `
  --url http://127.0.0.1:8000
```

The corresponding end-to-end dock-generation check is:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/test_live_generation.gd -- `
  --url http://127.0.0.1:8000
```

## License

Original extension code is MIT licensed. Model, backend, and test-fixture
provenance are recorded separately; no model weights are included.
