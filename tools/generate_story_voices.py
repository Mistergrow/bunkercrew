#!/usr/bin/env python3
"""Generate fictional German or English speech locally, without reference voices.

Run tools/export_story_voice_lines.gd first. Install qwen-tts==0.1.1 in an
isolated environment with PyTorch CUDA. Weights stay in the HuggingFace cache;
only the mastered PCM16 speech and its provenance belong in the game.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/audio/story_voices"
MODEL = "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
REVISION = "5ecdb67327fd37bb2e042aab12ff7391903235d3"
PROFILES = {
    "san": {"seed":711, "instruct":"A mature female radio dispatcher speaking native standard German. Calm, precise, composed, lightly warm low mezzo voice. Even measured delivery, natural pauses, clear consonants. A fictional emergency radio operator, serious but humane. No whispering, no shouting, no theatrical singing."},
    "mara": {"seed":1291, "instruct":"A woman in her thirties speaking native standard German. Grounded warm low alto voice, practical and confident forewoman. Firm, conversational delivery with a slight tired edge and clear consonants. Natural dialogue, no announcement voice, no whispering or shouting."},
    "branko": {"seed":3137, "instruct":"A man in his fifties speaking native standard German. Deep resonant bass-baritone, gently gravelly and weathered, calm protective guard. Deliberate unhurried conversational delivery with warm strength and clear consonants. Natural dialogue, no exaggerated acting, no shouting."},
    "ivo": {"seed":4027, "instruct":"A young adult man speaking native standard German. Light clear tenor voice, agile and curious mechanic, friendly and alert. Slightly brisk natural conversational rhythm, bright precise articulation. Natural dialogue, no announcer tone, no whispering or shouting."},
}


def master(wave, rate, speaker):
    import numpy as np
    from scipy.signal import butter, sosfilt
    wave = np.asarray(wave, dtype=np.float64).reshape(-1)
    if not np.isfinite(wave).all() or len(wave) < rate // 2:
        raise ValueError("Invalid speech waveform")
    # Remove DC/rumble; SAN keeps intelligible sibilants through a soft radio EQ.
    edges = [170, 6200] if speaker == "san" else [65, 9800]
    wave = sosfilt(butter(2, edges, btype="bandpass", fs=rate, output="sos"), wave)
    active = np.flatnonzero(np.abs(wave) > 0.006)
    if len(active) == 0:
        raise ValueError("Silent speech waveform")
    wave = wave[max(0, active[0] - int(rate * .08)):min(len(wave), active[-1] + int(rate * .18))]
    rms = np.sqrt(np.mean(wave * wave))
    gain = min(10 ** (-20 / 20) / max(rms, 1e-8), .79 / max(np.max(np.abs(wave)), 1e-8))
    wave *= gain
    fade = min(int(rate * .008), len(wave) // 4)
    wave[:fade] *= np.linspace(0, 1, fade)
    wave[-fade:] *= np.linspace(1, 0, fade)
    return wave.astype(np.float32)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="*", default=[], help="Generate only these basenames")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--device", default="cuda:0", help="Use cpu if the workstation GPU is busy")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--locale", choices=["de", "en"], default="de")
    args = parser.parse_args()
    import numpy as np
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download
    from qwen_tts import Qwen3TTSModel

    torch.set_num_threads(args.threads)
    destination = DEST if args.locale == "de" else DEST / args.locale
    language = "German" if args.locale == "de" else "English"
    profiles = {speaker: {**profile, "instruct":profile["instruct"] if args.locale == "de" else profile["instruct"].replace("native standard German", "native standard English with a neutral American accent")} for speaker, profile in PROFILES.items()}
    lines = json.loads((destination / "lines.json").read_text())["lines"]
    source_path = destination / "source.json"
    source = json.loads(source_path.read_text()) if source_path.exists() else {}
    source.update({
        "generator":"tools/generate_story_voices.py",
        "model":MODEL, "revision":REVISION, "model_license":"Apache-2.0",
        "model_source":f"https://huggingface.co/{MODEL}/tree/{REVISION}",
        "code_source":"https://github.com/QwenLM/Qwen3-TTS",
        "license_source":"https://www.apache.org/licenses/LICENSE-2.0",
        "qwen_tts_version":"0.1.1", "language":language, "locale":args.locale, "reference_audio":None,
        "torch_version":torch.__version__,
        "method":"Text-described fictional voices; no real-person voice reference or cloning.",
        "profiles":profiles,
        "mastering":"Mono PCM16; high-pass rumble removal; SAN soft 170–6200 Hz radio band; -20 dBFS RMS target limited by -2 dBFS peak headroom; 8 ms edge fades.",
    })
    files = source.setdefault("files", {})
    selected = [line for line in lines if (not args.only or Path(line["file"]).stem in args.only)
                and (args.force or not (destination / line["file"]).exists())]
    # Four early samples let every fictional voice be checked while the longer
    # generation job continues with the remaining authored lines.
    probes = ["san_story_open.wav", "mara_crew_reply.wav", "branko_crew_reply.wav", "ivo_crew_reply.wav"]
    selected.sort(key=lambda line: probes.index(line["file"]) if line["file"] in probes else len(probes))
    if not selected:
        print("All selected lines already generated.", flush=True)
        return
    path = snapshot_download(MODEL, revision=REVISION)
    model = Qwen3TTSModel.from_pretrained(path, device_map=args.device, dtype=torch.bfloat16 if args.device.startswith("cuda") else torch.float32, attn_implementation="sdpa")
    print(f"Loaded {MODEL}; generating {len(selected)} lines", flush=True)
    for line in selected:
        started = time.monotonic()
        profile = profiles[line["speaker"]]
        torch.manual_seed(profile["seed"])
        if args.device.startswith("cuda"): torch.cuda.manual_seed_all(profile["seed"])
        with torch.inference_mode():
            waves, rate = model.generate_voice_design(text=line["text"], language=language, instruct=profile["instruct"], max_new_tokens=1100, do_sample=True, top_p=.85, temperature=.7, repetition_penalty=1.08)
        wave = master(waves[0], rate, line["speaker"])
        output = destination / line["file"]
        temporary = output.with_suffix(".wav.pending")
        sf.write(temporary, wave, rate, subtype="PCM_16", format="WAV")
        temporary.replace(output)
        files[line["file"]] = {**line, "sample_rate":rate, "frames":len(wave), "duration":len(wave)/rate,
            "rms_dbfs":float(20*np.log10(np.sqrt(np.mean(wave**2)))), "peak_dbfs":float(20*np.log10(np.max(np.abs(wave)))),
            "sha256":hashlib.sha256(output.read_bytes()).hexdigest(), "seed":profile["seed"],
            "device":args.device, "dtype":"bfloat16" if args.device.startswith("cuda") else "float32"}
        temporary_source = source_path.with_suffix(".json.pending")
        temporary_source.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
        temporary_source.replace(source_path)
        print(f"{line['file']}: {len(wave)/rate:.2f}s speech in {time.monotonic()-started:.1f}s", flush=True)


if __name__ == "__main__":
    main()
