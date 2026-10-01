# Agent handoff — start here after the product plan

Reviewed: 2026-10-01. Stage 1 is finished; the next session proposes Goal 22
(poses) before implementation. Read [the docs index](README.md) in order.
Do not mistake historical "pending" notes in Git for current blockers.

## Workspace and checkpoints

- Combined workspace: `C:/code/godot-kimodo/`, **not** a Git repository.
- Extension: `godot-kimodo/`, branch `main`, origin
  `https://github.com/Vega-KH/godot-kimodo.git`; Stage 1 code `7e9d1a8`.
- Backend: `kimodo-godot-server/`, branch `codex/milestone-0-bootstrap`,
  origin `https://github.com/Vega-KH/kimodo-godot-server.git`; Stage 1 `0f1d347`.
  Do not rename/merge branches as part of ordinary documentation or goal work.
- Fork provenance: Animatica `motionmcp-kimodo` at
  `99a88e6ceae89bdc9734503dd06cd61d9d82ed1b`; preserve upstream history,
  Apache notices and the `motionmcp_kimodo` namespace.
- Shared development docs now live in extension `docs/`. Backend `docs/`
  retains server guides and ADRs. Root's former plan moved here and is versioned.
- User has authorized pushing after completed and tested goals. No Stage 2 code
  is approved simply because Stage 1 passed.

## Local operation and testing

Reference engine: `C:/Godot-472/Godot_v4.7.2-stable_win64_console.exe`.
Backend root `start.bat` is the preferred launcher. It selects local text
encoding on CPU and motion inference on CUDA; wait for the server's ready message,
then connect to `http://127.0.0.1:8000`. The user normally closes the editor
during code work and can start the backend for GPU tests; do not assume it is running.

Backend `pyproject.toml` is the dependency authority:
Kimodo fork `3362b92c37faa100fb697972f0fc5485dd94dd4f`,
MMCP SDK `a298338bb3684a506ec313dce6d5cb12a6dc5167`,
Python 3.10.16 in the local `.venv`, PyTorch 2.12.1+cu130, uv 0.12.9.
Reference GPU: RTX 4070 Laptop, 8 GB VRAM. Cold full-text-encoder startup has
used about 28.52 GiB of system RAM; close memory-heavy apps first.
Existing gated Llama access works; never print or commit credentials.
Pinned Kimodo emits known torch.jit deprecation warnings.

From the extension repository:

```powershell
.\scripts\test.ps1
```

From the backend repository:

```powershell
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m ruff check .
```

Latest full checks: 35 Godot checks; backend 24 passed/7 hardware-specific skips;
Ruff passed. Treat unexpected engine/parser errors and orphan warnings as failures.
The owner-created Python venv and Godot AppData settings can be inaccessible
under restricted agent identity. Owner-context execution passes: this is sandbox
isolation, **not a broken Python installation**. Request normal permissions for
these tests rather than replacing environments or changing the test to hide errors.
If `rg` is unavailable, use PowerShell Select-String/Get-ChildItem.

Package: `scripts/package-addon.ps1 -Destination <new empty folder>`.
It allowlists add-on scripts/UIDs/config/guide and MIT LICENSE only.
Clean install: `scripts/create-clean-test-project.ps1 -Destination <new folder>
-Character <explicit private GLB>`; then:

```powershell
$godotExe = 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --editor --path '<new folder>' --quit
& $godotExe --headless --path '<new folder>' --script res://test_driver.gd
& $godotExe --headless --path '<new folder>' --script res://test_driver.gd -- --offline
```

The live smoke requires a compatible character that can certify its suggested map.
It creates one/two-take batches at 30 frames/100 steps and exports four forms.
Offline mode requires that intact smoke session and exports; it is not a generic
test of an arbitrary user-modified project. Use a **new** clean project if the
manual deletion test removed it. Optional `--capture-dir <path>` uses rendered
rather than headless runs for UI captures. Existing manual project:
`C:/code/godot-kimodo/stage1-clean-project`; useful test assets may have been deleted
during the accepted walkthrough. Captures: `.research/goal21-ui/` in combined root.

## Code map

Paths below are relative to `godot-kimodo/addons/kimodo_motion/`:

| Area | Starting files |
| --- | --- |
| Editor orchestration | `ui/ai_motion_dock.gd`, `plugin.gd` |
| Focused UI | `ui/session_shell.gd`, `generation_take_panel.gd`, `preview_save_panel.gd`, `history_panel.gd`, `rig_setup_panel.gd` (all under `ui/`) |
| Session identity/intent/autosave | `domain/motion_session.gd`, `motion_session_store.gd`, `motion_session_controller.gd` |
| Durable source/history | `domain/take_archive_service.gd`, `generation_archive_manifest.gd`, `soma77_rig_snapshot.gd`, `soma77_contract.gd` |
| Deletion and ownership | `domain/session_deletion_service.gd`, `session_lifecycle.gd`, `project_paths.gd` |
| Production library transactions | `domain/acceptance_service.gd` |
| MMCP and strict glTF decoding | `transport/`; capability/generation clients, request and response types |
| Native source baking | `animation/native_animation_baker.gd` |
| Profile and compatibility | `retargeting/kimodo_rig_profile.gd`, `rig_profile_store.gd`, `rig_compatibility.gd` |
| Conservative suggestions | `retargeting/rig_candidate_matcher.gd`, `rig_name_hints.gd`, `rig_geometry.gd` |
| Forward transfer | `retargeting/humanoid_retarget_baker.gd`, `humanoid_character_baker.gd`, `rest_orientation.gd`, `soma77_humanoid_map.gd` |

