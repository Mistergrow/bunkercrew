#!/usr/bin/env python3
"""Layer CC0 recorded foley into enemy contacts and original research cues.

Only writes the enemy_step_* and tech_upgrade_* banks. Existing audio is preserved.
Requires numpy, scipy and ffmpeg. Source recordings and CC0 license are local.
"""
from functools import lru_cache
from pathlib import Path
import hashlib
import json
import math
import subprocess
import wave

import numpy as np
from scipy.signal import butter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
SOURCES = OUT / "source_recordings/enemy_foley"
RATE = 48000
VARIANTS = 5
SURFACES = ("dry", "metal", "ice", "water")
# duration, recorded chassis contact, playback speed, modal frequency, damping.
FAMILIES = {
    "mech_light": (.28, "impactMetal_light", 1.18, 185, .025),
    "mech_quad": (.34, "impactPlate_light", 1.03, 130, .040),
    "mech_assault": (.33, "impactMetal_medium", .96, 113, .042),
    "mech_heavy": (.44, "impactPlate_heavy", .78, 73, .065),
    "mech_colossus": (.54, "impactMetal_heavy", .64, 48, .095),
    "boot_light": (.27, "footstep_concrete", 1.17, 155, .020),
    "boot_standard": (.33, "footstep_concrete", 1.00, 122, .029),
    "boot_heavy": (.40, "footstep_concrete", .87, 95, .038),
}
ENEMY_FAMILIES = {
    "runner": "mech_light", "lancer": "mech_light",
    "strider": "mech_quad", "shield_guard": "mech_quad", "repair_crawler": "mech_quad",
    "assault": "mech_assault", "sniper": "mech_assault",
    "breaker": "mech_heavy", "demolisher": "mech_heavy", "siege": "mech_heavy",
    "colossus": "mech_colossus", "bastion": "mech_colossus",
    "scout": "boot_light", "marksman": "boot_light",
    "rifle_guard": "boot_standard", "grenadier": "boot_standard", "combat_medic": "boot_standard",
    "heavy_gunner": "boot_heavy",
}
UPGRADES = ("base", "weapons", "crew", "vehicle")


def envelope(t, at, decay, attack=.002):
    age = np.maximum(t - at, 0)
    return (1 - np.exp(-age / attack)) * np.exp(-age / decay) * (t >= at)


def texture(t, rng, low, high):
    value = sosfilt(butter(2, [low, high], "bandpass", fs=RATE, output="sos"), rng.normal(size=len(t)))
    return value / max(float(value.std()), 1e-9)


@lru_cache(maxsize=160)
def recording(family, index, speed=1.0):
    path = SOURCES / f"{family}_{index % 5:03d}.ogg"
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le",
                          "-ac", "1", "-ar", str(RATE), "-"], check=True, capture_output=True).stdout
    data = np.frombuffer(pcm, dtype="<f4").astype(float)
    # Trim recording padding, preserving 2 ms before the first contact.
    active = np.flatnonzero(np.abs(data) > max(float(np.max(np.abs(data))) * .008, .0003))
    if not len(active):
        raise ValueError(f"Silent source: {path}")
    data = data[max(0, active[0] - 96):min(len(data), active[-1] + 960)]
    data -= data.mean()
    # Polyphase resampling includes an anti-alias filter for faster contacts.
    data = resample_poly(data, 1000, round(speed * 1000))
    data = sosfilt(butter(2, [45, 11000], "bandpass", fs=RATE, output="sos"), data)
    return data / max(float(np.max(np.abs(data))), 1e-9)


def put(track, data, at, gain):
    first = round(at * RATE)
    length = min(len(data), len(track) - first)
    if length > 0:
        track[first:first + length] += data[:length] * gain


