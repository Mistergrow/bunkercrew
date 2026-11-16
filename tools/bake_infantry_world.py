#!/usr/bin/env python3
"""Bake the hostile infantry at its drawn size (style bible §1, rule 1).

EnemyCatalog.profile draws every human at 0.82 of its authored size, so the
hand-pixelled v2 field kit (tools/generate_infantry_parts_v2.py, 64-texel
tiles) put each texel on 0.82 world units. This tool reduces the kit offline
to one texel per world unit at that drawn size and bakes everything the rig
draws from it (assets/enemies/):

    infantry_parts_world.png         the v2 tiles (head, torso, rear, gun) at
                                     0.82: 54-texel tiles in the v2 index
                                     layout, body origin (27, 27), weapon
                                     origin (10, 13)
    infantry_living_turns_world.png  living attitudes, 7.5 degree keys
    infantry_gun_turns_world.png     living weapon, 7.5 degree keys
    infantry_turns_world.png         drawn defeat, 22.5 degree keys
    infantry_limbs_world.png         thighs, shins, upper arms and forearms
                                     in 48 direction keys, knees, elbows,
                                     gloves and boots in roll keys, per role
                                     and side, authored at world density (the
                                     native rig drew them as thick lines);
                                     scripts/infantry_limb_index.gd indexes it

Reduction of a hand-pixelled tile (no new colour, no blur):
1. the tile's anchor (shoulder, head pivot or grip) is a texel corner of the
   source and of the result, so the parts keep their joints,
2. coverage: a world texel is solid where the box-filtered alpha reaches 1/2,
3. colour: the source colour with the largest box-filter share of the texel,
   weighted by importance (accents such as lenses, eyes, crosses, brass and
   marks 1.9, ink 1.25, the rest 1), so the result keeps the role's own
   palette and its 1-texel features,
4. cleanup: a lone plain texel inside one other colour joins it,
5. the generator's 1-texel ink contour on the reduced silhouette (parts one
   or two texels thick keep their colours),
6. hand fixes (FIXES): crosses, the ear cup and the chin strap placed texel
   by texel where the reduction cannot hold their shape.

The turned keys are RotSprite turns (assets/workers/generate_character_workers.py)
of the reduced tiles at world density, as tools/bake_infantry_turns_v2.py
does at native density, so every key is world-texel art. Rebuild with
    python3 tools/bake_infantry_world.py [OUTPUT_DIR]
Pillow and NumPy required.
"""
from pathlib import Path
import hashlib
import json
import math
import sys

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))
import bake_infantry_turns as base  # noqa: E402
import generate_infantry_parts_v2 as kit  # noqa: E402

ENEMIES = PROJECT / "assets/enemies"
SOURCE = ENEMIES / "infantry_parts_v2.png"
INDEX = PROJECT / "scripts/infantry_limb_index.gd"
SCALE = 0.82
ROLES = kit.ROLES
TILE, COLUMNS = 54, 16
BODY_ANCHOR, GUN_ANCHOR = (27, 27), (10, 13)
# Turned keys at world density: the v2 cells and centres x 0.82.
BODY_CELL, BODY_CENTRE, GUN_CELL, GUN_CENTRE = 60, (30, 30), 86, (43, 43)
LIVING_BODY_CELL, LIVING_HEAD_CELL = 60, 40
GUN_STEPS_LIVING = tuple(range(-10, 11))
INK = (0x1b, 0x21, 0x1f)
INPUTS = ("assets/enemies/infantry_parts_v2.png", "tools/bake_infantry_world.py", "tools/generate_infantry_parts_v2.py",
          "tools/bake_infantry_turns.py", "assets/workers/generate_character_workers.py")


def _rgb(text):
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


# ---- colour ---------------------------------------------------------------

def _oklab(rgb):
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    return np.cbrt(np.maximum(lin @ m1.T, 0.0)) @ m2.T


def _srgb(lab):
    m2i = np.array([[1.0, 0.3963377774, 0.2158037573], [1.0, -0.1055613458, -0.0638541728], [1.0, -0.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965],
                    [-0.0041960863, -0.7034186147, 1.7076147010]])
    lin = np.clip(((np.asarray(lab) @ m2i.T) ** 3) @ m1i.T, 0.0, 1.0)
    c = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1.0 / 2.4) - 0.055)
    return tuple(int(round(v * 255)) for v in c)


# Readability (style bible §3): the heavy gunner's slate kit sat a value step
# below the other roles and vanished over dark trunks and night ground. Its
# ramps are lifted in OKLab lightness; ink and accents keep their values.
LIFT = {"heavy_gunner": 1.16}


