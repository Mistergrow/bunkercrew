#!/usr/bin/env python3
"""Validate the shipping dry steel bank and its local recorded provenance."""
from pathlib import Path
import hashlib
import itertools
import json
import sys
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/core-impact"
OUTPUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / "tools"))
import generate_core_impact_audio as generator

checks = []
measurements = {}


def check(value, description):
    checks.append({"passed": bool(value), "description": description})
    print(("PASS " if value else "FAIL ") + description)


def main():
    bank = {}
    for variant in range(generator.VARIANTS):
        path = ROOT / f"assets/audio/impact_core_{variant + 1:02d}.wav"
        metadata = json.loads(path.with_suffix(".source.json").read_text())
        with wave.open(str(path), "rb") as source:
            channels, rate, width = source.getnchannels(), source.getframerate(), source.getsampwidth()
            pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
        signal = pcm.astype(np.float64) / 32768
        spectrum = np.abs(np.fft.rfft(signal)) ** 2
        frequency = np.fft.rfftfreq(len(signal), 1 / rate)
        energy = float(np.sum(signal ** 2))
        metrics = {
            "seconds": len(signal) / rate, "peak": float(np.max(np.abs(signal))),
            "reconstructed_peak_4x": float(np.max(np.abs(resample_poly(signal, 4, 1)))),
            "rms": float(np.sqrt(np.mean(signal ** 2))), "dc": float(signal.mean()),
            "energy_below_180_hz": float(spectrum[frequency < 180].sum() / spectrum.sum()),
            "energy_after_80_ms": float(np.sum(signal[round(.080 * rate):] ** 2) / energy),
            "tail_rms_after_120_ms": float(np.sqrt(np.mean(signal[round(.120 * rate):] ** 2))),
        }
        measurements[path.name] = metrics
        bank[path.name] = signal
        check(channels == 1 and rate == 48000 and width == 2 and .20 < metrics["seconds"] < .30,
              path.name + ": short mono 48 kHz PCM contact")
        check(np.isfinite(signal).all() and .015 < metrics["rms"] < .12,
              path.name + ": finite and audible signal")
        check(.60 < metrics["peak"] < .66 and metrics["reconstructed_peak_4x"] < .70,
              path.name + ": decoded and reconstructed headroom")
        check(pcm[0] == 0 and pcm[-1] == 0 and abs(metrics["dc"]) < .0001,
              path.name + ": silent event edges and negligible DC")
        check(metrics["energy_below_180_hz"] < .075,
              path.name + ": restrained low frequencies instead of a bass drum body")
        check(metrics["energy_after_80_ms"] < .005 and metrics["tail_rms_after_120_ms"] < .0001,
              path.name + ": a damped physical strike without sustained percussion ringing")
        check(metadata["processing"]["added_oscillators"] == 0 and not metadata["processing"]["reverb"]
              and metadata["source_license"] == "CC0-1.0" and path.with_suffix(".LICENSE.txt").exists(),
              path.name + ": recorded CC0 layers with adjacent provenance and license")
        check(hashlib.sha256(path.read_bytes()).hexdigest() == metadata["sha256"],
              path.name + ": exact shipping asset hash")
        check(np.array_equal(pcm, np.round(generator.contact(variant) * 32767).astype("<i2")),
              path.name + ": deterministic reproduction from the declared recordings")
        check(all(hashlib.sha256((generator.SOURCE / name).read_bytes()).hexdigest() == digest
                  for name, digest in metadata["source_recordings"].items()),
              path.name + ": local recording hashes match the source declaration")
    correlations = {}
    for first, second in itertools.combinations(bank, 2):
        count = min(len(bank[first]), len(bank[second]))
        correlation = float(np.corrcoef(bank[first][:count], bank[second][:count])[0, 1])
        correlations[first + "/" + second] = correlation
        check(abs(correlation) < .985, first + "/" + second + ": distinct physical contact variation")
    report = {"checks": len(checks), "passed": sum(item["passed"] for item in checks),
              "failed": sum(not item["passed"] for item in checks), "measurements": measurements,
              "correlations": correlations, "results": checks,
              "measurement_limit": "4x polyphase reconstructed peaks; no claimed listening assessment or certified true-peak meter."}
    (OUTPUT / "asset-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    controls = "".join(f'<p>Variante {index}<audio controls preload="none" src="../../assets/audio/impact_core_{index:02d}.wav"></audio></p>'
                       for index in range(1, generator.VARIANTS + 1))
    (OUTPUT / "index.html").write_text(
        '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Bunkercrew · Bunkerkern-Treffer</title><style>body{max-width:820px;margin:40px auto;padding:0 24px;background:#141c19;color:#d4d1bc;font:17px system-ui}audio{display:block;margin:12px 0;width:100%}a{color:#d7b365}</style>'
        '<h1>Bunkerkern-Treffer</h1><p>Fünf kurze, gedämpfte Stahlkontakte aus den vorhandenen Kenney-Aufnahmen. Keine hinzugefügten musikalischen Töne oder Bassdrum-Körper.</p>'
        '<p>Bisheriger allgemeiner Metalltreffer<audio controls preload="none" src="../../assets/audio/impact_metal_01.wav"></audio></p>'
        + controls + '<p><a href="asset-verification.json">PCM- und Herkunftsprüfung</a></p></html>')
    print(f"CORE IMPACT ASSETS: {report['passed']}/{report['checks']} checks passed")
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
