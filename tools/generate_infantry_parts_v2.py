#!/usr/bin/env python3
"""Author infantry_parts_v2.png: hand-pixelled field kits for the six hostile roles.

infantry_parts_v1.png was a renderer export of shared procedural panels: every
role wore the same olive coat and a tan block for a face. This script places
every texel of the replacement by hand (the character maps below), one texel
per world unit, so the six roles differ in silhouette, headgear, face, kit,
weapon and colour:

    rifle_guard   olive-grey  dome helmet with cover band and red unit mark,
                              chin strap, open face; rucksack with bedroll;
                              assault rifle with curved magazine
    grenadier     khaki-brown flat combat helmet over a full respirator with
                              red-amber lens and forward filter; grenade
                              bandolier and round carrier; revolver launcher
                              with a fluted six-shot cylinder
    scout         sand        soft peaked cap, flip-down goggles, face scarf
                              whose tails trail behind; slim smock, radio pack
                              with a whip aerial; short carbine
    heavy_gunner  slate steel bulky helmet with ear cup and a visor slit,
                              plate vest with pauldron; ammunition box pack;
                              belt-fed gun with a perforated barrel jacket
    marksman      ghillie     wide-brim hat with ragged strands, painted face;
                              camouflage cape; long scoped rifle
    combat_medic  ivory/grey  ivory cap with neck curtain, round spectacles;
                              ivory vest with a green cross; large medical bag;
                              compact carbine

The atlas keeps the v1 layout (Atlas.tile_index, 64-texel tiles, 16 columns,
head/torso/rear origin (32, 32), weapon origin (12, 16)), the v1 grip, muzzle,
crown and hand points, so the articulated rig, hitboxes, weather segments and
combat anchors are unchanged. Light comes from the upper left; every piece has
a 1-texel ink contour (added from its own alpha) and a lit top edge, enemies
carry a small red hostile accent (style bible sections 3 and 4).

Head variants: seven squad slots (skin tone, facial hair, kit wear) times five
cloth sways (scarf tails, strands, curtains move by whole texels). Rear kits:
five sways. Rebuild with
    python3 tools/generate_infantry_parts_v2.py
then python3 tools/bake_infantry_turns.py for the turned attitudes. Pillow.
"""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "assets/enemies/infantry_parts_v2.png"
ROLES = ("rifle_guard", "grenadier", "scout", "heavy_gunner", "marksman", "combat_medic")
TILE, COLUMNS, SIZE = 64, 16, 1024
HEADS, SWAYS = 7, 5
BODY_ORIGIN, GUN_ORIGIN = (32, 32), (12, 16)

INK = "1b211f"
RED = {"r": "8c3628", "R": "c65b47", "Q": "f08a5c"}
SKIN = (  # shadow, mid, light per squad tone
    {"s": "8a5c40", "S": "b4845c", "L": "d8ac80"},
    {"s": "6e4630", "S": "9a6a48", "L": "c08e64"},
    {"s": "4e3224", "S": "70492f", "L": "946642"},
)
EYES = {"e": "231d1b", "w": "e9dfc4", "u": "2e2420"}
GUN = {"1": "1c2023", "2": "2c3134", "3": "454b4f", "4": "6d7377", "5": "a3a9a8",
       "6": "3d2e22", "7": "5b4430", "8": "7c5f43", "9": "a3815a",
       "y": "8a6a32", "Y": "c79a52", "Z": "e8c47a"}

# Per-role ramps. Head letters: h/H/I/J headgear dark..top light, d brim shade,
# b band, C/c/D collar or scarf, t strap. Body letters: 0-4 uniform darkest to
# highlight, a/A/B second material, k/q/x role specials.
PALETTES = {
    "rifle_guard": {
        "h": "3a4336", "H": "536048", "I": "6e7b5c", "J": "929c77", "d": "222820", "b": "5d553f",
        "c": "4b4838", "C": "686450", "D": "898466", "t": "35291f",
        "0": "232a25", "1": "36403a", "2": "4f5a50", "3": "6b786a", "4": "8f9c88",
        "a": "4a3b2b", "A": "6a553c", "B": "8c7352", "k": "7d7a5e", "q": "a7a07c",
    },
    "grenadier": {
        "h": "4a4232", "H": "675c45", "I": "857a5c", "J": "a69b77", "d": "28241c", "b": "3f3a2c",
        "m": "262b28", "M": "3d4541", "n": "5c6761", "g": "6e2a20", "G": "e86a46", "f": "353a35", "F": "7d847b",
        "c": "3c3528", "C": "554a37", "D": "6e604a", "t": "2c241b",
        "0": "2b241b", "1": "443828", "2": "62523a", "3": "826f50", "4": "a38f6b",
        "a": "3a3f37", "A": "545b50", "B": "717a6c", "k": "c79a52", "q": "8a6a32",
    },
    "scout": {
        "h": "5c5741", "H": "7a7556", "I": "9a9472", "J": "bab38e", "d": "34311f", "b": "4a4636",
        "o": "26241f", "O": "57534a", "g": "742a1e", "G": "ee8550",
        "c": "463d2d", "C": "645640", "D": "857558", "t": "3a3024",
        "0": "34321f", "1": "524f39", "2": "726e52", "3": "939072", "4": "b4b090",
        "a": "3d3a2e", "A": "5a5544", "B": "7a755e", "k": "2e3330", "q": "8d968e",
    },
    "heavy_gunner": {
        "h": "2c3439", "H": "434e55", "I": "5e6b71", "J": "86938f", "d": "161b1e", "b": "3a4440",
        "v": "121619", "V": "262d31", "o": "3d4347", "O": "6b7378",
        "c": "39402f", "C": "4e5741", "D": "677157", "t": "2a2620",
        "0": "1f2522", "1": "303a33", "2": "465246", "3": "5f6b5c", "4": "7d8a78",
        "a": "293136", "A": "414c53", "B": "5d6a70", "k": "7f8c88", "q": "a8b1aa",
    },
    "marksman": {
        "h": "363d25", "H": "4e5935", "I": "6a7646", "J": "89935b", "d": "1f2416", "b": "4a3c26",
        "x": "4a3b24", "X": "6c5733", "P": "36402a",
        "c": "3f3a26", "C": "5a5235", "D": "766c48", "t": "2e2619",
        "0": "232818", "1": "343c24", "2": "4a5533", "3": "65713f", "4": "838e54",
        "a": "43361f", "A": "62502f", "B": "81693f", "k": "2d3326", "q": "7b8f84",
    },
    "combat_medic": {
        "h": "8a8570", "H": "b4ae94", "I": "cec8ad", "J": "e6e0c6", "d": "4e4b3f", "b": "a29d85",
        "o": "2a2925", "q": "3d6a4a", "Q": "5d9068",
        "c": "8f8a74", "C": "b0aa90", "D": "cfc9ae", "t": "3a3127",
        "0": "283029", "1": "3b4640", "2": "56625b", "3": "717e75", "4": "909c92",
        "a": "8c8770", "A": "b6b097", "B": "d8d2b8", "k": "3d6a4a", "x": "5d9068",
    },
}

