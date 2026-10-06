#!/usr/bin/env python3
"""Repeat 1080p full/reduced renderer measurements in an independent project."""

from __future__ import annotations

import argparse
import datetime
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import verify_beta_stability as stability

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = "tests/combat_render_benchmark.gd"


def gpu_context() -> dict:
    result = {"gpus": [], "compute_processes": [], "available": False}
    if not shutil.which("nvidia-smi"):
        return result
    commands = (
        ["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used", "--format=csv,noheader,nounits"],
        ["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory", "--format=csv,noheader,nounits"],
    )
    try:
        gpu_rows, processes = [subprocess.check_output(cmd, text=True, timeout=5) for cmd in commands]
        for row in gpu_rows.splitlines():
            name, utilization, memory = row.rsplit(",", 2)
            result["gpus"].append({"name": name.strip(), "utilization_percent": float(utilization),
                                   "memory_used_mib": float(memory)})
        for row in processes.splitlines():
            pid_text, details = row.split(",", 1)
            name, memory = details.rsplit(",", 1)
            pid = int(pid_text)
            process = {"pid": pid, "executable": name.strip(), "memory_used_mib": float(memory),
                       "state": "unknown"}
            try:
                fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
                process["state"] = fields[0]
                process["start_ticks"] = int(fields[19])
            except (OSError, IndexError, ValueError):
                pass
            result["compute_processes"].append(process)
        result["available"] = bool(result["gpus"])
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    return result


def no_competing_compute(context: dict, benchmark_pid: int | None = None) -> bool:
    # An unchanged executable/memory list cannot prove isolation: a resident
    # compute job may resume without changing either. Unknown state fails closed.
    return bool(context.get("available")) and all(
        process.get("pid") == benchmark_pid or process.get("state") == "T"
        for process in context.get("compute_processes", ()))


def quiet_gpu(context: dict) -> bool:
    # A large compute allocation can remain resident while its process is
    # paused. GPU utilization before the game must also have settled to idle.
    return no_competing_compute(context) and bool(context.get("gpus")) and all(
        gpu["utilization_percent"] < 15 for gpu in context["gpus"])


def isolated_gpu_run(before: dict, samples: list[dict], after: dict, benchmark_pid: int) -> bool:
    # Include the final polling interval: a resident job can resume between the
    # last sample and process exit without changing its PID or allocation.
    return quiet_gpu(before) and bool(samples) and all(
        no_competing_compute(context, benchmark_pid) for context in samples + [after])


def qualifies_frame_target(isolated: bool, all_targets: bool, runs: int,
                           warmup: int, frames: int) -> bool:
    # Short overrides are useful diagnostics, but cannot certify the repeated
    # sample window promised by the default acceptance commands.
    return isolated and all_targets and runs >= 3 and warmup >= 120 and frames >= 600


