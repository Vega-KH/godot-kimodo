# Development goals

Reviewed: **2026-10-13**.
**Goals 0–21 complete. Stage 1 basic workflow accepted and pushed.**
**Goals 22–24 complete and owner-accepted. Stop for discussion before planning the next goal.**

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

## Goal 23 — completed 2026-10-12

The owner passed all tests, including combined pose/guide authoring, and requested
committing the checkpoint. Scene root-path and optional facing guides support
native gizmos, nearest-30-FPS frame recording, pose conflicts, session Undo/offline
reuse and archived-placement scene preview. Backend origin handling keeps path
positions and headings in the same frame. See [Stage 2 completion](STAGE2_COMPLETION.md)
and [Goal 23 acceptance](GOAL23_ACCEPTANCE.md) for evidence and limits.

## Goal 24 — completed 2026-10-13

The owner passed the visual workflow and both final usability additions, then
requested committing/pushing and stopping before planning the next goal.
Guide-driven Hips XZ/yaw editing, pose-to-guide synchronization, atomic paired
waypoint/full-body recording, frame-labelled authored ghosts, selection at the
current native frame, Undo/Redo and offline reconstruction are verified.
AI Motion character selection also binds Pose Library; its list refreshes to
show only compatible poses without modifying saved assets.

Scene-node placement remains fixed; recording does not implicitly key native
animations. Positional fitting and parent-node root-motion extraction remain
deferred. See [Stage 2 completion](STAGE2_COMPLETION.md) and
[Goal 24 acceptance](GOAL24_ACCEPTANCE.md) for evidence and limits.

No next goal is proposed or authorized. Wait for the owner's discussion.

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

### Positional fitting of character poses — further work required

The Goal 22 converter transfers edited body/palm orientations through reviewed
rest frames, then reconstructs SOMA-30 local rotations. It does not solve for
joint positions. Forward kinematics uses SOMA's own bone lengths, hierarchy and
neutral offsets: the same joint orientations on a character with different limb
proportions can therefore place hands/feet differently. Extra or collapsed joints
also make the reverse transfer non-unique. Altered-proportion stress rigs measured
hand differences up to 0.235 m before generation. The displayed transfer residual
is separate from the model's later generation error. Non-root translations and
body/ancestor scale edits are preserved in local poses but rejected for sending;
rotation-only SOMA-30 cannot directly represent them.

Proposed repair for a separately approved goal: initialize from the current
orientation reconstruction, then perform constrained positional fitting/IK on
the SOMA-30 hierarchy. Minimize selected hand/foot and body-position residuals
against character targets converted to the model's coordinate/scale convention,
while regularizing toward the authored orientations and preserving root, palm
orientation and joint limits. Keep model bone lengths fixed, report unreachable
targets and remaining residuals, and validate regular/proportion/partial rigs
before promising accuracy. This is a proposed design, not an implemented solver.
Explicit Kimodo effector position/orientation constraints are another route for
target-based authoring, but do not by themselves repair full-body pose conversion
or guarantee exact character placement after retargeting. Goal 23 adds root/path
guides only; positional fitting remains deferred as requested.

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