# ---------------------------------------------------------------------------
# Head maps. Column 12 is head-local x = 0, row 15 is head-local y = 0 (the
# head origin used by GroundInfantryArt.head_transform). Facing right.
# '~' marks texels that belong to trailing cloth and move with the sway.
HEAD_ORIGIN = (12, 15)
HEADS_MAP = {
    "rifle_guard": [
        "..........................",
        "..........................",
        "..........JJJJJ...........",
        "........JJIIIIIJJ.........",
        ".......JIIHHHHHHIJ........",
        "......JIHHHHHHHHHHI.......",
        ".....IIHHHHHHHHHHHHI......",
        ".....IHHHHHHHHHHHHHHH.....",
        "....IHHHHHHHHHHHHHHHH.....",
        "....HHHHHHHHHHHHHHHHHh....",
        "....hrrRbbbbbbbbbbbbbh....",
        "...hhhhhhhhhhhhhhhhhhhh...",
        "..dddddddddddddddddddddd..",
        "......uuutsssssssssss.....",
        "......uuutSSSSSSSeeeSS....",
        "......uusstSSSSSSSewS.....",
        "......usSsStSSSSSSSSSLL...",
        ".......sssSStSSSSSSSSSLL..",
        ".......sSssSStSSSSSSss....",
        ".......sssssSStSSSSSSL....",
        "........ssssSSStSSeeS.....",
        ".........sssssSStSSSL.....",
        "..........ssssssttsS......",
        "........CCCCCCCCCCCC......",
        ".......cCCCCDDDCCCCC......",
        ".......ccCCCCCCCCCc.......",
        "..........................",
    ],
    "grenadier": [
        "..........................",
        "..........................",
        "..........................",
        "........JJJJJJJJJ.........",
        ".......JIIIIIIIIIJ........",
        "......JIHHHHHHHHHHI.......",
        "......IHHHHHHHHHHHHI......",
        ".....IHHHHHHHHHHHHHHI.....",
        ".....HHHHHHHHHHHHHHHH.....",
        "....hHHHHHHHHHHHHHHHHh....",
        "....hrrRbbbbbbbbbbbbbh....",
        "...hhhhhhhhhhhhhhhhhhhhh..",
        "..hhddddddddddddddddddd...",
        "....mMMMMMMMMMMMMnnM......",
        "...mMMMMMMMMMMMMggggM.....",
        "...mMtMMMMMMMMMgGGggn.....",
        "...mMtMMMMMMMMMggggMMn....",
        "...mMtMMMMMMMMMMMMMMffF...",
        "...mmMtMMMMMMMMMMMffFFFF..",
        "....mMtMMMMMMMMMMfFFfFFFF.",
        "....mmMtMMMMMMMMMfFFfFFFF.",
        ".....mmMMMMMMMMMMffFfFFF..",
        "......mmmmMMMMMMMMffff....",
        "........CCCCCCCCCCC.......",
        ".......cCCCCDDDCCCC.......",
        ".......ccCCCCCCCCc........",
        "..........................",
    ],
    "scout": [
        "..........................",
        "..........................",
        "..........................",
        "..........................",
        "..........................",
        "..........................",
        "........JJJJJJJJ..........",
        ".......JIIIIIIIIIJ........",
        "......IIHHHHHHHHHHI.......",
        ".....IHHHHHHHHHHHHHH......",
        ".....HHHHHHHHHHHHHHHHhh...",
        ".....hbbbbbbbbbbbbbhhhhhh.",
        "....uuuoooooooooddddddd...",
        "....uuuOOOOOOOOOogggggo...",
        "....uusStSSSSSSSoGGgggo...",
        "....usSsStSSSSSSSoooooo...",
        ".....sssSStSSSSSSSSSSSLL..",
        ".....~DDDDDDDDDDDDDDDDLL..",
        "....~~CCCCCCCCCCCCCCCCDC..",
        "...~~~CCCcccCCCCCCCCCCC...",
        "...~~cCCCCCCccccCCCCCC....",
        "...~~..cCCCCCCCCCcccC.....",
        "....~....ccCCCCCCCcc......",
        "........cCCCCCCCCCC.......",
        ".......cCCCCDDDCCCC.......",
        ".......ccCCCCCCCCc........",
        "..........................",
    ],
    "heavy_gunner": [
        "..........................",
        ".........JJJJJJ...........",
        ".......JJIIIIIIJJ.........",
        "......JIIHHHHHHIIJ........",
        ".....JIHHHHHHHHHHHI.......",
        "....JIHHHHHHHHHHHHHI......",
        "....IHHHHHHHHHHHHHHHI.....",
        "...IHHHHHHHHHHHHHHHHH.....",
        "...HHHHHHHHHHHHHHHHHHh....",
        "...HHHHHHHHHHHHHHHHHHH....",
        "...hHHHHHHHHHHHHVVVVVVV...",
        "...hHHoOOOoHHHHVVVVVVVVV..",
        "...hHoOOOOOoHHHVvvvvvvvV..",
        "...hHoOOhOOoHHHVrRQQRrrV..",
        "...hhoOOOOOohHHVvvvvvvvV..",
        "...hhhoOOOohhHHVVVVVVVVV..",
        "....hhhoooohhHHHVVVVVVV...",
        "....hhhhhhhhhHHHHtSSSSL...",
        ".....dhhhhhhhhhHHtSSSSs...",
        ".........ssSSStSSSSSs.....",
        "..........sssSStSSeeS.....",
        "...........ssssStSSSL.....",
        "............ssssttsS......",
        "........CCCCCCCCCCCC......",
        ".......cCCCCDDDCCCCC......",
        ".......ccCCCCCCCCCc.......",
        "..........................",
    ],
    "marksman": [
        "..........................",
        "..........................",
        "..........................",
        "..........~..~............",
        ".........~X.~x..~.........",
        "........XJJJJXJJJ~........",
        ".......JIIIIIIIIIIJ.......",
        "......IIHHHHHHHHHHHI......",
        "......IHHHHHHHHHHHHH......",
        "......HHHHHHHHHHHHHHh.....",
        ".....hbbbbbbbbbbbbbbbh....",
        "..IHHHHHHHHHHHHHHHHHHHHHH.",
        ".hhhhhhhhhhhhhhhhhhhhhhhhh",
        ".~d.dddddddddddddddddd..d.",
        "..~...uuussssssssssss.....",
        "......uuuSSSPPPSSSeeeS....",
        "......uussSSSSSSSSSewS....",
        "......usSsSSSPPPPPSSSSLL..",
        ".......sssSSSSSSSSSSSSSLL.",
        ".......sSssSSSSPPPPSSss...",
        ".......sssssSSSSSSSSSSL...",
        "........ssssSSSSSSSeeS....",
        ".........sssssSSSSSSL.....",
        "..........sssssssssS......",
        "........CCCCCCCCCCCC......",
        ".......cCCCCDDDCCCCC......",
        ".......ccCCCCCCCCCc.......",
    ],
    "combat_medic": [
        "..........................",
        "..........................",
        "..........................",
        "..........................",
        "..........................",
        ".........JJJJJJJ..........",
        ".......JJIIIIIIIJJ........",
        "......JIIHHHHHHHHIJ.......",
        ".....JIHHHHHHqHHHHHI......",
        ".....IHHHHHHqqqHHHHH......",
        ".....HHHHHHHHqHHHHHHHh....",
        ".....hhbbbbbbbbbbbbbhhhh..",
        "...~hHhhhhhhhhhhhdddddddd.",
        "...~HHHussssssssssss......",
        "...~HIHuSSSSSSSSoooSS.....",
        "...~HIHuoooooooowSSoS.....",
        "...~HIHusSSSSSSSoooSSLL...",
        "...~HIHHssSSSSSSSSSSSSLL..",
        "...~HHHHsSsSSSSSSSSSss....",
        "...~hHHHssssSSSSSSSSSL....",
        "....hhHHHsssSSSSSSeeS.....",
        ".....hhhHssssSSSSSSSL.....",
        "..........ssssssssssS.....",
        "........CCCCCCCCCCCC......",
        ".......cCCCCDDDCCCCC......",
        ".......ccCCCCCCCCCc.......",
        "..........................",
    ],
}


