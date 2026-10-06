#!/usr/bin/env python3
"""Master fixed original Tessel scores, keeping real native hit timestamps.

No external samples or recordings. Distribution is only permitted with Bunkercrew.
"""
from __future__ import annotations

import argparse
from html import escape
import hashlib
import json
import os
from math import gcd
from pathlib import Path
import re
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/music-beat-refresh"
SOURCE = OUTPUT / "source"
RATE = 48000


def loudness(path: Path) -> dict:
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                             "-af", "loudnorm=I=-16.5:TP=-2:LRA=8:print_format=json",
                             "-f", "null", "-"], capture_output=True, text=True, check=True)
    match = re.findall(r'\{\s*"input_i".*?\}', result.stderr, re.S)
    if not match:
        raise RuntimeError("Missing actual loudness measurement: " + str(path))
    return json.loads(match[-1])


def markers(source: dict) -> dict:
    result = {}
    authored_form = bool(source.get("form"))
    for track, prefix in [(0, "kick"), (8, "secondary")]:
        hits = sorted((event for event in source["events"] if int(event["track"]) == track), key=lambda event: int(event["sample"]))
        samples = [round(int(event["sample"]) * RATE / int(source["rate"])) for event in hits]
        strengths = [round(float(event["strength"]), 6) for event in hits]
        beats = ([0, 16] if track == 0 else [0, 8, 16, 24]) if authored_form else []
        beats += [beat + (0 if track == 0 else .5) for beat in range(32 if authored_form else 0, 128)]
        grid = [beat * RATE * 60 / float(source["bpm"]) for beat in beats]
        if len(samples) != len(grid) or samples != sorted(set(samples)):
            raise RuntimeError("Lost or duplicate authored markers: " + source["id"])
        tolerance = 1 if track == 0 else round(RATE * .004)
        if any(abs(sample - round(expected)) > tolerance for sample, expected in zip(samples, grid)):
            raise RuntimeError("Native markers disagree with the authored groove: " + source["id"])
        result[prefix + "_samples"] = samples
        result[prefix + "_strengths"] = strengths
    return result


