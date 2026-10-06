#!/usr/bin/env python3
"""Four actual peers through the public TLS relay, including exported binaries.

Local Linux/Wine runs cannot establish two Internet connections or native
Windows acceptance. Coordination files carry barriers, not gameplay state.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlsplit

import verify_beta_stability as stability
import validate_beta as exports

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = {"tire": ("internet_coop_peer.gd", "BetaInternetCoopCheck"),
            "journey": ("internet_journey_peer.gd", "BetaInternetJourneyCheck"),
            "leave": ("internet_lifecycle_peer.gd", "BetaInternetLifecycleCheck"),
            "crash": ("internet_lifecycle_peer.gd", "BetaInternetLifecycleCheck")}
MARKER = re.compile(r"NETWORK_GAMEPLAY_PASS (host|guest[234]) checks=(\d+) failures=(\d+)")
PREPARED_STATES = {
    "tire": "Prepared wave20 victory, paid MG stock, capped guard damage and prepared sight lines; actual departure, defense, mechanic reconnect and repair takeover; ends during repair.",
    "journey": "Prepared campaign victory, researched SAN upgrades, finite travel/MG stock, tire checkpoint and road-end positions; actual ignition, driving/fire/reload, reconnect, complete tire repair, reboarding, harbor occupation and next defense; enemies removed during the full-repair stage, defense covered separately by tire.",
    "leave": "Actual four-player character choice/start, guest pause, host resume/rematch; round spawning halted after start/rematch; intentional guest and host departure.",
    "crash": "Actual four-player character choice/start, guest pause, host resume/rematch; round spawning halted after start/rematch; intentional guest departure and actual host process SIGKILL.",
}


def admission_cooldown(seconds: float) -> float:
    """Space fresh rooms without relaxing the production admission limiter."""
    if not math.isfinite(seconds) or not 0 <= seconds <= 300:
        raise ValueError("Admission cooldown must be finite and between 0 and 300 seconds")
    started = time.monotonic()
    deadline = started + seconds
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return time.monotonic() - started
        time.sleep(min(remaining, 1.0))


def read_json(path: Path) -> dict:
    return json.loads(path.read_text()) if path.is_file() else {}


def await_marker(path: Path, process: subprocess.Popen, seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while not path.is_file() and process.poll() is None and time.monotonic() < deadline:
        time.sleep(.05)
    if not path.is_file():
        raise RuntimeError("Peer did not publish " + path.name)


def retire(processes: list[subprocess.Popen]) -> list[int]:
    leftovers = []
    for process in processes:
        try:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
            active = stability.live_process_group_members(process.pid)
            if active:
                leftovers.extend(active)
                os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            leftovers.append(process.pid)
    return leftovers


def inspect_peer(log: Path, code: int, killed_host: bool, expected_role: str | None = None) -> dict:
    content = log.read_text(errors="replace")
    if stability.DIAGNOSTIC.search(stability.ANSI.sub("", content)):
        raise RuntimeError("Runtime diagnostic: " + str(log))
    if killed_host:
        if code != -signal.SIGKILL:
            raise RuntimeError("Hard host-loss fixture was not actually killed")
        return {"intentionally_killed": True, "exit_code": code}
    marker = MARKER.search(content)
    if code != 0 or not marker or int(marker[3]) or int(marker[2]) <= 0 or (expected_role is not None and marker[1] != expected_role):
        raise RuntimeError("Failed peer: " + str(log))
    return {"exit_code": code, "checks": int(marker[2]), "failures": int(marker[3])}


def package_identity(binary: Path) -> dict:
    libraries = {}
    for path in sorted(binary.parent.rglob("*")):
        if path.is_file() and path.suffix.lower() in (".dll", ".so"):
            libraries[path.relative_to(binary.parent).as_posix()] = {"sha256": stability.digest(path)}
    checksum = stability.digest(binary)
    info = read_json(binary.parent / "BUILD_INFO.json")
    if not all(isinstance(info.get(key), str) and info[key] for key in ("version", "network_protocol", "engine", "platform")) or type(info.get("world_revision")) is not int or info["world_revision"] < 1 or not re.fullmatch(r"[0-9a-f]{64}", str(info.get("source_sha256", ""))):
        raise RuntimeError("Package requires complete BUILD_INFO.json: " + str(binary))
    if info.get("executable_sha256", checksum) != checksum:
        raise RuntimeError("Package executable differs from its build identity: " + str(binary))
    native = info.get("live_music", {})
    if not isinstance(native, dict) or native.get("library") not in libraries or native.get("sha256") != libraries[native["library"]]["sha256"]:
        raise RuntimeError("Package native library differs from its build identity: " + str(binary))
    return {"sha256": checksum, "native_libraries": libraries, "build_info": info}


def expected_source_identity(project: Path) -> tuple[str, str, int]:
    version = re.search(r'^config/version="([^"\n]+)"', (project / "project.godot").read_text(), re.M)
    protocol = (project / "scripts/network_protocol.gd").read_text()
    build = re.search(r'^const BUILD\s*:=\s*"([^"\n]+)"', protocol, re.M)
    revision = re.search(r'^const WORLD_REVISION\s*:=\s*(\d+)', protocol, re.M)
    if not version or not build or not revision:
        raise RuntimeError("Source snapshot has no complete build identity")
    return version[1], build[1], int(revision[1])


def require_source_unchanged(project: Path, expected: dict) -> None:
    changed = stability.changed_files(expected, stability.source_manifest(project))
    if changed:
        raise RuntimeError("Source changed during Internet scenario: " + ", ".join(changed[:12]))


def validate_peer_identities(records: list[dict], source: bool, packages: dict,
                             source_identity: tuple[str, str, int] | None = None) -> None:
    if len(records) != 4 or {record.get("role") for record in records} != {"host", "guest2", "guest3", "guest4"}:
        raise RuntimeError("Identity proof requires four distinct peer roles")
    actual_builds = set()
    source_hashes = set()
    for record in records:
        identity = record.get("identity", {})
        platform = record.get("platform")
        if platform not in ("linux", "windows") or (source and platform != "linux") or identity.get("os") != ("Linux" if platform == "linux" else "Windows"):
            raise RuntimeError("Actual peer OS does not match the declared platform")
        if type(identity.get("exported_template")) is not bool or identity["exported_template"] == source:
            raise RuntimeError("Actual peer must prove the requested source/exported runtime")
        if not all(isinstance(identity.get(key), str) and identity[key] for key in ("application_version", "network_build", "engine", "executable")) or type(identity.get("world_revision")) is not int or identity["world_revision"] < 1 or not identity["engine"].startswith("4.7.2"):
            raise RuntimeError("Actual peer has an incomplete or unsupported build identity")
        actual = (identity["application_version"], identity["network_build"], identity["world_revision"])
        actual_builds.add(actual)
        if source:
            if source_identity is None or actual != source_identity:
                raise RuntimeError("Actual peer does not match the frozen source identity")
        else:
            info = packages.get(platform, {}).get("build_info", {})
            expected = (info.get("version"), info.get("network_protocol"), info.get("world_revision"))
            if actual != expected or not str(info.get("engine", "")).startswith("4.7.2") or info.get("platform") != ("ubuntu-x86_64" if platform == "linux" else "windows-x86_64"):
                raise RuntimeError("Actual peer identity does not match its exported package")
            source_hashes.add(info.get("source_sha256"))
    if len(actual_builds) != 1 or (not source and (len(source_hashes) != 1 or not re.fullmatch(r"[0-9a-f]{64}", str(next(iter(source_hashes)))))):
        raise RuntimeError("Build/source identities differ across actual peers")


def run_case(args, project: Path, case: str, folder: Path, output: Path) -> dict:
    output.mkdir()
    prefix = folder / "run"
    processes = []
    records = []
    fixture, main_loop = FIXTURES[case]
    platforms = args.platforms.split(",")
    manifest = None
    launcher = None
    frozen_inputs = stability.source_manifest(project) if args.source else None
    source_identity = expected_source_identity(project) if args.source else None
    data = {"case": case, "success": False, "peers": records, "relay_url": args.relay,
            "actual_client_machines": 1, "two_internet_connections_verified": False,
            "native_windows_verified": False}
    if not args.source:
        binaries = {platform: package_identity(getattr(args, platform))
                    for platform in set(platforms)}
        manifest = {"binaries": binaries, "processes": []}
        launcher = exports.BetaValidation(args, folder, manifest)
        launcher.output = output
        exports.DIAGNOSTIC_CLASSES[fixture] = main_loop
    started = time.monotonic()
    try:
        if launcher is not None and "windows" in platforms:
            launcher.initialize_wine()
        for slot, platform in enumerate(platforms, 1):
            role = "host" if slot == 1 else "guest" + str(slot)
            if args.source:
                cwd = project
                environment = dict(os.environ)
                for kind in ("DATA", "CONFIG", "CACHE", "STATE"):
                    environment["XDG_" + kind + "_HOME"] = str(folder / role / kind.lower())
                command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                           "--script", "tests/" + fixture, "--", "--no-profile-save", "--no-upnp"]
            else:
                cwd, environment = launcher.environment(role)
            shared_prefix = exports.windows_path(prefix) if platform == "windows" else str(prefix)
            environment.update({"LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": shared_prefix,
                                "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_PARTY_RELAY": args.relay,
                                "BUNKERCREW_HOST_DEPARTURE": case,
                                "BUNKERCREW_EXPORTED_PEER": "0" if args.source else "1"})
            log = output / (role + ".log")
            if args.source:
                with log.open("x") as stream:
                    process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=stream,
                                               stderr=subprocess.STDOUT, start_new_session=True)
                metadata = {"runtime": "Linux source/editor", "command": command}
            else:
                # The shared launcher copies and hashes actual package binaries
                # and libraries and chooses a registered class from their PCK.
                previous_output = launcher.output
                launcher.output = output
                process, metadata, _ = launcher.start_game(role, platform, fixture, environment, cwd)
                launcher.output = previous_output
                metadata["runtime"] = "Linux native export" if platform == "linux" else "Windows PE under Wine"
            processes.append(process)
            records.append({"role": role, "platform": platform, "runtime": metadata["runtime"],
                            "identity": {}, "pid": process.pid,
                            "command": metadata.get("command", []), "log": role + ".log"})
            await_marker(Path(str(prefix) + (".room.json" if slot == 1 else ".joined" + str(slot) + ".json")), process, 20)
            records[-1]["identity"] = read_json(Path(str(prefix) + ".identity" + str(slot) + ".json"))
        killed = False
        deadline = time.monotonic() + 130
        while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
            if case == "crash" and not killed and Path(str(prefix) + ".host_departure_ready.json").is_file():
                os.killpg(processes[0].pid, signal.SIGKILL)
                killed = True
            time.sleep(.05)
        for index, process in enumerate(processes):
            if process.poll() is None:
                raise RuntimeError("Four-peer scenario timed out")
            records[index].update(inspect_peer(output / records[index]["log"], process.returncode,
                                                case == "crash" and index == 0 and killed, records[index]["role"]))
        validate_peer_identities(records, args.source, manifest["binaries"] if manifest else {}, source_identity)
        data = {"case": case, "success": True, "peers": records, "relay_url": args.relay,
                "seconds": round(time.monotonic() - started, 3), "transport": "verified-certificate wss",
                "actual_client_machines": 1, "two_internet_connections_verified": False,
                "native_windows_verified": False,
                "prepared_state": PREPARED_STATES[case],
                "evidence": read_json(Path(str(prefix) + ".final.json")),
                "host_departure_observations": {str(slot): read_json(Path(str(prefix) + ".host_closed" + str(slot) + ".json")) for slot in (2,3)}}
        if manifest:
            data["package_identities"] = manifest["binaries"]
            for platform, identity in manifest["binaries"].items():
                if package_identity(getattr(args, platform)) != identity:
                    raise RuntimeError("Package changed during the Internet run")
        if frozen_inputs is not None:
            require_source_unchanged(project, frozen_inputs)
    except Exception as error:
        data["success"] = False
        data["error"] = str(error)
    finally:
        leftovers = retire(processes)
        data["owned_process_group_leftovers"] = leftovers
        if launcher is not None:
            try:
                if launcher.wineprefix.exists(): launcher.shutdown_wine()
                data["wine_runtime"] = {key: manifest[key] for key in ("wine_version", "wine_runtime_files", "wine_cleanup_success") if key in manifest}
            except Exception as error:
                data["success"] = False
                data["cleanup_error"] = str(error)
        if leftovers:
            data["success"] = False
            data["cleanup_error"] = "Owned test processes left behind: " + repr(leftovers)
        (output / "result.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--source", action="store_true", help="Source diagnostics only, not exported acceptance")
    parser.add_argument("--linux", type=Path)
    parser.add_argument("--windows", type=Path)
    parser.add_argument("--wine", default=shutil.which("wine") or "wine")
    parser.add_argument("--wineserver", default=shutil.which("wineserver") or "wineserver")
    parser.add_argument("--wine-extra-dll", type=Path, action="append", default=[])
    parser.add_argument("--wine-timeout", type=float, default=120)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--platforms", default="linux,linux,linux,linux")
    parser.add_argument("--relay", default="wss://bunkercrew.vibechain.rocks/ws")
    parser.add_argument("--case", choices=("all", *FIXTURES), default="all")
    parser.add_argument("--between-cases-seconds", type=float, default=45,
                        help="Explicit cooldown between rooms; keeps public admission limits intact (default: 45s)")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.port, args.discovery_port = 24937, 24938
    platforms = args.platforms.split(",")
    if len(platforms) != 4 or any(p not in ("linux", "windows") for p in platforms):
        parser.error("--platforms requires four linux/windows peers")
    if args.source and set(platforms) != {"linux"}:
        parser.error("Source diagnostics here run only on the actual Linux host")
    if not args.source and any(not getattr(args, p) or not getattr(args, p).is_file() for p in set(platforms)):
        parser.error("A package executable is required for each selected platform")
    if args.wine_timeout <= 0 or any(not path.is_file() or path.suffix.lower() != ".dll" for path in args.wine_extra_dll):
        parser.error("Use a positive Wine deadline and existing --wine-extra-dll files")
    if not math.isfinite(args.between_cases_seconds) or not 0 <= args.between_cases_seconds <= 300:
        parser.error("Use a finite admission cooldown between 0 and 300 seconds")
    parsed = urlsplit(args.relay)
    if parsed.scheme != "wss" or not parsed.hostname or parsed.path != "/ws":
        parser.error("Use the configured TLS relay /ws endpoint")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"success": False, "full_internet_acceptance": False, "runs": [], "error": None,
              "scope": "Four actual peers from one Linux machine through public TLS. Windows PE under Wine is compatibility only; native Windows, two Internet connections and physical LAN remain separate.",
              "between_cases_seconds": args.between_cases_seconds, "admission_cooldowns": []}
    try:
        with urllib.request.urlopen(urllib.request.Request("https://" + parsed.netloc + "/healthz",
                    headers={"User-Agent": "Godot/4.7.2"}), timeout=12) as response:
            report["relay_health"] = json.loads(response.read(4096))
        with tempfile.TemporaryDirectory(prefix="bunkercrew-internet-coop-") as directory:
            base = Path(directory)
            project = args.project.resolve()
            if args.source:
                manifest = stability.source_manifest(project)
                frozen = base / "project"
                stability.copy_snapshot(project, frozen, manifest)
                project = frozen
                environment = stability.private_environment(base / "import", args.godot)
                imported = stability.run_check([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                    "--editor", "--recovery-mode", "--import", "--quit"], project, environment, output / "import.log", 180)
                if not imported["success"]: raise RuntimeError("Private source import failed")
                (output / "source-inputs.json").write_text(json.dumps(stability.source_manifest(project), indent=2) + "\n")
            for case in FIXTURES if args.case == "all" else (args.case,):
                if report["runs"]:
                    print("Public relay admission cooldown: " + str(args.between_cases_seconds) + "s", flush=True)
                    report["admission_cooldowns"].append({"before_case": case,
                        "seconds": round(admission_cooldown(args.between_cases_seconds), 3)})
                folder = base / case
                folder.mkdir()
                result = run_case(args, project, case, folder, output / case)
                report["runs"].append(result)
                if not result["success"]:
                    raise RuntimeError(result.get("error", result.get("cleanup_error", "Internet scenario failed")))
                print("PASS public TLS " + case, flush=True)
            report["success"] = True
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    finally:
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(("PASS " if report["success"] else "FAIL ") + str(output / "report.json"))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
