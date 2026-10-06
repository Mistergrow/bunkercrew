#!/usr/bin/env python3
"""Rebuild the original score, then the current music/foley expansion.

Original music/synthesis plus attributed CC0 contact/reload recording layers.
Requires numpy, scipy and ffmpeg. Run: python3 tools/generate_audio.py
To preserve the existing original OGG bytes: tools/generate_audio_expansion.py
"""
from pathlib import Path
import json
import math
import subprocess
import tempfile
import wave

import numpy as np

OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
SFX_RATE = 22050
MUSIC_RATE = 32000
LOOP_SECONDS = 48.0
METRICS = {}


def noise(count, cutoff, rng, rate=SFX_RATE):
    """Band-limited noise avoids harsh full-band static."""
    white = rng.normal(0, 1, count)
    bins = np.fft.rfftfreq(count, 1 / rate)
    spectrum = np.fft.rfft(white) / np.sqrt(1 + (bins / cutoff) ** 6)
    result = np.fft.irfft(spectrum, count)
    return result / max(float(np.std(result)), 0.001)


def fade_edges(signal, rate, attack=0.0015, release=0.018):
    result = signal.copy()
    a, b = min(len(result), int(attack * rate)), min(len(result), int(release * rate))
    if a:
        curve = np.linspace(0, 1, a) ** 1.6
        result[:a] *= curve if result.ndim == 1 else curve[:, None]
    if b:
        curve = np.linspace(1, 0, b) ** 1.4
        result[-b:] *= curve if result.ndim == 1 else curve[:, None]
    return result


def write_wav(path, signal, rate, peak=None):
    if peak:
        signal = signal * (peak / max(float(np.max(np.abs(signal))), 0.001))
    assert np.max(np.abs(signal)) < 0.98, path.name
    pcm = np.round(signal * 32767).astype("<i2")
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1 if signal.ndim == 1 else signal.shape[1])
        file.setsampwidth(2)
        file.setframerate(rate)
        file.writeframes(pcm.tobytes())
    METRICS[path.name] = {
        "seconds": round(len(signal) / rate, 4),
        "peak": round(float(np.max(np.abs(signal))), 5),
        "rms": round(float(np.sqrt(np.mean(signal ** 2))), 5),
        "channels": 1 if signal.ndim == 1 else signal.shape[1],
    }
    return signal


def make_effect(kind, variant):
    durations = {"shot": .25, "enemy_shot": .29, "hit": .24, "mine": .28,
                 "pickup": .20, "build": .38, "reload": .53, "produce": .57,
                 "empty": .13, "explosion": 1.08, "warning": 1.65,
                 "start": .65, "thunder": 1.8}
    rng = np.random.default_rng(1701 + variant * 127 + sum(map(ord, kind)))
    t = np.arange(int(SFX_RATE * durations[kind])) / SFX_RATE
    grain = noise(len(t), 2500, rng)
    air = noise(len(t), 720, rng)
    low = noise(len(t), 110, rng)
    signal = np.zeros(len(t))

    def thump(at, strength, frequency=90, decay=.07):
        age = np.maximum(t - at, 0)
        return strength * np.sin(2 * np.pi * (frequency * age - frequency * .9 * age ** 2)) * np.exp(-age / decay) * (t >= at)

    def clack(at, strength, decay=.025):
        age = np.maximum(t - at, 0)
        partials = sum(np.sin(2 * np.pi * freq * age) / (i + 2) for i, freq in enumerate([307, 491, 823]))
        return strength * (grain * .65 + partials * .35) * np.exp(-age / decay) * (t >= at)

    if kind == "shot":
        signal = grain * np.exp(-t / .017) * .66 + air * np.exp(-t / .052) * .28
        signal += thump(0, 1.2, 86 + variant * 3, .060) + clack(.041, .24) + clack(.10, .13, .017)
    elif kind == "enemy_shot":
        signal = air * np.exp(-t / .085) * .48 + grain * np.exp(-t / .020) * .36
        signal += thump(0, 1.05, 59 + variant * 2, .092)
        signal += clack(.023, .16) + clack(.058, .12) + clack(.096, .08)
    elif kind == "hit":
        signal = thump(0, .45, 170, .037) + grain * np.exp(-t / .038) * .75
        signal += clack(.032, .32, .052) + clack(.082, .14, .025)
    elif kind == "mine":
        signal = thump(0, .75, 185 + variant * 12, .032) + air * np.exp(-t / .044) * .42
        for at, strength in [(.028, .24), (.073, .17), (.13, .09), (.18, .04)]:
            signal += clack(at + rng.uniform(-.003, .004), strength, .015)
    elif kind == "pickup":
        signal = air * (np.sin(np.pi * t / .20) ** 2) * .16 + low * np.exp(-t / .044) * .15
        signal += thump(.052, .14, 135, .024)
    elif kind == "build":
        signal = thump(0, .9, 113, .064) + thump(.071, .21, 177, .042)
        signal += air * np.exp(-t / .105) * .45 + grain * np.exp(-t / .030) * .25
    elif kind == "reload":
        signal = clack(.002, .43, .027) + clack(.37, .68, .046) + thump(.378, .38, 150, .056)
        slider = np.clip(np.sin(np.pi * np.clip((t-.045)/.31, 0, 1)), 0, 1) ** 1.2
        signal += air * slider * .21
    elif kind == "produce":
        signal = air * np.exp(-t / .18) * .21 + low * np.exp(-t / .16) * .24
        signal += clack(.16, .22, .05) + thump(.18, .38, 110, .085)
    elif kind == "empty":
        signal = clack(0, .4, .017) + thump(.008, .21, 205, .02)
    elif kind == "explosion":
        signal = low * np.exp(-t / .31) * .95 + air * np.exp(-t / .19) * .53
        signal += grain * np.exp(-t / .032) * .48 + thump(0, 1.3, 64, .17)
        for at in [.18, .29, .44, .67]:
            signal += clack(at, .11 * (1-at), .05)
    elif kind == "warning":
        envelope = np.clip(t / .20, 0, 1) * np.clip((1.65-t)/.44, 0, 1)
        # A restrained distant mechanical horn, played once at a phase transition.
        phase = 2 * np.pi * (91 * t + 1.8 * np.sin(t * 3.1))
        horn = np.sin(phase) * .48 + np.sin(phase * 2) * .16 + np.sin(phase * 3) * .07
        signal = (horn + air * .09) * envelope * (.84 + .16*np.sin(t*4))
    elif kind == "start":
        signal = thump(.015, .42, 115, .09) + clack(.17, .23, .04)
        signal += low * np.sin(np.pi*t/.65)**2 * .18
    elif kind == "thunder":
        envelope = np.minimum(t/.12, 1) * (1-t/1.8)**1.4
        signal = (low * .38 + noise(len(t), 43, rng) * .32) * envelope
    return fade_edges(signal, SFX_RATE, .001 if kind not in ["thunder", "warning"] else .05)


