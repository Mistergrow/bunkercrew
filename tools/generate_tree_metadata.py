#!/usr/bin/env python3
"""Analyze original tree alpha/foliage; write metadata without changing images."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/environments/props"
SOURCES = {
    "deciduous": {"family": "broadleaf", "root": [623, 1050], "trunk": [[623, 1050], [620, 910], [680, 775], [722, 647], [654, 458]]},
    "conifer": {"family": "conifer", "root": [614, 1135], "trunk": [[614, 1135], [610, 940], [612, 730], [622, 498], [628, 245]]},
    "dead": {"family": "dead", "root": [839, 1030], "trunk": [[839, 1030], [820, 905], [773, 765], [790, 618], [712, 469]]},
    "oak": {"family": "broadleaf", "root": [704, 1172], "trunk": [[704, 1172], [709, 1030], [712, 900], [660, 730], [650, 590]], "trunk_radius": 88, "stiffness": 1.22},
    "birch": {"family": "broadleaf", "root": [716, 1228], "trunk": [[716, 1228], [712, 1080], [698, 940], [665, 785], [628, 618]], "trunk_radius": 35, "stiffness": .88},
    "spruce": {"family": "conifer", "root": [627, 1201], "trunk": [[627, 1201], [628, 1050], [648, 845], [664, 651], [655, 435]], "trunk_radius": 56, "stiffness": 1.12},
}


def interior(mask: np.ndarray, radius: int) -> np.ndarray:
    padded = np.pad(mask, radius, constant_values=False)
    result = mask.copy()
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            result &= padded[radius + dy:radius + dy + h, radius + dx:radius + dx + w]
    return result


def foliage_mask(rgba: np.ndarray, family: str, root: list[int]) -> np.ndarray:
    rgb = rgba[:, :, :3].astype(np.float32) / 255.0
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    hi, lo = rgb.max(axis=2), rgb.min(axis=2)
    delta = hi - lo
    hue = np.zeros_like(hi)
    nonzero = delta > .001
    rm, gm, bm = nonzero & (hi == r), nonzero & (hi == g), nonzero & (hi == b)
    hue[rm] = ((g[rm] - b[rm]) / delta[rm]) % 6
    hue[gm] = (b[gm] - r[gm]) / delta[gm] + 2
    hue[bm] = (r[bm] - g[bm]) / delta[bm] + 4
    hue *= 60
    saturation = np.divide(delta, hi, out=np.zeros_like(hi), where=hi > .001)
    mask = rgba[:, :, 3] >= 220
    if family == "broadleaf":
        mask &= (hue >= 42) & (hue <= 165) & (saturation >= .15) & (g >= r * .86) & (g >= b * 1.10) & (hi >= .10)
    elif family == "conifer":
        mask &= (hue >= 60) & (hue <= 195) & (saturation >= .10) & (g >= r) & (g >= b * .94) & (hi >= .075)
    # No foliage comes from the bare lower trunk or from the root illustration.
    mask[round(root[1] * (.84 if family == "dead" else .88)):, :] = False
    return mask


def analyze(kind: str, spec: dict) -> dict:
    path = ASSETS / f"{kind}_tree.png"
    rgba = np.asarray(Image.open(path).convert("RGBA"))
    ys, xs = np.nonzero(rgba[:, :, 3] >= 64)
    region = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
    mask = foliage_mask(rgba, spec["family"], spec["root"])
    # Moss or warm highlights on the main trunk must not turn it into a leaf
    # emitter. Exclude the independently measured curved trunk corridor too.
    yy, xx = np.indices(mask.shape, dtype=np.float32)
    radius = float(spec.get("trunk_radius", 88 if spec["family"] == "dead" else 48))
    for index, (start, finish) in enumerate(zip(spec["trunk"], spec["trunk"][1:])):
        ax, ay = start
        vx, vy = finish[0] - ax, finish[1] - ay
        fraction = np.clip(((xx - ax) * vx + (yy - ay) * vy) / max(1.0, vx * vx + vy * vy), 0, 1)
        distance_sq = (xx - ax - fraction * vx) ** 2 + (yy - ay - fraction * vy) ** 2
        mask &= distance_sq > (radius * (1 - index * .15)) ** 2
    radius = 2 if spec["family"] != "dead" else 1
    safe = interior(mask, radius)
    # Broad spatial strata prevent dense central foliage from swallowing the
    # sampling budget. Every occupied cell gets a point before a second pass.
    py, px = np.nonzero(safe)
    if len(px) < 80:
        raise ValueError(f"{kind}: insufficient interior foliage pixels: {len(px)}")
    x0, x1, y0, y1 = int(px.min()), int(px.max() + 1), int(py.min()), int(py.max() + 1)
    seed = int.from_bytes(hashlib.sha256(kind.encode()).digest()[:8], "little")
    rng = np.random.default_rng(seed)
    cells: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for y, x in zip(py.tolist(), px.tolist()):
        cell = (min(19, (x - x0) * 20 // max(1, x1 - x0)), min(15, (y - y0) * 16 // max(1, y1 - y0)))
        cells.setdefault(cell, []).append((x, y))
    keys = sorted(cells)
    rng.shuffle(keys)
    # 192 points is enough to avoid recognisable emitter repetition while
    # keeping scene metadata and cached per-instance arrays small.
    points = []
    occupied = []
    for _ in range(3):
        for cell in keys:
            choices = cells[cell]
            point = choices[int(rng.integers(len(choices)))]
            if list(point) not in points:
                points.append(list(point))
                occupied.append(list(cell))
            if len(points) >= 192:
                break
        if len(points) >= 192:
            break
    if len(points) < 80:
        raise ValueError(f"{kind}: only {len(points)} spatial samples")
    return {"path": "res://" + str(path.relative_to(ROOT)), "size": [rgba.shape[1], rgba.shape[0]],
            "family": spec["family"], "root": spec["root"], "trunk": spec["trunk"], "region": region,
            "trunk_radius": spec.get("trunk_radius", 88 if spec["family"] == "dead" else 48), "stiffness": spec.get("stiffness", 1.0),
            "canopy_points": points, "canopy_cells": occupied, "canopy_grid": [20, 16],
            "canopy_bounds": [x0, y0, x1 - x0, y1 - y0], "valid_interior_pixels": len(px),
            "interior_radius": radius, "alpha_minimum": 220,
            "trunk_excluded": True,
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare existing metadata; never rewrite it.")
    args = parser.parse_args()
    metadata = {"version": 1, "generator": "tools/generate_tree_metadata.py", "images_modified": False,
                "sampling": "Seeded uniform occupied-cell sampling of eroded alpha/HSV foliage masks; dead trees use bark.",
                "trees": {kind: analyze(kind, spec) for kind, spec in SOURCES.items()}}
    target = ASSETS / "tree_metadata.json"
    if args.check:
        assert json.loads(target.read_text()) == metadata, "Tree metadata differs from current original images/settings"
    else:
        target.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    for kind, entry in metadata["trees"].items():
        print(f"{kind}: {entry['family']}, {len(entry['canopy_points'])} points across {len(set(map(tuple,entry['canopy_cells'])))} cells, {entry['valid_interior_pixels']} safe pixels")


if __name__ == "__main__":
    main()
