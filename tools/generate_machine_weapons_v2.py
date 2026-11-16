#!/usr/bin/env python3
"""Author the walker cannons as pixel art with baked aim keys (review 5, D29).

The walkers' weapons were flat procedural slabs (rectangles with stripes),
drawn at 0.78 of their local size and turned as a rigid sprite. This script
places every texel of five weapon families by hand, at the size they are
drawn in the world (one texel per world unit), and turns each into its aim
attitudes with the RotSprite method of the crew turns:

    light     runner, strider      receiver with vents, cooled barrel, brake
    heavy     breaker              + armoured shroud and an under-barrel tube
    colossus  colossus             heavy with a brass-ringed blast shroud
    assault   assault              three-barrel rotary cluster with clamps
    siege     siege                long cannon with recoil cylinders, ribs and
                                   a ported muzzle brake

Light from the upper left: lit top edges, a cylindrical highlight and shadow
on every tube, a dark bore with a lit rim at each muzzle, brass at breeches,
a red sensor as the hostile accent. The pivot is the weapon node origin and
the muzzle stays where SiegeMachine.weapon_muzzle() puts it (x 0.78).

Layout: one row per family (FAMILIES order), STEPS keys of CELL texels,
7.5 degrees apart (48 per turn), muzzle pointing left (-x) at step 0.
Rebuild with  python3 tools/generate_machine_weapons_v2.py  (Pillow).
"""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))
sys.path.insert(0, str(PROJECT / "assets/workers"))
import generate_infantry_parts_v2 as parts  # noqa: E402
import generate_character_workers as author  # noqa: E402

OUTPUT = PROJECT / "assets/enemies/machine_weapons_v2.png"
FAMILIES = ("light", "heavy", "colossus", "assault", "siege")
PER_TURN = 48
# Aim stops of SiegeMachine (-1.12 .. 0.38 rad) in 7.5 degree keys.
STEPS = tuple(range(-9, 4))
CELL = 96
PIVOT = (60, 48)       # pivot inside the authoring tile
CENTRE = (48, 48)      # pivot inside each baked cell
PALETTE = {
    "K": "1b211f", "1": "1c2023", "2": "2c3134", "3": "454b4f", "4": "6d7377", "5": "a3a9a8",
    "o": "2f372f", "O": "47513f", "P": "687258", "p": "8a9088",
    "y": "8a6a32", "Y": "c79a52", "Z": "e8c47a", "n": "7a4228",
    "r": "8c3628", "R": "c65b47", "Q": "f08a5c",
}


def _tube(c, x0, x1, y0, y1):
    """A round barrel: lit top line, body, shadow underside."""
    c.rect(x0, y0, x1, y1, "3")
    c.rect(x0, y0, x1, y0, "4")
    if y1 - y0 >= 3:
        c.rect(x0, y0 + 1, x1, y0 + 1, "5" if y1 - y0 >= 5 else "4")
    c.rect(x0, y1, x1, y1, "2")
    if y1 - y0 >= 4:
        c.rect(x0, y1 - 1, x1, y1 - 1, "2")


def _bore(c, x, y0, y1):
    """Muzzle face: dark bore with a lit rim."""
    c.rect(x, y0, x, y1, "4")
    c.rect(x, y0 + 1, x, y1 - 1, "1")


def _receiver(c):
    # Gunmetal housing around the pivot: lit top plate, darker belly panel,
    # an olive armour cheek and a brass feed; same metal as the barrel.
    c.bar(-12, -6, 7, 7, "4", "3", "2", left="4", right="2")
    c.rect(-11, -5, 6, -5, "5")
    c.rect(-12, 2, 7, 2, "2")
    c.rect(-11, 3, 6, 6, "2")
    c.bar(-8, -4, 2, 1, "P", "O", "o", right="o")
    for x in (-6, -3):
        c.rect(x, -2, x + 1, 0, "1")
    c.rect(3, -4, 6, -3, "Y")
    c.put(3, -4, "Z")
    for x, y in ((-11, -4), (6, 5)):
        c.put(x, y, "5")
    c.rect(-10, 4, -9, 5, "R")
    c.put(-10, 4, "Q")
    c.rect(-2, 8, 3, 9, "2")
    c.rect(-2, 8, 3, 8, "3")
    # Brass breech collar where the barrel leaves the housing.
    c.rect(-14, -5, -13, 5, "Y")
    c.rect(-14, -5, -13, -5, "Z")
    c.rect(-14, 5, -13, 5, "y")


def _jacket(c, x0, x1, y0, y1):
    """Cooling jacket: round tube with staggered vent holes."""
    _tube(c, x0, x1, y0, y1)
    for index, x in enumerate(range(x0 + 1, x1, 3)):
        c.put(x, y0 + 2 + index % 2 * 2, "1")


