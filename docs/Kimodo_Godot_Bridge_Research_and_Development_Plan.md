# Kimodo Motion Studio for Godot

## Research and development plan

**Status:** Goals 0–21 complete; Stage 1 basic workflow accepted (2026-10-01)

**Target engine:** Godot 4.7.2

**Initial platform:** Windows

**Reference hardware:** GeForce RTX 4070 Laptop GPU (8 GB VRAM), 32 GB RAM

**Distribution:** open source; MIT extension and Apache-2.0 backend additions

## 1. Governing product intent

This section is authoritative. If a later design note, goal, or historical
decision conflicts with these workflows, the workflows win and the other
document must be corrected.

### Basic workflow — current product stage

1. Start a new project-owned session or reopen a previous session. Authoring
   controls remain hidden until a session is active.
2. Select a humanoid character in Godot.
3. Describe a pose or motion with a text prompt.
4. Generate several takes locally.
5. Preview and compare takes on the selected character without altering
   its existing animation.
6. Accept one result as a native Godot animation, or revise the inputs and
   regenerate.

The basic workflow is not complete until all six steps form one coherent,
non-destructive editor workflow. SOMA-77 playback, synthetic-humanoid
retargeting, and intermediate saves are engineering tools, not required artist
steps.

### Advanced workflow — begins after the basic workflow

1. Start or reopen a project-owned session, then place a humanoid character in
   a scene.
2. Select a starting pose from a saved library, or generate and select one.
3. Position the character in the scene with that pose active.
4. Optionally direct motion with more poses, hand or foot targets, root
   waypoints, and paths.
5. Generate one or more takes locally.
6. Preview and compare takes in the scene without altering existing
   animation.
7. Accept a result into the active timeline, save it as a native Godot
   animation, or revise and regenerate.

## 2. Product and architecture boundaries

The project consists of two independently versioned applications:

- **`godot-kimodo`** owns editor authoring, target selection, previews,
  comparison, rig mapping, retargeting, acceptance, undo, and native Godot
  resources.
- **`kimodo-godot-server`** owns Kimodo dependencies, model loading,
  generation, constraint translation, post-processing, and generation-time
  diagnostics.

PyTorch, CUDA, Python, model weights, and inference must never run in the
Godot editor process. The server binds to `127.0.0.1` by default. Remote access
is a later opt-in feature with explicit authentication and hardening.

Use MMCP for model-neutral capabilities and generation while it fits. Add a
versioned Studio job API only when the product requires real server-side
progress, cancellation, retained results, or installation management. Do not
replace a working direct MMCP path merely to match the original architecture
sketch.

The service boundary returns authoritative SOMA-77 motion. SOMA-30 remains an
internal Kimodo constraint/model representation. The extension converts and
retargets motion; the server does not know about a user's Godot rig.

Prefer GDScript and supported editor APIs. Introduce GDExtension only after a
measured bottleneck shows it is necessary.

## 3. Current state after Goal 16

The two repositories now prove a substantial vertical slice:

- The pinned Windows/CUDA backend loads Kimodo-SOMA-RP-v1.1 with the text
  encoder on CPU and motion generation on CUDA within the reference 8 GB VRAM
  limit.
- The backend preserves the MMCP surface, translates supported constraints to
  SOMA-30, and returns complete SOMA-77 animation and six contact channels.
- The Godot dock connects asynchronously to the loopback backend, submits one
  prompt with one or two requested takes, validates every returned glTF
  animation against matching metadata, and previews the selected motion.
- Generated motion can be saved as a lightweight SOMA-77, humanoid, or
  target-character animation library. A separately selected Character Preview
  remains available when a complete scene with its model and textures is
  intentionally wanted.
- A versioned project-owned `KimodoSession` now gates the authoring workspace,
  persists editable intent separately from immutable generation provenance,
  and records explicit successful saves as artifacts. Schema v2 rejects the
  disposable pre-Goal-16 sessions and Goal 13 drafts unchanged; no retroactive
  migration or archive fabrication is attempted.
- Sessions autosave atomically at every meaningful workflow boundary. A
  disconnected dock can restore Jenny, intent, provenance/take summaries, and
  available/missing artifact status without generation or target mutation.
