#!/usr/bin/env python3
"""Verify the shipped non-root, read-only image retains friendships on /data."""
from __future__ import annotations

import subprocess
import uuid

CLIENT = r'''
import asyncio, json, os, secrets, sys
import aiohttp

async def until(socket, predicate):
    for _ in range(30):
        message = await asyncio.wait_for(socket.receive_json(), 5)
        if message.get('op') == 'error':
            raise AssertionError(message['code'])
        if predicate(message):
            return message
    raise AssertionError('No matching service response')

async def main():
    stage = sys.argv[1]
    path = '/data/container-fixture.json'
    if stage == 'create':
        profile = [{'secret':secrets.token_hex(32),'name':name} for name in ['Mara','Ivo']]
    else:
        with open(path) as source: profile = json.load(source)
    async with aiohttp.ClientSession() as client:
        async with client.get('http://127.0.0.1:8765/healthz') as response:
            build = (await response.json())['build']
        sockets = []
        for identity in profile:
            socket = await client.ws_connect('http://127.0.0.1:8765/social')
            sockets.append(socket)
            await socket.send_json({'op':'auth','version':1,'build':build,'secret':identity['secret'],'name':identity['name']})
            state = await until(socket, lambda value: value.get('op') == 'ready')
            if stage == 'create':
                identity['code'] = state['code']
            else:
                assert state['code'] == identity['code']
                assert len(state['friends']) == 1
        first, second = sockets
        if stage == 'create':
            await first.send_json({'op':'add_friend','code':profile[1]['code']})
            await until(second, lambda value: any(item['code'] == profile[0]['code'] for item in value.get('requests',[])))
            await second.send_json({'op':'accept_friend','code':profile[0]['code']})
            await until(first, lambda value: len(value.get('friends',[])) == 1)
            await until(second, lambda value: len(value.get('friends',[])) == 1)
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor,'w') as destination: json.dump(profile,destination)
        for socket in sockets: await socket.close()
        print('CONTAINER SOCIAL', stage, 'passed as uid', os.getuid())

asyncio.run(main())
'''


def run(*arguments: str) -> str:
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout.strip()


def main() -> None:
    suffix = uuid.uuid4().hex[:10]
    name = f"bunkercrew-social-check-{suffix}"
    volume = f"bunkercrew-social-check-data-{suffix}"
    run("docker", "volume", "create", volume)
    try:
        for stage in ("create", "restore"):
            run("docker", "run", "--detach", "--rm", "--pull", "never", "--name", name,
                "--network", "none", "--read-only", "--cap-drop", "ALL",
                "--security-opt", "no-new-privileges:true", "--pids-limit", "64",
                "--memory", "512m", "--volume", f"{volume}:/data",
                "bunkercrew-social:local")
            run("docker", "exec", name, "python", "-c",
                "import time,urllib.request\n"
                "for attempt in range(40):\n"
                " try:\n  urllib.request.urlopen('http://127.0.0.1:8765/healthz',timeout=.2);break\n"
                " except OSError: time.sleep(.1)\n"
                "else: raise RuntimeError('Container did not become ready')")
            print(run("docker", "exec", name, "python", "-c", CLIENT, stage))
            run("docker", "stop", "--time", "5", name)
        print("SOCIAL CONTAINER: non-root read-only runtime and durable friendships passed across container replacement.")
    finally:
        subprocess.run(["docker", "rm", "--force", name], capture_output=True, text=True)
        subprocess.run(["docker", "volume", "rm", volume], capture_output=True, text=True)


if __name__ == "__main__":
    main()
