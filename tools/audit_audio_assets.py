#!/usr/bin/env python3
"""Inventory and measure every repository WAV/OGG without changing recordings.

Source, runtime-bank and export coverage are separate. FFmpeg ebur128 supplies
integrated loudness/true peak; short transients also retain RMS measurements.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
import fnmatch
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/audio-air-review/assets"


def literal_constant(path: Path, name: str):
    text = path.read_text()
    found = re.search(r"const\s+" + re.escape(name) + r"(?:\s*:\s*(?![=])[^=\n]+)?\s*(?::=|=)\s*([\[{])", text)
    if not found:
        return {}
    start = found.start(1)
    depth = 0
    quoted = False
    escaped = False
    for end in range(start, len(text)):
        char = text[end]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char in "[{":
            depth += 1
        elif char in "}]":
            depth -= 1
            if depth == 0:
                return json.loads(re.sub(r",\s*([}\]])", r"\1", text[start:end + 1]))
    raise ValueError(f"Unterminated {path}:{name}")


def db(value: float) -> float:
    return round(20 * math.log10(max(float(value), 1e-12)), 4)


def scalar_constant(path: Path, name: str) -> float:
    match = re.search(r"const\s+" + re.escape(name) + r"\s*(?::=|=)\s*([-+]?\d+(?:\.\d+)?)", path.read_text())
    if not match:
        raise ValueError(f"Missing numeric constant {path}:{name}")
    return float(match.group(1))


def export_filters() -> dict[str, list[str]]:
    presets = {}
    text = (ROOT / "export_presets.cfg").read_text()
    for section in re.split(r"\[preset\.\d+\]\n", text)[1:]:
        name = re.search(r'^name="([^"]+)"', section, re.M)
        excludes = re.search(r'^exclude_filter="([^"]*)"', section, re.M)
        if name:
            presets[name.group(1)] = excludes.group(1).split(",") if excludes else []
    return presets


def runtime_banks() -> tuple[dict[str, dict], dict[str, float]]:
    catalog = ROOT / "scripts/audio_catalog.gd"
    counts = literal_constant(catalog, "VARIANT_COUNTS")
    levels = literal_constant(catalog, "LEVEL_DB")
    gains = literal_constant(catalog, "SHOT_HIT_KINDS")
    bank = {}
    triggers = effect_triggers(counts, literal_constant(catalog, "ALIASES"))
    for kind, count in counts.items():
        for variant in range(1, count + 1):
            bank[f"assets/audio/{kind}_{variant:02}.wav"] = {
                "role": "gameplay_effect", "kind": kind,
                "source_level_db": float(levels.get(kind, -16)) + (0.4237859813987618 if kind in gains else 0),
                "bus": "SFX", "users": ["scripts/audio.gd", "scripts/audio_catalog.gd"],
                "trigger_evidence": triggers.get(kind, []),
                "availability": "Canonical bank entry; actual triggers are documented separately, including dynamic dispatch.",
            }
    for family in literal_constant(ROOT / "scripts/enemy_audio_catalog.gd", "FAMILIES"):
        for surface in ["dry", "metal", "ice", "water"]:
            for variant in range(1, 6):
                bank[f"assets/audio/enemy_step_{family}_{surface}_{variant:02}.wav"] = {
                    "role": "actor_contact", "kind": family,
                    "source_level_db": -18, "player_contact_level_db": -11 if family.startswith("boot_") else None,
                    "bus": "SFX", "users": ["scripts/movement_audio.gd"],
                }
    for kind in ["dry", "metal", "water", "ice", "heavy"]:
        for variant in range(1, 4):
            bank[f"assets/audio/step_{kind}_{variant:02}.wav"] = {
                "role": "actor_contact_fallback", "kind": kind, "source_level_db": -13,
                "bus": "SFX", "users": ["scripts/movement_audio.gd"],
            }
    for branch in ["base", "weapons", "crew", "vehicle"]:
        for variant in range(1, 4):
            bank[f"assets/audio/tech_upgrade_{branch}_{variant:02}.wav"] = {
                "role": "research_confirmation", "kind": branch, "source_level_db": -7,
                "bus": "SFX", "users": ["scripts/upgrade_audio.gd"],
            }
    sets = literal_constant(catalog, "MUSIC_SETS")
    for score, stems in sets.items():
        for stem, filename in stems.items():
            bank["assets/audio/" + filename] = {
                "role": "recorded_score", "kind": score + ":" + stem,
                "source_level_db": 0 if score not in ["base", "foundry", "tidal", "frost"] else -7,
                "bus": "Music", "loop": True, "users": ["scripts/audio.gd"],
            }
    for filename in ["menu_rave_v1.ogg", "menu_rave_nachtstrom_v1.ogg", "menu_rave_schichtwechsel_v1.ogg", "menu_rave_kernimpuls_v2.ogg"]:
        bank["assets/audio/" + filename] = {"role": "menu_score", "source_level_db": 0, "bus": "Music", "loop": True, "users": ["scripts/menu_music_catalog.gd"]}
    effects = literal_constant(ROOT / "scripts/convoy_audio.gd", "EFFECTS")
    for kind, spec in effects.items():
        bank[f"assets/audio/convoy_{kind}_v2.wav"] = {"role": "convoy_foley", "kind": kind, "source_level_db": spec["db"], "bus": "SFX", "users": ["scripts/convoy_audio.gd"]}
    for kind, level in {"idle": -28, "torque": -25, "road": -29, "clatter": -33}.items():
        bank[f"assets/audio/convoy_{kind}_v2.wav"] = {"role": "convoy_loop", "kind": kind, "source_level_db": level, "bus": "SFX", "loop": True, "users": ["scripts/convoy_audio.gd"]}
    bank["assets/audio/ambience_wind.ogg"] = {"role": "ambient_loop", "source_level_db": -25, "bus": "SFX", "loop": True, "users": ["scripts/movement_audio.gd"], "gain_note": "Weather- and shelter-dependent, -25dB is an illustrative exposed steady level."}
    bank["assets/audio/air_raid_flyover_v1.wav"] = {"role": "intro_loop", "source_level_db": -9, "bus": "SFX", "loop": True, "users": ["scripts/air_raid_intro_panel.gd"], "gain_note": "Maximum approach envelope; another -4dB while dialogue is playing."}
    for locale, directory in [("de", ROOT / "assets/audio/story_voices_v2"), ("en", ROOT / "assets/audio/story_voices_v2/en")]:
        lines = json.loads((directory / "lines.json").read_text())["lines"]
        for line in lines:
            filename = line["file"]
            bank[str((directory / filename).relative_to(ROOT))] = {"role": "recorded_dialogue", "kind": locale + ":" + line["id"], "source_level_db": 0, "bus": "Voice", "users": ["scripts/story_dialogue_catalog.gd"], "gain_note": "Dialogue-player gain/crossfade applies in context; dry unity value is a source estimate."}
    aircraft = ROOT / "scripts/aircraft_audio_catalog.gd"
    if aircraft.exists():
        profiles = literal_constant(aircraft, "PROFILES")
        for family, spec in literal_constant(aircraft, "PROPULSION").items():
            bank[spec["stream_path"].removeprefix("res://")] = {"role": "aircraft_loop", "kind": family, "source_level_db": spec["level_db"], "bus": "SFX", "loop": True, "users": ["scripts/aircraft_audio.gd", "scripts/aircraft_audio_catalog.gd"],
                "aircraft_profiles": {kind: profile for kind, profile in profiles.items() if profile["family"] == family},
                "gain_note": "Family base at one source: each aircraft adds its profile gain, moving load adds0..3dB, and1..4 audible motors receive energy-normalized crowd gain0..-6.02dB. Actual attenuation/room filtering applies separately."}
    machinery = ROOT / "scripts/machinery_audio_catalog.gd"
    if machinery.exists():
        for kind, spec in literal_constant(machinery, "LOOPS").items():
            bank[spec["stream_path"].removeprefix("res://")] = {"role": "production_loop", "kind": kind, "source_level_db": spec["level_db"], "bus": "SFX", "loop": True, "users": ["scripts/machinery_audio.gd", "scripts/machinery_audio_catalog.gd"],
                "trigger_evidence": ["Local bounded pool observes actual working state in own-world production stations; no duplicated network sound events."]}
    output_gain = re.search(r"bus/0/volume_db\s*=\s*([-+]?\d+(?:\.\d+)?)", (ROOT / "default_bus_layout.tres").read_text())
    return bank, {"Music": scalar_constant(ROOT / "scripts/audio.gd", "MUSIC_MIX_TRIM_DB"),
                  "Voice": scalar_constant(ROOT / "scripts/audio.gd", "VOICE_MIX_TRIM_DB"), "SFX": 0.0,
                  "MasterPreGain": float(output_gain.group(1)) if output_gain else 0.0}


def effect_triggers(counts: dict, aliases: dict) -> dict:
    """Literal source evidence plus reviewed finite dynamic sound dispatches."""
    known = set(counts) | set(aliases)
    result = {}
    for path in sorted((ROOT / "scripts").glob("*.gd")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            endpoint = re.search(r"(?:\.|^|\s)(?:sound(?:_at)?|play_sound(?:_at)?)\(", line)
            spatial = "emit(" in line and ("spatial_sound.gd" in line or re.search(r"\bSound\.emit\(", line))
            if not endpoint and not spatial:
                continue
            for candidate in re.findall(r'"([^"]+)"', line):
                if candidate not in known:
                    continue
                key = aliases.get(candidate, candidate)
                result.setdefault(key, []).append(f"{path.relative_to(ROOT)}:{number}: {candidate}")
    for family, path in [("rifle", "worker_weapon.gd"), ("shotgun", "worker_weapon.gd"), ("arc", "worker_weapon.gd"),
                         ("cannon", "turret.gd"), ("flak", "flak_turret.gd")]:
        for phase in ["open", "load", "close"]:
            result.setdefault(f"reload_{family}_{phase}", []).append(f"scripts/{path}: _reload_sound dynamic family/phase dispatch")
    for kind in ["hit", "impact_metal", "impact_stone", "impact_wood", "impact_core"]:
        result.setdefault(kind, []).append("scripts/impact_burst.gd: sound_for/contact dispatches from the real impacted material")
    for kind in ["ricochet_metal", "ricochet_stone"]:
        if kind in counts:
            result.setdefault(kind, []).append("scripts/impact_burst.gd: ricochet_for/contact dispatches ballistic glancing contacts from the impacted hard material")
    for profile in literal_constant(ROOT / "scripts/aircraft_audio_catalog.gd", "PROFILES").values():
        for key in ["fire_key", "charge_key", "lock_key"]:
            if key in profile:
                result.setdefault(profile[key], []).append("scripts/air_machine.gd: _fire_at/_warn consumes AircraftAudioCatalog profile keys")
    return {kind: sorted(set(entries)) for kind, entries in result.items()}


def loudness(path: Path, duration: float) -> dict:
    process = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-filter_complex", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    if process.returncode:
        raise RuntimeError(process.stderr[-1000:])
    text = process.stderr.rsplit("Summary:", 1)[-1]
    integrated = re.search(r"I:\s*([-\d.]+) LUFS", text)
    true_peak = re.search(r"Peak:\s*([-\d.]+) dBFS", text)
    return {"integrated_lufs": float(integrated.group(1)) if integrated and duration >= .4 and float(integrated.group(1)) > -70 else None,
            "ffmpeg_true_peak_dbfs": float(true_peak.group(1)) if true_peak else None,
            "lufs_note": "Below 400ms, gated integrated loudness is not meaningful; use active-window RMS." if duration < .4 else "FFmpeg ebur128, full decoded duration."}


def provenance(path: Path, metadata: list[tuple[Path, str]]) -> dict:
    adjacent = path.with_suffix(".source.json")
    refs = [str(meta.relative_to(ROOT)) for meta, text in metadata if path.name in text and not ("story_voices" in str(meta) and meta.parent != path.parent)]
    if adjacent.exists():
        refs.insert(0, str(adjacent.relative_to(ROOT)))
    if "source_recordings" in str(path):
        refs += [str(p.relative_to(ROOT)) for p in path.parent.glob("sources.json")]
        category = "Recorded CC0 source; derivative processing is documented separately."
    elif "story_voices" in str(path):
        refs += [str(p.relative_to(ROOT)) for p in path.parent.glob("source.json")]
        category = "Synthetic fictional speaker; source model, conditioning, dialogue and mastering recorded in bank metadata."
    else:
        category = "Original game sound design; some foley banks contain attributed CC0 recording layers."
        if not refs:
            stem = re.sub(r"_\d\d$", "", path.stem)
            for meta, text in metadata:
                if meta.name.endswith("sources.json") and ('"' + stem + '"') in text:
                    refs.append(str(meta.relative_to(ROOT)))
            match = re.fullmatch(r"music_(foundry|tidal|frost)_(calm|combat)", path.stem)
            if match:
                source = path.parent / "sources.json"
                if match.group(1) in json.loads(source.read_text()).get("music", {}).get("sets", {}):
                    refs.append(str(source.relative_to(ROOT)))
    licenses = [str(p.relative_to(ROOT)) for p in [path.with_suffix(".LICENSE.txt"), path.parent / "LICENSE.txt", path.parent / "license.txt", path.parent / "License.txt"] if p.exists()]
    declared = {}
    for meta, text in metadata:
        if str(meta.relative_to(ROOT)) not in refs:
            continue
        data = json.loads(text)
        collect_license_fields(data, declared)
    return {"metadata": sorted(set(refs)), "licenses": licenses, "origin": category,
            "declared_license_fields": {key: sorted(values) for key, values in declared.items()},
            "metadata_coverage": bool(refs), "license_note": "Existing CC0 rights remain intact; model license describes the generation model, not ownership of a fictional speaker. New original aircraft/machinery/treatment assets restrict distribution to Bunkercrew."}


def collect_license_fields(data, output: dict) -> None:
    if isinstance(data, dict):
        for key, value in data.items():
            if key in ["license", "source_license", "model_license"] and isinstance(value, str):
                output.setdefault(key, set()).add(value)
            elif isinstance(value, (dict, list)):
                collect_license_fields(value, output)
    elif isinstance(data, list):
        for entry in data:
            collect_license_fields(entry, output)


def measure(path: Path, banks: dict, presets: dict, metadata: list, trims: dict, cached: dict | None = None) -> dict:
    relative = str(path.relative_to(ROOT))
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if cached and cached.get("sha256") == digest and cached.get("path") == relative:
        result = dict(cached)
        result["usage"] = banks.get(relative, {"role": "source_recording" if "source_recordings/" in relative else "excluded_authoring_reference" if "/anchors/" in relative else "retired_recording"})
        result["exported"] = {name: not any(fnmatch.fnmatchcase(relative, pattern) for pattern in excluded) for name, excluded in presets.items()}
        result["provenance"] = provenance(path, metadata)
        result.pop("default50_dry_estimate", None)
        add_mix_estimate(result, trims)
        result["technical_measurement_reused_after_exact_sha256_match"] = True
        return result
    info = sf.info(path)
    signal, rate = sf.read(path, dtype="float64", always_2d=True)
    if not len(signal) or not np.isfinite(signal).all():
        raise ValueError("Empty or nonfinite recording: " + relative)
    peak = float(np.abs(signal).max())
    rms = float(np.sqrt(np.mean(signal**2)))
    window = max(1, round(rate * .020))
    blocks = signal[:len(signal) // window * window].reshape(-1, window, signal.shape[1])
    envelopes = np.sqrt(np.mean(blocks**2, axis=(1, 2))) if len(blocks) else np.array([rms])
    active = envelopes[envelopes > 10**(-55 / 20)]
    voiced = np.max(np.abs(signal), axis=1) > 4 / 32768
    indices = np.flatnonzero(voiced)
    step = np.abs(np.diff(signal, axis=0))
    seam = float(np.max(np.abs(signal[-1] - signal[0])))
    step95 = float(np.percentile(step, 95)) if len(step) else 0
    usage = banks.get(relative, {"role": "source_recording" if "source_recordings/" in relative else "excluded_authoring_reference" if "/anchors/" in relative else "retired_recording"})
    exported = {name: not any(fnmatch.fnmatchcase(relative, pattern) for pattern in excluded) for name, excluded in presets.items()}
    result = {"path": relative, "sha256": digest, "bytes": path.stat().st_size,
              "format": info.format, "subtype": info.subtype, "rate": rate, "channels": signal.shape[1], "frames": len(signal), "seconds": round(len(signal) / rate, 6),
              "peak_dbfs": db(peak), "oversampled4x_peak_dbfs": db(float(np.abs(resample_poly(signal, 4, 1, axis=0)).max())),
              "rms_dbfs": db(rms), "active20ms_rms_dbfs": db(float(np.sqrt(np.mean(active**2)))) if len(active) else None,
              "dc_abs_max": round(float(np.max(np.abs(signal.mean(axis=0)))), 9), "crest_db": round(db(peak) - db(rms), 4),
              "sample_clipping_count": int(np.count_nonzero(np.abs(signal) >= 32760 / 32768)), "silent20ms_fraction": round(float(np.mean(envelopes < 1e-3)), 6),
              "leading_below_minus78db_ms": round(int(indices[0]) * 1000 / rate, 4) if len(indices) else len(signal) * 1000 / rate,
              "trailing_below_minus78db_ms": round((len(signal) - int(indices[-1]) - 1) * 1000 / rate, 4) if len(indices) else len(signal) * 1000 / rate,
              "edge_step_dbfs": db(seam), "edge_vs_normal_step95": round(seam / max(step95, 1e-10), 4),
              "usage": usage, "exported": exported, "provenance": provenance(path, metadata)}
    result.update(loudness(path, len(signal) / rate))
    add_mix_estimate(result, trims)
    result["flags"] = (["decoded_sample_clipping"] if result["sample_clipping_count"] else [])
    if peak < 1e-5:
        result["flags"].append("silent_file")
    if usage.get("loop") and seam > .015 and seam > step95 * 4:
        result["flags"].append("discontinuous_loop_edge")
    if result["dc_abs_max"] > .002:
        result["flags"].append("dc_above_0.002")
    return result


def add_mix_estimate(result: dict, trims: dict) -> None:
    usage = result["usage"]
    if "source_level_db" not in usage:
        return
    gain = usage["source_level_db"] + trims[usage["bus"]] + 20 * math.log10(.5)
    result["default50_dry_estimate"] = {
        "source_and_bus_gain_db": round(gain, 4), "rms_dbfs": round(result["rms_dbfs"] + gain, 4),
        "peak_dbfs": round(result["peak_dbfs"] + gain, 4),
        "integrated_lufs": round(result["integrated_lufs"] + gain, 2) if result["integrated_lufs"] is not None else None,
        "master_pre_gain_db": trims["MasterPreGain"],
        "unlimited_master_input_rms_dbfs": round(result["rms_dbfs"] + gain + trims["MasterPreGain"], 4),
        "unlimited_master_input_peak_dbfs": round(result["peak_dbfs"] + gain + trims["MasterPreGain"], 4),
        "scope": "One source at unity spatial gain, before room/occlusion and automatic ducks. Source/bus values exclude Master; separate unlimited Master-input estimates include its existing pre-gain but exclude the final limiter. Not a full gameplay mixer measurement.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--output", type=Path, default=OUT / "sound-manifest.json")
    parser.add_argument("--reuse", type=Path, help="Reuse existing full PCM/loudness measurements only after exact file SHA-256 match; refresh usage/mix/export/provenance")
    args = parser.parse_args()
    paths = sorted(p for p in (ROOT / "assets").rglob("*") if p.suffix.lower() in [".wav", ".ogg"])
    metadata = []
    for path in (ROOT / "assets/audio").rglob("*.json"):
        content = json.loads(path.read_text())
        if isinstance(content, dict):
            content.pop("preserved_sha256", None)
        metadata.append((path, json.dumps(content)))
    banks, trims = runtime_banks()
    presets = export_filters()
    cached = {item["path"]: item for item in json.loads(args.reuse.read_text()).get("files", [])} if args.reuse else {}
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        results = list(executor.map(lambda p: measure(p, banks, presets, metadata, trims, cached.get(str(p.relative_to(ROOT)))), paths))
    missing = sorted(set(banks) - {str(p.relative_to(ROOT)) for p in paths})
    summary = {"files": len(results), "bytes": sum(item["bytes"] for item in results), "roles": dict(Counter(item["usage"]["role"] for item in results)),
               "exported": {name: sum(item["exported"][name] for item in results) for name in presets},
               "missing_runtime_references": missing,
               "missing_metadata": [item["path"] for item in results if not item["provenance"]["metadata_coverage"]],
               "flags": dict(Counter(flag for item in results for flag in item["flags"]))}
    summary["runtime_bank_files"] = sum(item["path"] in banks for item in results)
    summary["active_technical_flags"] = {item["path"]: item["flags"] for item in results if item["path"] in banks and item["flags"]}
    summary["preserved_source_files"] = sum(item["usage"]["role"] == "source_recording" for item in results)
    summary["retired_files"] = sum(item["usage"]["role"] == "retired_recording" for item in results)
    summary["excluded_authoring_reference_files"] = sum(item["usage"]["role"] == "excluded_authoring_reference" for item in results)
    summary["canonical_effects_without_current_trigger_evidence"] = sorted({item["usage"]["kind"] for item in results
        if item["usage"]["role"] == "gameplay_effect" and not item["usage"].get("trigger_evidence")})
    report = {"scope": "Every assets WAV/OGG decoded and measured, including exported runtime banks, raw sources, retired recordings and excluded authoring references.",
              "method": "libsndfile decoding, sample metrics, scipy4x reconstruction proxy and full-file FFmpeg ebur128/true peak. Source estimates at exact0.5 sliders; spatial/mixed gameplay verification is separate.",
              "summary": summary, "files": results}
    report["default_mix"] = {"sliders": {"Music": .5, "SFX": .5, "Voice": .5}, "bus_trims_db": {key: value for key, value in trims.items() if key != "MasterPreGain"},
        "master_pre_gain_db": trims["MasterPreGain"], "master_ceiling_db": -1.0,
        "master_gain_order": "Runtime moves the shipped +6.0199986dB Master fader before the hard limiter, then keeps Master fader at0dB. This preserves quiet output and prevents post-ceiling amplification.",
        "runtime_capture": "artifacts/audio-air-review/runtime/complete-mix-verification.json",
        "source_estimate_limit": "Real spatial distance, shelter, source crowd limits, transient windows, music/dialogue ducking and output limiting change the combined sound; source estimates do not establish subjective quality."}
    report["source_hashes"] = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in [
        "tools/audit_audio_assets.py", "scripts/audio_catalog.gd", "scripts/aircraft_audio_catalog.gd",
        "scripts/machinery_audio_catalog.gd", "scripts/audio.gd", "scripts/movement_audio.gd",
        "scripts/convoy_audio.gd", "default_bus_layout.tres", "export_presets.cfg"]}
    if args.reuse:
        report["cached_measurements"] = {"source": str(args.reuse), "source_sha256": hashlib.sha256(args.reuse.read_bytes()).hexdigest(),
            "files": sum(bool(item.get("technical_measurement_reused_after_exact_sha256_match")) for item in results),
            "guard": "Reuse only when SHA-256 equals the current complete WAV/OGG file; dynamic usage, source gains, export and provenance are always refreshed."}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, indent=2))
    return int(bool(missing))


if __name__ == "__main__":
    raise SystemExit(main())