def _ink(image):
    """1-texel exterior contour from the piece's own alpha (4-neighbour)."""
    width, height = image.size
    source = image.load()
    out = image.copy()
    target = out.load()
    ink = _rgb(INK) + (255,)
    for y in range(height):
        for x in range(width):
            if source[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                u, v = x + dx, y + dy
                if 0 <= u < width and 0 <= v < height and source[u, v][3]:
                    target[x, y] = ink
                    break
    return out


def _rgb(hex_colour):
    return tuple(int(hex_colour[i:i + 2], 16) for i in (0, 2, 4))


def stamp(image, rows, origin, at, palette, shift=None):
    """Write a character map into `image`; map texel `origin` lands on `at`.
    `shift(x, y, char)` may move or drop single texels (cloth sway)."""
    pixels = image.load()
    for row, line in enumerate(rows):
        for column, char in enumerate(line):
            if char == ".":
                continue
            x, y = at[0] + column - origin[0], at[1] + row - origin[1]
            if shift is not None:
                moved = shift(column - origin[0], row - origin[1], char)
                if moved is None:
                    continue
                x, y, char = at[0] + moved[0], at[1] + moved[1], moved[2]
            colour = palette.get(char)
            if colour is None:
                continue
            if 0 <= x < image.size[0] and 0 <= y < image.size[1]:
                pixels[x, y] = _rgb(colour) + (255,)


def role_palette(role, slot=0):
    palette = dict(GUN)
    palette.update(EYES)
    palette.update(RED)
    palette.update(SKIN[(slot * 2 + ROLES.index(role)) % len(SKIN)])
    palette.update(PALETTES[role])
    palette["K"] = INK
    return palette


def head_piece(role, slot, sway):
    """One head on a 64-texel tile, origin (32, 32)."""
    image = Image.new("RGBA", (TILE, TILE))
    palette = role_palette(role, slot)
    rows = HEADS_MAP[role]
    stamp(image, [line.replace("~", ".") for line in rows], HEAD_ORIGIN, BODY_ORIGIN, palette)
    # Trailing cloth (~) drifts behind the head by whole texels, more towards
    # its tips; each row stays one contiguous run so it never tears off.
    pixels = image.load()
    colour = _rgb(palette[_cloth_char(role)]) + (255,)
    for row, line in enumerate(rows):
        columns = [column - HEAD_ORIGIN[0] for column, char in enumerate(line) if char == "~"]
        if not columns:
            continue
        def moved(x):
            return x - round(sway * min(1.0, max(0.2, (-5 - x) / 5.0)))
        low, high = min(moved(min(columns)), min(columns)), max(columns)
        y = BODY_ORIGIN[1] + row - HEAD_ORIGIN[1]
        for x in range(low, high + 1):
            pixels[BODY_ORIGIN[0] + x, y] = colour
    _slot_details(image, role, slot, palette)
    return _ink(image)


def _cloth_char(role):
    return {"scout": "C", "marksman": "X", "combat_medic": "H"}.get(role, "C")


def _slot_details(image, role, slot, palette):
    """Squad variety that does not change the silhouette: facial hair, wear."""
    pixels = image.load()
    ox, oy = BODY_ORIGIN

    def put(x, y, char):
        if 0 <= ox + x < TILE and 0 <= oy + y < TILE and pixels[ox + x, oy + y][3]:
            pixels[ox + x, oy + y] = _rgb(palette[char]) + (255,)
    if role in ("rifle_guard", "heavy_gunner", "marksman", "combat_medic"):
        if slot % 3 == 1:   # moustache
            for x in (6, 7, 8):
                put(x, 4, "u")
        elif slot % 3 == 2:  # stubble along the jaw
            for x, y in ((0, 6), (2, 6), (4, 6), (1, 7), (3, 7), (6, 5)):
                put(x, y, "s")
    if role in ("rifle_guard", "grenadier", "heavy_gunner"):
        # Helmet wear: one scuffed texel and one dent shadow per slot.
        put(-4 + slot, -9 + slot % 3, "I")
        put(-2 + slot, -7 + (slot * 2) % 3, "h")


class Canvas:
    """A character grid in piece-local texels (x right, y down)."""
    def __init__(self):
        self.cells = {}

    def put(self, x, y, char):
        self.cells[(int(x), int(y))] = char

    def rect(self, x0, y0, x1, y1, char):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, char)

    def bar(self, x0, y0, x1, y1, top, mid, bottom, left=None, right=None):
        """A shaded block: lit top row, body, shadowed bottom row."""
        self.rect(x0, y0, x1, y1, mid)
        if left: self.rect(x0, y0, x0, y1, left)
        if right: self.rect(x1, y0, x1, y1, right)
        self.rect(x0, y0, x1, y0, top)
        if y1 > y0: self.rect(x0, y1, x1, y1, bottom)

    def line(self, a, b, char, width=1):
        """Stepped pixel line (Bresenham), optionally thickened downwards."""
        (x0, y0), (x1, y1) = a, b
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        error = dx + dy
        while True:
            for extra in range(width):
                self.put(x0, y0 + extra, char)
            if (x0, y0) == (x1, y1):
                break
            twice = 2 * error
            if twice >= dy:
                error += dy
                x0 += sx
            if twice <= dx:
                error += dx
                y0 += sy

    def rows(self, rows, origin_x, origin_y):
        """Overlay a character map; '.' stays untouched."""
        for row, line in enumerate(rows):
            for column, char in enumerate(line):
                if char != ".":
                    self.put(column - origin_x, row - origin_y, char)

    def has(self, x, y):
        return (x, y) in self.cells

    def render(self, palette, origin, ink=True):
        image = Image.new("RGBA", (TILE, TILE))
        pixels = image.load()
        for (x, y), char in self.cells.items():
            u, v = origin[0] + x, origin[1] + y
            if char in palette and 0 <= u < TILE and 0 <= v < TILE:
                pixels[u, v] = _rgb(palette[char]) + (255,)
        return _ink(image) if ink else image


