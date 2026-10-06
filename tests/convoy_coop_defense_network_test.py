#!/usr/bin/env python3
"""Four actual isolated peers; local ENet or local memory-only WebSocket relay."""
import json
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/convoy-defense-20261004/network" / ("relay" if "--relay" in sys.argv else "direct")
SOURCES = ["scripts/convoy_vehicle.gd", "scripts/convoy_journey.gd", "scripts/convoy_defender.gd", "scripts/expedition_controller.gd",
    "scripts/convoy_seat.gd", "scripts/convoy_audio.gd", "scripts/convoy_presentation.gd", "scripts/convoy_vehicle_art.gd", "scripts/worker_weapon.gd",
    "scripts/convoy_air_encounter_catalog.gd", "scripts/convoy_air_encounters.gd",
    "scripts/travel_cinematic_controller.gd", "scripts/travel_cinematic_panel.gd", "scripts/travel_cinematic_catalog.gd", "scripts/travel_cinematic_art.gd",
    "scripts/network_input.gd", "scripts/audio.gd", "scripts/story_dialogue.gd", "locales/de.json", "locales/en.json",
    "scripts/enemy.gd", "scripts/game.gd", "scripts/player.gd", "scripts/hud.gd", "scripts/campaign_state.gd",
    "scripts/network_world.gd", "scripts/network_session.gd", "scripts/network_protocol.gd", "scripts/network_replication_schema.gd",
    "tests/convoy_coop_defense_peer.gd", "tests/convoy_coop_defense_network_test.py"]


def source_hashes():
    return {path:hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in SOURCES}


def wait_path(path, process, log, seconds=18):
    deadline = time.monotonic() + seconds
    while not path.exists() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(.05)
    if not path.exists():
        raise AssertionError(log.read_text())


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--relay", action="store_true", help="Use a local memory-only relay instead of direct ENet")
    parser.add_argument("--output", type=Path, help="Report folder; relative paths are resolved from the repository root")
    options = parser.parse_args()
    if options.output is not None:
        OUTPUT = options.output if options.output.is_absolute() else ROOT / options.output
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "result.json").unlink(missing_ok=True)
    source_before = source_hashes()
    processes = []
    relay_process = None
    relay_url = ""
    started = time.monotonic()
    try:
        if "--relay" in sys.argv:
            relay_url = "ws://127.0.0.1:24929/ws"
            with (OUTPUT / "relay.log").open("w") as log:
                relay_process = subprocess.Popen([sys.executable, "server/relay.py"], cwd=ROOT,
                    env={**os.environ, "PORT":"24929", "RELAY_HOST":"127.0.0.1", "SOCIAL_DB":":memory:"},
                    stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen("http://127.0.0.1:24929/healthz", timeout=.2) as response:
                        if response.status == 200: break
                except OSError: time.sleep(.05)
            else: raise AssertionError("Local memory-only relay failed to start")
        with tempfile.TemporaryDirectory(prefix="bunkercrew-tire-network-") as folder:
            prefix = str(Path(folder) / "run")
            for slot in range(1, 5):
                role = "host" if slot == 1 else f"guest{slot}"
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE":role, "LASTSHIFT_PARTY_SLOT":str(slot),
                    "LASTSHIFT_GAMEPLAY_PATH":prefix, "LASTSHIFT_PARTY_RELAY":relay_url,
                    **{f"XDG_{kind}_HOME":str(Path(folder) / role / kind.lower()) for kind in ("DATA", "CONFIG", "CACHE")}}
                log_path = OUTPUT / f"{role}.log"
                with log_path.open("w") as log:
                    process = subprocess.Popen([shutil.which("godot"), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                        "--script", "tests/convoy_coop_defense_peer.gd", "--", "--no-profile-save", "--no-upnp"],
                        cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                processes.append(process)
                wait_path(Path(prefix + (".room.json" if slot == 1 else f".joined{slot}.json")), process, log_path)
            deadline = time.monotonic() + 90
            while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
                time.sleep(.05)
            peers = []
            for slot, process in enumerate(processes, 1):
                role = "host" if slot == 1 else f"guest{slot}"
                log = (OUTPUT / f"{role}.log").read_text()
                marker = re.search(rf"NETWORK_GAMEPLAY_PASS {role} checks=(\d+) failures=(\d+)", log)
                if process.poll() != 0 or not marker or int(marker[2]) or any(error in log for error in ("ERROR:", "SCRIPT ERROR", "WARNING:")):
                    evidence_path = Path(prefix + ".final.json")
                    failure = {"mode":"local-relay" if relay_url else "direct-enet", "role":role,
                        "exit_code":process.returncode, "log":str(OUTPUT / f"{role}.log"),
                        "evidence":json.loads(evidence_path.read_text()) if evidence_path.exists() else None,
                        "source_sha256":source_hashes()}
                    (OUTPUT / "failure.json").write_text(json.dumps(failure, indent=2) + "\n")
                    raise AssertionError(log)
                peers.append({"role":role, "checks":int(marker[1]), "passed":int(marker[1]), "exit_code":process.returncode})
            evidence = json.loads(Path(prefix + ".final.json").read_text())
            source_after = source_hashes()
            assert source_before == source_after, "Tested source changed during the isolated run"
            report = {"mode":"local-relay" if relay_url else "direct-enet", "checks":sum(peer["checks"] for peer in peers),
                "passed":sum(peer["passed"] for peer in peers), "peers":peers, "elapsed_seconds":round(time.monotonic()-started, 3),
                "prepared_states":["wave20 victory, convoy_mg research and two finite ammo crates", "garage boarding uses actual four seat owners",
                    "actual starting cinematic and host shared skip before original ignition; one English and three German peers derive identical duration/cast",
                    "actual guest cinematic command denied and held fire/reload/interact keys blocked without finite ammunition or seat changes",
                    "position vehicle at real breakdown threshold1740.1", "two outside service stances; actual key input", "guard damage capped1; HP/movement/attack remain real",
                    "first spawned guard prepared300px behind chassis; replicas await independent native rear/front targets before real finite shots",
                    "headless fire uses actual held keys with authenticated sampled pointer target; real host projectiles",
                    "disconnecting client delays only its normal retry by3s for a bounded shared-pause observation window"],
                "evidence":evidence, "source_sha256":source_after}
            (OUTPUT / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            print(f"CONVOY COOP NETWORK: {report['passed']}/{report['checks']} passed ({report['mode']}).")
    finally:
        for process in processes:
            if process.poll() is None: process.kill()
            process.wait(timeout=5)
        if relay_process is not None:
            relay_process.terminate()
            relay_process.wait(timeout=5)


if __name__ == "__main__":
    main()