- One request can produce one or two tested takes. Every validated take is now
  archived as a SOMA-77 animation library with a versioned, deduplicated source
  rig snapshot before generation success is reported. History can reload and
  retarget those takes offline until the artist explicitly deletes a source.
- Source, humanoid, and character previews share playback, scrub, orbit, zoom,
  and root-follow controls. Generation builds all three layers automatically;
  the combined Preview & Save workspace switches takes and saves whichever take
  is currently selected.
- Output type defaults to the selected character. One Godot project save dialog
  replaces separate directory/name fields and save buttons; existing output
  paths are rejected rather than overwritten.
- Contract, lifecycle, save/reload, retarget, and fixture tests cover this
  vertical slice. Goal 12 passed a manual multi-angle Jenny review, Goal 13
  passed its offline restart/reload gate, Goal 14 passed its complete
  session/two-take/save/offline-reopen walkthrough, and Goal 16 passed durable
  offline History/retarget/save/delete/restart acceptance.

Goal 14 replaced the `MotionDraft` product metaphor with an autosaved,
conversation-like **session** that must be created or opened before authoring
controls appear. Automated, rendered, live two-take, and final real-editor
checks pass.

This is an engineering demonstration, not yet the basic product workflow.
Important gaps are:

- take comparison is limited to the tested maximum of two and there is no
  explicit Accept/Reject state;
- accepted output is still a standalone export rather than one undoable edit to
  an artist-selected production `AnimationLibrary`;
- target compatibility is proven for Jenny and synthetic/renamed fixtures, not
  a user-facing range of common imported humanoids;
- the completed Goal 15 mapping now transfers all 30 deforming humanoid finger
  rotations and explicitly classifies the remaining SOMA finger intermediates
  and terminals;
- client cancellation stops waiting but does not stop active server inference.

## 4. Stage 1 roadmap — finish the basic workflow

### Goal 13 — persistent, target-first `MotionDraft` (complete)

Make the draft the owner of basic authoring state. A draft selects its target
before generation, stores editable request intent separately from immutable
generation provenance, and records only successfully saved artifacts. Loading
a draft must work offline and must never regenerate or mutate the target.

Implementation, automated acceptance, and the manual Godot editor
restart/offline-reload check are complete. The implementation checkpoint is
`godot-kimodo` commit `3e415b2`.

The detailed scope and acceptance test live in
`kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`.

### Goal 14 — session-first workspace and multiple takes (complete)

The draft-facing entry point is replaced with a versioned `KimodoSession` and a
quiet New/Open Session landing state. Migrate Goal 13 resources losslessly,
autosave every meaningful transition, retain unsaved take payloads only in
memory or a disposable cache, and split the overgrown dock into focused
session, generation/take, and combined Preview & Save responsibilities. Only
takes the user explicitly saves become durable animation artifacts.

`num_samples == 2` is verified from Kimodo through the pinned MMCP SDK and
Godot. One request produces a batch of motion variations that
share the request seed; each take is identified by generation ID, sample index
and name, and a decoded-motion content hash—not an invented per-take seed. Let
the artist switch between tested takes on the selected character while
preserving preview state and source immutability. The selected preview is the
save source; conversion is automatic, while a compact type selector and Godot's
save dialog handle output. A final live run completed in 5.85 seconds inference
/ 6.59 seconds wall time, returned 147,763 bytes, and showed no new node leaks
or material GPU-memory increase. A post-refactor regression also passed in 7.23
seconds generation / 7.41 seconds wall with the same response size and complete
automatic SOMA-77→humanoid→character path.

Measured two-take latency did not trigger the server job/cancel decision gate;
real cancellation/progress remains assigned to the basic-workflow hardening
goal. The user passed the final real-editor session, two-take, save, restart,
and offline-reopen walkthrough. Detailed evidence lives in
`DEVELOPMENT_GOALS.md`.

### Goal 15 — full-skeleton retarget fidelity and rig-aware export (complete)

Audit every animated SOMA-77 joint against humanoid and character output,
implement and test the finger-chain mapping, validate rotation transfer across
the whole mapped skeleton, and introduce explicit rig-profile data where
exact-name assumptions are insufficient. This gate must pass before generated
takes are considered acceptance-ready.