# ---------------------------------------------------------------------------
# Torsos: origin at the shoulder (WorkerPoseArt.torso_transform), facing right.
# Width profiles (left, right) per y; light from the upper left.
def _profile(rows):
    profile = {}
    for y0, y1, left, right in rows:
        for y in range(y0, y1 + 1):
            profile[y] = (left, right)
    return profile


PROFILES = {
    "rifle_guard": _profile([(-6, -6, -3, 3), (-5, -5, -6, 5), (-4, -4, -8, 6), (-3, -1, -9, 7), (0, 21, -9, 8), (22, 22, -8, 7), (23, 23, -7, 6)]),
    "grenadier": _profile([(-6, -6, -3, 3), (-5, -5, -7, 5), (-4, -4, -9, 7), (-3, -1, -10, 8), (0, 18, -10, 9), (19, 23, -11, 9), (24, 24, -11, 8), (25, 25, -10, 6)]),
    "scout": _profile([(-6, -6, -3, 2), (-5, -5, -5, 4), (-4, -4, -7, 5), (-3, -1, -8, 6), (0, 21, -8, 7), (22, 22, -7, 6)]),
    "heavy_gunner": _profile([(-6, -6, -4, 3), (-5, -5, -8, 6), (-4, -4, -10, 8), (-3, -1, -11, 9), (0, 15, -11, 10), (16, 22, -10, 9), (23, 23, -9, 8)]),
    "marksman": _profile([(-6, -6, -4, 3), (-5, -5, -8, 6), (-4, -4, -10, 7), (-3, 20, -11, 8), (21, 22, -10, 8)]),
    "combat_medic": _profile([(-6, -6, -3, 3), (-5, -5, -6, 5), (-4, -4, -8, 6), (-3, -1, -9, 7), (0, 21, -9, 8), (22, 22, -8, 7), (23, 23, -7, 6)]),
}


