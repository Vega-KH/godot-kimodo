# ADR 0001: Persist accepted source motion as native Godot resources

- Status: Accepted
- Date: 2026-09-06

## Context

MMCP returns self-contained glTF, but an accepted animation must remain usable
without the editor extension, Python backend, model weights, or source response.
It must also be possible to keep multiple generated takes without silent
replacement.

## Decision

Bake source motion into two independently loadable Godot resources:

- a `Soma77Motion` scene containing `Soma77Skeleton` and `AnimationPlayer`;
- a binary `.res` `AnimationLibrary` containing animation `motion`.

Animation tracks use the stable path
`Soma77Skeleton:<SOMA-77 bone name>`. The baker creates new skeleton and
animation objects rather than modifying the imported scene. If the requested
output stem exists, it chooses `_2`, `_3`, and so on; replacement requires a
separate explicit operation that is not currently implemented.

Use binary `.res` for generated key data so text serialization precision is
not part of the artifact contract. The `.tscn` skeleton remains reviewable in
source control. Runtime dependency tests must reject references to `.gltf` or
`addons/` anywhere in the native resource closure.

## Consequences

- Accepted source-space motion is a normal Godot asset with no runtime model
  dependency.
- Multiple takes are safe by default and can coexist.
- Native artifacts currently remain on SOMA-77; humanoid retargeting is a
  later boundary.
- Godot's nine optimized identity-only rotation channels remain represented
  by their bones' stored rest/initial poses.
- Binary animation-library diffs require numerical tests rather than textual
  code review.