Replace the current 15+ MB packed-character take with a target-specific `.res`
`AnimationLibrary` containing the already rest-corrected Jenny tracks. Godot
animation tracks contain exact skeleton-node and bone paths relative to the
`AnimationPlayer.root_node`, so a generic humanoid library targeting
`HumanoidSkeleton:<bone>` is not directly compatible with Jenny even when bone
names overlap. The Jenny library must target Jenny's actual skeleton path,
carry no mesh/texture payload, reload in the editor without unresolved-track
warnings, and remain explicitly tied to the recorded target signature.

Saving remains one dropdown plus one button with four choices: Character
animation (default), Humanoid animation, SOMA-77 animation, and Character
Preview. The three animation choices produce lightweight `.res` libraries.
Character Preview retains the existing complete `.tscn` exporter and
intentionally embeds the model and textures, so it may be large.

Jenny is the Goal 15 acceptance fixture, not a special case in the transfer
architecture. Sampling, rest-aware transfer, path construction, and finger
mapping must consume explicit source/target profile data so the same functions
can support other imported characters once their profiles are validated.

Implementation verification also reprocessed the original read-only
`closed_fists.tscn` project fixture: all 30 non-rest source finger rotations
survived SOMA-77 → humanoid → Jenny conversion.

A subsequent `fistpump` comparison exposed exaggerated wrist bending despite
correct world-space rotation deltas. The implementation now transfers a full
two-axis anatomical hand frame, preserving wrist flexion and palm roll across
different rest bases. The measured worst hand-direction discrepancy fell from
about 59° to 1.8°. Extending that shared frame through every digit then removed
an observed thumb-roll regression caused by independently aligning each
phalanx's direction: on the saved `Fistpump2` fixture, the worst local thumb
bend difference through SOMA-77 → humanoid → Jenny is 0.009°. An extra unmapped
ponytail-bone regression confirms that non-standard branch bones inherit their
animated parent without receiving Kimodo tracks.

The complete proposed scope, decision gates, numeric/full-skeleton tests, size
test, and manual multi-angle/library-load gate are in
`kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`.

The user completed the final regenerated-preview gate and confirmed that
Jenny's wrist and finger bends match the SOMA-77 source. Goal 15 is complete.

### Goal 16 — durable generated-take history and preview-cache lifecycle

Status: complete on 2026-09-27.

Atomically archive every validated take as a project-owned SOMA-77
`AnimationLibrary` and store its path/hash/contract metadata in the session.
SOMA-77 is the authoritative form because it preserves all source joints and
can be reprocessed by better future retargeters; humanoid and character motion
remain derived forms.

An animation library alone does not preserve the source skeleton's rest pose.
Goal 16 therefore also stores a compact, versioned SOMA rig snapshot for each
distinct rest/hierarchy signature and deduplicates it within session storage.
The library plus snapshot must reconstruct the original source exactly without
the backend, response glTF, current character, or a mutable test fixture.

Add a chronological History workspace grouped by generation and headed by the
prompt, with time/take disambiguation. Selecting an older take loads the small
source resource and rebuilds its humanoid/character preview on demand.
Generated source takes remain until explicit confirmed deletion. Automatically
created previews are ephemeral; explicitly saved Preview Scenes are durable
user artifacts and are never cleaned as cache.

Generation persistence is a recoverable batch transaction: stage and reload all
takes, promote the complete generation with a manifest, then atomically update
the session. At the user's direction, the new session schema rejects disposable
Goal 14/15 test sessions unchanged rather than spending effort migrating their
transient records. Explicit take deletion removes only the automatic source
archive, retains a provenance tombstone, and never deletes exported or accepted
descendants.

The implementation passes exact reconstruction, rollback, interruption
recovery, corruption, deletion, complete Godot/backend, and rendered narrow-dock
checks. The user passed the real-editor
generate→restart→offline-History→retarget→save→delete walkthrough and reported
that everything looked good. The extension checkpoint is `6860e9b`. Detailed
scope and evidence are in
`kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`.

### Goal 17 — explicit acceptance into native animation data (complete)

Let the artist choose an existing or new character-compatible
`AnimationPlayer`/`AnimationLibrary` destination and animation name. Accept the
selected take in one Godot editor undo action without replacing existing
animation unless the user explicitly confirms Replace. A new destination, Add,
and Replace each restore their prior animation/session state through Undo; a
new destination remains as an empty artist-owned library rather than being
deleted. Redo reuses the captured animation rather than regenerating or
retargeting.

