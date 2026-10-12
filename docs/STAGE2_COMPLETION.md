# Stage 2 completion history

## Goal 22 — editable pose library, accepted 2026-10-11

The owner passed all manual tests, authored/recalled poses and built native
animations with them. Current-frame keying was explicitly accepted as a fast,
intuitive workflow. The owner authorized pushing this checkpoint.

- Separate offline Pose Library dock; versioned `.tres` pose resources contain
  one-sample native Animation channels and rig compatibility metadata.
- Capture displayed manual edits, save/reopen full or sparse poses, preview,
  apply and key with real editor scene-history Undo/Redo and collision review.
- Follow native AnimationPlayer clip/evaluated cursor; refresh new clips without
  reselecting the character. Numeric bone controls were removed after review.
- Convert complete authored frames to SOMA-30 via reviewed rest/palm/profile
  reconstruction; queue full-body constraints and archive exact authored inputs,
  profile configuration and submitted requests. Finger poses remain local detail.
- 39 Godot checks; backend 29 passed/7 expected skips and Ruff; real editor
  save/reload, rendered narrow/wide docks, live CUDA conditioning and offline
  history/reopen verified. Detailed evidence: [Goal 22 acceptance](GOAL22_ACCEPTANCE.md).

Orientation transfer has no positional-fitting solver. Altered-proportion stress
rigs showed hand differences up to 0.235 m; the user explicitly deferred fitting.
Direct resource/AnimationTree/inactive-player preview is outside native cursor
following. Existing sessions, shared profiles and artist animation/pose assets
remain independent of session deletion.

Checkpoint: extension's commit introducing this record and backend's
`Pin Goal 22 pose conditioning semantics` commit on their existing branches.
Git retains the original detailed goal and implementation history.

## Goal 23 — scene root-path and facing guides, accepted 2026-10-12

The owner verified guide-based steering, then passed mixed pose/guide authoring
after frame rounding and workflow guidance were corrected. All manual tests passed;
the owner requested committing the goal.

- AI Motion Guides tab, temporary native transform gizmo, root XZ waypoints and
  optional facing, frame labels/path display and native current-frame recording.
- Guide recording and pose queuing round to the nearest 30 FPS frame without
  changing the native cursor or resampling edited bones.
- Session intent, field-only editor Undo/Redo, offline persistence, reviewed
  coordinate/profile scaling, explicit stale-placement checks and pose conflicts.
- Immutable authored guide/placement provenance, advertised root_path submission,
  archived-placement temporary scene preview and existing Save/Accept/Undo.
- Backend origin normalization rotates headings with path positions and chooses
  the earliest root pin across paths and poses.
- 41 Godot checks; backend 31 passed/7 expected skips and Ruff; actual editor,
  rendered UI/viewport, live CUDA route and fresh-process offline reopen verified.
  The three-point live route measured XZ root residuals of 0.0038–0.0582 m.
  See [Goal 23 acceptance](GOAL23_ACCEPTANCE.md) for evidence and boundaries.

Character scene-node placement remains fixed during guide/pose authoring; Hips
bone travel/turning is captured into poses. Visual Hips manipulation via the guide
is a next-goal discussion, not part of this accepted checkpoint. Parent-node/root
motion extraction and positional fitting are separate future work. Private models
and artist animations remain outside the committed add-on.

Checkpoint: extension's `Complete Goal 23: scene root-path and facing guides`
commit introducing this record; backend `b0b0874` on
`codex/milestone-0-bootstrap`.
