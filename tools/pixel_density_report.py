#!/usr/bin/env python3
"""Measure the effective art-pixel size of regions in a capture.

The playfield is meant to share one pixel density: one art pixel is one world
unit, shown as an s x s block of screen pixels where s is the camera's whole
pixels per unit (style bible §1). This tool estimates, per region, how large
the art pixels really are on screen and how much of the visible detail falls
off that world grid.

For every pair of neighbouring screen pixels whose colours differ clearly
(max channel step > --threshold) it records an edge at that boundary. Art drawn
on an s-pixel grid only has edges on every s-th boundary (in one phase), so:

* ``block``: the largest s whose edges line up with one phase (alignment
  score >= 0.8 after removing the chance level 1/s), per axis. Strict: one
  seam at another phase inside the region lowers it.
* ``off_grid``: share of edges NOT on the reference world grid (s, phase).
* ``aligned``: alignment score at the reference block size with the region's
  own best phase (1 = every edge on an s-pixel grid, 0 = chance). Each object
  may sit at its own phase; this measures density, not placement.
* ``thin``: share of feature runs (pixels between two edges, along x and y)
  that are a single screen pixel long. Art on an s >= 2 grid has almost none;
  art at full screen resolution has many.
* ``p20``: 20th percentile of the feature run length in screen pixels, an
  estimate of the smallest art pixel that is common in the region.
* ``run``: mean length of runs of identical colour along x (soft, filtered or
  shaded art has runs near 1 even when its features are large).
* ``soft``: share of neighbour steps that are small but non-zero (gradients
  from bilinear filtering or per-pixel shading) among all non-zero steps.

The reference grid is given with --grid S,PX,PY, or measured from a region
named with --reference (normally a worker sprite: s is its p20 run length).

    python3 tools/pixel_density_report.py IMAGE --region actor=800,600,70,130 \\
        --region station=640,540,590,180 --reference actor [--json out.json]
    python3 tools/pixel_density_report.py --spec regions.json [--json out.json]

A spec file maps image paths to {"reference": name, "regions": {name: [x,y,w,h]}}.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MAX_BLOCK = 8


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int16)


def steps(pixels, axis):
    # Largest channel difference between each pixel and its next neighbour.
    return np.abs(np.diff(pixels, axis=axis)).max(axis=2)


def edge_positions(pixels, axis, threshold):
    step = steps(pixels, axis)
    ys, xs = np.nonzero(step > threshold)
    # Boundary index: the edge between i and i+1 lies at boundary i+1.
    return (xs + 1) if axis == 1 else (ys + 1)


def alignment(positions, block):
    if positions.size == 0:
        return 0.0, 0
    counts = np.bincount(positions % block, minlength=block)
    phase = int(np.argmax(counts))
    share = counts[phase] / positions.size
    if block == 1:
        return 1.0, 0
    return (share - 1.0 / block) / (1.0 - 1.0 / block), phase


def block_size(positions):
    best = 1
    for block in range(2, MAX_BLOCK + 1):
        score, _ = alignment(positions, block)
        if score >= 0.8:
            best = block
    return best


def feature_runs(pixels, threshold):
    # Lengths of the stretches between consecutive edges along rows and columns.
    runs = []
    for axis in (1, 0):
        edge = steps(pixels, axis) > threshold
        if axis == 0:
            edge = edge.T
        for line in edge:
            index = np.nonzero(line)[0]
            if index.size > 1:
                runs.append(np.diff(index))
    return np.concatenate(runs) if runs else np.zeros(0, dtype=int)


def region_stats(pixels, origin, threshold, grid):
    x0, y0 = origin
    h_edges = edge_positions(pixels, 1, threshold) + x0
    v_edges = edge_positions(pixels, 0, threshold) + y0
    runs = feature_runs(pixels, threshold)
    result = {
        "block_x": block_size(h_edges),
        "block_y": block_size(v_edges),
        "edges_per_px": round(float(h_edges.size + v_edges.size) / max(1, pixels.shape[0] * pixels.shape[1]), 4),
    }
    if grid:
        size, phase_x, phase_y = grid
        off_x = float(np.mean((h_edges - phase_x) % size != 0)) if h_edges.size else 0.0
        off_y = float(np.mean((v_edges - phase_y) % size != 0)) if v_edges.size else 0.0
        total = h_edges.size + v_edges.size
        result["off_grid"] = round((off_x * h_edges.size + off_y * v_edges.size) / max(1, total), 3)
        score_x, _ = alignment(h_edges, size)
        score_y, _ = alignment(v_edges, size)
        result["aligned"] = round((score_x * h_edges.size + score_y * v_edges.size) / max(1, total), 3)
    result["thin"] = round(float(np.mean(runs == 1)) if runs.size else 0.0, 3)
    result["p20"] = float(np.percentile(runs, 20)) if runs.size else 0.0
    same = np.all(pixels[:, 1:] == pixels[:, :-1], axis=2)
    runs = pixels.shape[0] * pixels.shape[1] / max(1, pixels.shape[0] * pixels.shape[1] - int(same.sum()))
    result["run"] = round(float(runs), 2)
    step = np.concatenate([steps(pixels, 1).ravel(), steps(pixels, 0).ravel()])
    nonzero = step[step > 0]
    result["soft"] = round(float(np.mean(nonzero <= threshold)) if nonzero.size else 0.0, 3)
    return result


def measure_reference(pixels, origin, threshold):
    # The camera's pixels per texel: the common smallest feature run of a
    # sprite authored at one texel per world unit (its 20th percentile).
    x0, y0 = origin
    runs = feature_runs(pixels, threshold)
    size = max(1, int(round(float(np.percentile(runs, 20))))) if runs.size else 1
    h_edges = edge_positions(pixels, 1, threshold) + x0
    v_edges = edge_positions(pixels, 0, threshold) + y0
    _, phase_x = alignment(h_edges, size)
    _, phase_y = alignment(v_edges, size)
    return size, phase_x, phase_y


def crop(image, rect):
    x, y, w, h = rect
    return image[y:y + h, x:x + w]


def report(path, regions, reference, threshold, grid):
    image = load(path)
    if grid is None and reference:
        rect = regions[reference]
        grid = measure_reference(crop(image, rect), rect[:2], threshold)
    rows = {}
    for name, rect in regions.items():
        rows[name] = region_stats(crop(image, rect), rect[:2], threshold, grid)
        rows[name]["rect"] = list(rect)
    return {"image": str(path), "grid": list(grid) if grid else None, "regions": rows}


def parse_rect(text):
    values = [int(part) for part in text.split(",")]
    if len(values) != 4:
        raise argparse.ArgumentTypeError("rect must be x,y,w,h")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", nargs="?")
    parser.add_argument("--region", action="append", default=[], help="name=x,y,w,h")
    parser.add_argument("--reference", default="", help="region that defines the world grid")
    parser.add_argument("--grid", default="", help="world grid S,PX,PY instead of --reference")
    parser.add_argument("--spec", help="JSON {image: {reference, regions}}")
    parser.add_argument("--threshold", type=int, default=20)
    parser.add_argument("--json", help="write the full report here")
    args = parser.parse_args()
    jobs = []
    grid = tuple(int(v) for v in args.grid.split(",")) if args.grid else None
    if args.spec:
        spec = json.loads(Path(args.spec).read_text())
        base = Path(args.spec).parent
        for image, entry in spec.items():
            path = Path(image) if Path(image).is_absolute() else base / image
            entry_grid = tuple(entry["grid"]) if entry.get("grid") else grid
            jobs.append((path, {k: v for k, v in entry["regions"].items()}, entry.get("reference", ""), entry_grid))
    elif args.image:
        regions = {}
        for item in args.region:
            name, _, rect = item.partition("=")
            regions[name] = parse_rect(rect)
        jobs.append((Path(args.image), regions, args.reference, grid))
    else:
        parser.error("an image or --spec is required")
    results = []
    for path, regions, reference, job_grid in jobs:
        result = report(path, regions, reference, args.threshold, job_grid)
        results.append(result)
        print(f"{result['image']}  world grid {result['grid']}")
        for name, row in result["regions"].items():
            off = f"  aligned {row['aligned']:.2f}" if "aligned" in row else ""
            print(f"  {name:<22} thin {row['thin']:.2f}  p20 {row['p20']:3.0f}px{off}  block {row['block_x']}x{row['block_y']}  run {row['run']:5.2f}  soft {row['soft']:.2f}")
    if args.json:
        Path(args.json).write_text(json.dumps(results, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
