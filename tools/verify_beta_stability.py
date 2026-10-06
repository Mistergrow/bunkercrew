#!/usr/bin/env python3
"""Check a copied, frozen project without touching player or editor data."""

from __future__ import annotations

import argparse
import ast
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = ("scripts", "scenes", "shaders", "assets", "locales", "addons",
               "tests", "tools", "server", "docs", "native")
ROOT_FILES = ("project.godot", "export_presets.cfg", "default_bus_layout.tres",
              "README.md", "CHANGELOG.md", "AGENTS.md", ".gitignore")
EXCLUDED_PARTS = {"__pycache__", ".venv", ".godot", "build-linux", "build-windows"}
GROUPS = {
    "economy": (
        "gameplay_boundary", "gameplay_owner_boundary", "interaction_owner_boundary",
        "resource_ledger_hardening", "supply_storage", "storage_reserve_followup",
        "campaign_checkpoint_consistency", "campaign_restore_storage", "campaign_stock_bounds",
        "campaign_completion", "campaign_production", "expedition_preparation_checkpoint",
        "campaign_revisit",
        "expedition_transition_rollback", "convoy_personal_checkpoint", "convoy_terminal_resume",
        "offline_campaign_resume", "medic_campaign_cargo", "medical_lifecycle",
        "medical_ownership", "medic_logistics_ownership", "medical", "field_medic", "convoy_medical_priority",
        "worker_medical_visual",
        "wave_roster_stability", "solo_story_state", "solo_story_runtime", "solo_story_recruits",
        "solo_story_walk", "story_flow_review",
    ),
    "lifecycle": (
        "restart_lifecycle", "presentation_lifecycle_hardening", "station_shader_lifetime",
        "story_dialogue_lifecycle", "character_voice_identity", "character_party_identity", "worker_visual_identity", "audio_exit_drain", "audio_fx_dependency_ownership",
        "audio_defaults", "audio_settings", "ui", "ui_panel_hardening", "character_selection_presentation", "technology_presentation",
        "ui_modal_shortcuts", "options_ui", "personnel_presentation", "session_action_presentation", "menu_rave_logo",
        "support_report", "p1_controller_routing", "p1_ui_navigation", "p1_first_defense",
        "help_manual", "options_layout_navigation", "social_chat_ui",
        "cinematic_dev_player", "cinematic_dev_player_fx", "travel_cinematic_audio", "classic_scenery",
        "sky_traffic", "sky_cloud_zoom",
        "courtyard_defense", "courtyard_art",
        "beta_asset_export",
    ),
    "network": (
        "network_protocol_hardening", "network_control_validation", "network_structure_validation",
        "network_snapshot_boundary", "network_lifecycle_boundary", "network_wallclock",
        "network_world_revision", "network_session_hardening", "network_pause_resume",
        "network_social_retry", "network_backpressure", "network_transport_hardening",
        "chat_session_lifecycle", "voice_lifecycle", "voice_member_lifecycle",
        "social_wallclock", "router_mapping_cleanup",
        "network_input_catchup", "network_drop_catchup", "network_fire_catchup", "network_relay_silence",
    ),
    "performance": (
        "actor_wetness", "rain_collision", "rain_spatial", "rain_index_cache",
        "weather_contour_batch", "rain_prop_surfaces", "surface_weather",
        "weather_world_isolation", "weather_hotpath_optimization", "weather_cache_followup",
        "weather_efficiency",
        "enemy_weapon_redraw", "enemy_motion", "network_snapshot_hotpath", "network_world",
        "network_combat_input",
        "vegetation_outskirts",
    ),
    "music": (
        "dance_world_isolation", "music_synthesis_fx", "music_beat_clock", "music_beat_continuity",
        "rhythm_dance_timing", "worker_dance_repertoire", "worker_dance_identity", "dance_unlock", "dance_gameplay",
        "audio_balance_adjustment", "audio_bus_edit", "live_music_integration",
    ),
}
ANSI = re.compile(r"\x1b\[[0-9;]*m")
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR:|ERROR[:\s]|WARNING[:\s]|Traceback \(most recent call last\):|Exception in thread ).*$", re.MULTILINE)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_manifest(root: Path) -> dict[str, str]:
    files = []
    for name in ROOT_FILES:
        path = root / name
        if path.is_symlink():
            raise RuntimeError(f"Input symlink needs explicit review: {path.relative_to(root)}")
        if path.is_file():
            files.append(path)
    for directory in DIRECTORIES:
        directory_root = root / directory
        if directory_root.is_symlink():
            raise RuntimeError(f"Input symlink needs explicit review: {directory}")
        for path in directory_root.rglob("*"):
            relative = path.relative_to(root)
            if EXCLUDED_PARTS.intersection(relative.parts) or path.name == ".env":
                continue
            if path.is_symlink():
                raise RuntimeError(f"Input symlink needs explicit review: {relative}")
            if path.is_file() and path.suffix not in (".pyc", ".tmp"):
                files.append(path)
    return {path.relative_to(root).as_posix(): digest(path) for path in sorted(files)}


