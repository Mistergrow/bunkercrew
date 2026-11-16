#!/usr/bin/env python3
"""Grade the painted enemy hull plates for readability against the backdrops.

Review 5 (D02, D03, D04): brown and olive aircraft vanished against the dark
night forest and the brown rail-yard trains, and ground machines clumped into
one brown mass. Style bible sections 3 and 4 ask for palette and value, not
outlines: mid values with a lit top edge, a hostile red accent and a value
distance of at least 15 % to the backdrop. This script writes graded copies of
the three plates; the v1 plates stay untouched for comparison.

Per hull region, only colour changes; every alpha texel is kept, so
silhouettes, weather contours, sockets and regions are identical:

  * Paint identity: the olive/brown body paint (low saturation texels) is
    moved to a per-type hue and saturation, so neighbouring types differ.
    Brass, rust, glass and the red sensor lamps keep their hue.
  * Value structure: an S-curve about the region's paint median deepens the
    recesses and lifts the plates, and sky light from above lifts the upper
    planes and shades the lower body. Texels above ~0.53 luma separate from
    both the night (~0.10) and the snow (~0.38) backdrops, the shaded lower
    body from the snow, the lit upper body from the night.
  * Lit top edge: every texel within one world texel (the region's source
    pixels per world unit at its drawn size) below empty space above it is
    lifted and cooled by the sky. Runtime sampling keeps it one texel thick.
  * Ground contact / underside: ground hulls darken their lowest texel row;
    aircraft get a slightly lighter belly (countershading at night).
  * Hostile accent: each aircraft gets a red sensor lamp near its nose; the
    machines already carry painted red optics.

Rebuild with  python3 tools/grade_enemy_hulls.py  (Pillow, NumPy).
"""
from pathlib import Path
import colorsys
import hashlib
import json
import sys
import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
ENEMIES = PROJECT / "assets/enemies"

# (hue degrees, saturation scale, value gain) of the body paint per type.
AIRCRAFT = {
    "source": "aircraft_hulls_v1.png", "output": "aircraft_hulls_v2.png", "air": True,
    "regions": {
        "scout_drone": ((48, 137, 281, 150), 5.8, (84, 1.05, 1.06)),
        "gunship": ((368, 123, 383, 167), 5.4, (74, 1.00, 1.04)),
        "bomber": ((773, 73, 409, 219), 5.0, (46, 1.00, 1.12)),
        "interceptor": ((1211, 96, 431, 194), 7.4, (58, 0.45, 1.08)),
        "shield_airship": ((30, 385, 340, 212), 3.2, (40, 1.05, 1.10)),
        "sky_fortress": ((387, 374, 434, 214), 3.8, (58, 0.85, 1.00)),
        "rocket_drone": ((881, 406, 270, 157), 4.4, (92, 0.95, 1.06)),
        "patrol_plane": ((1209, 401, 424, 171), 5.4, (50, 0.95, 1.14)),
        "tiltrotor": ((44, 656, 345, 211), 4.2, (100, 0.80, 1.06)),
        "dive_bomber": ((407, 667, 396, 191), 4.8, (26, 1.00, 1.06)),
        "pulse_fighter": ((823, 664, 348, 223), 3.9, (30, 0.35, 0.86)),
        "heavy_zeppelin": ((1193, 676, 463, 213), 3.2, (66, 0.85, 1.04)),
    },
}
CHASSIS = {
    "source": "chassis_atlas.png", "output": "chassis_atlas_v2.png", "air": False,
    "regions": {
        "runner": ((96, 243, 344, 198), 5.3, (20, 1.30, 1.06)),
        "strider": ((558, 220, 396, 252), 5.4, (78, 0.92, 1.06)),
        "breaker": ((1012, 232, 489, 245), 6.3, (40, 0.40, 0.86)),
        "colossus": ((47, 513, 433, 428), 5.9, (46, 1.00, 1.18)),
        "assault": ((508, 626, 442, 271), 6.1, (104, 0.55, 1.00)),
        "siege": ((987, 525, 530, 412), 6.7, (52, 0.95, 0.95)),
    },
}
# The mortar carrier shared the tank's hull region; v2 gives it its own
# graded copy in a new row below (ground_vehicle_art.gd REGIONS).
VEHICLES = {
    "source": "vehicle_hulls_v1.png", "output": "vehicle_hulls_v2.png", "air": False,
    "regions": {
        "scout_car": ((265, 130, 1055, 330), 9.4, (48, 1.00, 1.14)),
        "battle_tank": ((103, 556, 1393, 361), 11.1, (82, 1.05, 1.04)),
        "mortar_carrier": ((103, 556, 1393, 361), 11.1, (32, 1.15, 1.08)),
    },
    "copies": {"mortar_carrier": (103, 1024)},
    "size": (1536, 1408),
}
PLATES = (AIRCRAFT, CHASSIS, VEHICLES)
CONTRAST = 1.40
SKY_LIFT = 0.45     # added value on the upper planes (fading to the middle)
BODY_SHADE = 0.75   # value scale of the lowest body texels (fading up)
RED = np.array([0xc6, 0x5b, 0x47]) / 255.0
RED_CORE = np.array([0xf0, 0x8a, 0x5c]) / 255.0


