#!/usr/bin/env python3
"""Godot reconnects to a killed service and keeps identities across cold starts."""
from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT/"artifacts/social/reconnect"


def wait(predicate, seconds=20):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("Real social integration barrier timed out")


def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    processes = []
    relay = None
    with tempfile.TemporaryDirectory(prefix="bunkercrew-social-reconnect-") as temporary:
        folder = Path(temporary)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1",0))
            port = probe.getsockname()[1]

        def start_relay(generation):
            with (OUTPUT/f"relay-{generation}.log").open("w") as log:
                process = subprocess.Popen([sys.executable,"server/relay.py"],cwd=ROOT,
                    env={**os.environ,"PORT":str(port),"RELAY_HOST":"127.0.0.1","SOCIAL_DB":str(folder/"social.sqlite3")},
                    stdout=log,stderr=subprocess.STDOUT)
            def ready():
                if process.poll() is not None:
                    raise AssertionError((OUTPUT/f"relay-{generation}.log").read_text())
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz",timeout=0.2) as response:
                        return response.status == 200
                except OSError:
                    return False
            wait(ready,8)
            return process

        def clients(phase):
            result = []
            for role in ("host","guest"):
                flags = ["--no-upnp"] + (["--no-profile-save"] if phase=="initial" else [])
                command = [shutil.which("godot") or "godot","--headless","--debug","--audio-driver","Dummy",
                    "--path",str(ROOT),"--script","tests/social_reconnect_peer.gd","--",*flags]
                with (OUTPUT/f"{phase}-{role}.log").open("w") as log:
                    result.append(subprocess.Popen(command,cwd=ROOT,env={**os.environ,
                        "XDG_DATA_HOME":str(folder/f"userdata-{role}"),"BUNKERCREW_SOCIAL_ISOLATED":"1",
                        "BUNKERCREW_SOCIAL_ROLE":role,"BUNKERCREW_SOCIAL_PHASE":phase,
                        "BUNKERCREW_SOCIAL_FOLDER":str(folder),"BUNKERCREW_SOCIAL_URL":f"ws://127.0.0.1:{port}/social"},
                        stdout=log,stderr=subprocess.STDOUT))
            processes.extend(result)
            return result

        def barriers(stage):
            return all((folder/f"{role}-{stage}.json").exists() for role in ("host","guest"))

        def finish_clients(group,phase):
            wait(lambda:all(process.poll() is not None for process in group),10)
            for role,process in zip(("host","guest"),group):
                text = (OUTPUT/f"{phase}-{role}.log").read_text()
                assert process.returncode==0 and f"SOCIAL RECONNECT {phase} {role}:" in text,text
                assert not any(marker in text for marker in ("ERROR:","WARNING:","SCRIPT ERROR","Debugger Break")),text

        try:
            relay = start_relay(1)
            initial = clients("initial")
            wait(lambda:barriers("ready"))
            relay.kill()  # Abrupt death, including SQLite WAL recovery.
            relay.wait(timeout=5)
            wait(lambda:barriers("disconnected"))
            relay = start_relay(2)
            wait(lambda:barriers("reconnected"),25)
            (folder/"done-initial.json").write_text('{"ready":true}')
            finish_clients(initial,"initial")
            time.sleep(0.3)
            cold = clients("cold")
            wait(lambda:barriers("cold-connected"))
            # Give the actual rename/confirmed friend notification a chance to
            # reach the guest before completing its final wait barrier.
            time.sleep(0.5)
            (folder/"done-cold.json").write_text('{"ready":true}')
            finish_clients(cold,"cold")
            for role in ("host","guest"):
                data = json.loads((folder/f"{role}-profile.json").read_text())
                assert data["connect_on_start"] is True
                if os.name == "posix":
                    assert (folder/f"{role}-profile.json").stat().st_mode&0o777==0o600
            print("SOCIAL RECONNECT: real Godot clients recovered after hard server restart; cold starts retained credentials, consent, names and opt-in.")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            if relay and relay.poll() is None:
                relay.terminate()
                relay.wait(timeout=5)


if __name__=="__main__":
    main()
