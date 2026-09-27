# ADR 0004: Durable source-take archives

Status: Accepted

Date: 2026-09-26

## Context

A session must preserve every generated take, but a packed character preview
duplicates meshes and textures and derived humanoid/character motion may change
as retargeting improves. An animation library alone is not enough to interpret
an old take if the source rest rig changes.

## Decision

Archive each take as a self-contained SOMA-77 `AnimationLibrary`. Archive one
deduplicated rig snapshot for each exact rest/hierarchy signature, including the
SOMA contract version, snapshot schema, bone names, parents, local rests, and
skeleton transform.

Commit a complete generation as one recoverable batch: write and reload all
take libraries plus a manifest in a same-parent staging directory, promote the
directory, then atomically save the session reference. The manifest allows a
verified promoted generation to be attached after interruption. Controlled
failures roll back the batch and preserve the prior session bytes.

Treat SOMA scene instances and humanoid/character conversions as disposable
preview cache. Rebuild them lazily from the source archive. Explicit export is
independent and is never removed by source-take deletion. Confirmed source
deletion keeps a tombstone in session history.

Pre-Goal-16 sessions were disposable development data. Schema v2 rejects them
unchanged; it does not invent archives or attempt migration.

## Consequences

- History works offline and can benefit from later retargeting repairs.
- Exact rig identity, rather than the label “SOMA-77,” governs compatibility.
- Archive files remain small and Godot-native.
- Persistence spans several files, so manifests and open-time recovery are
  required instead of claiming perfect filesystem atomicity.
- A user may explicitly delete an automatic source take, but not by merely
  closing a session or changing previews.
