#!/usr/bin/env python3
"""Write an online checkpoint, restart both processes, resume every boundary."""

import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARTY_SIZE = 4 if "--four" in sys.argv else 2
OUTPUT = ROOT / (
    "artifacts/expedition/network-resume-four"
    if PARTY_SIZE == 4
    else "artifacts/expedition/network-resume"
)
CASES = [
    "write",
    "preparation",
    "travel",
    "stop",
    "occupation",
    "failed",
    "after_stop",
    "defense",
    "solo",
    "complete",
    "backup",
    "corrupt",
]


if PARTY_SIZE == 4:
    CASES = ["write", "after_stop", "solo", "complete"]


def run_pair(case, temporary):
    godot = os.environ.get("GODOT") or shutil.which("godot")
    assert godot, "Godot is required"
    command = [
        godot,
        "--headless",
        "--debug",
        "--audio-driver",
        "Dummy",
        "--path",
        str(ROOT),
        "--script",
        "tests/expedition_resume_network_peer.gd",
        "--",
        "--no-profile-save",
        "--no-upnp",
    ]
    prefix = temporary / case
    processes = {}
    try:
        for slot in range(1, PARTY_SIZE + 1):
            role = "host" if slot == 1 else f"guest{slot}"
            peer_role = "host" if slot == 1 else "guest"
            env = {
                **os.environ,
                "LASTSHIFT_GAMEPLAY_ROLE": peer_role,
                "LASTSHIFT_PARTY_SLOT": str(slot),
                "LASTSHIFT_RESUME_PLAYERS": str(PARTY_SIZE),
                "LASTSHIFT_GAMEPLAY_PATH": str(prefix),
                "LASTSHIFT_RESUME_CASE": case,
                "LASTSHIFT_RESUME_SAVES": str(temporary / "saves"),
                "XDG_DATA_HOME": str(temporary / (case + "-" + role)),
                "LASTSHIFT_TEST_PORT": "24897",
                "LASTSHIFT_TEST_DISCOVERY_PORT": "24898",
            }
            with (OUTPUT / f"{case}-{role}.log").open("w") as log:
                processes[role] = subprocess.Popen(
                    command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT
                )
            if role == "host" or PARTY_SIZE > 2:
                barrier = ".room.json" if slot == 1 else f".joined{slot}.json"
                deadline = time.monotonic() + 12
                while (
                    not Path(str(prefix) + barrier).exists()
                    and processes[role].poll() is None
                    and time.monotonic() < deadline
                ):
                    time.sleep(0.05)
                assert Path(str(prefix) + barrier).exists(), (
                    OUTPUT / f"{case}-{role}.log"
                ).read_text()
        deadline = time.monotonic() + 45
        while (
            any(p.poll() is None for p in processes.values())
            and time.monotonic() < deadline
        ):
            time.sleep(0.05)
        for role, process in processes.items():
            result = (OUTPUT / f"{case}-{role}.log").read_text()
            assert (
                process.poll() == 0
                and f"NETWORK_GAMEPLAY_PASS {'host' if role == 'host' else 'guest'}"
                in result
            ), result
            assert not any(
                marker in result for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")
            ), result
        print("PASS durable online resume:", case, flush=True)
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lastshift-online-resume-") as directory:
        temporary = Path(directory)
        (temporary / "saves").mkdir()
        for case in CASES:
            run_pair(case, temporary)
    print(
        f"ONLINE CAMPAIGN RESUME: all {len(CASES)} cases passed using fresh {PARTY_SIZE}-player processes."
    )


if __name__ == "__main__":
    main()
