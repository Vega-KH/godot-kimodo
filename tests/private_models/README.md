# Private retargeting fixtures

This directory is the project-local staging area for licensed or otherwise
non-redistributed character models used during retargeting development. Godot
must import target models from below `res://`, but the model files, generated
`.import` metadata, and local test artifacts must never be committed or included
in release packages.

The directory contents are ignored except for this guide. Copy a private model
here locally, let Godot import it, and refer to it only from tests that skip
cleanly when the fixture is absent. Repository acceptance must continue to pass
without any private fixture installed.

Current local test names:

- `Remy-with-taunt-animation.fbx` — Mixamo-rigged Goal 18 target.
- `Jenny04.glb` — Goal 19 imported hair/eye and full-workflow check.
- `mannequiny-0.3.0.glb` — Goal 19 actionable bind/rest rejection check, not a
  supported retargeting target without re-exporting matching poses.
- `godette_rigged.glb` — planned Goal 20 complex-rig target.

Goal 19's main coverage is the distributable synthetic matrix in
`tests/test_rig_variants.gd`: anatomy, naming, differing rest bases/proportions,
root policies, reindexing and saved playback. Godette and the Skeleton model
remain optional Goal 20 examples; they are not needed to pass Goal 19.

For a local manual wrist/digit/eye stress fixture after staging Jenny04:

```powershell
& 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_private_jenny04_workflow.gd -- --keep-stress
```

The command prints paths under the ignored `goal19_manual/` folder for a
lightweight character library, a self-contained Character Preview, and the
humanoid source stress scene. Preview/library filenames are collision-safe;
the test-owned `humanoid_stress.tscn` is regenerated. Inspect the `motion`
animation at 0.0, 0.25 and 0.5 seconds in the Godot editor. This deliberately
moves all finger joints, wrists, head and eyes, without relying on Kimodo's
subtle generated finger motion. The regular headless suite does not retain
these generated assets.
