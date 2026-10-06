#!/usr/bin/env python3
"""Original aircraft mechanisms and airborne ordnance, deterministic PCM16.

No borrowed recordings, speech, music or instrument patches. Periodic engines
have complete integer-period harmonics and circularly filtered airflow. One-shots
layer mechanical contacts, pressure bursts, fin friction and electrical discharge.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
RATE = 48000
LOOP_SECONDS = 8.0
SEED = 910271
LICENSE = "Original Bunkercrew sound design. Distribution only together with Bunkercrew; standalone redistribution and use in other projects are not permitted."
NEW_ASSET_PREFIXES = ("air_engine_", "air_dart_", "air_tracer_", "air_rocket_", "air_bomb_", "air_arc_", "air_charge_", "air_lock_", "air_crash_", "machinery_", "medical_heal_", "medical_revive_")
ENGINES = {
    "rotor": "Asynchronous blade-pressure passes, dry electric rotor bearings and narrow hull resonance",
    "propeller": "Piston compression, uneven two-blade air cuts, intake and a restrained mechanical valve layer",
    "tiltrotor": "Two broad blade-pressure trains, geared transmission and a heavier ducted-air load",
    "jet": "Broad intake/exhaust pressure, restrained turbine harmonics and a speech-band notch",
    "airship": "Slow side-propeller pressure, low hull air volume and occasional braced-frame bearing tension",
    "vtol": "Four ducted fan pressure passes, asynchronous drive components and low hover pressure",
}
EFFECTS = {
    "air_dart": (3, .20, -16.5, "Sharp pneumatic needle launch, short valve contact and displaced air"),
    "air_tracer": (3, .30, -14.5, "Dry autocannon pressure report, breech contact and short ejection mechanism"),
    "air_rocket": (3, .74, -14.0, "Igniter snap, nonmusical motor pressure and fin/rail release"),
    "air_bomb": (3, .68, -17.0, "Bomb-rack latch, heavy release contact and falling fin airflow; no premature detonation"),
    "air_arc": (3, .48, -17.0, "Electrical corona, irregular high-voltage contact and damped coil discharge"),
    "air_charge": (2, .72, -19.0, "Rising field pressure and irregular electrical crackle before pulse discharge"),
    "air_lock": (2, .37, -20.0, "Two short dry mechanical targeting ticks with restrained warning electronics"),
    "air_crash": (3, 1.35, -14.0, "Large pressure collapse, buckling alloy, separated fragments and turbine rundown"),
}


def shaped_noise(count: int, low: float, high: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    bins = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = np.fft.rfft(rng.normal(size=count))
    response = bins**4 / np.sqrt(bins**8 + low**8)
    response /= np.sqrt(1 + (bins / high)**8)
    spectrum *= response
    spectrum[0] = 0
    result = np.fft.irfft(spectrum, n=count)
    return result / max(float(np.std(result)), 1e-12)


def master(signal: np.ndarray, rms_db: float, peak_limit: float) -> np.ndarray:
    signal = signal - signal.mean()
    # Smooth physical compression controls rare airflow peaks; no hard clipping.
    signal = np.tanh(signal * .85)
    signal -= signal.mean()
    rms = float(np.sqrt(np.mean(signal**2)))
    gain = min(10 ** (rms_db / 20) / max(rms, 1e-12), peak_limit / max(float(np.abs(signal).max()), 1e-12))
    return signal * gain


def engine(family: str) -> np.ndarray:
    index = list(ENGINES).index(family)
    count = round(RATE * LOOP_SECONDS)
    t = np.arange(count) / RATE
    cycle = 2 * np.pi * t / LOOP_SECONDS
    seed = SEED + index * 1031
    air = shaped_noise(count, 120, 2150, seed)
    body = shaped_noise(count, 40, 340, seed + 1)
    high = shaped_noise(count, 550, 3400, seed + 2)
    signal = np.zeros(count)
    blade_rates = {"rotor": [20.0, 21.375], "propeller": [29.25], "tiltrotor": [17.75, 18.5],
                   "jet": [78.75, 131.0], "airship": [11.0, 11.625], "vtol": [28.0, 29.125, 31.0, 31.75]}[family]
    for rotor, frequency in enumerate(blade_rates):
        phase = 2 * np.pi * frequency * t + rotor * 1.93
        phase += .045 * np.sin(cycle * (rotor + 1) + rotor * .41)
        pressure = (.5 + .5 * np.cos(phase))**(3 if family == "jet" else 5)
        harmonics = sum(np.sin(phase * harmonic + .19 * harmonic) * strength
                        for harmonic, strength in [(1, .27), (2, .19), (3, .095), (5, .027), (7, .016)])
        signal += harmonics / len(blade_rates)
        signal += air * (.17 + .24 * pressure) / len(blade_rates)
    load = .91 + .055 * np.sin(cycle + .4) + .035 * np.cos(3 * cycle)
    signal *= load
    if family == "jet":
        signal += air * .25 + high * .18 + body * .09
        signal += .047 * np.sin(2 * np.pi * 253.125 * t + .05 * np.sin(cycle))
    elif family == "airship":
        signal += body * .25 + air * .07
        signal += .026 * np.sin(2 * np.pi * 63.5 * t) + .017 * np.sin(2 * np.pi * 96.125 * t)
    elif family == "propeller":
        compression = (.5 + .5 * np.sin(2 * np.pi * 48.375 * t))**6
        signal += .10 * body + .065 * high * compression
        signal += .12 * np.sin(2 * np.pi * 48.375 * t + .12 * np.sin(cycle))
    else:
        signal += body * .12 + high * (.035 if family == "rotor" else .06)
        signal += .025 * np.sin(2 * np.pi * (177.5 + index * 21.25) * t + .035 * np.sin(cycle))
    bins = np.fft.rfftfreq(count, 1 / RATE)
    notch = 1 - .46 * np.exp(-.5 * ((bins - 2400) / 850)**2)
    spectrum = np.fft.rfft(signal) * notch
    signal = np.fft.irfft(spectrum, n=count)
    signal = master(signal, -20, .48)
    # Rotate an intact periodic signal to a quiet low-derivative cut; never fade
    # or splice a recurring silent hole into an engine.
    seam_cost = np.abs(signal) + 4 * np.abs(signal - np.roll(signal, 1))
    return np.roll(signal, -int(np.argmin(seam_cost)))


def effect(kind: str, variant: int) -> np.ndarray:
    index = list(EFFECTS).index(kind)
    _, seconds, rms_db, _ = EFFECTS[kind]
    seed = SEED + 25000 + index * 1733 + variant * 137
    rng = np.random.default_rng(seed)
    count = round(seconds * RATE)
    t = np.arange(count) / RATE
    grain = shaped_noise(count, 220, 5200, seed)
    air = shaped_noise(count, 70, 1700, seed + 1)
    low = shaped_noise(count, 34, 230, seed + 2)
    signal = np.zeros(count)

    def contact(at: float, strength: float, decay: float = .027):
        age = np.maximum(t - at, 0)
        gate = t >= at
        body = sum(np.sin(2 * np.pi * f * age + .07) * g
                   for f, g in [(347 + variant * 11, .19), (863 + variant * 7, .095), (1729 - variant * 19, .041)])
        return (grain * .68 + body) * strength * np.exp(-age / decay) * gate

    if kind == "air_dart":
        signal = air * .48 * np.exp(-t / .031) + grain * .15 * np.exp(-t / .008)
        signal += contact(.004, .25, .014) + contact(.044, .11, .012)
    elif kind == "air_tracer":
        signal = grain * .57 * np.exp(-t / .013) + air * .44 * np.exp(-t / .047)
        signal += low * .25 * np.exp(-t / .058) + contact(.043, .22) + contact(.105, .13, .019)
    elif kind == "air_rocket":
        ignition = contact(.004, .28, .017)
        motor = np.clip(t / .038, 0, 1) * np.exp(-t / .16)
        signal = ignition + (air * .47 + low * .33 + grain * .08) * motor
        signal += contact(.035, .19) + contact(.091, .11, .023)
    elif kind == "air_bomb":
        signal = contact(.006, .38, .035) + contact(.054, .16, .029)
        drift = np.minimum(t / .10, 1) * np.exp(-t / .19)
        signal += air * .19 * drift + grain * .025 * drift
        signal += low * .15 * np.exp(-t / .07)
    elif kind in ["air_arc", "air_charge"]:
        charging = kind == "air_charge"
        envelope = np.minimum(t / (.16 if charging else .013), 1) * np.minimum((seconds - t) / .10, 1)
        envelope *= np.exp(-t / (1.0 if charging else .14))
        # Aperiodic discharge is the main sound; restrained coil partials do
        # not form a melody or replace the game's beat.
        signal = grain * .12 * envelope + air * .20 * envelope
        frequency = 385 + variant * 23
        phase = 2 * np.pi * frequency * t + 2.1 * np.sin(2 * np.pi * 43.7 * t)
        signal += (.05 * np.sin(phase) + .035 * np.sin(phase * 2.731)) * envelope
        for at in rng.uniform(.02, seconds * .75, 7 if charging else 5):
            signal += contact(float(at), rng.uniform(.08, .17), .005)
        if not charging:
            signal += low * .26 * np.exp(-t / .10) + contact(.003, .21, .014)
    elif kind == "air_lock":
        signal = contact(.01, .25, .012) + contact(.13, .23, .013)
        for at in [.035, .155]:
            age = np.maximum(t - at, 0)
            signal += .038 * np.sin(2 * np.pi * (790 + variant * 45) * age) * np.exp(-age / .020) * (t >= at)
    elif kind == "air_crash":
        signal = low * .67 * np.exp(-t / .32) + air * .38 * np.exp(-t / .20)
        signal += grain * .25 * np.exp(-t / .049)
        for at, strength in [(.032, .28), (.13, .16), (.25, .12), (.41, .09), (.61, .055), (.87, .03)]:
            signal += contact(at + rng.uniform(-.007, .007), strength, .047)
        signal += high_rundown(t, variant) * np.exp(-t / .23) * .032
    attack = min(round(.002 * RATE), count)
    release = min(round(.035 * RATE), count)
    signal[:attack] *= np.linspace(0, 1, attack)**1.5
    signal[-release:] *= np.linspace(1, 0, release)**1.6
    signal = master(signal, rms_db, .79)
    signal[:attack] *= np.linspace(0, 1, attack)
    signal[-release:] *= np.linspace(1, 0, release)
    # Fading an otherwise centered short transient can create residual DC.
    # Remove it with the same edge envelope so the event still starts/ends at 0.
    edge = np.ones(count)
    edge[:attack] = np.linspace(0, 1, attack)
    edge[-release:] = np.linspace(1, 0, release)
    signal -= signal.mean() * edge / edge.mean()
    return signal


def high_rundown(t: np.ndarray, variant: int) -> np.ndarray:
    return np.sin(2 * np.pi * ((310 + variant * 19) * t - 72 * t**2))


def save(path: Path, signal: np.ndarray, role: str, loop: bool, layers: str, seed: int) -> dict:
    assert np.isfinite(signal).all() and np.abs(signal).max() < .9
    pcm = np.round(signal * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    metadata = {"asset": str(path.relative_to(ROOT)), "generator": "tools/generate_aircraft_audio.py",
                "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "origin": "Original deterministic aircraft mechanism, airflow and ordnance sound design; no external recordings, music or speech.",
                "license": LICENSE, "role": role, "layers": layers, "seed": seed, "sample_rate": RATE,
                "channels": 1, "pcm_bits": 16, "frames": len(pcm), "seconds": len(pcm) / RATE, "loop": loop,
                "loop_method": "Integer-period carriers and circular FFT textures, intact rotation to quiet low-derivative cut" if loop else "Finite dry transient with short attack/release; no repeated waveform",
                "peak_dbfs": float(20 * np.log10(np.abs(signal).max())), "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(signal**2)))),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "playback": "Canonical mono source on SFX; runtime supplies bounded voices, world-space pan, attenuation, pause and mixer gain. Existing 50% saved settings remain unchanged."}
    path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    path.with_suffix(".LICENSE.txt").write_text(LICENSE + "\n")
    return metadata


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    preserved = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in OUT.rglob("*") if path.suffix in [".wav", ".ogg"] and not path.name.startswith(NEW_ASSET_PREFIXES)}
    assets = {}
    for index, (family, layers) in enumerate(ENGINES.items()):
        filename = f"air_engine_{family}_v1.wav"
        assets[filename] = save(OUT / filename, engine(family), family, True, layers, SEED + index * 1031)
    for index, (kind, (variants, _, _, layers)) in enumerate(EFFECTS.items()):
        for variant in range(variants):
            filename = f"{kind}_{variant + 1:02d}.wav"
            assets[filename] = save(OUT / filename, effect(kind, variant), kind, False, layers, SEED + 25000 + index * 1733 + variant * 137)
    for path, digest in preserved.items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    (OUT / "aircraft_v1_sources.json").write_text(json.dumps({"generator": "tools/generate_aircraft_audio.py", "license": LICENSE, "assets": assets, "preserved_sha256": preserved}, indent=2) + "\n")
    print(f"Generated {len(assets)} aircraft recordings; preserved {len(preserved)} existing WAV/OGG bytes")


if __name__ == "__main__":
    main()
