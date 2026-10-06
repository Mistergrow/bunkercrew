#!/usr/bin/env python3
"""Verify real mixer captures and build a browser listening comparison."""
from pathlib import Path
import json
import math
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/environment-acoustics"
REPORT = json.loads((OUT / "mixer-measurements.json").read_text())
NAMES = {
    "explosion-outside": "Draußen: offener Raum",
    "explosion-inside": "Im Bunker: kurze Betonreflexionen",
    "explosion-outside-wall": "Außenexplosion hinter intakter Bunkerwand",
    "explosion-open-door": "Gleiche Positionen mit entfernter Wand",
    "explosion-left": "Quelle links, hinter dem Bunker",
    "explosion-right": "Quelle rechts im Freien",
}
checks = 0
rows = {}


def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)


for name in NAMES:
    with wave.open(str(OUT / (name + ".wav")), "rb") as wav:
        check(wav.getnchannels() == 2 and wav.getsampwidth() == 2, name + " is stereo PCM16")
        rate = wav.getframerate()
        samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float64).reshape(-1, 2) / 32768
    check(rate == round(REPORT["mix_rate"]), name + " preserves the native mixer rate")
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples**2)))
    tail = float(np.sum(samples[round(rate * 1.3):] ** 2))
    channels = np.sum(samples**2, axis=0)
    roughness = float(np.sum(np.diff(samples, axis=0)**2) / np.sum(samples**2))
    check(.0001 < rms < .2 and peak < .98, name + " is audible, finite and unclipped")
    check(abs(rms - REPORT["recordings"][name]["rms"]) < .0001, name + " agrees with in-engine capture metrics")
    rows[name] = dict(rate=rate, frames=len(samples), rms=rms, peak=peak, tail=tail,
                      high_frequency_ratio=roughness, left=float(channels[0]), right=float(channels[1]))

check(rows["explosion-inside"]["tail"] > max(1e-7, rows["explosion-outside"]["tail"] * 2), "room reflection tail survives file export")
check(rows["explosion-outside-wall"]["rms"] < rows["explosion-open-door"]["rms"] * .6, "real wall attenuates fixed-position control")
check(rows["explosion-outside-wall"]["high_frequency_ratio"] < rows["explosion-open-door"]["high_frequency_ratio"] * .7, "wall removes measurable high-frequency energy")
check(rows["explosion-left"]["left"] > rows["explosion-left"]["right"] * 1.5, "left output is actually panned")
check(rows["explosion-right"]["right"] > rows["explosion-right"]["left"] * 1.5, "right output is actually panned")
wall_db = 20 * math.log10(rows["explosion-outside-wall"]["rms"] / rows["explosion-open-door"]["rms"])
OUT.joinpath("recording-verification.json").write_text(json.dumps({"checks":checks, "wall_attenuation_db":wall_db, "recordings":rows}, indent=2) + "\n")
cards = "\n".join(
    f'<section><h2>{label}</h2><audio controls preload="none" src="{name}.wav"></audio>'
    f'<p>RMS {rows[name]["rms"]:.4f} · Spitze {rows[name]["peak"]:.3f}</p></section>'
    for name, label in NAMES.items()
)
OUT.joinpath("index.html").write_text(
    '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
    '<title>Letzte Schicht – Raumakustik</title><style>'
    'body{max-width:980px;margin:3rem auto;padding:0 1rem;background:#151b1b;color:#ddd8c9;font:17px/1.55 system-ui}'
    'h1{font-size:2rem}h2{font-size:1.12rem}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1.2rem}'
    'section{padding:1rem 1.2rem;background:#232c2b;border-radius:5px}audio{width:100%}a{color:#b5cdac}p{max-width:75ch}</style>'
    '<h1>Raumakustik im Spiel</h1><p>Originale Explosion, durch den tatsächlichen Godot-Audiomixer aufgenommen: '
    'offene Umgebung, Betonraum und Schallübertragung durch die echte Bunkerwand. Musik und Sprache waren für den Vergleich stumm. '
    'Dies sind vorbereitete Spielsituationen, keine nachträglich bearbeiteten Soundvarianten.</p>'
    f'<p>Bei identischen Quell- und Hörerpositionen reduziert die intakte Wand den gemessenen Pegel um {abs(wall_db):.1f} dB. '
    'Alle Dateien sind unverändert aus dem Master-Mixer exportiert; sie wurden nicht einzeln normalisiert.</p><main>'
    + cards + '</main><p>Keine subjektive Hörbewertung durch den Agenten. Nachweise: '
    '<a href="verification.md">Prüfbericht</a> · <a href="mixer-measurements.json">Mixer-Messung</a> · '
    '<a href="recording-verification.json">WAV-Prüfung</a></p></html>'
)
print(f"ACOUSTIC RECORDINGS: {checks}/{checks} checks passed; wall {wall_db:.2f} dB")
