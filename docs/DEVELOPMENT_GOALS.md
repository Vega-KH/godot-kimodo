# Development goals

Reviewed: **2026-10-01**.
**Goals 0–21 complete. Stage 1 basic workflow accepted and pushed.**
**Stage 2 begins with poses; implementation has not begun.**

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

## Next starting point — Goal 22: pose foundation (direction only)

The user requested general Stage 2 direction rather than a detailed roadmap.
The next session should turn this starting point into a small, detailed Goal 22
proposal for review **before implementation**.

Intended first result: a reusable pose can be selected/captured, saved, reopened,
previewed and positioned at a chosen frame without requiring another generation
or changing existing artist animation. Whether initial capture comes from a
selected History frame, manual posing, or both is a proposal-time UX decision.

Investigate and settle:

- A lightweight versioned pose resource: identity, joint representation,
  source rig/reference signature, root placement policy and provenance.
  Avoid serializing live nodes, meshes or target-specific paths as portable poses.
- Distinguish reusable pose content from a session's timeline occurrence.
  Native Godot animation keyframes may be an export/application form; they
  need not be the only authoring representation.
- Prove capture → disk → reload → apply round-trips on the canonical source,
  then through existing profiles. Define how unsupported/extra joints are treated.
- Audit backend `pose_keyframe` semantics against the **SOMA-30** constraint
  subset, fill mode, local quaternions, heading and origin normalization.
  SOMA-77 output does not imply all 77 joints are constrainable.
- Separate pose-library playback from model conditioning. Selected-character
  editing may require a deliberate inverse mapping/solver; existing forward
  retargeting cannot simply be reversed when joints are omitted/collapsed.
- Keep placement/Undo/Cancel, persistence ownership, session deletion and old
  session compatibility explicit. Real useful Stage 1 archives now exist:
  the earlier permission to discard test sessions is not a perpetual data policy.

Do not start a full timeline editor, IK system, new retargeter, job service or
large dock redesign merely to store a pose. Begin with the smallest useful,
testable vertical slice and expand after approval.

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
