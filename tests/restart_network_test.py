#!/usr/bin/env python3
"""Check host-only restart and campaign checkpoints using two real ENet peers."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest


class RestartNetworkIntegration(unittest.TestCase):
    def test_host_restart_retains_party_and_campaign(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT") or shutil.which("godot")
        self.assertIsNotNone(godot, "Godot executable required")
        output = root / "artifacts/ui-hardening/restart-network"
        output.mkdir(parents=True, exist_ok=True)
        command = [godot, "--headless", "--path", str(root), "--script", "tests/restart_network_peer.gd", "--", "--no-upnp"]
        processes = {}
        with tempfile.TemporaryDirectory(prefix="bunkercrew-restart-") as directory:
            prefix = str(pathlib.Path(directory) / "run")
            try:
                for role in ("host", "guest"):
                    environment = {**os.environ, "LASTSHIFT_GAMEPLAY_ROLE": role,
                                   "LASTSHIFT_GAMEPLAY_PATH": prefix, "LASTSHIFT_TEST_PORT": "24937",
                                   "LASTSHIFT_TEST_DISCOVERY_PORT": "24938",
                                   "XDG_DATA_HOME": str(pathlib.Path(directory) / role)}
                    with (output / f"{role}.log").open("w") as log:
                        role_command = command + (["--no-profile-save"] if role == "host" else [])
                        processes[role] = subprocess.Popen(role_command, cwd=root, env=environment,
                                                           stdout=log, stderr=subprocess.STDOUT)
                    if role == "host":
                        deadline = time.monotonic() + 12
                        while not pathlib.Path(prefix + ".room.json").exists() and processes[role].poll() is None and time.monotonic() < deadline:
                            time.sleep(.04)
                        self.assertTrue(pathlib.Path(prefix + ".room.json").exists(), (output / "host.log").read_text())
                deadline = time.monotonic() + 43
                while any(process.poll() is None for process in processes.values()) and time.monotonic() < deadline:
                    time.sleep(.05)
                for role, process in processes.items():
                    text = (output / f"{role}.log").read_text()
                    self.assertIsNotNone(process.poll(), text)
                    self.assertEqual(process.returncode, 0, text)
                    self.assertIn(f"NETWORK_GAMEPLAY_PASS {role}", text)
                    for marker in ("SCRIPT ERROR", "ERROR:", "WARNING:"):
                        self.assertNotIn(marker, text)
                print("Actual host/guest mission and campaign restart passed.")
            finally:
                for process in processes.values():
                    if process.poll() is None:
                        process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
