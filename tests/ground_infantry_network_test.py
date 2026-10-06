#!/usr/bin/env python3
"""Exercise combat polish through two real ENet peers with isolated local saves."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def main():
    root = Path(__file__).resolve().parents[1]
    output = Path(os.environ.get("LASTSHIFT_INFANTRY_OUTPUT", str(root / "artifacts/ground-reinforcements")))
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    assert godot, "Godot is required"
    peer_script = os.environ.get("LASTSHIFT_INFANTRY_PEER", "tests/ground_infantry_network_peer.gd")
    command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(root),
               "--script", peer_script, "--", "--no-profile-save", "--no-upnp"]
    processes = {}
    with tempfile.TemporaryDirectory(prefix="lastshift-human-network-") as temporary:
        prefix = str(Path(temporary) / "run")
        try:
            for role in ("host", "guest"):
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix,
                       "XDG_DATA_HOME": str(Path(temporary) / role)}
                with (output / f"network-{role}.log").open("w") as log:
                    processes[role] = subprocess.Popen(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
                if role == "host":
                    deadline = time.monotonic() + 12
                    while not Path(prefix + ".room.json").exists() and processes[role].poll() is None and time.monotonic() < deadline:
                        time.sleep(.05)
                    assert Path(prefix + ".room.json").exists(), (output / "network-host.log").read_text()
            deadline = time.monotonic() + 45
            while any(process.poll() is None for process in processes.values()) and time.monotonic() < deadline:
                time.sleep(.05)
            for role, process in processes.items():
                text = (output / f"network-{role}.log").read_text()
                assert process.poll() == 0, text
                assert f"NETWORK_GAMEPLAY_PASS {role}" in text, text
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), text
            print(f"ENET INTEGRATION: {peer_script}, both peer checks passed without engine diagnostics.")
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