def _hsv(rgb):
    flat = rgb.reshape(-1, 3)
    return np.array([colorsys.rgb_to_hsv(*pixel) for pixel in flat]).reshape(rgb.shape)


def _rgb(hsv):
    flat = hsv.reshape(-1, 3)
    return np.array([colorsys.hsv_to_rgb(*pixel) for pixel in flat]).reshape(hsv.shape)


def _depth_from(alpha, direction):
    """Texels between each opaque texel and the empty space above (direction
    -1) or below (+1), counted along the column, capped at 64."""
    height, width = alpha.shape
    depth = np.full(alpha.shape, 64, dtype=np.int32)
    rows = range(height) if direction < 0 else range(height - 1, -1, -1)
    previous = np.zeros(width, dtype=np.int32)
    for y in rows:
        current = np.where(alpha[y], np.minimum(previous + 1, 64), 0)
        depth[y] = np.where(alpha[y], current, 0)
        previous = current
    return depth


def grade_region(crop, px_per_texel, paint, air):
    rgba = np.asarray(crop, dtype=np.float64) / 255.0
    rgb, alpha = rgba[..., :3], rgba[..., 3] > 0.5
    hsv = _hsv(rgb)
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    target_hue, sat_scale, gain = paint
    body = alpha & (sat < 0.42) & (val > 0.10) & (val < 0.92)
    accent = alpha & ~body
    lamp = accent & ((hue < 0.04) | (hue > 0.95)) & (sat > 0.5)
    median = float(np.median(val[body])) if body.any() else 0.4
    # Paint identity: one hue per type, the painted value detail kept.
    hue = np.where(body, target_hue / 360.0, hue)
    sat = np.where(body, np.clip(sat * sat_scale + 0.05, 0.0, 0.55), sat)
    # Value structure (S-curve about the paint median), lamps untouched.
    curved = np.clip(median + (val - median) * CONTRAST, 0.0, 1.0) * gain
    val = np.where(alpha & ~lamp & (val > 0.08), np.clip(curved, 0.0, 1.0), val)
    band = max(2, int(round(px_per_texel)))
    top = _depth_from(alpha, -1)
    bottom = _depth_from(alpha, 1)
    # Sky light: 0 at the upper silhouette, 1 at the lower one, per column.
    height = np.maximum(1, top + bottom - 1)
    down = np.clip((top - 1) / height, 0.0, 1.0)
    upper = np.clip(1.0 - down / 0.45, 0.0, 1.0)
    lower = np.clip((down - 0.45) / 0.55, 0.0, 1.0)
    shaded = alpha & ~lamp
    val = np.where(shaded, np.clip(val + SKY_LIFT * upper * (1.0 - val), 0.0, 1.0), val)
    val = np.where(shaded, val * (1.0 - (1.0 - BODY_SHADE) * lower), val)
    lit = alpha & (top >= 1) & (top <= band) & ~lamp
    val = np.where(lit, np.clip(val + 0.20 + 0.25 * (1.0 - val), 0.0, 1.0), val)
    sat = np.where(lit & body, sat * 0.55, sat)
    hue = np.where(lit & body, (hue * 0.7 + 0.16 * 0.3), hue)
    if air:
        belly = alpha & (bottom >= 1) & (bottom <= band * 2) & ~lamp & (top > band)
        val = np.where(belly, np.clip(val + 0.07, 0.0, 1.0), val)
    else:
        contact = alpha & (bottom >= 1) & (bottom <= band) & ~lamp
        val = np.where(contact, val * 0.72, val)
    out_rgb = _rgb(np.stack([hue, sat, val], axis=-1))
    if air:
        out_rgb = _nose_lamp(out_rgb, alpha, band)
    out = np.concatenate([out_rgb, rgba[..., 3:4]], axis=-1)
    return Image.fromarray(np.clip(np.round(out * 255.0), 0, 255).astype(np.uint8), "RGBA")


