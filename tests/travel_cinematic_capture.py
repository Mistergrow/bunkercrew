#!/usr/bin/env python3
"""Record complete native travel scenes with real Godot audio in isolated XDG."""
import array
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/travel-cinematics-20261004/sequence"
SOURCES = [
    "scripts/travel_cinematic_controller.gd", "scripts/travel_cinematic_panel.gd",
    "scripts/travel_cinematic_catalog.gd", "scripts/travel_cinematic_art.gd",
    "scripts/game.gd", "scripts/hud.gd", "scripts/network_input.gd", "scripts/audio.gd",
    "scripts/story_dialogue.gd", "scripts/expedition_controller.gd", "scripts/convoy_vehicle.gd",
    "scripts/convoy_journey.gd", "locales/de.json", "locales/en.json",
    "tests/travel_cinematic_sequence_capture.gd", "tests/travel_cinematic_capture.py",
]


def source_hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}


def command(arguments, **kwargs):
    return subprocess.run(arguments, check=True, cwd=ROOT, **kwargs)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    before = source_hashes()
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="bunkercrew-cinematic-movie-") as temporary:
        folder = Path(temporary)
        movie = folder / "native.avi"
        env = {**os.environ, **{f"XDG_{kind}_HOME": str(folder / kind.lower()) for kind in ("DATA", "CONFIG", "CACHE")}}
        arguments = [shutil.which("godot"), "--audio-driver", "Dummy", "--path", str(ROOT),
                     "--position", "-30000,-30000", "--resolution", "1440x900", "--disable-vsync",
                     "--fixed-fps", "60", "--write-movie", str(movie),
                     "--script", "tests/travel_cinematic_sequence_capture.gd", "--", "--no-profile-save", "--no-upnp"]
        with (OUTPUT / "native.log").open("w") as log:
            command(arguments, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        log = (OUTPUT / "native.log").read_text()
        assert not any(message in log for message in ("SCRIPT ERROR", "ERROR:", "WARNING:")), log
        sequence = json.loads((OUTPUT / "sequences.json").read_text())
        assert sequence["failures"] == 0 and len(sequence["sequences"]) == 3, sequence
        clips = []
        for scene in sequence["sequences"]:
            name = scene["id"]
            start = float(scene["start_seconds"])
            duration = float(scene["end_seconds"]) - start
            clip = OUTPUT / f"{name}.mp4"
            command(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", str(start), "-i", str(movie),
                     "-t", str(duration), "-c:v", "libx264", "-preset", "medium", "-crf", "18",
                     "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(clip)])
            poster = OUTPUT / f"{name}.png"
            command(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", "3.5", "-i", str(clip),
                     "-frames:v", "1", str(poster)])
            cue = OUTPUT / f"{name}-cue.png"
            cue_at = 1.02 if name == "storm" else 2.5
            command(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", str(cue_at), "-i", str(clip),
                     "-frames:v", "1", str(cue)])
            probe = json.loads(command(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(clip)],
                                       stdout=subprocess.PIPE).stdout)
            audio = next(stream for stream in probe["streams"] if stream["codec_type"] == "audio")
            video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
            assert audio["channels"] == 2 and video["width"] == 1440 and video["height"] == 900, probe
            pcm = command(["ffmpeg", "-v", "error", "-i", str(clip), "-vn", "-f", "s16le", "-ac", "2", "-ar", "48000", "pipe:1"],
                          stdout=subprocess.PIPE).stdout
            samples = array.array("h", pcm)
            rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
            peak = max(abs(value) for value in samples) / 32768
            assert rms > .00001 and peak < 1.0, (name, rms, peak)
            clips.append({"id": name, "file": clip.name, "poster": poster.name, "cue_still": cue.name,
                          "seconds": duration, "stereo": True, "rms_dbfs": round(20 * math.log10(rms), 2),
                          "peak_dbfs": round(20 * math.log10(peak), 2), "sha256": hashlib.sha256(clip.read_bytes()).hexdigest()})
    after = source_hashes()
    assert before == after, "Source changed during full native sequence proof"
    report = {"checks": sequence["checks"], "passed": sequence["passed"], "failures": 0,
              "clips": clips, "command": arguments, "elapsed_seconds": round(time.monotonic() - started, 2),
              "source_sha256": after, "fixture": sequence["fixture"],
              "audio_limit": "Original full engine stereo mix, including scene Voice/SFX and existing music. Clip RMS/peak validate present bounded output; they do not isolate a single stem or claim subjective listening preference."}
    (OUTPUT / "movie-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"TRAVEL CINEMATIC MOVIES: {sequence['passed']}/{sequence['checks']} passed; three native60Hz stereo films.")


if __name__ == "__main__":
    main()
