# Kimodo Motion Studio for Godot

Open-source Godot 4.7.2 editor extension for local humanoid animation authoring
with [kimodo-godot-server](https://github.com/Vega-KH/kimodo-godot-server).

**Stage 1 is complete:** all final manual tests passed on 2026-10-01.
Create/reopen a session, select and review a character rig, generate one or two
takes, compare previews, keep durable offline History, then Save or explicitly
Accept into a native production AnimationLibrary. Confirmed session deletion
removes managed source data without deleting independent exports or libraries.

## Start here

- Artists: [installation, basic workflow and storage guide](addons/kimodo_motion/README.md).
- Developers/new sessions: [shared project docs index](docs/README.md), then
  the product plan, current development goals and technical handoff.
- Completed work: [Stage 1 checkpoints and acceptance](docs/STAGE1_COMPLETION.md).

Shared planning covers both repositories and lives here; server-specific guides
and ADRs remain with the backend. Stage 2 starts with reusable poses. A detailed
next goal must be discussed and approved before implementation.

## Supported reference workflow

Windows, Godot 4.7.2 stable (`ed1daf0bf`), local CPU text encoding and CUDA
motion inference. Reference GPU: RTX 4070 Laptop, 8 GB VRAM; 32 GB RAM.
The console engine in this workspace is
`C:/Godot-472/Godot_v4.7.2-stable_win64_console.exe`.

The editor runs no Python or inference. Start the backend using its root
`start.bat`, wait for ready, enable **Kimodo Motion Studio** in Godot Plugins,
and connect to `http://127.0.0.1:8000`.
**Stop waiting** is client-side, not guaranteed cancellation of CUDA inference.

Rig setup provides reviewable suggestions/manual mappings for compatible complete
or partial humanoids. Matching bind/rest poses are required; one shared positive
uniform bind-space scale is allowed. Arbitrary control rigs and all exporter
conventions are not promised. See the add-on guide for diagnostics and limits.

## Verify and package

From this repository:

```powershell
.\scripts\test.ps1
```

The offline suite currently contains 35 checks. Parser/engine errors and orphan
warnings are failures. Private compatibility checks skip when licensed fixtures
are absent; generic synthetic correctness tests still run.

`scripts/package-addon.ps1 -Destination <new empty folder>` copies only the
allowlisted `addons/kimodo_motion` files and MIT LICENSE. It excludes models,
tests, user animations, weights, environments and credentials.
`scripts/create-clean-test-project.ps1 -Destination <new folder> -Character
<private GLB>` adds an isolated test driver and explicit local character;
that project is not a redistributable package.

Fixture/provenance references (consult when working in that area):
[transport](tests/fixtures/README.md), [native](tests/native/README.md),
[humanoid](tests/retargeting/README.md), [skinned Jenny](tests/characters/README.md).
The technical handoff covers live/clean-project checks and test-isolation rules.

## License

Original extension code is MIT licensed. Bundled Jenny is copyright © 2026
Kyle Howard, separately CC BY 4.0; see
[its attribution](tests/characters/fixtures/LICENSE.md).
Backend is Apache-2.0. Other fixtures/dependencies/weights have separate licenses.
Private test models and user animations are never part of the add-on package.
