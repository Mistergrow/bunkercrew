#!/usr/bin/env python3
"""Crew bust portraits for the menus.

v2 (default, pass 6A-2): every bust is the crew member's own in-game sprite
geometry, re-drawn at twice the sprite density from the canonical author
(assets/workers/generate_character_workers.py; its head() and torso() calls
are recorded and replayed scaled, see generate_crew_layers.Recorder), in the
sprite's palette ramps, with the sprite's chibi proportions and 1-pixel ink
contours, plus a hand-set portrait pass at bust density: eyes under the
brim, ears, mouths, hair strands, helmet light, cloth folds and seams. No
reference image, no resampling, no dither. Written to portraits_v2.png.

v1 (--v1): the earlier reduction of the production references, below.

Reduce the crew art-direction references to pixel-exact bust portraits.

Inputs are the full-body production references of the eight identities: the
original three in assets/workers/identities/ and the five added for this atlas
in assets/workers/portraits/references/ (generated in the same style, with the
runtime sprite of each identity as its identity reference; prompts and task
IDs in portraits_v1.source.json). Every figure is measured the same way: its
alpha silhouette is eroded so thin parts (an aerial, a cable) cannot move the
crop, the head is located in the top rows, and a square bust scaled to the
figure height is reduced to SIZE pixels with premultiplied area averaging, a
mild tone lift, hard alpha and a re-inked 1 px charcoal outline. The crop
extends below the square and is cut after the outline, so the chest runs out
of the frame instead of ending on an inked edge. The menus draw these at
whole multiples of their size. Requires Pillow.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageColor, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
WORKERS = ROOT / 'assets/workers'
DEST = WORKERS / 'portraits'
ORDER = ['mara', 'branko', 'ivo', 'nora', 'levin', 'selma', 'oskar', 'rika']
ORIGINAL = {'mara', 'branko', 'ivo'}
SIZE = 80
# Share of the figure height that the square bust covers, and how far the head
# centre sits behind the bust centre (the figures face right; the backpack
# and shoulders need room on the left).
BUST = 0.34
LEAD = 0.06
HEAD_ROWS = 0.10
INK = (20, 26, 27, 255)

GENERATED = {
    'nora': {'task_id': '01a1dd01-3881-742c-98dc-b60a5da03fb0', 'character': 'Character NORA: adult woman engineer, medium build, wide bronze-brown helmet with a broad brim and a small pale badge on the front, short dark brown bob haircut, warm light skin, calm focused expression, high-collared slate blue-grey engineer vest over a slate shirt, a small measuring gauge on the chest, dark grey-green trousers, durable brown boots, a long cream blueprint tube carried diagonally on her back and a rectangular brown document folio at her side.'},
    'levin': {'task_id': '01a1dd02-3a95-76f6-b46f-c9204d9c6849', 'character': 'Character LEVIN: slim adult man scout and radio operator, a pointed olive-green hood pulled up with the side of his face exposed, short stubble, warm tan skin, alert watchful expression, a short asymmetric olive field poncho over his upper body, a muted neck scarf, slate blue-grey trousers, durable brown boots, a compact radio pack on his back with a long thin aerial rising high above his head.'},
    'selma': {'task_id': '01a1dd02-3ec9-755b-957a-f2a6f0a5e7a0', 'character': 'Character SELMA: adult woman field medic, medium build, a soft rounded ivory medical cap with a small pale-green cross, short auburn bob haircut, warm light skin, composed caring expression, a long sage-green field jacket with a pale medical insignia on the sleeve, dark grey-violet trousers, durable brown boots, a large cream canvas medical bag with a pale cross carried at her back hip on a strap.'},
    'oskar': {'task_id': '01a1dd02-413d-72b3-8f2a-0a98aea1275d', 'character': 'Character OSKAR: broad heavy-set older adult man, veteran miner, a khaki-olive dust helmet with a tall raised square headlamp on top, short greying moustache, weathered tan skin, steady stern expression, heavy grey-khaki work overalls, a long brown leather miner apron reaching to his knees, dark trousers, heavy boots, a tall squared brown dust pack on his back and a tool strap across his chest.'},
    'rika': {'task_id': '01a1dd02-4395-7508-9702-a78f51ee4e39', 'character': 'Character RIKA: lean adult woman electrician, a ribbed dark slate-blue beanie, cropped dark hair, warm light skin, quick sharp expression, a copper headset with a small boom microphone over her ear, a short ochre insulated electrician jacket, dark brown-grey trousers, durable brown boots, a round copper cable reel with wound cable carried at her back hip and a small pouch for a handheld meter on her belt.'},
}
PROMPT = ('Game character production reference for a 2D side-view industrial bunker survival game. Draw ONE full-body worker facing right in relaxed side profile, from head to boot soles, on a plain transparent background. '
    'Match the FIRST reference image exactly in rendering style, outline weight, pixel cluster size, lighting and level of detail: restrained gritty pixel art like late-1990s detailed 2D PC games, crisp hand-placed pixel clusters, dark charcoal outlines, earthy industrial palette, realistic adult proportions with a slightly enlarged readable head, no smooth painting, no 3D. '
    'The SECOND reference image is the small in-game sprite of this exact character: copy its identity, colours, headwear and equipment faithfully. {character} '
    'Unarmed, hands relaxed. Slight left-front light. No scene, floor, cast shadow, letters, logos, panels, grid, extra poses or extra figures.')


def source_path(identity: str) -> Path:
    if identity in ORIGINAL: return WORKERS / 'identities' / f'{identity}.png'
    return DEST / 'references' / f'{identity}.png'


def bust(figure: Image.Image) -> Image.Image:
    solid = figure.getchannel('A').point(lambda a: 255 if a > 96 else 0)
    core = solid.filter(ImageFilter.MinFilter(9))
    box = core.getbbox()
    height = box[3] - box[1]
    head = core.crop((box[0], box[1], box[2], box[1] + int(height * HEAD_ROWS))).getbbox()
    centre = box[0] + (head[0] + head[2]) / 2.0
    side = height * BUST
    left = centre - side * (0.5 + LEAD)
    top = box[1] - side * 0.05
    # The crop runs 18% below the square: cut after inking (see reduce()).
    return figure.crop((round(left), round(top), round(left + side), round(top + side * 1.18)))


def reduce(crop: Image.Image) -> Image.Image:
    tall = round(SIZE * crop.height / crop.width)
    small = crop.convert('RGBa').resize((SIZE, tall), Image.BOX).convert('RGBA')
    alpha = small.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    colour = ImageEnhance.Brightness(small.convert('RGB')).enhance(1.12)
    colour = ImageEnhance.Contrast(colour).enhance(1.15)
    body = colour.convert('RGBA')
    body.putalpha(alpha)
    pixels = body.load()
    solid = {(x, y) for x in range(SIZE) for y in range(tall) if pixels[x, y][3]}
    for x in range(SIZE):
        for y in range(tall):
            if (x, y) not in solid and any((x + dx, y + dy) in solid for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                pixels[x, y] = INK
    return body.crop((0, 0, SIZE, SIZE))


def main_v1() -> None:
    atlas = Image.new('RGBA', (SIZE * len(ORDER), SIZE), (0, 0, 0, 0))
    regions: dict[str, list[int]] = {}
    sources: dict[str, dict] = {}
    for index, identity in enumerate(ORDER):
        path = source_path(identity)
        atlas.paste(reduce(bust(Image.open(path).convert('RGBA'))), (index * SIZE, 0))
        regions[identity] = [index * SIZE, 0, SIZE, SIZE]
        entry = {'file': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        if identity in ORIGINAL:
            entry['provenance'] = 'assets/workers/identities/prompts.json'
        else:
            entry.update({'generator': 'Meshy image-to-image, model gpt-image-2', 'generated_at': '2026-11-15',
                'task_id': GENERATED[identity]['task_id'],
                'reference_images': ['assets/workers/identities/mara.png (style)', f'assets/workers/{identity}_body.png + {identity}_arms.png idle frame 0, 12x nearest (identity)'],
                'prompt': PROMPT.format(character=GENERATED[identity]['character'])})
        sources[identity] = entry
    target = DEST / 'portraits_v1.png'
    atlas.save(target, optimize=False)
    metadata = {
        'asset': target.name,
        'purpose': 'Original Bunkercrew crew bust portraits for the menus, drawn at whole multiples of their size.',
        'atlas_size': list(atlas.size),
        'cell_size': [SIZE, SIZE],
        'regions': regions,
        'sources': sources,
        'references': 'No third-party artwork used. The style reference is the project\'s own crew production art; identity references are the runtime sprites.',
        'postprocessing': 'tools/build_crew_portraits.py: eroded-silhouette head location, square bust at 34% of the figure height, premultiplied area reduction to 80 px, mild tone lift, hard alpha, re-inked 1 px outline, chest cut after inking. Full generated references preserved in references/ and excluded from export.',
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    }
    (DEST / 'portraits_v1.source.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + '\n')
    print('Built', target, atlas.size)


# ---------------------------------------------------------------- v2
SCALE = 2
# Sprite pixel (feet anchor 48, 90 in a 112 cell) at the bust's top-left:
# the window spans the hardhat crown to just above the belt, face to pack.
WINDOW = (48 - 25, 90 - 68)
HEAD = (1, -57)  # head origin of the authored head piece (sprite texels)


def _author():
    import sys
    sys.path.insert(0, str(WORKERS))
    import generate_character_workers as author
    import generate_crew_layers as layers
    return author, layers


def _replay_scaled(draw, calls, origin):
    ox, oy = origin
    half = 0.5 * (SCALE - 1)

    def at(point):
        return ((point[0] - ox) * SCALE + half, (point[1] - oy) * SCALE + half)
    for name, points, kwargs in calls:
        if name in ('rectangle', 'ellipse'):
            (x0, y0), (x1, y1) = points
            getattr(draw, name)([(x0 - ox) * SCALE, (y0 - oy) * SCALE, (x1 - ox) * SCALE + SCALE - 1, (y1 - oy) * SCALE + SCALE - 1], **kwargs)
        elif name == 'polygon':
            draw.polygon([at(p) for p in points], **kwargs)
        else:
            # Outline loops stay one pixel (the ink contour); strokes scale.
            closed = len(points) > 2 and points[0] == points[-1]
            stroke = dict(kwargs)
            stroke['width'] = 1 if closed else int(kwargs.get('width', 1)) * SCALE
            draw.line([at(p) for p in points], **stroke)


class Bust:
    """Bust-pixel helpers around the head origin (sprite texel u, v -> bust)."""
    def __init__(self, image, palette, identity):
        self.image, self.c, self.id = image, palette, identity
        self.draw = ImageDraw.Draw(image)
        self.fx = (WORKERS_OX + HEAD[0] - WINDOW[0]) * SCALE
        self.fy = (WORKERS_OY + HEAD[1] - WINDOW[1]) * SCALE

    def at(self, u, v):
        return (self.fx + round(u * SCALE), self.fy + round(v * SCALE))

    def px(self, u, v, colour, w=1, h=1):
        x, y = self.at(u, v)
        self.draw.rectangle([x, y, x + w - 1, y + h - 1], fill=colour)

    def opaque(self, x, y):
        return 0 <= x < self.image.width and 0 <= y < self.image.height and self.image.getpixel((x, y))[3] > 0


WORKERS_OX, WORKERS_OY = 48, 90
# Per identity: hanging hair tones for strands.
HAIR = {'mara': ('#322a29', '#66503a'), 'nora': ('#372d2b', '#685047'), 'selma': ('#6a3e2c', '#a16a45'), 'rika': ('#312c2c', '#675143')}
WOMEN = {'mara', 'nora', 'selma', 'rika'}
PROFILE_HAT = {}
# The sprite face is ten primitives (outlined jaw polygon, lit polygon, cheek,
# nose, ear, ear light, eye, catchlight, mouth); the bust draws its own face in
# their place at bust density, in the same ramps, with the same long nose.
FACE_CALLS = 10


def _face_profile(identity):
    """Profile outline in bust pixels from the head origin (2 per texel)."""
    jaw = 3 if identity in ('branko', 'oskar') else 0
    chin = -1 if identity in WOMEN else 0
    return [(-12, -2), (10, -3), (12, 4), (13, 8), (13, 10), (16, 12), (19, 14), (20, 16), (18, 17), (15, 17),
            (14, 18), (15, 20), (13, 21), (14 + chin, 23), (12 + chin, 25 + jaw // 2), (9, 27 + jaw // 2), (4, 28 + jaw // 2),
            (0, 29 + jaw // 2), (-5, 27), (-9, 24), (-12, 19), (-14, 13), (-14, 7), (-13, 2)]


def _face(bust):
    """A side-profile face at bust density: lit front planes, shaded jaw and
    back of the head, cheek and nose ridge light, eye with brow and
    catchlight, nostril, lips, ear. Whole pixels; sprite skin ramps."""
    c, ident, draw = bust.c, bust.id, bust.draw
    fx, fy = bust.fx, bust.fy

    def to(points):
        return [(fx + x, fy + y) for x, y in points]
    outline = _face_profile(ident)
    draw.polygon(to(outline), fill=c['skin'])
    # Shade bands: the jaw's underside and the back of the head turn away
    # from the upper-left key light; the area under the nose is in shade.
    mask = Image.new('L', bust.image.size)
    ImageDraw.Draw(mask).polygon(to(outline), fill=255)
    pixels = bust.image.load()
    for y in range(fy - 2, fy + 31):
        for x in range(fx - 15, fx + 22):
            if not (0 <= x < bust.image.width and 0 <= y < bust.image.height) or not mask.getpixel((x, y)):
                continue
            u, v = x - fx, y - fy
            if v >= 24 - (u + 14) // 9 or u <= -9 or (v == 17 and 14 <= u <= 17):
                pixels[x, y] = c['skin_shadow']
            elif (u - 4) ** 2 / 6.0 + (v - 14) ** 2 / 2.5 <= 1.0 or (v - 3 <= u - 10 <= v - 2 and 11 <= v <= 14):
                pixels[x, y] = c['skin_light']
            elif v <= 1 and 2 <= u <= 9:
                pixels[x, y] = c['skin_light']
    draw.line(to(outline + outline[:1]), fill=c['ink'], width=1)
    # Ear: an outlined shell with its inner curve and a lit rim.
    if ident != 'levin':
        ear = [(-10, 10), (-6, 9), (-5, 12), (-6, 17), (-9, 18), (-11, 15)]
        draw.polygon(to(ear), fill=c['skin'], outline=c['ink'])
        bust.draw.line(to([(-8, 12), (-7, 14), (-8, 16)]), fill=c['skin_shadow'], width=1)
        bust.draw.point(to([(-9, 11), (-10, 13)]), fill=c['skin_light'])
    # Eye under the brim: brow, lid shade, dark eye, catchlight, lower lid.
    if ident != 'ivo':
        brow = c['deep'] if ident not in HAIR else ImageColor.getrgb(HAIR[ident][0]) + (255,)
        draw.line(to([(6, 8), (11, 8)]), fill=brow, width=1)
        draw.line(to([(6, 9), (11, 9)]), fill=c['skin_shadow'], width=1)
        draw.rectangle([fx + 8, fy + 10, fx + 9, fy + 12], fill=c['ink'])
        draw.point((fx + 9, fy + 10), fill=c['skin_light'])
        draw.line(to([(7, 13), (10, 13)]), fill=c['skin_shadow'], width=1)
        if ident in WOMEN:
            draw.line(to([(10, 9), (11, 10)]), fill=c['ink'], width=1)
    # Nostril and lips; the beard (Branko) and moustache (Oskar) draw over.
    draw.point((fx + 16, fy + 16), fill=c['ink'])
    draw.line(to([(10, 21), (13, 21)]), fill=c['deep'], width=1)
    lip = c['red'] if ident in WOMEN and ident != 'selma' else c['skin_shadow']
    draw.line(to([(12, 22), (13, 22)]), fill=lip, width=1)
    draw.point((fx + 13, fy + 20), fill=c['skin_light'])


def _hair_strands(bust):
    if bust.id not in HAIR:
        return
    tone, light = (ImageColor.getrgb(v) + (255,) for v in HAIR[bust.id])
    if bust.id == 'mara':
        # Braid: crossing strands and a second amber tie further down.
        for v in (13, 18, 23, 28, 33, 38):
            x, y = bust.at(-11.0, 0)
            bust.draw.line([(x - 1 + (v - 13) // 12, bust.fy + v), (x + 3 + (v - 13) // 12, bust.fy + v - 2)], fill=light, width=1)
        bust.px(-11.0, 19.0, PROFILE_HAT['mara'][1], 4, 1)
    else:
        for u, top, length in ((-10.5, 4, 14), (-8.5, 6, 12)):
            x, y = bust.at(u, 0)
            bust.draw.line([(x, bust.fy + top), (x, bust.fy + top + length)], fill=light, width=1)


def _helmet_light(bust):
    hat = PROFILE_HAT.get(bust.id)
    if not hat or bust.id in ('levin', 'rika', 'ivo'):
        return
    # A lit rim along the crown and a scuff on the shell.
    bust.draw.line([bust.at(-6.0, -5.0), bust.at(-2.0, -7.5)], fill=hat[3], width=1)
    bust.px(5.0, -3.0, hat[0], 2, 1)


def _cloth_pass(bust):
    """Folds and seams on the coat, in its own shade tones."""
    c = bust.c
    sv = -42 - HEAD[1]  # shoulder row relative to the head origin
    bust.draw.line([bust.at(-3.0, sv + 4.0), bust.at(-2.5, sv + 10.0)], fill=c['deep'], width=1)
    bust.draw.line([bust.at(-2.5, sv + 4.0), bust.at(-2.0, sv + 9.0)], fill=c['light'], width=1)
    bust.draw.line([bust.at(2.0, sv + 1.0), bust.at(5.0, sv + 1.0)], fill=c['shadow'], width=1)


def _silhouette_ink(image, ink):
    pixels = image.load()
    width, height = image.size
    solid = {(x, y) for x in range(width) for y in range(height) if pixels[x, y][3]}
    for x in range(width):
        for y in range(height):
            if (x, y) not in solid and any((x + dx, y + dy) in solid for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                pixels[x, y] = ink


def bust_v2(identity):
    author, layers = _author()
    rig = author.rig
    rig.C = dict(author.BASE_PALETTE, **author.PROFILES[identity]['palette'])
    palette = {key: ImageColor.getrgb(value) + (255,) for key, value in rig.C.items()}
    PROFILE_HAT[identity] = [ImageColor.getrgb(v) + (255,) for v in author.PROFILES[identity]['hat']]
    torso = layers.record(lambda d: author.torso(d, (0, -42), (0, -25), identity))
    head = layers.record(lambda d: author.head(d, *HEAD, identity))
    face = next(index for index, call in enumerate(head) if call[0] == 'polygon' and call[2].get('fill') == rig.C['skin_shadow'])
    if head[face + FACE_CALLS - 1][2].get('fill') != rig.C['deep']:
        raise ValueError(f'{identity}: the authored face no longer has its {FACE_CALLS} primitives')
    tall = Image.new('RGBA', (SIZE, SIZE + 12))
    draw = ImageDraw.Draw(tall)
    _replay_scaled(draw, torso, WINDOW)
    bust = Bust(tall, palette, identity)
    _cloth_pass(bust)
    _replay_scaled(draw, head[:face], WINDOW)
    _hair_strands(bust)
    _face(bust)
    _replay_scaled(draw, head[face + FACE_CALLS:], WINDOW)
    _helmet_light(bust)
    _silhouette_ink(tall, palette['ink'])
    # The chest runs out of the frame: cut after inking (as v1).
    return tall.crop((0, 0, SIZE, SIZE))


def main_v2(output=None) -> None:
    destination = Path(output) if output is not None else DEST
    destination.mkdir(parents=True, exist_ok=True)
    author, layers = _author()
    atlas = Image.new('RGBA', (SIZE * len(ORDER), SIZE), (0, 0, 0, 0))
    regions: dict[str, list[int]] = {}
    for index, identity in enumerate(ORDER):
        atlas.alpha_composite(bust_v2(identity), (index * SIZE, 0))
        regions[identity] = [index * SIZE, 0, SIZE, SIZE]
    target = destination / 'portraits_v2.png'
    atlas.save(target, optimize=False)
    source = Path(__file__)
    metadata = {
        'asset': target.name,
        'purpose': 'Crew bust portraits for the menus in the in-game sprite style, drawn at whole multiples of their size.',
        'atlas_size': list(atlas.size),
        'cell_size': [SIZE, SIZE],
        'regions': regions,
        'tool': 'tools/build_crew_portraits.py (main_v2, Pillow)',
        'tool_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'geometry': 'assets/workers/generate_character_workers.py head()/torso() calls recorded by generate_crew_layers.Recorder and replayed at %dx sprite density' % SCALE,
        'geometry_sha256': hashlib.sha256((WORKERS / 'generate_character_workers.py').read_bytes()).hexdigest(),
        'construction': 'Sprite geometry at 2x density in the sprite palette ramps (character_visuals.json), 1-pixel ink contours kept unscaled, a hand-set portrait pass (eyes, ears, mouth, nose shade, hair strands, braid ties, helmet light, cloth fold and collar seam) and a 1-pixel ink silhouette; chest cut at the frame edge after inking. No reference image, no generated image, no resampling, no dither.',
        'previous': 'portraits_v1.png (reduced production references, kept unchanged for comparison)',
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'license': author.LICENSE,
    }
    (destination / 'portraits_v2.source.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + '\n')
    print('Built', target, atlas.size)


if __name__ == '__main__':
    import sys
    main_v1() if '--v1' in sys.argv[1:] else main_v2()
