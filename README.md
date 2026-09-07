# Kimodo Motion Studio for Godot

An open-source Godot 4.7 editor extension for authoring humanoid animation
with the local `kimodo-godot-server` backend.

The project is at an early development milestone. Its current vertical slice
connects an editor dock asynchronously to a loopback MMCP backend, submits
typed text-to-motion requests, validates the returned SOMA-77 glTF, and plays
the result immediately in a line-skeleton preview. Recorded motion can also be
validated and baked into a self-contained native Godot scene and
`AnimationLibrary`.

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
manual playback details.

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

Once connected, enter a prompt, choose a frame count and seed, and press
**Generate**. The request runs asynchronously and can be canceled. A valid
response starts playing in the embedded SOMA-77 preview with Pause/Play and
Loop controls. Generating another take replaces only the temporary preview;
it does not overwrite fixtures or native animation assets.

For a lightweight connection-only check, start the server with
`--text-encoder-mode dummy`. For real prompt-driven generation on the reference
machine, use the full encoder on CPU:

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