def _cloth_body(canvas, profile):
    ys = sorted(profile)
    for y in ys:
        left, right = profile[y]
        for x in range(left, right + 1):
            char = "2"
            if x <= left + 1: char = "3"
            if x >= right: char = "1"
            if y >= ys[-1] - 1: char = "1"
            canvas.put(x, y, char)
        # Lit top edge on every texel whose upper neighbour is empty.
    for (x, y) in list(canvas.cells):
        if not canvas.has(x, y - 1):
            canvas.put(x, y, "4" if x < 2 else "3")


def torso_piece(role):
    canvas = Canvas()
    profile = PROFILES[role]
    _cloth_body(canvas, profile)
    getattr(sys.modules[__name__], "_torso_" + role)(canvas)
    return canvas.render(role_palette(role), BODY_ORIGIN)


def _belt(canvas, left, right, y, buckle=True):
    canvas.rect(left, y, right, y + 1, "a")
    canvas.rect(left, y, right, y, "A")
    if buckle:
        canvas.rect(right - 4, y, right - 3, y + 1, "Y")
        canvas.put(right - 4, y, "Z")


def _torso_rifle_guard(c):
    c.rect(-3, -6, 3, -5, "C")
    c.rect(-2, -6, 2, -6, "D")
    # Collar seam and crease.
    for y in (5, 8, 11):
        c.put(-3, y, "1")
    # Web strap from the back shoulder to the front hip.
    c.line((-7, -3), (6, 15), "a", 2)
    c.line((-6, -3), (6, 14), "A")
    # Two magazine pouches on the chest.
    for x0 in (1, 5):
        c.bar(x0, 5, x0 + 2, 11, "B", "A", "a", right="a")
        c.rect(x0, 6, x0 + 2, 6, "a")
    _belt(c, -9, 8, 15)
    c.rect(-9, 17, -6, 20, "a")  # canteen pouch on the hip
    c.rect(-9, 17, -6, 17, "A")
    # Red unit patch on the upper sleeve seam.
    c.rect(-7, 0, -6, 1, "R")
    c.put(-6, 1, "r")


def _torso_grenadier(c):
    c.rect(-3, -6, 3, -4, "C")
    c.rect(-2, -6, 2, -6, "D")
    # Coat front placket with buttons and the split hem.
    c.line((7, -2), (7, 24), "1")
    for y in (2, 7, 12):
        c.put(6, y, "0")
    c.line((3, 19), (2, 25), "1")
    # Grenade bandolier: canvas strap with brass-cased rounds.
    c.line((-8, -3), (7, 16), "a", 3)
    for index in range(5):
        x, y = -6 + index * 3, -1 + index * 3 + (index + 1) // 2
        c.rect(x, y, x + 1, y + 3, "Y")
        c.put(x, y, "Z")
        c.put(x + 1, y + 3, "y")
        c.rect(x, y - 1, x + 1, y - 1, "A")
    _belt(c, -10, 9, 17)
    c.rect(-10, 15, -10, 16, "3")


def _torso_scout(c):
    c.rect(-3, -6, 2, -5, "C")
    # Smock pocket and drawcord.
    c.bar(-6, 6, -3, 10, "3", "2", "1")
    c.line((-8, 12), (7, 12), "1")
    # Chest rig: one radio pouch and binocular case.
    c.line((-6, -3), (5, 13), "a")
    c.bar(2, 3, 6, 9, "B", "A", "a", right="a")
    c.rect(3, 4, 5, 4, "a")
    c.put(4, 7, "q")
    _belt(c, -8, 7, 15, False)
    c.rect(-2, 15, 0, 16, "Y")


def _torso_heavy_gunner(c):
    c.rect(-4, -6, 3, -5, "C")
    # Chest and back plates over the fatigues.
    c.bar(-2, -2, 10, 14, "B", "A", "a", left="B", right="a")
    c.bar(-11, -1, -6, 13, "B", "A", "a", left="q", right="a")
    for y in (4, 9):
        c.rect(-1, y, 9, y, "a")
        c.rect(-1, y + 1, 9, y + 1, "B")
    for x, y in ((0, 0), (8, 0), (0, 12), (8, 12), (-10, 1), (-7, 11)):
        c.put(x, y, "q")
    # Pauldron over the shoulder, lit along the top.
    c.rows([
        "...BBBBBB...",
        ".BqqqqqqqB..",
        "BqAAAAAAAAB.",
        "BAAAAAAAAAAa",
        "aAAARrAAAAAa",
        ".aaAAAAAAaa.",
        "...aaaaaa...",
    ], 8, 6)
    _belt(c, -10, 9, 16)
    for x0 in (-8, -4, 2):
        c.bar(x0, 18, x0 + 2, 21, "A", "a", "a")