def put(track, event, seconds, pan=0):
    """Wrap tails across the loop seam; a continuous phrase cannot click there."""
    start = int(seconds * MUSIC_RATE) % len(track)
    if event.ndim == 1:
        gains = np.array([math.sqrt((1-pan)/2), math.sqrt((1+pan)/2)])
        event = event[:, None] * gains[None, :]
    count = min(len(event), len(track)-start)
    track[start:start+count] += event[:count]
    if count < len(event):
        track[:len(event)-count] += event[count:]


def midi(note):
    return 440 * 2 ** ((note - 69) / 12)


def pad_voice(note, length, rng):
    t = np.arange(int(length * MUSIC_RATE)) / MUSIC_RATE
    freq = midi(note)
    envelope = np.minimum(t/1.65, 1) * np.minimum((length-t)/3.3, 1)
    signal = np.zeros(len(t))
    for detune, gain in [(-.0015, .42), (0, .35), (.0018, .32)]:
        phase = 2*np.pi*freq*(1+detune)*t + rng.uniform(0, 2*np.pi)
        signal += (np.sin(phase) + .19*np.sin(phase*2) + .05*np.sin(phase*3)) * gain
    return signal * envelope * (.94 + .06*np.sin(t*.91))


def music_tracks():
    rng = np.random.default_rng(480716)
    calm = np.zeros((int(LOOP_SECONDS * MUSIC_RATE), 2), dtype=np.float64)
    combat_rhythm = np.zeros_like(calm)
    # Four 4-bar phrases at 80 BPM: Am, F, Dm, Em. One cycle is exactly 48 seconds.
    chords = [[45, 52, 57, 60, 64], [41, 48, 53, 57, 60], [38, 45, 50, 53, 57], [40, 47, 52, 55, 59]]
    for phrase, notes in enumerate(chords):
        start = phrase * 12
        for voice, note in enumerate(notes):
            put(calm, pad_voice(note, 15.0, rng) * .021, start, (voice-2)*.24)
        t = np.arange(int(14.2*MUSIC_RATE))/MUSIC_RATE
        envelope = np.minimum(t/1.7, 1)*np.minimum((14.2-t)/2.4, 1)
        bass = np.sin(2*np.pi*midi(notes[0]-12)*t) * envelope * .042
        put(calm, bass, start, 0)
        # Sparse, slow motif with bowed attacks; no high, abrupt arpeggio beeps.
        for offset, note in [(3.75, notes[3]+12), (8.25, notes[2]+12)]:
            put(calm, pad_voice(note, 3.9, rng) * .017, start+offset, -.18 if phrase%2 else .18)

    def drum(kind):
        duration = .36 if kind == "kick" else .18
        t = np.arange(int(duration*MUSIC_RATE))/MUSIC_RATE
        if kind == "kick":
            wave = np.sin(2*np.pi*(58*t - 24*t*t)) * np.exp(-t/.105)
            wave += noise(len(t), 300, rng, MUSIC_RATE) * np.exp(-t/.022)*.14
        elif kind == "snare":
            wave = noise(len(t), 1450, rng, MUSIC_RATE)*np.exp(-t/.044)*.36
            wave += np.sin(2*np.pi*157*t)*np.exp(-t/.029)*.24
        else:
            wave = noise(len(t), 1900, rng, MUSIC_RATE)*np.exp(-t/.018)*.18
            wave += np.sin(2*np.pi*412*t)*np.exp(-t/.023)*.13
        return fade_edges(wave, MUSIC_RATE)

    for bar in range(16):
        start = bar * 3.0
        # Calm stem has only occasional distant workshop knocks.
        if bar % 2 == 0:
            put(calm, drum("metal")*.026, start+2.25, -.4 if bar%4 else .4)
        for beat in [0, 2]:
            put(combat_rhythm, drum("kick")*.13, start+beat*.75)
        for beat in [1, 3]:
            put(combat_rhythm, drum("snare")*.069, start+beat*.75, .12)
        for beat in [.5, 1.5, 2.5, 3.5]:
            put(combat_rhythm, drum("metal")*.043, start+beat*.75, -.32 if beat<2 else .32)
        if bar % 4 == 3:
            put(combat_rhythm, drum("kick")*.075, start+2.625)
    # Fixed room reflections keep space without a long muddy combat tail.
    for delay, strength in [(0.071, .13), (.137, .08), (.227, .045)]:
        calm += np.roll(calm[:, ::-1], int(delay*MUSIC_RATE), axis=0)*strength
        combat_rhythm += np.roll(combat_rhythm[:, ::-1], int(delay*MUSIC_RATE), axis=0)*strength
    combat = calm + combat_rhythm
    gain = min(.63/np.max(np.abs(combat)), .55/np.max(np.abs(calm)))
    return calm*gain, combat*gain


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    variants = {"shot": 3, "enemy_shot": 3, "hit": 3, "mine": 3, "pickup": 3,
                "build": 3, "reload": 2, "produce": 2, "empty": 2,
                "explosion": 2, "warning": 1, "start": 1, "thunder": 1}
    for kind, count in variants.items():
        for variant in range(count):
            name = f"{kind}_{variant+1:02}.wav"
            peak = {"pickup": .37, "produce": .46, "empty": .42, "warning": .57,
                    "thunder": .63, "mine": .64}.get(kind, .76)
            write_wav(OUT/name, make_effect(kind, variant), SFX_RATE, peak)
            import_options = OUT/(name+".import")
            if import_options.exists():
                import_options.write_text(import_options.read_text().replace("compress/mode=2", "compress/mode=0"))
    calm, combat = music_tracks()
    with tempfile.TemporaryDirectory(prefix="lastshift-score-") as temp:
        for name, data in [("music_calm", calm), ("music_combat", combat)]:
            wav_path = Path(temp)/(name+".wav")
            write_wav(wav_path, data, MUSIC_RATE)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "5", str(OUT/(name+".ogg"))], check=True)
            METRICS[name+".ogg"] = METRICS.pop(name+".wav")
    assert all(0 < m["rms"] < .3 and m["peak"] < .98 for m in METRICS.values())
    metadata = {"origin": "Original procedural composition and layered sound design. No third-party samples.",
                "generator": "tools/generate_audio.py", "seeded": True,
                "music": {"tempo": 80, "bars": 16, "seconds": 48, "chords": ["A minor", "F major", "D minor", "E minor"],
                          "stems": "Calm score and synchronized combat arrangement; shared harmonic recording."},
                "variants": variants, "metrics": METRICS}
    (OUT/"sources.json").write_text(json.dumps(metadata, indent=2)+"\n")
    print(f"Generated {sum(variants.values())} original sound effects and two 48-second stereo music stems.")
    for name in ["music_calm.ogg", "music_combat.ogg"]:
        print(name, METRICS[name])
    # Keep the documented entry point from restoring an outdated effects bank.
    from generate_audio_expansion import generate
    generate()
    from generate_movement_audio import generate as generate_movement
    generate_movement()
    from generate_weapon_audio import generate as generate_weapons
    generate_weapons()
    from generate_enemy_tech_audio import generate as generate_enemy_tech
    generate_enemy_tech()
    from generate_aircraft_audio import main as generate_aircraft
    generate_aircraft()
    from generate_machinery_medical_audio import main as generate_machinery_medical
    generate_machinery_medical()


if __name__ == "__main__":
    main()
