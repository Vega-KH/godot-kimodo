# Native SOMA-77 fixture

The `generated/soma77_walk.tscn` scene and `generated/soma77_walk.res`
`AnimationLibrary` are native Godot resources baked from the immutable Goal 4
MMCP fixture. Their dependency closure contains only those two files: no glTF,
addon script, backend, or model is required for runtime playback.

Native track paths follow one stable convention:

```text
Soma77Skeleton:<SOMA-77 bone name>
```

The animation is named `motion`. Its binary `.res` representation keeps
generated key data compact and avoids making text serialization precision part
of the accepted-animation contract.

## Reproducible bake

From the repository root, run:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path . --script res://tools/bake_native_fixture.gd
```

The baker never overwrites an existing scene or library. Re-running it creates
`soma77_walk_2`, then higher unique suffixes. Review any regenerated artifact
against the committed fixture before replacing it deliberately.

The baker creates a new scene tree, skeleton, animation copy, and library; it
does not mutate or take ownership of the imported glTF scene. Once accepted,
the output files belong to the user's Godot project and can be renamed, moved,
or removed like any other native project resource.

Run all automated plugin, transport, round-trip, dependency, and playback
checks with `scripts/test.ps1` from the repository root.

## Visual comparison

Run `soma77_native_playback.tscn`. Its orange skeleton uses only the native
scene/library. Compare it with the cyan in-memory glTF scene from Goal 4.

