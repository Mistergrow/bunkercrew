#!/usr/bin/env python3
"""Author the crew's pick and personal weapons in every drawn attitude.

The pick and the personal guns used to be drawn at runtime as lines and
rectangles under a free rotation, so their edges and details fell between the
texels of the actor they belong to. Here each tool is authored as native pixel
geometry and drawn upright for every attitude step:

* the pick, whose geometry matches scripts/mining_worker_pose.gd, is drawn at
  each step from its rotated vector geometry (lines and polygon re-rasterized
  on the texel grid, so the haft stays a clean 1-texel-stepped line);
* each personal weapon of scripts/worker_weapon.gd is drawn level as native
  rectangles, then turned with the RotSprite method shared with the crew pieces
  (generate_character_workers.turned_piece); a variant without its magazine
  serves the reload.

Rebuild with `python3 assets/workers/generate_tool_turns.py` (Pillow
required); it rewrites tool_turns.png and tool_turns.source.json.
"""
from pathlib import Path
from math import cos, sin, pi
import hashlib
import json
from PIL import Image, ImageDraw
import generate_character_workers as author

ROOT = Path(__file__).resolve().parent
PICK_STEPS = 48
PICK_CELL = 112
PICK_CENTRE = (56, 56)
GUN_STEPS = 48
GUN_RANGE = (-13, 10)  # local aim from straight up (reload tilt) to steeply down
GUN_CELL = 88
GUN_CENTRE = (44, 44)
WEAPONS = ("rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun")
FAMILY = {"rifle": "rifle", "veteran_rifle": "rifle", "shotgun": "shotgun", "breacher_shotgun": "shotgun", "arcgun": "arcgun", "storm_arcgun": "arcgun"}
MAGAZINE = ("rifle", "veteran_rifle", "arcgun", "storm_arcgun")
INK = "#151b1e"


def pick(step):
    """The pick at one attitude, head at PICK_CENTRE, haft pointing back."""
    image = Image.new("RGBA", (PICK_CELL, PICK_CELL))
    d = ImageDraw.Draw(image)
    angle = step * 2 * pi / PICK_STEPS
    c, s = cos(angle), sin(angle)

    def p(x, y):
        return (round(PICK_CENTRE[0] + c * x - s * y - 0.5), round(PICK_CENTRE[1] + s * x + c * y - 0.5))

    def line(a, b, color, width=1):
        d.line([p(*a), p(*b)], fill=color, width=width)

    butt, head = (-48.0, 0.0), (0.0, 0.0)
    line(butt, head, "#17211f", 5)
    line(butt, head, "#80694b", 3)
    line((-48, -1), (0, -1), "#b39c70")
    for mark in (0.18, 0.40, 0.68):
        x = -48 + 48 * mark
        line((x, 1), (x + 3, 1), "#594d3c")
    blade = [(-2, -12), (2, -8), (3, -3), (2, 4), (0, 12), (-3, 7), (-3, -4)]
    d.polygon([p(*v) for v in blade], fill="#737d73")
    d.line([p(*v) for v in blade + blade[:1]], fill="#17211f", width=1)
    line((0, -10), (2, -3), "#c1c3a7")
    line((1, 3), (0, 12), "#a7b1a2")
    line((-3, 2), (-3, -2), "#3e4a42", 3)
    return image


