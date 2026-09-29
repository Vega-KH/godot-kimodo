# ADR 0005: Accept animation through one undoable production-library transaction

Status: Accepted

Date: 2026-09-28

## Context

An explicit Save creates a standalone artifact, but the basic workflow also
needs to place one selected character take under an artist-chosen name in a
production `AnimationLibrary`. Previewing, automatic source retention, Save,
and production acceptance have different ownership and deletion rules.

An existing animation must never be overwritten implicitly. The operation also
updates session provenance, so a partial library/session update would be
misleading even if the animation data itself survived.

## Decision

Accept only the current target-character animation into a project-owned `.res`
`AnimationLibrary`. Preflight a deep copy against the current target signature,
player-root basis, track namespace, finite values, positive duration, staged
serialization, reload, and a clean target instance. Reject import-cache,
read-only, wrong-type, out-of-project, stale, and unresolved destinations.

Capture the exact prior and resulting library bytes plus the prior and resulting
session acceptance dictionaries. Persist each file through same-directory
staging, roll both back on a controlled failure, and register the successful
Add, explicit Replace, or new-file creation as one `EditorUndoRedoManager`
action. Register only after the initial do succeeds. Undo restores the captured
prior file state and session provenance; Redo restores the captured result and
never regenerates or retargets.

Acceptance provenance is separate from automatic archives and Save artifacts.
It identifies the take and generation, target signature, destination and key,
mode, timestamp, semantic animation hashes, and resulting library-file hash.
It does not own the production library, so source-take deletion cannot remove
accepted data.

## Consequences

- Artists can accumulate named motions in one native Godot library and use the
  normal editor Undo/Redo commands for Add and Replace.
- A collision is inert until the artist confirms Replace.
- New-file Undo removes the accepted animation but retains a valid empty
  project-owned library. Godot's resource cache and filesystem remain aligned,
  and the artist may reuse or explicitly delete the container. Add/Replace Undo
  restores exact prior bytes, including unrelated animations.
- Successful output has no Kimodo, source-glTF, backend, or target-fixture
  resource dependency.
- The transaction uses compensating rollback across two independently persisted
  resources; it does not claim a filesystem-level atomic commit across files.
  Controlled staging, promotion, session-save, undo, and redo failures are
  tested to restore the prior state and leave no temporary debris.
