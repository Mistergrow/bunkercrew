#!/usr/bin/env python3
"""Author three short, spatial-ready bullet ricochets from local CC0 foley.

The initial contacts are Kenney Impact Sounds recordings. Inharmonic glances
and air trails are original deterministic DSP, not purported recordings of
real gunfire. Requires numpy, scipy and ffmpeg. Writes only this three-file
bank, its provenance/licenses, and an optional verification report.
"""
from functools import lru_cache
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import wave

import numpy as np
from scipy.signal import butter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
SOURCE = OUT / "source_recordings/enemy_foley"
RATE = 48000
DESIGN_DATE = "2026-10-05"
REVISION = 1
ASSETS = {
    "ricochet_metal_01": {
        "material": "metal", "description": "Short steel contact with a fast, airy deflection zip.",
        "duration": .300, "peak": .56, "seed": 501039,
        "layers": [
            {"file": "impactMetal_light_002.ogg", "gain": .65, "at": .001,
             "speed": 1.54, "low": 720, "high": 8000, "decay": .040},
            {"file": "impactPlate_light_003.ogg", "gain": .14, "at": .004,
             "speed": 1.91, "low": 1400, "high": 7400, "decay": .020},
        ],
        "glance": {"at": .010, "start_hz": 4350, "end_hz": 1480, "decay": .061,
                   "pitch_decay": .037, "gain": .21, "roughness": .12},
        "air": {"at": .012, "low": 2100, "high": 7200, "decay": .039, "gain": .041},
    },
    "ricochet_metal_02": {
        "material": "metal", "description": "A longer rough, downward metallic glancing zing.",
        "duration": .460, "peak": .54, "seed": 501043,
        "layers": [
            {"file": "impactPlate_light_004.ogg", "gain": .52, "at": .001,
             "speed": 1.38, "low": 680, "high": 7700, "decay": .053},
            {"file": "impactTin_medium_001.ogg", "gain": .18, "at": .005,
             "speed": 1.67, "low": 1200, "high": 6800, "decay": .033},
        ],
        "glance": {"at": .009, "start_hz": 3620, "end_hz": 1190, "decay": .088,
                   "pitch_decay": .072, "gain": .25, "roughness": .18},
        "air": {"at": .015, "low": 1300, "high": 6000, "decay": .065, "gain": .038},
    },
    "ricochet_stone_01": {
        "material": "stone", "description": "A dry concrete chip, scattered grit and a brief deflection whistle.",
        "duration": .240, "peak": .52, "seed": 501047,
        "layers": [
            {"file": "footstep_concrete_003.ogg", "gain": .69, "at": .001,
             "speed": 2.28, "low": 850, "high": 7700, "decay": .016},
            {"file": "impactWood_light_004.ogg", "gain": .24, "at": .004,
             "speed": 2.61, "low": 1900, "high": 7500, "decay": .012},
            {"file": "footstep_concrete_001.ogg", "gain": .075, "at": .024,
             "speed": 2.46, "low": 1700, "high": 6600, "decay": .013},
        ],
        "glance": {"at": .008, "start_hz": 3280, "end_hz": 1820, "decay": .026,
                   "pitch_decay": .023, "gain": .085, "roughness": .23},
        "air": {"at": .013, "low": 2000, "high": 6900, "decay": .025, "gain": .056},
    },
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owned_names():
    return {name + suffix for name in ASSETS for suffix in (".wav", ".source.json", ".LICENSE.txt")}


def protected_audio(directory):
    """Protect earlier audio, including the input recordings, on each write."""
    return {str(path.relative_to(directory)): digest(path)
            for path in directory.rglob("*") if path.is_file()
            and path.suffix.lower() in {".wav", ".ogg", ".mp3", ".flac"}
            and str(path.relative_to(directory)) not in owned_names()}


@lru_cache(maxsize=16)
def recorded(filename, speed, low, high, decay):
    path = SOURCE / filename
    encoded = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le",
        "-ac", "1", "-ar", str(RATE), "-",
    ])
    audio = np.frombuffer(encoded, dtype="<f4").astype(np.float64)
    active = np.flatnonzero(np.abs(audio) > max(float(np.max(np.abs(audio))) * .006, .0001))
    if not len(active):
        raise ValueError(f"Silent source contact: {path}")
    # Preserve the leading contact; remove only recording padding, never the
    # strongest transient. Resampling filters the quicker playback safely.
    audio = audio[max(0, int(active[0]) - 24):int(active[-1]) + 1]
    audio = resample_poly(audio, 1000, round(speed * 1000))
    audio = sosfilt(butter(3, [low, high], "bandpass", fs=RATE, output="sos"), audio)
    audio *= np.exp(-np.arange(len(audio)) / RATE / decay)
    return audio / max(float(np.max(np.abs(audio))), 1e-12)


