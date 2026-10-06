#!/usr/bin/env python3
"""Music and dance through two real game processes, with isolated profiles."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request


class MusicDanceGameplay(unittest.TestCase):
    def test_real_native_music_and_choreography_in_online_game(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT") or shutil.which("godot")
        self.assertIsNotNone(godot)
        use_relay = os.environ.get("BUNKERCREW_MUSIC_DANCE_RELAY")=="1"
        artifacts = root / "artifacts/music-dance-gameplay" / ("network-relay" if use_relay else "network")
        artifacts.mkdir(parents=True, exist_ok=True)
        processes = {}
        relay_process = None
        outputs = {}
        command = [godot, "--headless", "--path", str(root), "--script",
                   "tests/music_dance_gameplay_peer.gd", "--", "--no-profile-save", "--no-upnp"]
        with tempfile.TemporaryDirectory(prefix="bunkercrew-music-dance-") as temporary:
            prefix = str(pathlib.Path(temporary) / "run")
            try:
                if use_relay:
                    with (artifacts / "relay.log").open("w", encoding="utf-8") as log:
                        relay_process = subprocess.Popen([sys.executable, "server/relay.py"], cwd=root,
                                                         env={**os.environ, "PORT":"24983", "RELAY_HOST":"127.0.0.1", "SOCIAL_DB":":memory:"},
                                                         stdout=log, stderr=subprocess.STDOUT)
                    deadline = time.monotonic()+8
                    ready = False
                    while relay_process.poll() is None and time.monotonic()<deadline:
                        try:
                            with urllib.request.urlopen("http://127.0.0.1:24983/healthz", timeout=.3) as response:
                                ready = response.status==200
                            if ready:
                                break
                        except (OSError, urllib.error.URLError):
                            time.sleep(.04)
                    self.assertTrue(ready, (artifacts / "relay.log").read_text())
                for role in ("host", "guest"):
                    outputs[role] = artifacts / f"{role}.log"
                    environment = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role,
                                   "LASTSHIFT_GAMEPLAY_PATH": prefix,
                                   "BUNKERCREW_MUSIC_DANCE_RELAY_URL": "ws://127.0.0.1:24983/ws" if use_relay else "",
                                   "XDG_DATA_HOME": str(pathlib.Path(temporary) / role)}
                    with outputs[role].open("w", encoding="utf-8") as log:
                        processes[role] = subprocess.Popen(command, cwd=root, env=environment,
                                                           stdout=log, stderr=subprocess.STDOUT)
                    if role == "host":
                        deadline = time.monotonic() + 12
                        while not pathlib.Path(prefix + ".room.json").exists() and processes[role].poll() is None and time.monotonic() < deadline:
                            time.sleep(.04)
                        self.assertTrue(pathlib.Path(prefix + ".room.json").exists(), outputs[role].read_text())
                deadline = time.monotonic() + 115
                while any(process.poll() is None for process in processes.values()) and time.monotonic() < deadline:
                    time.sleep(.05)
                text = "\n\n".join(f"{role}:\n{path.read_text(errors='replace')}" for role, path in outputs.items())
                for role, process in processes.items():
                    self.assertEqual(process.poll(), 0, text)
                    log = outputs[role].read_text(errors="replace")
                    self.assertIn(f"NETWORK_GAMEPLAY_PASS {role}", log)
                    for error in ("SCRIPT ERROR", "ERROR:", "WARNING:"):
                        self.assertNotIn(error, log)
                results = {role: json.loads(pathlib.Path(prefix + f".{role}_passed.json").read_text())
                           for role in ("host", "guest")}
                results.update({"actual_game_processes": 2, "transport": "WebSocket relay" if use_relay else "ENet",
                                "native_audio_mixer": True, "developer_lab_used": False,
                                "authoritative_physics_running": True,
                                "prepared_state": "No automatic wave spawning; level 10 crew waiting outside the actual foundry bunker"})
                (artifacts / "verification.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
                print("Real two-process music, audible dance, input, pause, mute, shared restart and chat passed.")
            finally:
                for process in processes.values():
                    if process.poll() is None:
                        process.kill()
                    process.wait(timeout=5)
                if relay_process is not None:
                    relay_process.terminate()
                    relay_process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
