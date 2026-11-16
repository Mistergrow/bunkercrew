#!/usr/bin/env python3
"""Bake playfield art to one texel per world unit (style bible §1, rule 1).

High-density sources (generated atlases at 4-17 source pixels per world unit)
stay in the repository as provenance. This tool reduces every region that the
game draws to exactly the world size it is drawn at, offline:

1. area average in linear light with premultiplied alpha (exact box coverage);
   with the `accent` parameter, a texel mostly covered by small saturated
   accents (sensor lamps, lit brass and edge highlights) takes their own mean
   colour, and the palette gets entries for them, so they are not greyed out,
2. a binary silhouette from the averaged coverage,
3. a mild local-contrast recovery (the average softens painted material),
4. quantisation to a per-object palette of the source's dominant ramps
   (k-means in OKLab over the source region's opaque pixels),
5. cleanup: low-contrast orphan texels join their neighbourhood, single
   holes close, specks drop; high-contrast single texels (bolts, gauge
   needles, highlights) stay,
6. a 1-texel dark contour on the silhouette in the actors' ink colour
   (thin parts keep their colour, darkened, so a 2-texel pipe stays a pipe).

Rotating parts (gun barrels) and tilting hulls (aircraft attitude, walker
lean) are baked as stances: the source is rotated at source resolution
(bicubic), then reduced the same way, so every aim angle or attitude is clean
world-texel art instead of a rotated sprite.

Every output atlas gets a .source.json with the source file and its SHA-256,
the parameters and the packed regions. scripts/world_texel_index.gd is
generated for the runtime lookup (WorldTexels).

    python3 tools/bake_world_density_art.py            # bake everything
    python3 tools/bake_world_density_art.py --only components_world
    python3 tools/bake_world_density_art.py --sheet artifacts/x.png  # review sheet
"""
import argparse
import hashlib
import json
import math
import os
import re
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools" / "world_density_bake.json"
INDEX = ROOT / "scripts" / "world_texel_index.gd"
INK = np.array([21, 27, 30], dtype=np.float64) / 255.0
TOOL = "tools/bake_world_density_art.py"
VERSION = 1


# ---- colour ---------------------------------------------------------------

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def linear_to_oklab(rgb):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    lms = np.cbrt(np.maximum(rgb @ m1.T, 0.0))
    return lms @ m2.T


