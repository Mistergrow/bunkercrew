#!/usr/bin/env python3
"""Two authenticated ENet peers exchange synthetic speech through their real audio mixers."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "artifacts/network-hardening"
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    assert godot, "Godot is required"
    command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(root), "--script", "tests/voice_network_peer.gd", "--", "--no-profile-save", "--no-upnp"]
    processes = {}
    relay = None
    use_relay = "--relay" in sys.argv
    label = "voice-relay" if use_relay else "voice"
    with tempfile.TemporaryDirectory(prefix="lastshift-voice-network-") as temporary:
        prefix = str(Path(temporary) / "run")
        try:
            relay_url = ""
            if use_relay:
                with socket.socket() as reservation:
                    reservation.bind(("127.0.0.1", 0))
                    relay_port = reservation.getsockname()[1]
                with (output / "voice-relay-server.log").open("w") as log:
                    relay = subprocess.Popen([sys.executable, "server/relay.py"], cwd=root,
                        env={**os.environ, "RELAY_HOST": "127.0.0.1", "PORT": str(relay_port), "SOCIAL_DB": ":memory:"}, stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 10
                while True:
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{relay_port}/healthz", timeout=.3) as response:
                            assert response.status == 200
                        break
                    except OSError:
                        assert relay.poll() is None and time.monotonic() < deadline, "Local voice relay did not start"
                        time.sleep(.05)
                relay_url = f"ws://127.0.0.1:{relay_port}/ws"
            for role in ("host", "guest"):
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix, "XDG_DATA_HOME": str(Path(temporary) / role), "LASTSHIFT_VOICE_RELAY": relay_url}
                with (output / f"{label}-{role}.log").open("w") as log:
                    processes[role] = subprocess.Popen(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
                if role == "host":
                    deadline = time.monotonic() + 12
                    while not Path(prefix + ".room.json").exists() and processes[role].poll() is None and time.monotonic() < deadline:
                        time.sleep(.05)
                    assert Path(prefix + ".room.json").exists(), (output / f"{label}-host.log").read_text()
            deadline = time.monotonic() + 35
            while any(p.poll() is None for p in processes.values()) and time.monotonic() < deadline:
                time.sleep(.05)
            for role, process in processes.items():
                text = (output / f"{label}-{role}.log").read_text()
                assert process.poll() == 0, text
                assert f"NETWORK_GAMEPLAY_PASS {role}" in text, text
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), text
            print(f"VOICE {'RELAY' if use_relay else 'ENET'}: Authenticated speech reached both real audio mixers; no physical microphone was opened.")
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay is not None:
                relay.terminate()
                relay.wait(timeout=5)


if __name__ == "__main__":
    main()
