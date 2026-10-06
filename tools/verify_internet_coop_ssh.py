#!/usr/bin/env python3
"""Four exported peers across this computer and an authorized public Linux server.

SSH transfers the unchanged package, fixture stage markers and logs only.
Authoritative gameplay, input and voice use the configured public TLS relay.
Windows PE under Wine remains compatibility coverage, not native Windows.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

import internet_coop_ssh_peer as remote
import validate_beta as exports
import verify_internet_coop as internet

ROOT = Path(__file__).resolve().parents[1]


def ssh_command(target, command):
    return ["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", target, command]


def run_ssh(target, command, timeout=30):
    result = subprocess.run(ssh_command(target, command), capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError("Owned SSH operation failed: " + result.stderr[-2000:])
    return result.stdout


def prepare_remote(args, output):
    # Reject an invalid local candidate before allocating any server resource.
    manifest = internet.package_identity(args.linux)
    code = 'import tempfile,os,json; p=tempfile.mkdtemp(prefix="bunkercrew-wan-",dir="/tmp"); os.chmod(p,0o700); os.mkdir(p+"/package",0o700); print(json.dumps({"directory":p}))'
    directory = json.loads(run_ssh(args.ssh, "python3 -c " + shlex.quote(code)))["directory"]
    if not directory.startswith("/tmp/bunkercrew-wan-") or "/" in directory.removeprefix("/tmp/bunkercrew-wan-"):
        raise RuntimeError("Server did not return an owned private temporary directory")
    files = [(args.linux, "package/Bunkercrew.x86_64"), (ROOT / "tools/internet_coop_ssh_peer.py", "peer.py"),
             (ROOT / "tools/internet_coop_ssh_cleanup.py", "cleanup.py")]
    files.extend((args.linux.parent / relative, "package/"+relative) for relative in manifest["native_libraries"])
    try:
        for source, relative in files:
            destination = directory + "/" + relative
            parent = str(Path(destination).parent)
            run_ssh(args.ssh, "mkdir -p -- " + shlex.quote(parent))
            result = subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                                     str(source.resolve()), args.ssh + ":" + shlex.quote(destination)], capture_output=True, text=True, timeout=600)
            if result.returncode:
                raise RuntimeError("Owned package upload failed: " + result.stderr[-2000:])
        run_ssh(args.ssh, "chmod 700 -- " + shlex.quote(directory + "/package/Bunkercrew.x86_64"))
        (output / "remote-preparation.json").write_text(json.dumps({"ssh_target": args.ssh, "directory": directory,
                    "local_package": manifest, "transferred_files": [{"relative": relative, "sha256": internet.stability.digest(source)} for source, relative in files]}, indent=2)+"\n")
        return directory, manifest
    except Exception:
        cleanup_remote(args.ssh, directory)
        raise


def cleanup_remote(target, directory):
    code = 'import os,pathlib,shutil,sys; p=pathlib.Path(sys.argv[1]); assert p.parent==pathlib.Path("/tmp") and p.name.startswith("bunkercrew-wan-") and not p.is_symlink() and p.stat().st_uid==os.getuid() and not p.stat().st_mode&0o077; shutil.rmtree(p); print("owned directory removed")'
    return run_ssh(target, "python3 -c " + shlex.quote(code) + " " + shlex.quote(directory))


def confirm_remote_retired(args,directory,started):
    if not started: raise RuntimeError("Missing remote PID/start identity; cannot certify cleanup")
    configuration={**started,"directory":directory}
    result=subprocess.run(ssh_command(args.ssh,"python3 "+shlex.quote(directory+"/cleanup.py")),input=json.dumps(configuration),capture_output=True,text=True,timeout=15)
    observed=json.loads(result.stdout)
    if result.returncode or not observed.get("retired"):
        raise RuntimeError("Remote owned process group has not retired: "+json.dumps(observed))
    return observed


class Bridge:
    def __init__(self, args, directory, case, prefix, output, package):
        self.prefix = prefix
        self.output = output
        self.sent = {}
        self.pending = b""
        self.exited = None
        self.crashed = None
        self.started = None
        self.error = None
        self.write_closed = False
        self.events = output / "ssh-events.jsonl"
        self.events.touch()
        self.log = output / ("host.log" if args.remote_slot == 1 else "guest4.log")
        self.log.touch()
        self.process = None
        self.selector = None
        try:
            command = ssh_command(args.ssh, "python3 -u " + shlex.quote(directory+"/peer.py") + " " + shlex.quote(directory))
            with (output / "ssh-stderr.log").open("x") as stderr:
                self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, start_new_session=True)
            self.selector = selectors.DefaultSelector()
            self.selector.register(self.process.stdout.fileno(), selectors.EVENT_READ)
            self.send({"slot": args.remote_slot, "case": case, "relay": args.relay,
                       "binary_sha256": package["sha256"], "libraries": {p: record["sha256"] for p, record in package["native_libraries"].items()}})
        except BaseException:
            # The caller cannot assign/retire a constructor that has failed.
            self.stop()
            raise

    def send(self, value):
        line = json.dumps(value, separators=(",", ":")).encode()+b"\n"
        if len(line) > remote.MAX_MESSAGE: raise RuntimeError("SSH coordination message exceeds its bound")
        try:
            self.process.stdin.write(line)
            self.process.stdin.flush()
        except BrokenPipeError:
            self.write_closed = True

    def pump(self):
        for path in (() if self.write_closed or self.exited is not None else self.prefix.parent.glob(self.prefix.name+".*.json")):
            name = "run"+path.name.removeprefix(self.prefix.name)
            remote.stage_path(Path("."), name)
            data = remote.stage_data(path.read_text())
            checksum = hashlib.sha256(data.encode()).hexdigest()
            if self.sent.get(name) != checksum:
                self.send({"op": "stage", "name": name, "data": data})
                self.sent[name] = checksum
        for _, _ in self.selector.select(.03):
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                self.selector.unregister(self.process.stdout.fileno())
                break
            self.pending += data
            if len(self.pending) > remote.MAX_MESSAGE: raise RuntimeError("SSH reply exceeds its bound")
            while b"\n" in self.pending:
                line, self.pending = self.pending.split(b"\n", 1)
                message = json.loads(line)
                with self.events.open("a") as stream: stream.write(line.decode()+"\n")
                operation = message.get("op")
                if operation == "stage":
                    path = remote.stage_path(self.prefix.parent, message.get("name"))
                    data = remote.stage_data(message.get("data"))
                    temporary = path.with_suffix(".tmp")
                    temporary.write_text(data)
                    os.replace(temporary, path)
                    self.sent[path.name] = hashlib.sha256(data.encode()).hexdigest()
                elif operation == "log":
                    if not isinstance(message.get("data"), str): raise RuntimeError("Invalid remote log fragment")
                    with self.log.open("a") as stream: stream.write(message["data"])
                elif operation == "started": self.started = message
                elif operation == "exit": self.exited = message
                elif operation == "crashed": self.crashed = message
                elif operation == "error": self.error = message.get("error")
                else: raise RuntimeError("Unknown SSH fixture message")
        if self.error: raise RuntimeError("Remote fixture: " + str(self.error))

    def stop(self):
        if self.process is None: return
        if self.process.poll() is None:
            try: self.send({"op": "stop"})
            except (BrokenPipeError, OSError): pass
        if self.process.stdin and not self.process.stdin.closed:
            try: self.process.stdin.close()
            except (BrokenPipeError,OSError): pass
        try: self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            try: os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try: os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                self.process.wait(timeout=5)
        if self.selector is not None: self.selector.close()
        stdout=getattr(self.process,"stdout",None)
        if stdout is not None and not stdout.closed: stdout.close()


def run_case(args, case, folder, output, directory, remote_package):
    output.mkdir()
    prefix = folder / "run"
    platforms = args.platforms.split(",")
    packages = {platform: internet.package_identity(getattr(args, platform)) for platform in set(platforms)}
    manifest = {"binaries": packages, "processes": []}
    launcher = exports.BetaValidation(args, folder, manifest)
    launcher.output = output
    fixture, main_loop = internet.FIXTURES[case]
    exports.DIAGNOSTIC_CLASSES[fixture] = main_loop
    bridge = None
    remote_attempted = False
    processes = []
    records = []
    report = {"case": case, "success": False, "peers": records, "remote_slot": args.remote_slot,
              "transport": "Public verified TLS WebSocket relay for all game/input/voice packets",
              "relay_url": args.relay, "actual_client_machines": 2,
              "network_connections": "Local Linux computer via its router/VPN and the public Linux server network; no second residential client is asserted.",
              "native_windows_verified": False, "package_identities": packages}
    report["prepared_state"] = internet.PREPARED_STATES[case]
    started = time.monotonic()
    requested_crash = False
    try:
        if "windows" in platforms: launcher.initialize_wine()
        for slot, platform in enumerate(platforms, 1):
            role = "host" if slot == 1 else "guest"+str(slot)
            if slot == args.remote_slot:
                remote_attempted = True
                bridge = Bridge(args, directory, case, prefix, output, remote_package)
                record = {"role": role, "platform": "linux", "runtime": "Native Linux export on separate public Linux server", "log": role+".log"}
            else:
                cwd, environment = launcher.environment(role)
                environment.update({"LASTSHIFT_GAMEPLAY_ROLE": role, "LASTSHIFT_GAMEPLAY_PATH": exports.windows_path(prefix) if platform == "windows" else str(prefix),
                     "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_PARTY_RELAY": args.relay,
                     "BUNKERCREW_HOST_DEPARTURE": case, "BUNKERCREW_EXPORTED_PEER": "1"})
                process, entry, _ = launcher.start_game(role, platform, fixture, environment, cwd)
                processes.append((slot, process))
                record = {"role": role, "platform": platform, "runtime": "Linux native export" if platform == "linux" else "Windows PE under Wine", "pid": process.pid, "command": entry["command"], "log": role+".log"}
            records.append(record)
            marker = Path(str(prefix)+(".room.json" if slot == 1 else ".joined"+str(slot)+".json"))
            deadline = time.monotonic()+25
            while not marker.exists() and time.monotonic() < deadline:
                if bridge is not None: bridge.pump()
                if slot != args.remote_slot and process.poll() is not None: break
                time.sleep(.03)
            if not marker.exists(): raise RuntimeError("Peer did not publish "+marker.name)
            record["identity"] = internet.read_json(Path(str(prefix)+".identity"+str(slot)+".json"))
        deadline = time.monotonic()+130
        while time.monotonic() < deadline:
            bridge.pump()
            if case == "crash" and not requested_crash and Path(str(prefix)+".host_departure_ready.json").is_file():
                bridge.send({"op":"crash_owned_host"})
                requested_crash = True
            if bridge.exited is not None and all(process.poll() is not None for _, process in processes): break
            time.sleep(.03)
        if bridge.exited is None or any(process.poll() is None for _, process in processes): raise RuntimeError("Two-machine scenario exceeded its real deadline")
        for slot, process in processes:
            record = records[slot-1]
            record.update(internet.inspect_peer(output / record["log"], process.returncode, False, record["role"]))
        record = records[args.remote_slot-1]
        record.update(internet.inspect_peer(output / record["log"], bridge.exited["returncode"], case=="crash" and requested_crash, record["role"]))
        record["remote_start"] = bridge.started
        if case == "crash":
            if not bridge.crashed or bridge.crashed.get("pid")!=bridge.started.get("pid") or bridge.crashed.get("signal")!=int(signal.SIGKILL) or bridge.crashed.get("returncode")!=-signal.SIGKILL:
                raise RuntimeError("Missing proof that the helper killed its own recorded remote host")
            report["remote_host_crash"] = bridge.crashed
        if bridge.exited.get("binary_sha256") != remote_package["sha256"] or bridge.exited.get("libraries")!={p:record["sha256"] for p,record in remote_package["native_libraries"].items()}: raise RuntimeError("Remote package changed during the actual game")
        internet.validate_peer_identities(records, False, packages)
        report["seconds"] = round(time.monotonic()-started,3)
        report["evidence"] = internet.read_json(Path(str(prefix)+".final.json"))
        report["host_departure_observations"] = {str(slot): internet.read_json(Path(str(prefix)+".host_closed"+str(slot)+".json")) for slot in (2,3)}
        report["success"] = True
    except Exception as error:
        report["error"] = str(error)
    finally:
        report["remote_process_created"]=remote_attempted
        if remote_attempted and bridge is None:
            # A failed constructor can retire its local SSH group, but cannot
            # certify an unobserved remote PID. Preserve the private directory.
            report["remote_cleanup_error"]="SSH initialization failed before remote PID identity was observed"
        if bridge is not None:
            try: bridge.stop()
            except Exception as error: report["cleanup_error"] = str(error); report["success"] = False
            try: report["remote_process_cleanup"]=confirm_remote_retired(args,directory,bridge.started)
            except Exception as error: report["remote_cleanup_error"]=str(error);report["success"]=False
        report["owned_process_group_leftovers"] = internet.retire([process for _, process in processes])
        if report["owned_process_group_leftovers"]: report["success"] = False
        if launcher.wineprefix.exists():
            try: launcher.shutdown_wine()
            except Exception as error: report["cleanup_error"] = str(error); report["success"] = False
        (output / "result.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh", default="85.93.8.135", help="Previously authorized SSH config target")
    parser.add_argument("--linux", type=Path, required=True)
    parser.add_argument("--windows", type=Path)
    parser.add_argument("--platforms", default="linux,linux,linux,linux")
    parser.add_argument("--remote-slot", type=int, choices=(1,4), required=True)
    parser.add_argument("--swap-host", action="store_true",
                        help="Also test the opposite native Linux host position with the same remote package")
    parser.add_argument("--case", choices=("leave", "journey", "tire", "crash", "all"), default="all")
    parser.add_argument("--relay", default="wss://bunkercrew.vibechain.rocks/ws")
    parser.add_argument("--wine", default=shutil.which("wine") or "wine")
    parser.add_argument("--wineserver", default=shutil.which("wineserver") or "wineserver")
    parser.add_argument("--wine-extra-dll", type=Path, action="append", default=[])
    parser.add_argument("--wine-timeout", type=float, default=120)
    parser.add_argument("--between-cases-seconds", type=float, default=45,
                        help="Admission cooldown between rooms, preserving public server limits")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    platforms = args.platforms.split(",")
    if len(platforms)!=4 or any(platform not in ("linux","windows") for platform in platforms) or platforms[args.remote_slot-1]!="linux": parser.error("Four declared platforms and a native Linux remote slot are required")
    if args.swap_host and (platforms[0]!="linux" or platforms[3]!="linux"):
        parser.error("Native Linux host swapping requires Linux slots 1 and 4")
    if args.case=="crash" and args.remote_slot!=1:
        parser.error("Hard remote host loss requires --remote-slot 1")
    if args.ssh.startswith("-") or not args.ssh or args.relay!="wss://bunkercrew.vibechain.rocks/ws": parser.error("Use the authorized SSH target and configured public TLS relay")
    if any(not getattr(args,platform) or not getattr(args,platform).is_file() for platform in set(platforms)): parser.error("Every declared platform needs its exported executable")
    if not math.isfinite(args.between_cases_seconds) or not 0 <= args.between_cases_seconds <= 300:
        parser.error("Use a finite admission cooldown between 0 and 300 seconds")
    args.port, args.discovery_port = 24937,24938
    args.output = args.output.resolve()
    args.output.mkdir(parents=True,exist_ok=False)
    report = {"success":False,"full_internet_acceptance":False,"runs":[],"native_windows_verified":False,"actual_client_machines":2,
              "between_cases_seconds":args.between_cases_seconds,"admission_cooldowns":[]}
    directory = None
    try:
        directory, package = prepare_remote(args,args.output)
        with tempfile.TemporaryDirectory(prefix="bunkercrew-two-wan-") as temporary:
            positions=(args.remote_slot,5-args.remote_slot) if args.swap_host else (args.remote_slot,)
            for position in positions:
                args.remote_slot=position
                cases=("leave","journey","tire","crash") if args.case=="all" else (args.case,)
                for case in cases:
                    if case=="crash" and position!=1: continue
                    name="remote"+str(position)+"-"+case if args.swap_host else case
                    if report["runs"]:
                        print("Public relay admission cooldown: "+str(args.between_cases_seconds)+"s",flush=True)
                        report["admission_cooldowns"].append({"before_case":case,"before_remote_slot":position,"seconds":round(internet.admission_cooldown(args.between_cases_seconds),3)})
                    folder=Path(temporary)/name
                    folder.mkdir()
                    result=run_case(args,case,folder,args.output/name,directory,package)
                    report["runs"].append(result)
                    if not result["success"]: raise RuntimeError(result.get("error",result.get("cleanup_error","Two-machine test failed")))
                    print("PASS actual two-machine public TLS "+name,flush=True)
        report["success"]=True
    except Exception as error:
        report["error"]=str(error)
    finally:
        if directory is not None:
            safe=all(not result.get("remote_process_created") or (result.get("remote_process_cleanup",{}).get("retired") and not result.get("cleanup_error")) for result in report["runs"])
            try:
                if not safe:raise RuntimeError("Owned remote directory preserved because peer retirement is not certified: "+directory)
                report["remote_cleanup"]=cleanup_remote(args.ssh,directory)
            except Exception as error: report["cleanup_error"]=str(error);report["success"]=False
        (args.output/"report.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n")
    print(("PASS " if report["success"] else "FAIL ")+str(args.output/"report.json"))
    raise SystemExit(0 if report["success"] else 1)


if __name__=="__main__": main()
