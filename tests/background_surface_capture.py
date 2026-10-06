#!/usr/bin/env python3
"""Capture real gameplay surface motion and trim native 60 FPS comparison clips."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/background-surfaces/native"


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    raw_movie = OUTPUT / "native-source.avi"
    with tempfile.TemporaryDirectory(prefix="bunkercrew-surface-capture-") as isolated:
        env = os.environ.copy()
        for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            env[name] = str(Path(isolated) / name)
        arguments = sys.argv[1:]
        if "--software-renderer" in arguments:
            env.update({"LIBGL_ALWAYS_SOFTWARE": "1", "__GLX_VENDOR_LIBRARY_NAME": "mesa",
                        "MESA_LOADER_DRIVER_OVERRIDE": "llvmpipe"})
            arguments = [value for value in arguments if value != "--software-renderer"]
        command = [
            "godot", "--path", str(ROOT), "--resolution", "1440x900",
            "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--write-movie", str(raw_movie),
            "--script", "tests/background_surface_native_test.gd", "--",
            "--no-profile-save", "--no-upnp", "--video",
        ]
        command.extend(arguments)
        process = subprocess.run(
            command, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=600,
        )
    (OUTPUT / "capture.log").write_text(process.stdout)
    print(process.stdout, flush=True)
    vsync_warning = "WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver."
    environment_warnings = []
    if "Mesa - llvmpipe" in process.stdout and vsync_warning in process.stdout:
        environment_warnings.append(vsync_warning)
    issues = [line for line in process.stdout.splitlines()
              if ("ERROR:" in line or "WARNING:" in line) and line not in environment_warnings]
    if process.returncode or issues:
        raise SystemExit(process.returncode or 1)
    report = json.loads((OUTPUT / "verification.json").read_text())
    if report["failures"]:
        raise SystemExit(1)
    retained = OUTPUT / "native-source-retained.avi"
    retained.unlink(missing_ok=True)
    os.link(raw_movie, retained)
    media: list[dict] = []
    for segment in report["video_segments"]:
        name = f"{segment['id']}-{segment['mode']}"
        full = OUTPUT / f"{name}.mp4"
        crop = OUTPUT / f"{name}-surface.mp4"
        trim = (
            f"trim=start_frame={segment['start_frame']}:"
            f"end_frame={segment['end_frame']},setpts=PTS-STARTPTS"
        )
        for destination, filters in ((full, trim), (crop, trim + ",crop=1440:600:0:0")):
            run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(raw_movie), "-vf", filters, "-an", "-r", "60",
                "-c:v", "libx264", "-preset", "fast", "-crf", "0",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(destination),
            ])
        poster = OUTPUT / f"{name}-poster.png"
        run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", "1.25", "-i", str(crop), "-frames:v", "1", str(poster),
        ])
        media.append({"scene": segment["id"], "comparison": segment["mode"],
                      "full": full.name, "surface": crop.name, "poster": poster.name,
                      "fps": 60, "source_frames": [segment["start_frame"], segment["end_frame"]],
                      "speed": "normal", "silent": True})
    source_hashes = {}
    for relative in (
        "shaders/parallax_valley.gdshader", "shaders/background_sampling.gdshaderinc",
        "shaders/background_fragment.gdshaderinc", "scripts/parallax_landscape.gd",
        "assets/environments/background_surface_regions.json",
        "assets/environments/surface_masks/catalog.json",
    ):
        source_hashes[relative] = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
    (OUTPUT / "capture-manifest.json").write_text(json.dumps(
        {"prepared": report["prepared"], "media": media,
         "source_hashes": source_hashes, "checks": report["checks"], "failures": 0,
         "renderer": report["renderer"], "environment_warnings": environment_warnings}, indent=2,
    ) + "\n")
    raw_movie.unlink()
    raw_movie.with_suffix(".wav").unlink(missing_ok=True)
    print(f"Saved {len(media)} real gameplay segments, 60FPS, normal speed; all native checks passed.")


if __name__ == "__main__":
    main()
