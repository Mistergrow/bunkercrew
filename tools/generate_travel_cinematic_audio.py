#!/usr/bin/env python3
"""Author six original roadside scene recordings without touching older banks."""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/travel_cinematics"
RATE = 48000
SEED = 840173
TAU = 2 * np.pi
LICENSE = "Original Bunkercrew sound design; distribution only together with Bunkercrew."
SPECS = {
    "signal_receiver_v1": (7.50, "bed", 0.48,
        "Quiet verge wind, restrained receiver static fading as the right-hand relay acquires power"),
    "signal_relay_lock_v1": (.90, "cue", 0.49,
        "Physical electrical contact, two receiver detents and a muted relay housing resonance"),
    "storm_roof_rain_v1": (7.85, "bed", 0.0,
        "Irregular rain on the shelter roof, diffuse wet wind and restrained tin resonances"),
    "storm_branch_snap_v1": (.78, "cue", 0.64,
        "Dry branch fracture, layered small splinters and the struck tree's damped wooden body"),
    "supply_generator_v1": (6.25, "bed", 0.088,
        "Wind on the verge, a small loaded diesel generator catching as its pictured fan starts"),
    "supply_shutter_v1": (1.625, "cue", 0.48,
        "Rolling steel shutter, guide-wheel chatter, granular sliding friction and final upper stop"),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def noise(t, rng, low, high):
    raw = rng.normal(size=len(t))
    filtered = sosfilt(butter(3, [low, high], "bandpass", fs=RATE, output="sos"), raw)
    return filtered / max(float(np.std(filtered)), 1e-12)


def pan(signal, position):
    return signal[:, None] * np.array([np.sqrt((1 - position) * .5),
                                       np.sqrt((1 + position) * .5)])


def burst(t, at, decay, attack=.0015):
    age = np.maximum(t - at, 0)
    return (1 - np.exp(-age / attack)) * np.exp(-age / decay) * (t >= at)


def modes(t, at, frequencies, gain, decay, rng):
    age = np.maximum(t - at, 0)
    value = sum(np.sin(TAU * frequency * rng.uniform(.985, 1.015) * age) / (index + 1) ** 1.7
                for index, frequency in enumerate(frequencies))
    return value * burst(t, at, decay, .0008) * gain


def smoothstep(low, high, value):
    p = np.clip((value - low) / (high - low), 0, 1)
    return p * p * (3 - 2 * p)


def render(kind):
    seconds, role, position, _ = SPECS[kind]
    rng = np.random.default_rng(SEED + list(SPECS).index(kind) * 1009)
    t = np.arange(round(RATE * seconds)) / RATE
    result = np.zeros((len(t), 2))
    low = noise(t, rng, 45, 360)
    middle = noise(t, rng, 230, 1450)
    grit = noise(t, rng, 1200, 5700)
    if role == "bed":
        gust = .74 + .12 * np.sin(t * 1.13) + .08 * np.sin(t * 2.7 + 1.3)
        result += pan(low * gust * .075, 0.0 if kind == "supply_generator_v1" else -.13)
        for channel in range(2):
            result[:, channel] += noise(t, rng, 130, 1300) * gust * .022
    if kind == "signal_receiver_v1":
        acquiring = 1 - smoothstep(1.5, 3.68, t)
        static = grit * (.08 + .22 * acquiring) * (.72 + .28 * np.sin(t * 18.3) ** 2)
        cabinet = .035 * np.sin(TAU * 96.5 * t + .08 * np.sin(t * 3.7))
        result += pan(static + cabinet, position)
    elif kind == "signal_relay_lock_v1":
        value = modes(t, .015, (183, 569, 1439), .24, .045, rng)
        value += middle * burst(t, .014, .02) * .08
        for at, gain in [(.19, .18), (.31, .10)]:
            value += modes(t, at, (371, 1153, 2543), gain, .030, rng)
        value += low * burst(t, .035, .09, .008) * .09
        result += pan(value, position)
    elif kind == "storm_roof_rain_v1":
        result += pan(middle * .080 + grit * .027, -.22)
        result += pan(noise(t, rng, 470, 4200) * .045, .32)
        for at in np.sort(rng.uniform(.03, seconds - .18, 138)):
            strike = modes(t, at, (823, 1493, 2581), rng.uniform(.02, .075),
                           rng.uniform(.011, .032), rng)
            result += pan(strike, rng.uniform(-.65, .65))
    elif kind == "storm_branch_snap_v1":
        value = modes(t, .012, (103, 237, 579), .27, .08, rng)
        value += middle * burst(t, .009, .019) * .17
        for at in [.031, .069, .12, .185]:
            value += grit * burst(t, at, .012) * rng.uniform(.045, .10)
            value += modes(t, at, (413, 947, 1931), .05, .019, rng)
        result += pan(value, position)
    elif kind == "supply_generator_v1":
        power = smoothstep(1.0, 1.875, t)
        phase = TAU * (24.5 * t + 6.0 * np.maximum(t - 1.0, 0) ** .55)
        phase += .25 * np.sin(t * 9.7) + .08 * np.sin(t * 23.1)
        diesel = sum(gain * np.sin(harmonic * phase + harmonic * .17)
                     for harmonic, gain in [(1, .18), (2, .11), (3, .045), (6, .014)])
        diesel += middle * (.5 + .5 * np.cos(phase)) ** 4 * .055
        diesel += low * .040
        result += pan(diesel * power, position)
    elif kind == "supply_shutter_v1":
        travel = smoothstep(.015, .12, t) * (1 - smoothstep(1.34, 1.49, t))
        value = middle * travel * (.075 + .025 * np.sin(t * 51) ** 2)
        value += grit * travel * .028
        for index, at in enumerate(np.arange(.045, 1.36, .067)):
            value += modes(t, at, (167, 439, 967), .028 if index % 3 else .06, .024, rng)
        value += modes(t, 1.435, (93, 317, 827), .28, .05, rng)
        value += low * burst(t, 1.438, .055, .004) * .10
        result += pan(value, position)
    # Keep only physical lower-mid textures. The presence-band reduction leaves
    # the existing DE/EN recordings space while retaining roof and latch detail.
    result = sosfilt(butter(3, [38, 6200], "bandpass", fs=RATE, output="sos"), result, axis=0)
    attack = .20 if role == "bed" else .003
    release = .32 if role == "bed" else .065
    result *= (np.sin(np.clip(t / attack, 0, 1) * np.pi / 2) ** 2)[:, None]
    result *= (np.sin(np.clip((seconds - 1 / RATE - t) / release, 0, 1) * np.pi / 2) ** 2)[:, None]
    window = np.sin(np.pi * np.arange(len(t)) / (len(t) - 1)) ** 2
    result -= window[:, None] * result.sum(axis=0) / window.sum()
    target_rms = 10 ** ((-25.0 if role == "bed" else -22.0) / 20)
    gain = min(target_rms / np.sqrt(np.mean(result ** 2)), .44 / np.max(np.abs(result)))
    return result * gain


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source_sha = digest(Path(__file__))
    assets = {}
    for kind, (seconds, role, position, layers) in SPECS.items():
        signal = render(kind)
        pcm = np.round(signal * 32767).astype("<i2")
        path = OUT / (kind + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setparams((2, 2, RATE, len(pcm), "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        metadata = {"asset": str(path.relative_to(ROOT)), "generator": "tools/generate_travel_cinematic_audio.py",
            "generator_sha256": source_sha, "source": "Original deterministic stereo synthesis; no external samples or recordings.",
            "license": LICENSE, "role": role, "layers": layers, "seed": SEED + list(SPECS).index(kind) * 1009,
            "sample_rate": RATE, "channels": 2, "pcm_bits": 16, "frames": len(pcm), "seconds": seconds,
            "loop": False, "screen_pan": position,
            "mix": {"bus": "SFX", "additional_dialogue_duck_db": -7.0,
                    "note": "Authored stereo follows the visible object's horizontal position; existing sliders and buses remain unchanged."},
            "measurements": {"peak_dbfs": float(20 * np.log10(np.abs(signal).max())),
                             "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(signal ** 2))))},
            "sha256": digest(path)}
        path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
        path.with_suffix(".LICENSE.txt").write_text(LICENSE + "\n" + metadata["source"] + "\n")
        assets[path.name] = metadata
    manifest = {"generator": "tools/generate_travel_cinematic_audio.py", "generator_sha256": source_sha,
        "license": LICENSE, "assets": assets,
        "reuse": {"storm_thunder": "assets/audio/thunder_01.wav", "air_raid_flyover": "assets/audio/air_raid_flyover_v1.wav",
                 "dialogue": "Existing identity-matched German/English story_voices_v2 recordings"},
        "validation": "python3 tests/travel_cinematic_audio_assets_test.py; Godot tests/travel_cinematic_audio_test.gd"}
    (OUT / "sources.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Rendered {len(SPECS)} original roadside cinematic recordings in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
