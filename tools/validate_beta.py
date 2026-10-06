#!/usr/bin/env python3
"""Validate the shipped Linux/Windows binaries, including cross-platform ENet.

Run from any directory; no Godot editor or loose gameplay source files are used:

    python3 tools/validate_beta.py --include-perimeter

Windows runs under Wine in a disposable prefix. This is a compatibility test,
not validation on native Windows hardware. Every game runs headless with Dummy
audio, profile saving disabled, and UPnP disabled. The default fixture ports are
UDP 24877 (ENet) and 24878 (LAN discovery), separate from a normal game session.
Each executable is linked/copied unchanged into a private working directory.
A temporary override.cfg selects a diagnostic SceneTree class from its own pack;
the override is never written beside the distributed executable.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
ERROR_MARKERS = ("SCRIPT ERROR", "ERROR:", "WARNING:")
DIAGNOSTIC_CLASSES = {
    "story_export_test.gd": "BetaStoryExportCheck",
    "network_gameplay_peer.gd": "BetaNetworkGameplayCheck",
    "perimeter_network_peer.gd": "BetaPerimeterNetworkCheck",
    "live_music_export_test.gd": "BetaLiveMusicExportCheck",
    "medic_software_test.gd": "BetaMedicSoftwareCheck",
    "beta_asset_export_test.gd": "BetaAssetExportCheck",
}


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def project_version():
    project = ROOT / "project.godot"
    if not project.is_file():
        return None
    match = re.search(r'^config/version\s*=\s*"([^"\n]+)"', project.read_text(encoding="utf-8"), re.MULTILINE)
    return match[1] if match else None


def network_build():
    protocol = ROOT / "scripts/network_protocol.gd"
    match = re.search(r'^const BUILD\s*:=\s*"([^"\n]+)"', protocol.read_text(encoding="utf-8"), re.MULTILINE)
    if not match:
        raise ValueError("Missing network build in network_protocol.gd")
    return match[1]


def windows_path(path):
    """Wine's default Z: drive maps the Unix filesystem, including barriers."""
    return "Z:" + str(Path(path).resolve()).replace("/", "\\")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_log(path):
    return path.read_text(encoding="utf-8", errors="replace")


def stop_process(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=3)


