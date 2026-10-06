#!/usr/bin/env python3
"""Actual named lobby/combat chat in 2/4 ENet and relay processes."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/network-chat"


def run_case(count, relay, *, peer_script="tests/network_chat_peer.gd"):
    case = OUTPUT / f"{'relay' if relay else 'direct'}-{count}"
    case.mkdir(parents=True, exist_ok=True)
    command = [shutil.which("godot"), "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--script", peer_script, "--", "--no-profile-save", "--no-upnp"]
    processes = []
    relay_process = None
    relay_url = "ws://127.0.0.1:24949/ws" if relay else ""
    with tempfile.TemporaryDirectory(prefix="bunkercrew-chat-") as temporary:
        prefix = str(pathlib.Path(temporary) / "run")
        try:
            if relay:
                with (case / "relay.log").open("w") as log:
                    relay_process = subprocess.Popen(
                        [sys.executable, "server/relay.py"], cwd=ROOT,
                        env={**os.environ, "PORT": "24949", "RELAY_HOST": "127.0.0.1",
                             "SOCIAL_DB": str(pathlib.Path(temporary) / "social.sqlite3")},
                        stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:24949/healthz", timeout=.2) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        time.sleep(.05)
                else:
                    raise AssertionError("Local relay did not start")
            for slot in range(1, count + 1):
                role = "host" if slot == 1 else f"guest{slot}"
                env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role,
                       "LASTSHIFT_GAMEPLAY_PATH": prefix, "BUNKERCREW_CHAT_SLOT": str(slot),
                       "BUNKERCREW_CHAT_COUNT": str(count), "BUNKERCREW_CHAT_RELAY": relay_url,
                       **{f"XDG_{kind}_HOME": str(pathlib.Path(temporary) / role / kind.lower())
                          for kind in ("DATA", "CONFIG", "CACHE")}}
                with (case / f"{role}.log").open("w") as log:
                    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                processes.append((role, process))
                stage = "room" if slot == 1 else f"joined{slot}"
                deadline = time.monotonic() + 15
                while not pathlib.Path(prefix + f".{stage}.json").exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.04)
                if not pathlib.Path(prefix + f".{stage}.json").exists():
                    raise AssertionError((case / f"{role}.log").read_text())
            deadline = time.monotonic() + 65
            while any(process.poll() is None for _, process in processes) and time.monotonic() < deadline:
                time.sleep(.05)
            for role, process in processes:
                log = (case / f"{role}.log").read_text()
                if process.poll() != 0 or f"NETWORK_GAMEPLAY_PASS {role}" not in log or any(marker in log for marker in ["SCRIPT ERROR", "ERROR:", "WARNING:"]):
                    combined = "\n".join(f"{name}:\n{(case / f'{name}.log').read_text()[-14000:]}" for name, _ in processes)
                    raise AssertionError(f"{role} exit={process.poll()}\n{combined}")
            print(f"CHAT {'relay' if relay else 'direct'} {count} players: PASS", flush=True)
        finally:
            for _, process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay_process:
                relay_process.terminate()
                try:
                    relay_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    relay_process.kill()
                    relay_process.wait(timeout=5)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    cases = [(2, False), (2, True), (4, False), (4, True)]
    if "--direct-only" in sys.argv:
        cases = [(2, False), (4, False)]
    for party_count, use_relay in cases:
        run_case(party_count, use_relay)
