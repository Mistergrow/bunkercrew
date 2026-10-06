#!/usr/bin/env python3
"""Author original layered truck and roadside foley; preserve the legacy v1 bank.

All PCM is deterministic. Periodic FFT textures and whole-cycle oscillators
make the four running layers real loops, without a boundary crossfade or gap.
One-shots use damped mechanical modes and independent filtered noise grains.
"""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
RATE = 48000
LOOP_SECONDS = 8.0
TAU = 2 * np.pi
SEED = 601940
LICENSE = "Original Bunkercrew sound design; distribution only together with Bunkercrew."
SPECS = {
    "idle": (8.0, True, "Low diesel compression pulses, uneven exhaust, valve tick and restrained fan texture"),
    "torque": (8.0, True, "Loaded combustion pulses, resonant intake and broad turbo pressure; no musical note"),
    "road": (8.0, True, "Rubber contact, granular road hiss and irregular small suspension impacts"),
    "clatter": (8.0, True, "Damped loose body panels, cargo fasteners and short metal suspension knocks"),
    "start": (1.85, False, "Starter relay, uneven cranking, compression catch, diesel settling"),
    "stop": (1.05, False, "Compression rundown, engine block settling and air-valve release"),
    "accelerate": (.65, False, "Short intake rush and loaded exhaust response"),
    "brake": (.88, False, "Air-brake release, muted rubber drag and body settling"),
    "gear": (.34, False, "Mechanical linkage travel, detent and low transmission contact"),
    "door_open": (.72, False, "Latch disengagement, damped hinge travel and heavy open stop"),
    "door_close": (.68, False, "Panel slam, low body resonance and separate latch click"),
    "refuel": (1.8, False, "Canister/nozzle seating, liquid glugs and final metal release"),
    "tire_puncture": (1.55, False, "Rubber rupture, pressured escaping air and wheel/body sag"),
    "jack": (1.1, False, "Two loaded jack ratchet strokes, hydraulic pressure and foot contact"),
    "wrench": (.82, False, "Distinct ratchet teeth, wrench reseating and loaded bolt torque"),
    "bolt_success": (.38, False, "Firm bolt seating, socket lift and short restrained steel resonance"),
    "tool_miss": (.42, False, "Socket slipping and a short loose tooth chatter, without a warning beep"),
    "fit": (.65, False, "Rubber wheel reseating on the hub and socket engagement"),
    "lower": (.90, False, "Hydraulic release, descending chassis and tire contact"),
    "repair_done": (1.38, False, "Jack release, solid tire/body return, tools packed; no victory melody"),
    "caution": (.72, False, "Brief double vehicle air horn; separated from tool confirmation"),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_bank():
    # Only the explicit v2 filenames and this bank's manifest may be replaced.
    return {p.name: digest(p) for p in sorted(OUT.iterdir())
            if p.is_file() and not p.name.startswith("convoy_")}


def periodic_noise(count, rng, low, high):
    frequency = np.fft.rfftfreq(count, 1 / RATE)
    spectrum = np.fft.rfft(rng.normal(size=count))
    response = 1 / np.sqrt(1 + (frequency / high) ** 8)
    response *= (frequency / low) ** 2 / (1 + (frequency / low) ** 2)
    response[0] = 0
    result = np.fft.irfft(spectrum * response, count)
    return result / max(float(np.std(result)), 1e-12)


def burst(t, at, decay, attack=.0015):
    age = np.maximum(t - at, 0)
    return (1 - np.exp(-age / attack)) * np.exp(-age / decay) * (t >= at)


def modes(t, at, frequencies, gain, decay, rng):
    age = np.maximum(t - at, 0)
    result = np.zeros_like(t)
    for index, frequency in enumerate(frequencies):
        result += np.sin(TAU * frequency * rng.uniform(.97, 1.03) * age) / (index + 1) ** 1.5
    return result * burst(t, at, decay, .0007) * gain


def loop(kind, seed):
    rng = np.random.default_rng(seed)
    count = round(LOOP_SECONDS * RATE)
    t = np.arange(count) / RATE
    phase = TAU * t / LOOP_SECONDS
    low = periodic_noise(count, rng, 32, 260)
    middle = periodic_noise(count, rng, 170, 1700)
    grit = periodic_noise(count, rng, 780, 4900)
    # Oscillator frequencies and modulation periods are exact integer cycles.
    if kind in ("idle", "torque"):
        firing = 236 if kind == "idle" else 352
        angle = firing * phase + .09 * np.sin(phase * 11) + .04 * np.sin(phase * 23)
        exhaust = np.sin(angle) * .40 + np.sin(angle * 2 - .5) * .18 + np.sin(angle * 3 + .2) * .075
        compression = np.maximum(np.sin(angle - .35), 0) ** 6
        load = .78 + .11 * np.sin(phase * 3) + .07 * np.sin(phase * 13 + .7)
        result = exhaust * load + low * (.11 if kind == "idle" else .19)
        result += middle * compression * (.085 if kind == "idle" else .14)
        result += grit * compression * .024 + middle * .023
        valve = np.sin(phase * 2207) + .45 * np.sin(phase * 4053)
        result += valve * np.maximum(np.sin(angle * .5 + .2), 0) ** 11 * .027
        if kind == "torque":
            result += periodic_noise(count, rng, 480, 2600) * (.035 + .018 * np.sin(phase * 5))
        result = np.tanh(result * 1.18)
    elif kind == "road":
        contact = .72 + .14 * np.sin(phase * 19) + .08 * np.sin(phase * 47 + .8)
        result = low * .27 + middle * contact * .12 + grit * contact ** 2 * .039
        for at in rng.uniform(0, LOOP_SECONDS, 49):
            age = np.mod(t - at, LOOP_SECONDS)
            envelope = (1 - np.exp(-age / .002)) * np.exp(-age / rng.uniform(.013, .040))
            result += (np.sin(TAU * 67 * age) * .20 + np.sin(TAU * 143 * age) * .05) * envelope
    else:
        result = low * .028 + middle * .010
        for at in rng.uniform(0, LOOP_SECONDS, 63):
            age = np.mod(t - at, LOOP_SECONDS)
            envelope = (1 - np.exp(-age / .001)) * np.exp(-age / rng.uniform(.009, .026))
            pressure = np.sin(TAU * 171 * age) + .41 * np.sin(TAU * 419 * age) + .17 * np.sin(TAU * 853 * age)
            result += pressure * envelope * rng.uniform(.045, .13)
        result += grit * (.006 + .004 * np.sin(phase * 41))
    result -= result.mean()
    return result * .64 / max(float(np.max(np.abs(result))), 1e-12)


def effect(kind, seed):
    rng = np.random.default_rng(seed)
    seconds = SPECS[kind][0]
    t = np.arange(round(seconds * RATE)) / RATE
    low = periodic_noise(len(t), rng, 32, 320)
    middle = periodic_noise(len(t), rng, 230, 2200)
    grit = periodic_noise(len(t), rng, 1200, 6700)
    result = np.zeros_like(t)

    def metal(at, gain=.3, decay=.035, frequencies=(117, 281, 623)):
        return modes(t, at, frequencies, gain, decay, rng) + middle * burst(t, at, .011, .0006) * gain * .28

    if kind in ("start", "stop"):
        if kind == "start":
            rpm = 8 + 5 * np.minimum(t / .50, 1) + 19 / (1 + np.exp(-(t - .52) * 22))
            envelope = np.minimum(t / .04, 1) * (.60 + .40 / (1 + np.exp(-(t - .55) * 14)))
            result += metal(.015, .31, .02, (141, 367, 931))
            result += np.sin(TAU * (205 * t + 38 * t * t)) * burst(t, .03, .55, .08) * .08
        else:
            rpm = np.maximum(30 * (1 - t / .73), 3)
            envelope = np.clip(1 - t / .77, 0, 1) ** .65
            result += metal(.73, .10, .028, (67, 143, 357)) + grit * burst(t, .69, .095, .025) * .033
        angle = np.cumsum(rpm) * TAU / RATE
        firing = np.maximum(np.sin(angle), 0) ** 5
        result += (np.sin(angle) * .31 + np.sin(angle * 2 - .4) * .12 + low * .11 + middle * firing * .065) * envelope
        if kind == "start":
            result += low * burst(t, .55, .085, .009) * .25
    elif kind in ("door_open", "door_close"):
        if kind == "door_open":
            result += metal(.010, .22, .018, (309, 731, 1403))
            result += middle * burst(t, .09, .24, .06) * .058
            result += modes(t, .11, (131, 259, 499), .06, .20, rng)
            result += metal(.47, .17, .045, (61, 127, 281))
        else:
            result += low * burst(t, .01, .045, .001) * .24
            result += metal(.012, .66, .063, (53, 109, 247, 613))
            result += metal(.087, .20, .016, (379, 857, 1421))
    elif kind == "gear":
        result += middle * burst(t, .008, .043, .012) * .12
        result += metal(.071, .22, .024, (137, 313, 719))
        result += metal(.13, .095, .021, (89, 181, 431))
    elif kind == "refuel":
        result += metal(.01, .14, .035, (127, 293, 617))
        for at in [.17, .32, .52, .72, .88, 1.04, 1.23, 1.42]:
            result += low * burst(t, at, .051, .010) * rng.uniform(.12, .23)
            result += modes(t, at, (rng.uniform(130, 260), rng.uniform(450, 740)), .045, .042, rng)
        result += middle * burst(t, .15, .8, .10) * .030
        result += metal(1.59, .10, .04)
    elif kind == "accelerate":
        result += low * burst(t, .012, .18, .045) * .18
        result += middle * burst(t, .028, .15, .06) * .11
        angle = TAU * (35 * t + 32 * t * t)
        result += (np.sin(angle) + .38 * np.sin(angle * 2)) * burst(t, .015, .21, .035) * .11
    elif kind == "brake":
        result += grit * burst(t, .015, .17, .012) * .16
        result += middle * burst(t, .05, .26, .047) * .11
        result += low * burst(t, .12, .19, .06) * .10
        result += metal(.40, .08, .04, (59, 137, 313))
    elif kind == "tire_puncture":
        result += low * burst(t, .003, .055, .0005) * .46
        result += middle * burst(t, .003, .011, .0003) * .36
        pressure = burst(t, .013, .37, .012)
        result += (grit * .20 + middle * .16) * pressure
        result += metal(.27, .095, .075, (49, 107, 239))
    elif kind == "jack":
        for at in [.03, .47]:
            result += low * burst(t, at, .065, .014) * .12
            result += middle * burst(t, at + .04, .11, .028) * .07
            for tooth in range(5): result += metal(at + tooth * .042, .06, .010, (383, 851, 1471))
        result += metal(.81, .10, .031, (89, 193, 443))
    elif kind == "wrench":
        result += metal(.009, .10, .022, (211, 537, 1069))
        for tooth in range(9):
            at = .071 + tooth * .027 + rng.uniform(-.002, .002)
            result += metal(at, rng.uniform(.035, .075), .006, (521, 1163, 2381))
        result += metal(.41, .20, .033, (137, 347, 709))
        result += low * burst(t, .40, .05, .016) * .08
    elif kind == "bolt_success":
        result += metal(.009, .32, .022, (173, 431, 971))
        result += metal(.080, .09, .026, (317, 719, 1511))
    elif kind == "tool_miss":
        for at in [.011, .029, .067]: result += metal(at, .13, .009, (647, 1301, 2771))
        result += grit * burst(t, .015, .058, .005) * .10
        result += metal(.14, .055, .02, (293, 733, 1397))
    elif kind == "fit":
        result += low * burst(t, .009, .12, .024) * .20
        result += middle * burst(t, .04, .11, .030) * .12
        result += metal(.27, .17, .035, (137, 319, 661))
        result += metal(.37, .06, .027, (239, 557, 1117))
    elif kind == "lower":
        result += middle * burst(t, .011, .17, .012) * .11
        result += grit * burst(t, .025, .13, .02) * .031
        result += low * burst(t, .31, .065, .013) * .29
        result += metal(.34, .22, .050, (57, 119, 271))
    elif kind == "repair_done":
        result += middle * burst(t, .011, .22, .012) * .10
        for at in [.05, .12, .18]: result += metal(at, .085, .012, (353, 787, 1477))
        result += low * burst(t, .31, .09, .018) * .29
        result += metal(.33, .26, .070, (51, 113, 271))
        result += metal(.70, .105, .021, (229, 557, 997))
        result += metal(.90, .085, .029, (151, 337, 653))
    elif kind == "caution":
        for at, duration in [(.018, .16), (.29, .22)]:
            age = np.maximum(t - at, 0)
            env = np.minimum(age / .018, 1) * np.clip((duration - age) / .045, 0, 1) * (t >= at)
            horn = sum(np.sin(TAU * frequency * age) * gain for frequency, gain in [(193, .32), (257, .22), (386, .09), (514, .06)])
            result += (horn + middle * .038) * env
    result = sosfilt(butter(3, [28, 6200], "bandpass", fs=RATE, output="sos"), result)
    fade_in = np.sin(np.clip(t / .001, 0, 1) * np.pi / 2) ** 2
    fade_out = np.sin(np.clip((seconds - 1 / RATE - t) / .065, 0, 1) * np.pi / 2) ** 2
    result *= fade_in * fade_out
    # Subtract DC through a zero-ended window, preserving silent event edges.
    window = np.sin(np.pi * np.arange(len(t)) / (len(t) - 1)) ** 2
    result -= window * result.sum() / window.sum()
    return result * .68 / max(float(np.max(np.abs(result))), 1e-12)


def render(kind):
    seed = SEED + list(SPECS).index(kind) * 997
    return loop(kind, seed) if SPECS[kind][1] else effect(kind, seed)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    before = protected_bank()
    legacy = {p.name: digest(p) for p in sorted(OUT.glob("convoy_*_v1.*")) if p.is_file()}
    source_sha = digest(Path(__file__))
    assets = {}
    for kind, (seconds, looping, layers) in SPECS.items():
        pcm = np.round(render(kind) * 32767).astype("<i2")
        path = OUT / f"convoy_{kind}_v2.wav"
        with wave.open(str(path), "wb") as output:
            output.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
            output.writeframes(pcm.tobytes())
        metadata = {"asset": str(path.relative_to(ROOT)), "generator": "tools/generate_convoy_audio.py",
                    "generator_sha256": source_sha, "source": "Original deterministic procedural mechanical foley; no external samples, recordings or melodies.",
                    "license": LICENSE, "role": kind, "layers": layers, "seed": SEED + list(SPECS).index(kind) * 997,
                    "sample_rate": RATE, "channels": 1, "pcm_bits": 16, "frames": len(pcm), "seconds": seconds,
                    "loop": looping, "loop_method": "Periodic FFT textures and integer-period harmonics; no fades or seam crossfade" if looping else "Silent one-shot edges with 65 ms terminal fade",
                    "sha256": digest(path), "playback": "Bounded spatial convoy voices on the existing SFX bus; defaults and other audio banks unchanged."}
        path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
        path.with_suffix(".LICENSE.txt").write_text(LICENSE + "\n" + metadata["source"] + "\n")
        assets[path.name] = metadata
    assert before == protected_bank(), "Unrelated audio changed while rendering convoy sounds"
    assert all(digest(OUT / name) == value for name, value in legacy.items()), "Legacy convoy bank changed"
    manifest = {"generator": "tools/generate_convoy_audio.py", "generator_sha256": source_sha,
                "license": LICENSE, "sample_rate": RATE, "assets": assets, "legacy_preserved_sha256": legacy,
                "validation": "python3 tests/convoy_audio_assets_test.py; Godot tests/convoy_audio_test.gd",
                "review": "Signal measurements and browser listening gallery; no human listening assessment claimed."}
    (OUT / "convoy_v2_sources.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Rendered {len(SPECS)} original convoy assets; four true loops and {len(SPECS)-4} one-shots. Legacy and unrelated audio preserved.")


if __name__ == "__main__":
    main()
