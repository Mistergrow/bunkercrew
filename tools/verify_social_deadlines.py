#!/usr/bin/env python3
"""Exercise full social deadlines over real sockets with isolated identities."""
from __future__ import annotations

import argparse
import asyncio
import collections
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile

from aiohttp.test_utils import TestServer
import verify_beta_stability as stability

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from server.relay import Settings, create_app
from server.social import SOCIAL_KEY


async def run(args) -> dict:
    # Only these test-instance acknowledgements are withheld. Authentication,
    # profile storage, packet validation and heartbeat remain production code.
    app = create_app(Settings(social_db=":memory:"))
    social = app[SOCIAL_KEY]
    ordinary_command = social.command
    withheld = collections.Counter()

    async def controlled_command(session, payload):
        operation = payload.get("op")
        if session.profile is not None and operation in ("resolve_room", "verify_crew", "add_friend"):
            withheld[operation] += 1
            return
        await ordinary_command(session, payload)

    social.command = controlled_command
    sockets = set()

    async def blackhole(reader, writer):
        sockets.add(writer)
        try:
            # Accept the actual TLS client hello and never answer it.
            while await reader.read(4096):
                pass
        finally:
            writer.close()
            await writer.wait_closed()
            sockets.discard(writer)

    server = TestServer(app)
    await server.start_server()
    silent = await asyncio.start_server(blackhole, "127.0.0.1", 0)
    port = silent.sockets[0].getsockname()[1]
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix="bunkercrew-social-deadlines-") as directory:
            base = Path(directory)
            original = stability.source_manifest(args.project)
            frozen = base / "project"
            stability.copy_snapshot(args.project, frozen, original)
            env = stability.private_environment(base / "import", args.godot)
            imported = await asyncio.to_thread(stability.run_check,
                [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(frozen),
                 "--editor", "--recovery-mode", "--import", "--quit"], frozen, env, args.output / "import.log", 180)
            if not imported["success"]:
                raise RuntimeError("Private deadline project import failed")
            inputs = stability.source_manifest(frozen)
            env = stability.private_environment(base / "peer", args.godot)
            env.update({"BUNKERCREW_DEADLINE_SILENT": f"wss://127.0.0.1:{port}/social",
                        "BUNKERCREW_DEADLINE_SERVICE": str(server.make_url("/social")).replace("http://", "ws://", 1)})
            command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(frozen),
                       "--script", "tests/social_deadline_peer.gd", "--", "--no-profile-save", "--no-upnp"]
            log = args.output / "peer.log"
            with log.open("x") as stream:
                process = subprocess.Popen(command, cwd=frozen, env=env, stdout=stream,
                                           stderr=subprocess.STDOUT, start_new_session=True)
            await asyncio.wait_for(asyncio.to_thread(process.wait), 45)
            content = log.read_text(errors="replace")
            match = re.search(r"SOCIAL DEADLINE: (\d+)/(\d+) checks passed", content)
            if process.returncode or not match or match[1] != match[2] or stability.DIAGNOSTIC.search(content):
                raise RuntimeError("Real social deadline fixture failed; see " + str(log))
            if dict(withheld) != {"resolve_room": 1, "add_friend": 1, "verify_crew": 1}:
                raise RuntimeError("Real service did not observe each withheld request exactly once")
            if stability.changed_files(inputs, stability.source_manifest(frozen)):
                raise RuntimeError("Frozen deadline fixture changed during execution")
            evidence = re.search(r"^SOCIAL_DEADLINE_EVIDENCE (.+)$", content, re.MULTILINE)
            return {"success": True, "checks": int(match[2]), "observed_withheld_commands": dict(withheld),
                    "seconds": json.loads(evidence[1]), "paused": True, "gameplay_time_scale": .1,
                    "fixtures": "Real production SocialService in memory; only the three responses withheld. Actual silent TLS TCP endpoint; isolated no-save Godot hub.",
                    "inputs": inputs}
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            await asyncio.to_thread(process.wait)
        silent.close()
        await silent.wait_closed()
        for writer in tuple(sockets):
            writer.close()
        await server.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"success": False}
    try:
        report = asyncio.run(run(args))
    except (OSError, ValueError, RuntimeError, asyncio.TimeoutError) as error:
        report["error"] = str(error)
    (args.output / "result.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(("PASS " if report["success"] else "FAIL ") + str(args.output / "result.json"))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
