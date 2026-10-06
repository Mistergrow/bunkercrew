#!/usr/bin/env python3
"""Two real peers: boarding, driving, remote repair/rejoin and destination."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    relay_mode = "--relay" in sys.argv
    output = ROOT / "artifacts/convoy-journey" / ("network-relay" if relay_mode else "network-direct")
    output.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    assert godot, "Godot is required"
    command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--script", "tests/expedition_network_peer.gd", "--", "--no-profile-save", "--no-upnp"]
    relay = None
    peers = {}
    with tempfile.TemporaryDirectory(prefix="bunkercrew-journey-network-") as folder:
        temporary = Path(folder)
        prefix = str(temporary / "run")
        try:
            relay_url = ""
            if relay_mode:
                relay_url = "ws://127.0.0.1:24931/ws"
                with (output / "relay.log").open("w") as log:
                    relay = subprocess.Popen([sys.executable, "server/relay.py"], cwd=ROOT,
                        env={**os.environ, "PORT":"24931", "RELAY_HOST":"127.0.0.1", "SOCIAL_DB":":memory:"},
                        stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:24931/healthz", timeout=.2) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        time.sleep(.05)
                else:
                    raise AssertionError("Local relay did not start")
            for role in ["host", "guest"]:
                profile = temporary / role
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE":role, "LASTSHIFT_GAMEPLAY_PATH":prefix,
                       "LASTSHIFT_CONVOY_RELAY":relay_url, "LASTSHIFT_TEST_PORT":"24887",
                       "LASTSHIFT_TEST_DISCOVERY_PORT":"24888", "XDG_DATA_HOME":str(profile / "data"),
                       "XDG_CONFIG_HOME":str(profile / "config"), "XDG_CACHE_HOME":str(profile / "cache")}
                with (output / (role + ".log")).open("w") as log:
                    peers[role] = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                if role == "host":
                    deadline = time.monotonic() + 15
                    while not Path(prefix + ".room.json").exists() and peers[role].poll() is None and time.monotonic() < deadline:
                        time.sleep(.05)
                    assert Path(prefix + ".room.json").exists(), (output / "host.log").read_text()
            deadline = time.monotonic() + 110
            while any(peer.poll() is None for peer in peers.values()) and time.monotonic() < deadline:
                time.sleep(.05)
            for role, peer in peers.items():
                result = (output / (role + ".log")).read_text()
                assert peer.poll() == 0 and "NETWORK_GAMEPLAY_PASS " + role in result, result
                assert not any(marker in result for marker in ["ERROR:", "SCRIPT ERROR", "WARNING:"]), result
            print("CONVOY NETWORK:", "relay" if relay_mode else "ENet", "boarding, ignition, remote tire repair, real reconnect, cache and destination passed.")
        finally:
            for peer in peers.values():
                if peer.poll() is None:
                    peer.kill()
                peer.wait(timeout=5)
            if relay is not None:
                relay.terminate()
                relay.wait(timeout=5)

if __name__ == "__main__":
    main()
