#!/usr/bin/env python3
"""A private real WebSocket injects malformed controls before valid admission."""
from __future__ import annotations
import asyncio
import os
from pathlib import Path
import shutil
import tempfile
from aiohttp import web
from aiohttp.test_utils import TestServer

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/code-hardening/network/network_relay_json_peer.log"


async def main():
    async def connection(request):
        socket = web.WebSocketResponse()
        await socket.prepare(request)
        message = await socket.receive_json()
        assert message["op"] == "host", message
        for malformed in ("{", '{"op":', "[invalid]", "null", "[]", "true"):
            await socket.send_str(malformed)
        await socket.send_json({"op":"hosted", "code":"ABCDEF", "role":"host", "player_id":1,
                                "token":"abcdefghijklmnopqrstuvwxyz012345",
                                "resume_token":"abcdefghijklmnopqrstuvwxyz012345", "started":False})
        async for _message in socket:
            pass
        return socket

    app = web.Application()
    app.router.add_get("/ws", connection)
    async with TestServer(app) as server:
        with tempfile.TemporaryDirectory(prefix="bunkercrew-relay-json-") as folder:
            environment = {**os.environ, "BUNKERCREW_JSON_RELAY": str(server.make_url("/ws")).replace("http://", "ws://")}
            for kind in ("CONFIG", "DATA", "CACHE"):
                environment[f"XDG_{kind}_HOME"] = str(Path(folder) / kind.lower())
            process = await asyncio.create_subprocess_exec(
                shutil.which("godot") or "godot", "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                "--script", "tests/network_relay_json_peer.gd", "--", "--no-profile-save", "--no-upnp",
                cwd=ROOT, env=environment, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
            try:
                stdout, _ = await asyncio.wait_for(process.communicate(), 20)
            except BaseException:
                if process.returncode is None:
                    process.kill()
                    await process.wait()
                raise
            log = stdout.decode()
            OUTPUT.parent.mkdir(parents=True, exist_ok=True)
            OUTPUT.write_text(log)
            assert process.returncode == 0 and "RELAY JSON:" in log, log
            assert not any(marker in log for marker in ("ERROR:", "SCRIPT ERROR", "WARNING:")), log
            print("RELAY JSON: actual malformed text frames are handled quietly; later valid admission succeeds.")


if __name__ == "__main__":
    asyncio.run(main())
