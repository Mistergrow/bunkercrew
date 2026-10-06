#!/usr/bin/env python3
"""Record the actual four-player foundry and native mixed audio with Godot."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    destination = root / "artifacts/music-dance-gameplay/render"
    destination.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot or not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise SystemExit("Godot, ffmpeg and ffprobe are required, with a graphical display.")
    movie = destination / "live-game.avi"
    video = destination / "live-game.mp4"
    with tempfile.TemporaryDirectory(prefix="bunkercrew-dance-capture-") as profile:
        with (destination.parent / "render.log").open("w", encoding="utf-8") as output:
            result = subprocess.run([godot, "--disable-vsync", "--path", str(root), "--script",
                                     "tests/music_dance_gameplay_capture.gd", "--write-movie", str(movie),
                                     "--", "--no-profile-save", "--no-upnp"], cwd=root,
                                    env={**os.environ, "XDG_DATA_HOME": profile}, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=180)
    log = (destination.parent / "render.log").read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(error in log for error in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    verification = json.loads((destination / "verification.json").read_text())
    if verification["failures"] or not verification["actual_native_audio"] or not verification["floorwork_seen"]:
        raise SystemExit("Actual rendered gameplay verification failed.")
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(movie),
                    "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(video)], check=True)
    media = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                    "stream=codec_name,width,height,sample_rate,channels,duration,nb_frames",
                                    "-show_entries", "format=duration,size", "-of", "json", str(video)], text=True)
    (destination / "media.json").write_text(media, encoding="utf-8")
    streams = json.loads(media)["streams"]
    if not any(stream.get("codec_name")=="aac" and stream.get("channels")==2 for stream in streams):
        raise SystemExit("The actual movie must contain Godot's mixed stereo audio.")
    with (destination / "audio-peaks.log").open("w", encoding="utf-8") as output:
        subprocess.run(["ffmpeg", "-hide_banner", "-i", str(video), "-af", "volumedetect",
                        "-vn", "-sn", "-dn", "-f", "null", "-"], stdout=output,
                       stderr=subprocess.STDOUT, check=True)
    # The encoded, inspected MP4 retains actual game sound; no raw 375 MB movie
    # is needed in the gallery. Delete only this runner's intermediate file.
    movie.unlink()
    print(f"Actual gameplay music/dance capture passed; video: {video}")


if __name__ == "__main__":
    main()
