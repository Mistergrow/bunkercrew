#!/usr/bin/env python3
"""Four real processes with sender-bound ENet input, seats and reconnection."""

import os
import shutil
import subprocess
import sys
import urllib.request
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / (
    ("artifacts/solo-story/network/relay" if "--relay" in sys.argv else "artifacts/solo-story/network/direct")
    if "--story-recruits" in sys.argv else
    (
    "artifacts/expedition/network-four-relay"
    if "--relay" in sys.argv
    else "artifacts/expedition/network-four"
    )
)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    command = [
        shutil.which("godot"),
        "--headless",
        "--debug",
        "--audio-driver",
        "Dummy",
        "--path",
        str(ROOT),
        "--script",
        "tests/network_four_peer.gd",
        "--",
        "--no-profile-save",
        "--no-upnp",
    ]
    processes = []
    relay_process = None
    relay_url = ""
    if "--relay" in sys.argv:
        relay_url = "ws://127.0.0.1:24919/ws"
        with (OUTPUT / "relay.log").open("w") as log:
            relay_process = subprocess.Popen(
                [sys.executable, "server/relay.py"],
                cwd=ROOT,
                env={**os.environ, "PORT": "24919", "RELAY_HOST": "127.0.0.1", "SOCIAL_DB": ":memory:"},
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(
                    "http://127.0.0.1:24919/healthz", timeout=0.2
                ) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(0.05)
        else:
            relay_process.kill()
            relay_process.wait()
            raise AssertionError("Local relay did not start")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-four-") as folder:
        prefix = str(Path(folder) / "run")
        try:
            for slot in range(1, 5):
                role = "host" if slot == 1 else f"guest{slot}"
                env = {
                    **os.environ,
                    "LASTSHIFT_GAMEPLAY_ROLE": role,
                    "LASTSHIFT_PARTY_SLOT": str(slot),
                    "LASTSHIFT_PARTY_RELAY": relay_url,
                    "LASTSHIFT_PARTY_RECRUITS": "1" if "--story-recruits" in sys.argv else "",
                    "LASTSHIFT_GAMEPLAY_PATH": prefix,
                    "XDG_DATA_HOME": str(Path(folder) / role),
                }
                with (OUTPUT / f"{role}.log").open("w") as log:
                    process = subprocess.Popen(
                        command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT
                    )
                    processes.append(process)
                stage = ".room.json" if slot == 1 else f".joined{slot}.json"
                deadline = time.monotonic() + 15
                while (
                    not Path(prefix + stage).exists()
                    and process.poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.05)
                assert Path(prefix + stage).exists(), (
                    OUTPUT / f"{role}.log"
                ).read_text()
            deadline = time.monotonic() + 55
            while (
                any(p.poll() is None for p in processes) and time.monotonic() < deadline
            ):
                time.sleep(0.05)
            for slot, process in enumerate(processes, 1):
                role = "host" if slot == 1 else f"guest{slot}"
                text = (OUTPUT / f"{role}.log").read_text()
                assert (
                    process.poll() == 0 and f"NETWORK_GAMEPLAY_PASS {role}" in text
                ), text
                assert not any(
                    marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")
                ), text
            print("FOUR PLAYERS: four independent processes passed.")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay_process is not None:
                relay_process.terminate()
                relay_process.wait(timeout=5)


if __name__ == "__main__":
    main()
