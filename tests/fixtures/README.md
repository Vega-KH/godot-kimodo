# SOMA-77 playback fixture

`soma77_mmcp_1_0.gltf` is a copied, self-contained MMCP animation response
recorded live by `Vega-KH/kimodo-godot-server` at backend implementation commit
`06a5f8cd412be25e3af2678a1a44eb1ca923eac9` and fixture commit `def4acf`.

- Prompt: “A person walks forward naturally, then turns to the right.”
- Seed: 1234
- Duration: 30 frames at 30 fps
- Source skeleton: SOMA-77
- Model: `nvidia/Kimodo-SOMA-RP-v1.1`, revision
  `6c9233af1180b8151e3c4703477104af5dce9dd5`
- Expected SHA-256: `54a7a63a326149d4573005be29df49142345bec43240f4cc2451db6bd70461b0`

The file contains animation data and an embedded glTF buffer. It contains no
model weights, credentials, or personal paths. Kimodo model provenance and
license information are available from NVIDIA; backend code is Apache-2.0.
This fixture is not relicensed by the extension's MIT license.

`soma77_capabilities.json` is the matching Goal 3 `GET /capabilities`
response copied byte-for-byte from the same backend fixture set. Its expected
SHA-256 is
`b4f3b573fb9d926c65a76da08f0adaaf3f4c016f79ecbbe2507c040b50c6b219`.
It drives offline typed-contract, incompatibility, and dock-state tests.

## Manual playback check

1. Open this project in Godot 4.7.2.
2. Open `tests/fixtures/soma77_playback.tscn` and run the scene.
3. Confirm the line skeleton animates for one second and loops, with root
   motion visible and no import or script errors.

Godot retains all 77 bones but optimizes nine identity-only rotation channels
out of the generated native `Animation`. The automated test separately proves
that the source glTF contains all 77 rotation channels and that the resulting
native animation has the expected 68 varying rotation tracks plus root motion.
