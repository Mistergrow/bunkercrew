#!/usr/bin/env python3
"""Construct the Bunkercrew logo lockup as native pixel art (Pillow only).

No font, no image source and no generated reference: every texel comes from
the construction below, so the lockup is reproducible byte for byte.

  * Emblem: an octagonal blast-hatch plate with a hazard-striped rim, eight
    rivets and the crew's amber hardhat with its lit lamp in the middle.
  * Lettering: chamfered stencil plate capitals (the bridges are real 1-texel
    cuts), painted worn ivory over steel: lit top edge, shaded underside,
    a few chips where the bare steel shows, 1-texel ink contour.
  * Nameplate: a riveted steel band behind the letters; the capitals break
    out of it above and below, so the word and the emblem read as one plate.

Two variants are written to assets/ui/logo/: the title lockup and a small
lockup that reads at 1x within 160 px. Menus draw them at whole real pixels
per texel (UiArt.pixel_fit). Run: python3 tools/build_bunkercrew_logo.py
"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/ui/logo'

INK = (20, 26, 27, 255)
# Worn ivory paint (UI ivory #e0decb family) over olive steel (style bible §4).
PAINT = {'lit': (246, 236, 204, 255), 'face': (222, 214, 186, 255), 'shade': (170, 162, 132, 255), 'deep': (122, 116, 96, 255)}
CHIP = (92, 102, 93, 255)
STEEL = {'edge': (138, 144, 136, 255), 'light': (92, 102, 93, 255), 'mid': (59, 69, 61, 255), 'dark': (43, 50, 46, 255), 'deep': (30, 36, 33, 255)}
LIT_EDGE = (201, 164, 106, 255)  # sodium room light catching the plate's top edge
AMBER = {'deep': (130, 84, 46, 255), 'mid': (203, 148, 58, 255), 'light': (237, 197, 102, 255), 'hot': (255, 228, 165, 255)}
LAMP = (255, 240, 184, 255)
HAZARD_DARK = (34, 32, 28, 255)
RUST = (138, 74, 42, 255)


class Canvas:
    def __init__(self, width: int, height: int):
        self.w, self.h = width, height
        self.px: dict[tuple[int, int], tuple] = {}

    def set(self, x: int, y: int, colour: tuple) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = colour

    def image(self) -> Image.Image:
        img = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        for (x, y), colour in self.px.items():
            img.putpixel((x, y), colour)
        return img


# ---------------------------------------------------------------- lettering
# Hand-set capitals, one string per texel row ('#' = paint). The title cut is
# a chamfered stencil plate face (cap height 24, 6-texel stems, 1-texel
# stencil bridges); the small cut (cap height 11) drops the bridges so it
# stays legible at 1x.
LARGE_GLYPHS = {
    'B': [
        '...###.#########..',
        '..####.##########.',
        '.#####.###########',
        '######.###########',
        '######.###########',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......#####.',
        '######.##########.',
        '######.#########..',
        '######.#########..',
        '######.##########.',
        '######......#####.',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######.###########',
        '######.###########',
        '.#####.###########',
        '..####.##########.',
        '...###.#########..',
    ],
    'U': [
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '#######....#######',
        '##################',
        '##################',
        '.################.',
        '..##############..',
        '...############...',
    ],
    'N': [
        '...###.......######',
        '..####.......######',
        '.#####.......######',
        '######.#.....######',
        '######.#.....######',
        '######.##....######',
        '######.##....######',
        '##########...######',
        '###########..######',
        '###########..######',
        '############.######',
        '############.######',
        '######.############',
        '######.############',
        '######..###########',
        '######..###########',
        '######...##########',
        '######....##.######',
        '######....##.######',
        '######.....#.######',
        '######.....#.######',
        '######.......#####.',
        '######.......####..',
        '######.......###...',
    ],
    'K': [
        '...###......######',
        '..####......######',
        '.#####.....######.',
        '######.....######.',
        '######....######..',
        '######....######..',
        '######...######...',
        '######...######...',
        '######..######....',
        '######..######....',
        '######.######.....',
        '######.######.....',
        '######.######.....',
        '######.######.....',
        '######..######....',
        '######..######....',
        '######...######...',
        '######...######...',
        '######....######..',
        '######....######..',
        '######.....######.',
        '.#####.....######.',
        '..####......######',
        '...###......######',
    ],
    'E': [
        '...###.########',
        '..####.########',
        '.#####.########',
        '######.########',
        '######.#######.',
        '######.........',
        '######.........',
        '######.........',
        '######.........',
        '######.........',
        '######.######..',
        '######.#######.',
        '######.#######.',
        '######.######..',
        '######.........',
        '######.........',
        '######.........',
        '######.........',
        '######.........',
        '######.#######.',
        '######.########',
        '.#####.########',
        '..####.########',
        '...###.########',
    ],
    'R': [
        '...###.#########..',
        '..####.##########.',
        '.#####.###########',
        '######.###########',
        '######.###########',
        '######......######',
        '######......######',
        '######......######',
        '######......######',
        '######......#####.',
        '######.##########.',
        '######.#########..',
        '######.########...',
        '######.#######....',
        '######.######.....',
        '######..######....',
        '######..######....',
        '######...######...',
        '######...######...',
        '######....######..',
        '######....######..',
        '.#####.....######.',
        '..####.....######.',
        '...###......######',
    ],
    'C': [
        '....#####.#######',
        '...######.#######',
        '..#######.#######',
        '.########.#######',
        '#########.#######',
        '######......#####',
        '######......#####',
        '######.......###.',
        '######...........',
        '######...........',
        '######...........',
        '######...........',
        '######...........',
        '######...........',
        '######...........',
        '######...........',
        '######.......###.',
        '######......#####',
        '######......#####',
        '#########.#######',
        '.########.#######',
        '..#######.#######',
        '...######.#######',
        '....#####.#######',
    ],
    'W': [
        '######............######',
        '######............######',
        '######............######',
        '######............######',
        '######............######',
        '######............######',
        '######............######',
        '######.....##.....######',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '.######...####...######.',
        '..######..####..######..',
        '..######..####..######..',
        '..######..####..######..',
        '..####################..',
        '..####################..',
        '..####################..',
        '..####################..',
        '...########..########...',
    ],
}
SMALL_GLYPHS = {
    'B': ['.######.', '########', '###..###', '###..###', '#######.', '#######.', '###..###', '###..###', '###..###', '########', '.######.'],
    'U': ['###..###'] * 9 + ['########', '.######.'],
    'N': ['####..###', '####..###', '#####.###', '#####.###', '#####.###', '###.#.###', '###.#####', '###.#####', '###.#####', '###..####', '###..####'],
    'K': ['###..###', '###.###.', '######..', '#####...', '####....', '####....', '#####...', '######..', '###.###.', '###..###', '###..###'],
    'E': ['.######', '#######', '###....', '###....', '######.', '######.', '###....', '###....', '###....', '#######', '.######'],
    'R': ['.######.', '########', '###..###', '###..###', '#######.', '######..', '###.###.', '###.###.', '###..###', '###..###', '###..###'],
    'C': ['..######', '.#######', '###...##', '###.....', '###.....', '###.....', '###.....', '###.....', '###...##', '.#######', '..######'],
    'W': ['###.....###', '###.....###', '###.....###', '###..#..###', '###.###.###', '###.###.###', '###.###.###', '###.###.###', '###.###.###', '###########', '.####.####.'],
}


def glyph(letter: str, small: bool) -> tuple[set, int]:
    rows = (SMALL_GLYPHS if small else LARGE_GLYPHS)[letter]
    mask = {(x, y) for y, row in enumerate(rows) for x, key in enumerate(row) if key == '#'}
    return mask, len(rows[0])


def paint_letters(canvas: Canvas, word: str, x: int, y: int, small: bool, chips: list[tuple[int, int]]) -> tuple[int, set]:
    """Paint the word with bevel light, returning its right edge and its mask."""
    union: set = set()
    cursor = x
    gap = 2 if small else 3
    for letter in word:
        mask, width = glyph(letter, small)
        union |= {(cursor + gx, y + gy) for gx, gy in mask}
        cursor += width + gap
    for (px, py) in union:
        up, down = (px, py - 1) in union, (px, py + 1) in union
        right = (px + 1, py) in union
        if not up:
            colour = PAINT['lit']
        elif not down:
            colour = PAINT['deep']
        elif not small and not (px, py + 2) in union:
            colour = PAINT['shade']
        elif not right:
            colour = PAINT['shade']
        else:
            colour = PAINT['face']
        canvas.set(px, py, colour)
    # Worn paint: a few authored dents along top edges, where a tool or a
    # boot knocked the paint off: bare steel with the paint edge below it.
    for column, length in chips:
        for xx in range(x + column, x + column + length):
            tops = [py for (px, py) in union if px == xx]
            if not tops:
                continue
            top = min(tops)
            canvas.set(xx, top, CHIP)
            if (xx, top + 1) in union:
                canvas.set(xx, top + 1, PAINT['shade'])
    return cursor - gap, union


def ink_outline(canvas: Canvas, mask: set) -> None:
    for (px, py) in list(mask):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
            at = (px + dx, py + dy)
            if at not in mask:
                canvas.set(at[0], at[1], INK)


# ---------------------------------------------------------------- plate
def nameplate(canvas: Canvas, x0: int, y0: int, x1: int, y1: int, small: bool) -> set:
    plate: set = set()
    chamfer = 1 if small else 2
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            corner = min(x - x0, x1 - x) + min(y - y0, y1 - y)
            if corner >= chamfer:
                plate.add((x, y))
    for (x, y) in plate:
        if (x, y - 1) not in plate:
            colour = LIT_EDGE
        elif (x, y - 2) not in plate:
            colour = STEEL['edge']
        elif (x, y + 1) not in plate:
            colour = STEEL['deep']
        elif (x, y + 2) not in plate:
            colour = STEEL['dark']
        else:
            colour = STEEL['mid']
        canvas.set(x, y, colour)
    if not small:
        # Brushed band: one lighter rolled-steel line, broken at the welds.
        band = y0 + 4
        for x in range(x0 + 3, x1 - 2):
            if (x - x0) % 37 not in (0, 1):
                canvas.set(x, band, STEEL['light'])
        # Welded seam with a rust bleed and rivets at the plate end.
        for y in range(y0 + 2, y1 - 1):
            canvas.set(x1 - 9, y, STEEL['dark'])
        canvas.set(x1 - 9, y1 - 2, RUST)
        canvas.set(x1 - 8, y1 - 2, RUST)
        for ry in (y0 + 4, y1 - 5):
            rivet(canvas, x1 - 5, ry, False)
    else:
        canvas.set(x1 - 2, (y0 + y1) // 2, STEEL['edge'])
    return plate


def rivet(canvas: Canvas, x: int, y: int, small: bool) -> None:
    if small:
        canvas.set(x, y, STEEL['edge'])
        return
    canvas.set(x, y, STEEL['edge'])
    canvas.set(x + 1, y, STEEL['light'])
    canvas.set(x, y + 1, STEEL['light'])
    canvas.set(x + 1, y + 1, STEEL['deep'])


# ---------------------------------------------------------------- emblem
def octagon(size: int, cut: int) -> set:
    shape: set = set()
    for y in range(size):
        for x in range(size):
            if min(x, size - 1 - x) + min(y, size - 1 - y) >= cut:
                shape.add((x, y))
    return shape


def emblem(canvas: Canvas, ox: int, oy: int, size: int, small: bool) -> set:
    cut = size * 3 // 10
    outer = octagon(size, cut)
    ring = 3 if small else 6
    inner = {(x, y) for x, y in outer if all((x + dx, y + dy) in outer for dx in range(-ring, ring + 1, ring) for dy in range(-ring, ring + 1, ring))}
    centre = (size - 1) / 2.0
    for (x, y) in outer:
        at = (ox + x, oy + y)
        if (x, y) in inner:
            # Hatch plate: lit from the upper left in three stepped bands.
            light = (x - centre) + (y - centre)
            colour = STEEL['light'] if light < -size * 0.30 else (STEEL['mid'] if light < size * 0.22 else STEEL['dark'])
            canvas.set(*at, colour)
        else:
            # Hazard rim: amber/black diagonals, stepping 45 degrees.
            stripe = ((x + y) // (2 if small else 4)) % 2 == 0
            colour = AMBER['mid'] if stripe else HAZARD_DARK
            if stripe and (x, y - 1) not in outer:
                colour = AMBER['light']
            elif stripe and (x + 1, y + 1) not in outer:
                colour = AMBER['deep']
            canvas.set(*at, colour)
    # Ink between rim and plate so both read as separate parts.
    for (x, y) in inner:
        if any((x + dx, y + dy) not in inner for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            canvas.set(ox + x, oy + y, INK if small else STEEL['deep'])
    if not small:
        # Eight rivets around the hatch plate.
        r = size / 2 - ring - 3.2
        for i in range(8):
            a = math.pi / 8 + i * math.pi / 4
            rivet(canvas, round(ox + centre + math.cos(a) * r - 0.5), round(oy + centre + math.sin(a) * r - 0.5), False)
    hardhat(canvas, ox, oy, size, small)
    return {(ox + x, oy + y) for x, y in outer}


def hardhat(canvas: Canvas, ox: int, oy: int, size: int, small: bool) -> None:
    """The crew's amber hardhat in side view (facing right, like the sprites),
    its lamp lit. Small cut: hand-set rows. Title cut: a dome shaded by its
    normal against the upper-left key light, a raised rib, a long front brim."""
    palette = {'#': INK, 'm': AMBER['mid'], 'l': AMBER['light'], 'L': AMBER['hot'], 'd': AMBER['deep'], 'W': LAMP, 's': STEEL['light']}
    if small:
        rows = [
            '...####....',
            '..#lLmm#...',
            '.#lmmmmd###',
            '.#mmmmmd#W#',
            '.#mmmmdd###',
            '###########',
            '#dddddddd#.',
            '##########.',
        ]
        x0 = ox + (size - 11) // 2
        y0 = oy + (size - 8) // 2
        for y, row in enumerate(rows):
            for x, key in enumerate(row):
                if key in palette:
                    canvas.set(x0 + x, y0 + y, palette[key])
        return
    width, height = 26, 18
    x0 = ox + (size - width) // 2
    y0 = oy + (size - height) // 2 + 1
    cx, cy, rx, ry = 11.5, 12.0, 10.6, 11.0
    dome: set = set()
    for y in range(0, 12):
        for x in range(0, 24):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                dome.add((x, y))
    shade: dict = {}
    for (x, y) in dome:
        nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
        light = -0.62 * nx - 0.78 * ny
        shade[(x, y)] = 'L' if light > 0.86 else ('l' if light > 0.55 else ('m' if light > -0.05 else 'd'))
    # Raised rib over the crown: a lit stripe with its own shadow side.
    for (x, y) in dome:
        if x in (9, 10):
            shade[(x, y)] = 'L' if y < 4 else 'l'
        elif x == 11 and y > 1:
            shade[(x, y)] = 'd'
    # Brim: a long front peak (right) and a short rear lip, two texels deep.
    brim = {(x, y) for y in (12, 13) for x in range(-1, 26 if y == 12 else 25)}
    for (x, y) in brim:
        shade[(x, y)] = 'l' if y == 12 and x < 20 else ('m' if y == 12 else 'd')
    body = dome | brim
    for (x, y) in body:
        canvas.set(x0 + x, y0 + y, palette[shade[(x, y)]])
    for (x, y) in body:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (x + dx, y + dy) not in body:
                canvas.set(x0 + x + dx, y0 + y + dy, INK)
    # Lamp housing on the front of the dome, lens lit, three stepped rays.
    lx, ly = x0 + 19, y0 + 4
    for yy in range(5):
        for xx in range(5):
            canvas.set(lx + xx, ly + yy, INK)
    for yy in range(1, 4):
        for xx in range(1, 4):
            canvas.set(lx + xx, ly + yy, LAMP)
    canvas.set(lx + 2, ly + 2, (255, 255, 236, 255))
    canvas.set(lx + 1, ly + 1, STEEL['edge'])
    for i, colour in enumerate((AMBER['hot'], AMBER['light'], AMBER['mid'])):
        canvas.set(lx + 5 + i, ly + 2, colour)
        if i < 2:
            canvas.set(lx + 5 + i, ly + 1, AMBER['light'] if i == 0 else AMBER['mid'])
            canvas.set(lx + 5 + i, ly + 3, AMBER['light'] if i == 0 else AMBER['mid'])


# ---------------------------------------------------------------- lockups
# (word column, width): dents on the B bar, the N stem, the E bar, the C bar,
# the second R and the W.
LARGE_CHIPS = [(10, 2), (42, 1), (87, 2), (132, 2), (152, 1), (190, 2)]


def lockup(small: bool) -> Image.Image:
    if small:
        H, size = 11, 22
        width, height = 160, 24
    else:
        H, size = 24, 48
        width, height = 290, 50
    canvas = Canvas(width, height)
    letters_x = size - (3 if small else 8) + (5 if small else 14)
    letters_y = (height - H) // 2
    # Measure the word first so the plate fits it exactly.
    probe = Canvas(width, height)
    right, _ = paint_letters(probe, 'BUNKERCREW', letters_x, letters_y, small, [])
    plate_top = letters_y + (2 if small else 4)
    plate_bottom = letters_y + H - (3 if small else 5)
    plate = nameplate(canvas, size // 2, plate_top, right + (4 if small else 14), plate_bottom, small)
    ink_outline(canvas, plate)
    # Re-paint the plate over its own outline pass (the outline only adds ink outside).
    nameplate(canvas, size // 2, plate_top, right + (4 if small else 14), plate_bottom, small)
    _, word = paint_letters(canvas, 'BUNKERCREW', letters_x, letters_y, small, [] if small else LARGE_CHIPS)
    ink_outline(canvas, word)
    paint_letters(canvas, 'BUNKERCREW', letters_x, letters_y, small, [] if small else LARGE_CHIPS)
    hatch = emblem(canvas, 1, (height - size) // 2, size, small)
    ink_outline(canvas, hatch)
    emblem(canvas, 1, (height - size) // 2, size, small)
    image = canvas.image()
    return image.crop(image.getbbox())


def main(output=None) -> None:
    destination = Path(output) if output is not None else DEST
    destination.mkdir(parents=True, exist_ok=True)
    outputs = {}
    for name, small in (('bunkercrew_logo_v1.png', False), ('bunkercrew_logo_v1_small.png', True)):
        image = lockup(small)
        path = destination / name
        image.save(path, optimize=False)
        outputs[name] = {'size': list(image.size), 'colours': len({p for p in (image.get_flattened_data() if hasattr(image, 'get_flattened_data') else image.getdata()) if p[3]}), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    source = Path(__file__)
    metadata = {
        'assets': outputs,
        'tool': 'tools/build_bunkercrew_logo.py (Pillow)',
        'tool_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'construction': 'Native pixel construction, no font, no image input and no generated reference: chamfered stencil plate capitals with bevel light and authored paint chips, a riveted steel nameplate, an octagonal blast-hatch emblem with a hazard rim and the crew hardhat with its lit lamp. 1-texel ink contour, hard alpha, no anti-aliasing.',
        'palette': 'Style bible §4: steel #3b453d ramp, worn ivory paint (UI ivory family), hardhat amber ramp, sodium-lit plate edge, rust #8a4a2a.',
        'use': 'Title lockup and small lockup (reads at 1x within 160 px). Drawn at whole real pixels per texel (UiArt.pixel_fit). The previous title was the Signal Bold wordmark (UiArt.wordmark), which is kept unchanged as a fallback.',
        'license': 'Original Bunkercrew artwork. Distribution only together with Bunkercrew.',
    }
    (destination / 'bunkercrew_logo_v1.source.json').write_text(json.dumps(metadata, indent=2) + '\n')
    for name, data in outputs.items():
        print(name, data['size'], data['colours'], 'colours')


if __name__ == '__main__':
    main()
