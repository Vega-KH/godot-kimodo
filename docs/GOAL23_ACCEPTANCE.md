# Goal 23 acceptance — scene root guides

Implemented and developer-tested 2026-10-11. **Owner accepted 2026-10-12.**
After the frame-rounding and workflow corrections, the owner reported that the
combined pose/guide workflow worked and all tests passed, and requested committing
Goal 23. The manual gate is complete.

Owner feedback 2026-10-12: guide-only generation steers motion successfully.
Mixed pose/guide testing subsequently passed. Native scrubbing now rounds to the
nearest 30 FPS frame in both guide recording and pose queuing, preserving the
native cursor and current bone edits. The node-placement diagnostic and artist
instructions now explain authoring root motion on the Hips bone. A new regression
captures/queues two complete poses with edited Hips travel/turning, matches both
guides and verifies that the combined constraints agree with a fixed scene node.
Verification after these revisions: all 41 console checks passed, followed by
the actual-editor probe, including a native seek to 0.501 s recording frame 15.
Evidence: `.research/goal23-owner-fixes-20261012.log` and
`.research/goal23-owner-editor-20261012/` in the combined workspace.

## Evidence

- Godot console suite: 41 checks. Coordinate tests include translated/yawed
  placement, profile and scene scale, 1e-5 m position / 1e-4 rad heading roundtrip,
  and rejection of tilt/nonuniform placement. A subsequent completion audit
  tightened shear rejection, including equal-length nonorthogonal axes in live
  and persisted placement. Both coordinate and guide integration tests passed
  again after this fix.
- Guide regressions cover native frames, explicit facing, pose root/heading
  conflicts, stale replacement review, playback during review, field-only Undo,
  save/reopen offline, changed placement and shortened duration.
- Real Godot editor probe passes native selection/gizmo, editor session-history
  Undo/Redo, native pose keying, and save/reload excluding temporary guide nodes.
  Rendered narrow/wide panels and actual 3D viewport were inspected.
- Backend: 31 passed, 7 hardware-specific skips; Ruff passed. New regressions
  verify shared position/heading origin normalization and an earlier path anchor
  taking precedence over a later pose.
- Isolated CUDA test: 60 frames, three turning-route waypoints, optional facing,
  one full-body starting pose, seed 1234, 100 steps. Inference took 7.077 s.
  XZ model root errors at frames 0/29/59 were 0.003781 / 0.038924 / 0.058154 m.
  Retargeted character-world errors were effectively equal at the tested scale.
  These are measured results for one route, not an accuracy guarantee.
- Live generation, immutable request/guide provenance, character Save,
  production Accept/Undo/Redo, fresh-process offline History reconstruction and
  archived-placement scene preview passed. The rendered scene preview was inspected.

Local evidence is under the combined workspace's ignored `.research/` directory:
`goal23-godot-final.log`, `goal23-editor-rendered/`, `goal23-ui-final/` and
`goal23-live-ab7b316fc25a4c8d9cdde625eef04274/`. Private fixture copies and generated
test assets are not distributable add-on content.

## Owner manual gate

Completion audit: implementation, documentation, automated/rendered checks and
the live/offline test have evidence above. Owner workflow acceptance was supplied
on 2026-10-12. The following checklist records the manual gate used for acceptance.

Restart the backend to load the normalization fix, then reopen/enable the updated
add-on. Follow [the root guide workflow](../addons/kimodo_motion/ROOT_GUIDES.md).

1. Use a saved character scene and its native animation timeline. Record several
   waypoints at the current frame with position/rotation gizmos and optional facing.
   Change clips, replace/remove a point and verify Undo/Redo and scene saving.
2. Combine a queued complete pose with a route. Try a conflicting shared frame,
   then resolve it with **Match guide to queued pose at current frame** or by
   disabling facing. Generate and inspect movement and turning.
3. Show the take in the scene, scrub the native timeline and check its placement.
   Save/Accept the animation and verify production Undo. Reopen offline and
   reconstruct the same session/History preview.
4. Move the scene character or shorten the duration and confirm that stale or
   out-of-range guides receive a useful diagnostic. Report workflow friction and
   whether generated route quality is acceptable before approving this checkpoint.

## Boundaries

Guides record ground-plane root XZ and optional yaw at 30 fps. Upright positive
uniform placement is required. Changing placement/profile requires restoration
or explicit clear/reauthor, not silent rebasing. Positional fitting of character
poses remains deferred and is documented in `DEVELOPMENT_GOALS.md`.
