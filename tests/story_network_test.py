#!/usr/bin/env python3
"""Run the story-specific lifecycle through two actual ENet processes.

No router mapping and no profile writes. Coordination files are phase barriers
and expected scalar assertions, never an alternate state-replication channel.
This wrapper always uses headless/Dummy and separate temporary user data.
"""
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest


class StoryNetworkIntegration(unittest.TestCase):
    def test_story_lobby_events_reconnect_rematch(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT") or shutil.which("godot")
        self.assertIsNotNone(godot, "Godot executable required")
        self.assertTrue((root / "scripts/network_world.gd").is_file(), "World replication script must be present")
        artifacts = root / "artifacts/story-mode"
        artifacts.mkdir(parents=True, exist_ok=True)
        command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(root), "--script", "tests/story_network_peer.gd",
                   "--", "--no-profile-save", "--no-upnp"]
        processes = {}
        outputs = {}
        with tempfile.TemporaryDirectory(prefix="lastshift-gameplay-") as temporary:
            prefix = str(pathlib.Path(temporary) / "run")
            try:
                for role in ("host", "guest"):
                    log_path = artifacts / f"network-enet-{role}.log"
                    outputs[role] = log_path
                    log = log_path.open("w", encoding="utf-8")
                    env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix, "XDG_DATA_HOME":str(pathlib.Path(temporary)/role)}
                    process = subprocess.Popen(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
                    log.close()
                    processes[role] = process
                    if role == "host":
                        deadline = time.monotonic() + 12
                        room = pathlib.Path(prefix + ".room.json")
                        while not room.exists() and process.poll() is None and time.monotonic() < deadline:
                            time.sleep(0.04)
                        self.assertTrue(room.exists(), "Host did not create a room; UDP24777 must be free.\n" + log_path.read_text())
                deadline = time.monotonic() + 43
                while any(process.poll() is None for process in processes.values()) and time.monotonic() < deadline:
                    time.sleep(0.05)
                combined = "\n\n".join(f"{role}:\n{path.read_text(encoding='utf-8', errors='replace')[-18000:]}" for role, path in outputs.items())
                for role, process in processes.items():
                    text = outputs[role].read_text(encoding="utf-8", errors="replace")
                    self.assertIsNotNone(process.poll(), f"{role} exceeded the bounded integration timeout\n{combined}")
                    self.assertEqual(process.returncode, 0, combined)
                    self.assertIn(f"NETWORK_GAMEPLAY_PASS {role}", text)
                    self.assertNotIn("SCRIPT ERROR", text)
                    self.assertNotIn("ERROR:", text)
                    self.assertNotIn("WARNING:", text)
                print("Real ENet story lobby, objectives, duplicate dialogue, positioned sounds, reconnect and rematch passed.")
            finally:
                for process in processes.values():
                    if process.poll() is None:
                        process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
