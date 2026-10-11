# Development goals

Reviewed: **2026-10-11**.
**Goals 0–21 complete. Stage 1 basic workflow accepted and pushed.**
**Goal 22 complete and owner-accepted 2026-10-11. Goal 23 proposed, awaiting approval.**

## Read first

The [product workflows](Kimodo_Godot_Bridge_Research_and_Development_Plan.md)
are authoritative. [AGENT_HANDOFF.md](AGENT_HANDOFF.md) is the technical
fresh-session guide. [STAGE1_COMPLETION.md](STAGE1_COMPLETION.md) records all
completed goals and final acceptance; do not reload the historical ledger
unless investigating a specific decision.

Product checkpoint: extension `7e9d1a8` on `main`; backend `0f1d347` on
`codex/milestone-0-bootstrap`. Later documentation commits do not change this
tested code baseline. The user passed every final manual test on 2026-10-01.

## Where we are

The complete session → character/profile → local generation → compare/history
→ Save/Accept → offline reopen/delete workflow works in a clean Godot project.
Every returned take has a durable source archive and versioned rig snapshot.
Generic reviewed profiles support regular complete/partial humanoid rigs,
including renamed bones and extra branches. Matching is useful, not perfect;
manual choices remain authoritative.

Save exports an independent resource. Accept modifies a production library as
one undoable editor action; neither preview nor Save is implicit acceptance.
Deleting a session removes only verified session-owned source data. Stage 1's
supported scope is Windows/Godot 4.7.2 with the pinned local CUDA backend, not
universal rigs or a marketplace release.

## Goal 22 — completed 2026-10-11

The owner passed all manual tests: authoring, saving/reopening poses and building
native animations by keying at the current frame. The separate Pose Library
captures actual edited bone values, supports sparse/full channels and scene Undo,
and follows the native AnimationPlayer clip/cursor with automatic clip refresh.
Full-body SOMA-30 constraints, immutable provenance and offline reuse are verified.
Numeric bone editing was removed at the user's request. Positional fitting remains
deferred; orientation-transfer differences are disclosed before submission.
See [Stage 2 completion](STAGE2_COMPLETION.md) and
[Goal 22 acceptance](GOAL22_ACCEPTANCE.md) for evidence and supported limits.

## Goal 23 — proposed: scene root-path and facing guides

**Status: proposed for user review; not approved or started.**

Artist result: place and rotate a root guide in the Godot scene, scrub the native
AnimationPlayer timeline and record a waypoint at its current frame. Build a path
and optional facing directions, combine them with existing full-body pose frames
and a prompt, then generate and preview motion in the same scene placement.
Keep Pose Library focused on reusable poses; guide authoring belongs in the
motion/session tools.

### Scope and ordered work

1. Audit the pinned backend's root-path, heading and origin normalization behavior.
   Prove scene-to-model and model-to-scene conversions with translated/rotated
   characters and the reviewed profile's scale policy before building the UI.
2. Provide an editor scene guide with Godot's position/rotation gizmos. Record,
   replace and remove root waypoints at the native current frame; display frame
   markers and the path in the viewport. Optional facing is explicit. A straight
   segment joins waypoints for display; do not silently add dense constraints or
   promise that generated motion follows a mathematical curve exactly.
3. Store authored guides as session intent with Undo/Redo and offline reopening.
   Changing character placement/profile or duration must invalidate or explicitly
   rebase affected guides. Preserve Stage 1 sessions and Goal 22 pose assets.
4. Translate reviewed waypoints to advertised `root_path` constraints. Detect
   contradictory root/heading values where full-body pose frames also constrain
   them; ask the artist to resolve conflicts rather than choose silently. Archive
   exact authored guides, scene/model placement and the submitted request.
5. Verify native-frame workflow, coordinate transforms, stale state, collision
   behavior, save/reopen, combined pose/path generation, and Save/Accept/Undo.
   Render the viewport/UI and complete a live generation plus owner manual gate.

### Acceptance and boundaries

- Record waypoints at native frames without calculating seconds or reselecting
  the character. Moving/rotating the guide is visual and uses native gizmos.
- A translated/rotated character's authored path converts correctly and the
  generated preview returns to that placement. Conversions roundtrip within
  1e-5 meters and 1e-4 radians; profile scale is applied exactly once.
- A short curved walking route with optional facing and one/two full-body pose
  constraints generates, archives and reopens offline. Report measured model
  waypoint error and assess character placement visually; do not invent a model
  accuracy guarantee before the first live result.
- Preserve all current pose/native animation/session behaviors and require the
  owner to approve the scene-guide workflow before committing the checkpoint.

This goal adds root XZ travel and facing, not terrain navigation, collision
avoidance or arbitrary root height control. Timed prompt ranges and hand/foot
position/orientation targets are subsequent authoring slices. Positional fitting
of character poses remains a separate design discussion: explicit effector
constraints may address placement needs without first building a full inverse
pose solver. Do not implement a solver or these later slices under Goal 23.

## General Stage 2 aims

Reusable pose library/starting pose → prompt and pose direction over time →
supported effector/root controls → non-destructive in-scene preview/comparison →
explicit native animation/timeline acceptance. This expresses direction, not
fixed goal numbers or a promise of specific model quality.

## Work protocol

1. Propose one focused goal with scope, ordered tasks, risks and acceptance tests.
2. Wait for explicit user approval; work only that goal.
3. Record concrete defects, fix nearby ones with tests when within scope.
   Stop for discussion on major blockers or consequential architecture changes.
4. Run automated checks, relevant rendered/live tests and the manual gate.
5. Record the outcome and checkpoint, commit/push both affected repositories.
   Push permission already exists after completed, tested goals.
6. Add the next detailed proposal for discussion; do not implement it unapproved.

Keep this file focused on the current/next goal. Move completed outcomes to the
compact completion history; Git retains detailed old checklists. Keep permanent
compatibility decisions in backend ADRs and practical notes in the handoff.

## Remaining maintenance / honest limitations

No known Stage 1 blocker remains. Carry forward:

- True backend progress/cancellation/retained jobs are deferred; Stop waiting
  cannot promise that inference stopped.
- Bakers still duplicate some rest sampling/track/save logic; consolidate only
  when nearby work warrants it and full regression coverage is retained.
- Future UI overhaul remains optional. Do not reopen rig matching solely to cover
  every possible exporter or control topology.
- Backend exception text needs sanitizing before any remote/LAN mode.
- glTF validation intentionally requires the pinned skeleton-only 77-node
  contract; other MMCP backends need a deliberate contract extension.
- Newer NVIDIA dependency reconciliation, broad prompt/seed quality benchmarks
  and automatic environment provisioning are separate decisions.

Resolved defects (finger/wrist/thumb frames, paths/partial saves, request mutation,
capability gating, stale acceptance writes, and deletion resurrection) are
summarized in the completion record. Do not keep them as active repair tasks.
