#!/usr/bin/env python3
"""Measure live combat using four actual ENet processes and one native renderer."""
from __future__ import annotations

import argparse
import datetime
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

import benchmark_combat_performance as rendering
import verify_beta_stability as stability

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = "tests/network_combat_performance_peer.gd"
DRIVER = "tools/benchmark_network_combat_performance.py"


def retire(process: subprocess.Popen) -> list[int]:
    """Own and retire the complete process group, including early-exit children."""
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    leftovers = []
    try:
        process.wait(timeout=10)
    finally:
        leftovers = stability.live_process_group_members(process.pid)
        if leftovers:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return leftovers


def retire_all(processes: list[subprocess.Popen]) -> tuple[list[int], list[dict]]:
    """A failed wait must never prevent retiring the remaining owned groups."""
    leftovers, errors = [], []
    for process in processes:
        try:
            leftovers += retire(process)
        except (OSError, subprocess.SubprocessError) as error:
            errors.append({"pid": process.pid, "error": str(error)})
    return leftovers, errors


def wait_marker(path: Path, process: subprocess.Popen, timeout: float = 45) -> None:
    deadline = time.monotonic() + timeout
    while not path.exists() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(.05)
    if not path.exists():
        raise RuntimeError("Peer did not publish readiness: " + path.name)


def validate_samples(result: dict, frames: int, warmup: int, environment: str, reduced: bool, rendered: bool) -> bool:
    if (result["players"] != 4 or result["enemies"] != 40 or result["min_enemies"] != 40 or result["max_enemies"] != 40 or result["min_live_workers"] != 4
            or result["warmup_frames"] < warmup or result["requested_warmup_frames"] != warmup or result["warmup_seconds"] < 2 or result["measured_frames"] != frames
            or result["reduced_effects"] is not reduced or result["environment"] != environment
            or result["scenario_environment"] != environment or result["requested_environment"] != environment
            or result["rendered"] is not rendered or result["network_error"] or result["microphone_open"]):
        raise ValueError("Incorrect actual scene, renderer, live population or network state")
    if rendered and result["viewport"] != [1920, 1080]:
        raise ValueError("Native render viewport differs from 1920x1080")
    samples = result["frame_samples_ms"]
    if len(samples) != frames or any(type(value) not in (int, float) or not math.isfinite(value) or value <= 0 for value in samples):
        raise ValueError("Invalid or incomplete frame samples")
    recomputed = {"mean": sum(samples) / frames, "p95": sorted(samples)[math.ceil(frames * .95) - 1], "max": max(samples)}
    for metric, value in recomputed.items():
        if not math.isclose(result["frame_ms"][metric], value, abs_tol=1e-6):
            raise ValueError("Reported frame metric differs from raw samples")
    if result["physics_ticks"] <= 0 or result["simulation_seconds"] <= 0 or result["snapshots"] <= 0:
        raise ValueError("Physics, simulation or genuine socket snapshots did not advance")
    if not math.isclose(result["configured_snapshot_interval_seconds"], .05, abs_tol=1e-9):
        raise ValueError("The native snapshot rate was altered")
    target = rendered and 1000 / recomputed["mean"] >= 60 and recomputed["p95"] <= 16.7
    if result["meets_frame_target"] is not target:
        raise ValueError("Frame acceptance differs from raw measured samples")
    return target


def validate_combat(host: dict) -> None:
    if host["worker_projectile_spawns"] <= 0 or host["enemy_attacks"] <= 0:
        raise ValueError("Fixture has no actual worker projectiles or enemy attacks")
    for index in range(4):
        key = str(index + 1)
        if (host["hit_counts"].get(key, 0) <= 0 or host["hit_damage"].get(key, 0) <= 0
                or host["shots_fired"][index] <= 0 or not host["normal_reload_seen"].get(key)
                or host["ammunition_remaining"][index] <= 0 or host["minimum_ammunition"][index] <= 0
                or not 0 <= host["maximum_silent_seconds"][index] <= 5):
            raise ValueError("A worker lacks finite shots, native reload or genuine collision-hit credit")
    if not any(value > 0 for value in host["player_damage_received"]):
        raise ValueError("Enemy attacks never damage the defended crew")
    if (host["initial_ammunition_rounds"] - host["remaining_supply_rounds"] - sum(host["ammunition_remaining"])
            != sum(host["total_shots_fired"])):
        raise ValueError("Prepared finite ammunition is not conserved through normal shots and crate refills")


