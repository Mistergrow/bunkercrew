#!/usr/bin/env python3
"""Turn the hand-pixelled infantry_parts_v2.png into its key attitudes.

Same RotSprite method and layouts as tools/bake_infantry_turns.py (which keeps
baking the v1 sheets from infantry_parts_v1.png for comparison):

    infantry_turns_v2.png         drawn defeat, 22.5 degree keys
    infantry_living_turns_v2.png  living soldier, 7.5 degree keys
    infantry_gun_turns_v2.png     living soldier's weapon, 7.5 degree keys
                                  (GUN_STEPS_LIVING, one row per role), so an
                                  aiming weapon is no longer a rigidly turned tile

Rebuild after tools/generate_infantry_parts_v2.py with
    python3 tools/bake_infantry_turns_v2.py
Pillow required.
"""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))
import bake_infantry_turns as base  # noqa: E402

SOURCE = PROJECT / "assets/enemies/infantry_parts_v2.png"
OUTPUT = PROJECT / "assets/enemies/infantry_turns_v2.png"
LIVING_OUTPUT = PROJECT / "assets/enemies/infantry_living_turns_v2.png"
GUN_OUTPUT = PROJECT / "assets/enemies/infantry_gun_turns_v2.png"
# Aim clamp (-0.9 .. 0.65 rad) plus rest drop, recoil, flinch, reload and the
# medic's dressing angle stay within +-75 degrees.
GUN_STEPS_LIVING = tuple(range(-10, 11))
INPUTS = ("assets/enemies/infantry_parts_v2.png", "tools/bake_infantry_turns_v2.py", "tools/bake_infantry_turns.py",
          "assets/workers/generate_character_workers.py")


def _sheet(atlas, cells, size, origins, centres, steps):
    sheet = Image.new("RGBA", size)
    prepared = {}
    for part, role, slot, step, x, y, cell in cells:
        key = (part, role, slot)
        if key not in prepared:
            prepared[key] = base.author._Turnable(base.tile(atlas, base.tile_index(part, role, slot)), origins(part))
        sheet.alpha_composite(base.author.turned_piece(prepared[key], step, steps, cell, centres(part)), (x, y))
    return sheet


def _notice(target, extra):
    notice = {
        "asset": target.name,
        "generator": "tools/bake_infantry_turns_v2.py",
        "method": "RotSprite turns (3x Scale2x, one sample per native texel; quarter turns exact) of the hand-pixelled v2 field-kit parts. No new colour or shape.",
        "license": "Original Bunkercrew project art.",
    }
    notice.update(extra)
    notice["source_sha256"] = {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in INPUTS}
    notice["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")


def main(output=None):
    atlas = Image.open(SOURCE).convert("RGBA")
    target = Path(output) / OUTPUT.name if output is not None else OUTPUT
    cells, size = base.layout()
    _sheet(atlas, cells, size, lambda part: (12, 16) if part == "gun" else (32, 32),
           lambda part: base.GUN_CENTRE if part == "gun" else base.BODY_CENTRE, base.STEPS).save(target)
    _notice(target, {"steps_per_turn": base.STEPS, "body_steps": list(base.BODY_STEPS), "gun_steps": list(base.GUN_STEPS),
                     "body_cell": base.BODY_CELL, "body_centre": list(base.BODY_CENTRE), "gun_cell": base.GUN_CELL,
                     "gun_centre": list(base.GUN_CENTRE), "heads": base.HEADS, "roles": list(base.ROLES), "size": list(size)})
    print(f"BAKED INFANTRY TURNS V2: {size} {len(cells)} cells")
    living = Path(output) / LIVING_OUTPUT.name if output is not None else LIVING_OUTPUT
    cells, size = base.living_layout()
    _sheet(atlas, cells, size, lambda part: (32, 32),
           lambda part: base.LIVING_HEAD_CENTRE if part == "head" else base.LIVING_BODY_CENTRE, base.LIVING_PER_TURN).save(living)
    _notice(living, {"steps_per_turn": base.LIVING_PER_TURN, "steps": list(base.LIVING_STEPS),
                     "body_cell": base.LIVING_BODY_CELL, "body_centre": list(base.LIVING_BODY_CENTRE),
                     "head_cell": base.LIVING_HEAD_CELL, "head_centre": list(base.LIVING_HEAD_CENTRE),
                     "heads_per_row": base.LIVING_HEADS_PER_ROW, "head_rows": base.LIVING_HEAD_ROWS,
                     "heads": base.HEADS, "roles": list(base.ROLES), "size": list(size)})
    print(f"BAKED LIVING INFANTRY TURNS V2: {size} {len(cells)} cells")
    guns = Path(output) / GUN_OUTPUT.name if output is not None else GUN_OUTPUT
    cells = [("gun", role, 0, step, column * base.GUN_CELL, role * base.GUN_CELL, base.GUN_CELL)
             for role in range(len(base.ROLES)) for column, step in enumerate(GUN_STEPS_LIVING)]
    size = (len(GUN_STEPS_LIVING) * base.GUN_CELL, len(base.ROLES) * base.GUN_CELL)
    _sheet(atlas, cells, size, lambda part: (12, 16), lambda part: base.GUN_CENTRE, base.LIVING_PER_TURN).save(guns)
    _notice(guns, {"steps_per_turn": base.LIVING_PER_TURN, "steps": list(GUN_STEPS_LIVING), "cell": base.GUN_CELL,
                   "centre": list(base.GUN_CENTRE), "roles": list(base.ROLES), "size": list(size)})
    print(f"BAKED LIVING INFANTRY WEAPON TURNS V2: {size} {len(cells)} cells")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
