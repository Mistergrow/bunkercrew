#!/usr/bin/env python3
"""Three real ENet game processes; SIGSTOP simulates an abrupt silent loss."""
import json
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/network-followup/blackhole"

def wait(path, processes, timeout=20):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if path.exists():
            return json.loads(path.read_text())
        assert all(p.poll() is None for p in processes), "A fixture process exited early"
        time.sleep(.025)
    raise AssertionError(f"Timeout waiting for {path.name}")

def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Directory for isolated peer logs and verification")
    options = parser.parse_args()
    if options.output is not None:
        OUTPUT = options.output if options.output.is_absolute() else ROOT / options.output
    OUTPUT.mkdir(parents=True, exist_ok=True)
    processes = []
    logs = []
    with tempfile.TemporaryDirectory(prefix="bunkercrew-blackhole-") as folder:
        prefix = str(Path(folder) / "sync")
        try:
            for slot in [1, 2, 3]:
                log = (OUTPUT / f"slot{slot}.log").open("w")
                logs.append(log)
                env = {**os.environ, "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_GAMEPLAY_PATH": prefix,
                       **{f"XDG_{kind}_HOME": str(Path(folder) / str(slot) / kind.lower()) for kind in ("DATA", "CONFIG", "CACHE")}}
                command = [shutil.which("godot"), "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "tests/network_blackhole_peer.gd", "--", "--no-profile-save", "--no-upnp"]
                process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                processes.append(process)
                if slot == 1:
                    wait(Path(prefix + ".room.json"), processes)
                else:
                    # Seats belong to authenticated join order, not process
                    # creation order. Confirm one join before starting another.
                    joined = wait(Path(prefix + f".joined{slot}.json"), processes)
                    assert joined["player_id"] == slot, joined
            for slot in [1, 2, 3]:
                wait(Path(prefix + f".started{slot}.json"), processes)
            began = time.monotonic()
            processes[1].send_signal(signal.SIGSTOP)
            Path(prefix + ".stopped.json").write_text('{"ready":true}')
            result = wait(Path(prefix + ".detected.json"), [processes[0], processes[2]], 8)
            elapsed = time.monotonic() - began
            healthy = wait(Path(prefix + ".healthy.json"), [processes[2]], 3)
            assert result["failures"] == healthy["failures"] == 0
            assert 3.8 < elapsed < 6.5, elapsed
            for process in [processes[0], processes[2]]:
                assert process.wait(timeout=10) == 0
            # The intentionally stopped guest also loaded a real game before
            # SIGSTOP. Its startup diagnostics must not disappear from the gate.
            for slot in [1, 2, 3]:
                text = (OUTPUT / f"slot{slot}.log").read_text()
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), text
            (OUTPUT / "verification.json").write_text(json.dumps({"mode":"direct ENet", "players":3,"failure":"SIGSTOP guest 2 without leave or socket close", "detection_seconds":round(elapsed,3),"host":result,"healthy_guest":healthy}, indent=2))
            print(f"BLACKHOLE PASS: silent loss detected after {elapsed:.3f}s; healthy guest stays connected")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.send_signal(signal.SIGCONT)
                    process.kill()
                process.wait(timeout=10)
            for log in logs:
                log.close()

if __name__ == "__main__":
    main()
