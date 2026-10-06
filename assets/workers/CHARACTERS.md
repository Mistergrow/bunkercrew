# Character artwork

All eight selectable identities use their own six texture parts: body, foreground arms, clean side-view head/torso, and clean rear-view head/torso. Character identity follows `Worker.character_id`; the P1–P4 label identifies the local controller separately.

- **Mara:** rust jacket, reflective bands, amber hardhat, dark braid and light satchel.
- **Branko:** broad navy coat, padded shoulder, split coat hem, ivory hardhat and beard.
- **Ivo:** narrow leather tool vest, teal sleeves, low fabric cap and welding goggles.
- **Nora:** broad bronze helmet brim, short dark bob, high-collared slate engineer vest, long blueprint tube and document folio.
- **Levin:** pointed olive hood, asymmetric field poncho, neck scarf and radio pack with a long aerial.
- **Selma:** soft ivory medical cap, short auburn bob, sage field jacket and a large cross-marked medical bag.
- **Oskar:** raised headlamp, short moustache, heavy work overalls, long leather apron and a tall dust pack.
- **Rika:** ribbed dark beanie, cropped hair, copper headset, ochre insulated jacket and a circular cable reel.

`generate_character_workers.py` is the canonical author for all eight identities. It draws original native geometry using primitives from `generate_workers.py` and reads the established trajectories from `character_motion_frames.json`. Rebuild with `python3 assets/workers/generate_character_workers.py` (Pillow required). This leaves the original worker textures, material props and all pose/armor metadata byte-identical. It does not read or edit imported artwork. The old `generate_recruits.py` and `generate_solo_recruits.py` commands remain compatible subset entry points; they preserve the eight-character catalog and cannot reintroduce inherited base heads.

All eight preserve the existing 19 states, 110 frames, 112-pixel cells, feet anchor `(48, 90)`, mining contact frame and carrying/weapon/ladder grips. Separate clean head/torso textures let medical and idle gestures move limbs without duplicating old atlas arms. Character selection displays the actual animated runtime frames. Head and torso origins stay `(49, 33)` and `(48, 48)` respectively. Side profiles remain the front-facing presentation; no frontal dance sprite is introduced.

Each adjacent `<identity>.source.json` lists the six generated asset hashes, source hash, native origins, unchanged trajectory hash and Bunkercrew-only distribution terms. Earlier source notices and asset hashes are preserved verbatim in `identities/source-history-20261005.json`; the prior bitmaps and generators are archived under `artifacts/crew-identities-20261005/visuals/baseline-source/`. The original Imagegen art-direction references and their prompts remain unchanged.

Validate reproducible generation, all 880 frame cells, silhouette differences and compatibility entry points with `python3 tests/worker_identity_generator_test.py`. Runtime routing and actual atlas/articulated/carrying/rear/medical appearance are covered by `godot --path . --script tests/worker_visual_identity_test.gd -- --no-profile-save --no-upnp --capture`. The [eight-character before/after gallery](../../artifacts/crew-identities-20261005/visuals/index.html) contains native-size and 2× rendered poses plus two prepared four-worker Aschewerk scenes. Its fixture conditions and resource hashes are recorded in each capture JSON.

## Individual movement

- **Mara:** controlled stride, restrained arm swing, balanced landing; checks her radio and tightens her shoulder strap.
- **Branko:** wider, slower steps with a low foot lift, heavy shoulder settling and a deeper landing; rolls his shoulders and adjusts his beard.
- **Ivo:** quick narrow steps with high knees, bent arms and a compact jump; adjusts his goggles and inspects a wrench.

Idle, walking, carrying, jumping, falling, landing, mining anticipation/recovery and station work have different joint trajectories. `character_motion_frames.json` records the actual authored hips, shoulders, hands, feet, item anchors and tool angles for every frame. Armour, dressings and weather contacts use those same endpoints. The fixed ladder grips still advance one frame per seven world pixels; mining still strikes on frame 3 at 12.8 frames per second. Cargo and weapon grip points are unchanged.

`scripts/worker_personality.gd` shares presentation pacing and gesture names with the menu. `WorkerPoseArt.sample(kind, phase, gait, reach, character_id)` and `draw_identity_pose(canvas, pose, character_id)` render the same articulated gestures without creating gameplay actors. Each worker has an independently seeded bag of six exclusive idle gestures; walking, aiming, damage, nearby threats and medical treatment interrupt them immediately. The four legacy gesture names remain available for existing galleries.

Run `godot --headless --path . --script tests/worker_personality_test.gd -- --no-profile-save` to check movement differences after removing the initial stance, grip/contact contracts, runtime identity changes and gesture interruption. Gameplay movement speed, inventory and health are unaffected by presentation pacing.

`identities/` contains the Imagegen art-direction references and full prompt provenance. Runtime sprites are independently authored pixel geometry matching that shared brief; the generated reference illustrations are not animation sheets. `character_visuals.json` records the native source, palettes, proportions and animation contract.

Visual review: `godot --path . --script tests/character_identity_gallery.gd -- --no-profile-save`. Add `--video` to save 180 frames under `artifacts/character-identities/frames/`. The arranged gallery includes normal game size and enlarged action/medical poses. The rendering regression runs with `godot --path . --script tests/character_identity_test.gd -- --no-profile-save --capture`.

The current motion comparison is in [`artifacts/character-motion/index.html`](../../artifacts/character-motion/index.html): a 12-second movement/work clip and a 9-second gesture clip at 30 fps. These use actual `WorkerVisual` instances in prepared states, shown at native size and 2×. Rebuild with `godot --path . --script tests/character_motion_preview.gd -- --no-profile-save`, adding `--gestures` for the second clip. `capture.json` records the prepared conditions and encoding.

## Additional performances

`worker_gesture_library.gd` adds six new performances per selectable identity (18 total), on top of the earlier two gestures and 19 atlas states:

| Character | Four additional idle actions | After sustained work | After a cleared wave |
| --- | --- | --- | --- |
| Mara | Scan the horizon, tighten a glove, write a route note, check a bootlace | Dust off a sleeve | Give the all-clear salute |
| Branko | Flex knuckles, brush his coat, drink from a canteen, settle his belt | Wipe his brow | Fold his arms and nod |
| Ivo | Check pockets, test a spring, polish a lens, tune a meter | Shake out his hands | Small fist pump |

These are native articulated animations, authored as timed poses with eased transitions; no additional generated images are used. Both boots stay planted. Notebook, canteen, spring, cloth and meter follow the actual hand anchors. The joint solver matches the atlas generator's perpendicular direction, preventing reversed elbows/knees when switching to articulated poses.

`worker_expression_clock.gd` observes at least 0.65 seconds of mining or station work, then 0.22 seconds of safe rest, before a recovery gesture. It observes the round's `attack` → `salvage` transition for wave-clear gestures. Movement, held actions, cargo, aiming, injury and nearby threats cancel these reactions. Work recovery has an eight-second cooldown and canceled gestures are not delayed until a later idle. Scene pause freezes their clocks; reduced effects preserve the animation timing.

Validation: `tests/player_animation_expansion_test.gd` checks runtime triggers, shuffled idle reachability, gameplay interruption, pause and continuous connected limbs with fixed contacts. The [33.4-second gallery](../../artifacts/player-animation-expansion/index.html) shows all 18 additions through actual `WorkerVisual` instances at native size and 2×. Its prepared states are documented in `capture.json`; it is a presentation fixture, not a playthrough. Rebuild with `godot --path . --script tests/player_animation_expansion_preview.gd -- --no-profile-save` and encode the saved 30 fps frames with FFmpeg.
