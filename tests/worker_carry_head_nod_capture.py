#!/usr/bin/env python3
"""Record real loaded gameplay; trim only the original score's cinematic preroll."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "artifacts/carry-head-nod"
    output.mkdir(parents=True, exist_ok=True)
    movie = output / "loaded-head-nod.avi"
    video = output / "loaded-head-nod.mp4"
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot or not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise SystemExit("Godot, ffmpeg, ffprobe and a graphical display are required")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-carry-head-nod-") as profile:
        with (output / "render.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(
                [godot, "--disable-vsync", "--path", str(root), "--script",
                 "tests/worker_carry_head_nod_capture.gd", "--write-movie", str(movie),
                 "--", "--no-profile-save", "--no-upnp"], cwd=root,
                env={**os.environ, "XDG_DATA_HOME": profile}, stdout=log,
                stderr=subprocess.STDOUT, timeout=180)
    log = (output / "render.log").read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(issue in log for issue in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    verification = json.loads((output / "render-verification.json").read_text())
    if verification["failures"] or not verification["actual_native_audio"] or verification["maximum_grip_error"] > 0.00001:
        raise SystemExit("Actual loaded gameplay verification failed")
    # No music is added or remixed: cut the original rendered preroll together
    # with its own stereo game sound and retain the visible dip/return sequence.
    start = max(0.0, verification["capture_start_seconds"] - 0.15)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", str(start),
                    "-i", str(movie), "-t", "16.2", "-c:v", "libx264", "-preset", "medium",
                    "-crf", "19", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(video)], check=True)
    media = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                     "stream=codec_name,width,height,sample_rate,channels,nb_frames",
                                     "-show_entries", "format=duration,size", "-of", "json", str(video)], text=True)
    (output / "media.json").write_text(media, encoding="utf-8")
    if not any(stream.get("codec_name") == "aac" and stream.get("channels") == 2 for stream in json.loads(media)["streams"]):
        raise SystemExit("The actual clip must retain Godot's mixed stereo audio")
    with (output / "audio-peaks.log").open("w", encoding="utf-8") as audio_log:
        subprocess.run(["ffmpeg", "-hide_banner", "-i", str(video), "-af", "volumedetect",
                        "-vn", "-sn", "-dn", "-f", "null", "-"], stdout=audio_log,
                       stderr=subprocess.STDOUT, check=True)
    movie.unlink()
    print(f"Actual loaded gameplay capture passed: {video}")


if __name__ == "__main__":
    main()
