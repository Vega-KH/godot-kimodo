# Goal 24 acceptance — visual pose and waypoint authoring

Approved 2026-10-12; implementation and developer verification in goal mode.
**Owner manual acceptance completed 2026-10-13; commit/push authorized.**

Owner feedback 2026-10-12: all original manual tests passed. Two final usability
additions were requested and implemented: selecting the scene character from
AI Motion also selects it in Pose Library, and the pose list filters by existing
rig compatibility and refreshes when the target changes. The original visual
workflow and both additions are accepted; the owner confirmed all tests pass on 2026-10-13 and requested committing/pushing, then stopping for discussion.

The additions passed isolated two-rig filtering/switching/no-target regressions,
the complete 43-check console suite and the actual-editor cross-dock selection
probe. Evidence: `.research/goal24-selection-filter-console.log` and
`.research/goal24-selection-filter-editor/` in the combined workspace.

The owner approved restoring selected records at the current native frame,
leaving the playhead unchanged. AnimationPlayer.seek changed the player's time
without moving the native Animation panel's cursor in the actual-editor probe;
production selection does not seek or search private editor controls.

## Evidence

- Console suite: 43 checks, including new calibrated guide math and authored
  pose/ghost integration. Three profile scales, scene scale/yaw and a rotated
  bone ancestor verify XZ/facing agreement, preservation of height/tilt and
  unchanged other bone articulation. Repeated synchronization has no drift.
- Integration covers Pose Library application updating the guide, complete
  authored channels/finger detail, paired field-only Undo/Redo, cancellation,
  stale bone edits, conversion failure without half a pair, replacement,
  waypoint-only conversion, visibility, selection, removal, preservation of
  independent queued poses, offline reference/ghost reconstruction and editing,
  and exclusion of helper nodes from packed scenes.
- Actual editor verifies native guide transform Undo/Redo updating Hips,
  combined session-history Undo/Redo, authored ghost creation and saved-scene
  helper exclusion, alongside the existing pose-keying checks. Selection tests
  check native/public time agreement under the approved current-frame workflow.
- Live CUDA test: two combined endpoint pose/waypoint records and one route-only
  midpoint; 60 frames, seed 1234, 100 steps, one take. Inference/request turnaround
  was 8.936 s. Model XZ root residuals at frames 0/29/59 were 0.003013 / 0.029614 /
  0.028811 m; character-world residuals were effectively equal for this case.
  These are one measured example, not an accuracy guarantee.
- Live generation, request/authored provenance, Save/Accept/Undo/Redo and a fresh
  offline process reconstructing both authored and generated previews passed.
  Rendered narrow/wide UI and gold authored versus cyan generated scene previews
  were inspected. The approved selection test reports native cursor=1.0 and
  public player position=1.0 after restoring a recorded frame-15 ghost.

Local evidence is retained outside either repository under the combined
workspace's `.research/`: `goal24-console-final.log` (43 checks),
`goal24-editor-approved-selection/`, `goal24-ui-final/`, and
`goal24-live-92d8d1a1c76847bb86ef2e11b9d84e72/` (live/offline/render logs,
requests, archives and `scene_preview.png`). Subsequent focused tests verified
actual finger-channel preservation and root-only waypoint-restoration Undo,
including preservation of newer unrelated finger edits. The goal-owned backend
was stopped after verification; private fixture copies remain outside the add-on.

Completion audit added a committed clear-all regression: independent pose
constraints survive, one Undo restores paired fields while retaining newer
unrelated intent, and offline scene rebinding reconstructs the restored ghost.
The focused integration test passed (`.research/goal24-clear-audit.log`).
Implementation, documentation and developer gates have evidence above. Owner final confirmation of both selection/list additions passed 2026-10-13.

## Completed owner manual gate

The original visual workflow was accepted 2026-10-12. Both final additions below were confirmed working properly 2026-10-13:

1. Click **Use selected scene character** in AI Motion and confirm that Pose
   Library shows that same skeleton/player without a second selection action.
2. Confirm that the pose list shows only compatible poses. Switch to a character
   with a different rig and check that the list refreshes; select the original
   character again to see its poses return. No pose files should be removed.

### Original accepted workflow

The [guide workflow](../addons/kimodo_motion/ROOT_GUIDES.md) was verified as follows:

1. Bind a saved scene character and native timeline. Enable **Move character
   with guide**, then move/turn the guide and verify that Hips follow while the
   character's scene node remains fixed. Check native gizmo Undo/Redo.
2. Apply a library pose and check that the guide follows it. Record **waypoint
   and pose** at several frames; use **waypoint only** for one intermediate frame.
   Gold static ghosts and cyan arrows should show the authored sequence.
3. Hide/show ghosts. Select a recorded item, verify that the native playhead stays
   put and that the pose/guide restore at that current frame. Copy it to another
   frame, or scrub to its labelled frame and review replacement. Check one-step
   paired Undo/Redo, cancellation and removal.
4. Generate, compare the cyan take against gold authored poses, Save/Accept and
   verify production Undo. Save the scene and reopen the session offline; bind
   the original scene placement and reconstruct/edit its records. Helpers must
   not have been saved into the artist scene.

## Boundaries

Visual guide editing adjusts Hips XZ/yaw, preserving height and existing tilt.
Recording stores session intent and does not implicitly key the native animation.
General bone gizmos, IK/positional fitting, terrain and parent-node root-motion
extraction remain outside this goal. Ghosts show authored character poses; SOMA
transfer/model generation may differ. Existing pose-only queueing remains valid.
