# SOMA-77 to Godot humanoid retarget fixtures

Goal 9 maps the native SOMA-77 walking take to a separate Godot-standard
humanoid skeleton. The target fixture is generated from
`SkeletonProfileHumanoid`, includes all 56 profile bones, and deliberately has
taller proportions plus 32-degree lowered upper arms. It is a skeleton-only
repository fixture, not a distributable character asset.

## Explicit body map

| Godot humanoid target | SOMA-77 source |
| --- | --- |
| Hips | Hips |
| Spine | Spine1 |
| Chest | Spine2 |
| UpperChest | Chest |
| Neck | Neck2 |
| Head | Head |
| Left/Right Shoulder | Left/Right Shoulder |
| Left/Right UpperArm | Left/Right Arm |
| Left/Right LowerArm | Left/Right ForeArm |
| Left/Right Hand | Left/Right Hand |
| Left/Right UpperLeg | Left/Right Leg |
| Left/Right LowerLeg | Left/Right Shin |
| Left/Right Foot | Left/Right Foot |
| Left/Right Toes | Left/Right ToeBase |

SOMA `Neck1` is deliberately collapsed between mapped `Chest` and `Neck2`.
`HeadEnd`, `Jaw`, both eyes, all 48 finger joints, and both toe-end joints are
not mapped. The six contact channels are generation metadata rather than
animation transform tracks; foot and toe-base rotations are mapped, while
contact values themselves are not copied into the native target library.

## Generated artifacts

- `fixtures/godot_humanoid_a_pose.tscn`: deterministic target rest fixture.
- `generated/soma77_walk_humanoid.tscn`: self-contained target playback scene.
- `generated/soma77_walk_humanoid.res`: target `AnimationLibrary` named
  `motion` with 22 rotation tracks plus root and hips position tracks. Planar
  locomotion travels on `Root`; vertical pelvis motion remains on `Hips`.

Regenerate the target rest fixture and reviewable animation from the repository
root with:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tools/build_humanoid_fixture.gd
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tools/bake_humanoid_fixture.gd
```

Run `tests/retargeting/humanoid_retarget_playback.tscn` to view the cyan source
and pink humanoid target side by side. The automated test verifies profile
structure, mapping coverage, rest-delta equivalence, root travel, finite keys,
source immutability, unique naming, dependency closure, and save/reload
stability.
