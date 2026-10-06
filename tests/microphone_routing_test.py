#!/usr/bin/env python3
"""Synthetic PulseAudio microphone test; never reads the physical microphone.
Creates an isolated tone source and a separate silent output sink, removes both.
"""
import array
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]

def pactl(*args):
    return subprocess.check_output(["pactl", *args], text=True).strip()

def main():
    for tool in ("pactl", "paplay", "godot"):
        if not shutil.which(tool):
            raise SystemExit(f"Required local test tool missing: {tool}")
    modules = []
    player = None
    initial_source = pactl("get-default-source")
    initial_sink = pactl("get-default-sink")
    try:
        modules.append(pactl("load-module", "module-null-sink", "sink_name=lastshift_test_input", "rate=48000", "channels=2"))
        modules.append(pactl("load-module", "module-null-sink", "sink_name=lastshift_test_output", "rate=48000", "channels=2"))
        modules.append(pactl("load-module", "module-remap-source", "master=lastshift_test_input.monitor", "source_name=lastshift_test_microphone"))
        with tempfile.TemporaryDirectory(prefix="lastshift-mic-") as folder:
            tone = Path(folder) / "synthetic-tone.wav"
            samples = array.array("h", (int(10000 * math.sin(2 * math.pi * 440 * i / 48000)) for i in range(48000 * 20)))
            with wave.open(str(tone), "wb") as output:
                output.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
                output.writeframes(samples.tobytes())
            player = subprocess.Popen(["paplay", "--device=lastshift_test_input", str(tone)])
            env = os.environ.copy()
            env["PULSE_SINK"] = "lastshift_test_output"
            env["PULSE_SOURCE"] = "lastshift_test_output.monitor"
            probe = subprocess.Popen(["parec", "--raw", "--device=lastshift_test_microphone", "--format=float32le", "--channels=1", "--rate=48000"], stdout=subprocess.PIPE)
            try:
                probe.communicate(timeout=3.0)
            except subprocess.TimeoutExpired:
                probe.terminate()
            raw, _ = probe.communicate(timeout=3)
            floats = array.array("f")
            floats.frombytes(raw[:len(raw) // 4 * 4])
            energy = math.sqrt(sum(float(value) ** 2 for value in floats) / max(1, len(floats)))
            print(f"Isolated Pulse source RMS: {energy:.6f}; samples={len(floats)}")
            if energy < .03:
                raise RuntimeError("Synthetic Pulse source has no test tone")
            result = subprocess.run(["godot", "--headless", "--audio-driver", "PulseAudio", "--path", str(ROOT), "--script", "tests/microphone_routing_test.gd", "--", "--no-profile-save", "--synthetic-device"], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
            print(result.stdout, end="")
            log = ROOT / "artifacts/microphone/audio-routing.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(result.stdout)
            return result.returncode or int("FAIL" in result.stdout or "SCRIPT ERROR" in result.stdout or "ERROR:" in result.stdout or "WARNING:" in result.stdout)
    finally:
        if player is not None:
            player.terminate()
            player.wait(timeout=5)
        for module in reversed(modules):
            subprocess.run(["pactl", "unload-module", module], check=True)
        # Neither test capture nor playback changes the user's default routes.
        assert pactl("get-default-source") == initial_source, "Default source changed during test"
        assert pactl("get-default-sink") == initial_sink, "Default sink changed during test"

if __name__ == "__main__":
    raise SystemExit(main())
