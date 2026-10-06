#!/usr/bin/env python3
"""Stable fictional cast: design one synthetic anchor, reuse its conditioning.

No real person's voice is used. Candidate output stays separate from the shipped
v1 recordings until waveform and transcription checks pass.
"""

from __future__ import annotations

import argparse
import gc
import hashlib
import json
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/story_voices_v2"
DESIGN = "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
DESIGN_REV = "5ecdb67327fd37bb2e042aab12ff7391903235d3"
BASE = "Qwen/Qwen3-TTS-12Hz-1.7B-Base"
BASE_REV = "fd4b254389122332181a7c3db7f27e918eec64e3"
ANCHOR_TEXT = "Wir haben noch einen langen Weg vor uns. Ich sehe nach den Vorräten, dann fahren wir weiter. Bleibt in meiner Nähe. Zusammen kommen wir hier durch."
PROFILES = {
    "san": {
        "seed": 718,
        "prompt": "Native German woman in her late forties, mature low mezzo voice. An experienced calm emergency radio dispatcher. Clear factual spoken dialogue, composed reassurance, even compact phrasing. Natural standard German articulation, intimate close microphone, no announcer performance, no whispering, no theatrical emphasis.",
    },
    "mara": {
        "seed": 1299,
        "prompt": "Native German woman in her late thirties, distinct deep smoky alto, slightly rough dry vocal texture. A practical confident forewoman talking directly to her work crew. Relaxed everyday conversational German, firm grounded energy, natural connected words and breath pauses. No announcer cadence, no whispering, no exaggerated drama.",
    },
    "branko": {
        "seed": 3149,
        "prompt": "Native German man in his late fifties with a distinctly low resonant bass, coarse weathered gravel at the ends of words. A protective veteran guard. Unhurried, terse, warm but tough conversational German. Compact natural phrases, close dry microphone, no singing, no announcer delivery, no whispering.",
    },
    "ivo": {
        "seed": 4049,
        "prompt": "Native German man in his early twenties. Clearly youthful high light tenor, bright slightly nasal timbre, nimble spontaneous conversational rhythm. A curious mechanic thinking while speaking. Friendly alert energy, natural German vowel connections and mild breath pauses. Dry close microphone, no presenter voice or dramatic performance.",
    },
    "nora": {
        "seed": 5303,
        "prompt": "Native German woman in her late twenties with a bright clear higher soprano speaking voice and precise light articulation. An analytical engineer, direct and brisk, slightly wry and curious. Natural relaxed spoken German with connected syllables, crisp short sentences. Dry close microphone, no airy whisper, no announcer or cartoon tone.",
    },
    "levin": {
        "seed": 6217,
        "prompt": "Native German man in his mid thirties. Distinct medium baritone, dry lean edged timbre, slightly raspy forward voice. An observant scout speaking quietly but fully voiced, alert and economical. Brisk confident everyday spoken German, restrained urgency, dry close microphone. No bass rumble, no whisper, no theatrical narration.",
    },
    "selma": {
        "seed": 7331,
        "prompt": "Native German woman in her early fifties. Warm rounded middle register, full gentle chest resonance, velvety softly textured voice. An experienced field medic speaking to someone nearby. Patient reassuring conversational German, steady natural breath groups, clear unforced consonants. Dry close microphone, no announcer delivery, no whispering or exaggerated softness.",
    },
    "oskar": {
        "seed": 8453,
        "prompt": "Native German man in his early forties. Broad rounded chesty mid-low baritone, warm open vowels, solid friendly miner with relaxed good humor. Distinct full-bodied resonant speaking voice, naturally a little breathy at phrase ends, not a gravelly bass or thin nasal tenor. Unhurried grounded everyday German, short practical sentences, clear consonants. Dry close microphone, no presenter cadence, no caricature, no singing or whispering.",
    },
    "rika": {
        "seed": 9547,
        "prompt": "Native German woman in her early twenties. Distinct forward mid-register speaking voice, lightly husky grain with lively quick confident articulation. An alert hands-on electrician, friendly direct everyday conversational German, energetic without shouting. Compact rhythm with natural connected syllables, darker and drier than a bright high soprano but without a deep smoky alto. Dry close microphone, no announcer cadence, no cartoon performance, no singing or whispering.",
    },
}


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def master(wave, rate, speaker):
    import numpy as np
    from scipy.signal import butter, sosfilt

    wave = np.asarray(wave, dtype=np.float64).reshape(-1)
    if not np.isfinite(wave).all() or len(wave) < rate // 2:
        raise ValueError("Invalid speech")
    wave = sosfilt(
        butter(
            2,
            [120, 7600] if speaker == "san" else [65, 10000],
            btype="bandpass",
            fs=rate,
            output="sos",
        ),
        wave,
    )
    active = np.flatnonzero(np.abs(wave) > 0.004)
    if not len(active):
        raise ValueError("Silent speech")
    wave = wave[
        max(0, int(active[0]) - int(rate * 0.07)) : min(
            len(wave), int(active[-1]) + int(rate * 0.16)
        )
    ]
    wave *= min(
        10 ** (-20 / 20) / max(float(np.sqrt(np.mean(wave**2))), 1e-8),
        0.79 / max(float(np.max(np.abs(wave))), 1e-8),
    )
    fade = min(int(rate * 0.008), len(wave) // 4)
    wave[:fade] *= np.linspace(0, 1, fade)
    wave[-fade:] *= np.linspace(1, 0, fade)
    return wave.astype(np.float32)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--anchors-only", action="store_true")
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--locale", choices=["de", "en", "all"], default="all")
    parser.add_argument("--batch", type=int, default=3)
    parser.add_argument("--speakers", nargs="*", choices=sorted(PROFILES), default=[])
    parser.add_argument("--device", default="cuda:0", help="CPU supports generation while a GPU is occupied")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--dtype", choices=["auto", "float32", "bfloat16"], default="auto")
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--seed",
        type=int,
        default=9001,
        help="Base sampling seed; stored with each recording",
    )
    args = parser.parse_args()
    if args.batch < 1 or args.threads < 1:
        parser.error("Batch and thread counts must be positive")
    import numpy as np
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download
    from qwen_tts import Qwen3TTSModel

    torch.set_num_threads(args.threads)
    device = args.device
    dtype_name = args.dtype if args.dtype != "auto" else ("bfloat16" if device.startswith("cuda") else "float32")
    dtype = getattr(torch, dtype_name)
    speakers = args.speakers or list(PROFILES)
    DEST.mkdir(parents=True, exist_ok=True)
    anchors = DEST / "anchors"
    anchors.mkdir(exist_ok=True)
    missing = [name for name in speakers if not (anchors / (name + ".wav")).exists()]
    if missing:
        model = Qwen3TTSModel.from_pretrained(
            snapshot_download(DESIGN, revision=DESIGN_REV),
            device_map=device,
            dtype=dtype,
            attn_implementation="sdpa",
        )
        for speaker in missing:
            began = time.monotonic()
            torch.manual_seed(PROFILES[speaker]["seed"])
            torch.cuda.manual_seed_all(PROFILES[speaker]["seed"])
            with torch.inference_mode():
                waves, rate = model.generate_voice_design(
                    text=ANCHOR_TEXT,
                    language="German",
                    instruct=PROFILES[speaker]["prompt"],
                    non_streaming_mode=True,
                    max_new_tokens=650,
                    do_sample=True,
                    top_p=0.8,
                    temperature=0.65,
                    repetition_penalty=1.1,
                )
            # Keep conditioning dry and unprocessed; only the final game line gets EQ.
            raw = np.asarray(waves[0], dtype=np.float32)
            sf.write(anchors / (speaker + ".wav"), raw, rate, subtype="PCM_16")
            meta = {
                "model": DESIGN,
                "revision": DESIGN_REV,
                "seed": PROFILES[speaker]["seed"],
                "prompt": PROFILES[speaker]["prompt"],
                "text": ANCHOR_TEXT,
                "reference_voice": "Entirely synthetic fictional voice; no human reference.",
                "sha256": checksum(anchors / (speaker + ".wav")),
                "sample_rate": rate,
                "duration": len(raw) / rate,
                "device": device,
                "dtype": dtype_name,
            }
            (anchors / (speaker + ".source.json")).write_text(
                json.dumps(meta, ensure_ascii=False, indent=2) + "\n"
            )
            print(
                "ANCHOR",
                speaker,
                round(len(raw) / rate, 2),
                "seconds; generated in",
                round(time.monotonic() - began, 1),
                flush=True,
            )
        del model
        gc.collect()
        if device.startswith("cuda"):
            torch.cuda.empty_cache()
    if args.anchors_only:
        return
    model_path = Path(snapshot_download(BASE, revision=BASE_REV))
    model = Qwen3TTSModel.from_pretrained(
        str(model_path),
        device_map=device,
        dtype=dtype,
        attn_implementation="sdpa",
    )
    prompts = {
        speaker: model.create_voice_clone_prompt(
            ref_audio=str(anchors / (speaker + ".wav")),
            ref_text=ANCHOR_TEXT,
            x_vector_only_mode=False,
        )
        for speaker in speakers
    }
    for locale in ["de", "en"] if args.locale == "all" else [args.locale]:
        dest = DEST if locale == "de" else DEST / "en"
        dest.mkdir(exist_ok=True)
        lines = json.loads((dest / "lines.json").read_text())["lines"]
        meta_path = dest / "source.json"
        metadata = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        metadata.update(
            {
                "generator": "tools/generate_story_voices_v2.py",
                "model": BASE,
                "revision": model_path.name,
                "language": "German" if locale == "de" else "English",
                "locale": locale,
                "model_license": "Apache-2.0",
                "model_source": "https://huggingface.co/" + BASE,
                "reference_audio": "../anchors for EN; anchors for DE. " + str(len(PROFILES)) + " separate synthetic fictional voice anchors, never a real person.",
                "method": "One designed speaker identity per character, held fixed with reference-code and speaker-embedding conditioning for every subsequent line.",
                "profiles": PROFILES,
                "mastering": "24kHz mono PCM16, gentle rumble removal, SAN120–7600Hz, others65–10000Hz, -20dBFS RMS target with -2dBFS peak headroom,8ms fades.",
            }
        )
        files = metadata.setdefault("files", {})
        selected = [
            line
            for line in lines
            if line["speaker"] in speakers
            and (not args.only or Path(line["file"]).stem in args.only)
            and (args.force or not (dest / line["file"]).exists())
        ]
        # Keep batches at similar phrase length, while every item uses its own anchor.
        selected.sort(key=lambda line: len(line["text"]))
        for offset in range(0, len(selected), args.batch):
            batch = selected[offset : offset + args.batch]
            began = time.monotonic()
            seed = args.seed + offset
            torch.manual_seed(seed)
            torch.cuda.manual_seed_all(seed)
            with torch.inference_mode():
                waves, rate = model.generate_voice_clone(
                    text=[x["text"] for x in batch],
                    language=["German" if locale == "de" else "English"] * len(batch),
                    voice_clone_prompt=[prompts[x["speaker"]][0] for x in batch],
                    non_streaming_mode=True,
                    max_new_tokens=900,
                    do_sample=True,
                    top_p=0.8,
                    temperature=0.65,
                    repetition_penalty=1.08,
                )
            for line, wave in zip(batch, waves):
                wave = master(wave, rate, line["speaker"])
                output = dest / line["file"]
                sf.write(output, wave, rate, subtype="PCM_16")
                files[line["file"]] = {
                    **line,
                    "sample_rate": rate,
                    "frames": len(wave),
                    "duration": len(wave) / rate,
                    "rms_dbfs": float(20 * np.log10(np.sqrt(np.mean(wave**2)))),
                    "peak_dbfs": float(20 * np.log10(np.max(np.abs(wave)))),
                    "sha256": checksum(output),
                    "seed": seed,
                    "anchor_sha256": checksum(anchors / (line["speaker"] + ".wav")),
                    "anchor_file": str(
                        (anchors / (line["speaker"] + ".wav")).relative_to(ROOT)
                    ),
                    "device": device,
                    "dtype": dtype_name,
                }
                print(
                    locale,
                    line["file"],
                    round(len(wave) / rate, 2),
                    "seconds",
                    flush=True,
                )
            temp = meta_path.with_suffix(".json.pending")
            temp.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
            temp.replace(meta_path)
            print(
                "BATCH",
                offset,
                "of",
                len(selected),
                "in",
                round(time.monotonic() - began, 1),
                "seconds",
                flush=True,
            )


if __name__ == "__main__":
    main()
