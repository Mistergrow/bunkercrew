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

## Turned pieces, tools and weapons

The articulated rig leans, ducks, falls and lies down. Its coat and head are never drawn as a rotated texture quad: `generate_character_workers.py` also writes `<identity>_turns.png`, the generated head and torso in 48 attitudes 7.5° apart (row 0 torso, row 1 head), the rear pieces for a ladder sway of ±3 steps (row 2) and a supine coat whose pack is pressed flat under the back for the steps around lying on the back (row 3). Each attitude is a RotSprite turn of the authored piece (three Scale2x passes, one sample per native texel; quarter turns are exact), so no colour is added and step 0 is the piece itself. `WorkerPoseArt.drawn_torso_transform` snaps the drawn coat, head, arm sockets and badges to the nearest attitude on a whole texel; pose math, contacts and weather keep the exact `torso_transform`. The `turns` entry of each `<identity>.source.json` records the layout.

`generate_tool_turns.py` writes `tool_turns.png`: the pick in 48 attitudes (re-rasterized from its vector geometry, head at the cell centre) and the six personal weapons, plus four without their magazine for the reload, RotSprite-turned from level native rectangles for local aims from -97.5° to +75°. `tools/bake_infantry_turns.py` turns the baked infantry parts into 22.5° key attitudes for the drawn infantry defeat (`assets/enemies/infantry_turns_v1.png`). All three are checked for reproducible output and provenance by `tests/worker_identity_generator_test.py`.

Under a low lintel or through a dug adit a moving worker ducks and keeps running bent double, head up; a slow or resting one still crawls.

## Authored body keys and follow-through (pass 6A-2)

Idle, hit, collapse, get-up and machine tending are held poses in whole texels, played stepped at body rates (style bible §5), from `scripts/worker_motion_keys.gd`:

- **Idle** (8 fps, 24-frame loop, own phase per worker): weight on the rear foot, transfer to the front foot and back (hips lead, shoulders a frame late, free heel lifts), one breath per half (chest a texel, head and hanging hands a frame later), pack and hair trailing each transfer and swinging through; every third loop a glance up. Idle gestures (`worker_gesture_library.gd`) still interrupt it.
- **Hit** (12 fps, 0.58 s): impact, held peak (shoulders thrown 6 texels, hips 3, head snapped two turned steps, arms up, the boot on the pushed side steps 3 texels), three recovery keys with the pack overshooting. Also played over a guard, limp or idle gesture. Gameplay knockback, stun, i-frames and colliders are untouched.
- **Collapse** (12 fps, 0.75 s): buckle, knee down with a hand reaching for the floor, topple back, fall, floor strike with limbs and head bouncing, settle on the back; then slow breathing. **Get-up** over the 1.1 s rise: eyes open, onto an elbow, sit up and draw a knee, kneel, push off the knee, stand with the pack settling.
- **Tending** (8 fps, 1.5 s loop): a worker idling at the running production machine in focus knocks the drum twice with a mallet, then watches its mouth; a load stays on the near hip. Moving, acting, aiming, injury or a nearby threat end it at once.