def qualifies_frame_target(isolated: bool, targets: bool, options: argparse.Namespace) -> bool:
    """Short configurable runs provide diagnostics, never full FPS acceptance."""
    return (rendering.qualifies_frame_target(isolated, targets, options.runs, options.warmup, options.frames)
            and options.scenario == "all" and options.effects == "both")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--warmup", type=int, default=120)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--scenario", choices=("all", "ash_foundry", "mountain_pass"), default="all")
    parser.add_argument("--effects", choices=("both", "standard", "reduced"), default="both")
    parser.add_argument("--render-role", choices=("host", "guest2"), default="host")
    parser.add_argument("--port", type=int, default=25041)
    parser.add_argument("--allow-contended-gpu", action="store_true", help="Diagnostic only; never claims an isolated FPS result")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--smoke", action="store_true", help="All peers headless; proves gameplay/transport only, never native FPS")
    options = parser.parse_args()
    if options.runs < 1 or options.warmup < 60 or options.frames < 120 or not 1024 <= options.port <= 65534:
        parser.error("Require runs>=1, warmup>=60, frames>=120 and a valid unprivileged port pair")
    godot = shutil.which(options.godot)
    if not godot:
        parser.error("Godot executable not found")
    godot = str(Path(godot).resolve())
    source = options.project.resolve()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = (options.output or ROOT / "artifacts" / ("network-combat-performance-" + stamp)).resolve()
    if output.is_relative_to(ROOT) and not output.is_relative_to(ROOT / "artifacts"):
        parser.error("Repository reports must be under artifacts/")
    output.mkdir(parents=True, exist_ok=False)
    fixture_hashes = {path: stability.digest(ROOT / path) for path in (FIXTURE, DRIVER, "tools/benchmark_combat_performance.py", "tools/verify_beta_stability.py")}
    report = {"success": False, "isolated_live_network_frame_target": False, "error": None,
              "headless_smoke": options.smoke, "render_role": options.render_role, "scenario": options.scenario, "effects": options.effects,
              "source_project": str(source), "fixture_sha256": fixture_hashes, "runs": [],
              "scope": "Four actual authenticated ENet processes; one native 1080p host or guest renderer, three headless peers. All host gameplay/weather/actor physics active; only round spawning and camera tracking held. Forty mixed CLASS_ORDER enemies retain AI, movement, abilities and real attacks. Four normal WorkerWeapons fire through sampled held input, collision projectiles, finite ammunition and normal reloads. Fifteen additional dynamic supply crates contain 100 twenty-round packs each on the defense apron; normal focus cycling and sampled reload input consume this bounded stock. Combat, hit and damage deltas begin at the shared warmup-complete barrier and remain monitored until the slowest peer finishes its sample window. Authentic reloads are evidenced over warmup plus measurement; fresh-window reload observations are recorded separately without requiring a reload in every short interval. Each weapon must retain ammunition and never remain silent over five seconds. Whole-run ammunition conservation rejects creation/loss. Crew start at capped level30 so level-up does not replace the temporary HP pool; progression callbacks and real hit credits continue. Initial HP pools are prepared at 500000 for enemies and 1000000 for crew/core/walls, within wire limits; damage remains real. Warmup is at least the requested frames and two seconds. Files carry barriers/reports only, no gameplay transport. No physical microphone, WAN server or saved player settings."}
    manifest = {}
    try:
        initial_gpu = rendering.gpu_context()
        report["initial_gpu"] = initial_gpu
        if not options.smoke and not options.allow_contended_gpu and not rendering.quiet_gpu(initial_gpu):
            raise RuntimeError("GPU not verified idle; use diagnostic --allow-contended-gpu or wait for isolation")
        version = subprocess.check_output([godot, "--version"], text=True).strip()
        if not version.startswith("4.7.2."):
            raise RuntimeError("Godot 4.7.2 required: " + version)
        report["godot_version"] = version
        manifest = stability.source_manifest(source)
        (output / "runtime-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
        environments = ("ash_foundry", "mountain_pass") if options.scenario == "all" else (options.scenario,)
        effects = (False, True) if options.effects == "both" else (options.effects == "reduced",)
        render_slot = 0 if options.smoke else (1 if options.render_role == "host" else 2)
        with tempfile.TemporaryDirectory(prefix="bunkercrew-live-network-combat-") as temporary:
            base = Path(temporary)
            project = base / "project"
            stability.copy_snapshot(source, project, manifest)
            shutil.copy2(ROOT / FIXTURE, project / FIXTURE)
            imported = stability.run_check([godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), "--editor", "--recovery-mode", "--import", "--quit"], project,
                stability.private_environment(base / "import-profile", godot), output / "import.log", 120)
            report["import"] = imported
            if not imported["success"]:
                raise RuntimeError("Private import failed")
            parsed = stability.run_check([godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(project), "--script", "tests/project_parse_test.gd", "--", "--unused-diagnostics", "--no-profile-save", "--no-upnp"], project,
                stability.private_environment(base / "parser-profile", godot), output / "strict-parser.log", 120)
            report["strict_parser"] = parsed
            if not parsed["success"]:
                raise RuntimeError("Strict GDScript compile failed")
            frozen = stability.source_manifest(project)
            isolated = not options.smoke and not options.allow_contended_gpu and rendering.quiet_gpu(initial_gpu)
            targets = True
            for repeat in range(options.runs):
                for environment in environments:
                    for reduced in effects:
                        name = f"{repeat + 1}-{environment}-{'reduced' if reduced else 'standard'}-{options.render_role}"
                        case_output = output / name
                        case_output.mkdir()
                        gpu_before = rendering.gpu_context()
                        if not options.smoke and not options.allow_contended_gpu and not rendering.quiet_gpu(gpu_before):
                            raise RuntimeError("GPU became busy before " + name)
                        prefix = str(base / name / "coordination")
                        Path(prefix).parent.mkdir()
                        processes = []
                        gpu_samples = []
                        started = time.monotonic()
                        leftovers = []
                        cleanup_errors = []
                        try:
                            for slot in range(1, 5):
                                role = "host" if slot == 1 else "guest" + str(slot)
                                env = stability.private_environment(base / (name + "-" + role), godot)
                                env.update({"LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_GAMEPLAY_PATH": prefix,
                                    "LASTSHIFT_TEST_PORT": str(options.port), "LASTSHIFT_TEST_DISCOVERY_PORT": str(options.port + 1),
                                    "BUNKERCREW_PERF_ENVIRONMENT": environment, "BUNKERCREW_PERF_REDUCED": "1" if reduced else "0",
                                    "BUNKERCREW_PERF_RENDER_SLOT": str(render_slot), "BUNKERCREW_PERF_WARMUP": str(options.warmup), "BUNKERCREW_PERF_FRAMES": str(options.frames),
                                    "BUNKERCREW_PERF_CAPTURE": "1" if options.capture and repeat == 0 else "0", "BUNKERCREW_PERF_CASE_OUTPUT": str(case_output)})
                                command = [godot, "--debug", "--audio-driver", "Dummy", "--path", str(project)]
                                if slot != render_slot:
                                    command.append("--headless")
                                else:
                                    command += ["--position", "-30000,-30000"]
                                command += ["--script", FIXTURE, "--", "--no-profile-save", "--no-upnp"]
                                with (case_output / (role + ".log")).open("x") as log:
                                    process = subprocess.Popen(command, cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                                processes.append(process)
                                wait_marker(Path(prefix + (".room.json" if slot == 1 else f".joined{slot}.json")), process)
                            deadline = time.monotonic() + 240
                            while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
                                if any(process.poll() not in (None, 0) for process in processes):
                                    raise RuntimeError("An actual peer failed during live combat: " + name)
                                if not options.smoke: gpu_samples.append(rendering.gpu_context())
                                time.sleep(1)
                            for slot, process in enumerate(processes, 1):
                                role = "host" if slot == 1 else "guest" + str(slot)
                                text = (case_output / (role + ".log")).read_text()
                                marker = re.search(rf"NETWORK_GAMEPLAY_PASS {role} checks=(\d+) failures=0", text)
                                if process.poll() != 0 or not marker:
                                    raise RuntimeError("Actual peer failed: " + name + "/" + role)
                            host = json.loads(Path(prefix + ".host_report.json").read_text())
                            peers = [host] + [json.loads(Path(prefix + f".peer_report{slot}.json").read_text()) for slot in (2, 3, 4)]
                            for slot, peer in enumerate(peers, 1):
                                target = validate_samples(peer, options.frames, options.warmup, environment, reduced, slot == render_slot)
                                if slot == render_slot: targets = targets and target
                            validate_combat(host)
                            if host["combat_window_seconds"] < max(peer["elapsed_seconds"] for peer in peers):
                                raise ValueError("Combat monitoring ended before the slowest peer completed native samples")
                            result = {"peers": peers, "elapsed_seconds": round(time.monotonic() - started, 3), "actual_processes": 4, "mode": "direct-enet", "render_slot": render_slot}
                            (case_output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                        finally:
                            leftovers, cleanup_errors = retire_all(processes)
                            if cleanup_errors:
                                report.setdefault("cleanup_errors", []).extend(cleanup_errors)
                            for marker in Path(prefix).parent.glob("coordination.*.json"):
                                shutil.copy2(marker, case_output / marker.name)
                        if leftovers:
                            raise RuntimeError("A benchmark peer left owned child processes")
                        if cleanup_errors:
                            raise RuntimeError("Benchmark peer retirement failed: " + str(cleanup_errors))
                        if stability.diagnostic_logs(case_output):
                            raise RuntimeError("Engine/Python diagnostics in peer logs")
                        if stability.changed_files(frozen, stability.source_manifest(project)):
                            raise RuntimeError("Combat fixture changed copied runtime inputs")
                        gpu_after = rendering.gpu_context()
                        isolated = isolated and rendering.isolated_gpu_run(gpu_before, gpu_samples, gpu_after, processes[render_slot - 1].pid)
                        report["runs"].append({"name": name, "result": str((case_output / "result.json").relative_to(output)), "gpu_before": gpu_before, "gpu_samples": gpu_samples, "gpu_after": gpu_after})
                        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
                        print("PASS " + name, flush=True)
            if stability.diagnostic_logs(output):
                raise RuntimeError("Diagnostics in benchmark import/parser/peer logs")
            report["gpu_isolation_verified"] = isolated
            report["isolated_live_network_frame_target"] = qualifies_frame_target(isolated, targets, options)
            report["success"] = True
    except KeyboardInterrupt:
        report["interrupted"] = True
        report["error"] = "Owned benchmark interrupted; partial results cannot pass the aggregate"
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        if manifest:
            changed = stability.changed_files(manifest, stability.source_manifest(source))
            report["original_input_changes"] = changed
            if changed:
                report["success"] = False
                report["isolated_live_network_frame_target"] = False
        if any(stability.digest(ROOT / path) != digest for path, digest in fixture_hashes.items()):
            report["success"] = False
            report["isolated_live_network_frame_target"] = False
            report["error"] = "Fixture/driver helpers changed during the benchmark"
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"success": report["success"], "isolated_live_network_frame_target": report["isolated_live_network_frame_target"], "error": report["error"], "output": str(output)}), flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
