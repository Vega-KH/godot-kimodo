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

The intended basic product workflow is not complete yet: durable take history,
full-skeleton retargeting, rig-aware export, and explicit undoable acceptance
into a production animation library now work. General rig setup and final
workflow hardening remain before the basic stage is complete.

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
plugin restart, durable archives, production-library acceptance, native baking,
and short playback scene runs, with:

```powershell
& .\scripts\test.ps1
```

## AI Motion dock

Enable **Kimodo Motion Studio** under **Project > Project Settings > Plugins**.
The **AI Motion** dock appears on the right at a quiet session chooser. Create a
named session or open a recent/project-owned `.tres`; backend, generation,
preview, and output controls do not appear until a session is active. Goal 16
introduces session schema v2. Earlier test sessions and Goal 13 `MotionDraft`
resources are rejected unchanged rather than migrated or assigned archives
that never existed.

Sessions save atomically under `res://animations/kimodo/sessions`. There is no
manual session Save button: editable fields are debounced, while session
creation, target changes, Generate, animation saves, session switches, and
editor shutdown force persistence. A visible Saved/Saving/error indicator
reports the state. The active workspace is divided into **Generate**,
**Preview & Save**, and **History** tabs instead of presenting every control at
once.

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
response is converted through the humanoid intermediate and onto the selected
character automatically. It starts playing in the combined **Preview & Save**
workspace with shared Pause/Play, Loop, and timeline-scrub controls. Use the
take selector there to switch variations without changing playback time or the
camera; the selected preview is also the take that Save exports. Before the UI
reports success, every take in the batch is stored as a lightweight SOMA-77
`AnimationLibrary` and verified. The open session then appends an immutable
generation record containing the exact request and capability documents,
protocol/model/fps/skeleton identity, UTC time, and request/capability/response
SHA-256 hashes plus a stable ID, sample index/name, and decoded-motion hash for
each take. All takes in one response share the request seed. Editing the next
prompt does not rewrite that record.

Automatic source archives live under
`res://animations/kimodo/session_data/<session_id>/`. A deduplicated, versioned
rig snapshot records the exact SOMA-77 hierarchy and rest transforms associated
with each library. Its contract version and complete-content signature prevent
a later rig revision from silently reinterpreting old motion. Generation
manifests and same-parent staging make an interrupted promotion/session-save
window recoverable; controlled failures commit none of the batch.

The **History** tab groups generations chronologically by prompt and time and
lists every take in response order. Selecting an available historical take
reloads it without the backend, reconstructs its archived SOMA source, and
regenerates the current humanoid and character previews on demand. These scene
instances and derived previews are disposable cache. Source takes remain until
the user confirms deletion; deletion retains a truthful tombstone and never
removes a separately saved animation or Character Preview. Missing or corrupt
archive files are reported rather than regenerated or hidden.

The preview follows planar root motion by default so locomotion remains in
frame. Left-drag directly on the preview to orbit, use the mouse wheel to zoom,
toggle **Follow Root** to keep a fixed world view, and press **Reset View** to
restore the default angle and distance. Camera angle and zoom stay synchronized
when switching between the SOMA-77 and humanoid previews.

Each generated take includes a non-destructive in-memory copy on the
repository's 56-bone Godot humanoid A-pose. The preview layer selector switches
between the cyan SOMA-77 source, pink humanoid intermediate, and selected
character result while all three remain at the same playback time.