def light(c):
    _receiver(c)
    _jacket(c, -25, -15, -3, 3)
    c.bar(-29, -4, -26, 4, "4", "3", "2")
    c.put(-28, -2, "1")
    c.put(-28, 2, "1")
    _bore(c, -30, -3, 3)


def heavy(c):
    light(c)
    c.bar(-20, -9, -2, -7, "p", "P", "O")
    c.line((-20, -7), (-23, -4), "O")
    _tube(c, -25, -15, 6, 8)
    _bore(c, -26, 6, 8)
    c.rect(-16, 5, -15, 9, "Y")


def colossus(c):
    heavy(c)
    c.rows([
        "..yYYYYYYy..",
        ".y44444444Y.",
        "y4555555554Y",
        "y3333333333Y",
        "y3333333333Y",
        "y3332RQ2333Y",
        "y3333333333Y",
        "y2222222222Y",
        ".y22222222y.",
        "..yyyyyyyy..",
    ], 34, 5)
    _bore(c, -35, -3, 3)


def assault(c):
    _receiver(c)
    c.bar(-17, -8, -13, 8, "P", "O", "o", left="p")
    for y in (-6, -1, 4):
        _tube(c, -33, -18, y, y + 2)
        _bore(c, -34, y, y + 2)
    for x in (-30, -24):
        c.rect(x, -7, x + 2, 7, "2")
        c.rect(x, -7, x + 2, -7, "4")
        c.put(x + 1, -6, "Y")


def siege(c):
    _receiver(c)
    c.bar(-19, -9, -12, 9, "P", "O", "o", left="p", right="o")
    _tube(c, -36, -20, -4, 4)
    for x in range(-34, -22, 4):
        c.rect(x, -5, x + 1, 5, "2")
        c.rect(x, -5, x + 1, -5, "4")
    _tube(c, -30, -20, 6, 8)
    _tube(c, -30, -20, -8, -6)
    c.rect(-31, -8, -31, 8, "2")
    c.rows([
        "44444",
        "45554",
        "33333",
        "31313",
        "33333",
        "31313",
        "33333",
        "32222",
        "22222",
        "21212",
        "22222",
    ], 41, 5)
    _bore(c, -42, -4, 4)


def piece(family):
    canvas = parts.Canvas()
    getattr(sys.modules[__name__], family)(canvas)
    image = Image.new("RGBA", (CELL, CELL))
    pixels = image.load()
    for (x, y), char in canvas.cells.items():
        u, v = PIVOT[0] + x, PIVOT[1] + y
        if char in PALETTE and 0 <= u < CELL and 0 <= v < CELL:
            pixels[u, v] = parts._rgb(PALETTE[char]) + (255,)
    return parts._ink(image)


def main(output=None):
    target = Path(output) / OUTPUT.name if output is not None else OUTPUT
    sheet = Image.new("RGBA", (CELL * len(STEPS), CELL * len(FAMILIES)))
    for row, family in enumerate(FAMILIES):
        turnable = author._Turnable(piece(family), PIVOT)
        for column, step in enumerate(STEPS):
            sheet.alpha_composite(author.turned_piece(turnable, step, PER_TURN, CELL, CENTRE), (column * CELL, row * CELL))
    sheet.save(target)
    notice = {
        "asset": OUTPUT.name,
        "generator": "tools/generate_machine_weapons_v2.py",
        "method": "Hand-placed native pixel art for five walker weapon families at world size (one texel per world unit), RotSprite-turned (3x Scale2x, one sample per native texel) into aim keys. Replaces the procedural slabs of SiegeMachine._draw_weapon.",
        "license": "Original Bunkercrew project art.",
        "families": list(FAMILIES), "steps": list(STEPS), "steps_per_turn": PER_TURN,
        "cell": CELL, "centre": list(CENTRE), "size": list(sheet.size),
        "source_sha256": {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in
                          ("tools/generate_machine_weapons_v2.py", "tools/generate_infantry_parts_v2.py", "assets/workers/generate_character_workers.py")},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"AUTHORED MACHINE WEAPONS V2: {sheet.size} {len(FAMILIES) * len(STEPS)} keys")


def preview(path, scale=6):
    out = Image.new("RGBA", (CELL * len(FAMILIES), CELL), (88, 104, 124, 255))
    for index, family in enumerate(FAMILIES):
        out.alpha_composite(piece(family), (index * CELL, 0))
    out.resize((out.width * scale, out.height * scale), Image.NEAREST).save(path)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else None)
