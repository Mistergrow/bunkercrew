#!/usr/bin/env python3
"""Reduce the generated material illustrations to pixel-exact UI icon sizes.

Input is the preserved original (assets/ui/materials/materials_v1_source.png,
2x2 cells of 512 px). Each cell is cropped to its silhouette and reduced to
40 and 28 pixel icons: area-averaged with premultiplied alpha, a mild
tone lift, hard alpha and a re-inked one-pixel charcoal outline. The interface
draws these 1:1, never engine-scaled. Requires Pillow.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/ui/materials'
SOURCE = DEST / 'materials_v1_source.png'
KINDS = ['steel', 'concrete', 'scrap', 'ammo']  # row-major cells of the source
# 18 and 14 px reductions were built and rejected: at HUD size the bold authored
# sprites in assets/workers/material_props.png read better than any reduction.
SIZES = [40, 28]
INK = (20, 26, 27, 255)


def reduce(cell: Image.Image, size: int) -> Image.Image:
    # Keep the run of occupied rows that holds the picture; the original has a
    # detached speck under the bucket that would otherwise shift the crop.
    mask = cell.getchannel('A').point(lambda a: 255 if a > 40 else 0)
    box = mask.getbbox()
    rows = [mask.crop((0, y, mask.width, y + 1)).getbbox() is not None for y in range(mask.height)]
    best = (0, 0)
    start = None
    for y, filled in enumerate(rows + [False]):
        if filled and start is None: start = y
        if not filled and start is not None:
            if y - start > best[1] - best[0]: best = (start, y)
            start = None
    cell = cell.crop((box[0], best[0], box[2], best[1]))
    inner = size - 2
    scale = inner / max(cell.size)
    target = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
    # Plain premultiplied area reduction keeps the painted shading. Sharpening
    # or palette reduction at these sizes turned every icon into brown noise.
    small = cell.convert('RGBa').resize(target, Image.BOX).convert('RGBA')
    alpha = small.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    colour = ImageEnhance.Brightness(small.convert('RGB')).enhance(1.25)
    colour = ImageEnhance.Contrast(colour).enhance(1.2)
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    body = colour.convert('RGBA')
    body.putalpha(alpha)
    icon.paste(body, ((size - target[0]) // 2, (size - target[1]) // 2), body)
    pixels = icon.load()
    solid = {(x, y) for x in range(size) for y in range(size) if pixels[x, y][3]}
    for x in range(size):
        for y in range(size):
            if (x, y) not in solid and any((x + dx, y + dy) in solid for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                pixels[x, y] = INK
    return icon


def main() -> None:
    source = Image.open(SOURCE).convert('RGBA')
    cell = source.width // 2
    atlas = Image.new('RGBA', (SIZES[0] * len(KINDS), sum(SIZES)), (0, 0, 0, 0))
    regions: dict[str, dict[str, list[int]]] = {}
    top = 0
    for size in SIZES:
        for index, kind in enumerate(KINDS):
            picture = source.crop(((index % 2) * cell, (index // 2) * cell, (index % 2 + 1) * cell, (index // 2 + 1) * cell))
            atlas.paste(reduce(picture, size), (index * SIZES[0], top))
            regions.setdefault(kind, {})[str(size)] = [index * SIZES[0], top, size, size]
        top += size
    target = DEST / 'materials_v1.png'
    atlas.save(target, optimize=False)
    metadata = {
        'generator': 'Meshy image-to-image, model gpt-image-2',
        'generated_at': '2026-11-14',
        'asset': 'materials_v1.png',
        'source_asset': 'materials_v1_source.png',
        'style_reference': 'assets/ui/crafting/crafting_items_v1.png',
        'prompt': PROMPT,
        'purpose': 'Original Bunkercrew inventory material icons (steel, concrete, scrap, ammunition) matching the painted crafting plans.',
        'atlas_size': list(atlas.size),
        'source_size': list(source.size),
        'source_cells': {kind: [(index % 2) * cell, (index // 2) * cell, cell, cell] for index, kind in enumerate(KINDS)},
        'regions': regions,
        'references': 'No third-party artwork used. The style reference is the project\'s own generated crafting atlas.',
        'postprocessing': 'tools/build_material_icons.py: silhouette crop, premultiplied area reduction to 40/28 px, mild tone lift, hard alpha, re-inked 1 px outline. Original generated RGBA PNG preserved as materials_v1_source.png (not exported).',
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    }
    (DEST / 'materials_v1.source.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + '\n')
    print('Built', target, atlas.size)


PROMPT = ('Production game UI item sprite atlas in exactly the same detailed industrial pixel-art style, palette, outline weight, lighting direction and level of wear as the reference image. '
    'One clean sprite atlas, square composition, exactly 2 columns by 2 rows with four equally sized cells, no visible grid, no borders, no text, no labels, no backdrop, no glow, plain transparent background. '
    'Four separate inventory material illustrations at consistent scale, three-quarter view, centered with generous padding, each readable as a simple bold silhouette at 32 px. '
    'Top left: stack of three rolled steel plates, cool steel grey with rust-orange edges and rivets. Top right: dented steel bucket filled with wet grey concrete, wire handle, drips. '
    'Bottom left: small heap of machine scrap: bent gear, cut pipe, torn plate, bolts. Bottom right: olive-drab metal ammunition box, open lid, belt of brass rifle cartridges. '
    'Crisp square pixel clusters, dark charcoal outlines, muted olive, brown and steel greys, warm brass and rust-orange highlights, no smooth gradients.')

if __name__ == '__main__':
    main()