Preflight must verify a project-owned editable `.res` library, current target
signature, character track namespace, finite data, and clean-target playback.
Imported/read-only resources and unresolved tracks are rejected before mutation.
Acceptance records the selected take, destination, animation key, target
signature, hashes, mode, and undo state separately from automatic archives and
ordinary Save exports. Deleting the source archive later cannot delete the
accepted animation.

The saved result must remain editable and playable without the plugin,
backend, model, source glTF, or acceptance character fixture.

Implementation now passes focused Add/Replace/new-file, exact Undo/Redo,
clean-target sampled playback, dependency, source-deletion, restart, and
injected rollback tests. A GPU-backed 480×1000 render verifies the compact
Preview & Save layout. The transaction uses same-directory staged writes and
compensating rollback across the library and session; it deliberately does not
claim filesystem-level atomicity across two files. The user passed the complete
real-editor Add/Replace/Undo/Redo/restart gate on 2026-09-29 and selected
retaining an empty artist-owned library after first-animation Undo as the
intended behavior. The extension checkpoint is `aadd920`; the completion record
and split retargeting roadmap are in server documentation checkpoint `35d1bba`.

The full approval-gated scope, failure/undo decision gates, and seven-part
completion test are in `kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`.

### Goal 18 — rig-profile foundation and Mixamo onboarding (complete)

Build the versioned project-owned `KimodoRigProfile`, deterministic
confidence-ranked suggestions, and editable Rig Setup workspace. Begin with the
local-only Mixamo-rigged Remy FBX: normalize its imported `mixamorig_` prefix, require
review of weak/ambiguous matches, define its Hips/root-motion policy, ignore its
bundled taunt during Kimodo retargeting, and prove the complete
History→preview→Save→Accept workflow. Jenny must use the same profile-driven API,
not a special transfer branch.

