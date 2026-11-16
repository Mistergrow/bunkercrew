#!/usr/bin/env python3
"""Author the shield airship's energy bubble at world density (style bible §1, §4).

The bubble was a stepped ellipse of translucent rows drawn every frame: a
thin rim and faint bands that read as a vector outline. This tool draws it as
pixel art, one texel per world unit, in the cold/energy ramp of the style
bible (#f2fffd #c4f4ff #8fd8f0 #6f9fd8 #5a6cb0):

* a 2-texel rim, bright on the crown, clear on the flanks, dim on the keel,
* inner bands in ordered (4x4 Bayer) dither that thin out towards the
  middle, so the hull inside stays clear,
* a crown highlight crescent on the upper left, where the light comes from.

ThreatOverlay.draw_shield draws it 1:1 on whole world texels and animates a
crest, travelling sparks and the hit flash on top. Rebuild with
    python3 tools/bake_shield_world.py [OUTPUT_DIR]
"""
from pathlib import Path
import hashlib
import json
import math
import sys

from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "assets/enemies/shield_bubble_world.png"
# ThreatOverlay.draw_shield: radii in world units; the texture's centre texel
# corner is (RX + 1, RY + 1).
RX, RY = 88, 46
RAMP = {"white": (0xf2, 0xff, 0xfd), "ice": (0xc4, 0xf4, 0xff), "sky": (0x8f, 0xd8, 0xf0), "blue": (0x6f, 0x9f, 0xd8), "deep": (0x5a, 0x6c, 0xb0)}
BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
# Inner bands: depth from the rim where they end (texels), dither share,
# colour, alpha.
BANDS = ((5.0, 0.50, "sky", 150), (9.0, 0.25, "blue", 130), (14.0, 0.0625, "sky", 110))


def inset(x, y):
    """Approximate distance in texels from the ellipse rim, inward positive."""
    nx, ny = x / RX, y / RY
    r = math.hypot(nx, ny)
    if r == 0.0:
        return float(RY)
    gradient = math.hypot(x / RX ** 2, y / RY ** 2) / r
    return (1.0 - r) / gradient


def texel(x, y):
    d = inset(x, y)
    if d < 0.0:
        return None
    height = (y + RY) / (2.0 * RY)
    if d < 2.0:
        outer = d < 1.0
        if height < 0.30:
            return RAMP["ice" if outer else "white"] + (240 if outer else 225,)
        if height > 0.76:
            return RAMP["deep" if outer else "blue"] + (185 if outer else 140,)
        return RAMP["blue" if outer else "sky"] + (230 if outer else 200,)
    angle = math.degrees(math.atan2(y, x)) % 360.0
    if d < 4.0 and 196.0 <= angle <= 252.0:
        return RAMP["white"] + (215,)
    for depth, share, colour, alpha in BANDS:
        if d < depth:
            threshold = BAYER[int(y) % 4][int(x) % 4] / 16.0
            if threshold < share:
                tone = RAMP["deep" if height > 0.76 else colour]
                return tone + (alpha if height <= 0.76 else alpha - 40,)
            return None
    return None


def main(output=None):
    target = Path(output) / OUTPUT.name if output else OUTPUT
    image = Image.new("RGBA", (RX * 2 + 2, RY * 2 + 2))
    for row in range(-RY, RY):
        for column in range(-RX, RX):
            value = texel(column + 0.5, row + 0.5)
            if value is not None:
                image.putpixel((column + RX + 1, row + RY + 1), value)
    image.save(target)
    notice = {
        "asset": target.name,
        "generator": "tools/bake_shield_world.py",
        "method": "Authored at world density: 2-texel rim, 4x4 Bayer-dithered inner bands, crown highlight, energy ramp of the style bible.",
        "license": "Original Bunkercrew project art.",
        "radii": [RX, RY], "centre": [RX + 1, RY + 1],
        "source_sha256": {"tools/bake_shield_world.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"AUTHORED SHIELD BUBBLE: {image.size}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
