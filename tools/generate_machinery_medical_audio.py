#!/usr/bin/env python3
"""Original restrained bunker machinery and treatment contacts, deterministic PCM16."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from generate_aircraft_audio import RATE, LICENSE, NEW_ASSET_PREFIXES, master, shaped_noise

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
SEED = 720391
SECONDS = 8.0
LOOPS = {
    "mixer": "Uneven drum/gear pressure, restrained motor bearings and circular gravel/contact texture",
    "furnace": "Low combustion pressure, circular filtered airflow and sparse irregular hot-material crackle",
}
EFFECTS = {
    "medical_heal": (2, .36, "Short dressing/tool contact, fabric handling and soft pressure release; no musical confirmation"),
    "medical_revive": (2, .60, "Two restrained dressing/tool contacts and controlled respirator/valve release; no speech or melody"),
}


def loop(kind: str) -> np.ndarray:
    count = round(RATE * SECONDS)
    t = np.arange(count) / RATE
    phase = 2 * np.pi * t / SECONDS
    body = shaped_noise(count, 45, 350, SEED)
    air = shaped_noise(count, 170, 1800, SEED + 1)
    fine = shaped_noise(count, 950, 3900, SEED + 2)
    if kind == "mixer":
        rotation = 2 * np.pi * 1.375 * t + .03 * np.sin(phase)
        load = .69 + .18 * np.sin(rotation) + .08 * np.sin(rotation * 3 + .7)
        bearings = np.sin(2 * np.pi * 31.625 * t + .14 * np.sin(rotation))
        gear = np.sin(2 * np.pi * 94.875 * t + .03 * np.sin(phase))
        grit = (.5 + .5 * np.sin(rotation + .8))**4
        signal = (body * .20 + bearings * .11 + gear * .025) * load
        signal += air * (.095 + .12 * grit) + fine * .025 * grit
    elif kind == "furnace":
        convection = .83 + .11 * np.sin(phase + .9) + .055 * np.sin(phase * 3)
        signal = (body * .17 + air * .23) * convection + fine * .018
        rng = np.random.default_rng(SEED + 3)
        # Circular event ages make every crackle continuous through wrap.
        for at in rng.uniform(0, SECONDS, 17):
            age = np.mod(t - at, SECONDS)
            signal += fine * rng.uniform(.017, .043) * np.exp(-age / .017)
    else:
        raise ValueError(kind)
    signal = master(signal, -22, .38)
    seam_cost = np.abs(signal) + 4 * np.abs(signal - np.roll(signal, 1))
    return np.roll(signal, -int(np.argmin(seam_cost)))


def treatment(kind: str, variant: int) -> np.ndarray:
    _, seconds, _ = EFFECTS[kind]
    count = round(seconds * RATE)
    t = np.arange(count) / RATE
    seed = SEED + 10000 + variant * 193 + (503 if kind == "medical_revive" else 0)
    cloth = shaped_noise(count, 450, 2900, seed)
    air = shaped_noise(count, 95, 1450, seed + 1)
    metal = shaped_noise(count, 1000, 5100, seed + 2)
    signal = np.zeros(count)
    for index, at in enumerate([.008, .11] if kind == "medical_revive" else [.008]):
        age = np.maximum(t - at, 0)
        contact = np.exp(-age / (.018 + variant * .002)) * (t >= at)
        signal += (metal * .065 + cloth * .21) * contact * (1 if index == 0 else .7)
    handling = np.minimum(t / .023, 1) * np.exp(-t / .075)
    signal += cloth * .11 * handling
    if kind == "medical_revive":
        age = np.maximum(t - .16, 0)
        release = np.minimum(age / .032, 1) * np.exp(-age / .080) * (t >= .16)
        signal += air * .22 * release
    else:
        signal += air * .10 * handling
    signal = master(signal, -20 if kind == "medical_revive" else -21, .55)
    attack = round(.002 * RATE)
    release = round(.018 * RATE)
    signal[:attack] *= np.linspace(0, 1, attack)
    signal[-release:] *= np.linspace(1, 0, release)
    edge = np.ones(count)
    edge[:attack] = np.linspace(0, 1, attack)
    edge[-release:] = np.linspace(1, 0, release)
    signal -= signal.mean() * edge / edge.mean()
    return signal


def save(path: Path, signal: np.ndarray, role: str, looped: bool, layers: str) -> dict:
    pcm = np.round(signal * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    metadata = {
        "asset": str(path.relative_to(ROOT)), "version": 1,
        "generator": "tools/generate_machinery_medical_audio.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "helper_generator": "tools/generate_aircraft_audio.py",
        "helper_sha256": hashlib.sha256((ROOT / "tools/generate_aircraft_audio.py").read_bytes()).hexdigest(),
        "origin": "Original deterministic mechanism, fabric and airflow design; no borrowed recordings, music or speech.",
        "license": LICENSE, "role": role, "layers": layers, "seed": SEED,
        "sample_rate": RATE, "channels": 1, "pcm_bits": 16,
        "frames": len(pcm), "seconds": len(pcm) / RATE, "loop": looped,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(signal**2)))),
        "peak_dbfs": float(20 * np.log10(np.abs(signal).max())),
        "playback": "Mono SFX source, runtime spatial gain and bounded pooling. Machinery audible only during real production; treatment at successful completion, replacing the old build cue. Existing 50% preferences remain unchanged.",
    }
    path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    path.with_suffix(".LICENSE.txt").write_text(LICENSE + "\n")
    return metadata


def main() -> None:
    preserved = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in OUT.rglob("*") if path.suffix in [".wav", ".ogg"]
                 and not path.name.startswith(NEW_ASSET_PREFIXES)}
    assets = {}
    for kind, layers in LOOPS.items():
        filename = f"machinery_{kind}_v1.wav"
        assets[filename] = save(OUT / filename, loop(kind), kind, True, layers)
    for kind, (count, _, layers) in EFFECTS.items():
        for variant in range(count):
            filename = f"{kind}_{variant + 1:02d}.wav"
            assets[filename] = save(OUT / filename, treatment(kind, variant), kind, False, layers)
    assert all(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest for path, digest in preserved.items())
    (OUT / "machinery_medical_v1_sources.json").write_text(json.dumps({
        "generator": "tools/generate_machinery_medical_audio.py", "license": LICENSE,
        "assets": assets, "preserved_sha256": preserved}, indent=2) + "\n")
    print(f"Generated {len(assets)} machinery/treatment recordings; preserved {len(preserved)} existing WAV/OGG bytes")


if __name__ == "__main__":
    main()
