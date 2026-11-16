#!/usr/bin/env python3
"""Pass 6A enemy art: reproducible v2 sources, unchanged layouts and anchors,
per-role identity and untouched v1 originals. Writes only to a temp folder."""
from pathlib import Path
import hashlib
import json
import sys
import tempfile
from itertools import combinations
import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
ENEMIES = PROJECT / "assets/enemies"
sys.path.insert(0, str(PROJECT / "tools"))
import generate_infantry_parts_v2 as parts  # noqa: E402
import bake_infantry_turns_v2 as turns  # noqa: E402
import generate_machine_weapons_v2 as weapons  # noqa: E402
import grade_enemy_hulls as hulls  # noqa: E402
import generate_aircraft_pods_v2 as pods  # noqa: E402
import bake_infantry_world as infantry_world  # noqa: E402
import bake_machine_weapons_world as weapons_world  # noqa: E402
import bake_shield_world as shield_world  # noqa: E402

checks = 0
# The originals stay for before/after comparison (style bible section 7).
ORIGINALS = {
    "infantry_parts_v1.png", "infantry_turns_v1.png", "infantry_living_turns_v1.png",
    "aircraft_hulls_v1.png", "chassis_atlas.png", "vehicle_hulls_v1.png",
}
# InfantryRoleArt muzzles (gun-local x) that the drawn weapons must reach.
MUZZLES = {"rifle_guard": 32, "grenadier": 32, "scout": 27, "heavy_gunner": 44, "marksman": 49, "combat_medic": 25}


def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tile(atlas, index):
    x, y = index % 16 * 64, index // 16 * 64
    return atlas.crop((x, y, x + 64, y + 64))


