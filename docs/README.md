# Project development documents

Stage 1 and Goals 22–23 are complete and owner-accepted (Goal 23: 2026-10-12).
The independent Pose Library follows the native AnimationPlayer clip/frame and
converts complete authored poses to SOMA-30 constraints.
See [Stage 2 completion](STAGE2_COMPLETION.md) and
[Goal 22 acceptance](GOAL22_ACCEPTANCE.md) and [Goal 23 acceptance](GOAL23_ACCEPTANCE.md).
Positional fitting remains documented as further work in the development goals.
Artist instructions are in [the root guide workflow](../addons/kimodo_motion/ROOT_GUIDES.md).
The next discussion concerns visual Hips authoring with the scene guide; Goal 24
has not yet been proposed in detail or approved.

For a fresh development session, read these in order:

1. [Research and development plan](Kimodo_Godot_Bridge_Research_and_Development_Plan.md):
   authoritative product workflows, boundaries and general Stage 2 direction.
2. [Development goals](DEVELOPMENT_GOALS.md): current status, next starting point
   and the approval/verification workflow.
3. [Agent handoff](AGENT_HANDOFF.md): code map, local environment, tests,
   preservation rules and technical traps.
4. [Stage 1 completion](STAGE1_COMPLETION.md): compact goal history, checkpoint
   commits and final acceptance evidence. Consult when relevant, not every turn.

Product instructions belong in the [add-on guide](../addons/kimodo_motion/README.md),
not in the development ledger. Server setup and compatibility decisions belong
in the [backend documentation](https://github.com/Vega-KH/kimodo-godot-server/tree/codex/milestone-0-bootstrap/docs)
(local sibling: `../../kimodo-godot-server/docs/`).

These documents cover both repositories but live in the extension repository,
which owns the artist-facing workflow. Do not maintain a second roadmap in the
server. Git preserves superseded task lists and the full original plan; see the
completion record for retrieval checkpoints.
