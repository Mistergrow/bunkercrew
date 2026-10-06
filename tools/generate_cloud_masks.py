#!/usr/bin/env python3
"""Derive v3 sky visibility masks offline without changing the source panoramas.

Requires numpy, Pillow and opencv-python. Source-pixel contour annotations and
independent landmark probes live in assets/environments/v3/landmarks.json.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTLINES = ROOT / "assets/environments/v3/landmarks.json"
OUTPUT = ROOT / "assets/atmosphere/sky_masks"


def generate(name: str, entry: dict, preview: Path | None) -> None:
    source_path = ROOT / entry["source"]
    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
    if digest != entry["source_sha256"]:
        raise ValueError(f"{name}: image changed; review source-pixel annotations first")
    image = np.asarray(Image.open(source_path).convert("RGB"))
    height, width = image.shape[:2]
    outline = np.asarray(entry["skyline_pixels"], dtype=np.float64)
    skyline = np.interp(np.arange(width) + .5, outline[:, 0], outline[:, 1])
    distance = np.arange(height)[:, None] + .5 - skyline[None, :]
    labels = np.where(distance < 0, cv2.GC_BGD, cv2.GC_FGD).astype(np.uint8)
    labels[(distance >= -12) & (distance < 0)] = cv2.GC_PR_BGD
    labels[(distance >= 0) & (distance < 12)] = cv2.GC_PR_FGD
    # Tiny warm beacons and chimney rims resemble cloud colors. These
    # inspected landmark origins belong to the solid source architecture.
    for anchor in entry["details"].get("lights", []) + entry["details"].get("plumes", []):
        x, y = anchor[:2]
        labels[y, x] = cv2.GC_FGD
    background = np.zeros((1, 65), np.float64)
    foreground = np.zeros((1, 65), np.float64)
    cv2.setRNGSeed(1)
    cv2.grabCut(image, labels, None, background, foreground, 5, cv2.GC_INIT_WITH_MASK)
    sky = np.where((labels == cv2.GC_BGD) | (labels == cv2.GC_PR_BGD), 255, 0).astype(np.uint8)
    for kind, pixels in entry["probes"].items():
        for x, y in pixels:
            if bool(sky[y, x]) != (kind == "sky"):
                raise ValueError(f"{name}: incorrect {kind} probe {(x, y)}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"{name}.png"
    Image.fromarray(sky).save(destination, optimize=True)
    metadata = {
        "kind": "single-channel sky visibility; white sky, black solid landscape",
        "source": entry["source"], "source_sha256": digest,
        "generator": "tools/generate_cloud_masks.py",
        "outline_source": str(OUTLINES.relative_to(ROOT)),
        "method": "v3 source-pixel contour seeds and local source-color graph cut within 12 pixels; verified independent sky/land probes",
        "license": "Same as the source environment asset; provenance remains with that source",
        "size": [width, height],
    }
    destination.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        overlay = image.astype(np.float32)
        overlay[sky > 0] = overlay[sky > 0] * .45 + np.array([255, 40, 240]) * .55
        Image.fromarray(overlay.astype(np.uint8)).save(preview / f"{name}-mask-overlay.png")
    print(f"{name}: {width}x{height}, {destination.stat().st_size} bytes", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-output", type=Path)
    parser.add_argument("--environment", action="append")
    args = parser.parse_args()
    cv2.setNumThreads(2)
    entries = json.loads(OUTLINES.read_text())["environments"]
    for name, entry in entries.items():
        if args.environment and name not in args.environment:
            continue
        generate(name, entry, args.preview_output)


if __name__ == "__main__":
    main()