def main():
    for name in ORIGINALS:
        check((ENEMIES / name).is_file(), f"Original {name} is kept")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-enemy-art-") as temporary:
        out = Path(temporary)
        parts.main(out)
        check(sha(out / "infantry_parts_v2.png") == sha(ENEMIES / "infantry_parts_v2.png"), "Generator reproduces infantry_parts_v2.png")
        check((out / "infantry_parts_v2.source.json").read_bytes() == (ENEMIES / "infantry_parts_v2.source.json").read_bytes(), "Reproducible v2 parts provenance")
        turns.SOURCE = ENEMIES / "infantry_parts_v2.png"
        turns.main(out)
        for name in ("infantry_turns_v2", "infantry_living_turns_v2", "infantry_gun_turns_v2"):
            check(sha(out / f"{name}.png") == sha(ENEMIES / f"{name}.png"), f"RotSprite bake reproduces {name}.png")
            check((out / f"{name}.source.json").read_bytes() == (ENEMIES / f"{name}.source.json").read_bytes(), f"Reproducible {name} provenance")
        weapons.main(out)
        check(sha(out / "machine_weapons_v2.png") == sha(ENEMIES / "machine_weapons_v2.png"), "Generator reproduces machine_weapons_v2.png")
        pods.main(out)
        check(sha(out / "aircraft_pods_v2.png") == sha(ENEMIES / "aircraft_pods_v2.png"), "Generator reproduces aircraft_pods_v2.png")
        # Pass 7A: the world-density bakes reproduce byte for byte.
        infantry_world.main(out)
        for name in ("infantry_parts_world", "infantry_living_turns_world", "infantry_gun_turns_world", "infantry_turns_world", "infantry_limbs_world"):
            check(sha(out / f"{name}.png") == sha(ENEMIES / f"{name}.png"), f"bake_infantry_world reproduces {name}.png")
        check((out / "infantry_limb_index.gd").read_bytes() == (PROJECT / "scripts/infantry_limb_index.gd").read_bytes(), "Limb index reproduces")
        weapons_world.main(out)
        check(sha(out / "machine_weapons_world.png") == sha(ENEMIES / "machine_weapons_world.png"), "Walker cannons reproduce at every drawn scale")
        check((out / "machine_weapon_index.gd").read_bytes() == (PROJECT / "scripts/machine_weapon_index.gd").read_bytes(), "Cannon index reproduces")
        shield_world.main(out)
        check(sha(out / "shield_bubble_world.png") == sha(ENEMIES / "shield_bubble_world.png"), "Shield bubble reproduces")
        hulls.main(out)
        for plate in hulls.PLATES:
            check(sha(out / plate["output"]) == sha(ENEMIES / plate["output"]), f"Grade reproduces {plate['output']}")
            check((out / plate["output"]).with_suffix(".source.json").read_bytes() == (ENEMIES / plate["output"]).with_suffix(".source.json").read_bytes(), f"Reproducible {plate['output']} provenance")

    v1 = Image.open(ENEMIES / "infantry_parts_v1.png").convert("RGBA")
    v2 = Image.open(ENEMIES / "infantry_parts_v2.png").convert("RGBA")
    check(v2.size == v1.size == (1024, 1024), "v2 keeps the 1024 atlas")
    for role_index, role in enumerate(parts.ROLES):
        for index in [role_index * 35 + s * 5 + w for s in range(7) for w in range(5)] + [210 + role_index, 246 + role_index] + [216 + role_index * 5 + w for w in range(5)]:
            if tile(v1, index).getbbox() is not None and index not in range(216, 221):
                check(tile(v2, index).getbbox() is not None, f"{role} keeps tile {index} of the v1 layout")
        gun = np.asarray(tile(v2, 246 + role_index))[..., 3] > 0
        reach = int(np.nonzero(gun[16])[0].max()) - 12
        check(abs(reach - MUZZLES[role]) <= 1, f"{role} weapon reaches its muzzle (x {reach} vs {MUZZLES[role]})")
        # The rig's 7x6 gloves sit at (-1, 5) and (13, 4): weapon under both.
        check(gun[16 + 2:16 + 8, 12 - 4:12 + 3].any() and gun[16 + 2:16 + 7, 12 + 10:12 + 17].any(), f"{role} weapon lies under both gloves")
        head = np.asarray(tile(v2, role_index * 35 + 1))
        check(int((head[..., 3] > 0).sum()) > 250, f"{role} head is a full drawn head")
    # Silhouette identity: every pair of role heads differs by many texels.
    masks = [np.asarray(tile(v2, r * 35 + 1))[..., 3] > 0 for r in range(6)]
    for a, b in combinations(range(6), 2):
        check(int((masks[a] ^ masks[b]).sum()) >= 40, f"Heads of {parts.ROLES[a]} and {parts.ROLES[b]} differ in silhouette")
    # Colour identity: the coats' mean colours are apart.
    coats = [np.asarray(tile(v2, 210 + r)).reshape(-1, 4) for r in range(6)]
    means = [coat[coat[:, 3] > 0][:, :3].mean(axis=0) for coat in coats]
    for a, b in combinations(range(6), 2):
        check(float(np.abs(means[a] - means[b]).sum()) >= 18, f"Coats of {parts.ROLES[a]} and {parts.ROLES[b]} differ in colour")
    # Faces: open-faced roles show eye and skin; masked roles show a lens.
    for role_index, role in enumerate(parts.ROLES):
        colours = {tuple(pixel[:3]) for pixel in np.asarray(tile(v2, role_index * 35 + 1)).reshape(-1, 4) if pixel[3]}
        if role in ("grenadier", "scout"):
            check(parts._rgb(parts.PALETTES[role]["G"]) in colours, f"{role} shows its hostile lens glint")
        else:
            check(parts._rgb(parts.EYES["e"]) in colours, f"{role} has a drawn eye")
    # Graded plates keep every alpha texel of their sources.
    for plate in hulls.PLATES:
        source = np.asarray(Image.open(ENEMIES / plate["source"]).convert("RGBA"))[..., 3]
        graded = np.asarray(Image.open(ENEMIES / plate["output"]).convert("RGBA"))[..., 3]
        check(np.array_equal(graded[:source.shape[0], :source.shape[1]], source), f"{plate['output']} keeps the source alpha")
        notice = json.loads((ENEMIES / plate["output"]).with_suffix(".source.json").read_text())
        for kind, entry in notice["regions"].items():
            x, y, w, h = entry["box"]
            sx, sy, _, _ = plate["regions"][kind][0]
            check(np.array_equal(graded[y:y + h, x:x + w], source[sy:sy + h, sx:sx + w]), f"{kind} region keeps its silhouette")
    sheet = Image.open(ENEMIES / "machine_weapons_v2.png")
    check(sheet.size == (weapons.CELL * len(weapons.STEPS), weapons.CELL * len(weapons.FAMILIES)), "Weapon key sheet layout")
    print(f"ENEMY ART V2: {checks}/{checks} checks passed")


if __name__ == "__main__":
    main()