def finish(signal, peak, release=.035):
    signal = sosfilt(butter(2, [35, 12500], "bandpass", fs=RATE, output="sos"), signal, axis=0)
    t = np.arange(len(signal)) / RATE
    fade = np.sin(np.minimum(t / .002, 1) * np.pi / 2) ** 2
    fade *= np.sin(np.clip((len(signal) / RATE - 1 / RATE - t) / release, 0, 1) * np.pi / 2) ** 2
    signal *= fade if signal.ndim == 1 else fade[:, None]
    # Remove DC without reintroducing nonzero endpoints.
    window = np.sin(np.pi * np.arange(len(signal)) / (len(signal) - 1)) ** 2
    if signal.ndim == 1:
        signal -= window * signal.sum() / window.sum()
    else:
        signal -= window[:, None] * signal.sum(axis=0) / window.sum()
    signal *= peak / max(float(np.max(np.abs(signal))), 1e-9)
    return signal


def contact(family, surface, variant):
    duration, source, speed, frequency, decay = FAMILIES[family]
    seed = 910721 + list(FAMILIES).index(family) * 1009 + variant * 163
    rng = np.random.default_rng(seed)
    t = np.arange(round(duration * RATE)) / RATE
    result = np.zeros(len(t))
    mechanical = family.startswith("mech_")
    detune = rng.uniform(.975, 1.025)
    strike = .010 if mechanical else .003
    body = recording(source, variant, round(speed * detune, 3))
    # Damp metallic recorded tails to avoid an incessant ringing crowd.
    body = body * np.exp(-np.arange(len(body)) / RATE / (.065 if mechanical else .12))
    put(result, body, strike, .64 if mechanical else .60)
    age = np.maximum(t - strike, 0)
    for index, mode in enumerate([1, 1.81, 2.73, 4.16]):
        result += np.sin(2 * np.pi * frequency * mode * detune * age) * envelope(t, strike, decay / (1 + index * .3)) * (.18 if mechanical else .035) / (index + 1) ** 1.7
    if mechanical:
        latch_at = .046 + rng.uniform(-.007, .012)
        put(result, recording("impactTin_medium", variant + 2, 1.13), latch_at, .09)
        servo = texture(t, rng, 300, 1450)
        result += servo * envelope(t, .014, .034, .014) * .023
        # Small separated gear contacts distinguish multi-legged machinery.
        if family == "mech_quad":
            put(result, recording("impactMetal_light", variant + 1, 1.25), .073, .065)
    else:
        put(result, recording("footstep_carpet", variant + 1, 1.04), .040, .12)
        if family == "boot_heavy":
            put(result, recording("impactMetal_light", variant + 3, .91), .058, .045)
    if surface == "dry":
        put(result, recording("footstep_grass", variant, 1.10), .014, .16 if mechanical else .22)
    elif surface == "metal":
        put(result, recording("impactPlate_light", variant + 1, 1.12), .008, .19)
    elif surface == "ice":
        put(result, recording("footstep_snow", variant, .98), .006, .38 if mechanical else .46)
    elif surface == "water":
        # Original shallow splash texture, no borrowed water recording.
        result += texture(t, rng, 420, 3900) * envelope(t, .024, .050, .010) * .11
        for at in rng.uniform(.045, min(.20, duration - .07), 7):
            age = np.maximum(t - at, 0)
            bubble = rng.uniform(540, 950)
            result += np.sin(2 * np.pi * (bubble * age - bubble * 1.5 * age ** 2)) * envelope(t, at, .008) * .023
    return finish(result, .62 if family in ["mech_heavy", "mech_colossus"] else .52)


