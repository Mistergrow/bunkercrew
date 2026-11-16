#!/usr/bin/env python3
"""Author the aircraft weapon pods and the bomber bay (review 5, D25/D47/D26).

The pods were flat striped rectangles turned as rigid sprites (jagged,
shimmering edges) and the bomb bay a flat dark rectangle. This script places
every texel of five pod families and the bay by hand at their drawn world size
(the aircraft draw at 0.85, so 24 local units are 20 texels) and turns each pod
into a full circle of aim keys with the RotSprite method of the crew turns:

    dart    scout drone          slim sensor gun with a needle barrel
    gun     tracer flavours      cylindrical gun pod: nose cone, panel seam,
                                 brass band, short barrel with a bored muzzle
    rocket  rocket flavours      three-tube launcher with rust bands and dark
                                 tube mouths, warheads visible inside
    arc     pulse / shield       copper coil pod with a cold emitter lens
    heavy   sky fortress,        four-tube heavy launcher, armoured cheek
            heavy zeppelin

Every pod keeps its ball mount at the pivot (local (3, 0)), the mouth near
local x -24 (AirMachine.muzzle_global) and light from the upper left.
The bay (one upright sprite, the bay never turns) is a recessed frame with
ribs, two riveted door panels with lit edges and hinge pins.

Layout: rows = POD_FAMILIES, KEYS columns of CELL texels, 7.5 degrees apart
(48 per turn), muzzle pointing left at key 0; the bay sits in an extra row,
key 0 column. Drawn by scripts/aircraft_art.gd (AircraftArt._pod, body bay).
Rebuild with  python3 tools/generate_aircraft_pods_v2.py  (Pillow).
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

OUTPUT = PROJECT / "assets/enemies/aircraft_pods_v2.png"
POD_FAMILIES = ("dart", "gun", "rocket", "arc", "heavy")
KEYS = 48
CELL = 48
PIVOT = (30, 24)     # ball mount inside the authoring tile
CENTRE = (24, 24)    # ball mount inside each baked cell
PALETTE = dict(parts.GUN)
PALETTE.update({
    "K": parts.INK, "o": "2f372f", "O": "47513f", "P": "687258", "p": "8a9088",
    "n": "7a4228", "N": "a35a34", "r": "8c3628", "R": "c65b47", "Q": "f08a5c",
    "c": "5a6cb0", "C": "8fd8f0", "W": "f2fffd",
})


def _mount(c):
    # Ball mount at the pivot: lit upper left, dark pin.
    c.rows([
        ".2332.",
        "234432",
        "345543",
        "343143",
        "233332",
        ".2222.",
    ], -1, 3)


def dart(c):
    c.bar(-14, -1, 1, 1, "4", "3", "2")
    c.rows(["..33", ".344", "3332", ".222"], 17, 2)
    c.bar(-20, 0, -17, 0, "4", "4", "2")
    c.put(-21, 0, "1")
    c.put(-6, -1, "5")
    c.put(-6, 0, "R")
    _mount(c)


def gun(c):
    c.bar(-15, -2, 1, 2, "5", "3", "2")
    c.rect(-15, -1, 1, -1, "4")
    c.rows([".333", "3444", "3333", "3222", ".222"], 18, 2)
    c.rect(-8, -2, -8, 2, "2")
    c.rect(-4, -2, -3, 2, "Y")
    c.put(-4, -2, "Z")
    c.bar(-21, -1, -19, 0, "4", "4", "2")
    c.rect(-22, -1, -22, 0, "4")
    c.put(-22, 0, "1")
    c.put(-12, 1, "R")
    _mount(c)


def rocket(c):
    c.bar(-17, -3, 1, 3, "5", "3", "2", left="4")
    c.rect(-16, -2, 0, -2, "4")
    for x in (-14, -9, -4):
        c.rect(x, -3, x, 3, "n")
        c.put(x, -3, "N")
    # Tube mouths with warheads inside.
    for y in (-2, 0, 2):
        c.put(-18, y, "1")
        c.put(-19, y, "4" if y < 2 else "3")
        c.put(-17, y, "R" if y == 0 else "r")
    c.rect(-19, -3, -19, 3, "3")
    _mount(c)


def arc(c):
    c.bar(-16, -2, 1, 2, "5", "3", "2")
    for x in range(-14, 0, 3):
        c.rect(x, -3, x, 3, "Y")
        c.put(x, -3, "Z")
        c.put(x, 3, "y")
    c.rows([".cc", "cCC", "CWC", "cCC", ".cc"], 20, 2)
    c.rect(-17, -2, -17, 2, "2")
    _mount(c)


def heavy(c):
    c.bar(-18, -4, 2, 4, "5", "3", "2", left="4")
    c.rect(-17, -3, 1, -3, "4")
    c.bar(-8, -5, 2, -3, "p", "P", "O")
    for x in (-15, -10, -5):
        c.rect(x, -2, x, 4, "n")
        c.put(x, -2, "N")
    for y in (-2, 2):
        for x in (-19, -20):
            c.put(x, y, "1" if x == -19 else "4")
            c.put(x, y + 1, "1" if x == -19 else "3")
        c.put(-18, y, "R")
    c.rect(-20, -4, -20, 4, "3")
    _mount(c)


def bay(c):
    # Recessed bomb bay (17 x 5 texels) with ribs, riveted doors, hinge pins.
    c.rows([
        "K44444444444444444K",
        "4211112111121111124",
        "4p2PPPPPP2PPPPPP2p4",
        "4P2OOOOOO2OOOOOO2P4",
        "4O2o5ooo52o5ooo52O4",
        "K22222222222222222K",
    ], 9, 2)


def piece(family):
    canvas = parts.Canvas()
    getattr(sys.modules[__name__], family)(canvas)
    image = Image.new("RGBA", (CELL + 12, CELL))
    pixels = image.load()
    for (x, y), char in canvas.cells.items():
        u, v = PIVOT[0] + x, PIVOT[1] + y
        if char in PALETTE and 0 <= u < image.width and 0 <= v < image.height:
            pixels[u, v] = parts._rgb(PALETTE[char]) + (255,)
    return parts._ink(image)


def main(output=None):
    target = Path(output) / OUTPUT.name if output is not None else OUTPUT
    sheet = Image.new("RGBA", (CELL * KEYS, CELL * (len(POD_FAMILIES) + 1)))
    for row, family in enumerate(POD_FAMILIES):
        turnable = author._Turnable(piece(family), PIVOT)
        for step in range(KEYS):
            sheet.alpha_composite(author.turned_piece(turnable, step, KEYS, CELL, CENTRE), (step * CELL, row * CELL))
    bay_image = piece("bay")
    sheet.alpha_composite(bay_image.crop((PIVOT[0] - CENTRE[0], 0, PIVOT[0] - CENTRE[0] + CELL, CELL)), (0, len(POD_FAMILIES) * CELL))
    sheet.save(target)
    notice = {
        "asset": OUTPUT.name,
        "generator": "tools/generate_aircraft_pods_v2.py",
        "method": "Hand-placed native pixel art for five aircraft pod families and the bomb bay at world size (one texel per world unit), pods RotSprite-turned (3x Scale2x, one sample per native texel) into 48 aim keys. Replaces the striped rectangles and the flat bay of scripts/aircraft_art.gd.",
        "license": "Original Bunkercrew project art.",
        "families": list(POD_FAMILIES), "keys": KEYS, "cell": CELL, "centre": list(CENTRE),
        "bay": {"row": len(POD_FAMILIES), "column": 0},
        "size": list(sheet.size),
        "source_sha256": {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in
                          ("tools/generate_aircraft_pods_v2.py", "tools/generate_infantry_parts_v2.py", "assets/workers/generate_character_workers.py")},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"AUTHORED AIRCRAFT PODS V2: {sheet.size} {len(POD_FAMILIES) * KEYS} keys + bay")


def preview(path, scale=8):
    out = Image.new("RGBA", ((CELL + 12) * (len(POD_FAMILIES) + 1), CELL), (88, 104, 124, 255))
    for index, family in enumerate(POD_FAMILIES + ("bay",)):
        out.alpha_composite(piece(family), (index * (CELL + 12), 0))
    out.resize((out.width * scale, out.height * scale), Image.NEAREST).save(path)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else None)
