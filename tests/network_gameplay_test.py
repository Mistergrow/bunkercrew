#!/usr/bin/env python3
"""Run a real authoritative host and guest through a full gameplay lifecycle.

No router mapping and no profile writes. Coordination files are phase barriers
and expected scalar assertions, never an alternate state-replication channel.
Set LASTSHIFT_NETWORK_CAPTURE=1 to render both peers and capture their live world.
"""
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest


class NetworkGameplayIntegration(unittest.TestCase):
    def test_authoritative_gameplay_reconnect_and_rematch(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT") or shutil.which("godot")
        self.assertIsNotNone(godot, "Godot executable required")
        self.assertTrue((root / "scripts/network_world.gd").is_file(), "World replication script must be present")
        artifacts = root / "artifacts/network"
        artifacts.mkdir(parents=True, exist_ok=True)
        capture = os.environ.get("LASTSHIFT_NETWORK_CAPTURE") == "1"
        command = [godot, *([] if capture else ["--headless"]), "--path", str(root), "--script", "tests/network_gameplay_peer.gd",
                   "--", "--no-profile-save", "--no-upnp"]
        processes = {}
        outputs = {}
        with tempfile.TemporaryDirectory(prefix="lastshift-gameplay-") as temporary:
            prefix = str(pathlib.Path(temporary) / "run")
            try:
                for role in ("host", "guest"):
                    log_path = artifacts / f"gameplay-{role}.log"
                    if capture:
                        (artifacts / f"gameplay-{role}.png").unlink(missing_ok=True)
                    outputs[role] = log_path
                    log = log_path.open("w", encoding="utf-8")
                    env = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": prefix}
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
                    if capture:
                        self.assertTrue((artifacts / f"gameplay-{role}.png").is_file(), f"Missing actual {role} world capture")
                print("Real host/guest gameplay, input isolation, snapshots, pause, reconnect and rematch passed.")
            finally:
                for process in processes.values():
                    if process.poll() is None:
                        process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
