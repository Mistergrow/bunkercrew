#!/usr/bin/env python3
"""Verify delivered native clip timing and decoded motion independently."""
from __future__ import annotations

from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/background-surfaces/native"


def output(command: list[str]) -> str:
    return subprocess.check_output(command, cwd=ROOT, text=True)


def hashes(path: Path, filters: str = "") -> list[str]:
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path)]
    if filters:
        command += ["-vf", filters]
    command += ["-an", "-f", "framemd5", "-"]
    return [line.rsplit(",", 1)[-1].strip() for line in output(command).splitlines()
            if line and not line.startswith("#")]


def main() -> None:
    manifest = json.loads((OUTPUT / "capture-manifest.json").read_text())
    report: list[dict] = []
    failures: list[str] = []
    for media in manifest["media"]:
        for size in ("full", "surface"):
            path = OUTPUT / media[size]
            metadata = json.loads(output([
                "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                "-show_entries", "stream=avg_frame_rate,r_frame_rate,nb_read_frames,width,height:format=duration",
                "-of", "json", str(path),
            ]))
            stream = metadata["streams"][0]
            fps = float(Fraction(stream["avg_frame_rate"]))
            frames = int(stream["nb_read_frames"])
            duration = float(metadata["format"]["duration"])
            decoded = hashes(path)
            unique = len(set(decoded))
            valid_time = fps == 60 and frames == 180 and abs(duration - 3.0) < 0.001
            valid_motion = media["comparison"] == "before" or unique > 1
            if not valid_time:
                failures.append(f"{path.name}: expected 60FPS,180 frames,3 seconds; got {fps}/{frames}/{duration}")
            if not valid_motion:
                failures.append(f"{path.name}: animated final surface has only one decoded frame")
            report.append({"file": path.name, "fps": fps, "frames": frames,
                           "duration_seconds": duration, "width": stream["width"],
                           "height": stream["height"], "decoded_unique_frames": unique,
                           "normal_speed": valid_time, "actual_motion": valid_motion,
                           "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
            print(path.name, f"{fps:g}FPS {frames}frames {duration:g}s {unique}distinct frames", flush=True)
    raw = OUTPUT / "native-source-retained.avi"
    source_records: list[dict] = []
    if raw.exists():
        native = json.loads((OUTPUT / "verification.json").read_text())
        all_native = hashes(raw)
        for segment in native["video_segments"]:
            decoded = all_native[segment['start_frame']:segment['end_frame']]
            unique = len(set(decoded))
            if len(decoded) != 180 or (segment["mode"] == "after" and unique <= 1):
                failures.append(f"Native source {segment['id']}/{segment['mode']} lacks 180 frames or real motion")
            source_records.append({"scene": segment["id"], "mode": segment["mode"],
                                   "native_source_frames": len(decoded), "native_distinct_frames": unique})
    result = {"checks": len(report) * 2 + len(source_records), "failures": failures,
              "clips": report, "source_segments": source_records,
              "prepared": "ffprobe frame count/rate/duration and independently decoded frame hashes; final clips require motion; former clips may correctly be stationary; native Godot AVI source independently checked when retained."}
    (OUTPUT / "video-verification.json").write_text(json.dumps(result, indent=2) + "\n")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"VIDEO SURFACES: {result['checks']} checks, 0 failures")


if __name__ == "__main__":
    main()
