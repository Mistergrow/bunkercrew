#!/usr/bin/env python3
"""Twelve actual aircraft over direct ENet or a local production-code relay.

Every peer runs the game in its own process and isolated user directories.
Coordination files contain phase barriers/expected scalars, never snapshots.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--players", choices=(2, 4), type=int, default=2)
    parser.add_argument("--relay", action="store_true")
    args = parser.parse_args()
    mode = "relay" if args.relay else "direct"
    output = ROOT / f"artifacts/audio-air-review/network/{args.players}-{mode}"
    output.mkdir(parents=True, exist_ok=True)
    godot = shutil.which("godot")
    assert godot, "Godot required"
    command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "tests/air_network_peer.gd", "--", "--no-profile-save", "--no-upnp"]
    processes = []
    relay = None
    relay_url = ""
    try:
        if args.relay:
            relay_url = "ws://127.0.0.1:24929/ws"
            with (output / "relay.log").open("w") as log:
                relay = subprocess.Popen([shutil.which("python3"), "server/relay.py"], cwd=ROOT, env={**os.environ, "PORT": "24929", "RELAY_HOST": "127.0.0.1", "SOCIAL_DB": ":memory:"}, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic()+8
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen("http://127.0.0.1:24929/healthz", timeout=.25) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(.05)
            else:
                raise AssertionError("Isolated relay startup failed")
        with tempfile.TemporaryDirectory(prefix="bunkercrew-air-network-") as folder:
            prefix = str(Path(folder)/"run")
            for slot in range(1,args.players+1):
                role = "host" if slot == 1 else f"guest{slot}"
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix, "BUNKERCREW_AIR_SLOT": str(slot), "BUNKERCREW_AIR_PARTY": str(args.players), "BUNKERCREW_AIR_RELAY": relay_url, "XDG_DATA_HOME": str(Path(folder)/role/"data"), "XDG_CONFIG_HOME": str(Path(folder)/role/"config"), "XDG_CACHE_HOME": str(Path(folder)/role/"cache")}
                log_path = output/f"{role}.log"
                with log_path.open("w") as log:
                    process = subprocess.Popen(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
                processes.append((role,process,log_path))
                barrier = Path(prefix+(".room.json" if slot == 1 else f".joined{slot}.json"))
                deadline = time.monotonic()+15
                while not barrier.exists() and process.poll() is None and time.monotonic()<deadline:
                    time.sleep(.04)
                assert barrier.exists(), log_path.read_text(errors="replace")
            deadline = time.monotonic()+55
            while any(process.poll() is None for _,process,_ in processes) and time.monotonic()<deadline:
                time.sleep(.05)
            reports = []
            for role,process,path in processes:
                text = path.read_text(errors="replace")
                assert process.poll() == 0, text
                assert f"NETWORK_GAMEPLAY_PASS {role}" in text, text
                assert not any(marker in text for marker in ("SCRIPT ERROR", "ERROR:", "WARNING:")), text
                match = re.search(r"checks=(\d+) failures=0",text)
                assert match, text
                reports.append({"role":role,"checks":int(match[1]),"log":path.name})
            report = {"mode":mode,"players":args.players,"aircraft_types":12,"prepared_state":"Three batches of four real aircraft, stopped authoritative AI and ordnance for deterministic snapshot observation; shots, damage, death and transport loss use production APIs.","checks":sum(row["checks"] for row in reports),"peers":reports}
            (output/"report.json").write_text(json.dumps(report,indent=2)+"\n")
            print(f"AIR NETWORK: {args.players} players {mode}, {report['checks']} checks; twelve types, authority, spatial events and reconnect passed")
    finally:
        for _,process,_ in processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        if relay:
            if relay.poll() is None:
                relay.terminate()
            relay.wait(timeout=5)


if __name__ == "__main__":
    main()
