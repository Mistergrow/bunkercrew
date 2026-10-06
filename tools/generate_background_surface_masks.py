#!/usr/bin/env python3
"""Rasterize reviewed vector regions as cropped shader data, never repaint art.

Requires Pillow, NumPy and OpenCV. Hashes lock annotations to the exact plate.
The game loads prepared RGB textures; no segmentation or readback at runtime.
Annotation max_displacement_texels values are initial visual-review suggestions,
not shader controls. The shader caps water at 2 and falling water at 3 source
texels before region strength and integer quantization; solid ice never shifts.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
REGIONS = ROOT / "assets/environments/background_surface_regions.json"
OUTPUT = ROOT / "assets/environments/surface_masks"
CHANNELS = {"water": 0, "flow": 1, "ice": 2}


def polygon_mask(points: list, size: tuple[int, int]) -> np.ndarray:
    if len(points) < 3 or any(len(p) != 2 or not all(0 <= x <= 1 for x in p) for p in points):
        raise ValueError("Expected a normalized polygon with at least three vertices")
    mask = Image.new("L", size)
    width, height = size
    vertices = [(round(x * width), round(y * height)) for x, y in points]
    ImageDraw.Draw(mask).polygon(vertices, fill=255)
    return np.asarray(mask).copy()


def generate(name: str, entry: dict, annotation_hash: str, preview: Path | None) -> dict:
    source = ROOT / entry["source_path"].removeprefix("res://")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != entry["source_sha256"]:
        raise ValueError(f"{name}: the source plate changed; review polygons before generating")
    with Image.open(source) as image:
        original = np.asarray(image.convert("RGBA"))
        size = image.size
    if list(size) != entry["source_dimensions"]:
        raise ValueError(f"{name}: source dimensions changed")
    opaque = original[:, :, 3] >= 250
    channels = np.zeros((*opaque.shape, 3), dtype=np.uint8)
    for region in entry["regions"]:
        channel = CHANNELS[region["material"]]
        shape = polygon_mask(region["polygon"], size)
        for hole in region.get("exclusions", []):
            shape[polygon_mask(hole, size) > 0] = 0
        shape[~opaque] = 0
        feather = float(region.get("feather_texels", 2))
        strength = float(region.get("strength", 1))
        if not 0 < strength <= 1 or not 0 <= feather <= 8:
            raise ValueError(f"{name}: invalid strength or feather")
        distance = cv2.distanceTransform(shape, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        weight = np.minimum(distance / max(feather, 1), 1) * (shape > 0)
        value = np.rint(weight * strength * 255).astype(np.uint8)
        channels[:, :, channel] = np.maximum(channels[:, :, channel], value)
    # A waterfall or solid ice patch never receives simultaneous lake motion.
    channels[:, :, 0][(channels[:, :, 1] > 0) | (channels[:, :, 2] > 0)] = 0
    for material, probes in entry.get("probes", {}).items():
        for probe in probes:
            x, y = probe["source_pixel"]
            correct = not np.any(channels[y, x]) if material == "protected" else channels[y, x, CHANNELS[material]] > 0
            if not correct:
                raise ValueError(f"{name}: independent {material} source probe failed at {(x, y)}")
    width, height = size
    occupied = np.any(channels > 0, axis=2)
    ys, xs = np.nonzero(occupied)
    if xs.size:
        left, top = max(0, int(xs.min()) - 3), max(0, int(ys.min()) - 3)
        right, bottom = min(width, int(xs.max()) + 4), min(height, int(ys.max()) + 4)
        cropped = channels[top:bottom, left:right]
        bounds = [left / width, top / height, (right - left) / width, (bottom - top) / height]
        crop = [left, top, right - left, bottom - top]
    else:
        cropped = np.zeros((1, 1, 3), dtype=np.uint8)
        bounds, crop = [0, 0, 1, 1], [0, 0, 1, 1]
    destination = OUTPUT / (name + ".png")
    Image.fromarray(cropped).save(destination, optimize=True)
    metadata = {
        "kind": "Cropped RGB surface data: R water, G falling water, B solid ice",
        "source_path": entry["source_path"], "source_sha256": digest,
        "annotation_path": "res://assets/environments/background_surface_regions.json",
        "annotation_sha256": annotation_hash,
        "generator": "tools/generate_background_surface_masks.py",
        "method": "Reviewed normalized polygons, protected-island exclusions, opaque-alpha intersection, inward feather, cropped source UV bounds",
        "license": "Same as the source background; original art and adjacent provenance retained",
        "original_dimensions": [width, height], "mask_dimensions": [cropped.shape[1], cropped.shape[0]],
        "bounds": bounds, "crop_pixels": crop,
        "occupied_pixels": {key: int(np.count_nonzero(channels[:, :, value])) for key, value in CHANNELS.items()},
        "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
    }
    destination.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    if preview:
        preview.mkdir(parents=True, exist_ok=True)
        # Inspection overlay, separate from production art and shader textures.
        overlay = original[:, :, :3].astype(np.float32)
        colors = [(20, 180, 255), (255, 190, 20), (210, 120, 255)]
        for channel, tint in enumerate(colors):
            amount = channels[:, :, channel:channel + 1].astype(np.float32) / 255 * .65
            overlay = overlay * (1 - amount) + np.asarray(tint) * amount
        Image.fromarray(overlay.astype(np.uint8)).save(preview / (name + "-mask-overlay.png"))
    print(f"{name}: {cropped.shape[1]}x{cropped.shape[0]} data texels, " + str(metadata["occupied_pixels"]), flush=True)
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-output", type=Path)
    args = parser.parse_args()
    cv2.setNumThreads(2)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    annotation_hash = hashlib.sha256(REGIONS.read_bytes()).hexdigest()
    entries = json.loads(REGIONS.read_text())["environments"]
    results = {name: generate(name, entry, annotation_hash, args.preview_output) for name, entry in entries.items()}
    original_texels = sum(np.prod(item["original_dimensions"]) for item in results.values())
    mask_texels = sum(np.prod(item["mask_dimensions"]) for item in results.values())
    manifest = {"version": 1, "channels": CHANNELS, "environments": results,
                "total_source_texels": int(original_texels), "total_mask_texels": int(mask_texels),
                "texture_area_saved_percent": float(100 * (1 - mask_texels / original_texels))}
    (OUTPUT / "catalog.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"MASK AREA SAVED: {manifest['texture_area_saved_percent']:.1f}%")


if __name__ == "__main__":
    main()
