# Jenny Auto-Rig Pro test fixture

`fixtures/Jenny03.glb` is the canonical skinned-character fixture supplied by
the project owner for plugin testing. It is the root-bearing Auto-Rig Pro
export and remains outside the addon runtime package.

- SHA-256: `cea2da0dead498499b0433322d9aba04681da24e587d3e2a15004acfe2afeae9`
- Size: 12,414,456 bytes
- Geometry: 21,661 imported vertices and 37,270 indexed triangles
- Rig: 61 bones rooted at `Root`, including 53 Godot humanoid profile names and
  eight limb twist bones
- Skin: eight mesh nodes; the largest skin binds all 61 bones
- Embedded animation: none

The alternative workspace export, `Jenny03-no-root-bone.glb`, was inspected
without modification. It has the same geometry and materials, 60 skin binds,
and `Hips` as the hierarchy root. Its SHA-256 is
`a0c57fecd3a80d02e53082e374fc0d43eb08590df960df412e7c38d76a36c3c2`.
It is not duplicated here because a dedicated root is required by the current
humanoid motion contract.

Godot imports embedded textures as Basis Universal resources so no extracted
texture copies are committed. The GLB is below GitHub's 50 MiB warning
threshold, so keeping this single fixture directly in Git avoids imposing Git
LFS on addon contributors.

The supplied historical `arp_fixer.gd` copies object-level animation tracks
onto an exported `Root` bone. These GLBs contain no animation tracks, and the
Kimodo baker writes planar motion directly to `Root`, so neither that script
nor the external `arp-importer` addon is used for this fixture.

Run the automated contract with:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tests/test_jenny_character_retarget.gd
```

Open `jenny_retarget_playback.tscn` for the cyan line-humanoid and skinned
Jenny comparison. Drag to orbit, use the mouse wheel to zoom, press `F` to
toggle root following, and press `R` to reset the view.