def lifted(rgb, role):
    factor = LIFT.get(role)
    if factor is None or tuple(rgb) == INK or importance(rgb) == 1.9:
        return tuple(rgb)
    lab = _oklab(rgb)
    lab[0] = min(0.92, lab[0] * factor)
    return _srgb(lab)


def lift_image(image, role):
    if role not in LIFT:
        return image
    out = image.copy()
    cache = {}
    for y, x in zip(*np.nonzero(image[..., 3])):
        key = tuple(int(v) for v in image[y, x, :3])
        if key not in cache:
            cache[key] = lifted(key, role)
        out[y, x, :3] = cache[key]
    return out


def importance(rgb):
    lab = _oklab(rgb)
    if math.hypot(lab[1], lab[2]) > 0.085 or lab[0] > 0.80:
        return 1.9
    if lab[0] < 0.27:
        return 1.25
    return 1.0


# ---- reduction ------------------------------------------------------------

def coverage(count, anchor_source, anchor_target, size, scale=SCALE):
    """(size, count) box weights: target texel j covers the source span
    [anchor_source + (j - anchor_target) / scale, +1 / scale)."""
    matrix = np.zeros((size, count))
    span = 1.0 / scale
    for j in range(size):
        start = anchor_source + (j - anchor_target) * span
        end = start + span
        for k in range(max(0, int(math.floor(start))), min(count, int(math.ceil(end)))):
            overlap = min(end, k + 1) - max(start, k)
            if overlap > 0:
                matrix[j, k] = overlap / span
    return matrix


def reduce_piece(piece, anchor, size, target_anchor, alpha=0.5, scale=SCALE):
    """Steps 2-4 for an RGBA uint8 array: `anchor` (a source corner) lands on
    `target_anchor` of a `size` result drawn at `scale` of the source."""
    height, width = piece.shape[:2]
    rows = coverage(height, anchor[1], target_anchor[1], size[1], scale)
    columns = coverage(width, anchor[0], target_anchor[0], size[0], scale)
    opaque = piece[..., 3] > 0
    solid = rows @ opaque.astype(np.float64) @ columns.T >= alpha
    colours = {}
    keys = np.zeros((height, width), dtype=np.int64)
    for y, x in zip(*np.nonzero(opaque)):
        keys[y, x] = colours.setdefault(tuple(int(v) for v in piece[y, x, :3]), len(colours) + 1)
    best = np.zeros(size[::-1])
    choice = np.zeros(size[::-1], dtype=np.int64)
    for rgb, index in colours.items():
        vote = rows @ (keys == index).astype(np.float64) @ columns.T * importance(rgb)
        better = vote > best
        best[better] = vote[better]
        choice[better] = index
    palette = {index: rgb for rgb, index in colours.items()}
    out = np.zeros((size[1], size[0], 4), dtype=np.uint8)
    for y, x in zip(*np.nonzero(solid & (choice > 0))):
        out[y, x, :3] = palette[int(choice[y, x])]
        out[y, x, 3] = 255
    return cleanup(out)


