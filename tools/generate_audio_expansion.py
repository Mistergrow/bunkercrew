#!/usr/bin/env python3
"""Deterministic original score expansion and layered foley (NumPy/SciPy/ffmpeg).

python3 tools/generate_audio_expansion.py
Preserves the two original score files. No recordings or third-party samples.
"""
from pathlib import Path
import hashlib
import json
import math
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, resample_poly, sosfilt

import generate_audio as legacy

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
RATE = 32000
SECONDS = 48
BEAT = 0.75
SAMPLES = RATE * SECONDS
VARIANTS = {"shot": 3, "enemy_shot": 3, "hit": 3, "mine": 3, "pickup": 3,
            "build": 3, "reload": 2, "produce": 2, "empty": 2,
            "explosion": 2, "warning": 1, "start": 1, "thunder": 1,
            "shotgun": 3, "cannon": 3, "arc": 3, "impact_metal": 3,
            "impact_stone": 3, "impact_wood": 3, "glass_break": 3}
SCORES = {
    "foundry": {"seed": 915203, "title": "Glut unter Stahl", "key": "D minor",
        "chords": [[50, 57, 60, 64], [46, 53, 57, 60], [43, 50, 53, 57], [45, 52, 55, 62]],
        "melody": [[74, 72, 69, 65, 69], [69, 65, 62, 60, 65],
                   [67, 69, 70, 65, 62], [64, 67, 69, 67, 64]],
        "instruments": "bowed low strings, muted felt motif, metal ostinato, deep toms"},
    "tidal": {"seed": 421019, "title": "Schwarzes Wasser", "key": "E minor with Dorian inflections",
        "chords": [[52, 59, 62, 66], [45, 52, 57, 61], [48, 55, 59, 62], [47, 54, 57, 61]],
        "melody": [[71, 74, 78, 76, 74], [73, 76, 73, 69, 71],
                   [71, 74, 79, 78, 74], [73, 71, 69, 66, 71]],
        "instruments": "damped plucked strings, airy chamber pads, suspended bells, brushed drums"},
    "frost": {"seed": 742183, "title": "Licht hinter dem Eis", "key": "B minor",
        "chords": [[47, 54, 59, 61], [43, 50, 54, 59], [50, 57, 62, 64], [42, 49, 54, 59]],
        "melody": [[78, 74, 73, 71, 66], [74, 71, 69, 66, 71],
                   [78, 81, 78, 76, 74], [73, 71, 66, 69, 73]],
        "instruments": "breathy choir-like pads, soft struck glass, low bowed strings, restrained toms"},
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def noise(length, cutoff, rng):
    return legacy.noise(length, cutoff, rng, RATE)


def envelope(t, length, attack, release):
    return np.sin(np.minimum(t / attack, 1) * np.pi / 2) ** 2 * np.sin(
        np.clip((length - t) / release, 0, 1) * np.pi / 2) ** 2


def note_voice(note, length, rng, voice="bow", velocity=1):
    """Damped/modal instruments with shaped transients, not one oscillator per note."""
    t = np.arange(round(length * RATE)) / RATE
    freq = legacy.midi(note)
    signal = np.zeros(len(t))
    if voice in ("bow", "choir"):
        attack = 0.58 if voice == "bow" else 1.0
        for detune, gain in [(-.0021, .34), (0, .46), (.0017, .31)]:
            phase = 2 * np.pi * freq * (1 + detune) * t + rng.uniform(0, 2 * np.pi)
            phase += .026 * np.sin(2 * np.pi * 4.6 * t) * np.minimum(t / .8, 1)
            # Roll off upper harmonics; formants on the choir remain low and soft.
            partials = ([1, .36, .17, .085, .035] if voice == "bow"
                        else [1, .12, .21, .035, .055])
            for harmonic, level in enumerate(partials, 1):
                signal += np.sin(phase * harmonic) * gain * level
        signal *= envelope(t, length, min(attack, length / 3), min(1.55, length / 2))
        signal *= .87 + .13 * np.sin(np.pi * t / length)
        signal += noise(len(t), 850, rng) * .017 * envelope(t, length, .45, .9)
    elif voice == "felt":
        for ratio, level, decay in [(1, 1, 1.8), (2.001, .30, .8), (3.009, .12, .48), (4.018, .035, .27)]:
            signal += np.sin(2 * np.pi * freq * ratio * t) * level * np.exp(-t / decay)
        signal += noise(len(t), 1150, rng) * np.exp(-t / .019) * .04
        signal *= envelope(t, length, .009, .55)
    elif voice == "pluck":
        for partial in range(1, 8):
            signal += np.sin(2 * np.pi * freq * partial * (1 + partial * partial * .000035) * t) * (
                .87 ** partial / partial) * np.exp(-t / (1.7 / partial ** .55))
        signal += noise(len(t), 1700, rng) * np.exp(-t / .013) * .035
        signal *= envelope(t, length, .006, .4)
    else:  # A dark suspended bell with decaying, slightly inharmonic upper modes.
        for ratio, level, decay in [(1, 1, 2.9), (2.004, .30, 1.8), (2.756, .07, .9), (4.073, .035, .4)]:
            signal += np.sin(2 * np.pi * freq * ratio * t) * level * np.exp(-t / decay)
        signal *= envelope(t, length, .012, .8)
    return signal * velocity


def put(track, event, seconds, pan=0):
    start = round(seconds * RATE) % len(track)
    if event.ndim == 1:
        event = event[:, None] * np.array([math.sqrt((1-pan)/2), math.sqrt((1+pan)/2)])
    count = min(len(event), len(track) - start)
    track[start:start+count] += event[:count]
    if count < len(event):
        track[:len(event)-count] += event[count:]


def percussion(kind, rng, velocity=1):
    length = {"kick": .52, "tom": .47, "metal": .31, "brush": .24, "tick": .15}[kind]
    t = np.arange(round(length * RATE)) / RATE
    if kind == "kick":
        phase = 2*np.pi*(48*t + 34*.017*(1-np.exp(-t/.017)))
        signal = np.sin(phase) * np.exp(-t/.13)
        signal += noise(len(t), 700, rng) * np.exp(-t/.013)*.075
    elif kind == "tom":
        signal = (np.sin(2*np.pi*91*t) + .24*np.sin(2*np.pi*146*t)) * np.exp(-t/.13)
        signal += noise(len(t), 650, rng) * np.exp(-t/.055)*.15
    elif kind == "metal":
        signal = sum(np.sin(2*np.pi*f*t)*g*np.exp(-t/d) for f,g,d in
                     [(223, .50, .045), (367, .29, .074), (608, .15, .033), (1131, .055, .021)])
        signal += noise(len(t), 2300, rng)*np.exp(-t/.009)*.12
    elif kind == "brush":
        signal = noise(len(t), 1600, rng)*np.exp(-t/.045)*.28
        signal += np.sin(2*np.pi*174*t)*np.exp(-t/.044)*.16
    else:
        signal = noise(len(t), 2700, rng)*np.exp(-t/.014)*.14
        signal += np.sin(2*np.pi*709*t)*np.exp(-t/.018)*.065
    return legacy.fade_edges(signal, RATE, .001, .025) * velocity


def room(track, spacious=False):
    dry = track.copy()
    # Circular early and late reflections wrap musical tails without a silent seam.
    delays = [(.043, .13), (.079, .095), (.163, .070), (.281, .049),
              (.437, .034), (.719, .023), (1.117, .015)]
    for i, (delay, gain) in enumerate(delays):
        reflected = dry[:, ::-1] if i % 2 == 0 else dry
        track += np.roll(reflected, round(delay * RATE), axis=0) * gain * (1.3 if spacious else 1)
    # Periodic filtering avoids a filter reset at the loop seam.
    sos = butter(2, [32, 6500], "bandpass", fs=RATE, output="sos")
    padding = RATE * 2
    track = sosfilt(sos, np.concatenate([track[-padding:], track, track[:padding]]), axis=0)[padding:-padding]
    track -= track.mean(axis=0)
    return track


def compose(kind):
    spec = SCORES[kind]
    rng = np.random.default_rng(spec["seed"])
    calm = np.zeros((SAMPLES, 2), dtype=np.float64)
    battle = np.zeros_like(calm)
    pad = "choir" if kind == "frost" else "bow"
    lead = {"foundry": "felt", "tidal": "pluck", "frost": "bell"}[kind]
    for phrase, chord in enumerate(spec["chords"]):
        origin = phrase * 12.0
        # Wide, restrained voicings overlap the next phrase and the loop boundary.
        for v, note in enumerate(chord):
            put(calm, note_voice(note, 14.0, rng, pad, .029 if v else .038),
                origin + v*.047, (v-1.5)*.36)
        put(calm, note_voice(chord[0]-12, 13.4, rng, "bow", .028), origin, 0)
        motif_beats = [1.5, 4.0, 6.5, 9.0, 12.0]
        for index, (note, beat) in enumerate(zip(spec["melody"][phrase], motif_beats)):
            length = [2.7, 3.2, 2.9, 3.8, 3.5][index]
            velocity = [.032, .043, .037, .048, .030][index]
            if kind == "frost":
                velocity *= .77
            put(calm, note_voice(note, length, rng, lead, velocity),
                origin + beat*BEAT + .018*math.sin(index+phrase),
                -.28 if index % 2 else .25)
        # Combat adds a lower, answered motif; the common score remains byte-aligned.
        pattern = ([0, 2, 1, 2, 0, 3, 2, 1] if kind == "foundry"
                   else [0, 1, 3, 2, 1, 2, 0, 2] if kind == "tidal"
                   else [0, 2, 1, 3, 2, 1, 0, 2])
        for bar in range(4):
            absolute_bar = phrase*4+bar
            origin_bar = origin + bar*3.0
            for step, degree in enumerate(pattern):
                if kind == "frost" and step in (1, 5):
                    continue
                note = chord[degree] + (12 if kind == "tidal" and step % 3 == 0 else 0)
                velocity = .024 * (1.0 if step % 2 == 0 else .68) * (1+bar*.06)
                put(battle, note_voice(note, 1.05, rng, "pluck" if kind != "foundry" else "felt", velocity),
                    origin_bar+step*BEAT*.5, -.18 if step % 2 else .18)
            # Slight timing/velocity variation repeats exactly only at the 16-bar boundary.
            kick_beats = [0, 2] + ([3.5] if bar == 3 else [])
            if kind == "tidal":
                kick_beats = [0, 1.5, 2.75] if bar % 2 else [0, 2.5]
            for beat in kick_beats:
                put(battle, percussion("kick", rng, .080 if kind == "foundry" else .062), origin_bar+beat*BEAT)
            for beat in [1, 3]:
                put(battle, percussion("tom" if kind == "frost" else "brush", rng, .056),
                    origin_bar+beat*BEAT+.008, .16)
            for step in range(8):
                if kind == "frost" and step % 2 == 0:
                    continue
                hit = "metal" if kind == "foundry" else "tick"
                put(battle, percussion(hit, rng, .033 if step % 2 else .045),
                    origin_bar+(step+.5)*BEAT*.5, -.38 if step < 4 else .38)
            if bar == 3:
                for beat, velocity in [(2.5, .030), (3.25, .034), (3.75, .027)]:
                    put(battle, percussion("tom", rng, velocity), origin_bar+beat*BEAT, -.26)
            if absolute_bar % 2 == 1:
                put(calm, percussion("metal" if kind == "foundry" else "brush", rng, .014),
                    origin_bar+2.5*BEAT, .47 if bar == 1 else -.47)
    calm = room(calm, kind != "foundry")
    battle = room(battle)
    combat = calm + battle
    # Joint gain preserves phase coherence across the calm/combat crossfade.
    gain = min(.62 / np.max(np.abs(combat)), .53 / np.max(np.abs(calm)))
    return calm * gain, combat * gain


def mode_impact(t, rng, material="metal", variant=0):
    modes = {
        "metal": [(211, .75, .090), (389, .41, .155), (711, .23, .100), (1339, .09, .047)],
        "stone": [(137, .76, .025), (281, .39, .039), (517, .18, .022), (901, .08, .014)],
        "wood": [(173, .75, .039), (301, .38, .027), (497, .15, .017), (1191, .05, .009)],
        "glass": [(1271, .29, .089), (2039, .23, .125), (2897, .11, .073), (4153, .03, .054)],
    }[material]
    result = np.zeros(len(t))
    shift = 1 + (variant-1)*.042 + rng.uniform(-.019, .019)
    for freq, level, decay in modes:
        result += np.sin(2*np.pi*freq*shift*t)*level*np.exp(-t/decay)
    return result


def improved_effect(kind, variant):
    rng = np.random.default_rng(591713 + variant*331 + sum(ord(c)*(i+1) for i,c in enumerate(kind)))
    lengths = {"shotgun": .58, "cannon": .69, "arc": .61, "impact_metal": .43,
               "impact_stone": .33, "impact_wood": .31, "glass_break": .78}
    if kind not in lengths:
        original = legacy.make_effect(kind, variant)
        length = len(original)/legacy.SFX_RATE
        # Preserve event durations while raising the output bank's sample rate.
        result = resample_poly(original, RATE, legacy.SFX_RATE)[:round(length*RATE)] * .75
    else:
        length = lengths[kind]
        result = np.zeros(round(length*RATE))
    t = np.arange(len(result))/RATE
    coarse = noise(len(t), 2400, rng)
    body = noise(len(t), 430, rng)
    air = noise(len(t), 3400, rng)

    def hit(at, strength, material, decay=.024):
        age = np.maximum(t-at, 0)
        sound = mode_impact(age, rng, material, variant) + coarse*np.exp(-age/decay)*.29
        return sound*(t>=at)*strength

    def low_thump(at, strength, pitch=72, decay=.07):
        age = np.maximum(t-at, 0)
        phase = 2*np.pi*(pitch*age + 55*.012*(1-np.exp(-age/.012)))
        return np.sin(phase)*np.exp(-age/decay)*(t>=at)*strength

    if kind in ("shot", "enemy_shot", "shotgun"):
        spread = kind == "shotgun"
        result += air*np.exp(-t/(.019 if spread else .010))*(.74 if spread else .24)
        result += body*np.exp(-t/(.099 if spread else .042))*(.41 if spread else .18)
        result += low_thump(0, 1.05 if spread else .42, 54 if spread else 94, .12 if spread else .045)
        result += hit(.049+variant*.003, .16, "metal")
        if spread:
            result += hit(.255, .29, "metal") + hit(.325, .17, "metal")
    elif kind == "cannon":
        # Immediate heavy report: no charge-up or synthetic descending rail tone.
        result += air*np.exp(-t/.016)*.57 + coarse*np.exp(-t/.036)*.28
        result += low_thump(0, 1.24, 46, .16) + hit(.073, .19, "metal")
        result += body*np.exp(-t/.20)*.37
        result += hit(.139, .085, "stone") + hit(.251, .042, "metal")
    elif kind == "arc":
        phase = 2*np.pi*(310*t + 270*t*t + .10*np.sin(2*np.pi*39*t))
        gate = (np.sin(2*np.pi*(31+variant*2)*t) > -.45).astype(float)
        result += (np.sin(phase)+.19*np.sin(phase*2.03))*gate*np.exp(-t/.105)*.25
        for at, strength in [(0, .8), (.031, .30), (.076, .19), (.133, .14)]:
            age = np.maximum(t-at, 0)
            result += coarse*np.exp(-age/.008)*(t>=at)*strength
        result += low_thump(0, .34, 107, .040)
    elif kind in ("impact_metal", "impact_stone", "impact_wood", "glass_break", "mine", "hit"):
        material = {"impact_metal": "metal", "impact_stone": "stone", "impact_wood": "wood",
                    "glass_break": "glass", "mine": "stone", "hit": "metal"}[kind]
        result += hit(0, .82, material)
        for index in range(5 if material == "glass" else 3):
            at = .035+index*.039+rng.uniform(-.010, .010)
            result += hit(at, .15*np.exp(-index*.43), material, .009)
        if material == "glass":
            result += air*np.exp(-t/.17)*.18
        elif material == "wood":
            result += body*np.exp(-t/.047)*.23
    elif kind == "explosion":
        result += low_thump(0, .37, 42, .24)
        for at, strength in [(.031, .20), (.139, .12), (.27, .08), (.44, .05)]:
            result += hit(at + variant*.005, strength, "stone")
    elif kind in ("reload", "build", "empty"):
        for at, strength in ({"reload": [(.006, .13), (.20, .10), (.379, .20)],
                              "build": [(.005, .25), (.081, .12)], "empty": [(.002, .22)]}[kind]):
            result += hit(at, strength, "metal")
    elif kind in ("pickup", "produce", "start"):
        result += hit(.014 if kind == "pickup" else .093, .11, "wood")
        result += body*np.sin(np.pi*t/length)**2*.045
    elif kind == "warning":
        result += np.sin(2*np.pi*136.7*t)*envelope(t,length,.25,.48)*.12
    elif kind == "thunder":
        # Distant rolling energy without an abrupt broadband thunder crack.
        result += noise(len(t), 61, rng)*envelope(t,length,.19,.58)*.14
    # Short dry-to-room reflections help bodies carry without washing out rapid fire.
    dry = result.copy()
    if kind not in ("empty", "pickup", "warning", "thunder"):
        for delay, gain in [(.024, .080), (.057, .045), (.103, .021)]:
            offset = round(delay*RATE)
            result[offset:] += dry[:-offset]*gain
    sos = butter(2, [37 if kind != "thunder" else 25, 7100], "bandpass", fs=RATE, output="sos")
    result = sosfilt(sos, result)
    result -= result.mean()
    result = legacy.fade_edges(result, RATE, .0009 if kind not in ("warning", "thunder") else .025, .030)
    # Remove any residual DC with a smooth interior correction that keeps endpoints zero.
    window = np.sin(np.pi*np.arange(len(result))/(len(result)-1))**2
    result -= window*(result.sum()/window.sum())
    peak = {"pickup": .37, "produce": .46, "empty": .42, "warning": .57,
            "thunder": .63, "mine": .64, "impact_stone": .64, "impact_wood": .59,
            "impact_metal": .67, "glass_break": .61, "arc": .68}.get(kind, .76)
    return result*(peak/max(float(np.max(np.abs(result))), 1e-9))


def save_wav(path, data):
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1 if data.ndim == 1 else 2)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(np.round(data*32767).astype("<i2").tobytes())


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    original = {name: digest(OUT/name) for name in ("music_calm.ogg", "music_combat.ogg")}
    for kind, count in VARIANTS.items():
        for variant in range(count):
            path = OUT/f"{kind}_{variant+1:02}.wav"
            save_wav(path, improved_effect(kind, variant))
            imported = path.with_name(path.name+".import")
            if imported.exists():
                imported.write_text(imported.read_text().replace("compress/mode=2", "compress/mode=0"))
        print(f"Rendered {kind}: {count} variations", flush=True)
    with tempfile.TemporaryDirectory(prefix="lastshift-score-expansion-") as temp:
        for kind in SCORES:
            calm, combat = compose(kind)
            for phase, data in [("calm", calm), ("combat", combat)]:
                name = f"music_{kind}_{phase}"
                source = Path(temp)/(name+".wav")
                save_wav(source, data)
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source),
                                "-c:a", "libvorbis", "-q:a", "6", str(OUT/(name+".ogg"))], check=True)
            print(f"Rendered {kind}: synchronized 48-second stereo arrangements", flush=True)
    previous = json.loads((OUT/"sources.json").read_text())
    metadata = {
        "origin": "Original procedural compositions and modal/noise sound design. No third-party samples or recordings.",
        "generator": "tools/generate_audio_expansion.py", "dependencies": ["numpy", "scipy", "ffmpeg/libvorbis"],
        "generation": "Deterministic PCM synthesis; Vorbis bitstream serials may differ between encodes.",
        "sample_rate": RATE, "variants": VARIANTS,
        "music": {"tempo": 80, "bars": 16, "seconds": SECONDS, "channels": 2,
                  "stems": "Each combat arrangement contains its matching calm recording at identical gain and phase, plus percussion and ostinato.",
                  "sets": SCORES},
        "original_score": previous.get("original_score", {"generator": "tools/generate_audio.py", "music": previous.get("music"), "sha256": original}),
        "mix": {"sfx_peak_ceiling": .76, "music_pcm_peak_ceiling": .62, "sfx_high_cut_hz": 7100,
                "music_high_cut_hz": 6500, "sfx_variation": "Independent seeded transients, modal pitch, noise, reflection tails and microtiming.",
                "seams": "Music events and room tails wrap around a periodic 48-second timeline; no silence or fade-out at loop boundary."},
        "validation": {"command": "python3 tests/audio_assets_test.py", "report": "artifacts/audio-refresh/measurements.json"},
        "review": "The validation command measures decoded output and builds an HTML gallery. No listening test claimed by the coding agent."
    }
    (OUT/"sources.json").write_text(json.dumps(metadata, indent=2)+"\n")
    for name, checksum in original.items():
        assert digest(OUT/name) == checksum, f"Original score changed: {name}"
    print("Generated 50 sound effects and six additional music arrangements; original score preserved.")


if __name__ == "__main__":
    generate()