def _torso_marksman(c):
    c.rect(-4, -6, 3, -5, "C")
    # Ghillie cape: a fixed mottle of greens and browns, ragged hem.
    for (x, y), char in list(c.cells.items()):
        noise = (x * 7 + y * 13 + (x * y) % 5) % 11
        if char in "234" and noise in (0, 4):
            c.put(x, y, "A" if noise == 0 else "1")
        elif char in "23" and noise == 7:
            c.put(x, y, "3")
    for x in range(-11, 9):
        drop = (x * 5) % 4
        for y in range(19, 21 + drop):
            c.put(x, y, "a" if y == 20 + drop else ("1" if (x + y) % 3 else "A"))
    # Leather sling with five cartridges.
    c.line((-8, -3), (7, 13), "a", 2)
    for index in range(5):
        c.rect(-4 + index * 2, 1 + index * 2, -4 + index * 2, 2 + index * 2, "Y")
        c.put(-4 + index * 2, 1 + index * 2, "Z")


def _torso_combat_medic(c):
    c.rect(-3, -6, 3, -5, "C")
    c.rect(-2, -6, 2, -6, "D")
    # Ivory front panel with the green cross.
    c.bar(0, -2, 8, 13, "B", "A", "a", left="B", right="a")
    c.rect(3, 3, 5, 9, "k")
    c.rect(1, 5, 7, 7, "k")
    c.rect(4, 4, 4, 8, "x")
    c.rect(2, 6, 6, 6, "x")
    c.line((-6, -3), (-1, 14), "1")
    _belt(c, -9, 8, 15, False)
    for x0 in (-8, -4):
        c.bar(x0, 17, x0 + 2, 20, "B", "A", "a")


# ---------------------------------------------------------------------------
# Rear kits: origin at the shoulder, behind the coat. `sway` (-1..3) moves
# trailing cloth and aerials by whole texels.
def rear_piece(role, sway):
    canvas = Canvas()
    getattr(sys.modules[__name__], "_rear_" + role)(canvas, sway)
    return canvas.render(role_palette(role), BODY_ORIGIN)


def _rear_rifle_guard(c, sway):
    c.bar(-15, 0, -7, 15, "B", "A", "a", left="B", right="a")
    c.rect(-15, 6, -7, 6, "a")
    c.bar(-14, 8, -11, 13, "B", "A", "a")
    # Bedroll strapped on top.
    c.rows([
        ".kkkkkkkkk.",
        "kqqqqqqqqqk",
        "kkkkkkkkkkk",
        ".kkkkkkkkk.",
    ], 16, 4)
    for x in (-13, -9):
        c.rect(x, -4, x, -1, "a")
    c.line((-15, 15), (-16 - max(0, sway), 19), "a")


def _rear_grenadier(c, sway):
    c.bar(-17, -1, -9, 18, "B", "A", "a", left="B", right="a")
    for index in range(4):
        x = -16 + index * 2
        c.rect(x, -4, x + 1, -2, "Y")
        c.put(x, -4, "Z")
        c.put(x + 1, -2, "y")
    for y in (5, 11):
        c.rect(-17, y, -9, y, "a")
        c.rect(-15, y + 1, -12, y + 3, "q")
        c.put(-15, y + 1, "k")
    c.line((-9, 18), (-8 - max(0, sway), 22), "a")


def _rear_scout(c, sway):
    c.bar(-14, 1, -8, 12, "B", "A", "a", left="B", right="a")
    c.rect(-13, 4, -9, 5, "k")
    c.put(-12, 4, "R")
    # Whip aerial: leans back with the sway, light tip.
    top = (-14 - sway, -24)
    c.line((-12, 1), top, "k")
    c.put(top[0], top[1], "q")
    c.put(top[0], top[1] + 1, "q")


def _rear_heavy_gunner(c, sway):
    c.bar(-20, -3, -9, 16, "B", "A", "a", left="q", right="a")
    c.rect(-20, 2, -9, 2, "a")
    c.rect(-20, 3, -9, 3, "B")
    for x, y in ((-19, -2), (-10, -2), (-19, 15), (-10, 15)):
        c.put(x, y, "k")
    # Feed chute towards the gun (the belt itself is drawn live).
    c.bar(-11, 7, -8, 11, "A", "a", "a")
    c.rect(-17, 6, -12, 8, "R")
    c.rect(-17, 6, -12, 6, "Q")


def _rear_marksman(c, sway):
    lean = max(0, sway)
    points = []
    for y in range(-3, 24):
        reach = -11 - (y + 3) * (5 + lean) // 26
        for x in range(reach, -6):
            noise = (x * 7 + y * 13 + (x * y) % 5) % 11
            c.put(x, y, "1" if noise in (1, 5) else ("A" if noise == 0 else ("3" if noise == 8 else "2")))
        points.append((reach, y))
    for x in range(-18 - lean, -6):
        length = (x * 5) % 4
        for y in range(22, 24 + length):
            if c.has(x, y - 1) or y == 22:
                c.put(x, y, "a" if y == 23 + length else "1")
    for reach, y in points:
        if y % 3 == 0:
            c.put(reach - 1, y, "X")


def _rear_combat_medic(c, sway):
    c.bar(-19, 0, -8, 16, "B", "A", "a", left="B", right="a")
    c.rect(-15, 4, -13, 12, "k")
    c.rect(-17, 7, -11, 9, "k")
    c.rect(-14, 5, -14, 11, "x")
    c.rect(-16, 8, -12, 8, "x")
    c.rows([
        ".2222222222.",
        "233333333332",
        "222222222222",
        ".1111111111.",
    ], 19, 4)
    c.line((-8, 16), (-7 - max(0, sway), 20), "a")


