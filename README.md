# Kimodo Motion Studio for Godot

An open-source Godot 4.7 editor extension for authoring humanoid animation
with the local `kimodo-godot-server` backend.

The project has a working engineering vertical slice. Its editor dock connects
asynchronously to a loopback MMCP backend, submits typed text-to-motion
requests for one or two takes, validates every SOMA-77 glTF animation and its
matching metadata, and previews the selected result. Motion
can be saved as native SOMA-77 data, retargeted through a deterministic Godot
humanoid fixture, previewed on a selected exact-name compatible character, and
saved on the repository's skinned Auto-Rig Pro acceptance character.

The intended basic product workflow is not complete yet: take switching now
works, but saving an artifact is not yet an explicit undoable Accept operation
into an animation destination, and full-skeleton finger retargeting remains a
known gap.

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
side-by-side acceptance scene. The [skinned character guide](tests/characters/README.md)
records the Jenny fixture provenance, root-bone decision, import measurements,
and manual character playback controls.

Run the complete offline suite, including capability transport failure cases,
plugin restart, native baking, and short playback scene runs, with:

```powershell
& .\scripts\test.ps1
```

## AI Motion dock

Enable **Kimodo Motion Studio** under **Project > Project Settings > Plugins**.
The **AI Motion** dock appears on the right at a quiet session chooser. Create a
named session or open a recent/project-owned `.tres`; backend, generation,
preview, and output controls do not appear until a session is active. Existing
Goal 13 `MotionDraft` resources can be opened and are migrated to a new
`KimodoSession` without rewriting the original file.

Sessions save atomically under `res://animations/kimodo/sessions`. There is no
manual session Save button: editable fields are debounced, while session
creation, target changes, Generate, animation saves, session switches, and
editor shutdown force persistence. A visible Saved/Saving/error indicator
reports the state. The active workspace is divided into **Generate**,
**Preview**, and **Output** tabs instead of presenting every control at once.

The connection defaults to `http://127.0.0.1:8000`. Start
`kimodo-godot-server`, press **Connect**, and confirm the summary reports
`kimodo-soma-rp`, 30 fps, SOMA-77 (77 joints), three constraint types, and six
contact channels. Stop the backend and press **Refresh** to exercise the
recoverable error state; technical transport or contract details are
expandable without blocking the editor.

Once connected, choose a compatible character, enter a prompt, and choose a
frame count, denoising-step count, seed, and one or two takes, then press
**Generate**. Two is the current tested maximum even though the dependency
advertises a larger protocol ceiling. The request runs asynchronously. Cancel stops
the Godot client from waiting for that response; the current direct MMCP server
does not yet prove that active model inference stopped. The default 100
denoising steps favors normal-quality previews; lower values trade quality for
speed, while values up to 200 allow a slower higher-quality pass. A valid
response starts playing in the embedded SOMA-77 preview with shared Pause/Play,
Loop, and timeline-scrub controls. Use the take selector to switch variations
without changing playback time or the camera. The open session appends an immutable
generation record containing the exact request and capability documents,
protocol/model/fps/skeleton identity, UTC time, and request/capability/response
SHA-256 hashes plus a stable ID, sample index/name, and decoded-motion hash for
each take. All takes in one response share the request seed. Editing the next
prompt does not rewrite that record.

Unsaved take payloads are intentionally transient. They remain in memory while
the session is open and are discarded on session switch or editor shutdown;
the session retains only their provenance and summaries. Only a take the user
explicitly saves becomes a durable animation artifact. Reopening offline shows
the prior take summaries honestly but does not pretend discarded previews are
still playable.

The preview follows planar root motion by default so locomotion remains in
frame. Left-drag directly on the preview to orbit, use the mouse wheel to zoom,
toggle **Follow Root** to keep a fixed world view, and press **Reset View** to
restore the default angle and distance. Camera angle and zoom stay synchronized
when switching between the SOMA-77 and humanoid previews.

Press **Retarget to Humanoid** to build a non-destructive in-memory copy on
the repository's 56-bone Godot humanoid A-pose. The preview selector switches
between the cyan SOMA-77 source and pink humanoid result while both remain at
the same playback time. Enter a separate humanoid take name and press **Save
Humanoid Take** to create a self-contained `.tscn` and `.res`; errors and
output paths are reported independently from generation and source saving.

The selected target must contain exactly one `Skeleton3D`, the required exact
Godot humanoid body names including `Root` and `Hips`, finite rest transforms,
and at least one bound skin. This is a narrow convention validated with Jenny,
not yet general rig certification. After creating the humanoid intermediate,
press **Preview on Character** to add the target as a third synchronized preview
with the same playback, scrub, orbit, zoom, and root-follow controls. **Clear**
removes only the target and derived preview.

Enter a project-relative output directory and take name, then press **Save
Character Take**. The result is a uniquely named, self-contained `.tscn` that
does not modify the imported character or live previews. Open the saved scene,
select `KimodoAnimationPlayer`, and choose its `motion` animation to inspect or
edit the character-specific tracks in Godot's Animation panel. Successful
character, humanoid, and SOMA-77 saves are attached to the open session and
selected take as saved
artifacts; previews are never recorded as artifacts and saved artifacts are not
yet labeled accepted.

To keep a generated result, enter a project-contained `res://` directory and a
take name, then press **Save SOMA-77 Native Take**. Canonical path validation
rejects traversal outside the project. The dock creates a self-contained
`.tscn` plus `.res` `AnimationLibrary`, selects the scene in the FileSystem
dock, and adds a numeric suffix rather than overwriting an existing take.
Saving does not interrupt or transfer ownership of the temporary preview, and
a saved take remains usable after the backend stops.

Each workspace tab scrolls with the dock when its contents exceed the available
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
  --url http://127.0.0.1:8000 `
  --takes 2 `
  --steps 200 `
  --native-dir res://tests/.live `
  --humanoid-dir res://tests/.live
```

## License

Original extension code is MIT licensed. The bundled Jenny test character is
copyright © 2026 Kyle Howard and licensed separately under CC BY 4.0; its
attribution notice is in `tests/characters/fixtures/LICENSE.md`. Backend and
other test-fixture provenance are recorded separately; no model weights are
included.
