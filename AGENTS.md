# Repository guidance

This repository contains only the Godot editor extension. Keep inference,
Python, CUDA, and model weights in the independently versioned
`kimodo-godot-server` repository.

## Goal-oriented development

- In the combined development workspace, read
  `../kimodo-godot-server/docs/DEVELOPMENT_GOALS.md` before starting work.
- Work on exactly one approved goal at a time.
- Preserve completed goals and tasks in the ledger.
- End every goal with its recorded automated or manual acceptance test.
- After successful completion without a major blocker, propose the next goal
  for user review, but do not begin it until explicitly approved.
- Commit and push the completed checkpoint, celebrate briefly, and stop.

## Godot boundaries

- Target Godot 4.7.2 unless an architecture decision changes the baseline.
- Prefer GDScript and supported editor-extension APIs before GDExtension.
- Never run model loading or inference inside the Godot editor process.
- Preview and fixture workflows must not overwrite user animation resources.
- Keep transport decoding, coordinate conversion, retargeting, and baking in
  separate testable modules.

## Verification

Run the documented headless suite with the console build before opening the
editor for a manual check. Treat parser errors, orphan-node warnings, and
unexpected engine errors as test failures.

