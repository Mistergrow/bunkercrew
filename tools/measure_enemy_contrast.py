#!/usr/bin/env python3
"""Measure enemy-vs-backdrop value contrast in rendered review shots.

Style bible section 4: enemies keep a value distance of at least 15 % to the
backdrop directly behind them. For each enemy box this splits the pixels into
warm actor texels (red channel above blue) and cool backdrop texels (the
painted night and snow backdrops are blue-dominant), then reports the median
luma of both, their distance, and the share of actor texels whose own luma is
at least 0.15 away from the backdrop median (how much of the silhouette reads).

    python3 tools/measure_enemy_contrast.py SHOT.png x0,y0,x1,y1 [...]
    python3 tools/measure_enemy_contrast.py --json SHOT.png x0,y0,x1,y1
"""
import json
import sys
from statistics import median
from PIL import Image


def luma(pixel):
    r, g, b = (channel / 255.0 for channel in pixel[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def measure(image, box, pad=24):
    x0, y0, x1, y1 = box
    actor, backdrop = [], []
    source = image.convert("RGB")
    for y in range(max(0, y0 - pad), min(source.height, y1 + pad)):
        for x in range(max(0, x0 - pad), min(source.width, x1 + pad)):
            pixel = source.getpixel((x, y))
            inside = x0 <= x < x1 and y0 <= y < y1
            if pixel[0] > pixel[2] + 6 and inside:
                actor.append(luma(pixel))
            elif pixel[2] >= pixel[0]:
                backdrop.append(luma(pixel))
    if not actor or not backdrop:
        return None
    back = median(backdrop)
    act = median(actor)
    reads = sum(1 for value in actor if abs(value - back) >= 0.15) / len(actor)
    return {"actor_luma": round(act, 3), "backdrop_luma": round(back, 3), "distance": round(abs(act - back), 3),
            "reading_share": round(reads, 3), "actor_texels": len(actor)}


def main(argv):
    as_json = argv and argv[0] == "--json"
    if as_json:
        argv = argv[1:]
    image = Image.open(argv[0])
    results = {}
    for spec in argv[1:]:
        box = tuple(int(value) for value in spec.split(","))
        results[spec] = measure(image, box)
    if as_json:
        print(json.dumps(results, indent=2))
    else:
        for spec, result in results.items():
            print(spec, result)


if __name__ == "__main__":
    main(sys.argv[1:])
