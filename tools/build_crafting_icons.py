#!/usr/bin/env python3
"""Reduce the generated crafting plan pictures to a pixel-exact icon atlas.

Input is the preserved original (assets/ui/crafting/crafting_items_v1.png,
3x2 cells of 512 px). Each cell is cropped to its silhouette, cleared of
detached specks and reduced to a 50 px icon with the same premultiplied area
reduction, tone lift, hard alpha and re-inked 1 px outline as the material
icons (tools/build_material_icons.py). The workbench draws these at exactly
twice their size, the art-pixel density of the menu's character sprites,
instead of point-sampling the 512 px paintings down to 100 px.
The original atlas stays in the game: extension packs may still reference it.
Requires Pillow.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from PIL import Image

import build_material_icons as material_icons

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/ui/crafting'
SOURCE = DEST / 'crafting_items_v1.png'
SOURCE_META = DEST / 'crafting_items_v1.source.json'
TARGET = DEST / 'crafting_icons_v1.png'
SIZE = 50
# A detached fleck below this share of the main silhouette is generation noise.
SPECK_SHARE = 0.01


def _without_specks(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel('A')
    width, height = cell.size
    solid = alpha.point(lambda a: 1 if a > 40 else 0).load()
    seen = [[False] * height for _ in range(width)]
    parts: list[list[tuple[int, int]]] = []
    for sx in range(width):
        for sy in range(height):
            if seen[sx][sy] or not solid[sx, sy]: continue
            stack = [(sx, sy)]
            seen[sx][sy] = True
            part = []
            while stack:
                x, y = stack.pop()
                part.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not seen[nx][ny] and solid[nx, ny]:
                        seen[nx][ny] = True
                        stack.append((nx, ny))
            parts.append(part)
    if not parts: return cell
    largest = max(len(part) for part in parts)
    clean = cell.copy()
    pixels = clean.load()
    for part in parts:
        if len(part) < largest * SPECK_SHARE:
            for x, y in part: pixels[x, y] = (0, 0, 0, 0)
    return clean


def main() -> None:
    meta = json.loads(SOURCE_META.read_text())
    source = Image.open(SOURCE).convert('RGBA')
    names = sorted(meta['regions'], key=lambda name: (meta['regions'][name][1], meta['regions'][name][0]))
    atlas = Image.new('RGBA', (SIZE * len(names), SIZE), (0, 0, 0, 0))
    regions: dict[str, list[int]] = {}
    for index, name in enumerate(names):
        x, y, w, h = meta['regions'][name]
        cell = _without_specks(source.crop((x, y, x + w, y + h)))
        atlas.paste(material_icons.reduce(cell, SIZE), (index * SIZE, 0))
        regions[name] = [index * SIZE, 0, SIZE, SIZE]
    atlas.save(TARGET, optimize=False)
    metadata = {
        'generator': meta['generator'],
        'generated_at': meta['generated_at'],
        'asset': TARGET.name,
        'source_asset': SOURCE.name,
        'source_image': meta['source_image'],
        'prompt': meta['prompt'],
        'purpose': 'Pixel-exact Bunkercrew workbench recipe icons, drawn at twice their size.',
        'atlas_size': list(atlas.size),
        'cell_size': [SIZE, SIZE],
        'source_size': list(source.size),
        'source_cells': meta['regions'],
        'regions': regions,
        'references': meta['references'],
        'postprocessing': 'tools/build_crafting_icons.py: detached specks removed, silhouette crop, premultiplied area reduction to 50 px, mild tone lift, hard alpha, re-inked 1 px outline (the reduction of tools/build_material_icons.py).',
        'sha256': hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    }
    (DEST / 'crafting_icons_v1.source.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + '\n')
    print('Built', TARGET, atlas.size)


if __name__ == '__main__':
    main()