The selected target must contain exactly one `Skeleton3D`, finite/invertible rest
transforms, and at least one bound skin with matching bind and rest poses.
One positive uniform bind-space scale shared by every skin binding is accepted
(for example, importer compensation for a scaled parent empty). It is detected,
not applied to or removed from the asset. Per-bone/per-mesh scale differences
and rotated, translated, reflected, sheared or non-uniform bind-space offsets
remain incompatible.
Incompatible assets receive a message identifying the affected mesh/bone and
the repair needed before re-export. Rotation-only transfer also rejects reflected,
sheared, or materially non-uniform bone rest scales; ordinary scene-node
transforms and small exporter rounding are handled separately. Exact Godot humanoid names configure
Jenny automatically. Other regular humanoid rigs open the focused **Rig Setup**
tab, where deterministic suggestions show their confidence and evidence, every
canonical role has an editable target or explicit Unmapped choice, and the
artist certifies a versioned project-owned `KimodoRigProfile`. Rig mappings are
suggested using bounded token/alias and parent-chain evidence, not arbitrary
fuzzy guesses. Neutral `.x` markers and exporter IDs are recognized while
meaningful spine/finger numbers remain available. Close candidates stay
unselected; alternatives lead the dropdown and explain their evidence.
**Suggest Unmapped** fills only unreviewed empty rows, preserving manual and
certified omissions. **Reset Suggestions** explicitly discards current choices.
Profile data and palm landmarks remain authoritative when reopened.
Profiles are
reused only for the exact recorded skeleton signature; a changed rig returns to
setup instead of silently applying stale mappings. The matcher understands
normalized namespaces/prefixes, Mixamo aliases, sided `.L`/`.R` or `_L`/`_R`
names, and numbered chains, while manual choices always win. Pelvis, head,
hands, feet and major limb chains are required, along with at least one mapped
Spine/Chest/UpperChest segment. Neck, shoulders, toes, extra torso segments,
eyes, jaw and digits may be intentionally unmapped. Every mapped subset must
retain anatomical chain order; different bone index ordering is supported.
Wrist transfer uses a shared palm frame with saved **source role / target bone**
landmark pairs in the bottom of Rig Setup. Suggestions use available finger
geometry (for example, index-to-ring on a four-finger hand). Artists can review
and replace these pairs. Missing or collinear palm geometry cannot certify;
fingerless rigs need usable explicit palm landmarks and are not silently guessed.
The frame preserves flexion and roll across differing rest bases. Every
finger and thumb joint shares that same palm frame instead of independently
aligning a single segment direction; this keeps bone roll determinate and
prevents large compensating twists in skinned thumbs.
Omitted torso/intermediate roles do not discard the mapped descendant's source
motion. Goal 18 schema-1 profiles upgrade in memory only when their certified
skeleton signature matches; the disk resource changes only on explicit Save Profile.
Unmapped branch bones, such as ponytail bones under `Head`, receive no Kimodo
tracks and continue to inherit their animated parent normally. Changing the
character rebuilds the derived preview automatically. **Clear** removes only
the target and derived preview.

Root travel is profile data rather than a character-name special case. Jenny
uses distinct `Root` and `Hips` roles. A conventional Mixamo rig uses the
explicit **Hips is skeleton root** policy, which combines source root travel
and pelvis displacement into one scaled Hips position track. No synthetic bone
is inserted. Camera **Follow Root** follows the profile's effective motion bone,
so it follows mapped Hips for a Hips-as-root rig instead of requiring a literal
bone named `Root`. Translation scaling uses recorded leg-height measurements;
target animation libraries already embedded in imported scenes are ignored and
remain unmodified and unplayed while Kimodo owns a separate disposable preview
player.

Private compatibility models belong under `tests/private_models/`, whose
contents are gitignored except for its guide. Clean repository tests skip those
checks when a licensed local fixture is absent.

To keep the selected result, choose **Character animation** (the default),
**Humanoid animation**, **SOMA-77 animation**, or **Character Preview**, then
press **Save…**. Godot's save dialog chooses the project location and filename,
so the dock has no separate directory or name fields. The three animation
choices create one lightweight `.res` `AnimationLibrary` in the selected rig's
track namespace. Character Preview creates one large, self-contained `.tscn`
with the selected character baked in. Its detached saved copy contains only the
selected Kimodo animation player; imported animation players are omitted from
that preview artifact while the selected source scene and live preview remain
untouched. Canonical path validation keeps output inside `res://`, and existing
files are rejected rather than overwritten.
Attach a character animation library to an `AnimationPlayer` under the same
character root to inspect or play its `motion` animation in Godot's Animation
panel. Successful saves record their rig layer, artifact form, target signature
where relevant, and selected-take provenance in the open session.
Saving does not interrupt the temporary preview, and a saved animation remains
usable after the backend stops.

**Save** and **Accept** serve different purposes. Save creates a standalone
export and rejects an existing filename. The separate **Accept into production
library** section adds the selected character take under an artist-chosen name
inside a new or existing project-owned `.res` `AnimationLibrary`. A collision
does nothing until the artist explicitly confirms Replace. Add, Replace, and
new-library creation are each one Godot editor action: Undo restores the exact
captured library bytes and prior session acceptance state, while Redo restores
the same captured animation without contacting the backend or retargeting it
again. Undoing the first animation added to a newly created destination retains
the now-empty library as an artist-owned project resource; delete that container
manually if it is no longer wanted.

Acceptance preflights the current target signature, AnimationPlayer root,
duration, finite keys, every character track path, and a staged library reload
against a clean target instance. Paths outside `res://`, `.godot` import data,
read-only files, wrong resource types, and unresolved tracks are rejected before
the production file changes. The session records take/generation identity,
target signature, destination and animation name, Add/Replace mode, timestamps,
and semantic/file hashes separately from Save artifacts and automatic archives.
Deleting an accepted source take removes only its automatic archive; the
production library remains editable and playable without Kimodo or the backend.

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
