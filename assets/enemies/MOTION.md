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