The dock still has historical `_draft` names; product state is `KimodoSession`
schema 2, not the obsolete MotionDraft. Do not mass-rename during pose work.
Backend `src/motionmcp_kimodo/`: `cli.py` launcher; `backbone.py` load/inference/
origin normalization; `translate.py` prompt/options/constraints; `skeleton.py`
canonical rig/contact declaration. SDK supplies HTTP/glTF serialization.

## Persistence and preservation traps

- Session `.tres`: default `res://animations/kimodo/sessions/`. Immutable
  generation records retain exact request/capability/response hashes and ordered
  take provenance. All samples share the request seed; there is no per-take seed.
- `res://animations/kimodo/session_data/<UUID>/`: source libraries, versioned
  deduplicated source rigs and immutable generation manifests. Batch promotion
  plus session write is recoverable, not a claim of cross-file filesystem atomicity.
- `rig_profiles/` is shared project data. Source libraries cannot reconstruct
  exact motion without their corresponding archived rest/hierarchy snapshot.
- Generated previews are disposable instances, not a durable animation store.
  Explicit Save exports and accepted production libraries are independent.
- Deletion verifies UUID/exclusive ownership/inventory; refuses links/junctions,
  shared files, protected outputs or unknown content. It stages renames with
  rollback/restart recovery. Tiny `session_deletions/<UUID>/` receipts remain
  after animation payload removal, preventing stale writers resurrecting sessions.
- Old Accept Undo/Redo must merge only acceptance metadata into latest saved
  session state, preserve dirty intent/new History, and still undo independent
  production libraries after the source session was deleted.
- Earlier pre-Goal-16 test sessions are deliberately rejected unchanged, not
  migrated. Do not treat the old permission to discard tests as permission to
  discard newly durable sessions.
- **Never stage, clean or overwrite user-owned `animations/`**. Private models
  belong in ignored `tests/private_models/`; original `Models/` is outside
  both repositories. Only the licensed bundled Jenny fixture is distributable.
- Tests/captures must use unique temporary character paths/profile identities.
  An old harness once removed a shared Remy profile; it was recovered with user
  confirmation and test isolation fixed. Do not test cleanup against artist profiles.

## Rig and generation rules that must survive

- SOMA-77 at the service/output boundary, SOMA-30 only for internal constraints,
  six contact channels, 30 fps. Preserve strict skeleton-only 77-node glTF validation.
- One/two takes tested; default 100 diffusion steps, maximum 200.
  **Stop waiting** invalidates client state; inference may still continue.
- Root travel follows profile policy, including Hips-as-root. Camera uses the
  effective mapped motion bone, never assumes a literal bone named Root.
- Complete and partial regular humanoids use reviewed semantic profiles.
  Bone reindexing/naming must not change transfer for an equivalent manual map.
  Missing optional torso/digit/face bones and extra hair/eye branches are supported.
  Unmapped bones inherit their parent at rest; no synthetic Kimodo tracks/IK invented.
- Require matching bind/rest; shared positive uniform bind-space scale is benign.
  Non-uniform/reflected/sheared or inconsistent offsets get actionable rejection.
  Changing a map cannot fix a bad skin bind.
- Suggestions are bounded, evidence-ranked and uncertain when needed; manual
  mappings, certified omissions and saved palm landmarks win on reopen.
  Profile signatures invalidate stale rig choices.
- Palm transfer uses **two axes** and a shared wrist/finger/thumb frame. Independent
  one-vector phalanx alignment caused backward thumbs. Preserve its regressions.
  Source finger articulation is limited by Kimodo training, not a reason to discard data.
- Save Character animation is a small rig-specific library; Character Preview
  intentionally contains a large full model. Saved previews contain only the
  selected Kimodo player; original imported animation players remain untouched.
- Accept is Add/confirmed Replace with exact Undo/Redo; Undo of first-add retains
  the empty artist-owned library.

## Pose-specific investigation notes

The backend already advertises `pose_keyframe`; this is not proof of an
editor authoring workflow. `translate.py::_pose_keyframe` consumes **local**
xyzw joint quaternions on `model.skeleton` (SOMA-30), optional root position and
a frame. It performs FK and chooses FullBody/EndEffector constraints according
to fill mode/joints. Presentation-only joints yield `unknown_joint`.
Verify partial fill semantics, shared names, rest basis and heading against
tests/dependencies before designing a pose schema.

Godot skeleton "global pose" means skeleton-relative, not scene-world.
Keep pose rotations, skeleton origin, scene placement and timeline time separate.
Retargeting collapses joints and compensates rest/palm frames; forward results
do not establish an inverse map. Prefer exact archived SOMA capture as the first
round-trip oracle. Stage 2 must retain Stage 1 export/history/deletion guarantees.