def event_envelope(time, at, decay, attack):
    age = np.maximum(time - at, 0)
    return (1 - np.exp(-age / attack)) * np.exp(-age / decay) * (time >= at)


def author(name):
    config = ASSETS[name]
    rng = np.random.default_rng(config["seed"])
    time = np.arange(round(config["duration"] * RATE)) / RATE
    signal = np.zeros(len(time), dtype=np.float64)
    for layer in config["layers"]:
        audio = recorded(layer["file"], layer["speed"], layer["low"], layer["high"], layer["decay"])
        start = round(layer["at"] * RATE)
        count = min(len(audio), len(signal) - start)
        signal[start:start + count] += audio[:count] * layer["gain"]

    # A fast changing, rough inharmonic resonance follows the contact. It has
    # no sustained musical pitch, tuned interval, kick or stereo room tail.
    glance = config["glance"]
    age = np.maximum(time - glance["at"], 0)
    frequency = glance["end_hz"] + (glance["start_hz"] - glance["end_hz"]) * np.exp(-age / glance["pitch_decay"])
    jitter = sosfilt(butter(2, 340, "lowpass", fs=RATE, output="sos"), rng.normal(size=len(time)))
    jitter /= max(float(jitter.std()), 1e-12)
    frequency *= 1 + np.clip(jitter, -2.2, 2.2) * glance["roughness"] * .028
    phase = np.cumsum(frequency) * (2 * np.pi / RATE)
    scrape = np.sin(phase) + .27 * np.sin(phase * 1.437 + .71) + .11 * np.sin(phase * 1.817 + 1.2)
    scrape *= 1 + .15 * np.sin(2 * np.pi * (197 * age + 39 * age ** 2))
    signal += scrape * event_envelope(time, glance["at"], glance["decay"], .0018) * glance["gain"]

    air = config["air"]
    noise = sosfilt(butter(3, [air["low"], air["high"]], "bandpass", fs=RATE, output="sos"), rng.normal(size=len(time)))
    noise /= max(float(noise.std()), 1e-12)
    signal += noise * event_envelope(time, air["at"], air["decay"], .003) * air["gain"]

    # Keep piercing highs and thudding bass out of this small secondary cue.
    signal = sosfilt(butter(3, [360, 8300], "bandpass", fs=RATE, output="sos"), signal)
    fade = np.sin(np.minimum(time / .0007, 1) * np.pi / 2) ** 2
    fade *= np.sin(np.clip((config["duration"] - 1 / RATE - time) / .030, 0, 1) * np.pi / 2) ** 2
    signal *= fade
    # Remove DC without upsetting the exact zero event boundaries.
    window = np.sin(np.arange(len(signal)) * np.pi / (len(signal) - 1)) ** 2
    signal -= window * signal.sum() / window.sum()
    signal *= config["peak"] / max(float(np.max(np.abs(signal))), 1e-12)
    return signal


def metrics(pcm):
    signal = pcm.astype(np.float64) / 32768
    return {"seconds": len(signal) / RATE, "sample_rate": RATE, "channels": 1,
            "format": "PCM16 WAV", "peak": float(np.max(np.abs(signal))),
            "reconstructed_peak_4x": float(np.max(np.abs(resample_poly(signal, 4, 1)))),
            "rms": float(np.sqrt(np.mean(signal ** 2))), "dc": float(signal.mean())}


