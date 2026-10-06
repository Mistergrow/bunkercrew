#!/usr/bin/env python3
"""Check the real stereo loop, reconstruction headroom and caption-voice margin."""
from pathlib import Path
import hashlib
import json
import sys
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_air_raid_audio as generator


def main():
    checks = []

    def check(value, label):
        checks.append({"passed": bool(value), "label": label})
        print(("PASS " if value else "FAIL ") + label)

    with wave.open(str(generator.TARGET), "rb") as source:
        check(source.getnchannels() == 2 and source.getsampwidth() == 2
              and source.getframerate() == generator.RATE, "Stereo PCM16 at 32 kHz")
        pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").reshape(-1, 2)
    signal = pcm.astype(np.float64) / 32768
    metadata = json.loads(generator.TARGET.with_suffix(".source.json").read_text())
    check(len(signal) == generator.FRAMES == 128000, "Exactly four seconds with a full-buffer forward loop")
    check(np.isfinite(signal).all() and np.max(np.abs(pcm)) < 18023, "Every sample has at least five decibels of clipping headroom")
    reconstructed_peak = float(np.max(np.abs(resample_poly(np.tile(signal, (3, 1)), 4, 1, axis=0))))
    check(reconstructed_peak < .60, "Four-times reconstructed loop peaks stay below clipping")
    rms = float(np.sqrt(np.mean(signal**2)))
    rms_db = float(20 * np.log10(rms))
    check(-21 < rms_db < -17, "Moderate source RMS leaves room for dialogue")
    check(np.max(np.abs(signal.mean(axis=0))) < .00001, "No DC offset in either channel")
    difference = signal - np.roll(signal, 1, axis=0)
    seam_step = np.abs(signal[0] - signal[-1])
    ordinary_limit = np.quantile(np.abs(difference), .99, axis=0)
    check(np.all(seam_step < ordinary_limit) and float(seam_step.max()) < .004,
          "The actual wrap step is quieter than normal sample changes in both channels")
    curvature = difference - np.roll(difference, 1, axis=0)
    check(np.all(np.abs(curvature[[0, 1]]) < np.quantile(np.abs(curvature), .999, axis=0)),
          "Loop seam has no abnormal slope discontinuity")
    # Check both sides and the straddling window: a fade-to-silence loop would
    # pass a zero endpoint check but would audibly pump every four seconds.
    window = generator.RATE // 10
    seam_rms = [float(np.sqrt(np.mean(samples**2))) for samples in
                [signal[-window:], signal[:window], np.concatenate([signal[-window // 2:], signal[:window // 2]])]]
    check(min(seam_rms) > rms * .60 and max(seam_rms) / min(seam_rms) < 1.50,
          "Continuous energy around the wrap has no recurring fade-out gap")
    side_rms = float(np.sqrt(np.mean(((signal[:, 0] - signal[:, 1]) * .5)**2)))
    mono_rms = float(np.sqrt(np.mean(signal.mean(axis=1)**2)))
    check(side_rms > rms * .12 and mono_rms > rms * .8, "Rotor separation is stereo and remains audible in mono")
    spectrum = np.abs(np.fft.rfft(signal, axis=0))**2
    frequencies = np.fft.rfftfreq(len(signal), 1 / generator.RATE)
    high_fraction = float(spectrum[frequencies > 6000].sum() / spectrum.sum())
    check(high_fraction < .0001, "High-frequency hiss is restrained")
    rendered, _ = generator.render()
    check(np.array_equal(pcm, np.round(rendered * 32767).astype("<i2")), "Generator reproduces the delivered PCM exactly")
    check(metadata["sha256"] == hashlib.sha256(generator.TARGET.read_bytes()).hexdigest(), "Adjacent source metadata verifies the delivered WAV")
    voice_margins = {}
    for locale in ["de", "en"]:
        directory = ROOT / "assets/audio/story_voices_v2"
        if locale == "en":
            directory /= "en"
        for speaker in ["mara", "branko", "ivo", "nora", "levin", "selma"]:
            with wave.open(str(directory / (speaker + "_crew_air.wav"))) as source:
                speech = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(float) / 32768
            voice_db = 20 * np.log10(np.sqrt(np.mean(speech**2)))
            margin = float(voice_db - (rms_db + generator.RECOMMENDED_DB + generator.SPEECH_DUCK_DB))
            voice_margins[locale + "/" + speaker] = round(margin, 3)
            check(margin > 8, locale + "/" + speaker + " voice exceeds the ducked rotor by at least eight dB RMS")
    output = ROOT / "artifacts/air-raid-audio"
    output.mkdir(parents=True, exist_ok=True)
    result = {"passed": sum(entry["passed"] for entry in checks), "failed": sum(not entry["passed"] for entry in checks),
              "checks": checks, "rms_dbfs": rms_db, "reconstructed_peak_4x": reconstructed_peak,
              "loop_step": seam_step.tolist(), "seam_window_rms": seam_rms,
              "stereo_side_rms": side_rms, "mono_rms": mono_rms, "above_6khz_energy": high_fraction,
              "voice_margin_db": voice_margins,
              "review": "Technical signal measurements; no subjective listening claim. Four-times resampling is not a certified true-peak meter."}
    (output / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
    (output / "index.html").write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Air contact audio</title>'
        '<style>body{background:#1b2328;color:#ebe4ce;font:18px system-ui;margin:3rem;max-width:46rem}audio{width:100%}</style>'
        '<h1>Twin-rotor scout drone</h1><p>Original stereo rotor and wind synthesis. Four-second continuous loop; '
        'in-game gain −9 dB, another −4 dB during the character comment.</p>'
        '<audio controls loop preload="none" src="../../assets/audio/air_raid_flyover_v1.wav"></audio>'
        '<p>No subjective listening assessment. <a href="verification.json">Signal measurements</a>.</p></html>')
    print(f'AIR RAID AUDIO: {result["passed"]}/{len(checks)} passed; RMS {rms_db:.2f} dBFS')
    return int(result["failed"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
