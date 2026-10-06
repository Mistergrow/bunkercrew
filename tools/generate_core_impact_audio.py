#!/usr/bin/env python3
"""Author five dry core contacts from the local Kenney CC0 impact bank.

Recorded steel transients, small fractured contacts and a short damped body
replace the generic synthesized metal bank. No oscillator, pitch sweep, bass
drum, rhythmic layer or artificial room tail is added. Only impact_core assets
and their own provenance are written; all earlier audio is preserved.
"""
from datetime import date
from pathlib import Path
import hashlib
import json
import subprocess
import wave

import numpy as np
from scipy.signal import butter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
SOURCE = OUT / "source_recordings/enemy_foley"
RATE = 48000
VARIANTS = 5


def recorded(family, variant, low, high, damping, speed=1.0):
    path = SOURCE / f"{family}_{variant % VARIANTS:03d}.ogg"
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le",
        "-ac", "1", "-ar", str(RATE), "-",
    ])
    data = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    active = np.flatnonzero(np.abs(data) > np.max(np.abs(data)) * .008)
    if not len(active):
        raise ValueError(f"Silent contact recording: {path}")
    data = data[max(0, int(active[0]) - 48):int(active[-1]) + 1]
    data = resample_poly(data, 1000, round(speed * 1000))
    data = sosfilt(butter(2, [low, high], "bandpass", fs=RATE, output="sos"), data)
    if family == "impactMetal_medium":
        # This pack's medium steel contacts share a strong ~1 kHz ringing
        # mode. Suppress that recorded resonance so repeated core damage
        # reads as a rough physical strike rather than a tuned percussion hit.
        data = sosfilt(butter(3, [760, 1450], "bandstop", fs=RATE, output="sos"), data)
    data *= np.exp(-np.arange(len(data)) / RATE / damping)
    data /= max(float(np.max(np.abs(data))), 1e-12)
    return data


def contact(variant):
    duration = [.230, .245, .260, .240, .275][variant]
    result = np.zeros(round(duration * RATE))

    def layer(family, index, gain, at, low, high, damping, speed=1.0):
        recording = recorded(family, index, low, high, damping, speed)
        start = round(at * RATE)
        count = min(len(recording), len(result) - start)
        result[start:start + count] += recording[:count] * gain

    # A sharp, medium steel strike has less sub-bass than the heavy recordings.
    # The separate high-passed heavy layer supplies a dense, rough structure
    # without the low resonant "bum" that was mistaken for the music drums.
    layer("impactMetal_medium", variant, .72, .001, 185, 10500, .045, 1.02)
    layer("impactMetal_heavy", variant + 1, .23, .003, 340, 6500, .030, 1.04)
    layer("impactWood_light", variant + 2, .13, .006 + variant * .0013, 720, 8000, .022, 1.11)
    layer("impactMetal_light", variant + 3, .035, .014 + variant * .0011, 1300, 10800, .010, 1.07)
    # Very brief debris rattles are irregular secondary contacts, not beats.
    layer("impactTin_medium", variant + 1, .04, .023 + variant * .0021, 950, 7500, .012, 1.13)
    time = np.arange(len(result)) / RATE
    fade = np.sin(np.minimum(time / .0008, 1) * np.pi / 2) ** 2
    fade *= np.sin(np.clip((duration - 1 / RATE - time) / .025, 0, 1) * np.pi / 2) ** 2
    result *= fade
    # Remove DC while retaining exact silent edges and all natural transients.
    window = np.sin(np.arange(len(result)) * np.pi / (len(result) - 1)) ** 2
    result -= window * result.sum() / window.sum()
    result *= .64 / max(float(np.max(np.abs(result))), 1e-12)
    return result


def generate():
    old_assets = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in OUT.iterdir() if path.suffix in {".wav", ".ogg"}
                  and not path.name.startswith("impact_core_")}
    source_metadata = json.loads((SOURCE / "sources.json").read_text())
    used_sources = {}
    for family in ["impactMetal_medium", "impactMetal_heavy", "impactWood_light", "impactMetal_light", "impactTin_medium"]:
        for variant in range(VARIANTS):
            path = SOURCE / f"{family}_{variant:03d}.ogg"
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != source_metadata["files"][path.name]:
                raise ValueError(f"Changed source recording: {path}")
            used_sources[path.name] = digest
    for variant in range(VARIANTS):
        signal = contact(variant)
        path = OUT / f"impact_core_{variant + 1:02d}.wav"
        pcm = np.round(signal * 32767).astype("<i2")
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(pcm.tobytes())
        metadata = {
            "generator": "tools/generate_core_impact_audio.py",
            "generated_at": date.today().isoformat(), "variant": variant + 1,
            "origin": "Short, damped layers of the local Kenney CC0 Impact Sounds recordings; no synthesized tonal body or musical percussion.",
            "source_author": "Kenney", "source_pack": "Impact Sounds",
            "source_page": source_metadata["page"], "source_license": "CC0-1.0",
            "source_license_url": source_metadata["license_url"],
            "source_recordings": used_sources, "sample_rate": RATE,
            "channels": 1, "format": "PCM16 WAV",
            "seconds": len(signal) / RATE, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "peak": float(np.max(np.abs(pcm))) / 32768,
            "processing": {"recorded_layers": 5, "added_oscillators": 0, "reverb": False,
                           "primary_highpass_hz": 185, "heavy_body_highpass_hz": 340,
                           "medium_steel_ring_bandstop_hz": [760, 1450],
                           "longest_decay_seconds": .045, "peak_target": .64},
        }
        path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
        path.with_suffix(".LICENSE.txt").write_text(
            "Bunkercrew core impact variant\n\n"
            "Source: Kenney, Impact Sounds (1.0), https://kenney.nl/assets/impact-sounds\n"
            "License: Creative Commons Zero, CC0-1.0\n"
            "https://creativecommons.org/publicdomain/zero/1.0/\n\n"
            "Audio processing and layered derivative are also released under CC0-1.0.\n"
            "Original license: assets/audio/source_recordings/enemy_foley/License.txt\n"
        )
    for name, digest in old_assets.items():
        if hashlib.sha256((OUT / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Unexpected modification to earlier audio: {name}")
    print(f"Generated {VARIANTS} dry 48 kHz core impacts; preserved {len(old_assets)} earlier recordings.")


if __name__ == "__main__":
    generate()
