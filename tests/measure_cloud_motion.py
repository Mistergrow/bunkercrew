#!/usr/bin/env python3
"""Measure rendered flow, plus each layer's contribution to the composed game.
Run after tests/cloud_layer_preview.gd; this does not infer motion from constants.
"""
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

DESTINATION = Path(__file__).resolve().parents[1] / "artifacts/cloud-layers"
measurements = json.loads((DESTINATION / "measurements.json").read_text())
failures = []
checks = 0

def check(value, label):
    global checks
    checks += 1
    print(f"CLOUD IMAGE {'PASS' if value else 'FAIL'}: {label}")
    if not value:
        failures.append(label)

for scene in measurements:
    world = scene["world"]
    full = np.asarray(Image.open(DESTINATION / f"{world}-0s.png"), dtype=np.int16)[..., :3]
    scene["rendered_layers"] = []
    for depth in range(3):
        without = np.asarray(Image.open(DESTINATION / f"{world}-0s-without{depth}.png"), dtype=np.int16)[..., :3]
        visible = int((np.abs(full - without).max(2) > 6).sum())
        first = np.asarray(Image.open(DESTINATION / f"{world}-plane{depth}-0s.png"), dtype=np.float32)
        second = np.asarray(Image.open(DESTINATION / f"{world}-plane{depth}-3s.png"), dtype=np.float32)
        # Premultiplied luminance uses real cloud contours and internal texture.
        a = first[..., :3].mean(2) * first[..., 3] / 255
        b = second[..., :3].mean(2) * second[..., 3] / 255
        window = cv2.createHanningWindow((a.shape[1], a.shape[0]), cv2.CV_32F)
        shift, confidence = cv2.phaseCorrelate(a, b, window)
        expected = scene["speeds"][depth] * 3 * scene["zoom"] * 1.6
        check(abs(shift[0] - expected) < 3 and abs(shift[1]) < 1,
              f"{world} layer{depth}: measured {shift[0]:.2f}px / expected {expected:.2f}px in3s; vertical {shift[1]:.2f}")
        check(visible > 16000, f"{world} layer{depth}: {visible:,} visible pixels in full game composition")
        pan = np.asarray(Image.open(DESTINATION / f"{world}-plane{depth}-pan.png"), dtype=np.float32)
        pa = second[..., :3].mean(2) * second[..., 3] / 255
        pb = pan[..., :3].mean(2) * pan[..., 3] / 255
        camera_shift, camera_confidence = cv2.phaseCorrelate(pa, pb, window)
        expected_camera = -100 * [0.12, 0.38, 0.72][depth] * scene["zoom"] * 1.6
        check(abs(camera_shift[0] - expected_camera) < 3 and abs(camera_shift[1]) < 1,
              f"{world} layer{depth}: camera shift measured {camera_shift[0]:.2f}px / expected {expected_camera:.2f}px")
        scene["rendered_layers"].append({"depth": depth, "visible_composite_pixels": visible,
            "measured_shift_3s": list(shift), "expected_shift_3s": expected, "correlation_confidence": confidence, "camera_shift": list(camera_shift), "expected_camera_shift": expected_camera})
    measured = [layer["measured_shift_3s"][0] for layer in scene["rendered_layers"]]
    check(measured[1] > measured[0] * 3 and measured[2] > measured[1] * 2.8,
          f"{world}: measured depth speeds remain clearly separated")

(DESTINATION / "render-measurements.json").write_text(json.dumps({"checks": checks, "failures": failures,
    "method": "Phase correlation of actual production cloud draw calls; leave-one-layer-out differences in complete real-game frames", "scenes": measurements}, indent=2) + "\n")
raise SystemExit(bool(failures))
