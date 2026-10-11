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
