# Stage 1 completion record

**Completed and owner-accepted: 2026-10-01. Goals 0–21 are complete.**

Tested product checkpoints, both pushed:

- Extension `7e9d1a8` on `main` — “Complete Stage 1: basic animation workflow is working”.
- Backend `0f1d347` on `codex/milestone-0-bootstrap` —
  “Complete Stage 1: verified local backend and basic workflow”.

Later documentation-only commits do not imply another product implementation.

## Compact goal history

| Goal | Durable outcome | Principal checkpoint |
| --- | --- | --- |
| 0 | Forked/locked Windows CUDA backend, model/MotionCorrection/dummy checks | Server `c90cf82`, `688ea8b` |
| 1 | Real CPU text encoder plus CUDA motion within 8 GB VRAM | Server `d3c2d43`; Kimodo `3362b92` |
| 2 | Hashed inherited protocol/error/glTF baseline | Server `4fc31b6` |
| 3 | Complete SOMA-77 output and six contacts; SOMA-30 constraints internal | Server `06a5f8c`, `def4acf` |
| 4 | Godot repository and canonical in-memory glTF playback | Extension `f1f9982` |
| 5 | Self-contained native SOMA save/reload/playback | Extension `986306a` |
| 6 | Async loopback capabilities and dock | Extension `b358606` |
| 7 | Typed generation, strict response validation, disposable preview | Extension `5680fa1` |
| 8 | Launcher, normal quality defaults, collision-safe native Save | Extension `aa0a675`, `a6f1f0f` |
| 9 | SOMA→humanoid transfer and corrected locomotion ownership | Extension `f40fc5d`, `5327522` |
| 10 | Integrated humanoid preview/save, orbit/scrub/follow | Extension `ddd1e07`, `961218b` |
| 11 | Skinned Jenny transfer and corrected anatomical rest directions | Extension `3466190`, `71346ad` |
| 12 | Selected character preview and complete scene export | Extension `d985782` |
| 13 | Persistent target-first intent and exact provenance | Extension `3e415b2` |
| 14 | Autosaved session-first UX, two takes, focused UI, compact Save | Extension `0898724`–`fb16d7b` |
| 15 | Full-skeleton/finger audit, wrist/thumb frames, lightweight character libraries | Extension `ad5d23b` |
| 16 | Every take archived with versioned rig, recoverable batches, offline History | Extension `6860e9b` |
| 17 | New/existing production-library Add/Replace and exact Undo/Redo | Extension `aadd920` |
| 18 | Reviewed reusable profiles/Mixamo and corrected camera/reopen/preview cleanup | Extension `ded4aef` |
| 19 | Generic partial anatomy, bind/rest diagnostics, harmless shared scale | Extension `4719722`; server record `886201e` |
| 20 | Bounded evidence matching and common-parent feasibility; no control solver | Extension `f4d667e`; server record `d69ca22` |
| 21 | Safe session deletion, square preview, correctness repairs, clean-project acceptance | Extension `7e9d1a8`; server `0f1d347` |

## Final verification

- Full Godot 4.7.2 suite: **35 checks passed**, without engine/script errors or
  orphan warnings. Final owner-context rerun passed before the completion commit.
- Backend: **24 passed, 7 hardware-specific skips**; Ruff passed. The new CPU
  deep-copy/nonzero-origin/retry regression executed, rather than being skipped.
  Only known pinned Kimodo torch.jit deprecation warnings remain.
- New project installed packaged add-on + MIT LICENSE only; privately imported
  Jenny04, no development scenes/profiles or repository fixture dependencies.
  Packaging excludes user outputs, private models, tokens, weights and environments.
- Live loopback: 30-frame/100-step one-take batch **7.94s**, distinct two-take
  batch **10.76s**. These are smoke timings, not quality/performance guarantees.
- Four Save forms, Accept/Undo/Redo, fresh Character Preview reload and library
  playback on a fresh imported character passed. Separate-process History reopened
  and rebuilt a preview without a backend connection.
