#!/usr/bin/env python3
"""Run music regressions in isolated profiles, rejecting logged engine errors."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/music-beat-refresh/qa"
TESTS = [
    "music_beat_clock_test", "music_beat_continuity_test", "live_music_test", "live_music_native_test",
    "live_music_native_profiles_test", "live_music_integration_test",
    "audio_test", "audio_defaults_test", "audio_settings_test",
    "audio_teardown_test", "menu_music_audio_test", "rave_music_gameplay_test",
    "music_calibration_ui_test", "music_calibration_transport_test", "audio_world_score_test",
    "audio_network_score_test", "audio_listener_rebuild_test", "audio_exit_drain_test",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", help="Comma-separated test stems")
    args = parser.parse_args()
    selected = args.only.split(",") if args.only else TESTS
    if any(item not in TESTS for item in selected):
        parser.error("Unknown music regression")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix="bunkercrew-music-qa-") as profile:
        environment = os.environ.copy()
        environment.update({"XDG_DATA_HOME":profile+"/data", "XDG_CONFIG_HOME":profile+"/config", "XDG_CACHE_HOME":profile+"/cache"})
        for name in selected:
            start = time.monotonic()
            command = ["godot", "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "tests/"+name+".gd", "--", "--no-profile-save", "--no-upnp"]
            try:
                result = subprocess.run(command, cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=150)
                output, code = result.stdout, result.returncode
            except subprocess.TimeoutExpired as error:
                output = (error.stdout or b"").decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout or ""
                code = 124
            (OUTPUT / (name+".log")).write_text(output)
            errors = [line for line in output.splitlines() if "ERROR:" in line or "WARNING:" in line]
            counts = re.findall(r"(\d+)\s*/\s*(\d+)\s+(?:checks\s+)?passed", output, flags=re.I)
            if not counts:
                totals = re.findall(r"(\d+)\s+passed,\s*(\d+)\s+failed", output, flags=re.I)
                counts = [(passed,str(int(passed)+int(failed))) for passed,failed in totals]
            record = {"test":name, "passed":code==0 and not errors, "exit_code":code,
                      "seconds":round(time.monotonic()-start,3), "errors":errors,
                      "assertions":int(counts[-1][1]) if counts else None,
                      "successful_assertions":int(counts[-1][0]) if counts else None}
            records.append(record)
            print(("PASS " if record["passed"] else "FAIL ")+name+" "+str(record["seconds"])+"s", flush=True)
            if errors: print("\n".join(errors[:8]), flush=True)
    report = {"passed_tests":sum(item["passed"] for item in records), "failed_tests":sum(not item["passed"] for item in records),
              "assertions_reported":sum(item["assertions"] or 0 for item in records), "tests":records,
              "fixture":"Headless Godot 4.7.2, Dummy audio, temporary XDG directories, --no-profile-save --no-upnp. No physical audio-device or listening assessment."}
    (OUTPUT / ("verification.json" if not args.only else "verification-subset.json")).write_text(json.dumps(report, indent=2)+"\n")
    print("MUSIC REFRESH QA: %d/%d tests, %d reported assertions" % (report["passed_tests"],len(records),report["assertions_reported"]), flush=True)
    return int(report["failed_tests"]>0)


if __name__ == "__main__":
    raise SystemExit(main())
