#!/usr/bin/env python3
"""Regression checks for frozen inputs, failure detection and child cleanup."""

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("stability_runner", ROOT / "tools/verify_beta_stability.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class StabilityRunnerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bunkercrew-p0-runner-test-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "source"
        self.root.mkdir()
        (self.root / "project.godot").write_text("config_version=5\n")
        (self.root / "scripts").mkdir()
        (self.root / "scripts/main.gd").write_text("extends Node\n")

    def assert_process_stopped(self, child_pid):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                state = Path(f"/proc/{child_pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
            except (FileNotFoundError, ProcessLookupError):
                return
            if state == "Z":
                return
            time.sleep(.02)
        self.fail("Completed check left a running child")

    def test_snapshot_is_not_linked_to_live_inputs(self):
        manifest = RUNNER.source_manifest(self.root)
        target = self.base / "snapshot"
        RUNNER.copy_snapshot(self.root, target, manifest)
        original = self.root / "scripts/main.gd"
        copied = target / "scripts/main.gd"
        self.assertNotEqual(original.stat().st_ino, copied.stat().st_ino)
        copied.write_text("extends Node2D\n")
        self.assertEqual(original.read_text(), "extends Node\n")
        self.assertEqual(RUNNER.source_manifest(self.root), manifest)

    def test_secrets_caches_and_generated_reports_not_copied(self):
        for relative in ("server/.env", "tools/__pycache__/cache.pyc", "artifacts/private.json",
                         "beta/old.exe", "native/bunkercrew_audio/build-linux/cache.bin"):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("excluded")
        manifest = RUNNER.source_manifest(self.root)
        self.assertEqual(set(manifest), {"project.godot", "scripts/main.gd"})

    def test_modified_input_refuses_snapshot(self):
        manifest = RUNNER.source_manifest(self.root)
        (self.root / "scripts/main.gd").write_text("extends Node2D\n")
        with self.assertRaisesRegex(RuntimeError, "changed while copying"):
            RUNNER.copy_snapshot(self.root, self.base / "snapshot", manifest)

    def test_added_input_refuses_snapshot(self):
        manifest = RUNNER.source_manifest(self.root)
        (self.root / "scripts/new.gd").write_text("extends Node\n")
        with self.assertRaisesRegex(RuntimeError, "changed while copying"):
            RUNNER.copy_snapshot(self.root, self.base / "snapshot", manifest)

    def test_external_root_and_asset_symlinks_refused(self):
        external = self.base / "external.txt"
        external.write_text("external")
        for relative in ("project.godot", "assets/reference.png"):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            original = path.read_bytes() if path.exists() else None
            path.unlink(missing_ok=True)
            path.symlink_to(external)
            with self.assertRaisesRegex(RuntimeError, "symlink"):
                RUNNER.source_manifest(self.root)
            path.unlink()
            if original is not None:
                path.write_bytes(original)

    def test_entire_source_directory_symlink_refused(self):
        external = self.base / "external-scripts"
        external.mkdir()
        (external / "outside.gd").write_text("extends Node\n")
        original = self.root / "scripts/main.gd"
        original.unlink()
        original.parent.rmdir()
        (self.root / "scripts").symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            RUNNER.source_manifest(self.root)

    def test_dangling_root_symlink_refused(self):
        (self.root / "default_bus_layout.tres").symlink_to(self.base / "absent.tres")
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            RUNNER.source_manifest(self.root)

    def test_fresh_environment_never_replaces_user_paths(self):
        before = {key: os.environ.get(key) for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "PATH")}
        first = RUNNER.private_environment(self.base / "profile-a", sys.executable)
        second = RUNNER.private_environment(self.base / "profile-b", sys.executable)
        for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            self.assertNotEqual(first[key], second[key])
            self.assertTrue(Path(first[key]).is_relative_to(self.base))
        self.assertEqual({key: os.environ.get(key) for key in before}, before)
        self.assertEqual((self.base / "profile-a/bin/godot").resolve(), Path(sys.executable).resolve())

    def test_zero_exit_warning_fails_and_clean_exit_passes(self):
        for message, success in (("WARNING: retained object", False), ("PASS regression", True)):
            record = RUNNER.run_check([sys.executable, "-c", "print(" + repr(message) + ")"],
                                      self.root, dict(os.environ), self.base / ("clean.log" if success else "warning.log"), 5)
            self.assertEqual(record["success"], success)
            self.assertEqual(record["exit_code"], 0)

    def test_nested_guest_and_relay_diagnostics_cannot_hide(self):
        logs = self.base / "logs"
        (logs / "stopped-guest").mkdir(parents=True)
        (logs / "driver.log").write_text("PASS driver\n")
        (logs / "stopped-guest/slot2.log").write_text("\x1b[31mWARNING: retained guest\x1b[0m\n")
        (logs / "relay.log").write_text("ERROR aiohttp.server: Error handling request\nWARNING bunkercrew.relay: Failed send\nTraceback (most recent call last):\nRuntimeError: failed\n")
        self.assertEqual(RUNNER.diagnostic_logs(logs), {
            "relay.log": ["ERROR aiohttp.server: Error handling request", "WARNING bunkercrew.relay: Failed send", "Traceback (most recent call last):"],
            "stopped-guest/slot2.log": ["WARNING: retained guest"],
        })

    @unittest.skipUnless(sys.platform == "linux", "Process group ownership uses Linux /proc")
    def test_timeout_terminates_only_its_children(self):
        pid_file = self.base / "child.pid"
        code = ("import subprocess,sys,time; from pathlib import Path; "
                "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                "Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(60)")
        record = RUNNER.run_check([sys.executable, "-c", code, str(pid_file)], self.root,
                                  dict(os.environ), self.base / "timeout.log", 1)
        self.assertFalse(record["success"])
        self.assertTrue(record["timed_out"])
        self.assertTrue(pid_file.is_file())
        child_pid = int(pid_file.read_text())
        self.assert_process_stopped(child_pid)

    @unittest.skipUnless(sys.platform == "linux", "Process group ownership uses Linux /proc")
    def test_clean_driver_exit_rejects_and_retires_running_child(self):
        pid_file = self.base / "early-exit-child.pid"
        code = ("import subprocess,sys; from pathlib import Path; "
                "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                "Path(sys.argv[1]).write_text(str(child.pid))")
        record = RUNNER.run_check([sys.executable, "-c", code, str(pid_file)], self.root,
                                  dict(os.environ), self.base / "early-exit.log", 5)
        self.assertFalse(record["success"])
        self.assertFalse(record["timed_out"])
        self.assertEqual(record["exit_code"], 0)
        child_pid = int(pid_file.read_text())
        self.assertIn(child_pid, record["leftover_children"])
        self.assert_process_stopped(child_pid)


if __name__ == "__main__":
    unittest.main()
