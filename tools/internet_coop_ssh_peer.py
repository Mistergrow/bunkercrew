#!/usr/bin/env python3
"""Owned remote Linux export peer; JSON lines carry fixture barriers and logs.

Game traffic never uses stdin/stdout. It uses the public verified TLS relay.
The helper runs only within a caller-created private /tmp directory.
"""

import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time

CLASSES = {"leave": "BetaInternetLifecycleCheck", "journey": "BetaInternetJourneyCheck",
           "tire": "BetaInternetCoopCheck", "crash": "BetaInternetLifecycleCheck"}
MAX_MESSAGE = 262144
MAX_STAGE = 65536


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def stage_path(directory, name):
    if not isinstance(name, str) or not re.fullmatch(r"run\.[A-Za-z0-9_]+\.json", name):
        raise ValueError("Invalid coordination filename")
    return directory / name


def stage_data(data):
    if not isinstance(data, str) or len(data.encode()) > MAX_STAGE:
        raise ValueError("Coordination marker exceeds its bound")
    parsed = json.loads(data)
    if not isinstance(parsed, dict) or parsed.get("ready") is not True:
        raise ValueError("Only existing ready stage markers are bridged")
    return data


def publish(message):
    print(json.dumps(message, separators=(",", ":")), flush=True)


def private_directory(path):
    directory = Path(path).resolve()
    stat = directory.stat()
    if directory.parent != Path("/tmp") or not directory.name.startswith("bunkercrew-wan-") or stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError("Remote fixture needs its own 0700 /tmp directory")
    return directory


def start_game(directory, configuration):
    slot = configuration.get("slot")
    case = configuration.get("case")
    if type(slot) is not int or slot not in (1,4) or case not in CLASSES or configuration.get("relay") != "wss://bunkercrew.vibechain.rocks/ws":
        raise ValueError("Unsupported owned fixture configuration")
    if case == "crash" and slot != 1:
        raise ValueError("Hard remote host loss requires its owned slot-one process")
    package = directory / "package"
    binary = package / "Bunkercrew.x86_64"
    if binary.is_symlink() or digest(binary) != configuration.get("binary_sha256"):
        raise ValueError("Remote executable hash differs from the local export")
    libraries = configuration.get("libraries")
    if not isinstance(libraries, dict) or len(libraries) != 1:
        raise ValueError("Exactly one recorded native audio library is required")
    for relative, expected in libraries.items():
        supplied = package / relative
        source = supplied.resolve()
        if not source.is_relative_to(package.resolve()) or supplied.is_symlink() or digest(source) != expected:
            raise ValueError("Remote native library hash differs from the local export")
    folder = directory / (case + "-" + str(slot))
    folder.mkdir(mode=0o700)
    cwd = folder / "cwd"
    cwd.mkdir(mode=0o700)
    os.link(binary, cwd / binary.name)
    for relative in libraries:
        target = cwd / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        os.link(package / relative, target)
    (cwd / "override.cfg").write_text('[application]\nrun/main_loop_type="' + CLASSES[case] + '"\nrun/main_scene="res://tests/beta_empty.tscn"\nrun/disable_stdout=false\n')
    environment = dict(os.environ)
    for name in ("LASTSHIFT_NETWORK_CAPTURE", "LASTSHIFT_GAMEPLAY_ROLE", "LASTSHIFT_GAMEPLAY_PATH"):
        environment.pop(name, None)
    for kind in ("DATA", "CONFIG", "CACHE", "STATE"):
        path = folder / kind.lower()
        path.mkdir(mode=0o700)
        environment["XDG_" + kind + "_HOME"] = str(path)
    environment.update({"LASTSHIFT_GAMEPLAY_ROLE": "host" if slot == 1 else "guest4",
                        "LASTSHIFT_GAMEPLAY_PATH": str(folder / "run"), "LASTSHIFT_PARTY_SLOT": str(slot),
                        "LASTSHIFT_PARTY_RELAY": configuration["relay"], "BUNKERCREW_HOST_DEPARTURE": case,
                        "BUNKERCREW_EXPORTED_PEER": "1"})
    command = [str(cwd / binary.name), "--headless", "--audio-driver", "Dummy", "--", "--no-profile-save", "--no-upnp"]
    log_path = folder / "peer.log"
    process = None
    try:
        with log_path.open("x") as stream:
            process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
        publish({"op": "started", "pid": process.pid, "command": command,
                 "cwd": str(cwd), "start_ticks": Path("/proc/%d/stat"%process.pid).read_text().rsplit(") ",1)[1].split()[19],
                 "binary_sha256": digest(binary), "libraries": libraries,
                 "machine": {"hostname": __import__("socket").gethostname(), "system": os.uname().sysname,
                             "kernel": os.uname().release, "architecture": os.uname().machine}})
        return process, folder, log_path
    except BaseException:
        # main() cannot own this handle until the return completes. A broken
        # SSH pipe or interruption during PID publication must retire it here.
        stop_owned(process)
        raise


