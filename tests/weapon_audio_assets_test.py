#!/usr/bin/env python3
"""Validate original weapon foley and render an optional browser review gallery."""
from pathlib import Path
import hashlib
import itertools
import json
import sys
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
import generate_weapon_audio as generator

OUTPUT = ROOT/"artifacts/weapon-audio"
checks = []


def check(value, label):
    checks.append({"passed": bool(value), "label": label})
    if not value:
        print("FAIL", label)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = json.loads((generator.OUT/"weapon_sources.json").read_text())
    bank, metrics, correlations = {}, {}, {}
    for kind, count in source["variants"].items():
        for variant in range(count):
            name = f"{kind}_{variant+1:02}.wav"
            with wave.open(str(generator.OUT/name)) as file:
                check(file.getnchannels() == 1 and file.getsampwidth() == 2 and file.getframerate() == 32000,
                      name+": mono PCM16 at 32 kHz")
                raw = np.frombuffer(file.readframes(file.getnframes()), dtype="<i2")
            data = raw.astype(float)/32768
            spectrum = np.abs(np.fft.rfft(data))**2
            hz = np.fft.rfftfreq(len(data), 1/32000)
            value = {"seconds": len(data)/32000, "peak": float(np.abs(data).max()),
                     "rms": float(np.sqrt(np.mean(data**2))), "dc": float(abs(data.mean())),
                     "reconstructed_peak_4x": float(np.abs(resample_poly(data, 4, 1)).max()),
                     "above_8khz_fraction": float(spectrum[hz>8000].sum()/spectrum.sum()),
                     "centroid_hz": float((spectrum*hz).sum()/spectrum.sum())}
            metrics[name] = value
            bank[name] = data
            check(len(data) == round(source["events"][kind]["seconds"]*32000), name+": declared phase length")
            check(.025 < value["rms"] < .24 and .53 < value["peak"] <= .69, name+": audible body with mix headroom")
            check(value["reconstructed_peak_4x"] < .79, name+": reconstructed peaks remain below clipping")
            check(value["dc"] < .00002 and raw[0] == 0 and raw[-1] == 0, name+": no DC offset or hard event edge")
            check(value["above_8khz_fraction"] < .002, name+": restrained highest frequencies")
            expected = np.round(generator.render(kind, variant)*32767).astype("<i2")
            check(np.array_equal(raw, expected), name+": reproducible generated PCM")
        pairs = [float(np.corrcoef(bank[f"{kind}_{a:02}.wav"], bank[f"{kind}_{b:02}.wav"])[0,1])
                 for a,b in itertools.combinations(range(1, count+1), 2)]
        correlations[kind] = pairs
        check(max(pairs) < .90, kind+": variations differ beyond gain")
    for phase in ("open", "load", "close"):
        for first, second in itertools.combinations(generator.PROFILES, 2):
            correlation = float(np.corrcoef(bank[f"reload_{first}_{phase}_01.wav"], bank[f"reload_{second}_{phase}_01.wav"])[0,1])
            check(abs(correlation) < .85, f"{phase}: {first} and {second} have distinct mechanical recordings")
    for name, digest in source["preserved_sha256"].items():
        check(hashlib.sha256((generator.OUT/name).read_bytes()).hexdigest() == digest, name+": previous asset unchanged")
    check(sum(source["variants"].values()) == 51, "Fifty-one new recordings across seventeen families")
    result = {"passed":sum(c["passed"] for c in checks), "failed":sum(not c["passed"] for c in checks),
              "measurements":metrics, "variant_correlations":correlations, "checks":checks,
              "review":"Technical measurements only; source recordings are CC0 by SpringySpringo and Brian MacIntosh. No subjective listening assessment.",
              "peak_method":"4x scipy resample_poly; not a certified true-peak meter."}
    (OUTPUT/"asset-measurements.json").write_text(json.dumps(result, indent=2)+"\n")
    cards = []
    for family in generator.PROFILES:
        phases = "".join(f'<label>{phase}<audio controls preload="none" src="../../assets/audio/reload_{family}_{phase}_01.wav"></audio></label>'
                         for phase in ("open", "load", "close"))
        cards.append(f'<section><h2>{family.title()}</h2><p>{generator.PROFILES[family]["description"]}</p>{phases}'
                     f'<p>Real mixer capture: <audio controls preload="none" src="capture-{family}.wav"></audio></p></section>')
    for kind in ("weapon_mount", "weapon_switch"):
        controls = "".join(f'<label>Variant {variant}<audio controls preload="none" src="../../assets/audio/{kind}_{variant:02}.wav"></audio></label>' for variant in range(1,4))
        cards.append(f'<section><h2>{kind.replace("_", " ").title()}</h2>{controls}</section>')
    html = '<!doctype html><html lang="en"><meta charset="utf-8"><title>Weapon handling audio</title><style>body{font:16px system-ui;background:#171e21;color:#eadfc8;max-width:1000px;margin:32px auto}section{border-top:1px solid #566368;padding:16px}label{display:inline-block;margin:8px}audio{display:block;width:280px}a{color:#ddb875}</style><h1>Weapon handling audio</h1><p>Reload revision 2: edits of attributed CC0 mechanical recordings; original synthesis for mount/switch. Three variants per phase. No subjective listening assessment; players below require manual interaction. Real mixer captures use prepared weapon states, normal timed reload logic, default 65% effects volume and Dummy audio output.</p>'+''.join(cards)+'<p><a href="asset-measurements.json">Asset measurements</a> · <a href="runtime-measurements.json">Runtime measurements</a></p></html>'
    (OUTPUT/"index.html").write_text(html)
    print(f'WEAPON AUDIO ASSETS: {result["passed"]}/{len(checks)} passed')
    print("Peak/RMS/reconstructed:", max(m["peak"] for m in metrics.values()),
          min(m["rms"] for m in metrics.values()), max(m["rms"] for m in metrics.values()),
          max(m["reconstructed_peak_4x"] for m in metrics.values()))
    return int(result["failed"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
