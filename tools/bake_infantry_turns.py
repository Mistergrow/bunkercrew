#!/usr/bin/env python3
"""Author the turned infantry field-kit parts for the drawn defeat.

A falling soldier used to show its native torso, pack, head and weapon tiles
as rotated quads, so the texels left the pixel grid and the corpse read as a
turned slab. This script turns the baked parts of infantry_parts_v1.png
(tools/bake_infantry_art.gd) into upright tiles at 22.5 degree key attitudes
with the RotSprite method of assets/workers/generate_character_workers.py
(three Scale2x passes, one sample per native texel; quarter turns exact).
No new colour or shape is introduced. Rebuild with
    python3 tools/bake_infantry_turns.py
after the base atlas changes; it rewrites infantry_turns_v1.png and its
.source.json (input and generator hashes). Pillow required.

Layout (rows of cells, left to right):
    per role, in Atlas.ROLES order: torso, rear (still cloth) and the seven
    head variants, each for BODY_STEPS; then the weapon for GUN_STEPS.

The same script bakes infantry_living_turns_v1.png: the standing, marching,
kneeling and firing attitudes of a living soldier, in 7.5 degree keys
(LIVING_STEPS of LIVING_PER_TURN; the upright key is the native tile itself).
Per role: one row of LIVING_BODY_CELL cells (torso, then rear, each for
LIVING_STEPS), then LIVING_HEAD_ROWS rows of LIVING_HEAD_CELL cells (the seven
head variants, each for LIVING_STEPS, LIVING_HEADS_PER_ROW to a row).
"""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "assets/workers"))
import generate_character_workers as author  # noqa: E402

SOURCE = PROJECT / "assets/enemies/infantry_parts_v1.png"
OUTPUT = PROJECT / "assets/enemies/infantry_turns_v1.png"
ROLES = ("rifle_guard", "grenadier", "scout", "heavy_gunner", "marksman", "combat_medic")
STEPS = 16
TILE, COLUMNS = 64, 16
# Upright to flat on the back (falling backwards turns anticlockwise), plus a
# forward slump; the dropped weapon tumbles within two steps of level.
BODY_STEPS = tuple(range(-4, 2))
GUN_STEPS = tuple(range(-2, 3))
BODY_CELL, BODY_CENTRE = 72, (36, 36)
GUN_CELL, GUN_CENTRE = 104, (52, 52)
HEADS = 7
LIVING_OUTPUT = PROJECT / "assets/enemies/infantry_living_turns_v1.png"
LIVING_PER_TURN = 48
LIVING_STEPS = (-2, -1, 1, 2, 3, 4)
LIVING_BODY_CELL, LIVING_BODY_CENTRE = 72, (36, 36)
LIVING_HEAD_CELL, LIVING_HEAD_CENTRE = 48, (24, 24)
LIVING_HEADS_PER_ROW = 21
LIVING_HEAD_ROWS = 2


def tile_index(part, role, slot=0):
    if part == "head": return role * 35 + slot * 5 + 1
    if part == "torso": return 210 + role
    if part == "rear": return 216 + role * 5 + 1
    return 246 + role


def tile(atlas, index):
    x, y = index % COLUMNS * TILE, index // COLUMNS * TILE
    return atlas.crop((x, y, x + TILE, y + TILE))


def layout():
    """[(part, role, slot, step, x, y, size)] in the order described above."""
    cells, x, y = [], 0, 0
    width = len(BODY_STEPS) * 9 * BODY_CELL
    for role in range(len(ROLES)):
        for part, slot in [("torso", 0), ("rear", 0)] + [("head", s) for s in range(HEADS)]:
            for step in BODY_STEPS:
                cells.append((part, role, slot, step, x, y, BODY_CELL))
                x += BODY_CELL
        x, y = 0, y + BODY_CELL
    for role in range(len(ROLES)):
        for step in GUN_STEPS:
            cells.append(("gun", role, 0, step, x, y, GUN_CELL))
            x += GUN_CELL
            if x + GUN_CELL > width: x, y = 0, y + GUN_CELL
    return cells, (width, y + (GUN_CELL if x else 0))


