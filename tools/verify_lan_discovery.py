#!/usr/bin/env python3
"""Run four actual peers through the default adapter-bound LAN discovery path.

All peers share this machine. The production broadcast and loopback fallback
remain enabled; this does not certify two physical LAN devices or their router.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import validate_beta as exports
import verify_beta_stability as stability
import verify_internet_coop as internet

ROOT = Path(__file__).resolve().parents[1]


def run(args, temporary, project, output):
    platforms = args.platforms.split(",")
    prefix = temporary / "coordination"
    processes = []
    records = []
    identities = {}
    launcher = None
    report = {"success": False, "scope": "One host machine; default LAN adapter broadcast and loopback fallback",
              "physical_two_device_lan_verified": False, "native_windows_verified": False,
              "transport": "Actual UDP discovery followed by authenticated ENet",
              "ports": {"game": args.port, "discovery": args.discovery_port}, "peers": records}
    try:
        for port in (args.port, args.discovery_port):
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.bind(("0.0.0.0", port))
        if not args.source:
            identities = {platform: internet.package_identity(getattr(args, platform)) for platform in set(platforms)}
            launcher = exports.BetaValidation(args, temporary, {"binaries": identities, "processes": []})
            exports.DIAGNOSTIC_CLASSES["lan_discovery_peer.gd"] = "BetaLanDiscoveryCheck"
            if "windows" in platforms:
                launcher.initialize_wine()
        for slot, platform in enumerate(platforms, 1):
            role = "host" if slot == 1 else "guest" + str(slot)
            if args.source:
                cwd = project
                environment = stability.private_environment(temporary / role, args.godot)
                command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                           "--script", "tests/lan_discovery_peer.gd", "--", "--no-profile-save", "--no-upnp"]
            else:
                cwd, environment = launcher.environment(role)
            environment.update({"LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": exports.windows_path(prefix) if platform == "windows" else str(prefix),
                                "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_TEST_PORT": str(args.port),
                                "LASTSHIFT_TEST_DISCOVERY_PORT": str(args.discovery_port)})
            if args.source:
                log = output / (role + ".log")
                with log.open("x") as stream:
                    process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            else:
                launcher.output = output
                process, _, _ = launcher.start_game(role, platform, "lan_discovery_peer.gd", environment, cwd)
            processes.append(process)
            internet.await_marker(Path(str(prefix) + (".room.json" if slot == 1 else ".joined" + str(slot) + ".json")), process, 15)
            records.append({"role": role, "platform": platform,
                            "runtime": "Linux source/editor" if args.source else "Linux native export" if platform == "linux" else "Windows PE under Wine",
                            "identity": internet.read_json(Path(str(prefix) + ".identity" + str(slot) + ".json"))})
        deadline = time.monotonic() + 45
        while any(process.poll() is None for process in processes) and time.monotonic() < deadline:
            time.sleep(.05)
        for slot, process in enumerate(processes, 1):
            role = records[slot-1]["role"]
            records[slot-1].update(internet.inspect_peer(output / (role + ".log"), process.poll(), False))
            proof = internet.read_json(Path(str(prefix) + ".result" + str(slot) + ".json"))
            if not proof or proof.get("failures") != 0 or (not args.source and not records[slot-1]["identity"].get("exported_template")):
                raise RuntimeError("Missing successful actual LAN proof for " + role)
            records[slot-1]["evidence"] = proof
        report["package_identities"] = identities
        for platform, identity in identities.items():
            if internet.package_identity(getattr(args, platform)) != identity:
                raise RuntimeError("Package changed during LAN run")
        report["success"] = True
    except Exception as error:
        report["error"] = str(error)
    finally:
        leftovers = internet.retire(processes)
        # Preserve actual sender identities even when a later assertion fails.
        # The private working directory is removed after this function returns.
        evidence_directory = output / "stage-evidence"
        evidence_directory.mkdir()
        for marker in prefix.parent.glob(prefix.name + ".*.json"):
            shutil.copy2(marker, evidence_directory / marker.name)
        if launcher is not None and launcher.wineprefix.exists():
            try:
                launcher.shutdown_wine()
            except Exception as error:
                report["cleanup_error"] = str(error)
                report["success"] = False
        report["owned_process_group_leftovers"] = leftovers
        if leftovers:
            report["success"] = False
        (output / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    return report["success"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--linux", type=Path)
    parser.add_argument("--windows", type=Path)
    parser.add_argument("--platforms", default="linux,linux,linux,linux")
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--wine", default=shutil.which("wine") or "wine")
    parser.add_argument("--wineserver", default=shutil.which("wineserver") or "wineserver")
    parser.add_argument("--wine-extra-dll", type=Path, action="append", default=[])
    parser.add_argument("--wine-timeout", type=float, default=120)
    parser.add_argument("--port", type=int, default=24957)
    parser.add_argument("--discovery-port", type=int, default=24958)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    platforms = args.platforms.split(",")
    if len(platforms) != 4 or any(platform not in ("linux", "windows") for platform in platforms):
        parser.error("Exactly four linux/windows peers are required")
    if args.source and set(platforms) != {"linux"}:
        parser.error("Source diagnostics run only on this actual Linux host")
    if not args.source and any(not getattr(args, platform) or not getattr(args, platform).is_file() for platform in set(platforms)):
        parser.error("Provide the package executable for every selected platform")
    if not 1024 < args.port < 65536 or not 1024 < args.discovery_port < 65536 or args.port == args.discovery_port:
        parser.error("Use distinct UDP ports above 1024")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="bunkercrew-default-lan-") as directory:
        temporary = Path(directory)
        project = args.project.resolve()
        if args.source:
            original = stability.source_manifest(project)
            frozen = temporary / "project"
            stability.copy_snapshot(project, frozen, original)
            project = frozen
            environment = stability.private_environment(temporary / "import", args.godot)
            imported = stability.run_check([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                    "--editor", "--recovery-mode", "--import", "--quit"], project, environment, args.output / "import.log", 180)
            if not imported["success"]:
                raise SystemExit("Private LAN source import failed")
            (args.output / "source-inputs.json").write_text(json.dumps(stability.source_manifest(project), indent=2) + "\n")
        success = run(args, temporary, project, args.output)
    print(("PASS " if success else "FAIL ") + str(args.output / "report.json"))
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()
