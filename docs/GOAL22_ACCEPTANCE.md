# Goal 22 verification and acceptance

Accepted 2026-10-11. The owner reports that all manual tests passed, including authoring/reopening poses and building animations with current-frame keying.
The user's 2026-10-11 revision removes numeric bone editing and follows the native
AnimationPlayer clip/evaluated cursor, replacing the earlier explicit-time UI.
See the [Pose Library guide](../addons/kimodo_motion/POSE_LIBRARY.md).

## Completed checks

- 2026-10-11 revision: complete 39-check console suite passes without engine,
  script, orphan or case-mismatch warnings. Expanded panel regressions prove
  manual-edit capture, new-clip refresh/following, precise cursor-time keys,
  stale confirmation after cursor movement, preview expiry, native resource
  identity/cursor preservation and multi-channel Undo preserving unrelated
  tracks, ordering, markers and animation settings. Existing artist pose folder
  capitalization is retained when browsing on Windows.
- Real editor revision probe exercises native clip selection and timeline seek
  signals, confirms public player state, keys at 0.5/1.0/1.5 seconds, and verifies
  selected-frame stability, scene history Undo/Redo and save/reload. Production
  uses public AnimationPlayer properties; editor-control access is test-only.
- Revised Library/Capture/Constraints tabs rendered and inspected at 360/680
  pixels. Numeric bone controls and independent seconds/FPS inputs are removed.

- Godot 4.7.2 console suite: 39 checks, including four new pose checks and all
  Stage 1 regressions. No unexpected engine/parser errors or orphan warnings.
- Backend: 29 passed, seven expected integration skips; Ruff passes. Five new
  CPU tests pin full-body/effector fill semantics, request preservation, excluded
  finger names and the shared SOMA-30/77 neutral positions.
- Sparse manual capture; interpolation from non-Kimodo animation; pose disk
  identity/value roundtrip; corrupt schema/quaternion/hierarchy rejection;
  equivalent reindexing and stale rest-rig rejection; collision-safe save.
  Complete position/rotation/scale values roundtrip within the goal's tolerances;
  position/scale sampling works at keyed and interpolated times. Sparse finger
  keying preserves a separate body track and its other keys. Root capture is
  explicitly opt-in; missing assets, outside-project saves and reserved archive
  destinations fail with diagnostics.
- Independent panel preview/cancel, native key Undo/Redo, collision cancellation,
  stale-confirmation rejection, editable-copy Undo and target-change handling.
- Separate real-editor integration check on the NVIDIA OpenGL renderer:
  saved native `.tscn` animation subresources accept pose keys; actions belong
  to the edited scene history; actual editor Undo/Redo restores resources and
  pose values; key collision confirmation, scene save/reload and independent
  copy editing preserve the source animation. This found and fixed an import
  detection defect: `::` denotes native embedded resources as well as imported
  clips. The source file/import metadata now determines editability.
- Character-origin manual torso, limb and palm edits on canonical, renamed,
  reindexed, different-axis, partial, hips-only and separate-root rigs.
  Reconstructed mapped global orientations survive both forward stages within
  0.001 rad; root position within 1e-5 m. Non-root translation and ancestor scale
  are rejected explicitly rather than silently discarded.
- Constraint queue/request validation, schema-2 session reopen, field-only Undo
  preserving newer prompt, frame bounds, generation locking, profile-policy
  staleness and immutable archive provenance.
- Saved finger-pose identity and file bytes survive verified session deletion,
  interrupted committed cleanup and recovery; the pose reloads/applies afterward.
- Rendered panel inspection: all three tabs at 360/680 pixel widths on the
  NVIDIA OpenGL renderer. Vertical scrolling supports the capture/edit controls.
- Two isolated clean-project live/offline checks on RTX 4070 Laptop (8 GB),
  pinned Kimodo/MMCP dependencies, CPU local text encoder and CUDA inference.
  Latest: sampled non-Kimodo hand animation, manually edited arm/palm, saved
  partial pose, native keys and complete constraints at frames 0/15; 30 frames,
  seed 1234, 100 steps, one take. Generation took 6.319 seconds. Character preview,
  archival, Save and Accept/Undo/Redo passed. A fresh process reopened the pose,
  authored scene/keys and conditioned History without a backend connection.
