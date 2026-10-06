#!/usr/bin/env python3
"""Finish the dedicated Tessel menu composition and bake its real kick markers.

Run from the repository root; original native settings live in the menu catalog.
No recordings or third-party music are used. Audiote/Tessel licensing applies.
"""
from __future__ import annotations

import hashlib
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
import numpy as np
from scipy.signal import resample_poly
from scipy.io import wavfile
from math import gcd

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "artifacts/menu-rave/source"
ASSET = ROOT / "assets/audio/menu_rave_v1.ogg"
CATALOG = ROOT / "scripts/menu_music_catalog.gd"
RATE = 48000
SECONDARY_TRACK = 8


def write_markers(source: dict) -> tuple[list[int], list[float], list[int], list[float]]:
    source_rate = int(source["rate"])
    events = sorted(source["events"], key=lambda event: int(event["sample"]))
    kicks = [event for event in events if int(event["track"]) == 0]
    secondary = [event for event in events if int(event["track"]) == SECONDARY_TRACK]
    samples = [round(int(event["sample"]) * RATE / source_rate) for event in kicks]
    strengths = [round(float(event["strength"]), 6) for event in kicks]
    secondary_samples = [round(int(event["sample"]) * RATE / source_rate) for event in secondary]
    secondary_strengths = [round(float(event["strength"]), 6) for event in secondary]
    if len(samples) != 128 or any(abs(sample - round(beat * RATE * 60 / 128)) > 1 for beat, sample in enumerate(samples)):
        raise RuntimeError("Native authoring did not produce the promised four-on-the-floor kick grid")
    # Tessel applies the authored tiny swing to offbeat notes. Preserve their
    # actual sample positions instead of snapping them to a hypothetical grid.
    if len(secondary_samples) != 128 or any(abs(sample - round((beat + .5) * RATE * 60 / 128)) > round(RATE * .003) for beat, sample in enumerate(secondary_samples)):
        raise RuntimeError("Native authoring did not produce the actual offbeat bass notes")
    text = CATALOG.read_text()
    for name, values in [("KICK_SAMPLES", samples), ("KICK_STRENGTHS", strengths),
                         ("SECONDARY_SAMPLES", secondary_samples), ("SECONDARY_STRENGTHS", secondary_strengths)]:
        text, count = re.subn(r"const " + name + r" := \[.*?\]", "const " + name + " := " + json.dumps(values), text, flags=re.S)
        if count != 1:
            raise RuntimeError("Expected exactly one baked marker constant: " + name)
    CATALOG.write_text(text)
    return samples, strengths, secondary_samples, secondary_strengths


