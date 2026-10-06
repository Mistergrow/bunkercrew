#!/usr/bin/env python3
"""Decode, reproduce and validate new aviation, production and medical sound banks."""
from pathlib import Path
import hashlib
import html
import itertools
import json
import sys
import wave
import fnmatch

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/audio-air-review/assets"
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / "tools"))
import generate_aircraft_audio as aircraft
import generate_machinery_medical_audio as machinery
from audit_audio_assets import literal_constant, export_filters, runtime_banks

checks = []


def check(value, description):
    checks.append({"passed": bool(value), "description": description})
    if not value:
        print("FAIL " + description)


def main():
    manifests = [json.loads((ROOT / "assets/audio" / name).read_text()) for name in
                 ["aircraft_v1_sources.json", "machinery_medical_v1_sources.json"]]
    definitions = {**manifests[0]["assets"], **manifests[1]["assets"]}
    protected = {}
    for manifest in manifests:
        for path, digest in manifest["preserved_sha256"].items():
            check(path not in protected or protected[path] == digest, path + ": agreeing preservation declarations")
            protected[path] = digest
    for path, digest in protected.items():
        check(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest,
              path + ": existing sound bytes remain intact")
    measurements = {}
    signals = {}
    for filename, metadata in definitions.items():
        path = ROOT / "assets/audio" / filename
        with wave.open(str(path), "rb") as source:
            rate, channels, width = source.getframerate(), source.getnchannels(), source.getsampwidth()
            pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
        signal = pcm.astype(np.float64) / 32768
        looped = metadata["loop"]
        role = metadata["role"]
        generator = aircraft if filename in manifests[0]["assets"] else machinery
        if looped:
            expected = aircraft.engine(role) if generator is aircraft else machinery.loop(role)
        else:
            variant = int(path.stem.rsplit("_", 1)[1]) - 1
            expected = aircraft.effect(role, variant) if generator is aircraft else machinery.treatment(role, variant)
        reconstructed_peak = float(np.abs(resample_poly(signal, 4, 1)).max())
        rms = float(np.sqrt(np.mean(signal**2)))
        step95 = float(np.percentile(np.abs(np.diff(signal)), 95))
        block = signal[:len(signal) // 2400 * 2400].reshape(-1, 2400)
        spectral = np.abs(np.fft.rfft(signal))**2
        bins = np.fft.rfftfreq(len(signal), 1 / rate)
        item = {"sample_rate": rate, "channels": channels, "seconds": len(signal) / rate,
                "peak_dbfs": float(20 * np.log10(np.abs(signal).max())),
                "rms_dbfs": float(20 * np.log10(rms)), "dc": float(signal.mean()),
                "reconstructed_peak_4x": reconstructed_peak,
                "edge_step": float(abs(signal[-1] - signal[0])),
                "edge_vs_step95": float(abs(signal[-1] - signal[0]) / max(step95, 1e-9)),
                "lowest50ms_rms": float(np.sqrt(np.mean(block**2, axis=1)).min()),
                "energy_above_8khz": float(spectral[bins > 8000].sum() / spectral.sum()),
                "loop": looped, "role": role}
        measurements[filename] = item
        signals[filename] = signal
        check(rate == 48000 and channels == 1 and width == 2, filename + ": mono 48kHz PCM16 for real spatial pan")
        check(np.isfinite(signal).all() and .004 < rms < .31, filename + ": finite audible bounded recording")
        check(np.abs(signal).max() < .81 and reconstructed_peak < .89, filename + ": sample and reconstructed peak headroom")
        check(abs(signal.mean()) < .00015, filename + ": negligible DC")
        check(np.array_equal(pcm, np.round(expected * 32767).astype("<i2")), filename + ": deterministic declared PCM reproduction")
        check(hashlib.sha256(path.read_bytes()).hexdigest() == metadata["sha256"], filename + ": source metadata hash matches shipping bytes")
        check(json.loads(path.with_suffix(".source.json").read_text()) == metadata, filename + ": adjacent and bank provenance agree")
        check(hashlib.sha256((ROOT / metadata["generator"]).read_bytes()).hexdigest() == metadata["generator_sha256"], filename + ": exact generator provenance")
        check(path.with_suffix(".LICENSE.txt").read_text().strip() == aircraft.LICENSE, filename + ": distribution only together with Bunkercrew")
        if looped:
            check(len(signal) == 48000 * 8 and item["edge_step"] < .001 and item["edge_vs_step95"] < .25,
                  filename + ": eight-second circular loop with quiet contiguous boundary")
            check(item["lowest50ms_rms"] > .015, filename + ": no recurring faded or silent engine gap")
        else:
            check(pcm[0] == 0 and pcm[-1] == 0 and .15 <= len(signal) / rate <= 1.4,
                  filename + ": finite contact with silent event edges")
        check(item["energy_above_8khz"] < .015, filename + ": restrained high-frequency energy")
    distinct = {}
    for manifest in manifests:
        for role in {metadata["role"] for metadata in manifest["assets"].values()}:
            names = [name for name, metadata in manifest["assets"].items() if metadata["role"] == role]
            for first, second in itertools.combinations(names, 2):
                correlation = float(np.corrcoef(signals[first], signals[second])[0, 1])
                distinct[first + "/" + second] = correlation
                check(abs(correlation) < .985, first + "/" + second + ": distinct contact variants")
    engines = [name for name, data in manifests[0]["assets"].items() if data["loop"]]
    for first, second in itertools.combinations(engines, 2):
        correlation = float(np.corrcoef(signals[first], signals[second])[0, 1])
        distinct[first + "/" + second] = correlation
        check(abs(correlation) < .90, first + "/" + second + ": distinct mechanical family waveform")
    profile_catalog = ROOT / "scripts/aircraft_audio_catalog.gd"
    profiles = literal_constant(profile_catalog, "PROFILES")
    propulsion = literal_constant(profile_catalog, "PROPULSION")
    gameplay = literal_constant(ROOT / "scripts/air_enemy_catalog.gd", "INTRO_WAVES")
    variants = literal_constant(ROOT / "scripts/audio_catalog.gd", "VARIANT_COUNTS")
    check(len(profiles) == 12 and set(profiles) == set(gameplay), "Every current aircraft has its own valid propulsion/weapon audio profile")
    for kind, profile in profiles.items():
        check(profile["family"] in propulsion and .70 <= profile["pitch"] <= 1.3 and abs(profile["gain_db"]) <= 3,
              kind + ": bounded mechanical audio profile")
        for key in ["fire_key", "charge_key", "lock_key"]:
            if key in profile:
                check(profile[key] in variants and all(f"{profile[key]}_{index:02d}.wav" in definitions
                      for index in range(1, variants[profile[key]] + 1)), kind + ": complete " + key + " source bank")
    production = literal_constant(ROOT / "scripts/machinery_audio_catalog.gd", "LOOPS")
    check(set(production) == {"mixer", "furnace"} and all(Path(spec["stream_path"].removeprefix("res://")).name in definitions for spec in production.values()),
          "Both working production machines have dedicated sources")
    check(len(definitions) == 34 and len(manifests[0]["preserved_sha256"]) >= 685,
          "Thirty-four new sources and a complete protected baseline")
    bank, _ = runtime_banks()
    all_audio = [str(path.relative_to(ROOT)) for path in (ROOT / "assets/audio").rglob("*") if path.suffix in [".wav", ".ogg"]]
    retired_patterns = ["assets/audio/music_rave_*_v1_*.ogg", "assets/audio/convoy_*_v1.wav"]
    retired = [path for path in all_audio if any(fnmatch.fnmatchcase(path, pattern) for pattern in retired_patterns)]
    check(len(retired) == 24 and not set(retired) & set(bank), "Exactly 24 old score/vehicle sources have no current bank reference")
    for preset, excluded in export_filters().items():
        exported = {path for path in all_audio if not any(fnmatch.fnmatchcase(path, pattern) for pattern in excluded)}
        check(all(pattern in excluded for pattern in retired_patterns), preset + ": exact retired-source export patterns")
        check(exported == set(bank) and len(exported) == 522, preset + ": exports every current source and no retired/raw recordings")
        check("assets/audio/menu_rave_v1.ogg" in exported and "assets/audio/air_raid_flyover_v1.wav" in exported,
              preset + ": original menu and air-intro fallbacks preserved")
    report = {"checks": len(checks), "passed": sum(item["passed"] for item in checks),
              "failed": sum(not item["passed"] for item in checks), "new_recordings": len(definitions),
              "protected_recordings": len(protected), "results": checks,
              "measurements": measurements, "correlations": distinct,
              "method_limit": "Decoded PCM and 4x reconstruction proxy; actual engine/spatial/default50 mix verification is recorded separately. Listening judgment remains available in the gallery, not inferred from these numeric checks."}
    (OUT / "new-bank-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    blocks = []
    names = {"rotor":"Rotor", "propeller":"Propeller", "tiltrotor":"Kipprotor", "jet":"Strahltriebwerk", "airship":"Luftschiff", "vtol":"Schwerer Schwebeflug", "mixer":"Betonmischer", "furnace":"Ofen", "medical_heal":"Behandlung", "medical_revive":"Wiederaufstehen"}
    for role in list(aircraft.ENGINES) + list(aircraft.EFFECTS) + list(machinery.LOOPS) + list(machinery.EFFECTS):
        entries = []
        for name, data in definitions.items():
            if data["role"] != role:
                continue
            entries.append('<li><span>' + html.escape(name) + '</span><audio controls preload="none" src="../../../assets/audio/' + html.escape(name) + '"></audio><small>' + html.escape(data["layers"]) + '</small></li>')
        blocks.append('<section><h2>' + html.escape(names.get(role, role)) + '</h2><ul>' + "".join(entries) + '</ul></section>')
    (OUT / "index.html").write_text('<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Bunkercrew · Klangprüfung</title><style>body{max-width:1050px;margin:36px auto;padding:0 24px;background:#101715;color:#d6d1bd;font:16px system-ui;line-height:1.5}h1{font-size:28px}h2{font-size:21px;margin:40px 0 14px}a{color:#e0b86b}ul{padding:0;list-style:none}li{padding:12px 0;border-bottom:1px solid #2a3831}audio{display:block;width:min(100%,660px);margin:10px 0}small{display:block;color:#a7ac9b}p{max-width:80ch}</style>'
        '<h1>Neue Flugzeug- und Bunkergeräusche</h1><p>34 originale Monoaufnahmen: sechs Flugmotoren, 22 Waffen-/Warn-/Absturzvarianten, zwei Maschinenloops und vier medizinische Kontakte. Die Schleifen können im Browser mehrfach abgespielt werden; die eigentliche Spielmischung hat räumliche Entfernung und unveränderte 50-%-Regler.</p>'
        '<p><a href="new-bank-verification.json">PCM, Quellen und Altdatei-Schutz</a> · <a href="sound-manifest.json">Vollständiges Audioinventar</a> · <a href="../index.html#listen">Aufnahmen aus der echten Spielmischung</a></p>'
        + "".join(blocks) + '</html>')
    print(f"AIRCRAFT/MACHINERY AUDIO ASSETS: {report['passed']}/{report['checks']} checks passed; {len(definitions)} new, {len(protected)} preserved")
    return int(report["failed"] > 0)


if __name__ == "__main__":
    raise SystemExit(main())
