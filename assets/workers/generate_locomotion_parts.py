#!/usr/bin/env python3
"""Author clean back-view rig pieces from the game's original pixel geometry.

Only the twelve back-view pieces and their provenance are written. No existing
image is read, transformed or overwritten. Runtime limbs follow real rungs.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw
import generate_recruits as recruits

ROOT = Path(__file__).resolve().parent
author = recruits.author
rig = author.rig


def main():
    for identity in ("mara", "branko", "ivo", "nora", "levin", "selma"):
        profile = author.PROFILES[identity]
        rig.C = dict(author.BASE_PALETTE, **profile["palette"])
        for part in ("torso", "head"):
            image = Image.new("RGBA", (rig.CELL, rig.CELL))
            draw = ImageDraw.Draw(image)
            if part == "torso":
                recruits.torso(draw, (0, -42), (0, -25), identity, back=True)
            else:
                recruits.head(draw, 1, -57, identity, back=True)
            image.save(ROOT / f"{identity}_back_{part}.png")
    (ROOT / "locomotion_parts.source.json").write_text(json.dumps({
        "source": "generate_locomotion_parts.py",
        "rig": ["generate_recruits.py", "generate_character_workers.py", "generate_workers.py"],
        "method": "Original source-authored pixel geometry; no imported image edits",
        "purpose": "Clean back-view heads and coats for continuous articulated ladder motion",
        "cell": 112,
        "identities": ["mara", "branko", "ivo", "nora", "levin", "selma"],
        "assets": [f"{identity}_back_{part}.png" for identity in
                   ("mara", "branko", "ivo", "nora", "levin", "selma")
                   for part in ("torso", "head")],
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