def validate_sources():
    provenance = json.loads((SOURCE / "sources.json").read_text())
    if provenance["license"] != "CC0-1.0" or not (SOURCE / "License.txt").is_file():
        raise ValueError("Recorded input license is missing or unexpected")
    for config in ASSETS.values():
        for layer in config["layers"]:
            path = SOURCE / layer["file"]
            if digest(path) != provenance["files"][path.name]:
                raise ValueError(f"Changed source recording: {path}")
    return provenance


def generate(output_directory=OUT, report_path=None):
    output_directory = Path(output_directory)
    output_directory.mkdir(parents=True, exist_ok=True)
    preserved = protected_audio(output_directory)
    source_pack = validate_sources()
    generated = {}
    for name, config in ASSETS.items():
        signal = author(name)
        pcm = np.round(signal * 32767).astype("<i2")
        path = output_directory / (name + ".wav")
        with wave.open(str(path), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(RATE)
            writer.writeframes(pcm.tobytes())
        measurement = metrics(pcm)
        if measurement["reconstructed_peak_4x"] >= .65:
            raise ValueError(f"Reconstructed peak exceeds reserved headroom: {path}")
        metadata = {
            "generator": "tools/generate_ricochet_audio.py", "generator_revision": REVISION,
            "authored_at": DESIGN_DATE, "asset": name, "material": config["material"],
            "description": config["description"],
            "origin": "Kenney CC0 contact recordings layered with original deterministic DSP deflection resonances and air trails. These are authored effects, not recordings of actual bullet ricochets. No AI audio model used.",
            "source_author": source_pack["author"], "source_pack": source_pack["pack"],
            "source_page": source_pack["page"], "source_archive_sha256": source_pack["archive_sha256"],
            "source_license": source_pack["license"], "source_license_url": source_pack["license_url"],
            "source_recordings": {layer["file"]: source_pack["files"][layer["file"]] for layer in config["layers"]},
            "derivative_license": "CC0-1.0", "sha256": digest(path), **measurement,
            "processing": {"recorded_layers": config["layers"], "original_dsp_glance": config["glance"],
                           "original_dsp_air": config["air"], "seed": config["seed"],
                           "reverb": False, "musical_layers": False, "output_bandpass_hz": [360, 8300],
                           "peak_target": config["peak"], "release_seconds": .030},
            "review": "Objective decoded-PCM and source verification only; browser samples provided for human listening.",
        }
        path.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        path.with_suffix(".LICENSE.txt").write_text(
            "Bunkercrew authored bullet ricochet effect\n\n"
            "Recorded contacts: Kenney, Impact Sounds (1.0)\n"
            "https://kenney.nl/assets/impact-sounds\n"
            "Source license: Creative Commons Zero, CC0-1.0\n"
            "https://creativecommons.org/publicdomain/zero/1.0/\n"
            "Original source license: assets/audio/source_recordings/enemy_foley/License.txt\n\n"
            "The original DSP deflection/air layers, audio processing and mixed derivative\n"
            "are also released under CC0-1.0. No actual gunfire recording or AI audio\n"
            "model was used. Exact contact inputs and hashes are in the adjacent source JSON.\n\n"
            + (SOURCE / "License.txt").read_text(encoding="utf-8"), encoding="utf-8")
        generated[path.name] = {**measurement, "sha256": metadata["sha256"]}
    current = protected_audio(output_directory)
    if current != preserved:
        raise ValueError("Unexpected addition, removal or modification to earlier audio")
    report = {"generator_revision": REVISION, "assets": generated,
              "preserved_audio_count": len(preserved), "preserved_audio_sha256": preserved,
              "preserved_unchanged": True,
              "measurement_limit": "4x polyphase reconstructed peaks; no certified true-peak meter or human listening claim."}
    if report_path:
        report_path = Path(report_path)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=OUT)
    parser.add_argument("--report", type=Path,
                        default=ROOT / "artifacts/ricochet-audio-20261005/generation-report.json")
    args = parser.parse_args()
    report = generate(args.output_directory, args.report)
    print(f"Generated {len(report['assets'])} spatial-ready ricochets; preserved {report['preserved_audio_count']} earlier audio files.")


if __name__ == "__main__":
    main()
