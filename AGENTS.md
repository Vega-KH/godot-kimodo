# Repository guidance

This repository contains only the Godot editor extension. Keep inference,
Python, CUDA, and model weights in the independently versioned
`kimodo-godot-server` repository.

## Goal-oriented development

- Read `docs/README.md`, then the product plan, `docs/DEVELOPMENT_GOALS.md`
  and `docs/AGENT_HANDOFF.md` before starting work. These shared documents
  cover both repositories; the product workflows take precedence.
- Stage 1 (Goals 0–21) is complete and pushed. Stage 2 begins with poses;
  propose the detailed next goal for approval before implementing it.
- Work on exactly one approved goal at a time.
- Preserve completed outcomes/checkpoints in `docs/STAGE1_COMPLETION.md`
  or subsequent compact history. Git retains obsolete detailed task lists.
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