def _nose_lamp(rgb, alpha, band):
    """A red sensor two texels square, one texel in from the nose (left)."""
    height, width = alpha.shape
    rows = [y for y in range(int(height * 0.30), int(height * 0.70)) if alpha[y].any()]
    if not rows:
        return rgb
    nose_y = min(rows, key=lambda y: int(np.argmax(alpha[y])))
    nose_x = int(np.argmax(alpha[nose_y]))
    size = band * 2
    x0 = nose_x + band + band // 2
    y0 = max(0, nose_y - size // 2)
    region = alpha[y0:y0 + size + 2, x0 - 1:x0 + size + 1]
    if region.size == 0 or not region.all():
        return rgb
    rgb = rgb.copy()
    rgb[y0 - 1 if y0 else 0:y0 + size + 1, x0 - 1:x0 + size + 1] = np.array([0x1b, 0x21, 0x1f]) / 255.0
    rgb[y0:y0 + size, x0:x0 + size] = RED
    rgb[y0:y0 + band, x0:x0 + band] = RED_CORE
    return rgb


def grade_plate(plate, output_dir=None):
    source = Image.open(ENEMIES / plate["source"]).convert("RGBA")
    size = plate.get("size", source.size)
    result = Image.new("RGBA", size)
    result.alpha_composite(source, (0, 0))
    regions = {}
    for kind, (box, px_per_texel, paint) in plate["regions"].items():
        x, y, w, h = box
        graded = grade_region(source.crop((x, y, x + w, y + h)), px_per_texel, paint, plate["air"])
        at = plate.get("copies", {}).get(kind, (x, y))
        result.paste(graded, at)
        regions[kind] = [at[0], at[1], w, h]
    target = (Path(output_dir) if output_dir else ENEMIES) / plate["output"]
    result.save(target)
    notice = {
        "asset": plate["output"],
        "generator": "tools/grade_enemy_hulls.py",
        "source": "assets/enemies/" + plate["source"],
        "method": "Colour and value grade of the painted hull plate per region: per-type paint hue, S-curve value structure, lit top edge one world texel thick, ground contact shade or lighter aircraft belly, red sensor lamp on aircraft. Alpha unchanged; no generated imagery.",
        "license": "Same as the source plate (see its source metadata).",
        "regions": {kind: {"box": box, "source_px_per_world_texel": plate["regions"][kind][1],
                           "paint_hue_sat_gain": list(plate["regions"][kind][2])} for kind, box in regions.items()},
        "contrast": CONTRAST,
        "size": list(size),
        "source_sha256": {"assets/enemies/" + plate["source"]: hashlib.sha256((ENEMIES / plate["source"]).read_bytes()).hexdigest(),
                          "tools/grade_enemy_hulls.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"GRADED {plate['source']} -> {target.name} {size}")


def main(output_dir=None):
    for plate in PLATES:
        grade_plate(plate, output_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
