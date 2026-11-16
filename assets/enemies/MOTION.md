# Mechanical performances

The 18 enemy classes and the final **Muttermaschine** each have seven additional performances. Existing walking, flight, aiming, attack windup and recoil remain separate and are not included in this count.

| Performance | Runtime trigger | Visible action |
| --- | --- | --- |
| Deployment | A new enemy first enters the camera | Suspension extends, optical mast rises, cooling shutters open; aircraft change engine trim. |
| Target acquisition | The target changes; periodic sensor checks | The optical head scans both sides and settles; mast and hull counterbalance the sweep. |
| Stabilization | Ground movement stops or flight speed drops | Suspension compresses and settles; aircraft tilt their engine assemblies to catch the hull. |
| Impact recovery | Replicated or local health decreases | Hull yields away from impact, knee joints absorb the load, then hydraulics recover. |
| Weapon service | A shot/volley completes | Breech slider retracts and returns while the access shutters open and close. |
| Cooling purge | Every three actual shots | Cooling shutters lift, five bounded steam wisps rise and fade, then shutters close. |
| Destruction | The original enemy dies or disappears from the remote snapshot | The actual hull, weapon, legs/propulsion and variant equipment collapse together and fade. |

## Per-figure direction

`enemy_motion_pose.gd` defines separate mass, actuator travel, mast height and roll values for all 19 figures. Lighter runners and interceptors react briskly; heavy siege machines and the boss use longer, restrained movements. Shields, lance, repair tools, bomb racks, wings and boss hardware retain their original drawing code throughout destruction.

The reusable source is native GDScript geometry layered onto the existing painted chassis atlas; no new bitmap source or license was introduced. Leg plates, joints and feet use cached native pixel textures with warm metal, dark cut edges, 1px surface grain and fixed wear. The same helpers draw aircraft skids/engine mounts and all wrecks. Upper leg sockets follow the real hull transform. Weapon presentation remains aligned with the real aim point. These performances do not change enemy damage, cooldowns, movement speed, rewards or hitboxes.

## Runtime and verification

- `enemy_motion.gd` runs as a presentation child. Frozen network gameplay parents still animate, and game pause freezes the presentation.
- F3 reduces redraw frequency and steam wisps; animation clocks keep advancing normally.
- Death immediately retires the original enemy and its collision. At most 20 detached visual wrecks remain, each for less than 1.8 seconds. Their drawing delegates never enter the game tree or run combat logic.
- `tests/enemy_motion_test.gd` checks every figure, actual observation triggers, pose continuity, pause, F3, frozen parents and cleanup.
- `tests/enemy_motion_preview.gd` captures prepared poses using the real scenes, at normal timing, native scale and 2×. See `artifacts/enemy-motion/index.html`; the gallery is an inspection fixture, not a recorded battle.

## Pass 6A art (v2)

Every v1 sheet stays next to its replacement for before/after comparison; the code references the v2 files.

| Asset | Author | What changed |
| --- | --- | --- |
| `infantry_parts_v2.png` | `tools/generate_infantry_parts_v2.py` | Hand-placed texels per role in the v1 tile layout: own headgear and face (dome helmet with red unit mark and chin strap, respirator with red lens and filter, peaked cap with goggles and trailing scarf, heavy helmet with ear cup and visor slit, boonie hat with ghillie strands and face paint, ivory cap with neck curtain and spectacles), own coat colour and kit, own weapon (assault rifle, revolver launcher with fluted cylinder, suppressed carbine, belt-fed gun with perforated jacket, scoped rifle, compact carbine). Grip, muzzle, crown and origin points are unchanged. |
| `infantry_turns_v2.png`, `infantry_living_turns_v2.png`, `infantry_gun_turns_v2.png` | `tools/bake_infantry_turns_v2.py` | RotSprite keys of the v2 parts; the living weapon now holds 7.5 degree keys instead of turning as a rigid tile. |
| `machine_weapons_v2.png` | `tools/generate_machine_weapons_v2.py` | Walker cannons in five families (light, heavy, colossus, assault, siege) at world size, in 7.5 degree aim keys, drawn upright by the `WeaponKeys` child of the weapon node. Muzzle, tracer and aim stay on the exact node. |
| `aircraft_hulls_v2.png`, `chassis_atlas_v2.png`, `vehicle_hulls_v2.png` | `tools/grade_enemy_hulls.py` | Colour and value grade with unchanged alpha: per-type paint hue, S-curve, sky-lit upper planes and shaded lower body, a lit top edge one world texel thick, aircraft red nose sensor. The mortar carrier has its own hull copy. Measure with `tools/measure_enemy_contrast.py`. |
| `aircraft_pods_v2.png` | `tools/generate_aircraft_pods_v2.py` | Five pod families (dart, gun, rocket, arc, heavy) in 48 aim keys, drawn upright by `AircraftArt._pod` through a counter-transform (the node keeps the exact aim, launch point and charge), scorched when badly damaged; the bomber/dive-bomber bay is a recessed, ribbed, riveted sprite on world texels. |

Held frames (style bible section 5): the infantry collapse and wind-up raise are sampled at 12 body frames per second, the infantry hit is one impact pose and three recovery frames over the replicated 0.2 s timer, and the machines' impact performance and ground wreck collapse are held at 12 frames per second. The clocks, gameplay timing and replication are unchanged; the final lock of a wind-up onto the combat gun stays exact. `tests/enemy_art_v2_test.py` checks reproducible generation, layout, anchors and identity.

## Pass 7A (world density and life)

| Asset | Author | What changed |
| --- | --- | --- |
| `infantry_parts_world.png`, `infantry_living_turns_world.png`, `infantry_gun_turns_world.png`, `infantry_turns_world.png`, `infantry_limbs_world.png` | `tools/bake_infantry_world.py` | The v2 field kit reduced to its drawn size (human factor 0.82, one texel per world unit; palette vote, ink contour, crosses, ear cup and chin strap set by hand; the heavy gunner's slate ramps lifted for readability), its keys turned at that density, limbs, caps, gloves and boots authored at world density. `GroundInfantryArt` draws all of it 1:1 on whole world texels in an art frame; the rig node keeps its scale, so muzzles, weather, gore and hitboxes are unchanged. The v1/v2 sheets stay. |
| `machine_weapons_world.png` | `tools/bake_machine_weapons_world.py` | The walker cannon keys at every walker's drawn scale (normal and elite), drawn 1:1 by `WeaponKeys`. |
| `vehicle_guns_src.png`, `vehicle_guns_world.png` | `tools/capture_vehicle_guns.gd`, `tools/bake_world_density_art.py` | The procedural vehicle guns rendered at 8 px per unit and baked in 2 degree aim stances at the drawn and elite size. |
| `shield_bubble_world.png` | `tools/bake_shield_world.py` | The airship's energy bubble as pixel art: 2-texel rim, dithered bands, crown highlight. |

Motion: the infantry walk steps through held keys per role (8 or 6 per cycle, march, crouch-walk, trot, plod, stalk) with the planted boot pinned to the ground and the stride lengthened against the gait clock; the soldier falls backwards through a kneel and a four-frame topple into one of two lying bodies (legs over the coat, boots up, the weapon dropped behind); standing soldiers breathe a texel, the weight shifts, every shot kicks the shoulders a texel and the weapon one key. Walkers breathe a texel at rest and sink into a three-frame brace through the wind-up, pitch back two stances on the shot; vehicles bounce a texel on the road and shudder a texel at idle, their wheels turn in held spin keys. All of it is presentation: the weapon nodes that fire, every timer, hitbox and replicated field are unchanged.