class BetaValidation:
    def __init__(self, args, temporary, report):
        self.args = args
        self.temporary = temporary
        self.report = report
        self.output = args.output
        self.wineprefix = temporary / "wineprefix"
        self.base_env = dict(os.environ)
        for name in ("LASTSHIFT_NETWORK_CAPTURE", "LASTSHIFT_GAMEPLAY_ROLE", "LASTSHIFT_GAMEPLAY_PATH"):
            self.base_env.pop(name, None)
        self.base_env.update({
            "WINEPREFIX": str(self.wineprefix),
            "WINEARCH": "win64",
            "WINEDEBUG": "-all,err+module",
            "WINEDLLOVERRIDES": "mscoree,mshtml=",
            "LASTSHIFT_TEST_PORT": str(args.port),
            "LASTSHIFT_TEST_DISCOVERY_PORT": str(args.discovery_port),
        })
        self.executables = {"linux": args.linux, "windows": args.windows}

    def environment(self, name):
        isolated = self.temporary / name
        cwd = isolated / "cwd"
        cwd.mkdir(parents=True)
        env = dict(self.base_env)
        for variable, directory in (
            ("XDG_DATA_HOME", "data"),
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_CACHE_HOME", "cache"),
            ("XDG_STATE_HOME", "state"),
            ("XDG_RUNTIME_DIR", "runtime"),
        ):
            target = isolated / directory
            target.mkdir(mode=0o700)
            env[variable] = str(target)
        return cwd, env

    def game_command(self, platform, executable):
        launch = [str(executable)] if platform == "linux" else [self.args.wine, windows_path(executable)]
        return launch + [
            "--headless", "--audio-driver", "Dummy",
            "--", "--no-profile-save", "--no-upnp",
        ]

    def start_game(self, name, platform, script, env=None, cwd=None, user_args=()):
        if env is None:
            cwd, env = self.environment(name)
        source = self.executables[platform]
        executable = cwd / source.name
        method = "hardlink"
        try:
            os.link(source, executable)
        except OSError:
            shutil.copy2(source, executable)
            method = "copy"
        actual_hash = sha256(executable)
        if actual_hash != self.report["binaries"][platform]["sha256"]:
            raise RuntimeError(f"{platform} executable changed after validation began")
        for relative, expected in self.report["binaries"][platform]["native_libraries"].items():
            library = source.parent / relative
            destination = cwd / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(library, destination)
            if sha256(destination) != expected["sha256"]:
                raise RuntimeError(f"{platform} native library changed: {relative}")
        main_loop = DIAGNOSTIC_CLASSES[script]
        override = cwd / "override.cfg"
        override.write_text(f'[application]\nrun/main_loop_type="{main_loop}"\n'
                            'run/main_scene="res://tests/beta_empty.tscn"\n'
                            'run/disable_stdout=false\n', encoding="utf-8")
        peer = self.start(name, self.game_command(platform, executable) + list(user_args), env, cwd)
        peer[1].update({"platform": platform, "embedded_fixture": "res://tests/" + script,
                        "temporary_main_loop": main_loop, "temporary_override": str(override),
                        "temporary_main_scene": "res://tests/beta_empty.tscn",
                        "executable_preparation": method, "executable_sha256": actual_hash,
                        "executable_matches_package": True})
        return peer

    def start(self, name, command, env=None, cwd=None):
        if env is None:
            cwd, env = self.environment(name)
        log = self.output / (name + ".log")
        entry = {
            "name": name, "command": command, "cwd": str(cwd), "log": str(log),
            "started_at": utc_now(), "success": False,
        }
        self.report["processes"].append(entry)
        started = time.monotonic()
        with log.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
        return process, entry, started

    @staticmethod
    def record_exit(process, entry, started):
        entry["elapsed_seconds"] = round(time.monotonic() - started, 3)
        entry["returncode"] = process.poll()

    def preserve_engine_logs(self, entry):
        candidates = list((Path(entry["cwd"]).parent / "data").rglob("godot.log"))
        if entry.get("platform") == "windows":
            candidates.extend(self.wineprefix.glob("drive_c/users/*/AppData/Roaming/Godot/app_userdata/*/logs/godot.log"))
        entry["engine_log_locations"] = []
        for index, source in enumerate(candidates):
            destination = self.output / f"{entry['name']}-godot-{index}.log"
            shutil.copyfile(source, destination)
            entry["engine_log_locations"].append({"original_path": str(source), "saved_copy": str(destination)})

    def single(self, name, command, timeout):
        process, entry, started = self.start(name, command)
        return self.wait_single(process, entry, started, timeout)

    def wait_single(self, process, entry, started, timeout):
        try:
            deadline = time.monotonic() + timeout
            while process.poll() is None and time.monotonic() < deadline:
                if "wine: Unhandled page fault" in read_log(Path(entry["log"])):
                    entry["fatal_runtime_error"] = "Wine reported an unhandled page fault before completion"
                    break
                time.sleep(0.05)
            entry["timed_out"] = process.poll() is None and time.monotonic() >= deadline
        finally:
            stop_process(process)
            self.record_exit(process, entry, started)
        entry["success"] = (process.returncode == 0 and not entry.get("timed_out", False)
                            and not entry.get("fatal_runtime_error"))
        return entry

    def initialize_wine(self):
        entry = self.single("wine-version", [self.args.wine, "--version"], 10)
        if not entry["success"]:
            raise RuntimeError("Wine version check failed; see " + entry["log"])
        self.report["wine_version"] = read_log(Path(entry["log"])).strip()
        entry = self.single("wine-init", [self.args.wine, "wineboot", "--init"], self.args.wine_timeout)
        if not entry["success"]:
            raise RuntimeError("Disposable Wine prefix initialization failed; see " + entry["log"])
        # Require the documented mapping before sharing filesystem barriers.
        z_drive = self.wineprefix / "dosdevices/z:"
        if not z_drive.is_symlink() or z_drive.resolve() != Path("/"):
            raise RuntimeError("The isolated Wine prefix does not map Z: to the Unix filesystem")
        self.report["wine_runtime_files"] = []
        for source in self.args.wine_extra_dll:
            destination = self.wineprefix / "drive_c/windows/system32" / source.name
            if destination.exists() or destination.is_symlink():
                raise RuntimeError(f"Refusing to replace an existing Wine runtime file: {destination}")
            shutil.copy2(source, destination)
            self.report["wine_runtime_files"].append({"source": str(source), "prefix_copy": str(destination),
                                                       "sha256": sha256(source)})

    @staticmethod
    def inspect_game(entry):
        output = read_log(Path(entry["log"]))
        entry["engine_errors"] = [line for line in output.splitlines()
                                  if any(marker in line for marker in ERROR_MARKERS)]
        engine = re.search(r"^Godot Engine .+$", output, re.MULTILINE)
        entry["engine"] = engine.group(0).strip() if engine else None
        entry["success"] = entry["success"] and not entry["engine_errors"]
        return output

    def smoke(self, platform):
        name = "smoke-" + platform
        print("Running " + name, flush=True)
        process, entry, started = self.start_game(name, platform, "story_export_test.gd")
        entry = self.wait_single(process, entry, started, self.args.smoke_timeout)
        self.preserve_engine_logs(entry)
        output = self.inspect_game(entry)
        match = re.search(r"STORY EXPORT: (\d+)/(\d+) checks passed", output)
        entry["assertions"] = {"passed": int(match[1]), "total": int(match[2])} if match else None
        expected = self.args.expected_smoke_checks
        entry["success"] = entry["success"] and match is not None and int(match[1]) == int(match[2]) == expected
        self.report["checks"].append({"name": name, "success": entry["success"]})
        if not entry["success"]:
            raise RuntimeError(f"{name} failed (expected {expected}/{expected} checks); see {entry['log']}")
        print(f"PASS {name}: {expected}/{expected} assertions", flush=True)

    def live_music(self, platform):
        name = "live-music-" + platform
        print("Running " + name, flush=True)
        process, entry, started = self.start_game(name, platform, "live_music_export_test.gd")
        entry = self.wait_single(process, entry, started, self.args.smoke_timeout)
        self.preserve_engine_logs(entry)
        output = self.inspect_game(entry)
        match = re.search(r"BETA LIVE MUSIC PASSED: (\d+)/(\d+) checks passed", output)
        entry["assertions"] = {"passed": int(match[1]), "total": int(match[2])} if match else None
        entry["success"] = entry["success"] and match is not None and int(match[1]) == int(match[2]) and int(match[2]) >= 87
        self.report["checks"].append({"name": name, "success": entry["success"]})
        if not entry["success"]:
            raise RuntimeError(f"{name} failed; see {entry['log']}")
        print(f"PASS {name}: native mixer and 13 exported themes", flush=True)

    def medic_software(self, platform):
        name = "medic-software-" + platform
        print("Running " + name, flush=True)
        process, entry, started = self.start_game(name, platform, "medic_software_test.gd")
        entry = self.wait_single(process, entry, started, self.args.smoke_timeout)
        self.preserve_engine_logs(entry)
        output = self.inspect_game(entry)
        match = re.search(r"SAN SOFTWARE: (\d+)/(\d+) passed", output)
        entry["assertions"] = {"passed": int(match[1]), "total": int(match[2])} if match else None
        entry["success"] = entry["success"] and match is not None and int(match[1]) == int(match[2]) == 47
        self.report["checks"].append({"name": name, "success": entry["success"]})
        if not entry["success"]:
            raise RuntimeError(f"{name} failed (expected 47/47 checks); see {entry['log']}")
        print(f"PASS {name}: 47/47 SAN-1 software assertions", flush=True)

    def assets(self, platform):
        name = "assets-" + platform
        print("Running " + name, flush=True)
        asset_report = self.output / (name + ".json")
        target = windows_path(asset_report) if platform == "windows" else str(asset_report)
        process, entry, started = self.start_game(
            name, platform, "beta_asset_export_test.gd",
            user_args=("--expect-packed", "--asset-report=" + target))
        entry = self.wait_single(process, entry, started, self.args.smoke_timeout)
        self.preserve_engine_logs(entry)
        output = self.inspect_game(entry)
        match = re.search(r"BETA ASSETS PASSED: (\d+)/(\d+) checks passed", output)
        payload = json.loads(asset_report.read_text()) if asset_report.is_file() else {}
        entry["assertions"] = {"passed": int(match[1]), "total": int(match[2])} if match else None
        entry["asset_report"] = str(asset_report)
        entry["success"] = (entry["success"] and match is not None and
                            int(match[1]) == int(match[2]) >= 628 and payload.get("success") is True and
                            payload.get("checks") == int(match[2]) and payload.get("voices") == {"de": 85, "en": 85})
        self.report["checks"].append({"name": name, "success": entry["success"]})
        if not entry["success"]:
            raise RuntimeError(f"{name} failed; see {entry['log']}")
        print(f"PASS {name}: runtime resources, raw metadata and real archive exclusions", flush=True)

    def network(self, fixture, host_platform, guest_platform):
        name = f"{fixture}-{host_platform}-host-{guest_platform}-guest"
        print("Running " + name, flush=True)
        prefix = self.temporary / name / "barriers/run"
        prefix.parent.mkdir(parents=True)
        room = Path(str(prefix) + ".room.json")
        peers = {}
        started = time.monotonic()
        check = {"name": name, "success": False, "transport": "UDP/ENet", "port": self.args.port,
                 "discovery_port": self.args.discovery_port, "join_method": "16-character LAN discovery code followed by ENet",
                            "host": host_platform, "guest": guest_platform}
        self.report["checks"].append(check)
        try:
            # Fail without disturbing an existing host on either requested fixture port.
            for port in (self.args.port, self.args.discovery_port):
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                    try:
                        probe.bind(("0.0.0.0", port))
                    except OSError as error:
                        raise RuntimeError(f"Fixture UDP port {port} is unavailable: {error}") from error
            for role, platform in (("host", host_platform), ("guest", guest_platform)):
                peer_name = name + "-" + role
                cwd, env = self.environment(peer_name)
                env["LASTSHIFT_GAMEPLAY_ROLE"] = role
                env["LASTSHIFT_GAMEPLAY_PATH"] = windows_path(prefix) if platform == "windows" else str(prefix)
                peers[role] = self.start_game(peer_name, platform, fixture + "_peer.gd", env, cwd)
                process, entry, _ = peers[role]
                entry.update({"platform": platform, "role": role,
                              "coordination_prefix": env["LASTSHIFT_GAMEPLAY_PATH"]})
                if role == "host":
                    deadline = time.monotonic() + self.args.room_timeout
                    while not room.is_file() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.05)
                    if not room.is_file():
                        raise RuntimeError(f"{name}: host did not publish its ENet room; see {entry['log']}")
                    code = json.loads(room.read_text(encoding="utf-8")).get("code", "")
                    symbols = re.sub(r"[-\s]", "", code) if isinstance(code, str) else ""
                    check["join_code_length"] = len(symbols)
                    check["displayed_code_length"] = len(code) if isinstance(code, str) else None
                    if len(symbols) != 16:
                        raise RuntimeError(f"{name}: host must publish a 16-symbol LAN code for the discovery join test")
            deadline = time.monotonic() + self.args.network_timeout
            while any(peer[0].poll() is None for peer in peers.values()) and time.monotonic() < deadline:
                # A failed peer cannot recover. Stop its partner instead of waiting out barriers.
                if any(peer[0].poll() not in (None, 0) for peer in peers.values()):
                    break
                time.sleep(0.05)
            for role, (process, entry, _) in peers.items():
                entry["timed_out"] = process.poll() is None and time.monotonic() >= deadline
                entry["success"] = process.poll() == 0
                output = self.inspect_game(entry)
                match = re.search(rf"NETWORK_GAMEPLAY_PASS {role} checks=(\d+) failures=(\d+)", output)
                entry["assertions"] = {"total": int(match[1]), "failed": int(match[2])} if match else None
                entry["success"] = entry["success"] and match is not None and int(match[1]) > 0 and int(match[2]) == 0
            check["success"] = len(peers) == 2 and all(peer[1]["success"] for peer in peers.values())
            if not check["success"]:
                raise RuntimeError(f"{name} failed; inspect its host and guest logs in {self.output}")
            print("PASS " + name, flush=True)
        finally:
            for process, entry, peer_started in peers.values():
                stop_process(process)
                self.record_exit(process, entry, peer_started)
                self.preserve_engine_logs(entry)
            check["elapsed_seconds"] = round(time.monotonic() - started, 3)
            check["completed_barriers"] = sorted(path.name for path in prefix.parent.glob("*.json"))

    def shutdown_wine(self):
        # WINEPREFIX always targets our temporary directory; never the user's prefix.
        entry = self.single("wine-stop", [self.args.wineserver, "-k"], 10)
        # Wine can exit its server naturally between fixtures; -k then returns 1.
        already_stopped = entry["returncode"] == 1 and not read_log(Path(entry["log"])).strip()
        entry["server_already_stopped"] = already_stopped
        entry["success"] = entry["success"] or already_stopped
        stop_succeeded = entry["success"]
        entry = self.single("wine-wait", [self.args.wineserver, "-w"], 10)
        self.report["wine_cleanup_success"] = stop_succeeded and entry["success"]
        if not self.report["wine_cleanup_success"]:
            raise RuntimeError("Disposable Wine server did not finish stopping; see " + entry["log"])