The open-source
[Kimodo Blender Bridge](https://github.com/lewdineer/Kimodo_Blender_Bridge)
offers useful UI precedent: exact/normalized/alias matching (including Mixamo),
reviewable mappings, per-pair controls, and reusable presets. Its implementation
is deterministic alias matching rather than a general fuzzy/anatomical solver,
so it is inspiration for transparent workflow—not proof or a drop-in algorithm.

Private test characters live only in a gitignored project-local fixture area so
Godot can import them under `res://`; they are not committed or packaged. The
detailed mapping/profile contract, decision gates, and seven-part completion
test are in `kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`.

The complete 28-check Godot suite, backend checks, narrow-dock render, and
manual Remy workflow passed. The final manual pass confirmed mapped-Hips camera
follow, complete Rig Setup restoration after reopen, and saved-preview cleanup
that preserves source/live imported clips. Extension checkpoint: `ded4aef`.

### Goal 19 — variant anatomy and hierarchy (in progress)

Define generic partial-anatomy transfer through reviewed semantic profiles.
Synthetic skeleton families establish the contract across canonical, Mixamo,
sided/numbered, and opaque naming; torso/digit variants; root conventions;
rest bases; scale; extra branches; and valid bone reindexing. Equivalent manual
mappings must transfer identically regardless of names. Imported models test
these rules rather than determine them; prohibit model-specific corrections.

Require matching skin bind and skeleton rest poses; defer alternate reference
selection. A single positive uniform bind-space scale shared by all bindings
is harmless importer compensation and is accepted without rewriting assets;
inconsistent scales and non-scalar offsets remain rejected. Incompatible assets
receive specific mesh/bone diagnostics and
re-export guidance. Mannequiny has a material bind/rest mismatch and now serves
as a rejection fixture, not a reason for special-case transfer mathematics.
Jenny04 imports 64 bones with consistent skins and weighted hair/eye branches;
synthetic eye motion and head-following hair checks pass. Its original remains
unchanged and staged privately. Synthetic four-finger/shorter-torso variants
cover the anatomy Mannequiny was intended to exercise.
Preserve existing clips, optional anatomy, root/scale behavior, profile reuse,
and the complete Save/Accept workflow. Active twist distribution and general
control-rig interpretation are deferred beyond the Stage 1 support contract.
The seven ordered tasks, generic
matrix, profile compatibility policy, numerical/manual gates, and stop conditions are detailed in
`kimodo-godot-server/docs/DEVELOPMENT_GOALS.md`. Implementation and automated
checks and the real-editor manual gate passed; Goal 19 is complete and pushed
on 2026-10-01 (extension `4719722`, documentation `886201e`).
An inherited test cleanup issue removed the shared staged-Remy profile (not
sessions, takes or animations). Test/capture isolation is repaired. After the
owner confirmed unchanged suggested mappings, the profile was recreated and
all affected sessions reopened unchanged. No removal was necessary; see the
ledger's resolved preservation checkpoint and accepted manual gate.

### Goal 20 — faster, evidence-based rig setup (complete)

Improve token-aware naming normalization, ranked hierarchy/side/rest evidence,
and explicit review of ambiguous candidates. Handle neutral `.x` markers and
exporter IDs without erasing meaningful spine/finger numbers. Distinguish a
pelvis named `root.x` from a trajectory/root helper by anatomy, not keywords.
Keep manual mappings and certified profiles authoritative.

Run a bounded, generic common-parent pelvis-helper experiment with corrected
Godette; full Godette support is not a completion gate. If existing transfer
cannot preserve its motion, explain the topology limitation and defer a new
solver. Do not reparent assets or reconstruct Blender controls/IK. General
control-rig solvers, active twist distribution and multiple-skeleton selection
are outside Stage 1's required scope. The detailed proposal and acceptance
matrix are in the ledger. Approved 2026-10-01 with a good-not-perfect scope:
useful suggestions, honest uncertainty and painless manual correction rather
than exhaustive naming or control-rig coverage. Implementation improves private
universal Remy from 12 to 53 suggestions, preserves reviewed choices, and
validates a bounded Godette common-parent body mapping without a new solver.
All 34 Godot checks and rendered setup checks pass; the user accepted Goal 20
on 2026-10-01 and the checkpoint is pushed (extension `f4d667e`,
completion documentation `d69ca22`).

Treat the Character Creator-style Skeleton FBX as an exploratory case only if
it fits without asset-specific hacks.

### Goal 21 — final Stage 1 workflow polish and acceptance (complete)

Add confirmed session deletion with an accurate remaining-draft count and
verified cleanup of session-owned archives/snapshots/manifests/cache. Independent
saved/accepted libraries, explicit preview exports, models and shared rig
profiles survive. Guard ownership, linked paths, partial failures and old
autosave/Undo callbacks; do not sweep arbitrary project data.

Make the Preview & Save viewport approximately square and responsive to dock
width. Polish the existing session chooser, controls and diagnostics without
another wholesale UI redesign. Close the bounded request-copy and optional
advanced-capability correctness issues; keep truthful client-side stop-waiting
semantics rather than adding a server job/cancellation protocol.

Refresh setup/storage/support documentation, verify an add-on-only copy/package
in a clean Godot project against the existing backend, and run the full automated,
rendered, live-smoke and manual basic-workflow gates. This is the final Stage 1
goal for the supported Windows/Godot 4.7.2 workflow, not a universal installer or
marketplace release. Large refactors, broad quality benchmarking, control-rig
solvers and Stage 2 authoring remain deferred.

The seven ordered tasks, deletion ownership contract, regression matrix and
manual acceptance walkthrough are in DEVELOPMENT_GOALS.md. The user approved
implementation on 2026-10-01 and passed all final manual tests. Stage 1 is complete.

## 5. Stage 2 roadmap — advanced in-scene direction

Implement in small vertical slices, preserving the same
session/generation/take/accept model:

1. Saved pose library and starting-pose placement.
2. Prompt blocks and ranges on a motion timeline.
3. Full-body pose keyframes.
4. Hand, foot, and supported end-effector targets.
5. Root waypoints, paths, and initial heading.
6. In-scene take preview and comparison.
7. Acceptance into an active timeline or a standalone animation.
8. Contact-aware cleanup, quality measurements, resampling, and curve
   reduction.

Constraint authoring coordinates are meters, Y-up, XZ ground plane, and +Z
forward at the service boundary. Scene/canonical conversion must remain in one
tested layer.

## 6. Persistent data model

### `KimodoSession`

The session is the authoritative, project-owned authoring workspace;
animations are generated takes or explicit output artifacts. Goal 14 once
migrated Goal 13 resources, but Goal 16 intentionally established a clean schema
v2 boundary and rejects those now-disposable test resources unchanged.
Use a versioned custom Godot `Resource` with these conceptual sections:

- identity: schema version, stable session ID, title, creation/update time;
- target: project-relative scene path, skeleton signature, rig-profile
  reference, destination, output fps, and root-motion policy;
- editable intent: prompt segments, constraints, take count, preset, and
  user notes;
- generation records: exact resolved request and shared request seed,
  capability/model/protocol snapshot, response path/hash, and returned
  metadata;
- takes: stable IDs, generation ID, sample index/name, decoded-motion hash,
  ratings/selection state, and quality information;
- artifacts: native animation, optional diagnostic source/humanoid assets, and
  saved character outputs, each recorded only after a successful save;
- acceptance: explicit destination and accepted take, added only when the
  acceptance workflow exists.

Do not label an artifact "accepted" merely because it was previewed or saved.
Do not serialize live nodes, backend objects, or absolute machine paths.

### Rig profiles

The current Jenny/Godot-humanoid mapping is an acceptance fixture, not a general
rig certification system. Goal 18's `KimodoRigProfile` should store a target
skeleton signature, Godot humanoid `BoneMap`, semantic SOMA mapping, reference
transforms/scale, root-motion policy, optional twist distribution, and
certification results.

## 7. Quality and safety requirements

- Never silently overwrite animation or escape the Godot project when saving.
- Preview must not mutate imported scenes, existing animations, or source
  resources.
- Accept is explicit and undoable; Reject restores the exact prior state.
- Model loading and generation must not freeze the Godot editor.
- Deterministic regeneration requires model/dependency identity, resolved
  settings, request data, and seed—not the prompt alone.
- Capability claims must match tested behavior. In particular, take count
  and cancellation must not be advertised from library defaults without an
  end-to-end test.
- Validate finite transforms, hierarchy, track ownership, duration, fps, and
  artifact dependencies at each boundary.
- Artist-facing errors stay concise; technical details are expandable and must
  not expose secrets or arbitrary local paths.

The current code-review repair list, verification evidence, and ownership by
future goal are maintained in `DEVELOPMENT_GOALS.md` rather than duplicated
here.

## 8. Deferred scope

- Runtime generation in exported games.
- Hosted accounts, billing, or cloud infrastructure.
- Unitree G1 or SMPL-X authoring workflows.
- Guaranteed AMD, Intel, or CPU-only inference support.
- Automatic scene-geometry/collision understanding.
- AnimationTree or state-machine generation.
- Remote/LAN service mode before authentication and path/error hardening.
- A Godot engine fork or custom engine module.

## 9. Reference sources

### Kimodo

- [Official repository](https://github.com/nv-tlabs/kimodo)
- [SOMA-RP-v1.1 model card](https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1)
- [Skeletons](https://research.nvidia.com/labs/sil/projects/kimodo/docs/key_concepts/skeleton.html)
- [Constraints](https://research.nvidia.com/labs/sil/projects/kimodo/docs/user_guide/constraints.html)
- [Generation parameters](https://research.nvidia.com/labs/sil/projects/kimodo/docs/user_guide/configuration.html)
- [Output formats](https://research.nvidia.com/labs/sil/projects/kimodo/docs/user_guide/output_formats.html)
- [Benchmark metrics](https://research.nvidia.com/labs/sil/projects/kimodo/docs/benchmark/metrics.html)
- [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)

### Backend and Godot

- [`motionmcp-kimodo`](https://github.com/animatica-ai/motionmcp-kimodo)
- [MMCP overview](https://animatica.ai/mmcp)
- [Godot `EditorPlugin`](https://docs.godotengine.org/en/stable/classes/class_editorplugin.html)
- [Godot `EditorUndoRedoManager`](https://docs.godotengine.org/en/stable/classes/class_editorundoredomanager.html)
- [Godot retargeting](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html)
- [Godot `AnimationLibrary`](https://docs.godotengine.org/en/stable/classes/class_animationlibrary.html)
- [Kimodo Blender Bridge retargeting reference](https://github.com/lewdineer/Kimodo_Blender_Bridge/blob/main/retarget.py)