def upgrade(branch, variant):
    rng = np.random.default_rng(810319 + UPGRADES.index(branch) * 761 + variant * 127)
    duration = {"base": 1.05, "weapons": .86, "crew": .98, "vehicle": 1.16}[branch]
    t = np.arange(round(duration * RATE)) / RATE
    result = np.zeros((len(t), 2))

    def layer(data, at, gain, pan=0.0):
        mono = np.zeros(len(t))
        put(mono, data, at, gain)
        result[:] += mono[:, None] * np.array([math.sqrt((1 - pan) / 2), math.sqrt((1 + pan) / 2)])

    times = np.array([.01, .10, .24]) + rng.uniform(-.005, .005, 3)
    source = {"base": "impactPlate_light", "weapons": "impactMetal_light",
              "crew": "impactWood_light", "vehicle": "impactMetal_medium"}[branch]
    for index, at in enumerate(times):
        layer(recording(source, variant + index, 1.1 + index * .11), max(0, at), [.13, .09, .20][index], (index - 1) * .10)
    # A shared restrained three-note confirmation identifies completed research;
    # each branch has its own voicing, resonances and physical assembly sound.
    fundamental = {"base": 196.0, "weapons": 293.665, "crew": 261.626, "vehicle": 146.832}[branch]
    intervals = [1.0, 1.25, 1.5]
    for index, ratio in enumerate(intervals):
        at = .19 + index * .105
        age = np.maximum(t - at, 0)
        tone = np.zeros(len(t))
        for partial, gain in [(1, .11), (2.01, .021), (3.96, .007)]:
            tone += np.sin(2 * np.pi * fundamental * ratio * partial * age) * envelope(t, at, .145 / partial, .004) * gain
        layer(tone, 0, 1.0, (index - 1) * .13)
    if branch == "base":
        layer(recording("impactSoft_heavy", variant, .81), .25, .10)
    elif branch == "weapons":
        layer(recording("impactTin_medium", variant + 1, 1.32), .34, .07)
    elif branch == "crew":
        layer(recording("footstep_carpet", variant, .95), .03, .055)
    else:
        motor = np.sin(2 * np.pi * 74 * t) + .22 * np.sin(2 * np.pi * 148 * t)
        layer(motor * envelope(t, .09, .13, .035), 0, .035)
        layer(recording("impactPlate_heavy", variant, .92), .29, .06)
    # Short stereo room reflections, preserving a clear center transient.
    dry = result.copy()
    for delay, gain in [(.031, .065), (.057, .040), (.093, .020)]:
        shift = round(delay * RATE)
        result[shift:] += dry[:-shift, ::-1] * gain
    return finish(result, .50, release=.075)


def save(path, signal):
    pcm = np.round(signal * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1 if signal.ndim == 1 else 2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    return {"seconds": round(len(signal) / RATE, 5), "channels": 1 if signal.ndim == 1 else 2,
            "peak": round(float(np.max(np.abs(signal))), 5), "rms": round(float(np.sqrt(np.mean(signal ** 2))), 5),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def generate():
    preserved = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir()
                 if p.suffix in [".wav", ".ogg"] and not p.name.startswith(("enemy_step_", "tech_upgrade_"))}
    metrics = {}
    for family in FAMILIES:
        for surface in SURFACES:
            for variant in range(VARIANTS):
                name = f"enemy_step_{family}_{surface}_{variant + 1:02d}.wav"
                metrics[name] = save(OUT / name, contact(family, surface, variant))
    for branch in UPGRADES:
        for variant in range(3):
            name = f"tech_upgrade_{branch}_{variant + 1:02d}.wav"
            metrics[name] = save(OUT / name, upgrade(branch, variant))
    assert all(hashlib.sha256((OUT / name).read_bytes()).hexdigest() == digest for name, digest in preserved.items())
    provenance = json.loads((SOURCES / "sources.json").read_text())
    metadata = {"generator": "tools/generate_enemy_tech_audio.py", "generated_at": "2026-10-02",
                "origin": "Layered Kenney CC0 recorded foley with original modal bodies, servo textures, shallow splashes and research motifs. No AI audio model used.",
                "source_pack": provenance, "sample_rate": RATE, "format": "PCM16 WAV",
                "enemy_families": ENEMY_FAMILIES, "surfaces": SURFACES, "variants_per_contact": VARIANTS,
                "upgrade_branches": UPGRADES, "variants_per_upgrade": 3,
                "preserved_files": len(preserved), "preserved_sha256": preserved, "assets": metrics,
                "review": "Objective signal checks and in-engine mixer capture; listening gallery provided for human review."}
    (OUT / "enemy_tech_sources.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Generated {len(metrics)} 48 kHz WAV assets; preserved {len(preserved)} existing files.")


if __name__ == "__main__":
    generate()