def living_layout():
    """[(part, role, slot, step, x, y, size)] for the living attitudes."""
    cells = []
    band = LIVING_BODY_CELL + LIVING_HEAD_ROWS * LIVING_HEAD_CELL
    for role in range(len(ROLES)):
        top = role * band
        for column, part in enumerate(("torso", "rear")):
            for index, step in enumerate(LIVING_STEPS):
                cells.append((part, role, 0, step, (column * len(LIVING_STEPS) + index) * LIVING_BODY_CELL, top, LIVING_BODY_CELL))
        for slot in range(HEADS):
            for index, step in enumerate(LIVING_STEPS):
                at = slot * len(LIVING_STEPS) + index
                cells.append(("head", role, slot, step, at % LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL,
                              top + LIVING_BODY_CELL + at // LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL, LIVING_HEAD_CELL))
    width = max(LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL, 2 * len(LIVING_STEPS) * LIVING_BODY_CELL)
    return cells, (width, len(ROLES) * band)


def bake_living(atlas, target):
    cells, size = living_layout()
    sheet = Image.new("RGBA", size)
    prepared = {}
    for part, role, slot, step, x, y, cell in cells:
        key = (part, role, slot)
        if key not in prepared:
            prepared[key] = author._Turnable(tile(atlas, tile_index(part, role, slot)), (32, 32))
        centre = LIVING_HEAD_CENTRE if part == "head" else LIVING_BODY_CENTRE
        sheet.alpha_composite(author.turned_piece(prepared[key], step, LIVING_PER_TURN, cell, centre), (x, y))
    sheet.save(target)
    notice = {
        "asset": LIVING_OUTPUT.name,
        "generator": "tools/bake_infantry_turns.py",
        "method": "RotSprite turns (3x Scale2x, one sample per native texel) of the baked native field-kit parts for the living soldier's attitudes. No new art design.",
        "license": "Same as the original project art; see original asset source metadata.",
        "steps_per_turn": LIVING_PER_TURN, "steps": list(LIVING_STEPS),
        "body_cell": LIVING_BODY_CELL, "body_centre": list(LIVING_BODY_CENTRE),
        "head_cell": LIVING_HEAD_CELL, "head_centre": list(LIVING_HEAD_CENTRE),
        "heads_per_row": LIVING_HEADS_PER_ROW, "head_rows": LIVING_HEAD_ROWS,
        "heads": HEADS, "roles": list(ROLES), "size": list(size),
        "source_sha256": {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in
                          ("assets/enemies/infantry_parts_v1.png", "tools/bake_infantry_turns.py", "assets/workers/generate_character_workers.py")},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"BAKED LIVING INFANTRY TURNS: {size} {len(cells)} cells")


def main(output=None):
    target = Path(output) / OUTPUT.name if output is not None else OUTPUT
    atlas = Image.open(SOURCE).convert("RGBA")
    cells, size = layout()
    sheet = Image.new("RGBA", size)
    prepared = {}
    for part, role, slot, step, x, y, cell in cells:
        key = (part, role, slot)
        if key not in prepared:
            origin = (12, 16) if part == "gun" else (32, 32)
            prepared[key] = author._Turnable(tile(atlas, tile_index(part, role, slot)), origin)
        centre = GUN_CENTRE if part == "gun" else BODY_CENTRE
        sheet.alpha_composite(author.turned_piece(prepared[key], step, STEPS, cell, centre), (x, y))
    sheet.save(target)
    notice = {
        "asset": OUTPUT.name,
        "generator": "tools/bake_infantry_turns.py",
        "method": "RotSprite turns (3x Scale2x, one sample per native texel; quarter turns exact) of the baked native field-kit parts. No new art design.",
        "license": "Same as the original project art; see original asset source metadata.",
        "steps_per_turn": STEPS, "body_steps": list(BODY_STEPS), "gun_steps": list(GUN_STEPS),
        "body_cell": BODY_CELL, "body_centre": list(BODY_CENTRE), "gun_cell": GUN_CELL, "gun_centre": list(GUN_CENTRE),
        "heads": HEADS, "roles": list(ROLES), "size": list(size),
        "source_sha256": {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in
                          ("assets/enemies/infantry_parts_v1.png", "tools/bake_infantry_turns.py", "assets/workers/generate_character_workers.py")},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"BAKED INFANTRY TURNS: {size} {len(cells)} cells")
    bake_living(atlas, Path(output) / LIVING_OUTPUT.name if output is not None else LIVING_OUTPUT)


if __name__ == "__main__":
    main()
