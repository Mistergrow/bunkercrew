#!/usr/bin/env python3
"""Actual four-client direct/relay identity, mutual consent and private routing."""
from __future__ import annotations
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/social/crew"

def run_case(relay: bool, short: bool=False, blocked_direct: bool=False) -> None:
    output = OUTPUT / ("relay-short-blocked-direct" if blocked_direct else "relay-short" if relay and short else "direct-short" if short else "relay" if relay else "direct")
    output.mkdir(parents=True, exist_ok=True)
    processes = []
    with tempfile.TemporaryDirectory(prefix="bunkercrew-crew-") as folder:
        fixture = Path(folder)
        with (output/"service.log").open("w") as log:
            server = subprocess.Popen([sys.executable,"server/relay.py"],cwd=ROOT,env={**os.environ,"PORT":"24980","RELAY_HOST":"127.0.0.1","SOCIAL_DB":str(fixture/"social.sqlite3")},stdout=log,stderr=subprocess.STDOUT)
        try:
            until = time.monotonic()+8
            while time.monotonic()<until:
                try:
                    with urllib.request.urlopen("http://127.0.0.1:24980/healthz",timeout=.2) as response:
                        if response.status==200: break
                except OSError: time.sleep(.05)
            else: raise AssertionError("Presence service did not start")
            command=[shutil.which("godot") or "godot","--headless","--debug","--path",str(ROOT),"--script","tests/crew_social_peer.gd","--","--no-profile-save","--no-upnp"]
            for slot in range(1,5):
                with (output/f"slot{slot}.log").open("w") as log:
                    process=subprocess.Popen(command,cwd=ROOT,env={**os.environ,"BUNKERCREW_CREW_SLOT":str(slot),"BUNKERCREW_CREW_SHORT":"1" if short else "0","BUNKERCREW_CREW_BLOCKED_DIRECT":"1" if blocked_direct else "0","BUNKERCREW_CREW_PATH":str(fixture/"flow"),"BUNKERCREW_CREW_RELAY":"ws://127.0.0.1:24980/ws" if relay else "","BUNKERCREW_CREW_SERVICE":"ws://127.0.0.1:24980/social","XDG_DATA_HOME":str(fixture/f"slot{slot}")},stdout=log,stderr=subprocess.STDOUT)
                processes.append(process)
                stage="room" if slot==1 else f"joined{slot}"
                until=time.monotonic()+22
                while not (fixture/f"flow.{stage}.json").exists() and process.poll() is None and time.monotonic()<until: time.sleep(.04)
                if not (fixture/f"flow.{stage}.json").exists(): raise AssertionError((output/f"slot{slot}.log").read_text())
            until=time.monotonic()+95
            while any(p.poll() is None for p in processes) and time.monotonic()<until: time.sleep(.05)
            all_logs="\n".join((output/f"slot{slot}.log").read_text() for slot in range(1,5))
            for slot,process in enumerate(processes,1):
                log=(output/f"slot{slot}.log").read_text()
                assert process.poll()==0 and "NETWORK_GAMEPLAY_PASS" in log, all_logs
                assert not any(marker in log for marker in ("ERROR:","SCRIPT ERROR","WARNING:")),all_logs
            assert "Traceback" not in (output/"service.log").read_text()
            print(f"CREW SOCIAL {'relay' if relay else 'direct'}{' short-code' if short else ''}{' blocked direct UDP' if blocked_direct else ''}: actual4-client PASS",flush=True)
        finally:
            for process in processes:
                if process.poll() is None: process.kill()
                process.wait(timeout=5)
            server.terminate();server.wait(timeout=5)
if __name__=="__main__":
    if "--blocked-direct-short-only" in sys.argv: run_case(True,True,True);sys.exit(0)
    if "--relay-short-only" in sys.argv: run_case(True,True);sys.exit(0)
    if "--short-only" in sys.argv: run_case(False,True);sys.exit(0)
    for use_relay in ([False] if "--direct-only" in sys.argv else [True] if "--relay-only" in sys.argv else [False,True]): run_case(use_relay)