def arguments():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", default=project_version(), help="Beta release directory/version (defaults to project.godot)")
    parser.add_argument("--linux", type=Path, help="Linux executable (defaults to beta/VERSION/ubuntu-x86_64/Bunkercrew.x86_64)")
    parser.add_argument("--windows", type=Path, help="Windows executable (defaults to beta/VERSION/windows-x86_64/Bunkercrew.exe)")
    parser.add_argument("--output", type=Path, help="Report directory (defaults to artifacts/beta-VERSION)")
    parser.add_argument("--wine", default=shutil.which("wine"))
    parser.add_argument("--wineserver", default=shutil.which("wineserver"))
    parser.add_argument("--wine-extra-dll", type=Path, action="append", default=[],
                        help="Copy a required existing Wine/Proton runtime DLL into the disposable system32 (repeatable)")
    parser.add_argument("--include-perimeter", action="store_true", help="Also test sentries, KO/revival and reconnect in both host directions")
    parser.add_argument("--include-assets", action="store_true", help="Check current runtime assets and archive exclusions inside each actual export")
    parser.add_argument("--smoke-only", action="store_true", help="Validate both packages without opening an ENet room")
    parser.add_argument("--expected-smoke-checks", type=int, default=402)
    parser.add_argument("--wine-timeout", type=float, default=120)
    parser.add_argument("--smoke-timeout", type=float, default=90)
    parser.add_argument("--room-timeout", type=float, default=20)
    parser.add_argument("--network-timeout", type=float, default=60)
    parser.add_argument("--port", type=int, default=24877, help="Fixture ENet port, passed through LASTSHIFT_TEST_PORT")
    parser.add_argument("--discovery-port", type=int, default=24878,
                        help="Fixture LAN discovery port, passed through LASTSHIFT_TEST_DISCOVERY_PORT")
    args = parser.parse_args()
    if not args.version:
        parser.error("--version is required when project.godot has no config/version")
    args.output = args.output or ROOT / "artifacts" / f"beta-{args.version}"
    bundle = ROOT / "beta" / args.version
    args.linux = args.linux or bundle / "ubuntu-x86_64/Bunkercrew.x86_64"
    args.windows = args.windows or bundle / "windows-x86_64/Bunkercrew.exe"
    for port in (args.port, args.discovery_port):
        if not 1024 <= port <= 65535:
            parser.error("--port and --discovery-port must be in 1024..65535")
    if args.port == args.discovery_port:
        parser.error("--port and --discovery-port must be different")
    for name in ("wine_timeout", "smoke_timeout", "room_timeout", "network_timeout", "expected_smoke_checks"):
        if getattr(args, name) <= 0:
            parser.error("--" + name.replace("_", "-") + " must be positive")
    for name in ("linux", "windows", "output"):
        setattr(args, name, getattr(args, name).expanduser().resolve())
    args.wine_extra_dll = [path.expanduser().resolve() for path in args.wine_extra_dll]
    for path in args.wine_extra_dll:
        if not path.is_file() or path.suffix.lower() != ".dll":
            parser.error("--wine-extra-dll must refer to an existing .dll file: " + str(path))
    return args


