#!/usr/bin/env python3
"""Reject fabricated/incomplete live-combat and frame evidence."""
import copy
from argparse import Namespace
import importlib.util
from pathlib import Path
import sys
import subprocess
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
SPEC = importlib.util.spec_from_file_location("live_network_benchmark", ROOT / "tools/benchmark_network_combat_performance.py")
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


class LiveEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.sample = {"players": 4, "enemies": 40, "min_enemies": 40, "max_enemies": 40, "min_live_workers": 4, "warmup_frames": 120, "requested_warmup_frames": 120, "warmup_seconds": 2.0,
            "measured_frames": 600, "reduced_effects": False, "environment": "ash_foundry", "rendered": True,
            "scenario_environment": "ash_foundry", "requested_environment": "ash_foundry",
            "viewport": [1920, 1080], "network_error": "", "microphone_open": False, "frame_samples_ms": [10.0] * 600,
            "frame_ms": {"mean": 10.0, "p95": 10.0, "max": 10.0}, "physics_ticks": 360, "simulation_seconds": 6.0,
            "snapshots": 120, "configured_snapshot_interval_seconds": .05, "meets_frame_target": True}
        self.combat = {"worker_projectile_spawns": 40, "enemy_attacks": 20,
            "hit_counts": {str(i): 10 for i in range(1, 5)}, "hit_damage": {str(i): 100.0 for i in range(1, 5)},
            "shots_fired": [10] * 4, "normal_reload_seen": {str(i): True for i in range(1, 5)},
            "ammunition_remaining": [86] * 4, "minimum_ammunition": [60] * 4, "maximum_silent_seconds": [.5] * 4,
            "initial_ammunition_rounds": 20384, "remaining_supply_rounds": 20000, "total_shots_fired": [10] * 4,
            "player_damage_received": [0, 0, 10, 0]}

    def validate(self, value=None):
        return DRIVER.validate_samples(self.sample if value is None else value, 600, 120, "ash_foundry", False, True)

    def test_complete_authentic_evidence_accepted(self):
        self.assertTrue(self.validate())
        DRIVER.validate_combat(self.combat)

    def test_incomplete_or_nonfinite_raw_frames_rejected(self):
        for values in ([10.0] * 599, [float("nan")] * 600, [-10.0] * 600):
            value = copy.deepcopy(self.sample)
            value["frame_samples_ms"] = values
            with self.assertRaises(ValueError): self.validate(value)

    def test_fabricated_percentile_or_acceptance_rejected(self):
        for metric in ("mean", "p95", "max"):
            value = copy.deepcopy(self.sample)
            value["frame_ms"][metric] += 1
            with self.assertRaises(ValueError): self.validate(value)
        value = copy.deepcopy(self.sample)
        value["meets_frame_target"] = False
        with self.assertRaises(ValueError): self.validate(value)

    def test_population_loss_or_snapshot_failure_rejected(self):
        for field, invalid in (("min_enemies", 39), ("max_enemies", 41), ("min_live_workers", 3), ("players", 3), ("network_error", "Invalid snapshot"), ("snapshots", 0), ("physics_ticks", 0), ("simulation_seconds", 0), ("configured_snapshot_interval_seconds", .1), ("microphone_open", True)):
            value = copy.deepcopy(self.sample)
            value[field] = invalid
            with self.assertRaises(ValueError): self.validate(value)

    def test_wrong_viewport_or_profile_rejected(self):
        for field, invalid in (("viewport", [1440, 900]), ("environment", "mountain_pass"), ("scenario_environment", "mountain_pass"), ("reduced_effects", True), ("rendered", False), ("warmup_frames", 119), ("warmup_seconds", 1.9)):
            value = copy.deepcopy(self.sample)
            value[field] = invalid
            with self.assertRaises(ValueError): self.validate(value)

    def test_no_real_worker_projectiles_or_enemy_attacks_rejected(self):
        for field in ("worker_projectile_spawns", "enemy_attacks"):
            value = copy.deepcopy(self.combat)
            value[field] = 0
            with self.assertRaises(ValueError): DRIVER.validate_combat(value)
        value = copy.deepcopy(self.combat)
        value["player_damage_received"] = [0] * 4
        with self.assertRaises(ValueError): DRIVER.validate_combat(value)

    def test_any_guest_without_actual_hit_or_reload_rejected(self):
        for field in ("hit_counts", "hit_damage", "normal_reload_seen"):
            value = copy.deepcopy(self.combat)
            value[field]["4"] = 0
            with self.assertRaises(ValueError): DRIVER.validate_combat(value)
        for field, invalid in (("shots_fired", 0), ("ammunition_remaining", 0), ("minimum_ammunition", 0), ("maximum_silent_seconds", 5.01)):
            value = copy.deepcopy(self.combat)
            value[field][2] = invalid
            with self.assertRaises(ValueError): DRIVER.validate_combat(value)

    def test_warmup_only_combat_cannot_pass_sample_window(self):
        for field in ("worker_projectile_spawns", "enemy_attacks"):
            value = copy.deepcopy(self.combat)
            value[field] = 0
            value["warmup_" + field] = 9999
            with self.assertRaises(ValueError): DRIVER.validate_combat(value)
        value = copy.deepcopy(self.combat)
        value["shots_fired"] = [0] * 4
        value["total_shots_fired"] = [96] * 4
        with self.assertRaises(ValueError): DRIVER.validate_combat(value)

    def test_short_sample_can_use_authentic_warmup_reload(self):
        value = copy.deepcopy(self.combat)
        value["sample_reload_seen"] = {}
        DRIVER.validate_combat(value)

    def test_short_quiet_target_runs_cannot_qualify_full_frame_acceptance(self):
        options = Namespace(runs=3, warmup=120, frames=120, scenario="all", effects="both")
        self.assertFalse(DRIVER.qualifies_frame_target(True, True, options))
        options.frames = 600
        self.assertTrue(DRIVER.qualifies_frame_target(True, True, options))
        options.warmup = 60
        self.assertFalse(DRIVER.qualifies_frame_target(True, True, options))
        options.warmup = 120
        self.assertFalse(DRIVER.qualifies_frame_target(False, True, options))
        self.assertFalse(DRIVER.qualifies_frame_target(True, False, options))
        options.runs = 2
        self.assertFalse(DRIVER.qualifies_frame_target(True, True, options))
        options.runs = 3
        options.effects = "reduced"
        self.assertFalse(DRIVER.qualifies_frame_target(True, True, options))
        options.effects = "both"
        options.scenario = "ash_foundry"
        self.assertFalse(DRIVER.qualifies_frame_target(True, True, options))

    def test_created_or_lost_finite_ammunition_rejected(self):
        for change in (-1, 1):
            value = copy.deepcopy(self.combat)
            value["remaining_supply_rounds"] += change
            with self.assertRaises(ValueError): DRIVER.validate_combat(value)

    def test_retirement_timeout_still_kills_every_owned_peer_group(self):
        processes = []
        for pid in (1234, 1235, 1236, 1237):
            process = Mock(pid=pid)
            process.poll.return_value = None
            processes.append(process)
        processes[0].wait.side_effect = subprocess.TimeoutExpired("owned-peer", 10)
        with patch.object(DRIVER.os, "killpg") as killpg, patch.object(DRIVER.stability, "live_process_group_members", return_value=[]):
            leftovers, errors = DRIVER.retire_all(processes)
        self.assertEqual(leftovers, [])
        self.assertEqual([value["pid"] for value in errors], [1234])
        self.assertEqual([call.args[0] for call in killpg.call_args_list], [1234, 1235, 1236, 1237])
        for process in processes: process.wait.assert_called_once_with(timeout=10)

    def test_early_exited_owned_children_are_killed_after_wait(self):
        process = Mock(pid=1234)
        process.poll.return_value = 0
        with patch.object(DRIVER.os, "killpg") as killpg, patch.object(DRIVER.stability, "live_process_group_members", return_value=[1238]):
            leftovers, errors = DRIVER.retire_all([process])
        self.assertEqual(leftovers, [1238])
        self.assertEqual(errors, [])
        killpg.assert_called_once_with(1234, DRIVER.signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