def finish(source_path: Path, shared_gain_db: float | None = None) -> dict:
    source = json.loads(source_path.read_text())
    identifier, arrangement = source["id"], source["arrangement"]
    version = int(source.get("version", source["settings"].get("composition_version", 1)))
    name = source.get("asset") or (f"menu_rave_{identifier}_v{version}.ogg" if source["role"] == "menu" else f"music_rave_{identifier}_v{version}_{arrangement}.ogg")
    asset = ROOT / "assets/audio" / name
    pcm = np.fromfile(source_path.with_suffix(".f32"), dtype="<f4").reshape(-1, 2).astype(np.float64)
    source_rate = int(source["rate"])
    if source_rate != RATE:
        common = gcd(source_rate, RATE)
        pcm = resample_poly(pcm, RATE // common, source_rate // common, axis=0)
    target = int(source["target_frames"])
    if abs(len(pcm) - target) > 1 or not np.isfinite(pcm).all():
        raise RuntimeError("Invalid source PCM duration: " + name)
    if len(pcm) < target:
        pcm = np.concatenate((pcm, pcm[-1:]), axis=0)
    pcm = pcm[:target]
    pcm -= pcm.mean(axis=0)
    seam_frames = round(RATE * .002)
    bridge = (1 - np.cos(np.linspace(0, np.pi, seam_frames))) / 2
    pcm[-seam_frames:] += bridge[:, None] * (pcm[0] - pcm[-1])
    with tempfile.TemporaryDirectory(prefix="bunkercrew-rave-master-") as temporary:
        wave = Path(temporary) / "master.wav"
        wavfile.write(wave, RATE, pcm.astype(np.float32))
        measured = loudness(wave)
        gain_db = min(-16.5 - float(measured["input_i"]), -2 - float(measured["input_tp"])) if shared_gain_db is None else shared_gain_db
        if float(measured["input_tp"]) + gain_db > -2:
            raise RuntimeError("Shared pair gain exceeds true-peak headroom: " + name)
        pcm *= 10 ** (gain_db / 20)
        wavfile.write(wave, RATE, pcm.astype(np.float32))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wave), "-c:a", "libvorbis", "-q:a", "6",
                        "-metadata", "title=" + source["title"], "-metadata", "artist=Bunkercrew / Audiote", str(Path(temporary) / name)], check=True)
        staged_asset = Path(temporary) / name
        decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", str(staged_asset), "-f", "f32le", "-acodec", "pcm_f32le", "-"], capture_output=True, check=True)
        decoded_pcm = np.frombuffer(decoded.stdout, dtype="<f4").reshape(-1, 2)
        if len(decoded_pcm) != target or not np.isfinite(decoded_pcm).all():
            raise RuntimeError("Decoded OGG contains invalid output: " + name)
        final = loudness(staged_asset)
        if float(final["input_tp"]) > -1.8:
            raise RuntimeError("Decoded true peak exceeds tolerance: " + name)
        if float(np.max(np.abs(decoded_pcm[-1] - decoded_pcm[0]))) > .005:
            raise RuntimeError("Decoded loop seam exceeds tolerance: " + name)
        os.replace(staged_asset, asset)
    seam_delta = float(np.max(np.abs(decoded_pcm[-1] - decoded_pcm[0])))
    if float(final["input_tp"]) > -1.8 or seam_delta > .005:
        raise RuntimeError("Decoded true peak or seam exceeds tolerance: " + name)
    peak = float(np.max(np.abs(decoded_pcm)))
    internal_delta = float(np.max(np.abs(np.diff(decoded_pcm, axis=0))))
    provenance = {"title":source["title"], "asset":name, "id":identifier, "version":version, "role":source["role"], "arrangement":arrangement,
                  "license":"Distribution only together with Bunkercrew", "engine":"Bunkercrew Tessel / Audiote native synthesizer",
                  "source":"native/bunkercrew_audio/third_party/tessel/SOURCE.json", "generator":"tools/generate_rave_music.py",
                  "native_generator":"tools/generate_rave_music.gd", "composition":"Original authored minimal-techno score; carried eight-note motif, rounded combat hook, short offbeat sub and phrase relief",
                  "form":source.get("form", []),
                  "bpm":float(source["bpm"]), "bars":32, "seconds":target / RATE, "rate":RATE, "native_rate":source_rate,
                  "seed":source["seed"], "native_settings":source["settings"], "native_events":source["events"],
                  "markers_method":"Actual kick track-zero and offbeat bass track-eight events extracted from TesselStream.poll_events(), resampled with PCM",
                  "finishing":"DC removal, 2 ms circular seam bridge and linear gain; calm uses the combat pair trim to preserve native stage dynamics; no beat offset or overlap",
                  "gain_db":round(gain_db, 6), "mastering_reference":"combat_pair" if shared_gain_db is not None else "integrated_target", "measurements":{"decoded_frames":target,"integrated_lufs":float(final["input_i"]),
                      "true_peak_dbtp":float(final["input_tp"]),"loudness_range_lu":float(final["input_lra"]),
                      "rms":float(np.sqrt(np.mean(decoded_pcm.astype(np.float64) ** 2))),"peak":peak,"loop_sample_delta":seam_delta,
                      "maximum_internal_sample_delta":internal_delta,"seam_ratio_to_maximum_internal_delta":seam_delta / max(internal_delta, 1e-9)},
                  "sha256":hashlib.sha256(asset.read_bytes()).hexdigest(),"bytes":asset.stat().st_size, **markers(source)}
    asset.with_suffix(".source.json").write_text(json.dumps(provenance, indent=2) + "\n")
    asset.with_suffix(".LICENSE.txt").write_text("Original Bunkercrew composition, generated with the Audiote / Tessel engine.\n"
                                               "Distribution permitted only together with Bunkercrew, under the permission granted for Audiote.\n"
                                               "No third-party music recordings or samples are included.\n")
    print(f"RAVE MASTER {identifier} {arrangement}: {provenance['bpm']:g} BPM, {target} frames, {final['input_i']} LUFS, {final['input_tp']} dBTP, seam {seam_delta:.7f}", flush=True)
    return provenance


def write_catalog(provenance: list[dict]) -> None:
    main = [item for item in provenance if item["arrangement"] == "combat"]
    records = {item["id"]:{key:item.get(key, []) if key == "form" else item[key] for key in ["title","asset","version","role","form","bpm","seconds","gain_db","kick_samples","kick_strengths","secondary_samples","secondary_strengths"]} for item in main}
    text = "extends RefCounted\n## Generated from measured original native scores; runtime never reads source JSON.\nconst TRACKS := " + json.dumps(records, ensure_ascii=False, separators=(",", ":")) + "\n"
    (ROOT / "scripts/rave_music_measurements.gd").write_text(text)


