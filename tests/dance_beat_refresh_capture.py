#!/usr/bin/env python3
"""Render real native audible choreography; retain Godot's original stereo mix."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "artifacts/music-beat-refresh/dance"
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot or not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise SystemExit("Godot, ffmpeg, ffprobe and a graphical display are required")
    movie = output / "native-dance.avi"
    video = output / "native-dance.mp4"
    with tempfile.TemporaryDirectory(prefix="bunkercrew-dance-refresh-") as profile:
        environment = {**os.environ, "XDG_DATA_HOME": profile,
                       "XDG_CONFIG_HOME": profile, "XDG_CACHE_HOME": profile}
        with (output / "native-capture.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(
                [godot, "--disable-vsync", "--audio-driver", "Dummy", "--path", str(root),
                 "--script", "tests/dance_beat_refresh_native.gd", "--write-movie", str(movie),
                 "--", "--no-profile-save", "--no-upnp"], cwd=root,
                env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    log = (output / "native-capture.log").read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(issue in log for issue in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    report = json.loads((output / "native-verification.json").read_text())
    if (report["failures"] or not report["actual_native_audio"]
            or report["max_visual_foot_error_pixels"] > 0.00001
            or report["authoritative_tempo_frames"] != report["frames_after_mature_kicks"]):
        raise SystemExit("Native audio, tempo or painted foot synchronization failed")
    start = max(0.0, report["capture_start_seconds"] - 0.12)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", str(start),
                    "-i", str(movie), "-t", str(16.0 * 60.0 / report["bpm"] + 0.15), "-c:v", "libx264", "-preset", "medium",
                    "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(video)], check=True)
    probe = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                     "stream=codec_name,width,height,sample_rate,channels,nb_frames",
                                     "-show_entries", "format=duration,size", "-of", "json", str(video)], text=True)
    (output / "media.json").write_text(probe, encoding="utf-8")
    if not any(stream.get("codec_name") == "aac" and stream.get("channels") == 2
               for stream in json.loads(probe)["streams"]):
        raise SystemExit("The clip must preserve actual Godot stereo audio")
    with (output / "audio-peaks.log").open("w", encoding="utf-8") as audio_log:
        subprocess.run(["ffmpeg", "-hide_banner", "-i", str(video), "-af", "volumedetect",
                        "-vn", "-sn", "-dn", "-f", "null", "-"], stdout=audio_log,
                       stderr=subprocess.STDOUT, check=True)
    movie.unlink()
    print(f"Native dance refresh capture passed: {video}")


if __name__ == "__main__":
    main()
