#!/usr/bin/env python3
"""Confirm that an owned native peer's process group retired; never signal it."""
import json
import os
from pathlib import Path
import sys
import time


def observations(configuration):
    pid=configuration["pid"]
    directory=Path(configuration["directory"])
    if type(pid) is not int or pid<=1 or directory.parent!=Path("/tmp") or not directory.name.startswith("bunkercrew-wan-"):
        raise ValueError("Invalid owned peer cleanup identity")
    path=Path("/proc")/str(pid)
    identity={"pid":pid,"exists":path.exists()}
    if path.exists():
        try:
            fields=(path/"stat").read_text().rsplit(") ",1)[1].split()
            ticks=fields[19]
            cwd=os.readlink(path/"cwd")
            command=(path/"cmdline").read_bytes().split(b"\0")[0].decode(errors="replace")
            matches=ticks==configuration.get("start_ticks") and cwd==configuration.get("cwd") and command==configuration.get("command",[None])[0]
            identity.update({"start_ticks_match":ticks==configuration.get("start_ticks"),"cwd_match":cwd==configuration.get("cwd"),"command_match":command==configuration.get("command",[None])[0],"owned_identity_match":matches})
        except FileNotFoundError:
            identity["exists"]=False
    group=[]
    for candidate in Path("/proc").iterdir():
        if not candidate.name.isdigit():continue
        try:
            fields=(candidate/"stat").read_text().rsplit(") ",1)[1].split()
            if int(fields[2])==pid:group.append({"pid":int(candidate.name),"state":fields[0]})
        except (OSError,IndexError,ValueError):pass
    identity["group_members"]=group
    identity["retired"]=not group and not identity["exists"]
    identity["foreign_identity_detected"]=identity["exists"] and not identity.get("owned_identity_match",False)
    return identity


def main():
    configuration=json.loads(sys.stdin.read(65536))
    deadline=time.monotonic()+8
    result=observations(configuration)
    while not result["retired"] and not result["foreign_identity_detected"] and time.monotonic()<deadline:
        time.sleep(.1)
        result=observations(configuration)
    print(json.dumps(result))
    return 0 if result["retired"] else 1


if __name__=="__main__":raise SystemExit(main())