# ---------------------------------------------------------------------------
# Weapons: origin (12, 16) of the tile; rear grip (-1, 5), fore grip (13, 4),
# muzzles as InfantryRoleArt (32 / 27 / 44 / 49 / 25).
def gun_piece(role):
    canvas = Canvas()
    getattr(sys.modules[__name__], "_gun_" + role)(canvas)
    # Digits are blued steel and wood here, not the uniform ramp.
    palette = role_palette(role)
    palette.update(GUN)
    return canvas.render(palette, GUN_ORIGIN)


def _grip(c, x=-2):
    c.rows([
        "2333",
        "2332",
        ".233",
        ".223",
        ".222",
    ], -x, -2)


def _gun_rifle_guard(c):
    c.bar(-11, -2, -3, 3, "9", "8", "7", left="2")          # stock
    c.rect(-11, -2, -11, 3, "2")
    c.line((-9, 3), (-4, 1), "7")
    c.bar(-3, -3, 13, 2, "4", "3", "2")                       # receiver
    c.rect(4, -1, 8, -1, "1")
    c.rect(0, -5, 2, -4, "3")
    c.put(1, -5, "4")
    _grip(c)
    c.rows([                                                  # curved magazine
        "33332",
        "33322",
        ".3332",
        ".33322",
        "..3332",
        "..33322",
        "...2222",
    ], -4, -3)
    c.bar(13, -2, 24, 2, "9", "8", "7")                      # handguard
    for x in (15, 18, 21):
        c.put(x, 0, "6")
    c.rect(23, -5, 24, -3, "3")                               # front sight
    c.bar(25, -1, 30, 0, "4", "3", "2")                       # barrel
    c.bar(30, -2, 32, 1, "4", "2", "1")                       # muzzle device
    c.rect(32, -1, 32, 0, "1")


def _gun_grenadier(c):
    c.line((-11, -2), (-3, -2), "3")                          # skeletal stock
    c.line((-11, 3), (-3, 1), "2")
    c.rect(-11, -2, -11, 3, "2")
    c.rect(-10, -1, -10, 2, "7")
    c.bar(-3, -4, 4, 3, "4", "3", "2")                        # frame
    _grip(c)
    c.rows([                                                  # fluted cylinder
        "..yYYYYYYYy..",
        ".45454545454.",
        "4343434343432",
        "4343434343432",
        "4343434343432",
        "4343434343432",
        "4343434343432",
        "4343434343432",
        "4343434343432",
        ".23232323232.",
        "..yyyyyyyyy..",
    ], -3, 6)
    c.bar(16, -3, 29, 2, "4", "3", "2")                       # barrel with shroud rings
    for x in (18, 21, 24, 27):
        c.rect(x, -3, x, 2, "2")
        c.put(x, -3, "3")
    c.rows([                                                  # flared muzzle
        "445",
        "432",
        "321",
        "321",
        "321",
        "321",
        "321",
        "222",
    ], -29, 4)
    c.bar(11, 3, 14, 8, "8", "7", "6")                        # fore grip
    c.rect(-1, 4, 1, 4, "R")                                  # red safety


def _gun_scout(c):
    c.line((-11, -1), (-4, -1), "3")                          # wire stock
    c.line((-11, 3), (-4, 1), "3")
    c.rect(-11, -1, -11, 3, "2")
    c.bar(-4, -3, 10, 2, "4", "3", "2")                       # receiver
    c.rect(2, -1, 5, -1, "1")
    c.bar(1, -6, 6, -4, "4", "2", "1")                        # red dot sight
    c.put(6, -5, "R")
    _grip(c)
    c.bar(3, 3, 6, 11, "3", "2", "1", left="3")               # straight magazine
    c.bar(10, -2, 19, 1, "8", "7", "6")                       # handguard
    c.bar(20, -2, 27, 1, "4", "2", "1")                       # suppressor
    c.rect(27, -1, 27, 0, "1")
    c.put(23, -2, "3")


def _gun_heavy_gunner(c):
    c.bar(-11, -3, -3, 4, "4", "3", "2", left="2")            # polymer stock
    c.line((-10, 4), (-4, 2), "1")
    c.bar(-3, -5, 16, 3, "4", "3", "2")                       # receiver
    c.bar(2, -7, 14, -5, "5", "4", "3")                       # feed cover
    c.rect(15, -8, 21, -8, "3")                               # carry handle
    c.rect(15, -7, 15, -5, "3")
    c.rect(21, -7, 21, -5, "3")
    _grip(c)
    c.bar(3, 3, 13, 13, "4", "3", "2", left="4", right="2")   # ammunition box
    c.rect(3, 7, 13, 7, "2")
    c.rect(4, 3, 6, 4, "Y")
    c.put(4, 3, "Z")
    c.bar(16, -3, 38, 2, "4", "3", "2")                       # perforated jacket
    for x in range(18, 37, 3):
        c.put(x, -1, "1")
        c.put(x + 1, 1, "1")
    c.bar(38, -1, 41, 0, "4", "3", "2")                       # barrel
    c.bar(41, -2, 44, 1, "4", "2", "1")                       # flash hider
    c.put(42, -1, "1")
    c.put(42, 0, "1")
    c.rect(44, -1, 44, 0, "1")