def gallery(provenance: list[dict]) -> None:
    main = [item for item in provenance if item["arrangement"] == "combat"]
    calm = {item["id"]:item for item in provenance if item["arrangement"] == "calm"}
    cards = []
    original = json.loads((ROOT / "assets/audio/menu_rave_v1.source.json").read_text())
    for item in [original, *main]:
        title = escape(item["title"])
        path = "../../assets/audio/" + item["asset"]
        measurement = item["measurements"]
        role = "Hauptmenü" if item.get("role", "menu") == "menu" else "Schauplatz"
        quieter = calm.get(item.get("id", ""))
        alternate = "" if quieter is None else '<p>Ruhige Bauphase</p><audio controls preload="none" src="../../assets/audio/' + quieter["asset"] + '"></audio>'
        cards.append(f'<article><h2>{title}</h2><p>{role} · {item["bpm"]:g} BPM · 32 Takte · {item["seconds"]:.3f} s</p><audio controls preload="none" src="{path}"></audio>{alternate}<small>{measurement["integrated_lufs"]:.2f} LUFS · {measurement["true_peak_dbtp"]:.2f} dBTP · geprüfter Loop</small></article>')
    html = '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Bunkercrew · Nachtschicht Musikbibliothek</title><style>body{margin:24px;background:#111a1c;color:#e0decb;font:16px system-ui}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:18px}article{padding:22px;border:1px solid #46534b;background:#1b2421}h1{font-size:26px}h2{font-size:19px;color:#e1bd70}p{color:#b8b9ad;line-height:1.55}audio{width:100%}small{display:block;margin-top:16px;color:#a6b5a4}a{color:#ddbd76}</style><h1>Bunkercrew · Nachtschicht &amp; neue Musikfassungen</h1><p>Eigene Minimal-Techno-Kompositionen mit ruhigen Bauphasen und kräftigen Kampfgrooves. Im Spiel passt die native Musik ihre vier Intensitätsstufen an die Wellen an. Im Hauptmenü folgen nach gespielten Runden Nachtschicht, Kernimpuls, Nachtstrom und Schichtwechsel aufeinander. Nur zusammen mit Bunkercrew verteilen.</p><main>' + "".join(cards) + '</main><script>document.querySelectorAll("audio").forEach(a=>a.addEventListener("play",()=>document.querySelectorAll("audio").forEach(b=>{if(b!==a)b.pause()})))</script></html>'
    (OUTPUT / "listening.html").write_text(html)
    (OUTPUT / "tracks.json").write_text(json.dumps({"companion_tracks":len(main),"refreshed_world_scores":sum(item["role"] == "world" and item["version"] == 2 for item in main),"new_menu_scores":sum(item["role"] == "menu" and item["version"] == 2 for item in main),"refreshed_compositions":sum(item["version"] == 2 for item in main),"newly_generated_arrangements":sum(item["version"] == 2 for item in provenance),"recorded_arrangements":len(provenance),"original_menu_sha256":original["sha256"],"tracks":provenance}, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-native", action="store_true")
    parser.add_argument("--refresh", action="store_true", help="Render version-two scores while retaining the existing menu recordings")
    parser.add_argument("--only", help="Render and master only this profile, preserving all existing recordings")
    arguments = parser.parse_args()
    if not arguments.skip_native:
        command = ["godot", "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "tools/generate_rave_music.gd", "--", "--no-profile-save", "--no-upnp"]
        if arguments.only: command.append("--only=" + arguments.only)
        if arguments.refresh: command.append("--refresh")
        subprocess.run(command, check=True)
    sources = sorted(SOURCE.glob("*.json"), key=lambda path:(path.stem.split("-")[0], 0 if path.stem.endswith("-combat") else 1))
    known = set()
    provenance = []
    combat_gains = {}
    for path in sources:
        source = json.loads(path.read_text())
        if arguments.only and source["id"] != arguments.only: continue
        if arguments.refresh and int(source.get("version", 1)) < 2: continue
        shared_gain = combat_gains.get(source["id"]) if source["arrangement"] == "calm" else None
        if source["arrangement"] == "calm" and shared_gain is None:
            companion = ROOT / "assets/audio" / source["asset"].replace("_calm.ogg", "_combat.source.json")
            shared_gain = float(json.loads(companion.read_text())["gain_db"])
        item = finish(path, shared_gain)
        if source["arrangement"] == "combat": combat_gains[source["id"]] = item["gain_db"]
        provenance.append(item)
        known.add((source["id"], source["arrangement"]))
    # Preserved masters are loaded from provenance, never recomposed or rewritten.
    # This includes the user's three favored original menu recordings.
    existing = sorted((ROOT / "assets/audio").glob("*rave_*.source.json"))
    candidates = {}
    for path in existing:
        item = json.loads(path.read_text())
        if "id" not in item: continue
        key = (item["id"], item["arrangement"])
        if key in known: continue
        if key not in candidates or int(item["version"]) > int(candidates[key]["version"]): candidates[key] = item
    for key, item in candidates.items():
        asset = ROOT / "assets/audio" / item["asset"]
        if hashlib.sha256(asset.read_bytes()).hexdigest() != item["sha256"]:
            raise RuntimeError("An existing recording differs from its provenance: " + item["asset"])
        provenance.append(item)
    if len(provenance) != 21 or len({item["id"] for item in provenance}) != 12:
        raise RuntimeError("Expected twelve companion scores and twenty-one recorded arrangements")
    provenance.sort(key=lambda item:(item["id"], item["arrangement"]))
    write_catalog(provenance)
    gallery(provenance)


if __name__ == "__main__":
    main()
