#!/usr/bin/env python3
"""Verify authored scene PCM, visual pan, reconstruction and speech headroom."""
from pathlib import Path
import hashlib
import json
import sys
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_travel_cinematic_audio as generator


def main():
    checks = []
    measurements = {}

    def check(value, label):
        checks.append({"passed": bool(value), "label": label})
        print(("PASS " if value else "FAIL ") + label)

    for kind, (seconds, role, position, _) in generator.SPECS.items():
        path = generator.OUT / (kind + ".wav")
        with wave.open(str(path), "rb") as source:
            check(source.getnchannels() == 2 and source.getsampwidth() == 2
                  and source.getframerate() == generator.RATE, kind + ": stereo PCM16 at 48 kHz")
            pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").reshape(-1, 2)
        signal = pcm.astype(float) / 32768
        check(len(signal) == round(seconds * generator.RATE), kind + ": exact authored scene or cue length")
        check(np.isfinite(signal).all() and np.max(np.abs(signal)) <= .44001,
              kind + ": finite samples with at least seven dB source headroom")
        rms = float(np.sqrt(np.mean(signal ** 2)))
        rms_db = float(20 * np.log10(rms))
        peak4 = float(np.max(np.abs(resample_poly(signal, 4, 1, axis=0))))
        check(peak4 < .51, kind + ": oversampled reconstruction remains below half scale")
        check(-30 < rms_db < -20, kind + ": useful source energy without raising existing bus settings")
        check(np.max(np.abs(signal.mean(axis=0))) < .000002,
              kind + ": negligible DC in both channels")
        check(np.max(np.abs(signal[[0, -1]])) == 0,
              kind + ": silent authored endpoints prevent an initial or terminal click")
        check(np.array_equal(pcm, np.round(generator.render(kind) * 32767).astype("<i2")),
              kind + ": generator reproduces every delivered PCM sample")
        metadata = json.loads(path.with_suffix(".source.json").read_text())
        check(metadata["sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
              and metadata["generator_sha256"] == hashlib.sha256(Path(generator.__file__).read_bytes()).hexdigest(),
              kind + ": asset and actual generator are traceable by SHA-256")
        check(path.with_suffix(".LICENSE.txt").read_text().startswith(generator.LICENSE)
              and metadata["license"] == generator.LICENSE, kind + ": original Bunkercrew distribution notice retained")
        powers = np.mean(signal ** 2, axis=0)
        measured_pan = float((powers[1] - powers[0]) / powers.sum())
        if role == "cue":
            check(abs(measured_pan - position) < .00003, kind + ": actual stereo energy follows pictured right-hand object")
        elif kind == "supply_generator_v1":
            check(0.03 < measured_pan < .15, kind + ": generator at x=783 is slightly right of screen center")
            onset = float(np.sqrt(np.mean(signal[:generator.RATE] ** 2)))
            running = float(np.sqrt(np.mean(signal[2*generator.RATE:4*generator.RATE] ** 2)))
            check(running > onset * 1.6, kind + ": engine energy catches only after pictured fan begins")
        else:
            check(float(np.sqrt(np.mean((signal[:, 0] - signal[:, 1]) ** 2))) > .005,
                  kind + ": ambience has actual stereo separation")
        check(np.sqrt(np.mean(signal.mean(axis=1) ** 2)) > rms * .88,
              kind + ": mono sum retains physical sound without phase cancellation")
        spectrum = np.abs(np.fft.rfft(signal, axis=0)) ** 2
        frequencies = np.fft.rfftfreq(len(signal), 1 / generator.RATE)
        ultrasonic = float(spectrum[frequencies > 9000].sum() / spectrum.sum())
        check(ultrasonic < .005, kind + ": high-frequency noise is restrained")
        measurements[kind] = {"rms_dbfs": rms_db, "reconstructed_peak_4x": peak4,
            "screen_pan_measured": measured_pan, "above_9khz_energy": ultrasonic,
            "frames": len(signal), "bytes": path.stat().st_size}
    # Compare actual identity-matched recordings at the unchanged 50% bus
    # reference. Master processing is shared, so cancels from this margin.
    # Beds use -10 dB, the SFX bus -6.0206 dB, plus the scene's -7 dB duck.
    voice_margins = {}
    for locale in ["de", "en"]:
        directory = ROOT / "assets/audio/story_voices_v2"
        if locale == "en": directory /= "en"
        for scene, line in [("signal", "crew_reply"), ("storm", "crew_storm"), ("supply", "crew_clear")]:
            bed = {"signal": "signal_receiver_v1", "storm": "storm_roof_rain_v1", "supply": "supply_generator_v1"}[scene]
            bed_level = measurements[bed]["rms_dbfs"] - 10 - 6.0206 - 7
            for speaker in ["mara", "branko", "ivo", "nora", "levin", "selma"]:
                path = directory / (speaker + "_" + line + ".wav")
                with wave.open(str(path), "rb") as source:
                    voice = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(float) / 32768
                voice_db = 20 * np.log10(np.sqrt(np.mean(voice ** 2))) - 14.89455
                margin = float(voice_db - bed_level)
                voice_margins[locale + "/" + speaker + "/" + scene] = margin
                check(margin > 8, locale + "/" + speaker + "/" + scene + ": actual speech exceeds ducked bed by eight dB RMS")
            radio_line = {"signal": "relay_online", "storm": "storm_tree", "supply": "wave_clear"}[scene]
            with wave.open(str(directory / ("san_" + radio_line + ".wav")), "rb") as source:
                radio = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(float) / 32768
            radio_db = 20 * np.log10(np.sqrt(np.mean(radio ** 2))) - 14.89455
            margin = float(radio_db - bed_level)
            voice_margins[locale + "/san_for_oskar_rika/" + scene] = margin
            check(margin > 8, locale + "/SAN-1/" + scene + ": Oskar and Rika retain eight dB radio margin")
    manifest = json.loads((generator.OUT / "sources.json").read_text())
    check(len(manifest["assets"]) == 6 and all((ROOT / value).is_file() for key, value in manifest["reuse"].items()
          if key != "dialogue"), "New recordings and existing thunder/flyover are explicitly accounted for")
    output = ROOT / "artifacts/vegetation-cinematics-20261004/audio"
    output.mkdir(parents=True, exist_ok=True)
    result = {"passed": sum(entry["passed"] for entry in checks), "failed": sum(not entry["passed"] for entry in checks),
              "checks": checks, "measurements": measurements, "voice_margin_db": voice_margins,
              "scope": "Deterministic PCM measurements and unchanged 50% reference-bus speech margin; no subjective human listening claim."}
    (output / "assets-verification.json").write_text(json.dumps(result, indent=2) + "\n")
    clips = "".join('<p>' + kind + '</p><audio controls preload="none" src="../../../assets/audio/travel_cinematics/'
                    + kind + '.wav"></audio>' for kind in generator.SPECS)
    (output / "index.html").write_text('<!doctype html><html lang="de"><meta charset="utf-8"><title>Reiseszenen – Soundprüfung</title>'
        '<style>body{background:#172321;color:#e5dfcb;font:18px system-ui;margin:3rem;max-width:55rem}audio{width:100%}</style>'
        '<h1>Originale für die Reiseszenen</h1><p>Signalempfänger, Regen auf dem Schutzdach und Versorgungsstation. '
        'Die Dateien sind Quellen vor dem leiseren SFX-Mix. Sprache senkt sie im Spiel zusätzlich um 7 dB.</p>' + clips
        + '<p><a href="assets-verification.json">Signalprüfung</a> · Keine behauptete menschliche Hörabnahme.</p></html>')
    print(f'TRAVEL CINEMATIC ASSETS: {result["passed"]}/{len(checks)} passed')
    return int(result["failed"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
