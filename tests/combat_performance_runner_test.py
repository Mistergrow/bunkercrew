#!/usr/bin/env python3
"""Acceptance must reject contention, incorrect scenes and falsified metrics."""

import copy
import importlib.util
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
SPEC = importlib.util.spec_from_file_location("performance_runner", ROOT / "tools/benchmark_combat_performance.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class CombatPerformanceRunnerTest(unittest.TestCase):
    def context(self, state="T"):
        return {"available": True, "gpus": [{"utilization_percent": 0}],
                "compute_processes": [{"pid": 123, "state": state}]}

    def scene(self):
        return {"viewport": [1920, 1080], "enemies": 40, "players": 4,
                "measured_frames": 120, "warmup_frames": 60, "reduced_effects": False,
                "frame_samples_ms": [16.0] * 120,
                "frame_ms": {"mean": 16.0, "p95": 16.0, "max": 16.0},
                "meets_frame_target": True}

    def test_resident_compute_resuming_is_not_isolated(self):
        self.assertTrue(RUNNER.quiet_gpu(self.context()))
        # PID/executable/allocation can stay identical while a stopped job wakes.
        for state in ("R", "S", "D", "unknown"):
            with self.subTest(state=state):
                self.assertFalse(RUNNER.no_competing_compute(self.context(state)))
                self.assertFalse(RUNNER.quiet_gpu(self.context(state)))

    def test_own_process_allowed_but_other_compute_not_allowed(self):
        context = self.context("R")
        self.assertTrue(RUNNER.no_competing_compute(context, 123))
        context["compute_processes"].append({"pid": 124, "state": "S"})
        self.assertFalse(RUNNER.no_competing_compute(context, 123))

    def test_unknown_or_busy_gpu_never_certifies_idle(self):
        self.assertFalse(RUNNER.quiet_gpu({"available": False}))
        self.assertFalse(RUNNER.quiet_gpu({"available": True, "gpus": []}))
        context = self.context()
        context["gpus"][0]["utilization_percent"] = 100
        self.assertFalse(RUNNER.quiet_gpu(context))

    def test_compute_resumes_in_final_polling_gap(self):
        before = self.context()
        samples = [self.context(), self.context()]
        self.assertTrue(RUNNER.isolated_gpu_run(before, samples, self.context(), 999))
        self.assertFalse(RUNNER.isolated_gpu_run(before, samples, self.context("R"), 999))
        self.assertFalse(RUNNER.isolated_gpu_run(before, [], self.context(), 999))

    def test_accepts_complete_correct_profile(self):
        self.assertTrue(RUNNER.validate_case(self.scene(), 120, 60, False))

    def test_short_diagnostics_do_not_qualify_repeated_frame_target(self):
        # Correct raw metrics and a quiet GPU still do not supply the full
        # repeated acceptance window when diagnostic overrides are shorter.
        self.assertTrue(RUNNER.validate_case(self.scene(), 120, 60, False))
        self.assertTrue(RUNNER.qualifies_frame_target(True, True, 3, 120, 600))
        for isolated, targets, runs, warmup, frames in (
                (True, True, 3, 120, 120), (True, True, 3, 60, 600),
                (True, True, 2, 120, 600), (False, True, 3, 120, 600),
                (True, False, 3, 120, 600)):
            with self.subTest(isolated=isolated, targets=targets, runs=runs,
                              warmup=warmup, frames=frames):
                self.assertFalse(RUNNER.qualifies_frame_target(
                    isolated, targets, runs, warmup, frames))

    def test_fast_average_with_slow_p95_does_not_pass(self):
        scene = self.scene()
        scene["frame_samples_ms"] = [10.] * 108 + [30.] * 12
        scene["frame_ms"] = {"mean": 12., "p95": 30., "max": 30.}
        scene["meets_frame_target"] = False
        self.assertFalse(RUNNER.validate_case(scene, 120, 60, False))
        scene["meets_frame_target"] = True
        with self.assertRaisesRegex(ValueError, "acceptance"):
            RUNNER.validate_case(scene, 120, 60, False)

    def test_metrics_cannot_hide_slow_frames(self):
        for metric in ("mean", "p95", "max"):
            scene = self.scene()
            scene["frame_ms"][metric] = 1.
            with self.subTest(metric=metric), self.assertRaisesRegex(ValueError, "metric"):
                RUNNER.validate_case(scene, 120, 60, False)

    def test_wrong_scene_or_profile_rejected(self):
        for field, value in (("viewport", [1280, 720]), ("players", 1), ("enemies", 4),
                             ("reduced_effects", True), ("measured_frames", 119), ("warmup_frames", 1)):
            scene = self.scene()
            scene[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "scene"):
                RUNNER.validate_case(scene, 120, 60, False)

    def test_incomplete_nonfinite_or_invalid_samples_rejected(self):
        for samples in ([16.] * 119, [float("nan")] * 120, [float("inf")] * 120,
                        [0.] * 120, [-1.] * 120, [True] * 120):
            scene = copy.deepcopy(self.scene())
            scene["frame_samples_ms"] = samples
            with self.subTest(sample=samples[0]), self.assertRaisesRegex(ValueError, "samples"):
                RUNNER.validate_case(scene, 120, 60, False)


if __name__ == "__main__":
    unittest.main()
