#!/usr/bin/env python3
"""Exercise courtyard defense through real ENet or local relay peers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request


def available_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--relay", action="store_true", help="Use a local memory-only WebSocket relay")
    parser.add_argument("--output", type=Path, help="Directory for logs and result evidence")
    options = parser.parse_args()
    output = options.output or root / "artifacts/perimeter" / ("relay" if options.relay else "direct")
    if not output.is_absolute(): output = root / output
    output.mkdir(parents=True, exist_ok=True)
    (output / "result.json").unlink(missing_ok=True)
    sources = ["scripts/game.gd", "scripts/expedition_controller.gd", "scripts/network_world.gd",
               "scripts/perimeter_catalog.gd", "scripts/perimeter_controller.gd",
               "scripts/perimeter_site.gd", "scripts/perimeter_replication.gd", "scripts/enemy.gd",
               "scripts/perimeter_art.gd", "scripts/courtyard_art.gd", "scripts/courtyard_art_catalog.gd",
               "assets/courtyard/modules_v1.png", "scripts/weather.gd", "scripts/rain_collision.gd",
               "scripts/actor_weather_geometry.gd", "scripts/weather_prop_surfaces.gd",
               "scripts/actor_wetness.gd", "scripts/surface_weather.gd",
               "tests/perimeter_network_peer.gd", "tests/perimeter_network_test.py"]
    source_before = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
    godot = os.environ.get("GODOT") or shutil.which("godot")
    assert godot, "Godot is required"
    command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(root),
               "--script", "tests/perimeter_network_peer.gd", "--", "--no-profile-save", "--no-upnp"]
    processes = {}
    relay_process = None
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="lastshift-perimeter-network-") as temporary:
        prefix = str(Path(temporary) / "run")
        try:
            relay_url = ""
            if options.relay:
                port = available_port()
                relay_url = f"ws://127.0.0.1:{port}/ws"
                with (output / "relay.log").open("w") as log:
                    relay_process = subprocess.Popen(["python3", "server/relay.py"], cwd=root,
                        env={**os.environ, "PORT":str(port), "RELAY_HOST":"127.0.0.1", "SOCIAL_DB":":memory:"},
                        stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline and relay_process.poll() is None:
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=.2) as response:
                            if response.status == 200: break
                    except OSError: time.sleep(.05)
                else: raise AssertionError((output / "relay.log").read_text())
            listen_port = available_port()
            discovery_port = available_port()
            for role in ("host", "guest"):
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix,
                       "LASTSHIFT_PERIMETER_RELAY":relay_url, "LASTSHIFT_TEST_PORT":str(listen_port),
                       "LASTSHIFT_TEST_DISCOVERY_PORT":str(discovery_port),
                       **{f"XDG_{kind}_HOME":str(Path(temporary) / role / kind.lower()) for kind in ("DATA", "CONFIG", "CACHE")}}
                with (output / f"network-{role}.log").open("w") as log:
                    processes[role] = subprocess.Popen(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
                if role == "host":
                    deadline = time.monotonic() + 12
                    while not Path(prefix + ".room.json").exists() and processes[role].poll() is None and time.monotonic() < deadline:
                        time.sleep(.05)
                    assert Path(prefix + ".room.json").exists(), (output / "network-host.log").read_text()
            deadline = time.monotonic() + 60
            while any(process.poll() is None for process in processes.values()) and time.monotonic() < deadline:
                time.sleep(.05)
            peers = []
            for role, process in processes.items():
                text = (output / f"network-{role}.log").read_text()
                assert process.poll() == 0, text
                assert f"NETWORK_GAMEPLAY_PASS {role}" in text, text
                assert not any(marker in text for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), text
                marker = re.search(rf"NETWORK_GAMEPLAY_PASS {role} checks=(\d+) failures=(\d+)", text)
                assert marker and int(marker[2]) == 0, text
                peers.append({"role":role, "checks":int(marker[1]), "passed":int(marker[1]), "exit_code":process.returncode})
            source_after = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources}
            assert source_before == source_after, "Tested courtyard sources changed during the run"
            result = {"mode":"local-relay" if options.relay else "direct-enet", "checks":sum(peer["checks"] for peer in peers),
                      "passed":sum(peer["passed"] for peer in peers), "peers":peers,
                      "elapsed_seconds":round(time.monotonic()-started, 3), "source_sha256":source_after,
                      "prepared_states":["waves disabled after actual online match start", "starter tier-1 mesh 120 HP",
                          "actual host damage to 83 HP, then real destruction to zero collision", "paid fence rebuild and finite sentry ammo",
                          "original fatal hit and crew KO/revive", "real guest transport disconnect and authenticated reconnect"]}
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(f"PERIMETER NETWORK: {result['passed']}/{result['checks']} passed ({result['mode']}).")
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay_process is not None:
                if relay_process.poll() is None: relay_process.terminate()
                try: relay_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    relay_process.kill()
                    relay_process.wait(timeout=5)


if __name__ == "__main__":
    main()
