#!/usr/bin/env python3
"""Actual friend invite -> relay game -> lobby/combat chat -> mission reload."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/social/end-to-end"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    port = 24973
    command = [
        shutil.which("godot") or "godot", "--headless", "--debug",
        "--audio-driver", "Dummy", "--path", str(ROOT),
        "--script", "tests/social_end_to_end_peer.gd", "--",
        "--no-profile-save", "--no-upnp",
    ]
    processes: list[subprocess.Popen] = []
    with tempfile.TemporaryDirectory(prefix="bunkercrew-social-e2e-") as folder:
        fixture = Path(folder)
        with (OUTPUT / "relay.log").open("w") as log:
            relay = subprocess.Popen(
                [sys.executable, "server/relay.py"], cwd=ROOT,
                env={**os.environ, "PORT": str(port), "RELAY_HOST": "127.0.0.1",
                     "SOCIAL_DB": str(fixture / "social.sqlite3")},
                stdout=log, stderr=subprocess.STDOUT,
            )
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and relay.poll() is None:
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=0.2) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(0.05)
            else:
                raise AssertionError((OUTPUT / "relay.log").read_text())
            for role in ("host", "guest"):
                with (OUTPUT / f"{role}.log").open("w") as log:
                    processes.append(subprocess.Popen(
                        command, cwd=ROOT,
                        env={**os.environ, "BUNKERCREW_SOCIAL_ROLE": role,
                             "BUNKERCREW_SOCIAL_PATH": str(fixture / "flow"),
                             "BUNKERCREW_SOCIAL_RELAY": f"ws://127.0.0.1:{port}/ws",
                             "XDG_DATA_HOME": str(fixture / role)},
                        stdout=log, stderr=subprocess.STDOUT,
                    ))
            deadline = time.monotonic() + 65
            while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
                time.sleep(0.05)
            for role, process in zip(("host", "guest"), processes):
                text = (OUTPUT / f"{role}.log").read_text()
                assert process.poll() == 0 and f"SOCIAL END TO END {role}:" in text, text
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:", "Debugger Break")), text
            relay_log = (OUTPUT / "relay.log").read_text()
            assert "Traceback" not in relay_log, relay_log
            print("SOCIAL END TO END: actual friends, consent, presence, invite, game join, lobby/combat chat and restart passed.")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay.poll() is None:
                relay.terminate()
            relay.wait(timeout=5)


if __name__ == "__main__":
    main()