- GPU-rendered 360/680-pixel layouts passed, including square viewport, scrollable
  controls and clipped long title/camera hints. Internal captures remain in the
  combined workspace `.research/goal21-ui/`.
- User reported **all final manual tests passed**, completing Stage 1.

The five manual gates are retained here as a compact regression checklist:

1. Clean install/session/character setup, one/two takes, square preview at narrow/
   wide sizes, switching, camera and playback; honest Stop waiting text.
2. Save and production Accept, Add/Replace/Undo/Redo, fresh target playback and
   preservation of newly typed intent during Undo.
3. Offline restart/History; actionable missing/changed references and recovery
   without source fabrication.
4. More than eight sessions visible; correct draft count; Cancel unchanged;
   confirmed deletion removes owned data only and stays deleted after restart/Undo.
5. Empty/active deletion safely returns to chooser; generation gates switching/
   deletion; independent exports, profiles and production libraries survive.

## Consequential repairs and decisions

- The old service discarded 47 presentation joints. Full SOMA-77 data now survives;
  full transfer audit classifies 55 mapped rotations, nine collapsed intermediates
  and 13 terminal joints, with 30 mapped humanoid finger rotations exercised.
- Anatomical rest-direction transfer fixed arm/neck deformation. Two-axis palm
  alignment reduced the observed wrist-direction error from about 59° to 1.8°;
  shared digit frames removed backward-thumb compensation (0.009° worst measured
  bend drift on the original Fistpump2 sample). Preserve numerical regression tests.
- Character libraries target actual character paths, not generic humanoid paths.
  They contain animation only; the complete preview exporter intentionally remains.
- Generated take storage changed from transient drafts to durable source archives
  with rig snapshots. The user chose not to migrate disposable pre-Goal-16 sessions.
- Reviewed mappings, partial anatomy and synthetic naming/reindexing families
  replaced exact-name/Jenny-only assumptions. Jenny04 hair/eye and additional
  user-imported Auto Rig Pro/universal/Unity rigs passed manual workflows.
- Mannequiny is an incompatible bind/rest rejection fixture. Godette's common
  positive uniform scale is accepted; a bounded common-parent body mapping works,
  but complete control/face/IK semantics are not claimed. No model-specific solver.
- Test profile cleanup once removed a shared Remy profile. Isolation was repaired,
  the user confirmed its suggested map, and the profile was recovered; affected
  sessions reopened unchanged. No animation/session data was discarded.
- Goal 21 repaired request mutation, optional advanced-capability gating and
  stale acceptance Undo overwriting newer session fields/dirty intent.
- Session deletion now proves exclusive ownership, rejects links/shared/unknown/
  protected data, revalidates confirmation, stages recoverably, and blocks stale
  autosave/Undo resurrection. Real Windows junction/lock/interruption tests pass.
  Library Undo remains independent; retaining an empty library is intentional.

Permanent decisions remain in [backend ADRs](https://github.com/Vega-KH/kimodo-godot-server/tree/codex/milestone-0-bootstrap/docs/adr).
Remaining maintenance and exclusions belong in [DEVELOPMENT_GOALS.md](DEVELOPMENT_GOALS.md),
not as unresolved Stage 1 gates.

## Historical-document retrieval

The long server ledger, bootstrap baseline and full Goal 21 walkthrough are
preserved in backend checkpoint `0f1d347`. For example, from that repository:

```powershell
git show 0f1d347:docs/DEVELOPMENT_GOALS.md
git show 0f1d347:docs/DEVELOPMENT_BASELINE.md
git show 0f1d347:docs/GOAL21_MANUAL_TESTS.md
```

The full original root plan was versioned before condensation in extension
checkpoint `7e9d1a8`:

```powershell
git show 7e9d1a8:docs/Kimodo_Godot_Bridge_Research_and_Development_Plan.md
```

There is one current plan/ledger now, not an active duplicate of this history.
