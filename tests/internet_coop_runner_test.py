#!/usr/bin/env python3
"""Incomplete, stale or mismatched Internet evidence must never pass acceptance."""

import importlib.util
import json
from pathlib import Path
from argparse import Namespace
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("internet_driver", ROOT / "tools/verify_internet_coop.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class InternetEvidenceTest(unittest.TestCase):
    def test_admission_cooldown_uses_elapsed_time_and_short_sleeps(self):
        elapsed = [10.0]
        sleeps = []
        def sleep(seconds):
            sleeps.append(seconds)
            elapsed[0] += seconds
        with patch.object(driver.time, "monotonic", side_effect=lambda: elapsed[0]), \
             patch.object(driver.time, "sleep", side_effect=sleep):
            self.assertEqual(driver.admission_cooldown(2.5), 2.5)
        self.assertEqual(sleeps, [1.0, 1.0, .5])

    def test_invalid_admission_deadlines_are_rejected_before_waiting(self):
        for seconds in (-1, float("nan"), float("inf"), 301):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError), \
                 patch.object(driver.time, "sleep", side_effect=AssertionError("Must not sleep")):
                driver.admission_cooldown(seconds)

    def records(self, source=True, mixed=False):
        result = []
        for slot in range(1,5):
            platform = "windows" if mixed and slot in (2,4) else "linux"
            result.append({"role": "host" if slot == 1 else "guest" + str(slot), "platform": platform,
                           "identity": {"os": "Windows" if platform == "windows" else "Linux",
                                        "engine": "4.7.2.stable.official", "application_version": "fixture-beta",
                                        "network_build": "fixture-net", "world_revision": 5,
                                        "exported_template": not source, "executable": "/fixture/game"}})
        return result

    def packages(self):
        return {platform: {"build_info": {"version": "fixture-beta", "network_protocol": "fixture-net",
                    "world_revision": 5, "engine": "4.7.2.stable.official", "source_sha256": "a" * 64,
                    "platform": "ubuntu-x86_64" if platform == "linux" else "windows-x86_64"}}
                for platform in ("linux", "windows")}

    def test_complete_actual_source_and_export_identity(self):
        driver.validate_peer_identities(self.records(), True, {}, ("fixture-beta", "fixture-net", 5))
        driver.validate_peer_identities(self.records(False, True), False, self.packages())

    def test_four_empty_identities_do_not_prove_agreement(self):
        records = self.records()
        for record in records: record["identity"] = {}
        with self.assertRaises(RuntimeError):
            driver.validate_peer_identities(records, True, {}, ("fixture-beta", "fixture-net", 5))

    def test_every_required_identity_field_must_be_present(self):
        for field in ("os", "engine", "application_version", "network_build", "world_revision", "exported_template", "executable"):
            records = self.records()
            records[2]["identity"].pop(field)
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                driver.validate_peer_identities(records, True, {}, ("fixture-beta", "fixture-net", 5))

    def test_os_export_flag_engine_and_revision_are_validated(self):
        for field, value in (("os", "Windows"), ("engine", "4.6.1.stable"), ("exported_template", True),
                             ("world_revision", True), ("world_revision", "5")):
            records = self.records()
            records[1]["identity"][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(RuntimeError):
                driver.validate_peer_identities(records, True, {}, ("fixture-beta", "fixture-net", 5))

    def test_stale_or_different_build_and_duplicate_role_fail(self):
        records = self.records()
        records[3]["identity"]["network_build"] = "stale-net"
        with self.assertRaises(RuntimeError):
            driver.validate_peer_identities(records, True, {}, ("fixture-beta", "fixture-net", 5))
        records = self.records()
        records[3]["role"] = "guest2"
        with self.assertRaises(RuntimeError):
            driver.validate_peer_identities(records, True, {}, ("fixture-beta", "fixture-net", 5))

    def test_different_export_source_or_fabricated_package_build_fails(self):
        for key, value in (("source_sha256", "b" * 64), ("network_protocol", "stale-net"), ("platform", "ubuntu-x86_64")):
            packages = self.packages()
            packages["windows"]["build_info"][key] = value
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                driver.validate_peer_identities(self.records(False, True), False, packages)

    def test_missing_build_metadata_or_replaced_executable_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "game"
            binary.write_bytes(b"fixture exported executable")
            with self.assertRaises(RuntimeError): driver.package_identity(binary)
            info = self.packages()["linux"]["build_info"]
            info["executable_sha256"] = driver.stability.digest(binary)
            library = root / "fixture.so"
            library.write_bytes(b"fixture native library")
            info["live_music"] = {"library": library.name, "sha256": driver.stability.digest(library)}
            (root / "BUILD_INFO.json").write_text(json.dumps(info))
            driver.package_identity(binary)
            binary.write_bytes(b"changed executable")
            with self.assertRaises(RuntimeError): driver.package_identity(binary)

    def test_replaced_native_library_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, library = root / "game", root / "fixture.so"
            binary.write_bytes(b"fixture game")
            library.write_bytes(b"fixture native")
            info = self.packages()["linux"]["build_info"]
            info["live_music"] = {"library": library.name, "sha256": driver.stability.digest(library)}
            (root / "BUILD_INFO.json").write_text(json.dumps(info))
            driver.package_identity(binary)
            library.write_bytes(b"changed native")
            with self.assertRaises(RuntimeError): driver.package_identity(binary)

    def test_changed_frozen_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "project.godot").write_text('[application]\nconfig/version="fixture-beta"\n')
            protocol = root / "scripts/network_protocol.gd"
            protocol.write_text('const BUILD := "fixture-net"\nconst WORLD_REVISION := 5\n')
            self.assertEqual(driver.expected_source_identity(root), ("fixture-beta", "fixture-net", 5))
            manifest = driver.stability.source_manifest(root)
            driver.require_source_unchanged(root, manifest)
            protocol.write_text('const BUILD := "changed-net"\nconst WORLD_REVISION := 5\n')
            with self.assertRaises(RuntimeError): driver.require_source_unchanged(root, manifest)

    def test_wrong_role_log_and_fake_hard_exit_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "peer.log"
            log.write_text("NETWORK_GAMEPLAY_PASS guest2 checks=10 failures=0\n")
            driver.inspect_peer(log, 0, False, "guest2")
            with self.assertRaises(RuntimeError): driver.inspect_peer(log, 0, False, "guest3")
            with self.assertRaises(RuntimeError): driver.inspect_peer(log, 0, True, "host")

    def test_retirement_timeout_does_not_abandon_remaining_peers(self):
        class Peer:
            def __init__(self, pid, timeout): self.pid, self.timeout, self.waited = pid, timeout, False
            def poll(self): return 0
            def wait(self, timeout):
                self.waited = True
                if self.timeout: raise subprocess.TimeoutExpired("fixture", timeout)
        first, second = Peer(12345, True), Peer(12346, False)
        with patch.object(driver.stability, "live_process_group_members", return_value=[]):
            leftovers = driver.retire([first, second])
        self.assertTrue(first.waited and second.waited)
        self.assertEqual(leftovers, [12345])

    def wine_failure(self, fail_initialization=False, fail_cleanup=False):
        events = []
        class Launcher:
            def __init__(self, args, folder, manifest):
                self.wineprefix = folder / "wineprefix"
                self.wineprefix.mkdir()
            def initialize_wine(self):
                events.append("initialize")
                if fail_initialization: raise RuntimeError("fixture Wine init failure")
            def shutdown_wine(self):
                events.append("shutdown")
                if fail_cleanup: raise RuntimeError("fixture Wine cleanup failure")
            def environment(self, role): return Path("/fixture"), {}
            def start_game(self, *args):
                events.append("start_game")
                return Namespace(pid=12345), {"runtime": "Windows PE under Wine"}, 0
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "case"
            folder.mkdir()
            args = Namespace(source=False, platforms="windows,linux,linux,linux", windows=Path("/fixture/windows.exe"),
                             linux=Path("/fixture/linux"), relay="wss://fixture.example/ws")
            with patch.object(driver, "package_identity", return_value=self.packages()["windows"]), \
                 patch.object(driver.exports, "BetaValidation", Launcher), \
                 patch.object(driver, "await_marker", side_effect=RuntimeError("fixture join failure")), \
                 patch.object(driver, "retire", return_value=[]):
                result = driver.run_case(args, Path(directory), "leave", folder, Path(directory) / "logs")
                saved = json.loads((Path(directory) / "logs/result.json").read_text())
        self.assertFalse(result["success"])
        self.assertFalse(saved["success"])
        return events, result

    def test_wine_initializes_before_game_and_stops_after_failed_join(self):
        events, _ = self.wine_failure()
        self.assertEqual(events, ["initialize", "start_game", "shutdown"])

    def test_partial_wine_initialization_is_cleaned_up(self):
        events, _ = self.wine_failure(fail_initialization=True)
        self.assertEqual(events, ["initialize", "shutdown"])

    def test_failed_wine_cleanup_cannot_leave_a_successful_case_report(self):
        _, result = self.wine_failure(fail_cleanup=True)
        self.assertIn("cleanup failure", result["cleanup_error"])


if __name__ == "__main__":
    unittest.main()
