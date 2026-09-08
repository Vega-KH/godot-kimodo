# ADR 0003: Use Godot's humanoid profile with an explicit offline retarget bake

- Status: Accepted
- Date: 2026-09-08

## Context

Kimodo produces a named SOMA-77 skeleton while Godot's standard humanoid
profile uses a different 56-bone hierarchy and vocabulary. The target may also
have different rest axes, limb lengths, and an A-pose rather than the source
rest pose. A saved result must be deterministic, inspectable, and independent
of its source after reload.

Godot 4.7's `RetargetModifier3D` transfers poses between child skeletons whose
bones already use names from one `SkeletonProfile`. It accepts
`SkeletonProfileHumanoid`, but it has no `BoneMap` property. It therefore
cannot directly express required mappings such as SOMA `LeftArm` to Godot
`LeftUpperArm`, or the intentional collapse of SOMA's two neck joints into
Godot's single `Neck`. Using it would require a second, canonical-name proxy
skeleton and sampling its modifier callback during playback.

## Decision

Use `SkeletonProfileHumanoid` as the target naming and hierarchy standard.
Keep the SOMA-to-profile map as explicit data and bake offline without a proxy
skeleton.

For each mapped bone and sample, calculate the source bone's model-space
rotation relative to its model-space rest and apply that delta to the target
bone's model-space rest. Reconstruct target local rotations in hierarchy order.
Keep target bone positions at their authored rests except for `Hips`, where
source root displacement is preserved. Emit only mapped rotation tracks and
the hips position track; unmapped target bones remain at rest.

The committed target fixture contains every bone from
`SkeletonProfileHumanoid`, but has deterministic altered proportions and
32-degree lowered upper arms. It contains no mesh or third-party asset.

## Consequences

- Rest axes and A/T-pose differences are handled rather than copied blindly.
- The mapping and every deliberately ignored source category are reviewable.
- Output is a new native scene and `AnimationLibrary`; source motion and target
  fixture remain immutable, and duplicate names receive numeric suffixes.
- Root displacement and heading survive, but target limb lengths remain those
  authored in the target fixture instead of stretching to SOMA proportions.
- `RetargetModifier3D` remains a candidate for later live character preview if
  an import-time canonical proxy makes that workflow worthwhile.
