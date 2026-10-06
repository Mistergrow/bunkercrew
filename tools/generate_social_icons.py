#!/usr/bin/env python3
"""Original 16 px geometric Bunkercrew social icons; no external source artwork."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

DESTINATION = Path(__file__).resolve().parents[1] / "assets/ui/social"
SHAPES = {
    "crew": [("ellipse", (5, 1, 10, 6)), ("rect", (4, 8, 11, 14)), ("rect", (1, 10, 2, 14)), ("rect", (13, 10, 14, 14))],
    "host": [("line", (1, 7, 7, 2)), ("line", (7, 2, 14, 7)), ("line", (3, 6, 3, 14)), ("line", (12, 6, 12, 14)), ("line", (3, 14, 12, 14)), ("rect", (6, 10, 9, 14))],
    "join": [("line", (9, 2, 14, 2)), ("line", (14, 2, 14, 13)), ("line", (9, 13, 14, 13)), ("line", (1, 7, 11, 7)), ("line", (7, 3, 11, 7)), ("line", (11, 7, 7, 11))],
    "copy": [("outline", (5, 4, 13, 14)), ("line", (2, 1, 10, 1)), ("line", (2, 1, 2, 11)), ("line", (2, 11, 3, 11))],
    "chat": [("outline", (1, 2, 14, 11)), ("line", (4, 11, 4, 14)), ("line", (4, 14, 8, 11)), ("line", (4, 5, 11, 5)), ("line", (4, 8, 9, 8))],
    "friends": [("ellipse", (2, 2, 6, 6)), ("ellipse", (9, 2, 13, 6)), ("rect", (1, 9, 7, 14)), ("rect", (9, 9, 14, 14))],
    "invite": [("outline", (1, 4, 14, 13)), ("line", (1, 4, 7, 9)), ("line", (7, 9, 14, 4)), ("line", (11, 0, 11, 5)), ("line", (8, 2, 14, 2))],
    "mute": [("rect", (1, 6, 4, 10)), ("polygon", [(4, 6), (8, 2), (8, 14), (4, 10)]), ("line", (10, 5, 14, 11)), ("line", (14, 5, 10, 11))],
    "voice": [("rect", (1, 6, 4, 10)), ("polygon", [(4, 6), (8, 2), (8, 14), (4, 10)]), ("line", (11, 5, 12, 6)), ("line", (12, 6, 12, 10)), ("line", (12, 10, 11, 11)), ("line", (14, 3, 14, 13))],
    "block": [("ellipse_outline", (1, 1, 14, 14)), ("line", (3, 12, 12, 3))],
    "add": [("ellipse", (2, 2, 7, 7)), ("rect", (1, 10, 8, 14)), ("line", (10, 6, 15, 6)), ("line", (12, 3, 12, 9))],
    "signal": [("rect", (1, 11, 3, 14)), ("rect", (6, 7, 8, 14)), ("rect", (11, 2, 13, 14))],
    "play": [("polygon", [(4, 2), (13, 8), (4, 14)])],
    "back": [("line", (2, 8, 14, 8)), ("line", (2, 8, 7, 3)), ("line", (2, 8, 7, 13))],
    "location": [("ellipse_outline", (3, 1, 12, 10)), ("line", (4, 8, 8, 15)), ("line", (8, 15, 12, 8)), ("rect", (7, 4, 8, 5))],
    "settings": [("line", (2, 1, 2, 14)), ("line", (7, 1, 7, 14)), ("line", (12, 1, 12, 14)), ("rect", (0, 4, 4, 6)), ("rect", (5, 9, 9, 11)), ("rect", (10, 3, 14, 5))],
}


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name, shapes in SHAPES.items():
        image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        for kind, coordinates in shapes:
            if kind == "rect": draw.rectangle(coordinates, fill="white")
            elif kind == "outline": draw.rectangle(coordinates, outline="white")
            elif kind == "ellipse": draw.ellipse(coordinates, fill="white")
            elif kind == "ellipse_outline": draw.ellipse(coordinates, outline="white")
            elif kind == "polygon": draw.polygon(coordinates, fill="white")
            else: draw.line(coordinates, fill="white", width=1)
        image.save(DESTINATION / (name + ".png"))
    source = {"name": "Bunkercrew social pixel icons", "author": "Bunkercrew project", "provenance": "Original geometric pixel drawings created for Bunkercrew; no third-party artwork, stock assets or generated bitmap references.", "generator": "tools/generate_social_icons.py", "dimensions": [16, 16], "palette": "White glyphs on transparent background; tinted by the existing UI palette.", "license": "Bunkercrew-only distribution; see adjacent LICENSE.txt", "shapes": SHAPES}
    (DESTINATION / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
    (DESTINATION / "LICENSE.txt").write_text("Bunkercrew social pixel icons\n\nOriginal artwork created for the Bunkercrew project.\nPermission is granted to use, modify and distribute these assets only together with Bunkercrew. Standalone redistribution or use in other products is not authorized.\nNo third-party artwork or samples are included.\n")
    print("Created", len(SHAPES), "original 16x16 pixel icons in", DESTINATION)


if __name__ == "__main__": main()