def loudness(path: Path) -> dict:
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                             "-af", "loudnorm=I=-16.5:TP=-2:LRA=8:print_format=json",
                             "-f", "null", "-"], capture_output=True, text=True, check=True)
    matches = re.findall(r"\{\s*\"input_i\".*?\}", result.stderr, re.S)
    if not matches:
        raise RuntimeError("No real loudness measurement was returned")
    return json.loads(matches[-1])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--markers-only", action="store_true", help="Re-extract real native markers while preserving the existing mastered OGG byte for byte")
    arguments = parser.parse_args()
    subprocess.run(["godot", "--headless", "--path", str(ROOT), "--script",
                    "tools/generate_menu_music.gd", "--", "--no-profile-save", "--no-upnp"], check=True)
    source = json.loads((SOURCE / "native.json").read_text())
    samples, strengths, secondary_samples, secondary_strengths = write_markers(source)
    if arguments.markers_only:
        provenance = json.loads(ASSET.with_suffix(".source.json").read_text())
        if hashlib.sha256(ASSET.read_bytes()).hexdigest() != provenance["sha256"]:
            raise RuntimeError("The existing audio master does not match its provenance")
        provenance.update({"kick_samples": samples, "kick_strengths": strengths,
                           "secondary_track": SECONDARY_TRACK, "secondary_instrument": "short offbeat bass",
                           "secondary_samples": secondary_samples, "secondary_strengths": secondary_strengths,
                           "native_events": source["events"],
                           "markers_method": "Actual kick track-zero and bass track-eight hit events extracted from TesselStream.poll_events(), resampled with PCM"})
        ASSET.with_suffix(".source.json").write_text(json.dumps(provenance, indent=2) + "\n")
        print("Preserved OGG SHA256: " + provenance["sha256"])
        print("Baked %d real kicks and %d independent offbeat bass markers" % (len(samples), len(secondary_samples)))
        return
    pcm = np.fromfile(SOURCE / "native.f32", dtype="<f4").reshape(-1, 2).astype(np.float64)
    source_rate = int(source["rate"])
    if source_rate != RATE:
        common = gcd(source_rate, RATE)
        pcm = resample_poly(pcm, RATE // common, source_rate // common, axis=0)
    if len(pcm) != RATE * 60 or not np.isfinite(pcm).all():
        raise RuntimeError("The menu master must contain exactly sixty seconds of finite stereo PCM")
    pcm -= pcm.mean(axis=0)
    # Two milliseconds join the quiet pre-kick tail to the next attack. No
    # padding/crossfade overlap changes the 32-bar length or event timestamps.
    seam_frames = round(RATE * .002)
    bridge = (1 - np.cos(np.linspace(0, np.pi, seam_frames))) / 2
    pcm[-seam_frames:] += bridge[:, None] * (pcm[0] - pcm[-1])
    with tempfile.TemporaryDirectory(prefix="bunkercrew-menu-master-") as directory:
        wave = Path(directory) / "menu-master.wav"
        wavfile.write(wave, RATE, pcm.astype(np.float32))
        measured = loudness(wave)
        gain_db = min(-16.5 - float(measured["input_i"]), -2 - float(measured["input_tp"]))
        pcm *= 10 ** (gain_db / 20)
        wavfile.write(wave, RATE, pcm.astype(np.float32))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wave), "-c:a", "libvorbis",
                        "-q:a", "6", "-metadata", "title=" + source["title"],
                        "-metadata", "artist=Bunkercrew / Audiote", str(ASSET)], check=True)
        decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", str(ASSET), "-f", "f32le",
                                  "-acodec", "pcm_f32le", "-"], capture_output=True, check=True)
        decoded_pcm = np.frombuffer(decoded.stdout, dtype="<f4").reshape(-1, 2)
        if len(decoded_pcm) != RATE * 60 or not np.isfinite(decoded_pcm).all():
            raise RuntimeError("The decoded OGG lost samples or contains non-finite output")
        final = loudness(ASSET)
    maximum_delta = float(np.max(np.abs(np.diff(decoded_pcm, axis=0))))
    seam_delta = float(np.max(np.abs(decoded_pcm[-1] - decoded_pcm[0])))
    if float(final["input_tp"]) > -1.8 or seam_delta > .005:
        raise RuntimeError("The decoded loop exceeded its true-peak or seam tolerance")
    provenance = {"title": source["title"], "asset": ASSET.name, "version": 1,
                  "license": "Distribution only together with Bunkercrew",
                  "engine": "Bunkercrew Tessel / Audiote native synthesizer",
                  "source": "native/bunkercrew_audio/third_party/tessel/SOURCE.json",
                  "generator": "tools/generate_menu_music.py", "native_generator": "tools/generate_menu_music.gd",
                  "composition": "Original A-minor minimal-techno menu rave; restrained offbeat bass, hats and sparse low stabs",
                  "bpm": 128, "bars": 32, "seconds": 60.0, "rate": RATE, "native_rate": source_rate,
                  "seed": source["seed"], "native_settings": source["settings"],
                  "kick_samples": samples, "kick_strengths": strengths, "native_events": source["events"],
                  "secondary_track": SECONDARY_TRACK, "secondary_instrument": "short offbeat bass",
                  "secondary_samples": secondary_samples, "secondary_strengths": secondary_strengths,
                  "markers_method": "Actual kick track-zero and bass track-eight hit events extracted from TesselStream.poll_events(), resampled with PCM",
                  "finishing": "DC removal, 2 ms circular seam bridge, linear loudness trim; no timestamp shift or padding",
                  "gain_db": round(gain_db, 4), "measurements": {
                      "decoded_frames": len(decoded_pcm), "integrated_lufs": float(final["input_i"]),
                      "true_peak_dbtp": float(final["input_tp"]), "loudness_range_lu": float(final["input_lra"]),
                      "rms": float(np.sqrt(np.mean(decoded_pcm.astype(np.float64) ** 2))),
                      "peak": float(np.max(np.abs(decoded_pcm))), "loop_sample_delta": seam_delta,
                      "maximum_internal_sample_delta": maximum_delta,
                      "seam_ratio_to_maximum_internal_delta": seam_delta / max(maximum_delta, 1e-9)},
                  "sha256": hashlib.sha256(ASSET.read_bytes()).hexdigest(), "bytes": ASSET.stat().st_size}
    ASSET.with_suffix(".source.json").write_text(json.dumps(provenance, indent=2) + "\n")
    ASSET.with_suffix(".LICENSE.txt").write_text("Original Bunkercrew menu composition, generated with the Audiote / Tessel engine.\n"
                                             "Distribution permitted only together with Bunkercrew, under the permission granted for Audiote.\n"
                                             "No third-party music recordings or samples are included.\n")
    print(json.dumps(provenance["measurements"], indent=2))


if __name__ == "__main__":
    main()