def cleanup(image):
    out = image.copy()
    height, width = image.shape[:2]
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            if not image[y, x, 3] or importance(tuple(image[y, x, :3])) != 1.0:
                continue
            around = [tuple(image[y + dy, x + dx]) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
            if all(a[3] for a in around) and len(set(around)) == 1 and around[0][:3] != tuple(image[y, x, :3]):
                out[y, x] = around[0]
    return out


def contour(image):
    """Step 5: outermost solid texels turn to ink where the part is at least
    three texels thick across that edge."""
    solid = np.pad(image[..., 3] > 0, 2)
    out = image.copy()
    height, width = image.shape[:2]
    for y in range(height):
        for x in range(width):
            if not solid[y + 2, x + 2]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if not solid[y + 2 + dy, x + 2 + dx] and solid[y + 2 - dy, x + 2 - dx] and solid[y + 2 - 2 * dy, x + 2 - 2 * dx]:
                    out[y, x, :3] = INK
                    break
    return out


# ---- hand fixes -------------------------------------------------------------

def _stamp(image, anchor, at, rows, palette, only=None):
    """Writes a character map with its top-left `at` texels from the anchor;
    `only` limits it to texels that already hold one of those colours."""
    for row, line in enumerate(rows):
        for column, char in enumerate(line):
            if char == ".":
                continue
            x, y = anchor[0] + at[0] + column, anchor[1] + at[1] + row
            if not (0 <= x < image.shape[1] and 0 <= y < image.shape[0]) or not image[y, x, 3]:
                continue
            if only is not None and tuple(image[y, x, :3]) not in only:
                continue
            image[y, x, :3] = _rgb(palette[char])


def _line(a, b):
    """Texels of a stepped line from a to b (Bresenham)."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    error, points = dx + dy, []
    while True:
        points.append((x0, y0))
        if (x0, y0) == (x1, y1):
            return points
        if 2 * error >= dy:
            error += dy
            x0 += sx
        if 2 * error <= dx:
            error += dx
            y0 += sy


def _replace(image, anchor, box, colours, char, palette):
    x0, y0, x1, y1 = box
    for y in range(anchor[1] + y0, anchor[1] + y1):
        for x in range(anchor[0] + x0, anchor[0] + x1):
            if image[y, x, 3] and tuple(image[y, x, :3]) in colours:
                image[y, x, :3] = _rgb(palette[char])


def fix_head(image, role, slot):
    palette = kit.role_palette(role, slot)
    if role == "combat_medic":
        # Green cross on the ivory cap: a 3x3 plus instead of a broken L.
        _replace(image, BODY_ANCHOR, (-2, -8, 4, -2), {_rgb(palette["q"]), _rgb(palette["Q"])}, "H", palette)
        _stamp(image, BODY_ANCHOR, (0, -6), [".q.", "qqq", ".q."], palette)
    elif role == "heavy_gunner":
        # The ear cup: a lit ring round a dark hub.
        _stamp(image, BODY_ANCHOR, (-5, -4), [".ooo.", "oOOOo", "oOhOo", "oOOOo", ".ooo."], palette)
    elif role == "rifle_guard":
        # Chin strap from the helmet rim across the cheek to the chin.
        skin = {_rgb(palette[c]) for c in "sSL"}
        for x, y in _line((-3, -2), (4, 6)):
            _stamp(image, BODY_ANCHOR, (x, y), ["t"], palette, skin)


def fix_torso(image, role):
    if role != "combat_medic":
        return
    palette = kit.role_palette(role)
    # The vest's green cross, lit along its upper left.
    _replace(image, BODY_ANCHOR, (0, 1, 8, 10), {_rgb(palette["k"]), _rgb(palette["x"])}, "A", palette)
    _stamp(image, BODY_ANCHOR, (1, 2), ["..xk..", "..xk..", "xxxxxk", "kkxkkk", "..xk..", "..kk.."], palette)


# ---- parts ----------------------------------------------------------------

def tile(atlas, index, size=64):
    x, y = index % COLUMNS * size, index // COLUMNS * size
    return atlas.crop((x, y, x + size, y + size))


def world_tile(atlas, index):
    """One v2 tile reduced to TILE texels, with its hand fixes."""
    gun = index >= 246
    reduced = contour(reduce_piece(np.asarray(tile(atlas, index)), (12, 16) if gun else (32, 32), (TILE, TILE),
                                   GUN_ANCHOR if gun else BODY_ANCHOR))
    if index < 210:
        role, rest = divmod(index, 35)
        fix_head(reduced, ROLES[role], rest // 5)
    elif index < 216:
        role = index - 210
        fix_torso(reduced, ROLES[role])
    elif index < 246:
        role = (index - 216) // 5
    else:
        role = index - 246
    return Image.fromarray(lift_image(reduced, ROLES[role]), "RGBA")


def parts_sheet(atlas):
    sheet = Image.new("RGBA", (COLUMNS * TILE, COLUMNS * TILE))
    for index in range(252):
        sheet.alpha_composite(world_tile(atlas, index), (index % COLUMNS * TILE, index // COLUMNS * TILE))
    return sheet


def world_index(part, role, slot=0):
    return base.tile_index(part, role, slot)


def _turnable(parts, part, role, slot=0):
    index = world_index(part, role, slot)
    x, y = index % COLUMNS * TILE, index // COLUMNS * TILE
    return base.author._Turnable(parts.crop((x, y, x + TILE, y + TILE)), GUN_ANCHOR if part == "gun" else BODY_ANCHOR)


def _turn_sheet(parts, cells, size, steps):
    sheet = Image.new("RGBA", size)
    prepared = {}
    for part, role, slot, step, x, y, cell, centre in cells:
        key = (part, role, slot)
        if key not in prepared:
            prepared[key] = _turnable(parts, part, role, slot)
        sheet.alpha_composite(base.author.turned_piece(prepared[key], step, steps, cell, centre), (x, y))
    return sheet


# The drawn defeat in 22.5 degree keys from flat on the back (-4) through
# upright to a forward slump (+1), as infantry_turns_v2.
DEATH_STEPS = tuple(range(-4, 2))
DEATH_HEAD_CELL = 40


def death_layout():
    """Per role one row: torso and rear (BODY_CELL) for DEATH_STEPS, then the
    seven heads (DEATH_HEAD_CELL, top-aligned) for DEATH_STEPS; below, one row
    of weapons (GUN_CELL) for every role in base.GUN_STEPS."""
    cells = []
    count = len(DEATH_STEPS)
    for role in range(len(ROLES)):
        y = role * BODY_CELL
        for column, part in enumerate(("torso", "rear")):
            for index, step in enumerate(DEATH_STEPS):
                cells.append((part, role, 0, step, (column * count + index) * BODY_CELL, y, BODY_CELL, BODY_CENTRE))
        for slot in range(base.HEADS):
            for index, step in enumerate(DEATH_STEPS):
                cells.append(("head", role, slot, step, 2 * count * BODY_CELL + (slot * count + index) * DEATH_HEAD_CELL, y,
                              DEATH_HEAD_CELL, (DEATH_HEAD_CELL // 2,) * 2))
    y = len(ROLES) * BODY_CELL
    for role in range(len(ROLES)):
        for index, step in enumerate(base.GUN_STEPS):
            cells.append(("gun", role, 0, step, (role * len(base.GUN_STEPS) + index) * GUN_CELL, y, GUN_CELL, GUN_CENTRE))
    width = max(2 * count * BODY_CELL + base.HEADS * count * DEATH_HEAD_CELL, len(ROLES) * len(base.GUN_STEPS) * GUN_CELL)
    return cells, (width, y + GUN_CELL)


def living_layout():
    """infantry_living_turns_v2's layout (bake_infantry_turns.living_layout) in world cells."""
    cells = []
    band = LIVING_BODY_CELL + base.LIVING_HEAD_ROWS * LIVING_HEAD_CELL
    steps = base.LIVING_STEPS
    for role in range(len(ROLES)):
        top = role * band
        for column, part in enumerate(("torso", "rear")):
            for index, step in enumerate(steps):
                cells.append((part, role, 0, step, (column * len(steps) + index) * LIVING_BODY_CELL, top, LIVING_BODY_CELL,
                              (LIVING_BODY_CELL // 2,) * 2))
        for slot in range(base.HEADS):
            for index, step in enumerate(steps):
                at = slot * len(steps) + index
                cells.append(("head", role, slot, step, at % base.LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL,
                              top + LIVING_BODY_CELL + at // base.LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL, LIVING_HEAD_CELL,
                              (LIVING_HEAD_CELL // 2,) * 2))
    width = max(base.LIVING_HEADS_PER_ROW * LIVING_HEAD_CELL, 2 * len(steps) * LIVING_BODY_CELL)
    return cells, (width, len(ROLES) * band)


def gun_layout():
    cells = [("gun", role, 0, step, column * GUN_CELL, role * GUN_CELL, GUN_CELL, GUN_CENTRE)
             for role in range(len(ROLES)) for column, step in enumerate(GUN_STEPS_LIVING)]
    return cells, (len(GUN_STEPS_LIVING) * GUN_CELL, len(ROLES) * GUN_CELL)


# ---- limbs ----------------------------------------------------------------
# The native rig's limb colours per role (formerly GroundInfantryArt.COLORS
# merged with ROLE_COLORS) and InfantryRoleArt.WEAR, matching the coats of
# infantry_parts_v2.png.
LIMB_COLOURS = {"trouser": "3d483f", "trouser_light": "56634f", "shadow": "36403a", "deep": "232a25", "olive": "4f5a50",
                "cloth": "55614f", "light": "6b786a", "boot": "2e2822", "boot_light": "4d4337", "strap": "3a3127",
                "sole": "141817", "leather": "3a2f25", "leather_light": "574634", "skin": "6a5440", "skin_light": "7f6650"}
ROLE_LIMB_COLOURS = {
    "grenadier": {"olive": "62523a", "cloth": "6b5a40", "light": "826f50", "shadow": "443828", "deep": "2b241b", "trouser": "3b3f33",
                  "trouser_light": "545b4c", "leather": "262b28", "leather_light": "3d4541", "skin": "3d4541", "skin_light": "5c6761"},
    "scout": {"olive": "726e52", "cloth": "7d7a5c", "light": "939072", "shadow": "524f39", "deep": "34321f", "trouser": "5a5844",
              "trouser_light": "7a775e", "boot": "4a3d2c", "boot_light": "6e5a40", "leather": "4a3d2c", "leather_light": "6e5a40",
              "skin": "9a6a48", "skin_light": "c08e64"},
    "heavy_gunner": {"olive": "465246", "cloth": "465246", "light": "5f6b5c", "shadow": "303a33", "deep": "1f2522", "trouser": "37403a",
                     "trouser_light": "4f5a50", "boot": "1f2326", "boot_light": "3a4247", "leather": "293136", "leather_light": "414c53",
                     "skin": "414c53", "skin_light": "5d6a70"},
    "marksman": {"olive": "4a5533", "cloth": "4a5533", "light": "65713f", "shadow": "343c24", "deep": "232818", "trouser": "43361f",
                 "trouser_light": "62502f", "leather": "343c24", "leather_light": "4a5533", "skin": "65713f", "skin_light": "838e54"},
    "combat_medic": {"olive": "56625b", "cloth": "56625b", "light": "717e75", "shadow": "3b4640", "deep": "283029", "trouser": "3b4640",
                     "trouser_light": "56625b", "leather": "8f8a74", "leather_light": "b6b097", "skin": "b6b097", "skin_light": "d8d2b8"},
}
WEAR = {"rifle_guard": ("6b786a", "4f5a50", "232a25", "4a3b2b", "6a553c"), "grenadier": ("826f50", "62523a", "2b241b", "3d4541", "5c6761"),
        "scout": ("939072", "726e52", "34321f", "5a5844", "7a775e"), "heavy_gunner": ("5f6b5c", "465246", "1f2522", "434e55", "86938f"),
        "marksman": ("65713f", "4a5533", "232818", "4a3b24", "6c5733"), "combat_medic": ("717e75", "56625b", "283029", "3b4640", "717e75")}
LIMB_KEYS = 48
# Segment kinds: native length x 0.82, drawn width; "shin_long" covers a leg
# stretched beyond its two-bone reach (the rig clamps the arms). Shins and
# forearms are anchored at the boot and the glove, so a gap can only open at
# the knee or elbow cap.
# An odd width runs through the centre of the anchor texel, an even width
# along its corner, so every width keeps its texel count in all directions.
SEGMENTS = (("thigh", 12 * SCALE, 7), ("shin", 12 * SCALE, 6), ("shin_long", 12 * SCALE + 2.5, 6),
            ("upper", 11 * SCALE, 6), ("fore", 12 * SCALE, 5))
DISTAL = {"shin", "shin_long", "fore"}
# Heel-toe roll of the walk (-0.24 .. 0.30 rad) and the lying body's toes
# pointing up.
BOOT_KEYS = (-90.0, -45.0, -15.0, -7.5, 0.0, 7.5, 15.0)
SINGLES = ("knee", "elbow", "glove")
PER_SIDE = len(SEGMENTS) * LIMB_KEYS + len(SINGLES) + len(BOOT_KEYS)
BOOT = ["KKKKKK.....", "KbBBbK.....", "KbBbbbKK...", "KbbbbbblbK.", "KbbbbbbbbbK", "SSSSSSSSSSS"]
BOOT_ORIGIN = (4, 3)
GLOVE = ["KKKKKK", "KllkkK", "KlllkK", "KddddK", "KKKKKK"]
GLOVE_ORIGIN = (3, 2)


def limb_palette(role):
    colours = dict(LIMB_COLOURS)
    colours.update(ROLE_LIMB_COLOURS.get(role, {}))
    return {key: lifted(_rgb(value), role) if key != "sole" else _rgb(value) for key, value in colours.items()}


def _segment_tones(role, kind, front):
    c = limb_palette(role)
    if kind.startswith(("thigh", "shin")):
        return (c["trouser_light"], c["trouser"], c["shadow"]) if front else (c["shadow"], c["deep"], c["deep"])
    if kind == "upper":
        return (c["light"], c["olive"], c["shadow"]) if front else (c["olive"], c["shadow"], c["deep"])
    return (c["light"], c["cloth"], c["olive"]) if front else (c["cloth"], c["olive"], c["shadow"])


def segment_sprite(role, kind, length, width, angle, front):
    """A limb segment from its anchor (a texel corner) along `angle`: ink
    rim, a lit band on the upper-left side, mid tone, shadow band, and the
    role's wear (sleeve light and crease, tufts, plates)."""
    radius = width * 0.5
    reach = int(math.ceil(length + radius)) + 2
    size = reach * 2
    image = np.zeros((size, size, 4), dtype=np.uint8)
    u = np.array([math.cos(angle), math.sin(angle)])
    n = np.array([-u[1], u[0]])
    if n @ np.array([-1.0, -1.0]) < 0:
        n = -n
    light, mid, dark = _segment_tones(role, kind, front)
    distal = kind in DISTAL
    solid = np.zeros((size, size), dtype=bool)
    along = np.zeros((size, size))
    across = np.zeros((size, size))
    centred = 0.5 if width % 2 else 0.0
    for y in range(size):
        for x in range(size):
            c = np.array([x + 0.5 - reach - centred, y + 0.5 - reach - centred])
            t, s = c @ u, c @ n
            if -0.5 <= t <= length + 0.5 and abs(s) < radius:
                solid[y, x] = True
                along[y, x] = t
                across[y, x] = s
    padded = np.pad(solid, 1)
    inner = padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:]
    wear = [lifted(_rgb(v), role) for v in WEAR.get(role, WEAR["rifle_guard"])]
    for y, x in zip(*np.nonzero(solid)):
        s = across[y, x]
        colour = mid
        if s > radius - 2.6:
            colour = light
        elif s < -radius + 1.6 and width >= 6:
            colour = dark
        if not inner[y, x]:
            colour = INK
        image[y, x, :3] = colour
        image[y, x, 3] = 255
    # Wear at 55 % from the proximal joint: a sleeve-light texel on the lit
    # side and a crease on the shadow side (InfantryRoleArt.limb_wear).
    proximal = length * (0.45 if distal else 0.55)
    marks = [(proximal, radius - 2.0, wear[0] if front else wear[1]), (proximal + 1.0, -radius + 2.0, wear[2])]
    if role == "marksman":
        # Ghillie tufts break the outline of every segment.
        for share in (0.3, 0.7):
            marks.append((length * share, radius - 0.5, wear[4] if front else wear[3]))
            marks.append((length * share + 1.0, radius + 0.5, wear[4] if front else wear[3]))
    for t, s, colour in marks:
        point = u * t + n * s
        x, y = int(math.floor(point[0] + reach + centred)), int(math.floor(point[1] + reach + centred))
        if 0 <= x < size and 0 <= y < size:
            image[y, x, :3] = colour
            image[y, x, 3] = 255
    if role == "heavy_gunner" and kind.startswith("fore"):
        # Slate forearm plate, lit along its top edge.
        centre = u * (length * (0.55 if distal else 0.45))
        _box(image, (int(math.floor(centre[0] + centred)) - 2 + reach, int(math.floor(centre[1] + centred)) - 2 + reach), ["KKKKK", "KeeeK", "KpppK", "KKKKK"],
             {"K": INK, "e": wear[4], "p": wear[3]})
    return image


def _box(image, at, rows, colours):
    for row, line in enumerate(rows):
        for column, char in enumerate(line):
            x, y = at[0] + column, at[1] + row
            if char != "." and 0 <= x < image.shape[1] and 0 <= y < image.shape[0]:
                image[y, x, :3] = colours[char]
                image[y, x, 3] = 255


def single_sprite(role, kind, front):
    """Knee and elbow caps and the glove; the anchor is the joint or grip."""
    c = limb_palette(role)
    wear = [lifted(_rgb(v), role) for v in WEAR.get(role, WEAR["rifle_guard"])]
    image = np.zeros((12, 12, 4), dtype=np.uint8)
    anchor = (6, 6)
    shade = c["shadow"] if front else c["deep"]
    if kind == "knee":
        if role == "heavy_gunner":
            _box(image, (anchor[0] - 3, anchor[1] - 2), ["KKKKK", "KeeeK", "KpppK", "KKKKK"], {"K": INK, "e": wear[4], "p": wear[3]})
        elif role == "marksman":
            _box(image, (anchor[0] - 2, anchor[1] - 1), ["ssss", ".ss."], {"s": shade})
        else:
            _box(image, (anchor[0] - 2, anchor[1] - 2), ["seee", "sppp", ".ss."], {"s": shade, "e": wear[4] if front else wear[3], "p": wear[3]})
    elif kind == "elbow":
        _box(image, (anchor[0] - 2, anchor[1] - 1), ["sss", "ss."], {"s": shade})
    else:
        tones = {"K": INK, "l": c["leather_light"] if front else c["leather"], "k": c["skin_light"] if front else c["skin"], "d": c["leather"]}
        _box(image, (anchor[0] - GLOVE_ORIGIN[0], anchor[1] - GLOVE_ORIGIN[1]), GLOVE, tones)
    return image, anchor


def boot_sprite(role, degrees, front):
    """The native boot at world density, turned by its roll: the lowest sole
    texel stays on the contact row (WorkerPoseArt.foot_transform)."""
    c = limb_palette(role)
    tones = {"K": INK, "b": c["boot"], "B": c["boot_light"] if front else c["strap"], "l": c["leather_light"] if front else c["boot_light"],
             "S": c["sole"]}
    flat = Image.new("RGBA", (len(BOOT[0]), len(BOOT)))
    for row, line in enumerate(BOOT):
        for column, char in enumerate(line):
            if char != ".":
                flat.putpixel((column, row), tones[char] + (255,))
    cell, centre = 24, (12, 12)
    turned = np.asarray(base.author.turned_piece(base.author._Turnable(flat, BOOT_ORIGIN), round(degrees / 7.5), 48, cell, centre)).copy()
    if -30.0 < degrees < 30.0:
        rows = np.nonzero(turned[..., 3].any(1))[0]
        drop = (centre[1] + len(BOOT) - 1 - BOOT_ORIGIN[1]) - int(rows.max())
        turned = np.roll(turned, drop, axis=0)
    return turned, centre


def _trim(image, anchor):
    rows = np.nonzero(image[..., 3].any(1))[0]
    columns = np.nonzero(image[..., 3].any(0))[0]
    if rows.size == 0:
        return image[:1, :1], (0, 0)
    crop = image[rows[0]:rows[-1] + 1, columns[0]:columns[-1] + 1]
    return crop, (int(columns[0]) - anchor[0], int(rows[0]) - anchor[1])


def limb_sprites():
    """[(image, offset of its top-left from the anchor)] in index order:
    per role, per side (front, back): the segments in LIMB_KEYS directions,
    SINGLES, then the boots in BOOT_KEYS."""
    sprites = []
    for role in ROLES:
        for front in (True, False):
            for kind, length, width in SEGMENTS:
                for key in range(LIMB_KEYS):
                    image = segment_sprite(role, kind, length, width, key * 2.0 * math.pi / LIMB_KEYS, front)
                    reach = image.shape[0] // 2
                    sprites.append(_trim(image, (reach, reach)))
            for kind in SINGLES:
                image, anchor = single_sprite(role, kind, front)
                sprites.append(_trim(image, anchor))
            for degrees in BOOT_KEYS:
                image, anchor = boot_sprite(role, degrees, front)
                sprites.append(_trim(image, anchor))
    return sprites


def pack(images, width):
    """Shelf packing, tallest first, one clear texel between sprites."""
    order = sorted(range(len(images)), key=lambda i: (-images[i].shape[0], -images[i].shape[1], i))
    places = [None] * len(images)
    x = y = shelf = 0
    for i in order:
        h, w = images[i].shape[:2]
        if x + w > width:
            x, y, shelf = 0, y + shelf + 1, 0
        places[i] = (x, y)
        x += w + 1
        shelf = max(shelf, h)
    canvas = np.zeros((y + shelf, width, 4), dtype=np.uint8)
    for i, (px, py) in enumerate(places):
        h, w = images[i].shape[:2]
        canvas[py:py + h, px:px + w] = images[i]
    return canvas, places


def write_index(sprites, places, target):
    values = []
    for (image, (ox, oy)), (px, py) in zip(sprites, places):
        values += [px, py, image.shape[1], image.shape[0], ox, oy]
    lines = [
        "extends RefCounted",
        "## Generated by tools/bake_infantry_world.py; do not edit. Six ints per",
        "## sprite of infantry_limbs_world.png: atlas x, y, width, height and the",
        "## offset of its top-left texel from the anchor (hip, shoulder, boot or",
        "## glove for the segments, the joint for caps and boots).",
        f"const KEYS := {LIMB_KEYS}",
        "const SEGMENTS: Array[String] = [" + ", ".join(f'"{kind}"' for kind, _, _ in SEGMENTS) + "]",
        "## Odd widths centre on the anchor texel (draw at the floored point), even",
        "## widths on its corner (draw at the rounded point).",
        "const CENTRED: Array[bool] = [" + ", ".join("true" if width % 2 else "false" for _, _, width in SEGMENTS) + "]",
        "const SINGLES: Array[String] = [" + ", ".join(f'"{kind}"' for kind in SINGLES) + "]",
        "const BOOT_KEYS: Array[float] = [" + ", ".join(f"{v:g}" for v in BOOT_KEYS) + "]",
        f"const PER_SIDE := {PER_SIDE}",
        "const DATA: Array[int] = [",
    ]
    for start in range(0, len(values), 24):
        lines.append("\t" + ", ".join(str(v) for v in values[start:start + 24]) + ",")
    lines.append("]")
    target.write_text("\n".join(lines) + "\n")


# ---- provenance -------------------------------------------------------------

def _notice(target, extra):
    notice = {
        "asset": target.name,
        "generator": "tools/bake_infantry_world.py",
        "license": "Original Bunkercrew project art.",
        "scale": SCALE,
    }
    notice.update(extra)
    notice["source_sha256"] = {path: hashlib.sha256((PROJECT / path).read_bytes()).hexdigest() for path in INPUTS}
    notice["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")


REDUCTION = ("Reduced from infantry_parts_v2.png to the drawn 0.82 size, one texel per world unit: anchor on a texel corner, "
             "box-filter alpha >= 1/2, importance-weighted majority colour of the source (no new colour), speck cleanup, "
             "1-texel ink contour, hand-fixed crosses, ear cup and chin strap; the heavy gunner's ramps lifted x1.16 in OKLab "
             "lightness for readability.")


def main(output=None):
    out = Path(output) if output else ENEMIES
    out.mkdir(parents=True, exist_ok=True)
    atlas = Image.open(SOURCE).convert("RGBA")
    parts = parts_sheet(atlas)
    target = out / "infantry_parts_world.png"
    parts.save(target)
    _notice(target, {"method": REDUCTION, "layout": {"tile": TILE, "columns": COLUMNS, "index": "as infantry_parts_v2 (InfantryArtAtlas.tile_index)",
                                                     "body_anchor": list(BODY_ANCHOR), "gun_anchor": list(GUN_ANCHOR)}})
    turned = "RotSprite turns (3x Scale2x, one sample per texel) of infantry_parts_world.png at world density; " + REDUCTION
    cells, size = death_layout()
    target = out / "infantry_turns_world.png"
    _turn_sheet(parts, cells, size, base.STEPS).save(target)
    _notice(target, {"method": turned, "steps_per_turn": base.STEPS, "body_steps": list(DEATH_STEPS), "gun_steps": list(base.GUN_STEPS),
                     "body_cell": BODY_CELL, "head_cell": DEATH_HEAD_CELL, "gun_cell": GUN_CELL, "size": list(size)})
    cells, size = living_layout()
    target = out / "infantry_living_turns_world.png"
    _turn_sheet(parts, cells, size, base.LIVING_PER_TURN).save(target)
    _notice(target, {"method": turned, "steps_per_turn": base.LIVING_PER_TURN, "steps": list(base.LIVING_STEPS),
                     "body_cell": LIVING_BODY_CELL, "head_cell": LIVING_HEAD_CELL, "size": list(size)})
    cells, size = gun_layout()
    target = out / "infantry_gun_turns_world.png"
    _turn_sheet(parts, cells, size, base.LIVING_PER_TURN).save(target)
    _notice(target, {"method": turned, "steps_per_turn": base.LIVING_PER_TURN, "steps": list(GUN_STEPS_LIVING), "cell": GUN_CELL,
                     "size": list(size)})
    sprites = limb_sprites()
    canvas, places = pack([image for image, _ in sprites], 512)
    target = out / "infantry_limbs_world.png"
    Image.fromarray(canvas, "RGBA").save(target, optimize=True)
    _notice(target, {"method": "Authored at world density: limb segments rasterised per direction key (ink rim, lit band, mid, "
                               "shadow band, role wear), boots RotSprite-turned per roll key, caps and gloves as texel maps, in the "
                               "native rig's role colours.", "keys": LIMB_KEYS, "segments": [list(s) for s in SEGMENTS],
                     "boot_keys": list(BOOT_KEYS), "sprites": len(sprites), "size": [canvas.shape[1], canvas.shape[0]]})
    write_index(sprites, places, INDEX if output is None else out / INDEX.name)
    print(f"BAKED INFANTRY WORLD: parts, turns, living, guns, {len(sprites)} limb sprites in {canvas.shape[1]}x{canvas.shape[0]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
