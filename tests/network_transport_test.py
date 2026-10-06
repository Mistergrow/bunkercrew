#!/usr/bin/env python3
"""Run two independent Godot processes over a real local ENet UDP socket."""

import os
import pathlib
import shutil
import socket
import subprocess
import time
import unittest


class TransportIntegration(unittest.TestCase):
    def test_two_real_godot_processes(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        godot = os.environ.get("GODOT", shutil.which("godot"))
        self.assertIsNotNone(godot, "Godot executable required")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        command = [godot, "--headless", "--path", str(root), "--script", "tests/network_transport_peer.gd", "--", "--no-profile-save"]
        processes = []
        try:
            for role in ("host", "guest"):
                env = {**os.environ, "LASTSHIFT_TRANSPORT_ROLE": role, "LASTSHIFT_TRANSPORT_PORT": str(port)}
                processes.append(subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
                if role == "host":
                    time.sleep(0.2)
            for role, process in zip(("host", "guest"), processes):
                output, _ = process.communicate(timeout=12)
                self.assertEqual(process.returncode, 0, f"{role}:\n{output}")
                self.assertIn("TRANSPORT_PASS", output)
                self.assertNotIn("SCRIPT ERROR", output)
                self.assertNotIn("ERROR:", output)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
