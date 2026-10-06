#!/usr/bin/env python3
"""Verify ricochet PCM, finite headroom, contact provenance and reproducibility."""
from pathlib import Path
import argparse
import hashlib
import html
import itertools
import json
import shutil
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_ricochet_audio as generator

LABELS = {
    "ricochet_metal_01": ("Stahl · kurzer Ping und Zip", "Steel · short ping and zip"),
    "ricochet_metal_02": ("Metall · längerer Streifschuss", "Metal · longer glancing zing"),
    "ricochet_stone_01": ("Beton / Stein · Splitter und kurzer Luftschweif", "Concrete / stone · chips and brief air trail"),
}


def _waveform(signal):
    chunks = np.array_split(signal, 220)
    peaks = [float(np.max(np.abs(chunk))) for chunk in chunks]
    top = " ".join(f"{index * 3:.2f},{32 - peak * 49:.3f}" for index, peak in enumerate(peaks))
    bottom = " ".join(f"{index * 3:.2f},{32 + peak * 49:.3f}" for index, peak in reversed(list(enumerate(peaks))))
    return '<svg role="img" aria-label="PCM envelope" viewBox="0 0 660 64"><path fill="#9aaa88" d="M ' + top + ' L ' + bottom + ' Z"/></svg>'


def _preview(output, bank, measurements):
    cards = []
    for name in generator.ASSETS:
        filename = name + ".wav"
        de, en = LABELS[name]
        values = measurements[filename]
        cards.append(
            '<article><h2>' + html.escape(de) + '</h2><p class="secondary">' + html.escape(en) + '</p>'
            + _waveform(bank[filename])
            + f'<audio controls preload="none" src="../../assets/audio/{filename}"></audio>'
            + f'<p class="technical">{values["seconds"]:.3f} s · 48 kHz · Mono · PCM16 · Peak {values["peak"]:.3f}</p>'
            + f'<p><a href="../../assets/audio/{name}.source.json">Herkunft / provenance</a> · '
              f'<a href="../../assets/audio/{name}.LICENSE.txt">CC0-Lizenz / license</a></p></article>'
        )
    output.joinpath("index.html").write_text(
        '<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Bunkercrew · Drei Abpraller / Three ricochets</title>'
        '<style>body{max-width:840px;margin:40px auto;padding:0 24px;background:#121b18;color:#d4d1bc;font:17px/1.5 system-ui}h1{font-size:28px}h2{font-size:21px;margin-bottom:0}article{padding:22px 0;border-bottom:1px solid #36443b}audio,svg{display:block;width:100%}svg{height:64px;margin:18px 0}.secondary,.technical{color:#a2aa96;margin-top:4px}.technical{font-size:14px}a{color:#d7b365}</style>'
        '<h1>Drei neue Schuss-Abpraller</h1>'
        '<p>Zwei Varianten für Metall und eine für Stein/Beton. Kurze mono Effekte für die räumliche Wiedergabe im Spiel; die Abpraller ersetzen keine Schussgeräusche.</p>'
        '<p class="secondary">Two metal variations and one concrete/stone variation. Mono effects for spatial playback; these supplement the original gunshots.</p>'
        + "".join(cards)
        + '<p>Die Kontaktanfänge stammen aus vorhandenen Kenney-CC0-Aufnahmen. Die kurzen Deflektionsresonanzen und Luftschweife sind originale, deterministische DSP-Layer. Keine Aufnahme echter abprallender Geschosse; kein KI-Audiomodell.</p>'
        '<p class="secondary">Recorded Kenney CC0 contacts plus original deterministic DSP deflection/air layers. These are authored effects, not live bullet-ricochet recordings.</p>'
        '<p><a href="asset-verification.json">PCM-, Herkunfts- und Reproduktionsprüfung / PCM, provenance and reproduction checks</a></p>'
        '<p class="technical">Objektive Signalprüfung; diese Vorschau ermöglicht menschliche Hörtests. Keine behauptete menschliche Hörabnahme.</p></html>', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-directory", type=Path,
                        default=ROOT / "artifacts/ricochet-audio-20261005")
    args = parser.parse_args()
    output = args.report_directory
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    measurements = {}
    bank = {}

    def check(condition, description):
        value = bool(condition)
        checks.append({"passed": value, "description": description})
        print(("PASS " if value else "FAIL ") + description)

    for name, config in generator.ASSETS.items():
        path = ROOT / "assets/audio" / (name + ".wav")
        metadata = json.loads(path.with_suffix(".source.json").read_text(encoding="utf-8"))
        with wave.open(str(path), "rb") as reader:
            channels = reader.getnchannels()
            width = reader.getsampwidth()
            rate = reader.getframerate()
            compression = reader.getcomptype()
            frames = reader.getnframes()
            raw = reader.readframes(frames)
        pcm = np.frombuffer(raw, dtype="<i2")
        signal = pcm.astype(np.float64) / 32768
        bank[path.name] = signal
        power = np.abs(np.fft.rfft(signal)) ** 2
        frequency = np.fft.rfftfreq(len(signal), 1 / rate)
        total_energy = float(np.sum(signal ** 2))
        values = {
            "seconds": len(signal) / rate,
            "peak": float(np.max(np.abs(signal))),
            "reconstructed_peak_4x": float(np.max(np.abs(resample_poly(signal, 4, 1)))),
            "rms": float(np.sqrt(np.mean(signal ** 2))),
            "dc": float(signal.mean()),
            "energy_below_180_hz": float(power[frequency < 180].sum() / power.sum()),
            "energy_above_10khz": float(power[frequency > 10000].sum() / power.sum()),
            "last_15_percent_energy": float(np.sum(signal[int(len(signal) * .85):] ** 2) / total_energy),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        measurements[path.name] = values
        check(channels == 1 and width == 2 and rate == 48000 and compression == "NONE"
              and len(raw) == frames * 2 and .20 < values["seconds"] < .60,
              path.name + ": short uncompressed mono 48 kHz PCM16, ready for positional playback")
        check(np.isfinite(signal).all() and .015 < values["rms"] < .12,
              path.name + ": finite, non-silent secondary contact cue")
        check(.45 < values["peak"] < .61 and values["reconstructed_peak_4x"] < .65
              and not np.any(np.abs(pcm.astype(np.int32)) >= 32767),
              path.name + ": decoded and 4x reconstructed peaks retain useful headroom")
        check(pcm[0] == 0 and pcm[-1] == 0 and abs(values["dc"]) < .0001,
              path.name + ": exact silent boundaries and negligible DC")
        check(values["energy_below_180_hz"] < .01 and values["energy_above_10khz"] < .005,
              path.name + ": restrained sub-bass and upper highs")
        check(values["last_15_percent_energy"] < .002,
              path.name + ": tail resolves within the event, without an abrupt sustained cut")
        check(values["sha256"] == metadata["sha256"] and metadata["sample_rate"] == rate
              and metadata["channels"] == channels and metadata["format"] == "PCM16 WAV",
              path.name + ": shipping bytes and format match the adjacent source declaration")
        source_pack = json.loads((generator.SOURCE / "sources.json").read_text(encoding="utf-8"))
        check(metadata["source_recordings"] and all(
            hashlib.sha256((generator.SOURCE / filename).read_bytes()).hexdigest() == digest
            and source_pack["files"][filename] == digest
            for filename, digest in metadata["source_recordings"].items()),
            path.name + ": every recorded source exists and matches the original pack hash")
        license_text = path.with_suffix(".LICENSE.txt").read_text(encoding="utf-8")
        check(metadata["source_license"] == "CC0-1.0" and metadata["derivative_license"] == "CC0-1.0"
              and "Kenney" in license_text and "original DSP" in license_text
              and (generator.SOURCE / "License.txt").read_text(encoding="utf-8") in license_text,
              path.name + ": recorded contacts and original DSP retain explicit CC0 provenance")
        check("not recordings of actual bullet ricochets" in metadata["origin"]
              and metadata["processing"]["original_dsp_glance"]
              and metadata["processing"]["original_dsp_air"]
              and not metadata["processing"]["musical_layers"]
              and not metadata["processing"]["reverb"],
              path.name + ": synthesized layers are honestly declared, with no musical or stereo tail")
        rebuilt = np.round(generator.author(name) * 32767).astype("<i2")
        check(np.array_equal(pcm, rebuilt),
              path.name + ": the shipping signal reproduces deterministically from declared inputs")

    correlations = {}
    for first, second in itertools.combinations(bank, 2):
        length = min(len(bank[first]), len(bank[second]))
        correlation = float(np.corrcoef(bank[first][:length], bank[second][:length])[0, 1])
        correlations[first + "/" + second] = correlation
        check(abs(correlation) < .65, first + "/" + second + ": distinct contact and deflection signals")
    check(measurements["ricochet_stone_01.wav"]["seconds"]
          < measurements["ricochet_metal_01.wav"]["seconds"]
          < measurements["ricochet_metal_02.wav"]["seconds"],
          "Dry stone cue and both metallic cues have independently useful temporal profiles")

    # Exercise the actual file writer twice in an isolated directory and
    # protect an existing WAV plus an existing nested source recording.
    with tempfile.TemporaryDirectory(prefix="bunkercrew-ricochet-reproduction-") as scratch:
        directory = Path(scratch)
        shutil.copyfile(ROOT / "assets/audio/impact_metal_01.wav", directory / "preserved_contact.wav")
        nested = directory / "source_recordings"
        nested.mkdir()
        shutil.copyfile(generator.SOURCE / "impactMetal_light_002.ogg", nested / "preserved_contact.ogg")
        protected = generator.protected_audio(directory)
        first = generator.generate(directory)
        first_bytes = {filename: (directory / filename).read_bytes() for filename in generator.owned_names()}
        second = generator.generate(directory)
        check(generator.protected_audio(directory) == protected
              and first["preserved_unchanged"] and second["preserved_unchanged"]
              and first["preserved_audio_count"] == 2,
              "Generator preserves all earlier WAV and nested recording bytes")
        check(all((directory / filename).read_bytes() == data for filename, data in first_bytes.items()),
              "Repeated generation reproduces WAV, source JSON and license bytes exactly")
        check({str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file()}
              == generator.owned_names() | set(protected),
              "Generator emits only its three assets and six adjacent provenance files")
        check(all((directory / filename).read_bytes() == (ROOT / "assets/audio" / filename).read_bytes()
                  for filename in generator.owned_names()),
              "Isolated regenerated asset bank exactly matches the shipped bank")

    generation_report = output / "generation-report.json"
    if generation_report.is_file():
        generated = json.loads(generation_report.read_text(encoding="utf-8"))
        check(generated["preserved_unchanged"] and all(
            hashlib.sha256((ROOT / "assets/audio" / filename).read_bytes()).hexdigest() == digest
            for filename, digest in generated["preserved_audio_sha256"].items()),
            "All earlier live audio matches the before-generation preservation manifest")
    report = {"checks": len(checks), "passed": sum(check["passed"] for check in checks),
              "failed": sum(not check["passed"] for check in checks), "measurements": measurements,
              "correlations": correlations, "results": checks,
              "measurement_limit": "4x polyphase reconstructed peaks; no certified true-peak meter or human listening claim."}
    output.joinpath("asset-verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    _preview(output, bank, measurements)
    print(f"RICOCHET AUDIO ASSETS: {report['passed']}/{report['checks']} checks passed")
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
