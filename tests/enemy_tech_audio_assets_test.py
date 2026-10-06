#!/usr/bin/env python3
"""Check decoded assets, original-bank preservation, family variety and edges."""
from pathlib import Path
import hashlib
import html
import importlib.util
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("enemy_tech", ROOT / "tools/generate_enemy_tech_audio.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
OUT = ROOT / "assets/audio"
REPORT = ROOT / "artifacts/enemy-tech-audio"
REPORT.mkdir(parents=True, exist_ok=True)
metadata = json.loads((OUT / "enemy_tech_sources.json").read_text())
failures = []
metrics = {}
decoded = {}


def check(ok, message):
    if not ok:
        failures.append(message)
        print("FAIL:", message)


for name, expected in metadata["assets"].items():
    path = OUT / name
    check(hashlib.sha256(path.read_bytes()).hexdigest() == expected["sha256"], f"{name}: output hash")
    with wave.open(str(path)) as stream:
        check(stream.getframerate() == 48000 and stream.getsampwidth() == 2, f"{name}: 48 kHz PCM16")
        channels = stream.getnchannels()
        pcm = np.frombuffer(stream.readframes(stream.getnframes()), dtype="<i2").astype(float) / 32767
    pcm = pcm.reshape(-1, channels)
    peak = float(np.max(np.abs(pcm)))
    rms = float(np.sqrt(np.mean(pcm ** 2)))
    check(channels == (2 if name.startswith("tech_") else 1), f"{name}: channel layout")
    check(.4 < peak < .7 and .015 < rms < .22, f"{name}: non-silent, restrained headroom")
    check(np.max(np.abs(pcm[[0, -1]])) < .0001, f"{name}: click-free endpoints")
    check(abs(float(pcm.mean())) < .0001, f"{name}: DC offset")
    # Compare the real decoded samples against repeat generation, including all layers.
    if name.startswith("enemy_step_"):
        suffix = name.removeprefix("enemy_step_").removesuffix(".wav")
        family, surface, variant = suffix.rsplit("_", 2)
        regenerated = generator.contact(family, surface, int(variant) - 1)[:, None]
    else:
        branch, variant = name.removeprefix("tech_upgrade_").removesuffix(".wav").rsplit("_", 1)
        regenerated = generator.upgrade(branch, int(variant) - 1)
    check(np.max(np.abs(pcm - regenerated)) <= 1 / 32767, f"{name}: deterministic recorded-source processing")
    decoded[name] = pcm
    metrics[name] = {"peak": peak, "rms": rms, "seconds": len(pcm) / 48000, "channels": channels}

for name, digest in metadata["preserved_sha256"].items():
    check(hashlib.sha256((OUT / name).read_bytes()).hexdigest() == digest, f"{name}: original bank preserved")
for name, digest in metadata["source_pack"]["files"].items():
    check(hashlib.sha256((generator.SOURCES / name).read_bytes()).hexdigest() == digest, f"{name}: CC0 source preserved")
check(len(decoded) == 172, "Complete 160-contact / 12-upgrade deliverable")
for family in generator.FAMILIES:
    for surface in generator.SURFACES:
        hashes = {metadata["assets"][f"enemy_step_{family}_{surface}_{i:02d}.wav"]["sha256"] for i in range(1, 6)}
        check(len(hashes) == 5, f"{family}/{surface}: five distinct waveforms")

# Standalone relative-path listening gallery, including cadence demos.
rows = []
labels = {"mech_light": "Leichte Läufer", "mech_quad": "Mehrbeinige Maschinen",
          "mech_assault": "Sturmmaschinen", "mech_heavy": "Schwere Mechs",
          "mech_colossus": "Koloss / Bastion", "boot_light": "Leichte Infanterie",
          "boot_standard": "Infanterie", "boot_heavy": "Schwere Infanterie"}
cadences = [.30, .40, .35, .58, .72, .32, .42, .52]
for index, family in enumerate(generator.FAMILIES):
    cadence = cadences[index]
    walk = np.zeros(round((4 * cadence + 1) * 48000))
    for variant in range(5):
        data = decoded[f"enemy_step_{family}_dry_{variant + 1:02d}.wav"][:, 0]
        start = round(variant * cadence * 48000)
        walk[start:start + len(data)] += data * .7
    filename = f"{family}_walk.wav"
    generator.save(REPORT / filename, walk)
    links = " ".join(f'<a href="../../assets/audio/enemy_step_{family}_{s}_01.wav">{s}</a>' for s in generator.SURFACES)
    rows.append(f'<article><h2>{html.escape(labels[family])}</h2><audio controls preload="none" src="{filename}"></audio><p>{links}</p></article>')
for branch, label in zip(generator.UPGRADES, ["Basis", "Waffen", "Besatzung", "Fahrzeug"]):
    rows.append(f'<article><h2>Upgrade: {label}</h2><audio controls preload="none" src="../../assets/audio/tech_upgrade_{branch}_01.wav"></audio></article>')
(REPORT / "index.html").write_text('<!doctype html><html lang="de"><meta charset="utf-8"><title>Bunkercrew – Schritte und Technik</title><style>body{background:#18201f;color:#dae0d4;font:16px system-ui;max-width:960px;margin:40px auto}main{display:grid;grid-template-columns:1fr 1fr;gap:20px}article{padding:18px;background:#28322e}h2{font-size:19px}a{color:#d5b46c}audio{width:100%}</style><h1>Gegnerschritte und Technik-Upgrades</h1><p>Hörprobe der fertigen Assets: fünf Schrittvarianten pro Typ. Die Spielmischung verwendet Entfernung, Raumklang und niedrigere Schrittlautstärke.</p><main>' + ''.join(rows) + '</main></html>')
(REPORT / "measurements.json").write_text(json.dumps({"assets": metrics, "failures": failures}, indent=2) + "\n")
print(f"ENEMY TECH ASSETS: {len(decoded)} WAV assets, {len(failures)} failures; gallery: {REPORT / 'index.html'}")
raise SystemExit(1 if failures else 0)