def main():
    args = arguments()
    started = time.monotonic()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {
        "schema_version": 1, "started_at": utc_now(), "success": False,
        "invocation": [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
        "expected_release": args.version, "expected_network_build": network_build(),
        "fixture_ports": {"enet": args.port, "lan_discovery": args.discovery_port},
        "runtime": {"linux": "native Linux executable", "windows": "Windows PE executable under Wine"},
        "isolation": {"working_directories": "private directories containing the package executable, its native libraries and override.cfg",
                      "temporary_main_loop_overrides": True, "temporary_xdg_directories": True,
                      "disposable_wineprefix": True, "source_project_path_supplied": False,
                      "headless": True, "audio_driver": "Dummy", "profile_saving": False, "upnp": False},
        "limits": [
            "Wine compatibility coverage does not replace a native Windows 10/11 test.",
            "Headless Dummy runs do not validate rendering, physical audio, microphone or input devices.",
            "ENet peers share one Linux machine; separate-machine LAN, WAN, NAT, router mapping and relay paths are not tested.",
            "LAN discovery uses the fixture loopback target; real router broadcast forwarding and firewall policies are not tested.",
            "Handshake success checks agreement between exports; fixtures do not print the actual network build string.",
            "These bounded prepared scenarios do not cover a long multiplayer session or every gameplay combination.",
        ],
        "checks": [], "processes": [], "binaries": {},
    }
    if args.smoke_only:
        report["limits"].append("Smoke-only mode: no ENet gameplay checks were requested.")
    elif not args.include_perimeter:
        report["limits"].append("The optional perimeter fixture was not requested.")
    try:
        if not args.wine or not args.wineserver:
            raise RuntimeError("wine and wineserver must be available; install Wine or supply both executable paths")
        for platform, path in (("linux", args.linux), ("windows", args.windows)):
            if not path.is_file():
                raise RuntimeError(f"Missing {platform} export: {path}")
            if platform == "linux" and not os.access(path, os.X_OK):
                raise RuntimeError(f"Linux export is not executable: {path}")
            report["binaries"][platform] = {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            suffix = ".so" if platform == "linux" else ".dll"
            libraries = [library for library in path.parent.rglob("*" + suffix)
                         if "bunkercrew_audio" in library.name]
            if len(libraries) != 1:
                raise RuntimeError(f"Expected one shipped {platform} live-music library, found {len(libraries)}")
            report["binaries"][platform]["native_libraries"] = {
                str(library.relative_to(path.parent)): {"bytes": library.stat().st_size, "sha256": sha256(library)}
                for library in libraries}
        with tempfile.TemporaryDirectory(prefix="lastshift-beta-validation-") as temporary:
            validation = BetaValidation(args, Path(temporary), report)
            try:
                validation.smoke("linux")
                validation.live_music("linux")
                validation.medic_software("linux")
                if args.include_assets:
                    validation.assets("linux")
                validation.initialize_wine()
                validation.smoke("windows")
                validation.live_music("windows")
                validation.medic_software("windows")
                if args.include_assets:
                    validation.assets("windows")
                # Never run networking until both embedded packages passed the smoke test.
                if not args.smoke_only:
                    fixtures = ["network_gameplay"]
                    if args.include_perimeter:
                        fixtures.append("perimeter_network")
                    for fixture in fixtures:
                        for host, guest in (("linux", "windows"), ("windows", "linux")):
                            validation.network(fixture, host, guest)
            finally:
                if validation.wineprefix.exists():
                    primary_error = sys.exc_info()[1]
                    try:
                        validation.shutdown_wine()
                    except Exception as error:
                        report["cleanup_error"] = f"{type(error).__name__}: {error}"
                        if primary_error is None:
                            raise
        report["success"] = True
    except (Exception, KeyboardInterrupt) as error:
        report["error"] = f"{type(error).__name__}: {error}"
        print(report["error"], file=sys.stderr, flush=True)
    finally:
        report["finished_at"] = utc_now()
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        destination = args.output / "validation-report.json"
        destination.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"{'PASS' if report['success'] else 'FAIL'}: {destination}", flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