def gun(kind, magazine=True):
    """A level weapon as native rectangles, origin (the aim pivot) at (64, 64)."""
    image = Image.new("RGBA", (128, 128))
    d = ImageDraw.Draw(image)

    def rect(x, y, w, h, color):
        d.rectangle((64 + x, 64 + y, 64 + x + w - 1, 64 + y + h - 1), fill=color)

    def hline(x0, x1, y, color):
        rect(x0, y, x1 - x0, 1, color)

    def vline(x, y0, y1, color):
        rect(x, y0, 1, y1 - y0, color)

    family = FAMILY[kind]
    rect(-18, -4, 13, 8, INK)
    rect(-16, -3, 10, 5, "#887653")
    rect(-8, -6, 23, 12, INK)
    rect(-6, -4, 20, 7, "#5d6b64")
    if magazine and kind in MAGAZINE:
        rect(-3, 4, 5, 9, "#242f34")
    rect(5, 4, 7, 7, "#89917b")
    if family == "shotgun":
        for y in (-3, 2): rect(12, y, 23, 3, "#a6ab96")
        rect(12, -5, 12, 10, "#85694b")
    elif family == "arcgun":
        rect(11, -8, 20, 16, "#253340")
        for x in (13, 21, 29): rect(x, -7, 3, 14, "#8f8ade")
        rect(12, -2, 23, 4, "#8bdff1")
    else:
        rect(13, -2, 21, 4, "#a0a997")
        rect(29, -4, 7, 8, "#253239")
        rect(-2, -8, 10, 3, "#8b957f")
    edge, recess, steel = "#a7ad95", "#34413e", "#78877b"
    hline(-6, 12, -4, edge)
    hline(-6, 11, 2, recess)
    rect(-4, -2, 9, 3, "#384944")
    rect(-2, -2, 5, 1, "#8a9682")
    rect(8, -2, 5, 2, "#b3b7a0")
    rect(9, -1, 3, 1, "#566358")
    for x, y in ((-5, 0), (6, -3)): rect(x, y, 1, 1, "#c0b58e")
    for index in range(3):
        d.line([(64 - 15 + index * 3, 64 - 2), (64 - 16 + index * 3, 64 + 1)], fill="#63553d")
    hline(-15, -9, -3, "#b0a17c")
    hline(5, 10, 5, "#b0b49a")
    for index in range(3): hline(6, 9, 6 + index, "#5d6c5c")
    if family == "rifle":
        hline(14, 29, -2, "#c0c4aa")
        hline(14, 29, 1, recess)
        for x in (17, 24): rect(x, -3, 2, 6, steel)
        rect(30, -3, 4, 1, "#8c9480")
        rect(33, -1, 2, 2, "#101f23")
    elif family == "shotgun":
        for y in (-3, 2):
            hline(25, 34, y, "#c1bfa7")
            hline(25, 34, y + 2, recess)
        for x in (14, 17, 20):
            vline(x, -3, 2, "#504733")
            vline(x + 1, -3, 2, "#b69d70")
        rect(24, -4, 2, 9, steel)
    else:
        hline(12, 29, -8, steel)
        for x in (13, 21, 29):
            rect(x, -6, 1, 12, "#b5b4cf")
            rect(x + 2, -6, 1, 12, "#585e86")
            rect(x, -3, 3, 1, "#7c8b89")
            rect(x, 3, 3, 1, "#455557")
        hline(13, 33, -1, "#d3ede0")
        hline(13, 33, 1, "#438e99")
    if kind == "veteran_rifle":
        rect(-1, -12, 17, 4, INK)
        rect(1, -11, 12, 2, "#baa274")
        rect(33, -3, 5, 6, "#716d55")
    elif kind == "breacher_shotgun":
        rect(29, -6, 8, 13, INK)
        rect(30, -5, 6, 3, "#b19468")
        for index in range(3): rect(-5 + index * 5, -5, 2, 5, "#bd8857")
    elif kind == "storm_arcgun":
        for index in range(3):
            rect(12 + index * 7, -9, 4, 3, "#aabe9e")
            rect(12 + index * 7, 7, 4, 3, "#85755a")
    return image


def gun_rows():
    rows = []
    for kind in WEAPONS:
        rows.append((kind, True))
    for kind in MAGAZINE:
        rows.append((kind, False))
    return rows


def main(output=None):
    destination = Path(output) if output is not None else ROOT
    steps = list(range(GUN_RANGE[0], GUN_RANGE[1] + 1))
    rows = gun_rows()
    width = max(PICK_STEPS * PICK_CELL // 2, len(steps) * GUN_CELL)
    sheet = Image.new("RGBA", (width, 2 * PICK_CELL + len(rows) * GUN_CELL))
    for step in range(PICK_STEPS):
        sheet.alpha_composite(pick(step), (step % (PICK_STEPS // 2) * PICK_CELL, step // (PICK_STEPS // 2) * PICK_CELL))
    for row, (kind, magazine) in enumerate(rows):
        prepared = author._Turnable(gun(kind, magazine), (64, 64))
        for column, step in enumerate(steps):
            sheet.alpha_composite(author.turned_piece(prepared, step, GUN_STEPS, GUN_CELL, GUN_CENTRE), (column * GUN_CELL, 2 * PICK_CELL + row * GUN_CELL))
    sheet.save(destination / "tool_turns.png")
    notice = {
        "asset": "tool_turns.png",
        "source": "generate_tool_turns.py",
        "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "turn_source_sha256": hashlib.sha256((ROOT / "generate_character_workers.py").read_bytes()).hexdigest(),
        "method": "Original native pixel geometry of the pick (mining_worker_pose.gd) and personal weapons (worker_weapon.gd); pick re-rasterized per attitude, weapons RotSprite-turned. No imported image.",
        "pick": {"steps": PICK_STEPS, "cell": PICK_CELL, "centre": list(PICK_CENTRE), "rows": 2, "anchor": "head centre; haft along -x (48 texels), tip at +y"},
        "guns": {"steps_per_turn": GUN_STEPS, "range": list(GUN_RANGE), "cell": GUN_CELL, "centre": list(GUN_CENTRE),
                 "rows": [kind + ("" if magazine else ":no_magazine") for kind, magazine in rows], "first_row_y": 2 * PICK_CELL},
        "sha256": hashlib.sha256((destination / "tool_turns.png").read_bytes()).hexdigest(),
        "license": author.LICENSE,
    }
    (destination / "tool_turns.source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"Authored {PICK_STEPS} pick attitudes and {len(rows)}x{len(steps)} weapon attitudes")


if __name__ == "__main__":
    main()