def validate_case(case: dict, frames: int, warmup: int, reduced: bool) -> bool:
    if (case["viewport"] != [1920, 1080] or case["enemies"] != 40 or case["players"] != 4
            or case["measured_frames"] != frames or case["warmup_frames"] != warmup
            or case["reduced_effects"] is not reduced):
        raise ValueError("Incorrect prepared scene/profile/sample count")
    samples = case["frame_samples_ms"]
    if len(samples) != frames or any(type(value) not in (int, float) or not math.isfinite(value)
                                    or value <= 0 for value in samples):
        raise ValueError("Incomplete/invalid frame samples")
    measured = {"mean": sum(samples) / frames, "p95": sorted(samples)[math.ceil(frames * .95) - 1],
                "max": max(samples)}
    for key, value in measured.items():
        reported = case["frame_ms"][key]
        if type(reported) not in (int, float) or not math.isclose(reported, value, abs_tol=1e-6):
            raise ValueError("Reported frame metric differs from raw samples: " + key)
    target = 1000 / measured["mean"] >= 60 and measured["p95"] <= 16.7
    if case["meets_frame_target"] is not target:
        raise ValueError("Reported frame acceptance differs from raw samples")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT, help="Runtime inputs, e.g. a preserved before snapshot")
    parser.add_argument("--output", type=Path, help="New report directory")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--warmup", type=int, default=120)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--allow-contended-gpu", action="store_true", help="Diagnostic runs only; never marks isolated acceptance")
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    if args.runs < 1 or args.warmup < 60 or args.frames < 120:
        parser.error("Require at least one run, 60 warmup and 120 measured frames")
    godot = shutil.which(args.godot)
    if not godot:
        parser.error("Godot 4.7.2 executable not found")
    godot = str(Path(godot).resolve())
    source = args.project.resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = (args.output or ROOT / "artifacts" / f"combat-performance-{stamp}").resolve()
    if output.is_relative_to(ROOT) and not output.is_relative_to(ROOT / "artifacts"):
        parser.error("Repository reports must be under artifacts/")
    output.mkdir(parents=True, exist_ok=False)
    report = {"success": False, "isolated_prepared_frame_target": False, "runs": [], "error": None,
              "source_project": str(source), "fixture_sha256": stability.digest(ROOT / FIXTURE),
              "scope": "Prepared four stationary crew and forty animated enemies; combat/AI frozen. Full and reduced effects, VSync/FPS cap disabled. This does not certify minimum hardware or live network combat."}
    manifest = {}
    try:
        before_context = gpu_context()
        report["initial_gpu"] = before_context
        if not quiet_gpu(before_context) and not args.allow_contended_gpu:
            raise RuntimeError("GPU is not verified idle; pause competing compute or use diagnostic --allow-contended-gpu")
        manifest = stability.source_manifest(source)
        (output / "runtime-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
        version = subprocess.check_output([godot, "--version"], text=True).strip()
        if not version.startswith("4.7.2."):
            raise RuntimeError("Godot 4.7.2 required: " + version)
        report["godot_version"] = version
        with tempfile.TemporaryDirectory(prefix="bunkercrew-frame-benchmark-") as temporary:
            base = Path(temporary)
            project = base / "project"
            stability.copy_snapshot(source, project, manifest)
            # Use one identical measured fixture with both old/new runtimes.
            shutil.copy2(ROOT / FIXTURE, project / FIXTURE)
            import_command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                              "--editor", "--recovery-mode", "--import", "--quit"]
            imported = stability.run_check(import_command, project,
                                           stability.private_environment(base / "import-profile", godot),
                                           output / "import.log", 120)
            report["import"] = imported
            if not imported["success"]:
                raise RuntimeError("Private import failed")
            frozen = stability.source_manifest(project)
            all_isolated = quiet_gpu(before_context) and not args.allow_contended_gpu
            all_targets = True
            for repeat in range(args.runs):
                for reduced in (False, True):
                    name = f"{repeat + 1}-{'reduced' if reduced else 'standard'}"
                    gpu_before = gpu_context()
                    if not quiet_gpu(gpu_before) and not args.allow_contended_gpu:
                        raise RuntimeError("GPU became busy before " + name)
                    destination = output / (name + ".json")
                    command = [godot, "--audio-driver", "Dummy", "--path", str(project), "--position", "-30000,-30000",
                               "--script", FIXTURE, "--", "--no-profile-save", "--no-upnp",
                               f"--warmup={args.warmup}", f"--frames={args.frames}", f"--output={destination}"]
                    if reduced:
                        command.append("--reduced-effects")
                    if args.capture and repeat == 0:
                        command.append("--capture-dir=" + str(output / (name + "-captures")))
                    environment = stability.private_environment(base / (name + "-profile"), godot)
                    with (output / (name + ".log")).open("x") as log:
                        started = time.monotonic()
                        process = subprocess.Popen(command, cwd=project, env=environment, stdout=log,
                                                   stderr=subprocess.STDOUT, start_new_session=True)
                        gpu_samples = []
                        try:
                            while process.poll() is None:
                                if time.monotonic() - started > 240:
                                    raise RuntimeError("Benchmark timed out: " + name)
                                gpu_samples.append(gpu_context())
                                time.sleep(1)
                        finally:
                            if process.poll() is None:
                                os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                            leftovers = stability.live_process_group_members(process.pid)
                            if leftovers:
                                os.killpg(process.pid, signal.SIGKILL)
                        if process.returncode != 0 or leftovers or not destination.exists():
                            raise RuntimeError("Benchmark failed: " + name)
                    result = json.loads(destination.read_text())
                    if set(result["cases"]) != {"ash_foundry", "mountain_pass"}:
                        raise RuntimeError("Incomplete scene inventory: " + name)
                    for case in result["cases"].values():
                        target = validate_case(case, args.frames, args.warmup, reduced)
                        all_targets = all_targets and target
                    for environment, case in result["cases"].items():
                        if case.get("environment_id") != environment:
                            raise ValueError("Prepared environment differs from reported case")
                    # If another large compute job appears mid-run, record the
                    # run but refuse an isolated acceptance claim.
                    gpu_after = gpu_context()
                    all_isolated = all_isolated and isolated_gpu_run(gpu_before, gpu_samples, gpu_after, process.pid)
                    report["runs"].append({"name": name, "command": command, "result": destination.name,
                                           "seconds": round(time.monotonic() - started, 3), "gpu_before": gpu_before,
                                           "gpu_samples": gpu_samples, "gpu_after": gpu_after})
                    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
                    print("PASS " + name, flush=True)
            if stability.diagnostic_logs(output):
                raise RuntimeError("Engine/Python diagnostics in benchmark logs")
            if stability.changed_files(frozen, stability.source_manifest(project)):
                raise RuntimeError("Benchmark changed copied runtime inputs")
            report["gpu_isolation_verified"] = all_isolated
            report["isolated_prepared_frame_target"] = qualifies_frame_target(
                all_isolated, all_targets, args.runs, args.warmup, args.frames)
            report["success"] = True
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        if manifest:
            changes = stability.changed_files(manifest, stability.source_manifest(source))
            report["original_input_changes"] = changes
            if changes:
                report["success"] = False
                report["isolated_prepared_frame_target"] = False
                report["error"] = "Runtime source changed during benchmark"
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(("PASS" if report["success"] else "FAIL") + " benchmark report: " + str(output / "report.json"))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