def changed_files(before: dict[str, str], after: dict[str, str]) -> list[str]:
    return sorted(name for name in before.keys() | after.keys()
                  if before.get(name) != after.get(name))


def copy_snapshot(root: Path, destination: Path, manifest: dict[str, str]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for relative, expected in manifest.items():
        original = root / relative
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        if digest(target) != expected:
            raise RuntimeError(f"Input changed while copying: {relative}")
    changes = changed_files(manifest, source_manifest(root))
    if changes:
        raise RuntimeError("Input changed while copying: " + ", ".join(changes[:12]))


def private_environment(directory: Path, godot: str) -> dict[str, str]:
    env = dict(os.environ)
    for kind in ("DATA", "CONFIG", "CACHE"):
        env[f"XDG_{kind}_HOME"] = str(directory / kind.lower())
    # Integration drivers select Godot through PATH. Make that selection agree
    # with the compiler rather than silently using another installed engine.
    binary_directory = directory / "bin"
    binary_directory.mkdir(parents=True)
    (binary_directory / "godot").symlink_to(godot)
    env["PATH"] = str(binary_directory) + os.pathsep + env.get("PATH", "")
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def live_process_group_members(group_id: int) -> list[int]:
    # The driver may exit without waiting for its game/relay children. Zombies
    # have already stopped; active members must fail the gate and be retired.
    if sys.platform == "linux":
        members = []
        for path in Path("/proc").iterdir():
            if not path.name.isdigit():
                continue
            try:
                fields = (path / "stat").read_text().rsplit(")", 1)[1].split()
                if int(fields[2]) == group_id and fields[0] != "Z":
                    members.append(int(path.name))
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
        return sorted(members)
    try:
        os.killpg(group_id, 0)
    except ProcessLookupError:
        return []
    return [group_id]


def diagnostic_logs(directory: Path) -> dict[str, list[str]]:
    findings = {}
    for path in sorted(directory.rglob("*.log")):
        issues = DIAGNOSTIC.findall(ANSI.sub("", path.read_text(errors="replace")))
        if issues:
            findings[path.relative_to(directory).as_posix()] = issues
    return findings


def run_check(command: list[str], cwd: Path, env: dict[str, str], log: Path,
              timeout: int) -> dict:
    started = time.monotonic()
    timed_out = False
    leftover_children = []
    with log.open("x") as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            # Drivers may own several Godot/relay children. Kill only this
            # newly created process group, never another game or editor.
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            timed_out = True
            code = process.returncode
        if not timed_out:
            leftover_children = live_process_group_members(process.pid)
            if leftover_children:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    content = ANSI.sub("", log.read_text(errors="replace"))
    issues = DIAGNOSTIC.findall(content)
    return {"command": command, "exit_code": code, "timed_out": timed_out,
            "leftover_children": leftover_children,
            "seconds": round(time.monotonic() - started, 3), "diagnostics": issues,
            "success": code == 0 and not timed_out and not issues and not leftover_children,
            "log": log.name, "tail": content.splitlines()[-8:]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4.7.2 executable")
    parser.add_argument("--output", type=Path, help="New report directory; existing output is refused")
    parser.add_argument("--compiler-only", action="store_true", help="Import/parser/languages/Python only; no P0 regression claim")
    parser.add_argument("--group", action="append", choices=GROUPS, help="Select regression groups; default runs all")
    parser.add_argument("--timeout", type=int, default=240, help="Seconds per check")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    godot = shutil.which(args.godot)
    if not godot:
        parser.error("Godot executable not found")
    godot = str(Path(godot).resolve())
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = (args.output or ROOT / "artifacts" / f"p0-stability-{stamp}").resolve()
    if output.is_relative_to(ROOT) and not output.is_relative_to(ROOT / "artifacts"):
        parser.error("Reports inside this repository must be under artifacts/")
    output.mkdir(parents=True, exist_ok=False)
    report = {"success": False, "recorded_utc": stamp, "selected_groups": [], "runs": [],
              "scope": "Copied source/runtime inputs, fresh import cache, isolated profiles. Prepared regression states and loopback tests do not replace normal campaign play, WAN, Windows or endurance acceptance.",
              "compiler_only": args.compiler_only, "error": None}
    original_manifest: dict[str, str] = {}
    try:
        original_manifest = source_manifest(ROOT)
        (output / "source-inputs.json").write_text(json.dumps(original_manifest, indent=2) + "\n")
        with tempfile.TemporaryDirectory(prefix="bunkercrew-p0-snapshot-") as temporary:
            base = Path(temporary)
            snapshot = base / "project"
            copy_snapshot(ROOT, snapshot, original_manifest)
            engine = subprocess.check_output([godot, "--version"], text=True).strip()
            report["godot_version"] = engine
            if not engine.startswith("4.7.2."):
                raise RuntimeError("Matching Godot 4.7.2 is required: " + engine)

            def execute(name: str, command: list[str]) -> None:
                environment = private_environment(base / ("profile-" + name), godot)
                record = {"name": name, **run_check(command, snapshot, environment,
                                                   output / (name + ".log"), args.timeout)}
                report["runs"].append(record)
                (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
                print(("PASS " if record["success"] else "FAIL ") + name, flush=True)
                if not record["success"]:
                    raise RuntimeError(f"Failed {name}; see {output / record['log']}")

            base_command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(snapshot)]
            execute("import", base_command + ["--editor", "--recovery-mode", "--import", "--quit"])
            imported_manifest = source_manifest(snapshot)
            report["import_normalized_files"] = changed_files(original_manifest, imported_manifest)
            execute("project_parse", base_command + ["--debug", "--script", "tests/project_parse_test.gd", "--",
                                                       "--unused-diagnostics", "--no-profile-save", "--no-upnp"])
            parsed = re.search(r"PROJECT PARSE: (\d+) scripts, 0 failures", (output / "project_parse.log").read_text())
            if not parsed or int(parsed[1]) == 0:
                raise RuntimeError("Parser did not complete its script inventory")
            report["parsed_scripts"] = int(parsed[1])
            execute("locales", [sys.executable, "tools/check_locales.py", "--json", str(output / "locales.json")])
            python_files = [snapshot / relative for relative in imported_manifest if relative.endswith(".py")]
            for path in python_files:
                ast.parse(path.read_text(), filename=str(path.relative_to(snapshot)))
            report["parsed_python_files"] = len(python_files)
            execute("stability_runner_unit", [sys.executable, "tests/beta_stability_runner_test.py"])
            execute("performance_runner_unit", [sys.executable, "tests/combat_performance_runner_test.py"])
            execute("network_performance_runner_unit", [sys.executable, "tests/network_combat_performance_runner_test.py"])
            execute("internet_runner_unit", [sys.executable, "tests/internet_coop_runner_test.py"])
            execute("internet_ssh_runner_unit", [sys.executable, "tests/internet_ssh_peer_test.py"])
            execute("network_candidate_unit", [sys.executable, "tests/network_beta_candidate_test.py"])
            execute("network_impairment_runner_unit", [sys.executable, "tests/network_impairment_runner_test.py"])
            execute("locales_checker_unit", [sys.executable, "tests/locales_checker_test.py"])
            execute("beta_asset_audit", [sys.executable, "tests/beta_asset_audit_test.py"])
            selected = [] if args.compiler_only else (args.group or list(GROUPS))
            report["selected_groups"] = list(dict.fromkeys(selected))
            suites = list(dict.fromkeys(suite for group in selected for suite in GROUPS[group]))
            for suite in suites:
                timing = ["--fixed-fps", "60"] if suite == "solo_story_walk" else []
                execute(suite, base_command + timing + ["--debug", "--script", f"tests/{suite}_test.gd", "--",
                                                        "--no-profile-save", "--no-upnp"])
            if "network" in selected:
                execute("social_real_deadlines", [sys.executable, "tools/verify_social_deadlines.py",
                        "--output", str(output / "social_real_deadlines")])
                for suite in ("relay", "social_service", "social_store_capacity"):
                    execute(suite + "_python", [sys.executable, f"tests/{suite}_test.py"])
                for suite in ("network_blackhole", "network_transition_transport"):
                    execute(suite, [sys.executable, f"tests/{suite}_test.py",
                                    "--output", str(output / suite)])
                for relay in (False, True):
                    name = "four_peers_relay" if relay else "four_peers_direct"
                    command = [sys.executable, "tests/convoy_coop_defense_network_test.py",
                               "--output", str(output / name)]
                    execute(name, command + (["--relay"] if relay else []))
            snapshot_changes = changed_files(imported_manifest, source_manifest(snapshot))
            report["snapshot_changes_during_checks"] = snapshot_changes
            if snapshot_changes:
                raise RuntimeError("Tests changed frozen project inputs: " + ", ".join(snapshot_changes[:12]))
            fixtures = snapshot / "artifacts"
            if fixtures.is_dir():
                shutil.copytree(fixtures, output / "fixture-results")
            # A successful driver can still hide a warning in a guest or relay
            # file. Include every fresh nested log before declaring acceptance.
            report["nested_log_diagnostics"] = diagnostic_logs(output)
            if report["nested_log_diagnostics"]:
                raise RuntimeError("Diagnostics in nested logs: " + ", ".join(report["nested_log_diagnostics"]))
            report["regression_suites"] = len(suites)
            report["success"] = True
    except (OSError, RuntimeError, SyntaxError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        if original_manifest:
            try:
                report["original_input_changes"] = changed_files(original_manifest, source_manifest(ROOT))
                if report["original_input_changes"]:
                    report["success"] = False
                    report["error"] = "Working inputs changed; rerun after freezing them: " + ", ".join(report["original_input_changes"][:12])
            except (OSError, RuntimeError) as error:
                report["success"] = False
                report["error"] = "Cannot verify final working inputs: " + str(error)
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'PASS' if report['success'] else 'FAIL'} stability report: {output / 'result.json'}", flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
