# ADR 0006: Persist reviewed target-rig profiles and explicit root policies

- Status: Accepted
- Date: 2026-09-29

## Context

Jenny's Godot-humanoid bone names made exact matching sufficient, but that
proved only one exporter convention. Mixamo's regular humanoid hierarchy uses
prefixed names and places `Hips` at the hierarchy root. Treating that as Jenny
with renamed bones would either reject a useful rig or invent a competing Root
track. Name-only automation also becomes unsafe when imported rigs are
ambiguous.

## Decision

Persist artist-reviewed target setup as a versioned project-owned
`KimodoRigProfile`. It records the character and skeleton signatures, skeleton
node path, canonical-role mapping, optional roles, reference measurements,
root-motion and translation-scale policies, and certification evidence. Reuse
requires the exact skeleton signature.

Candidate generation is deterministic and reviewable: exact names, normalized
namespace/prefix stripping, curated aliases, then structural evidence. The UI
shows confidence and evidence and permits an explicit target or Unmapped value
for every role. Manual selection overrides suggestions. Certification rejects
duplicates, wrong sides, broken hierarchy, degenerate chain geometry and hand
frames, and missing required roles.

Root translation is independent of rotation mapping. A separate-root profile
retains Root and Hips position tracks. A Hips-as-root profile emits only one
Hips position track using the source pelvis's complete model-space displacement
scaled by recorded leg height. No target bone is inserted. Imported animation
players are preserved; Kimodo preview uses its own named player.

## Consequences

- Jenny and Mixamo use the same transfer implementation and profile contract.
- Preview camera root-following uses the profile's effective motion bone: Root
  for a separate-root rig and Hips for a Hips-as-root rig.
- Rig edits invalidate reuse instead of producing plausible but stale motion.
- Profiles contain no private model data or absolute machine paths.
- A saved Character Preview strips imported animation players only from a
  detached packed copy. The selected source character and live preview retain
  their original clips, while the saved artifact contains only Kimodo's player.
- Missing anatomy and complex deform/control-rig selection remain explicit
  later goals rather than hidden heuristics in this foundation.
