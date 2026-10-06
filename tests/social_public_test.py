#!/usr/bin/env python3
"""Fresh public startup and two actual directly connected, invited game clients."""
from __future__ import annotations
import argparse
import os
import sys
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/social/public"
ENDPOINT = "wss://bunkercrew.vibechain.rocks/social"

def assert_log(process, path, marker):
    value=path.read_text()
    assert process.poll()==0 and marker in value,value
    assert not any(item in value for item in ("ERROR:","SCRIPT ERROR","WARNING:")),value

def main():
    global OUTPUT
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-only",action="store_true")
    parser.add_argument("--connection",choices=("direct","relay","both"),default="both")
    parser.add_argument("--output",type=Path,default=OUTPUT)
    args=parser.parse_args()
    output_root=args.output.resolve()
    output_root.mkdir(parents=True,exist_ok=True)
    OUTPUT=output_root
    OUTPUT.mkdir(parents=True,exist_ok=True)
    godot=shutil.which("godot") or "godot"
    cleanup=tempfile.NamedTemporaryFile(mode="w",prefix="bunkercrew-public-cleanup-",suffix=".json",delete=False)
    cleanup_path=Path(cleanup.name)
    cleanup.close()
    fixture_codes=[]
    def record_code(code):
        if isinstance(code,str) and len(code)==12 and code not in fixture_codes:
            fixture_codes.append(code)
            cleanup_path.write_text(json.dumps({"codes":fixture_codes}))
    print(f"Private QA-account cleanup manifest: {cleanup_path}",flush=True)
    if not args.game_only:
        with tempfile.TemporaryDirectory(prefix="bunkercrew-public-startup-") as folder:
            with (OUTPUT/"startup.log").open("w") as log:
                startup=subprocess.Popen([godot,"--headless","--debug","--path",str(ROOT),"--script","tests/social_default_startup_test.gd","--","--no-upnp"],cwd=ROOT,env={**os.environ,"XDG_DATA_HOME":folder},stdout=log,stderr=subprocess.STDOUT)
            try: startup.wait(timeout=25);assert_log(startup,OUTPUT/"startup.log","SOCIAL DEFAULT STARTUP: 6/6")
            finally:
                if startup.poll() is None: startup.kill();startup.wait()
            # Write a valid saved opt-out without any identity: this used to
            # incorrectly count as a fresh profile and force another login.
            profile=Path(folder)/"godot/app_userdata/Bunkercrew/social_v1.json"
            candidates=list(Path(folder).rglob("social_v1.json"))
            assert len(candidates)==1,candidates
            profile=candidates[0]
            offline=json.loads(profile.read_text())
            for identity in offline["identities"].values(): record_code(identity.get("code"))
            offline["identities"]={}
            offline["connect_on_start"]=False
            profile.write_text(json.dumps(offline))
            with (OUTPUT/"opt-out.log").open("w") as log:
                optout=subprocess.Popen([godot,"--headless","--debug","--path",str(ROOT),"--script","tests/social_default_startup_test.gd","--","--no-upnp","--verify-opt-out"],cwd=ROOT,env={**os.environ,"XDG_DATA_HOME":folder},stdout=log,stderr=subprocess.STDOUT)
            try: optout.wait(timeout=10);assert_log(optout,OUTPUT/"opt-out.log","SOCIAL DEFAULT OPT OUT: 4/4")
            finally:
                if optout.poll() is None: optout.kill();optout.wait()
            backup=profile.with_name(profile.name+".bak")
            backup.write_text(profile.read_text())
            profile.unlink()
            with (OUTPUT/"backup-opt-out.log").open("w") as log:
                backup_optout=subprocess.Popen([godot,"--headless","--debug","--path",str(ROOT),"--script","tests/social_default_startup_test.gd","--","--no-upnp","--verify-opt-out"],cwd=ROOT,env={**os.environ,"XDG_DATA_HOME":folder},stdout=log,stderr=subprocess.STDOUT)
            try: backup_optout.wait(timeout=10);assert_log(backup_optout,OUTPUT/"backup-opt-out.log","SOCIAL DEFAULT OPT OUT: 4/4")
            finally:
                if backup_optout.poll() is None: backup_optout.kill();backup_optout.wait()
    connections=("direct","relay") if args.connection=="both" else (args.connection,)
    for connection in connections:
        processes=[]
        output=OUTPUT/connection
        output.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="bunkercrew-public-game-") as folder:
            fixture=Path(folder)
            try:
                for role in ("host","guest"):
                    with (output/f"{role}.log").open("w") as log:
                        processes.append(subprocess.Popen([godot,"--headless","--debug","--path",str(ROOT),"--script","tests/social_end_to_end_peer.gd","--","--no-profile-save","--no-upnp"],cwd=ROOT,env={**os.environ,"BUNKERCREW_SOCIAL_ROLE":role,"BUNKERCREW_SOCIAL_PATH":str(fixture/"flow"),"BUNKERCREW_SOCIAL_RELAY":"" if connection=="direct" else ENDPOINT.removesuffix("/social")+"/ws","BUNKERCREW_SOCIAL_PUBLIC":ENDPOINT,"XDG_DATA_HOME":str(fixture/role)},stdout=log,stderr=subprocess.STDOUT))
                deadline=time.monotonic()+70
                while any(process.poll() is None for process in processes) and time.monotonic()<deadline: time.sleep(.05)
                for role,process in zip(("host","guest"),processes): assert_log(process,output/f"{role}.log",f"SOCIAL END TO END {role}:")
            finally:
                for process in processes:
                    if process.poll() is None: process.kill()
                    process.wait(timeout=5)
                for role in ("host","guest"):
                    identity=fixture/f"flow.fixture-identity-{role}.json"
                    if identity.exists(): record_code(json.loads(identity.read_text()).get("code"))
        print(f"PUBLIC SOCIAL {connection}: actual UI-six-code/friend/invite/game/chat/restart PASS",flush=True)
    print("PUBLIC SOCIAL: " + ("" if args.game_only else "fresh automatic startup and saved opt-out, ") + "actual " + "/".join(connections) + " six-code flows PASS")
if __name__=="__main__":main()