- Independent FK measurement of the latest saved request and generated glTF:
  constrained hand error 0.009–0.019 m, foot error 0.018–0.024 m, hips error
  0.001–0.003 m; maximum model-joint error 0.043 m. These are one smoke test's
  generation errors, not general model-quality guarantees.

## Reviewed conversion limit

The orientation converter has no positional solver. Its motion-position
differences use a transferred-neutral baseline and the profile's root scale.
The first forward fixture measured hands about 0.02 m and feet about 0.01 m.
Direct manual edits on regular synthetic variants measured hands up to 0.062 m;
altered limb proportions/partial torso stress variants measured up to 0.235 m.
Scene placement and fine fingers are separate from the model constraint.

On 2026-10-07 the user explicitly deferred positional fitting for discussion in
the next goal and asked to focus on the other Goal 22 features. The current
orientation transfer and displayed differences remain in this goal. Non-root
translations/scales remain usable in local pose assets/native animation but are
currently unsupported for sending. Do not start a solver or the next goal.

## Owner manual gate

The owner passed the manual gate on 2026-10-11 and explicitly authorized pushing
the completed goal. Their report confirms pose authoring, recall and native
current-frame animation construction. Automated evidence is mapped below.

| Requirement | Authoritative verification |
| --- | --- |
| Independent editable full/sparse pose panel and root/channel selection | `test_pose_library_panel.gd`, rendered three-tab captures; owner check 1 |
| Any compatible native clip, interpolated/manual capture and standalone `.tres` pose persistence | `test_pose_library.gd`; clean-project live/offline saved-pose reload; owner checks 2/4 |
| Native rebinding/key masks, collisions, copy isolation and Undo/Redo/save/reload | `test_pose_library.gd`, `test_pose_library_panel.gd`, `editor_pose_probe.gd`; owner check 3 |
| Character-to-SOMA-30 reconstruction, root/palm frames and disclosed proportion/detail limits | `test_character_pose_converter.gd`, backend `test_pose_conditioning.py`; fitting deferred explicitly by user |
| Selected authored frame requests, immutable provenance and offline History | `test_pose_conditioning.gd`, `test_take_archive.gd`, isolated live/offline checks and independent generated FK measurements; owner check 5 |
| Stage 1 workflow/storage preservation, independent poses surviving deletion and packaging | Full 39-check suite, expanded `test_session_deletion.gd`, pytest/Ruff and allowlisted package inspection; owner check 6 |

1. Enable the updated add-on in Godot 4.7.2. Open a character scene with one
   skeleton/player. Confirm Pose Library is a separate dock and works offline.
2. Choose a non-Kimodo clip/frame in the native Animation panel. Manually edit
   its bones before capture and verify those edits are preserved. Capture selected arm/hand/finger rotation
   channels, save a pose, restart and open it without relying on that source clip.
3. Create another editable animation in Godot's Animation panel. Verify Pose
   Library follows it without reselecting the character. Scrub to a frame,
   preview/cancel, apply and key with **Apply & Key at current frame**.
   Check only included channels change. Key at a second time and confirm/cancel
   replacement of an existing key. Scrub the native Animation panel and try
   Undo/Redo. Save and reopen the scene/library.
4. Open the pose, change a bone with Godot's skeleton/animation tools, capture edits to the
   opened mask and save to a new file. Verify the original pose remains intact.
   Sample an imported clip and copy it explicitly before keying.
5. Open a matching AI Motion session/profile, connect, seek/edit an arm and palm
   at a 30 FPS frame, review conversion quantities/excluded bones/differences,
   queue two full-body frames, and generate. Check body placement visually.
   Fingers should remain reusable local detail rather than model conditioning.
6. Confirm History reopens offline and Save/Accept/Undo/Redo work. Delete only
   this newly created test session; verify saved poses/authored/native exports
   and shared profiles survive.

Owner outcome: all tests passed. No new defect was reported. The completed checkpoint is authorized for commit/push; Goal 23 remains a proposal.

## Reproduce the editor integration check

After the console suite, run `scripts/test-pose-editor.ps1` with the console
Godot path if needed. It packages the add-on into a unique temporary project,
enables a test-only EditorPlugin, uses the real renderer to support editor scene
thumbnails, and retains its logs/native scene. An explicit `-Destination` must
be a new directory. This test is separate from the 39 console checks and does
not replace the owner's manual workflow/visual acceptance.
