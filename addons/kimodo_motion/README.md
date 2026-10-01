# Kimodo Motion Studio — basic workflow

Tested on Windows with Godot 4.7.2. This is an editor add-on, not an inference
runtime: generation runs in the separate local kimodo-godot-server process.

## Install and generate

1. Copy this `addons/kimodo_motion` folder into your Godot project and keep the
   accompanying MIT LICENSE. Enable **Kimodo Motion Studio** in
   **Project > Project Settings > Plugins**. No development tests/models are needed.
2. Complete the backend's development installation, then run its root `start.bat`.
   It uses its own `.venv`, CUDA motion generation and the local text encoder on
   CPU. Wait for model loading before connecting to `http://127.0.0.1:8000`.
   The launcher is not an installer; weights and dependencies have their own
   requirements/licenses. See the backend repository's installation documentation.
3. Start a named session in **AI Motion**, or open a saved session. Select an
   imported character. In **Rig Setup**, review suggestions, map missing required
   roles, and save the profile. Manual mapping remains available for custom names.
4. In **Generate**, enter the prompt, frames, seed, steps and one or two takes.
   Default steps: 100; UI maximum: 200. **Stop waiting** discards the response at
   the client; it does not promise to stop inference already running in the backend.
5. **Preview & Save** has a square viewport, a take selector, shared camera and
   playback controls, and one Save menu: Character animation, Humanoid animation,
   SOMA-77 animation, or Character Preview. Save exports a new file; it never
   silently overwrites an existing file. Character Preview embeds the complete
   model and can be large. Animation libraries contain animation only.
6. **Accept** adds the selected character animation to an existing/new production
   AnimationLibrary. Replacing an animation requires confirmation; Godot Undo/Redo
   restores the library. An empty newly created library remains after Undo.
7. Every successful generation archives every source take before reporting
   success. **History** can reload those takes offline and rebuild previews for
   the current character. Restart the editor and reopen the session to continue.

## Compatible rigs and limits

Use one Skeleton3D with matching skin bind and skeleton rest poses. A common
positive uniform bind-space scale is supported; per-bone scale, mismatched
poses, non-uniform/sheared/reflected bind offsets are not. Error messages name
the affected mesh/bone and suggest how to repair the import. A missing required
role or invalid chain must be corrected before generation is enabled.

Partial optional anatomy, additional spine/neck segments and unmapped extra
bones are supported within the validated hierarchy; unmapped bones retain their
rest pose and inherit parent movement. Hair physics, IK/control solvers and
active twist distribution are not provided. Generated fine finger motion is
limited by Kimodo's source motion, even when transfer is correct. Suggestions
are bounded assistance, not exhaustive rig recognition.

## Sessions, deletion, backup and ownership

Sessions autosave under `res://animations/kimodo/sessions`. Back up these together
with `session_data/<UUID>` (source libraries, manifests and versioned source rig
snapshots) and your shared rig profiles. These are valuable authoring data; decide
explicitly whether to version them or store them in your asset backup system.
Godot's `.godot` import cache and transient preview instances are not source data.

The chooser lists all default-folder sessions, not just the eight most recent.
**Delete…** works for a selected or active session. Its confirmation counts
remaining archive files and separately notes missing files. Cancel is the default.
Deletion removes only that session and its verified managed source tree. Saved
exports, accepted libraries, saved Character Previews, imported characters and
shared rig profiles are kept. It is not an undoable editor action or OS Trash.
Exports/Accept cannot use managed session storage as their destination.

Deletion stages files with a recovery receipt. Restart restores an interrupted
uncommitted deletion, or retries committed cleanup if files were locked. A tiny
identity receipt remains under `session_deletions/<UUID>` so old Undo/autosave
cannot recreate deleted sessions. Production-library Undo/Redo still works.
Do not manually remove those receipts while old editor undo actions remain.
Linked/junction storage, duplicate session IDs, unknown owned files, or an export
placed inside managed storage block deletion with instructions; nothing is swept
from the general animations folder. Legacy pre-Goal-16 sessions are not migrated.

Backend: https://github.com/Vega-KH/kimodo-godot-server
