# Kimodo Motion Studio for Godot — research and development plan

Reviewed: 2026-10-01. **Stage 1 basic workflow complete; Stage 2 preparation.**
Reference platform: Windows, Godot 4.7.2, RTX 4070 Laptop (8 GB VRAM),
32 GB RAM. Extension: MIT; backend additions: Apache-2.0.
This is a validated development workflow, not a universal installer or release.

## Governing product intent

These workflows supersede historical implementation notes and task lists.

### Basic workflow — completed Stage 1

1. Start a new project-owned session or reopen a previous session. Authoring
   controls remain hidden until a session is active.
2. Select a humanoid character in Godot.
3. Describe a pose or motion with a text prompt.
4. Generate several takes locally.
5. Preview and compare takes on the selected character without altering
   its existing animation.
6. Accept one result as a native Godot animation, or revise the inputs and
   regenerate.

SOMA-77 playback and synthetic-humanoid previews are diagnostics, not required
artist steps. The tested interface currently supports one or two takes.

### Advanced workflow — Stage 2 direction

1. Start or reopen a project-owned session, then place a humanoid character in
   a scene.
2. Select a starting pose from a saved library, or generate and select one.
3. Position the character in the scene with that pose active.
4. Optionally direct motion with more poses, hand or foot targets, root
   waypoints, and paths.
5. Generate one or more takes locally.
6. Preview and compare takes in the scene without altering existing animation.
7. Accept a result into the active timeline, save it as a native Godot
   animation, or revise and regenerate.

## Architecture and ownership

Two independently versioned repositories:

- `godot-kimodo`: authoring UI, sessions/history, poses and future timeline,
  rig profiles, retargeting, previews, native resources and undoable acceptance.
- `kimodo-godot-server`: Python dependencies, model loading, inference,
  constraint translation, post-processing and generation diagnostics.

Never run Python, PyTorch, CUDA or inference in the Godot editor process.
Keep the server on loopback by default. Preserve MMCP and the backend's
`motionmcp_kimodo` namespace; introduce a versioned job API only for an actual
need such as server cancellation/progress, not to match an old architecture sketch.
Prefer GDScript and supported editor APIs; measure before introducing GDExtension.

Authoritative generated data is SOMA-77 motion plus its versioned source rig.
SOMA-30 is the model's internal constraint rig. Humanoid/character motion is
derived. A character-specific animation library is not interchangeable with a
humanoid library merely because some bone names match.

## Durable product rules

- A session is a conversation-like authoring workspace, not an animation.
  Editable intent, immutable generation provenance, individual takes, Save
  artifacts and accepted production animation remain distinct.
- Preserve **every** validated generated take automatically. Session history
  owns compact SOMA-77 libraries and source-rig snapshots, not bulky previews.
  Rebuild previews on demand; only explicitly saved Character Previews are durable.
- Save stays one dropdown/button: Character animation (default), Humanoid
  animation, SOMA-77 animation, Character Preview. Save refuses collisions;
  Accept adds to an existing/new production library with explicit Replace and Undo.
- Session/take deletion is confirmed and ownership-checked. Independent exports,
  accepted libraries, models and shared profiles survive. No arbitrary file sweeps.
- Retargeting is generic and profile-driven. Synthetic convention/anatomy families
  define correctness; private characters are examples, never model-specific hacks.
  Helpful manual mapping is preferable to confident but incorrect automation.
- Require matching bind/rest poses. Accept one shared positive uniform bind-space
  scale without editing the model. Explain incompatible assets precisely.
- Stop and discuss major blockers or architectural changes; do not conceal them
  behind suboptimal repairs. Repair concrete nearby defects with regression tests.

## Stage 2 — general direction, not a scheduled roadmap

Begin with reusable **poses**: capture/select a pose, save/load it, preview it on
a compatible character, and make it easy to place that pose on a timeline.
Keep pose content separate from its occurrence (frame/placement) in a session.
Do not confuse animation export, a starting pose and a generation constraint.

Godot provides [Skeleton3D bone-pose APIs](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html),
[Animation keyframes](https://docs.godotengine.org/en/4.7/classes/class_animation.html)
and [custom Resource persistence](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html).
The proposed add-on pose asset supplies library identity, rig/reference metadata
and reuse semantics over these primitives; its final format is not decided yet.

First investigate pose round-tripping and the canonical/character coordinate
boundary. Retargeting is not generally invertible; copying character quaternions
into a Kimodo constraint is not an acceptable shortcut. Establish source-rig
pose capture/reload before committing to arbitrary character-to-source editing.

Later slices can introduce prompt ranges, pose keyframes, supported hand/foot
targets, root paths/heading, in-scene comparison and timeline acceptance.
Sequence them after hands-on results; do not commit to a full Stage 2 plan now.
Quality/resampling/curve reduction and a broader UI redesign are later decisions.

Service coordinates remain meters, Y-up, XZ ground plane, +Z forward. Centralize
and test scene/skeleton/canonical conversions. Advertised constraints must be
checked separately from basic-generation eligibility.

## Deferred scope

Runtime generation in exported games; cloud/accounts/billing; remote service
hardening; universal Python provisioning; guaranteed AMD/Intel/CPU inference;
scene collision understanding; AnimationTree generation; alternate bind/reference
poses; arbitrary control-rig/IK reconstruction, active twist solvers or engine forks.
True CUDA cancellation is not implemented: **Stop waiting** is client-side.

## References and current work

Current work and approval state: [DEVELOPMENT_GOALS.md](DEVELOPMENT_GOALS.md).
Technical notes: [AGENT_HANDOFF.md](AGENT_HANDOFF.md).
Completed evidence: [STAGE1_COMPLETION.md](STAGE1_COMPLETION.md).

- [Official Kimodo repository](https://github.com/nv-tlabs/kimodo)
- [Model card](https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1)
- [Kimodo constraints](https://research.nvidia.com/labs/sil/projects/kimodo/docs/user_guide/constraints.html)
- [Kimodo skeletons](https://research.nvidia.com/labs/sil/projects/kimodo/docs/key_concepts/skeleton.html)
- [Backend ADRs](https://github.com/Vega-KH/kimodo-godot-server/tree/codex/milestone-0-bootstrap/docs/adr)