def _gun_marksman(c):
    c.bar(-11, -2, 0, 4, "9", "8", "7", left="6")             # wooden stock
    c.rect(-9, -4, -3, -3, "8")                               # cheek rest
    c.rect(-9, -4, -3, -4, "9")
    c.rect(-6, 1, -3, 2, "6")                                 # thumb hole
    c.bar(0, -2, 16, 2, "4", "3", "2")                        # receiver
    c.rect(6, 3, 7, 4, "4")                                   # bolt knob
    c.rect(8, 3, 11, 5, "2")                                  # short magazine
    _grip(c)
    c.rows([                                                  # scope
        "4444.............4444",
        "45433333333333333454R",
        "43322222222222222332Q",
        "4322...........2232R.",
    ], -1, 10)
    for x in (4, 12):
        c.rect(x, -6, x, -3, "1")
    c.bar(16, -2, 30, 2, "9", "8", "7")                       # fore-end
    c.bar(30, -1, 45, 0, "4", "3", "2")                       # barrel
    c.bar(45, -2, 49, 1, "4", "2", "1")                       # muzzle brake
    c.put(47, -2, "1")
    c.put(47, 1, "1")
    c.rect(49, -1, 49, 0, "1")
    c.line((24, 3), (33, 3), "2")                             # folded bipod


def _gun_combat_medic(c):
    c.line((-11, -1), (-4, -1), "3")                          # folded stock
    c.line((-11, 1), (-4, 1), "2")
    c.rect(-11, -1, -11, 1, "2")
    c.bar(-4, -3, 9, 2, "4", "3", "2")                        # receiver
    c.rect(1, -1, 4, -1, "1")
    _grip(c)
    c.bar(2, 3, 5, 10, "3", "2", "1", left="3")               # magazine
    c.bar(9, -2, 22, 1, "4", "3", "2")                        # vented shroud
    for x in range(11, 21, 3):
        c.put(x, 0, "1")
    c.rect(13, -2, 16, 1, "B")                                # ivory tape
    c.rect(13, -2, 16, -2, "A")
    c.bar(22, -1, 25, 0, "4", "3", "2")
    c.rect(25, -1, 25, 0, "1")


# ---------------------------------------------------------------------------
def tile_index(part, role, slot=0, sway_index=1):
    role = ROLES.index(role)
    if part == "head": return role * 35 + slot * 5 + sway_index
    if part == "torso": return 210 + role
    if part == "rear": return 216 + role * 5 + sway_index
    return 246 + role


def build():
    atlas = Image.new("RGBA", (SIZE, SIZE))
    for role in ROLES:
        pieces = [("torso", 0, 1, torso_piece(role)), ("gun", 0, 1, gun_piece(role))]
        for sway_index in range(SWAYS):
            pieces.append(("rear", 0, sway_index, rear_piece(role, sway_index - 1)))
            for slot in range(HEADS):
                pieces.append(("head", slot, sway_index, head_piece(role, slot, sway_index - 1)))
        for part, slot, sway_index, image in pieces:
            index = tile_index(part, role, slot, sway_index)
            atlas.alpha_composite(image, (index % COLUMNS * TILE, index // COLUMNS * TILE))
    return atlas


def main(output=None):
    target = Path(output) / OUTPUT.name if output is not None else OUTPUT
    atlas = build()
    atlas.save(target)
    notice = {
        "asset": OUTPUT.name,
        "generator": "tools/generate_infantry_parts_v2.py",
        "method": "Hand-placed native pixel art (character maps and stepped primitives in the generator), one texel per world unit, 1-texel ink contour from each piece's alpha. No generated imagery, no downscaling.",
        "license": "Original Bunkercrew project art.",
        "replaces": "infantry_parts_v1.png (kept for comparison; tools/bake_infantry_art.gd)",
        "layout": {"tile": TILE, "columns": COLUMNS, "size": [SIZE, SIZE], "roles": list(ROLES),
                   "head": "role*35 + slot*5 + sway", "torso": "210 + role", "rear": "216 + role*5 + sway", "gun": "246 + role",
                   "body_origin": list(BODY_ORIGIN), "gun_origin": list(GUN_ORIGIN), "heads": HEADS, "sways": SWAYS},
        "source_sha256": {"tools/generate_infantry_parts_v2.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    target.with_suffix(".source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"AUTHORED INFANTRY PARTS V2: {atlas.size} -> {target}")


def preview(path, scale=6):
    """Contact sheet: per role head (3 slots), torso, rear, weapon, mock figure."""
    sheet = Image.new("RGBA", (len(ROLES) * 96, 260), (88, 104, 124, 255))
    for r, role in enumerate(ROLES):
        x0 = r * 96
        figure = Image.new("RGBA", (96, 96))
        shoulder = (40, 40)
        figure.alpha_composite(rear_piece(role, 0), (shoulder[0] - 32, shoulder[1] - 32))
        figure.alpha_composite(torso_piece(role), (shoulder[0] - 32, shoulder[1] - 32))
        figure.alpha_composite(head_piece(role, 0, 0), (shoulder[0] + 1 - 32, shoulder[1] - 14 - 32))
        figure.alpha_composite(gun_piece(role), (shoulder[0] + 4 - 12, shoulder[1] + 7 - 16))
        sheet.alpha_composite(figure, (x0, 0))
        sheet.alpha_composite(gun_piece(role), (x0 + 16, 100))
        for slot in range(3):
            sheet.alpha_composite(head_piece(role, slot, 2).crop((14, 14, 46, 46)), (x0 + slot * 32, 150))
        sheet.alpha_composite(rear_piece(role, 3).crop((0, 0, 48, 64)), (x0, 190))
        sheet.alpha_composite(torso_piece(role).crop((16, 16, 48, 64)), (x0 + 50, 190))
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST).save(path)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "--output":
        main(sys.argv[2])
    else:
        main()