def oklab_to_linear(lab):
    m2i = np.array([[1.0, 0.3963377774, 0.2158037573],
                    [1.0, -0.1055613458, -0.0638541728],
                    [1.0, -0.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                    [-1.2684380046, 2.6097574011, -0.3413193965],
                    [-0.0041960863, -0.7034186147, 1.7076147010]])
    lms = (lab @ m2i.T) ** 3
    return lms @ m1i.T


# ---- reduction ------------------------------------------------------------

def coverage_matrix(source, target):
    """(target, source) weights of an exact box filter."""
    matrix = np.zeros((target, source))
    scale = source / target
    for index in range(target):
        start, end = index * scale, (index + 1) * scale
        for column in range(int(math.floor(start)), min(source, int(math.ceil(end)))):
            overlap = min(end, column + 1) - max(start, column)
            if overlap > 0:
                matrix[index, column] = overlap / scale
    return matrix


def area_reduce(rgba, width, height):
    """Premultiplied linear area average of an RGBA float image (0..1)."""
    alpha = rgba[..., 3:4]
    premultiplied = srgb_to_linear(rgba[..., :3]) * alpha
    stack = np.concatenate([premultiplied, alpha], axis=2)
    rows = coverage_matrix(stack.shape[0], height)
    columns = coverage_matrix(stack.shape[1], width)
    # Two matrix products (rows, then columns); a three-operand einsum loops naively.
    reduced = np.einsum("ikc,lk->ilc", np.tensordot(rows, stack, axes=(1, 0)), columns, optimize=True)
    coverage = reduced[..., 3]
    colour = reduced[..., :3] / np.maximum(coverage[..., None], 1e-6)
    return colour, coverage


def box_blur(values, mask):
    """3x3 average over masked texels only."""
    padded = np.pad(values * mask[..., None], ((1, 1), (1, 1), (0, 0)))
    weight = np.pad(mask.astype(np.float64), 1)
    total = np.zeros_like(values)
    count = np.zeros(mask.shape)
    for dy in range(3):
        for dx in range(3):
            total += padded[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
            count += weight[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
    return total / np.maximum(count[..., None], 1e-6)


def kmeans(points, count, seed=7, rounds=24):
    rng = np.random.default_rng(seed)
    if len(points) <= count:
        return points.copy()
    # k-means++ seeding keeps rare but distinct ramps (brass, lamp glow).
    centres = [points[rng.integers(len(points))]]
    distance = np.full(len(points), np.inf)
    for _ in range(1, count):
        distance = np.minimum(distance, ((points - centres[-1]) ** 2).sum(1))
        centres.append(points[rng.choice(len(points), p=distance / distance.sum())])
    centres = np.array(centres)
    for _ in range(rounds):
        labels = ((points[:, None, :] - centres[None]) ** 2).sum(2).argmin(1)
        for index in range(count):
            members = points[labels == index]
            if len(members):
                centres[index] = members.mean(0)
    return centres


def source_palette(rgba, count, seed, params=None):
    opaque = rgba[..., 3] > 0.5
    colours = srgb_to_linear(rgba[..., :3][opaque])
    if len(colours) == 0:
        return np.zeros((1, 3))
    rng = np.random.default_rng(seed)
    if len(colours) > 24000:
        colours = colours[rng.choice(len(colours), 24000, replace=False)]
    palette = kmeans(linear_to_oklab(colours), count, seed)
    if params and params.get("accent", 0) > 0:
        # Rare accents get their own entries; k-means over the whole part
        # merges a few lamp pixels into the nearest rust.
        accents = srgb_to_linear(rgba[..., :3][accent_mask(rgba, params)])
        if len(accents):
            if len(accents) > 6000:
                accents = accents[rng.choice(len(accents), 6000, replace=False)]
            palette = np.concatenate([palette, kmeans(linear_to_oklab(accents), params.get("accent_palette", 4), seed)])
    return palette


def neighbours4(mask):
    padded = np.pad(mask, 1)
    return [padded[:-2, 1:-1], padded[2:, 1:-1], padded[1:-1, :-2], padded[1:-1, 2:]]


def accent_mask(rgba, params):
    """Source pixels of the small saturated accents (sensor lamps, lit brass
    and orange edge highlights) that an area average would grey out."""
    lab = linear_to_oklab(srgb_to_linear(rgba[..., :3]))
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    return (rgba[..., 3] > 0.5) & (chroma > params["accent"]) & (lab[..., 0] > params.get("accent_light", 0.5))


def reduce_item(rgba, width, height, params, palette=None):
    colour, coverage = area_reduce(rgba, width, height)
    if params.get("accent", 0) > 0:
        # A texel that is mostly accent takes the accents' own mean colour.
        accents = rgba.copy()
        accents[..., 3] = accent_mask(rgba, params)
        accent_colour, share = area_reduce(accents, width, height)
        keep = share >= params.get("accent_share", 0.3)
        colour[keep] = accent_colour[keep]
    solid = coverage >= params.get("alpha", 0.45)
    # Close single-texel holes and drop isolated specks of the silhouette.
    up, down, left, right = neighbours4(solid)
    count = up.astype(int) + down + left + right
    solid = (solid & (count >= 1)) | (~solid & (count == 4) & (coverage > 0.15))
    lab = linear_to_oklab(np.clip(colour, 0, 1))
    # Local contrast: the box average flattens painted wear and edges.
    sharpen = params.get("sharpen", 0.45)
    if sharpen > 0:
        lab[..., 0] = lab[..., 0] + sharpen * (lab[..., 0] - box_blur(lab[..., :1], solid)[..., 0])
    if palette is None:
        palette = source_palette(rgba, params.get("palette", 24), params.get("seed", 11), params)
    flat = lab.reshape(-1, 3)
    index = ((flat[:, None, :] - palette[None]) ** 2).sum(2).argmin(1).reshape(height, width)
    index = cleanup(index, solid, palette, params.get("orphan", 0.07))
    out_lab = palette[index]
    rgb = linear_to_srgb(oklab_to_linear(out_lab))
    rgb = contour(rgb, solid, params.get("contour", 0.8))
    result = np.zeros((height, width, 4))
    result[..., :3] = rgb
    result[..., 3] = solid
    return result


def cleanup(index, solid, palette, threshold):
    """Low-contrast single texels take the most common neighbour colour."""
    height, width = index.shape
    result = index.copy()
    for y in range(height):
        for x in range(width):
            if not solid[y, x]:
                continue
            values = []
            same = False
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dy == 0 and dx == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < height and 0 <= nx < width and solid[ny, nx]:
                        values.append(index[ny, nx])
                        same = same or index[ny, nx] == index[y, x]
            if same or len(values) < 5:
                continue
            common = max(set(values), key=values.count)
            if np.sqrt(((palette[common] - palette[index[y, x]]) ** 2).sum()) < threshold:
                result[y, x] = common
    return result


def contour(rgb, solid, strength):
    if strength <= 0:
        return rgb
    up, down, left, right = neighbours4(solid)
    edge = solid & ~(up & down & left & right)
    # A part one or two texels thick keeps its colour (darkened): a pipe, leg
    # or barrel must not turn into a plain ink line.
    thin = solid & ((~left & ~right) | (~up & ~down))
    result = rgb.copy()
    full = edge & ~thin
    result[full] = rgb[full] * (1 - strength) + INK * strength
    result[thin & edge] = rgb[thin & edge] * 0.62 + INK * 0.38
    return result


# ---- sources --------------------------------------------------------------

def load_rgba(path):
    return np.asarray(Image.open(ROOT / path).convert("RGBA")).astype(np.float64) / 255.0


def resolve_tres(path):
    text = (ROOT / path).read_text()
    atlas = re.search(r'path="res://([^"]+)"', text).group(1)
    region = [int(float(v)) for v in re.search(r"region = Rect2\(([^)]*)\)", text).group(1).split(",")]
    return atlas, region


def fit_size(region, box):
    # LevelProp: uniform factor that fits the display box, as in _build_artwork().
    factor = min(box[0] / region[2], box[1] / region[3])
    return [int(round(region[2] * factor)), int(round(region[3] * factor))]


def rotate_source(rgba, degrees, pad):
    """Rotate a premultiplied RGBA crop about its centre at source resolution."""
    alpha = rgba[..., 3:4]
    premultiplied = np.concatenate([rgba[..., :3] * alpha, alpha], axis=2)
    padded = np.pad(premultiplied, ((pad, pad), (pad, pad), (0, 0)))
    channels = []
    for channel in range(4):
        image = Image.fromarray(padded[..., channel].astype(np.float32), mode="F")
        channels.append(np.asarray(image.rotate(-degrees, resample=Image.BICUBIC)))
    rotated = np.clip(np.stack(channels, axis=2), 0, 1)
    out = rotated.copy()
    out[..., :3] = rotated[..., :3] / np.maximum(rotated[..., 3:4], 1e-6)
    return np.clip(out, 0, 1)


def stretch(rgba, width, height):
    """Premultiplied Lanczos resize at source density (aspect changes only)."""
    alpha = rgba[..., 3:4]
    channels = []
    for channel in range(4):
        values = rgba[..., channel] * (alpha[..., 0] if channel < 3 else 1.0)
        image = Image.fromarray(values.astype(np.float32), mode="F").resize((width, height), Image.LANCZOS)
        channels.append(np.asarray(image))
    out = np.clip(np.stack(channels, axis=2), 0, 1)
    out[..., :3] = out[..., :3] / np.maximum(out[..., 3:4], 1e-6)
    return np.clip(out, 0, 1)


def trim(image):
    rows = np.nonzero(image[..., 3].any(1))[0]
    columns = np.nonzero(image[..., 3].any(0))[0]
    if rows.size == 0:
        return image[:1, :1], (0, 0)
    return image[rows[0]:rows[-1] + 1, columns[0]:columns[-1] + 1], (int(columns[0]), int(rows[0]))


# ---- jobs -----------------------------------------------------------------

def authored(item, palettes):
    """A texel map drawn at world density by hand: one character per texel."""
    palette = palettes[item.get("palette", "default")]
    rows = item["pixels"]
    image = np.zeros((len(rows), max(len(row) for row in rows), 4))
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char in ". ":
                continue
            value = palette[char].lstrip("#")
            image[y, x, :3] = [int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
            image[y, x, 3] = 1.0
    return image


def composite(atlas, item):
    """Kitbash at source density: source regions resized (premultiplied
    Lanczos) into world rects at `scale` source pixels per unit, painted in
    order, then reduced like any other region. A machine assembled from the
    furnace's and the cabinet's painted steel shares their material."""
    spec = item["composite"]
    scale = float(spec["scale"])
    width, height = spec["size"]
    canvas = np.zeros((int(round(height * scale)), int(round(width * scale)), 4))
    sources = set()
    for part in spec["parts"]:
        source = part.get("source", atlas["source"])
        sources.add(source)
        x, y, w, h = part["region"]
        crop = load_rgba(source)[y:y + h, x:x + w].copy()
        crop[crop[..., 3] < 0.02] = 0
        px, py, pw, ph = part["rect"]
        tw, th = int(round(pw * scale)), int(round(ph * scale))
        piece = stretch(crop, tw, th)
        if part.get("flip"):
            piece = piece[:, ::-1]
        left, top = int(round(px * scale)), int(round(py * scale))
        region = canvas[top:top + th, left:left + tw]
        piece = piece[:region.shape[0], :region.shape[1]]
        alpha = piece[..., 3:4]
        region[..., :3] = piece[..., :3] * alpha + region[..., :3] * (1 - alpha)
        region[..., 3:4] = alpha + region[..., 3:4] * (1 - alpha)
    return sources, canvas


def item_jobs(atlas, item):
    """Expands one manifest item to (key, image, extra) entries."""
    if "composite" in item:
        sources, canvas = composite(atlas, item)
        params = dict(atlas.get("params", {}))
        params.update(item.get("params", {}))
        width, height = item["composite"]["size"]
        return sorted(sources), [(f"authored:{item['name']}", reduce_item(canvas, width, height, params), {})]
    if "pixels" in item:
        return None, [(f"authored:{item['name']}", authored(item, atlas.get("palettes", {})), {})]
    if "tres" in item:
        source, region = resolve_tres(item["tres"])
    else:
        source, region = item.get("source", atlas["source"]), item["region"]
    rgba = load_rgba(source)
    x, y, w, h = region
    crop = rgba[y:y + h, x:x + w].copy()
    crop[crop[..., 3] < 0.02] = 0
    for clear in item.get("clear", []):
        cx, cy, cw, ch = clear
        crop[cy - y:cy - y + ch, cx - x:cx - x + cw] = 0
    params = dict(atlas.get("params", {}))
    params.update(item.get("params", {}))
    sizes = [item["size"]] if "size" in item else []
    sizes += [fit_size(region, box) for box in item.get("fit", [])]
    sizes += item.get("sizes", [])
    jobs = []
    seen = set()
    for size in sizes:
        size = [int(size[0]), int(size[1])]
        if tuple(size) in seen:
            continue
        seen.add(tuple(size))
        base_key = f"res://{source}|{x},{y},{w},{h}|{size[0]}x{size[1]}"
        if "turns" in item:
            turns = item["turns"]
            angle = float(turns["from"])
            ratio = w / size[0]
            part = crop
            if abs(ratio - h / size[1]) > 0.01 * ratio:
                # A part drawn squashed: squash it at source density first, so
                # the rotation turns the shape the game shows.
                part = stretch(crop, w, int(round(size[1] * ratio)))
            pad = int(max(part.shape[:2]) * 0.5)
            # One palette for every stance: a turning barrel keeps its colours.
            palette = source_palette(part, params.get("palette", 24), params.get("seed", 11), params)
            angles = []
            while angle <= float(turns["to"]) + 1e-6:
                angles.append(angle)
                angle += float(turns["step"])
            with ProcessPoolExecutor(max_workers=min(12, os.cpu_count() or 1)) as pool:
                stances = pool.map(bake_stance, [(part, a, pad, ratio, params, palette) for a in angles])
                for a, (image, offset) in zip(angles, stances):
                    jobs.append((f"{base_key}|turn:{int(round(a * 10))}", image, {"offset": offset, "angle": a}))
        else:
            jobs.append((base_key, reduce_item(crop, size[0], size[1], params), {}))
    return source, jobs


def bake_stance(job):
    """One aim stance: rotate at source density, reduce, trim (worker process)."""
    part, angle, pad, ratio, params, palette = job
    rotated = rotate_source(part, angle, pad)
    rw = int(round(rotated.shape[1] / ratio))
    rh = int(round(rotated.shape[0] / ratio))
    image = reduce_item(rotated, rw, rh, params, palette)
    image, (ox, oy) = trim(image)
    # Offset of the trimmed stance from the rotated part's centre.
    return image, [ox - rw / 2.0, oy - rh / 2.0]


def pack(images, width):
    """Shelf packing, tallest first, one transparent texel between items."""
    order = sorted(range(len(images)), key=lambda i: (-images[i].shape[0], -images[i].shape[1]))
    places = [None] * len(images)
    x = y = shelf = 0
    for i in order:
        h, w = images[i].shape[:2]
        if x + w > width:
            x, y, shelf = 0, y + shelf + 1, 0
        places[i] = (x, y)
        x += w + 1
        shelf = max(shelf, h)
    height = y + shelf
    canvas = np.zeros((height, width, 4))
    for i, (px, py) in enumerate(places):
        h, w = images[i].shape[:2]
        canvas[py:py + h, px:px + w] = images[i]
    return canvas, places


def sha256(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def bake_atlas(atlas):
    entries = []
    sources = set()
    for item in atlas["items"]:
        source, jobs = item_jobs(atlas, item)
        if isinstance(source, list):
            sources.update(source)
        elif source:
            sources.add(source)
        for key, image, extra in jobs:
            entries.append({"name": item["name"], "key": key, "image": image, **extra})
    images = [entry["image"] for entry in entries]
    width = int(atlas.get("width", 512))
    width = max(width, max(image.shape[1] for image in images))
    canvas, places = pack(images, width)
    output = ROOT / atlas["output"]
    Image.fromarray((np.clip(canvas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(output, optimize=True)
    rows = []
    for entry, (px, py) in zip(entries, places):
        h, w = entry["image"].shape[:2]
        row = {"name": entry["name"], "key": entry["key"], "region": [px, py, w, h]}
        if "offset" in entry:
            row["offset"] = [round(v, 3) for v in entry["offset"]]
            row["angle"] = entry["angle"]
        rows.append(row)
    provenance = {
        "asset": Path(atlas["output"]).name,
        "tool": TOOL,
        "tool_version": VERSION,
        "manifest": "tools/world_density_bake.json",
        "method": "one texel per world unit: linear-light premultiplied area average, binary silhouette, OKLab local contrast, per-object k-means palette of the source, orphan cleanup, 1-texel ink contour; rotating parts baked as stances rotated at source resolution" + ("; texels mostly covered by saturated accents keep the accents' mean colour, with accent palette entries" if atlas.get("params", {}).get("accent", 0) > 0 else ""),
        "sources": [{"file": source, "sha256": sha256(source)} for source in sorted(sources)] or "authored texel maps in the manifest (hand-drawn at world density)",
        "params": atlas.get("params", {}),
        "ink": "#151b1e",
        "size": [int(canvas.shape[1]), int(canvas.shape[0])],
        "items": rows,
    }
    Path(str(output) + ".source.json").write_text(json.dumps(provenance, indent=1) + "\n")
    return rows, canvas


def write_index(manifest, baked):
    lines = [
        "extends RefCounted",
        "## Generated by tools/bake_world_density_art.py from tools/world_density_bake.json;",
        "## do not edit. Key: source path | source region | world size [| turn:deci-degrees].",
        "## Value: [atlas index, region in that atlas, stance offset from the part centre].",
        "const ATLASES: Array[String] = [",
    ]
    for atlas in manifest["atlases"]:
        lines.append(f'\t"res://{atlas["output"]}",')
    lines.append("]")
    lines.append("const ENTRIES := {")
    for atlas_index, atlas in enumerate(manifest["atlases"]):
        for row in baked.get(atlas["output"], []):
            x, y, w, h = row["region"]
            offset = row.get("offset", [0, 0])
            lines.append(f'\t"{row["key"]}": [{atlas_index}, Rect2({x}, {y}, {w}, {h}), Vector2({offset[0]:g}, {offset[1]:g})],')
    lines.append("}")
    # Atlas resources (.tres) by path, so a draw site can find its bake
    # without loading the resource and with it the high-density source.
    lines.append("const RESOURCES := {")
    for atlas in manifest["atlases"]:
        for item in atlas["items"]:
            if "tres" in item:
                source, (x, y, w, h) = resolve_tres(item["tres"])
                lines.append(f'\t"res://{item["tres"]}": ["res://{source}", Rect2({x}, {y}, {w}, {h})],')
    lines.append("}")
    INDEX.write_text("\n".join(lines) + "\n")


def existing_rows(atlas):
    path = ROOT / (atlas["output"] + ".source.json")
    if not path.exists():
        return []
    return json.loads(path.read_text()).get("items", [])


def review_sheet(manifest, path, names):
    """Source (nearest at the world size, as drawn before) beside the bake, 4x."""
    tiles = []
    for atlas in manifest["atlases"]:
        if names and Path(atlas["output"]).stem not in names:
            continue
        sheet = np.asarray(Image.open(ROOT / atlas["output"]).convert("RGBA"))
        for row in existing_rows(atlas):
            if row["key"].startswith("authored:"):
                continue
            if "angle" in row and int(round(row["angle"])) % 30 != 0:
                continue
            key = row["key"].split("|")
            source = key[0].replace("res://", "")
            x, y, w, h = [int(v) for v in key[1].split(",")]
            size = [int(v) for v in key[2].split("x")]
            bx, by, bw, bh = row["region"]
            baked = Image.fromarray(sheet[by:by + bh, bx:bx + bw])
            before = Image.open(ROOT / source).convert("RGBA").crop((x, y, x + w, y + h))
            if "angle" in row:
                before = before.rotate(-row["angle"], resample=Image.NEAREST, expand=True)
                size = [int(round(before.width * size[0] / w)), int(round(before.height * size[1] / h))]
            before = before.resize(tuple(size), Image.NEAREST)
            tiles.append((before, baked))
    scale = 4
    width = max(a.width + b.width for a, b in tiles) * scale + 24
    height = sum(max(a.height, b.height) * scale + 8 for a, b in tiles)
    canvas = Image.new("RGBA", (width, height), (54, 58, 52, 255))
    y = 0
    for before, baked in tiles:
        canvas.alpha_composite(before.resize((before.width * scale, before.height * scale), Image.NEAREST), (0, y))
        canvas.alpha_composite(baked.resize((baked.width * scale, baked.height * scale), Image.NEAREST), (before.width * scale + 16, y))
        y += max(before.height, baked.height) * scale + 8
    canvas.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default="", help="comma-separated output stems to bake")
    parser.add_argument("--sheet", help="write a before/after review sheet (no bake)")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    names = {name for name in args.only.split(",") if name}
    if args.sheet:
        review_sheet(manifest, args.sheet, names)
        return 0
    baked = {}
    for atlas in manifest["atlases"]:
        if names and Path(atlas["output"]).stem not in names:
            baked[atlas["output"]] = existing_rows(atlas)
            continue
        rows, canvas = bake_atlas(atlas)
        baked[atlas["output"]] = rows
        print(f"{atlas['output']}: {len(rows)} entries, {canvas.shape[1]}x{canvas.shape[0]}")
    write_index(manifest, baked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
