# ADR 0002: Validate before temporary editor preview

- Status: Accepted
- Date: 2026-09-07

## Context

Live MMCP generation returns untrusted network bytes to a long-running editor
process. Artists need immediate feedback, but previewing a result must not
silently create or replace project assets, and an older request must not win a
race against a newer one.

## Decision

Build generation requests from typed artist options plus the exact skeleton
already validated from `/capabilities`. Accept generation responses only from
the loopback server and require the negotiated glTF 2.0 format, all 77 ordered
SOMA rotation channels, one root-translation channel, a canonical imported
skeleton, one finite animation, and the requested duration.

Keep the decoded scene in a plugin-owned `SubViewport`. A successful newer
take frees and replaces the previous temporary scene. Cancellation and
monotonic attempt tokens prevent late HTTP completions from changing current
state. Play, pause, and loop controls modify only the temporary animation.
Native saving remains the separate, explicitly non-destructive bake boundary
defined in ADR 0001.

## Consequences

- Generated data is checked before it enters the interactive preview.
- Preview is immediate but intentionally ephemeral until an explicit future
  save/bake action is added to the dock.
- Connection and generation have independent state machines, keeping errors
  and cancellation recoverable and understandable.
- The preview contains no Python, CUDA, inference, or backend process.
- Direct GDScript integration tests and GPU-rendered scenes remain adequate;
  a Godot MCP/editor bridge is still deferred until it solves a demonstrated
  interactive automation limitation.
