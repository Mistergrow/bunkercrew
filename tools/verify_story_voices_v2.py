#!/usr/bin/env python3
"""Independent waveform, provenance, duplicate and optional Whisper speech audit."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
from verify_story_voices import error_rate

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/story_voices_v2"
REPORT = ROOT / "artifacts/expedition/voices"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcribe", action="store_true")
    parser.add_argument("--anchors", action="store_true")
    parser.add_argument("--locale", choices=["de", "en"], default="de")
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--report-dir", type=Path, default=REPORT)
    parser.add_argument("--device", default="cuda:0")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--download-asr", action="store_true", help="Allow downloading the independent Whisper checker")
    parser.add_argument(
        "--speaker-check",
        action="store_true",
        help="Compare synthetic anchor identities with generated recordings using the model speaker encoder",
    )
    parser.add_argument(
        "--reuse-report",
        action="store_true",
        help="Reuse independent transcripts only for byte-identical recordings from the previous report",
    )
    args = parser.parse_args()
    if args.threads < 1:
        parser.error("Thread count must be positive")
    report_dir = args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)
    if args.anchors:
        dest = DEST / "anchors"
        lines = []
        files = {}
        for meta_path in sorted(dest.glob("*.source.json")):
            meta = json.loads(meta_path.read_text())
            name = meta_path.name.replace(".source.json", ".wav")
            lines.append(
                {
                    "file": name,
                    "text": meta["text"],
                    "speaker": meta_path.stem.split(".")[0],
                }
            )
            files[name] = meta
    else:
        dest = DEST / ("en" if args.locale == "en" else "")
        lines = json.loads((dest / "lines.json").read_text())["lines"]
        files = json.loads((dest / "source.json").read_text())["files"]
    if args.only:
        lines = [row for row in lines if Path(row["file"]).stem in args.only]
    model = processor = None
    if args.transcribe:
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor

        torch.set_num_threads(args.threads)
        processor = WhisperProcessor.from_pretrained(
            "openai/whisper-small", local_files_only=not args.download_asr
        )
        model = (
            WhisperForConditionalGeneration.from_pretrained(
                "openai/whisper-small", local_files_only=not args.download_asr
            )
            .to("cpu")
            .eval()
        )
    report = {
        "locale": args.locale,
        "scope": "anchors" if args.anchors else "recordings",
        "asr": "openai/whisper-small local CPU" if args.transcribe else None,
        "subjective_listening": "Not performed by the coding model; it cannot consume audio input. Listen to the supplied audition page.",
        "files": [],
        "failures": [],
    }
    seen = {}
    output = report_dir / (
        "anchors-verification.json"
        if args.anchors
        else "voices-" + args.locale + "-verification.json"
    )
    if args.only:
        output = output.with_stem(output.stem + "-selected")
    cached = {}
    if args.reuse_report and output.exists():
        prior = json.loads(output.read_text())
        if prior.get("asr") == report["asr"]:
            cached = {
                entry["sha256"]: entry
                for entry in prior["files"]
                if "transcript" in entry
            }
    if not lines:
        report["failures"].append("No recordings selected")
    expected = {line["file"] for line in lines}
    actual = {
        path.name
        for path in dest.glob("*.wav")
        if not args.only or path.stem in args.only
    }
    if expected != actual:
        report["failures"].append(
            "Recording set differs: missing="
            + str(expected - actual)
            + ", extra="
            + str(actual - expected)
        )
    if args.speaker_check:
        import torch
        from generate_story_voices_v2 import BASE, BASE_REV, PROFILES
        from huggingface_hub import snapshot_download
        from qwen_tts import Qwen3TTSModel

        torch.set_num_threads(args.threads)
        speaker_model = Qwen3TTSModel.from_pretrained(
            snapshot_download(BASE, revision=BASE_REV),
            device_map=args.device,
            dtype=torch.bfloat16 if args.device.startswith("cuda") else torch.float32,
            attn_implementation="sdpa",
        )

        def embedding(path):
            wave, rate = sf.read(path, dtype="float32")
            with torch.inference_mode():
                vector = (
                    speaker_model.model.extract_speaker_embedding(audio=wave, sr=rate)
                    .float()
                    .cpu()
                    .numpy()
                )
            return vector / np.linalg.norm(vector)

        anchors = {
            speaker: embedding(DEST / "anchors" / (speaker + ".wav"))
            for speaker in PROFILES
        }
        report["speaker_encoder"] = (
            "Qwen3-TTS Base speaker encoder; diagnostic consistency check, not an independent listening review"
        )
        report["anchor_similarity"] = {
            left: {right: round(float(np.dot(a, b)), 3) for right, b in anchors.items()}
            for left, a in anchors.items()
        }
    for line in lines:
        path = dest / line["file"]
        errors = []
        if not path.exists():
            report["failures"].append(str(path) + " missing")
            continue
        wave, rate = sf.read(path, dtype="float32")
        info = sf.info(path)
        if info.channels != 1 or rate != 24000 or info.subtype != "PCM_16":
            errors.append("Expected24kHz mono PCM16")
        if not np.isfinite(wave).all():
            errors.append("Nonfinitewaveform")
        duration = len(wave) / rate
        peak = float(np.max(np.abs(wave)))
        rms = float(np.sqrt(np.mean(wave**2)))
        if not 0.7 < duration < 17:
            errors.append("Unexpectedduration")
        if not args.anchors and (not 0.08 < peak < 0.81 or not 0.02 < rms < 0.13):
            errors.append("Incorrectmasteredlevels")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        metadata = files.get(path.name, {})
        if metadata.get("sha256") != digest:
            errors.append("Checksum mismatch")
        if metadata.get("text") != line["text"] or (
            not args.anchors and metadata.get("speaker") != line["speaker"]
        ):
            errors.append("Authored text or speaker differs from provenance")
        if not args.anchors and "anchor_file" in metadata:
            anchor = ROOT / metadata["anchor_file"]
            if not anchor.is_file() or hashlib.sha256(
                anchor.read_bytes()
            ).hexdigest() != metadata.get("anchor_sha256"):
                errors.append("Synthetic speaker anchor checksum mismatch")
        if digest in seen:
            errors.append("Exactduplicate of " + seen[digest])
        seen[digest] = path.name
        entry = {
            "file": path.name,
            "speaker": line["speaker"],
            "reference": line["text"],
            "duration": round(duration, 3),
            "peak_dbfs": round(20 * np.log10(max(peak, 1e-8)), 2),
            "rms_dbfs": round(20 * np.log10(max(rms, 1e-8)), 2),
            "sha256": digest,
        }
        if args.speaker_check and ("anchor_file" in metadata or args.anchors):
            vector = embedding(path)
            similarities = {
                speaker: round(float(np.dot(vector, anchor)), 3)
                for speaker, anchor in anchors.items()
            }
            entry["speaker_similarity"] = similarities
            entry["nearest_anchor"] = max(similarities, key=similarities.get)
            if entry["nearest_anchor"] != line["speaker"]:
                errors.append("Speaker identity mismatch: review or regenerate")
        if args.transcribe:
            if digest in cached:
                entry["transcript"] = cached[digest]["transcript"]
                entry["transcript_reused_for_identical_sha256"] = True
            else:
                audio = resample_poly(wave, 2, 3)
                inputs = processor(
                    audio,
                    sampling_rate=16000,
                    return_tensors="pt",
                    return_attention_mask=True,
                )
                with torch.inference_mode():
                    ids = model.generate(
                        **inputs,
                        language=args.locale,
                        task="transcribe",
                        max_new_tokens=180,
                    )
                entry["transcript"] = processor.batch_decode(
                    ids, skip_special_tokens=True
                )[0].strip()
            entry["word_error_rate"] = round(
                error_rate(line["text"], entry["transcript"]), 3
            )
            if entry["word_error_rate"] > 0.25:
                errors.append("ASR mismatch: review or regenerate")
        entry["failures"] = errors
        report["files"].append(entry)
        report["failures"].extend(path.name + ": " + e for e in errors)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(entry, ensure_ascii=False), flush=True)
    print(
        "VOICE AUDIT",
        len(report["files"]),
        "files",
        len(report["failures"]),
        "failures",
        flush=True,
    )
    raise SystemExit(1 if report["failures"] else 0)


if __name__ == "__main__":
    main()
