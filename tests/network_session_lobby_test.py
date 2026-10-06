#!/usr/bin/env python3
"""Exercise the real main-scene direct-host lobby in two Godot processes."""

import os
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request


class SessionLobbyIntegration(unittest.TestCase):
    def test_real_host_guest_lobby(self):
        self.run_lobby()

    def test_rejected_and_silent_peers_release_slot_before_healthy_join(self):
        self.run_lobby(("rejector", "silent"))

    def test_real_relay_host_guest_lobby(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        server = subprocess.Popen([sys.executable, str(root / "server/relay.py")], cwd=root,
                                  env={**os.environ, "PORT": str(port), "RELAY_HOST": "127.0.0.1", "SOCIAL_DB": ":memory:"},
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + 5
            ready = False
            while time.monotonic() < deadline and server.poll() is None:
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=0.2) as response:
                        ready = response.status == 200
                    if ready:
                        break
                except (urllib.error.URLError, TimeoutError):
                    time.sleep(0.05)
            self.assertTrue(ready, "Local relay did not start")
            self.run_lobby(relay_url=f"ws://127.0.0.1:{port}/ws")
        finally:
            server.terminate()
            try:
                server.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.communicate()

    def run_lobby(self, probes=(), relay_url=""):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT", shutil.which("godot"))
        self.assertIsNotNone(godot, "Godot executable required")
        command = [godot, "--headless", "--path", str(root), "--script", "tests/network_session_lobby_peer.gd", "--", "--no-profile-save", "--no-upnp"]
        processes = []
        with tempfile.TemporaryDirectory(prefix="lastshift-lobby-") as temporary:
            coordination = str(pathlib.Path(temporary) / "lobby")
            try:
                env = {**os.environ, "LASTSHIFT_LOBBY_ROLE": "host", "LASTSHIFT_LOBBY_PATH": coordination,
                       "LASTSHIFT_LOBBY_RELAY": relay_url}
                host = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                processes.append(host)
                deadline = time.monotonic() + 15
                while not pathlib.Path(coordination + ".code").exists() and time.monotonic() < deadline and host.poll() is None:
                    time.sleep(0.05)
                if not pathlib.Path(coordination + ".code").exists():
                    if host.poll() is None:
                        host.kill()
                    output, _ = host.communicate(timeout=5)
                    self.fail("Host did not create a room. UDP24777 must be free.\n" + output)
                for probe_role in probes:
                    env["LASTSHIFT_LOBBY_ROLE"] = probe_role
                    probe = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    processes.append(probe)
                    output, _ = probe.communicate(timeout=12)
                    self.assertEqual(probe.returncode, 0, f"{probe_role}:\n{output}")
                    self.assertIn("SESSION_LOBBY_PASS", output)
                    self.assertNotIn("SCRIPT ERROR", output)
                    self.assertNotIn("ERROR:", output)
                env["LASTSHIFT_LOBBY_ROLE"] = "guest"
                guest = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                processes.append(guest)
                for role, process in (("host", host), ("guest", guest)):
                    output, _ = process.communicate(timeout=48)
                    self.assertEqual(process.returncode, 0, f"{role}:\n{output}")
                    self.assertIn("SESSION_LOBBY_PASS", output)
                    self.assertNotIn("SCRIPT ERROR", output)
                    self.assertNotIn("ERROR:", output)
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