def stop_owned(process):
    if process is None: return
    if process.poll() is None:
        try: os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try: os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            process.wait(timeout=3)


def crash_owned_host(process, configuration, folder):
    """Kill only this helper's still-owned Popen at its actual crash checkpoint."""
    if configuration.get("case") != "crash" or configuration.get("slot") != 1:
        raise ValueError("Only the configured owned remote host may be crashed")
    marker = stage_path(folder, "run.host_departure_ready.json")
    if not marker.is_file() or json.loads(stage_data(marker.read_text())).get("mode") != "crash":
        raise ValueError("Actual host crash readiness has not been published")
    if process is None or process.poll() is not None:
        raise ValueError("Owned host is no longer running")
    os.killpg(process.pid, signal.SIGKILL)
    code = process.wait(timeout=5)
    if code != -signal.SIGKILL:
        raise RuntimeError("Owned host did not exit from the requested SIGKILL")
    publish({"op":"crashed","pid":process.pid,"signal":int(signal.SIGKILL),"returncode":code})


def read_configuration():
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin.fileno(), selectors.EVENT_READ)
    pending = b""
    deadline = time.monotonic()+10
    try:
        while b"\n" not in pending:
            if time.monotonic() >= deadline: raise TimeoutError("Remote configuration deadline expired")
            if not selector.select(min(.1, max(0, deadline-time.monotonic()))): continue
            data = os.read(sys.stdin.fileno(), 65536)
            if not data: raise ConnectionError("Remote configuration stream closed")
            pending += data
            if len(pending) > MAX_MESSAGE: raise ValueError("Remote configuration exceeds its bound")
        first, remaining = pending.split(b"\n",1)
        return json.loads(first), remaining
    finally:
        selector.close()


def main():
    process = None
    try:
        directory = private_directory(sys.argv[1])
        configuration, pending = read_configuration()
        process, folder, log_path = start_game(directory, configuration)
        selector = selectors.DefaultSelector()
        selector.register(sys.stdin.fileno(), selectors.EVENT_READ)
        seen = {}
        log_position = 0
        deadline = time.monotonic()+130
        def flush_output():
            nonlocal log_position
            for path in folder.glob("run.*.json"):
                stage_path(folder, path.name)
                data = stage_data(path.read_text())
                checksum = hashlib.sha256(data.encode()).hexdigest()
                if seen.get(path.name) != checksum:
                    publish({"op": "stage", "name": path.name, "data": data})
                    seen[path.name] = checksum
            with log_path.open("r", errors="replace") as stream:
                stream.seek(log_position)
                content = stream.read(65536)
                log_position = stream.tell()
            if content: publish({"op": "log", "data": content})
        def accept_messages():
            nonlocal pending
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                message = json.loads(line)
                if message.get("op") == "stop": raise ConnectionError("Caller stopped its owned fixture")
                if message.get("op") == "crash_owned_host":
                    crash_owned_host(process, configuration, folder)
                    continue
                if message.get("op") != "stage": raise ValueError("Only stage markers are accepted")
                path = stage_path(folder, message.get("name"))
                data = stage_data(message.get("data"))
                if not path.exists() or path.read_text() != data:
                    temporary = path.with_suffix(".tmp")
                    temporary.write_text(data)
                    os.replace(temporary, path)
                seen[path.name] = hashlib.sha256(data.encode()).hexdigest()
        while process.poll() is None:
            if time.monotonic() >= deadline:
                raise TimeoutError("Remote owned game reached the real 130-second deadline")
            accept_messages()
            for _, _ in selector.select(.05):
                data = os.read(sys.stdin.fileno(), 65536)
                if not data: raise ConnectionError("Coordination SSH stream closed")
                pending += data
                if len(pending) > MAX_MESSAGE: raise ValueError("Remote message exceeds its bound")
            accept_messages()
            flush_output()
        flush_output()
        current_libraries = {relative:digest(directory/"package"/relative) for relative in configuration["libraries"]}
        if current_libraries != configuration["libraries"]: raise ValueError("Remote native library changed during the actual game")
        publish({"op": "exit", "returncode": process.returncode, "timed_out": False,
                 "binary_sha256": digest(directory / "package/Bunkercrew.x86_64"), "libraries":current_libraries})
        return 0
    except (Exception, KeyboardInterrupt) as error:
        publish({"op": "error", "error": str(error)})
        return 1
    finally:
        stop_owned(process)


if __name__ == "__main__":
    def interrupted(_signal, _frame): raise KeyboardInterrupt("Owned remote helper interrupted")
    for number in (signal.SIGHUP, signal.SIGTERM): signal.signal(number, interrupted)
    raise SystemExit(main())
