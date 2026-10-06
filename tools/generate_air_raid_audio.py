#!/usr/bin/env python3
"""Original periodic stereo rotor/wind bed for the solo air-contact preview.

No recordings or vehicle assets are read. NumPy supplies deterministic synthesis;
the panel supplies the approach envelope and speech ducking during playback.
"""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets/audio/air_raid_flyover_v1.wav"
RATE = 32000
SECONDS = 4
FRAMES = RATE * SECONDS
SEED = 832471
ROTOR_HZ = (35.5, 37.75)
RECOMMENDED_DB = -9.0
SPEECH_DUCK_DB = -4.0


def periodic_noise(low, high, seed):
    rng = np.random.default_rng(seed)
    frequencies = np.fft.rfftfreq(FRAMES, 1 / RATE)
    spectrum = np.fft.rfft(rng.normal(size=FRAMES))
    spectrum *= frequencies**4 / np.sqrt(frequencies**8 + low**8)
    spectrum /= np.sqrt(1 + (frequencies / high)**8)
    spectrum[0] = 0
    result = np.fft.irfft(spectrum, n=FRAMES)
    return result / np.std(result)


def pan(signal, position):
    return signal[:, None] * np.column_stack([
        np.sqrt((1 - position) * .5), np.sqrt((1 + position) * .5)])


def render():
    t = np.arange(FRAMES) / RATE
    cycle = 2 * np.pi * t / SECONDS
    signal = np.zeros((FRAMES, 2), dtype=np.float64)
    # Each carrier completes whole cycles. Independent periodic phase/load
    # variation gives two asynchronous rotors without introducing a loop seam.
    for rotor, frequency in enumerate(ROTOR_HZ):
        offset = .43 + rotor * 1.81
        phase = 2 * np.pi * frequency * t
        phase += .20 * np.sin(cycle + offset) + .045 * np.sin(3 * cycle - offset)
        load = .84 + .11 * np.sin(cycle + offset) + .05 * np.sin(2 * cycle - offset)
        tone = sum(gain * np.sin(harmonic * phase + .16 * harmonic)
                   for harmonic, gain in [(1, .52), (2, .23), (3, .12),
                                          (4, .055), (6, .025), (8, .012)])
        blade_pass = (.5 + .5 * np.cos(phase + .3))**4
        swish = periodic_noise(160, 1350, SEED + rotor * 137)
        body = periodic_noise(52, 340, SEED + 913 + rotor * 89)
        rotor_sound = .40 * tone * load
        rotor_sound += .12 * swish * (.30 + .70 * blade_pass) * load
        rotor_sound += .058 * body * (.8 + .2 * np.cos(phase))
        # Restrained electric drive overtones, not a vehicle exhaust pattern.
        carrier = 179.5 if rotor == 0 else 213.75
        rotor_sound += .015 * np.sin(2 * np.pi * carrier * t + .09 * np.sin(cycle))
        position = (-.34 if rotor == 0 else .34) + .075 * np.sin(cycle + offset)
        signal += pan(rotor_sound, position)
    common_wind = periodic_noise(90, 950, SEED + 2069)
    gust = .8 + .14 * np.sin(cycle - .7) + .06 * np.sin(3 * cycle)
    signal += pan(.080 * common_wind * gust, .10 * np.sin(cycle))
    for channel in range(2):
        signal[:, channel] += .029 * periodic_noise(150, 1700, SEED + 3019 + channel * 41) * gust
    # Circular filtering preserves the seam. Reduce the speech presence band
    # and very low rumble without making the mechanism thin or hissy.
    frequencies = np.fft.rfftfreq(FRAMES, 1 / RATE)
    response = frequencies**4 / np.sqrt(frequencies**8 + 38.0**8)
    response /= np.sqrt(1 + (frequencies / 2600.0)**8)
    response *= 1 - .60 * np.exp(-.5 * ((frequencies - 2300) / 650)**2)
    spectrum = np.fft.rfft(signal, axis=0) * response[:, None]
    signal = np.fft.irfft(spectrum, n=FRAMES, axis=0)
    signal -= signal.mean(axis=0)
    gain = min(10**(-18 / 20) / np.sqrt(np.mean(signal**2)), .55 / np.abs(signal).max())
    signal *= gain
    # Rotate, never splice or fade, to a quiet continuous point shared by both
    # channels. The loop remains periodic with no recurring fade-out gap.
    differences = signal - np.roll(signal, 1, axis=0)
    seam_cost = np.sum(np.abs(signal), axis=1) + 4 * np.sum(np.abs(differences), axis=1)
    seam = int(np.argmin(seam_cost))
    return np.roll(signal, -seam, axis=0), seam


def main():
    signal, seam = render()
    pcm = np.round(signal * 32767).astype("<i2")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(TARGET), "wb") as output:
        output.setparams((2, 2, RATE, FRAMES, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())
    metadata = {
        "asset": str(TARGET.relative_to(ROOT)),
        "generator": "tools/generate_air_raid_audio.py",
        "source": "Original deterministic stereo synthesis; no samples, recordings, voice models or vehicle assets.",
        "role": "Industrial twin-rotor scout drone and high-altitude wind during the solo air-contact preview",
        "seed": SEED,
        "sample_rate": RATE,
        "frames": FRAMES,
        "seconds": SECONDS,
        "channels": 2,
        "format": "PCM16",
        "rotor_blade_pass_hz": list(ROTOR_HZ),
        "loop": {"begin": 0, "end_exclusive": FRAMES, "mode": "forward",
                 "method": "Periodic carriers, Fourier noise and circular filtering; whole-wave rotation to a quiet seam, no crossfade gap.",
                 "seam_rotation_frames": seam},
        "mix": {"bus": "SFX", "volume_db": RECOMMENDED_DB,
                "additional_speech_duck_db": SPEECH_DUCK_DB,
                "panel_attack_seconds": .65, "panel_release_seconds": .8,
                "note": "Runtime panel owns smooth gain fades, including skip; obeys the SFX slider."},
        "measurements": {"peak_dbfs": float(20 * np.log10(np.abs(signal).max())),
                         "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(signal**2))))},
        "sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
    }
    TARGET.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"file": str(TARGET.relative_to(ROOT)), **metadata["measurements"]}))


if __name__ == "__main__":
    main()
