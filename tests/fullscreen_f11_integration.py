#!/usr/bin/env python3
"""Run actual F11 input in owned windows, preserving the user's editor and game."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import re
import subprocess
import tempfile
import time
import uuid


def own_godot_processes(token):
    found = []
    expected = f"BUNKERCREW_F11_PROBE={token}".encode()
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if expected in (process / "environ").read_bytes().split(b"\0"):
                comm = (process / "comm").read_text()
                if comm.startswith("godot"):
                    found.append(int(process.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return found


def native_windows_for(pid):
    tree = subprocess.check_output(["xwininfo", "-root", "-tree"], text=True, stderr=subprocess.DEVNULL)
    found = []
    for window_id in set(re.findall(r"\b0x[0-9a-f]+", tree)):
        if window_id=="0x0": continue
        try:
            properties = subprocess.check_output(["xprop", "-id", window_id, "_NET_WM_PID", "_NET_WM_STATE"], text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        if re.search(rf"_NET_WM_PID\(CARDINAL\)\s*=\s*{pid}\b", properties):
            found.append({"id":window_id,"pid":pid,"fullscreen":"_NET_WM_STATE_FULLSCREEN" in properties,"properties":properties})
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--embedded", action="store_true")
    parser.add_argument("--editor-pid", action="store_true", help="Give the owned host PID as an editor parent")
    parser.add_argument("--baseline-display", type=Path)
    parser.add_argument("--wait-handoff", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = root / "artifacts/fullscreen-f11"
    destination.mkdir(parents=True, exist_ok=True)
    mode = "embedded" if args.embedded else "standalone"
    prefix = mode + ("-baseline" if args.baseline_display else "-fixed")
    log_path = destination / f"{prefix}.log"
    for name in (f"{mode}-verification.json",f"{mode}-events.json"):
        (destination / name).unlink(missing_ok=True)
    token = uuid.uuid4().hex
    host = None
    process = None
    observations = []
    try:
        if args.embedded:
            import tkinter
            host = tkinter.Tk()
            host.title("Bunkercrew owned F11 regression window")
            host.geometry("1280x800+24+32")
            host.update()
        with tempfile.TemporaryDirectory(prefix="bunkercrew-f11-") as profile:
            command = [shutil.which("godot"), "--debug", "--path", str(root), "--script", "tests/fullscreen_f11_probe.gd", "--audio-driver", "Dummy", "--resolution", "1280x800", "--position", "24,32", "--max-fps", "60"]
            if args.embedded:
                command.extend(["--wid", str(host.winfo_id())])
            if args.editor_pid:
                command.extend(["--editor-pid", str(os.getpid())])
            command.extend(["--", "--no-profile-save", "--no-upnp"])
            if args.embedded:
                command.append("--embedded-probe")
            if args.wait_handoff:
                command.append("--wait-handoff")
            if args.baseline_display:
                command.append(f"--baseline-display={args.baseline_display.resolve()}")
            with log_path.open("w", encoding="utf-8") as log:
                process = subprocess.Popen(command, cwd=root, env={**os.environ, "XDG_DATA_HOME": profile, "BUNKERCREW_F11_PROBE": token}, stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 35.0
                while process.poll() is None and time.monotonic() < deadline:
                    if host:
                        host.update()
                    time.sleep(.025)
                if process.poll() is None:
                    raise TimeoutError("The owned Godot F11 probe did not complete.")
                observations.append({"initial_pid": process.pid, "initial_exit_code": process.returncode, "embedded": args.embedded, "editor_pid_flag": args.editor_pid, "baseline_source": bool(args.baseline_display)})
                # A baseline implicit restart can create an ordinary game instead
                # of returning to the runner. Observe and stop only our token's processes.
                for _ in range(200):
                    if host:
                        host.update()
                    alive = own_godot_processes(token)
                    if alive:
                        observations[-1]["spawned_pids"] = alive
                        windows = []
                        for pid in alive:
                            windows.extend(native_windows_for(pid))
                        observations[-1]["spawned_windows"] = windows
                        for window in windows:
                            if window["fullscreen"]:
                                subprocess.run(["import", "-window",window["id"],str(destination / "embedded-native-fullscreen.png")],check=True,timeout=15)
                        if any(window["fullscreen"] for window in windows): break
                    time.sleep(.025)
                (destination / f"{prefix}-processes.json").write_text(json.dumps(observations, indent=2), encoding="utf-8")
                for name in (f"{mode}-verification.json",f"{mode}-events.json"):
                    source = destination / name
                    if source.exists():
                        shutil.copyfile(source,destination / name.replace(mode,prefix,1))
                if args.wait_handoff:
                    assert observations[-1].get("spawned_pids") and any(window["fullscreen"] for window in observations[-1].get("spawned_windows",[])), "The actual embedded game did not hand over to a rendered native fullscreen window."
    finally:
        for pid in own_godot_processes(token):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if process and process.poll() is None:
            process.wait(timeout=5)
        if host:
            host.destroy()
    log = log_path.read_text(encoding="utf-8", errors="replace")
    if process.returncode or any(text in log for text in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    if args.wait_handoff:
        result = {"actual_main_scene":True,"owned_x11_parent":True,"editor_pid_flag":args.editor_pid,"passed":True,"processes":observations,"screenshot":"embedded-native-fullscreen.png","source":"Current DisplaySettings, actual F11 input; embedded process exits only after replacement fullscreen-frame acknowledgement"}
        path = destination / "embedded-handoff-verification.json"
        path.write_text(json.dumps(result,indent=2),encoding="utf-8")
        print(f"Actual embedded game acknowledged its rendered native fullscreen replacement: {path}")
        return
    verification_path = destination / f"{mode}-verification.json"
    if not verification_path.exists():
        print(f"F11 probe exited before verification: {observations}; log: {log_path}")
        return
    verification = json.loads(verification_path.read_text())
    if verification["failures"]:
        raise SystemExit(log)
    print(f"Actual {mode} F11 regression passed {verification['checks']}/{verification['checks']}: {verification_path}")


if __name__ == "__main__":
    main()