`generate_crew_layers.py` writes `<identity>_layers.png` for the follow-through: the coat without its gear, the gear alone, the head without its hanging hair and the hair alone, at rest and swung one step behind/forward (braid, bob and crop; Mara's satchel, Nora's tube, Levin's aerial, Selma's bag and Rika's cable bend; rigid packs only shift). It records and replays the canonical `torso()`/`head()` calls of `generate_character_workers.py` (which stays byte-identical), so no geometry is duplicated; at rest the layers composite to the authored pieces texel for texel. `WorkerPoseArt` draws them for turn steps -3..3 and keeps the single turned piece beyond. Provenance: `crew_layers.source.json`. Checks: `tests/worker_identity_generator_test.py`, `tests/worker_motion_keys_test.gd`.

## Standing idle, walk keys, revive, dance and the working mixer (pass 7A-crew)

No new bitmaps; every change is authored keys in `scripts/worker_motion_keys.gd` on the existing rig and layers, checked by `tests/worker_motion_keys_test.gd`. Key-pose sheets (real `Worker`/`WorkerVisual`/`WorkerMedical` state at 60 fps, drawn 3x): `godot --path . --script tests/crew_motion_key_sheet.gd -- --no-profile-save --no-upnp --out=<folder>` on the isolated display.

- **Standing idle:** `worker_personality.gd`'s stances stand the boots 6-7 texels apart roughly under the hips (sockets a texel inside each boot, hip_spread 2), hips high for nearly straight legs, arms hanging with a slight bend; the earlier 14-20 texel spread read as a frozen stride. The 6A-2 idle key then stands one leg upright under the weight while the free heel lifts (now 0.26 rad), with breath, late hands, pack and braid on top. Gestures, work and mining start from the same stance.
- **Walk and run:** four held body keys per step on the stride phase (contact, down, passing, up): bob in texels, chest lean, the head a key late, the pack lifting and landing late and pack/hair swinging. Boots roll heel to toe (`walk_foot_angle`) on the unchanged world-planted gait; the forward hand rises on an arc towards the chest. A gate panel or wall standing on the floor ahead no longer reads as a lintel: the body stays upright through an opening gate (`WorkerVisual.body_crouched`; the clearance probe's `crouched`, which the weapon height reads, is unchanged).
- **Revive:** the reviver steps in (two keys at 12 fps), kneels beside the patient's chest and presses at 8 fps (10 for a critical patient), timed from the replicated aid progress. The drawn rig slides along the body by `aid_offset` (at most 32 texels; collider, position and aid range unchanged) and is drawn behind the patient, so the body covers the far knee and the hands rest on top of the chest. After the revival it pushes off the knee, rises and steps back to its own place through four keys at 10 fps; any movement or action except the still-held interact ends that at once. Bandaging a crew mate on their feet (also straight after a revival) is done standing (`treat_pose`).
- **Dance:** every standing dance carries a one-bar groove of held beat poses (`DANCE_KEYS`): beat 1 punches both arms forward, beat 2 pumps them down, beat 3 throws both up (near arm up and forward, clear of the face), beat 4 points high; the weight steps foot to foot with the free heel lifting and the head looks up and down; full-body dances nod two drawn head steps on the kick. Free gloves move as plain translations held to the arm's reach; an arm chain a dance authors with its own elbows (popping, waves) is lifted rigidly about its shoulder instead, mixed continuously through transitions (`arm_chain`), so each dance keeps its own carriage and steps underneath. The keyed layer's gate is rate-limited and rests through repertoire changes, so drops into floorwork lower the arms over a beat.
- **Mixer (`scripts/mixer_animation.gd`, `shaders/mixer_drum.gdshader`):** one plate in six wears a pale primer band that crosses the visible face once per turn; the drum bumps a texel down as each plate seam rolls over the support roller (its sprite offset; the position stays the beat bob's); cement spatter arcs out over the lower lip and drops to the floor on the texel grid at 24 fps; the tending worker's mallet contact keys knock the drum (`WorkerVisual._knock_drum` → `MixerAnimation.knock`): a one-texel jolt along the blow and a flash, sparks and dust puff drawn above the crew. Reduced effects hold the rumble still and keep two flecks.

## Menu bust portraits

The menus use `portraits/portraits_v3.png`: one 80-pixel bust per identity for the character selection, the personal panel, story encounters and the online lobby. v3 is the detailed v1 drawing limited to its own 40-colour palette per bust (max-coverage, no dither, hard alpha), so the shading sits in clean clusters instead of 2,000+ colours of noise. Rebuild with `python3 tools/build_crew_portraits_v3.py`; provenance in `portraits/portraits_v3.source.json`. Menus draw it at whole multiples only (`CharacterSelectPanel.draw_bust`).

`portraits/portraits_v2.png` (pass 6A-2), kept for comparison, matches the sprites more literally but reads plainer than the portraits. Each bust is the identity's own sprite geometry re-drawn at twice the sprite density from the canonical author, in the sprite's palette ramps and chibi proportions, with 1-pixel ink contours and a hand-set bust-density face (eye under the brim, brow, ear, nostril, lips) plus braid/bob strands, helmet light and a coat fold; 14-32 colours per bust instead of the 2000+ of v1. Menus draw it at whole multiples only (`CharacterSelectPanel.draw_bust`), framed, with the animated runtime figure still shown beside it in the selection. Rebuild with `python3 tools/build_crew_portraits.py` (Pillow required); `--v1` rebuilds the earlier atlas. Checks: `tests/crew_art_assets_test.py`.

`portraits/portraits_v1.png`, kept for comparison, was reduced from production references: Mara, Branko and Ivo are reduced from their production references in `identities/`. The five later identities had no reference, so one was generated per identity in the same style, with Mara's reference as the style image and the identity's own runtime sprite as the identity image. Those originals are kept in `portraits/references/` and excluded from export. Generator, task IDs, prompts, inputs and hashes are in `portraits/portraits_v1.source.json`. Characters added by extension packs have no bust and keep their animated sprite.
