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
- `mannequiny-0.3.0.glb` — planned Goal 19 variant-anatomy target.
- `godette_rigged.glb` — planned Goal 20 complex-rig target.
