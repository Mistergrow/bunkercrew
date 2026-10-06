#!/usr/bin/env python3
"""Check delivered PCM speech; optionally transcribe it with independent Whisper.

No game runtime dependency. --transcribe uses the local openai/whisper-small
cache (Apache-2.0) and never sends recordings to an external service.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/story_voices"
REPORT = ROOT / "artifacts/story-dialogue/voice-verification.json"


def words(text):
    return re.findall(r"[\wäöüß]+", text.casefold(), flags=re.UNICODE)


def error_rate(reference, result):
    left, right = words(reference), words(result)
    row = list(range(len(right) + 1))
    for i, a in enumerate(left, 1):
        next_row = [i]
        for j, b in enumerate(right, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (a != b)))
        row = next_row
    return row[-1] / max(1, len(left))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcribe", action="store_true")
    parser.add_argument("--locale", choices=["de", "en"], default="de")
    parser.add_argument("--only", nargs="*", default=[], help="Check only these recording basenames")
    args = parser.parse_args()
    destination = DEST if args.locale == "de" else DEST / args.locale
    report_path = REPORT if args.locale == "de" else REPORT.with_name("voice-verification-" + args.locale + ".json")
    source = json.loads((destination / "source.json").read_text())
    lines = json.loads((destination / "lines.json").read_text())["lines"]
    if args.only:
        lines = [line for line in lines if Path(line["file"]).stem in args.only]
        report_path = report_path.with_stem(report_path.stem + "-selected")
    model = processor = None
    if args.transcribe:
        import torch
        from transformers import WhisperProcessor, WhisperForConditionalGeneration
        torch.set_num_threads(4)
        processor = WhisperProcessor.from_pretrained("openai/whisper-small", local_files_only=True)
        model = WhisperForConditionalGeneration.from_pretrained("openai/whisper-small", local_files_only=True).eval()
    report = {"speech_files":[], "failures":[], "locale":args.locale, "asr_model":"openai/whisper-small" if args.transcribe else None}
    expected = {line["file"] for line in lines}
    actual = {path.name for path in destination.glob("*.wav") if not args.only or path.stem in args.only}
    if actual != expected: report["failures"].append(f"File set differs: missing={expected-actual}, extra={actual-expected}")
    for line in lines:
        path = destination / line["file"]
        failures = []
        if not path.exists(): continue
        data, rate = sf.read(path, dtype="float32")
        info = sf.info(path)
        meta = source["files"].get(path.name, {})
        if info.channels != 1 or info.subtype != "PCM_16" or rate != 24000: failures.append("Expected 24kHz mono PCM16")
        if not np.isfinite(data).all(): failures.append("Nonfinite waveform")
        duration = len(data)/rate
        if not .8 < duration < 16: failures.append(f"Unexpected duration {duration}")
        peak = float(np.max(np.abs(data)))
        rms = float(np.sqrt(np.mean(data**2)))
        if not .08 < peak < .81 or not .02 < rms < .13: failures.append(f"Invalid speech level: peak={peak}, rms={rms}")
        if meta.get("sha256") != hashlib.sha256(path.read_bytes()).hexdigest(): failures.append("Provenance checksum mismatch")
        if meta.get("text") != line["text"] or meta.get("speaker") != line["speaker"]: failures.append("Recorded text/speaker differs from authored input")
        item = {"file":path.name,"reference":line["text"],"duration":round(duration,3),"peak_dbfs":round(20*np.log10(peak),2),"rms_dbfs":round(20*np.log10(rms),2)}
        if args.transcribe:
            import torch
            from scipy.signal import resample_poly
            audio = resample_poly(data, 2, 3)
            inputs = processor(audio, sampling_rate=16000, return_tensors="pt", return_attention_mask=True)
            with torch.inference_mode():
                ids = model.generate(**inputs, language=args.locale, task="transcribe", max_new_tokens=160)
            transcript = processor.batch_decode(ids, skip_special_tokens=True)[0].strip()
            item["transcript"] = transcript
            item["word_error_rate"] = round(error_rate(line["text"], transcript),3)
            if item["word_error_rate"] > .25: failures.append("ASR differs substantially; review or regenerate this line")
        item["failures"] = failures
        report["speech_files"].append(item)
        report["failures"].extend([path.name+": "+failure for failure in failures])
        print(json.dumps(item,ensure_ascii=False),flush=True)
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(f"Verified {len(report['speech_files'])}/{len(lines)} speech files; {len(report['failures'])} failures",flush=True)
    raise SystemExit(1 if report["failures"] else 0)


if __name__ == "__main__":
    main()
