#!/usr/bin/env python3
"""Real-socket relay integration tests; no external service or pytest needed."""

from __future__ import annotations

import asyncio
import dataclasses
import pathlib
import sys
import unittest

from aiohttp import ClientSession, WSServerHandshakeError, WSMsgType
from aiohttp.test_utils import TestServer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "server"))
from relay import (
    CODE_ALPHABET,
    GAME_BUILD,
    MAX_PACKET_BYTES,
    PROTOCOL_VERSION,
    RELAY_KEY,
    Settings,
    create_app,
    VoiceGuard,
)


class RelayIntegration(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.servers = []
        self.clients = ClientSession()
        self.sockets = []
        self.server = await self.start_server()

    async def asyncTearDown(self):
        for socket in self.sockets:
            await socket.close()
        await self.clients.close()
        for server in self.servers:
            await server.close()

    async def start_server(self, **changes):
        settings = dataclasses.replace(Settings(), **changes)
        server = TestServer(create_app(settings))
        await server.start_server()
        self.servers.append(server)
        return server

    async def connect(self, server=None, **kwargs):
        socket = await self.clients.ws_connect(
            (server or self.server).make_url("/ws"), **kwargs
        )
        self.sockets.append(socket)
        return socket

    async def receive(self, socket, op=None):
        message = await asyncio.wait_for(socket.receive_json(), timeout=2)
        if op:
            self.assertEqual(message["op"], op, message)
        return message

    async def command(self, socket, op, **fields):
        payload = {"op": op, **fields}
        if op in ("host", "join", "resume"):
            payload.setdefault("version", PROTOCOL_VERSION)
            payload.setdefault("build", GAME_BUILD)
            if op != "resume":
                payload.setdefault("name", "Testspieler")
        await socket.send_json(payload)

    async def room(self, server=None):
        host = await self.connect(server)
        guest = await self.connect(server)
        await self.command(host, "host", name="Mara")
        hosted = await self.receive(host, "hosted")
        await self.command(guest, "join", code=hosted["code"], name="Ivo")
        joined = await self.receive(guest, "joined")
        self.assertEqual((await self.receive(host, "peer_joined"))["role"], "guest")
        self.assertEqual((await self.receive(guest, "peer_joined"))["role"], "host")
        return host, guest, hosted, joined

    async def fill_room(self, host, hosted):
        peers = []
        for slot in (3, 4):
            peer = await self.connect()
            await self.command(peer, "join", code=hosted["code"])
            joined = await self.receive(peer, "joined")
            self.assertEqual(joined["player_id"], slot)
            self.assertEqual(
                (await self.receive(host, "peer_joined"))["player_id"], slot
            )
            self.assertEqual((await self.receive(peer, "peer_joined"))["player_id"], 1)
            peers.append(peer)
        return peers

    async def test_four_slots_route_only_through_authoritative_host(self):
        host, guest, hosted, _ = await self.room()
        third, fourth = await self.fill_room(host, hosted)
        for slot, peer in ((2, guest), (3, third), (4, fourth)):
            await peer.send_bytes(b"\x01same opaque payload")
            self.assertEqual(
                await host.receive_bytes(), bytes([slot]) + b"same opaque payload"
            )
            await host.send_bytes(bytes([slot]) + b"individual response")
            self.assertEqual(await peer.receive_bytes(), b"\x01individual response")
        await third.send_bytes(b"\x04forged direct command")
        self.assertEqual((await self.receive(third, "error"))["code"], "invalid_route")
        await fourth.send_bytes(b"\x00fake source")
        self.assertEqual((await self.receive(fourth, "error"))["code"], "invalid_route")

    async def test_host_broadcast_routes_once_to_every_guest(self):
        host, guest, hosted, _ = await self.room()
        third, fourth = await self.fill_room(host, hosted)
        await host.send_bytes(b"\x00shared state")
        for peer in (guest, third, fourth):
            self.assertEqual(await peer.receive_bytes(), b"\x01shared state")
        await host.send_bytes(b"\x80shared voice")
        for peer in (guest, third, fourth):
            self.assertEqual(await peer.receive_bytes(), b"\x01shared voice")

    async def test_slow_guest_does_not_block_other_guest(self):
        host, guest, hosted, _ = await self.room()
        third, _ = await self.fill_room(host, hosted)
        connection = self.server.app[RELAY_KEY].rooms[hosted["code"]].seats["guest"].connection
        blocked_send = asyncio.Event()

        async def blocked(_data, **_kwargs):
            await blocked_send.wait()

        connection.socket.send_bytes = blocked
        await host.send_bytes(b"\x02slow guest")
        await host.send_bytes(b"\x03healthy guest")
        self.assertEqual(
            await asyncio.wait_for(third.receive_bytes(), 0.5), b"\x01healthy guest"
        )
        blocked_send.set()

    async def test_game_leave_precedes_peer_left_behind_a_blocked_host_queue(self):
        host, guest, hosted, _ = await self.room()
        relay = self.server.app[RELAY_KEY]
        connection = relay.rooms[hosted["code"]].seats["host"].connection
        gate = asyncio.Event()
        entered = asyncio.Event()
        original = connection.socket.send_bytes

        async def blocked(data, **kwargs):
            entered.set()
            await gate.wait()
            await original(data, **kwargs)

        connection.socket.send_bytes = blocked
        await guest.send_bytes(b"\x01final game leave")
        await asyncio.wait_for(entered.wait(), 1)
        await self.command(guest, "leave")
        # The departure event must queue behind the in-flight binary writer.
        for _ in range(100):
            if connection.outbound.qsize():
                break
            await asyncio.sleep(.001)
        self.assertGreater(connection.outbound.qsize(), 0)
        gate.set()
        first = await asyncio.wait_for(host.receive(), 1)
        self.assertEqual(first.type, WSMsgType.BINARY)
        self.assertEqual(first.data, b"\x02final game leave")
        departure = await self.receive(host, "peer_left")
        self.assertEqual(departure["reconnect_seconds"], 0)
        self.assertEqual(departure["reason"], "left")
        await self.receive(guest, "left")

    async def test_voice_guard_tolerates_bursts_and_rejects_sustained_excess(self):
        guard = VoiceGuard()
        self.assertTrue(all(guard.observe(0) for _ in range(400)))
        # A burst followed by ordinary speech clears excess within one sample.
        for step in range(1, 151):
            self.assertTrue(guard.observe(step*.02))
        guard = VoiceGuard()
        rejected = False
        for step in range(1201):
            if not guard.observe(step/500):
                rejected = True
                self.assertGreaterEqual(step/500, 2)
                break
        self.assertTrue(rejected)
        host_guard = VoiceGuard()
        for step in range(2250):
            self.assertTrue(host_guard.observe(step/450, 9), "Full voice fanout is legitimate")

    async def test_excess_voice_is_dropped_without_delaying_other_guest_input(self):
        host, guest, hosted, _ = await self.room()
        third, _fourth = await self.fill_room(host, hosted)
        for _ in range(100):
            await guest.send_bytes(b"\x81speech")
        await third.send_bytes(b"\x01healthy input")
        got_input = False
        voices = 0
        for _ in range(60):
            packet = await asyncio.wait_for(host.receive_bytes(), .5)
            if packet == b"\x03healthy input":
                got_input = True
                break
            voices += 1
        self.assertTrue(got_input)
        self.assertLess(voices, 60, "Over-budget voice is discarded before recipient polling")
        self.assertFalse(guest.closed, "A short speech burst is harmless")

    async def test_sustained_voice_flood_disconnects_only_its_sender(self):
        host, guest, hosted, _ = await self.room()
        third, _fourth = await self.fill_room(host, hosted)
        seat = self.server.app[RELAY_KEY].rooms[hosted["code"]].seats["guest"]
        # Inject the measured persistent-abuse state; sockets still exercise
        # the actual receiver, close and independent-peer routing paths.
        seat.connection.voice_guard.updated = __import__('time').monotonic()-.26
        seat.connection.voice_guard.over_since = __import__('time').monotonic()-2.1
        seat.connection.voice_guard.count = 200
        await guest.send_bytes(b"\x81speech")
        self.assertEqual((await self.receive(guest, "error"))["code"], "rate_limited")
        message = await asyncio.wait_for(guest.receive(), 1)
        self.assertEqual(message.type, WSMsgType.CLOSE)
        self.assertEqual(message.data, 1008)
        await self.receive(host, "peer_left")
        await third.send_bytes(b"\x01healthy input")
        self.assertEqual(await host.receive_bytes(), b"\x03healthy input")

    async def test_full_crew_voice_and_world_packet_budget(self):
        host, guest, hosted, _ = await self.room()
        third, fourth = await self.fill_room(host, hosted)
        seat = self.server.app[RELAY_KEY].rooms[hosted["code"]].seats["host"]
        self.assertGreaterEqual(seat.connection.packets.rate, 540)
        self.assertEqual(seat.connection.packets.capacity, 1280)
        for peer in self.server.app[RELAY_KEY].others(seat):
            self.assertEqual(peer.connection.packets.rate, 160)

        async def collect(peer):
            for _ in range(9):
                self.assertEqual(await peer.receive_bytes(), b"\x01voice-or-world")

        # 2700 routed packets across a live host reconnection. The old160/s
        # host budget exhausted its320-packet burst in less than one second.
        await self.command(host, "status", started=True)
        for peer in (host, guest, third, fourth):
            await self.receive(peer, "status")
        for phase in range(2):
            if phase:
                await host.close()
                for peer in (guest, third, fourth):
                    await self.receive(peer, "peer_left")
                host = await self.connect()
                await self.command(host, "resume", token=hosted["resume_token"])
                await self.receive(host, "resumed")
                for peer in (guest, third, fourth):
                    await self.receive(host, "peer_joined")
                    await self.receive(peer, "peer_joined")
                self.assertEqual(seat.connection.packets.rate, 640)
                self.assertEqual(seat.connection.traffic.rate, 6 * 1024 * 1024)
            for _ in range(50):
                for _ in range(9):
                    for slot in (2, 3, 4):
                        await host.send_bytes(bytes([slot]) + b"voice-or-world")
                await asyncio.wait_for(
                    asyncio.gather(*(collect(peer) for peer in (guest, third, fourth))),
                    2,
                )
                await asyncio.sleep(0.05)
            self.assertFalse(host.closed)

    async def test_guest_does_not_receive_host_packet_budget(self):
        server = await self.start_server(packets_per_second=0, packet_burst=1)
        host, guest, hosted, _ = await self.room(server)
        room = server.app[RELAY_KEY].rooms[hosted["code"]]
        self.assertEqual(room.seats["host"].connection.packets.capacity, 4)
        self.assertEqual(room.seats["guest"].connection.packets.capacity, 1)
        await guest.send_bytes(b"\x01allowed")
        self.assertEqual(await host.receive_bytes(), b"\x02allowed")
        await guest.send_bytes(b"\x01over budget")
        self.assertEqual((await self.receive(guest, "error"))["code"], "rate_limited")
        self.assertEqual((await guest.receive()).type, WSMsgType.CLOSE)

    async def test_host_join_bidirectional_opaque_packets_and_status(self):
        host, guest, hosted, joined = await self.room()
        self.assertEqual(len(hosted["code"]), 6)
        self.assertTrue(all(char in CODE_ALPHABET for char in hosted["code"]))
        self.assertGreaterEqual(len(hosted["resume_token"]), 22)
        self.assertNotEqual(hosted["resume_token"], joined["resume_token"])
        payload = b"\x00\xff\xfe" + bytes(range(256)) * 500
        await host.send_bytes(b"\x02" + payload)
        self.assertEqual(
            await asyncio.wait_for(guest.receive_bytes(), 2), b"\x01" + payload
        )
        await guest.send_bytes(b"\x01\x00guest_input\xff")
        self.assertEqual(
            await asyncio.wait_for(host.receive_bytes(), 2), b"\x02\x00guest_input\xff"
        )
        await self.command(host, "status", started=True)
        self.assertTrue((await self.receive(host, "status"))["started"])
        self.assertTrue((await self.receive(guest, "status"))["started"])
        await self.command(host, "ping", id="latency-7")
        self.assertEqual((await self.receive(host, "pong"))["id"], "latency-7")

    async def test_versions_invalid_codes_malformed_and_unknown_operations(self):
        client = await self.connect()
        for payload in (
            {"op": "host", "version": 2, "build": GAME_BUILD},
            {"op": "host", "version": True, "build": GAME_BUILD},
            {"op": "host", "version": 1, "build": "wrong-build"},
        ):
            await client.send_json(payload)
            self.assertEqual(
                (await self.receive(client, "error"))["code"], "version_mismatch"
            )
        for code, expected in (
            ("a", "invalid_code"),
            ("123456", "invalid_code"),
            ("ABCDEF", "room_not_found"),
            ({}, "invalid_code"),
        ):
            await self.command(client, "join", code=code)
            self.assertEqual((await self.receive(client, "error"))["code"], expected)
        for value in ("[", "[]", "null", '{"op": "anything"}', '{"op": []}'):
            await client.send_str(value)
            self.assertEqual((await self.receive(client, "error"))["op"], "error")
        await self.command(client, "host", name="\ninvalid")
        self.assertEqual((await self.receive(client, "error"))["code"], "invalid_name")
        await self.command(client, "host", name="A" * 25)
        self.assertEqual((await self.receive(client, "error"))["code"], "invalid_name")
        await client.send_bytes(b"not in a room")
        self.assertEqual((await self.receive(client, "error"))["code"], "not_in_room")

    async def test_full_room_role_authority_and_code_normalization(self):
        host, guest, hosted, _ = await self.room()
        await self.fill_room(host, hosted)
        third = await self.connect()
        await self.command(third, "join", code=hosted["code"].lower())
        self.assertEqual((await self.receive(third, "error"))["code"], "room_full")
        await self.command(guest, "status", started=True)
        self.assertEqual((await self.receive(guest, "error"))["code"], "host_only")
        await self.command(host, "status", started="true")
        self.assertEqual((await self.receive(host, "error"))["code"], "invalid_request")
        await self.command(host, "host")
        self.assertEqual((await self.receive(host, "error"))["code"], "already_in_room")
        await self.command(guest, "leave")
        self.assertEqual((await self.receive(host, "peer_left"))["reason"], "left")
        await self.receive(guest, "left")
        code = hosted["code"]
        await self.command(
            third, "join", code=f" {code[:3].lower()}-{code[3:].lower()} "
        )
        self.assertEqual((await self.receive(third, "joined"))["code"], code)

    async def test_join_started_room_reports_current_status(self):
        host = await self.connect()
        await self.command(host, "host")
        hosted = await self.receive(host, "hosted")
        await self.command(host, "status", started=True)
        await self.receive(host, "status")
        guest = await self.connect()
        await self.command(guest, "join", code=hosted["code"])
        self.assertTrue((await self.receive(guest, "joined"))["started"])

    async def test_host_kick_frees_guest_slot_and_revokes_resume_token(self):
        host, guest, hosted, joined = await self.room()
        await self.command(guest, "kick")
        self.assertEqual((await self.receive(guest, "error"))["code"], "host_only")
        await self.command(host, "kick")
        self.assertEqual(
            (await self.receive(guest, "room_closed"))["reason"], "host_rejected"
        )
        self.assertEqual(
            (await self.receive(host, "peer_left"))["reason"], "host_rejected"
        )
        await self.receive(host, "kicked")
        self.assertEqual(len(self.server.app[RELAY_KEY].tokens), 1)
        await self.command(guest, "resume", token=joined["resume_token"])
        self.assertEqual((await self.receive(guest, "error"))["code"], "resume_expired")
        replacement = await self.connect()
        await self.command(replacement, "join", code=hosted["code"])
        await self.receive(replacement, "joined")
        await self.receive(host, "peer_joined")
        await self.receive(replacement, "peer_joined")
        await replacement.send_bytes(b"\x01replacement input")
        self.assertEqual(await host.receive_bytes(), b"\x02replacement input")

    async def test_guest_resume_token_rotation_and_occupied_seat(self):
        host, guest, hosted, joined = await self.room()
        await self.fill_room(host, hosted)
        intruder = await self.connect()
        await self.command(intruder, "resume", token=joined["resume_token"])
        self.assertEqual(
            (await self.receive(intruder, "error"))["code"], "already_connected"
        )
        await guest.close()
        left = await self.receive(host, "peer_left")
        self.assertEqual(left["reconnect_seconds"], 30)
        await self.command(intruder, "join", code=hosted["code"])
        self.assertEqual((await self.receive(intruder, "error"))["code"], "room_full")
        reconnected = await self.connect()
        await self.command(reconnected, "resume", token=joined["resume_token"])
        resumed = await self.receive(reconnected, "resumed")
        self.assertEqual(resumed["role"], "guest")
        self.assertNotEqual(resumed["resume_token"], joined["resume_token"])
        self.assertTrue((await self.receive(host, "peer_joined"))["resumed"])
        await self.receive(reconnected, "peer_joined")
        await self.command(intruder, "resume", token=joined["resume_token"])
        self.assertEqual(
            (await self.receive(intruder, "error"))["code"], "resume_expired"
        )
        await reconnected.send_bytes(b"\x01resumed")
        self.assertEqual(await host.receive_bytes(), b"\x02resumed")

    async def test_host_resume_preserves_code_and_started_flag(self):
        host, guest, hosted, _ = await self.room()
        await self.command(host, "status", started=True)
        await self.receive(host, "status")
        await self.receive(guest, "status")
        await host.close()
        self.assertEqual((await self.receive(guest, "peer_left"))["role"], "host")
        resumed_host = await self.connect()
        await self.command(resumed_host, "resume", token=hosted["resume_token"])
        resumed = await self.receive(resumed_host, "resumed")
        self.assertEqual(resumed["code"], hosted["code"])
        self.assertTrue(resumed["started"])
        host_link = (
            self.server.app[RELAY_KEY].rooms[hosted["code"]].seats["host"].connection
        )
        self.assertEqual(host_link.packets.rate, 640)
        self.assertEqual(host_link.traffic.rate, 6 * 1024 * 1024)
        self.assertTrue(resumed["peer_connected"])

    async def test_host_expiration_closes_room_and_invalidates_tokens(self):
        server = await self.start_server(grace_seconds=0.12)
        host, guest, hosted, joined = await self.room(server)
        await host.close()
        await self.receive(guest, "peer_left")
        self.assertEqual(
            (await self.receive(guest, "room_closed"))["reason"], "host_timeout"
        )
        relay = server.app[RELAY_KEY]
        self.assertEqual(len(relay.rooms), 0)
        self.assertEqual(len(relay.tokens), 0)
        await self.command(guest, "resume", token=joined["resume_token"])
        self.assertEqual((await self.receive(guest, "error"))["code"], "resume_expired")
        await self.command(guest, "join", code=hosted["code"])
        self.assertEqual((await self.receive(guest, "error"))["code"], "room_not_found")

    async def test_guest_expiration_reopens_slot(self):
        server = await self.start_server(grace_seconds=0.12)
        host, guest, hosted, _ = await self.room(server)
        await guest.close()
        await self.receive(host, "peer_left")
        self.assertEqual((await self.receive(host, "peer_left"))["reason"], "timeout")
        replacement = await self.connect(server)
        await self.command(replacement, "join", code=hosted["code"])
        await self.receive(replacement, "joined")
        self.assertEqual(len(server.app[RELAY_KEY].tokens), 2)

    async def test_explicit_host_leave_frees_room_immediately(self):
        host, guest, _, _ = await self.room()
        await self.command(host, "leave")
        self.assertEqual(
            (await self.receive(host, "room_closed"))["reason"], "host_left"
        )
        await self.receive(host, "left")
        await self.receive(guest, "room_closed")
        self.assertFalse(self.server.app[RELAY_KEY].rooms)
        self.assertFalse(self.server.app[RELAY_KEY].tokens)
        await self.command(guest, "host")
        await self.receive(guest, "hosted")

    async def test_control_rate_limit(self):
        server = await self.start_server(controls_per_second=0, control_burst=2)
        client = await self.connect(server)
        for i in range(2):
            await self.command(client, "ping", id=i)
            await self.receive(client, "pong")
        await self.command(client, "ping", id=3)
        self.assertEqual((await self.receive(client, "error"))["code"], "rate_limited")
        self.assertEqual((await client.receive()).type, WSMsgType.CLOSE)
        self.assertEqual(client.close_code, 1008)

    async def test_packet_and_byte_rate_limits(self):
        for limits in (
            {"packets_per_second": 0, "packet_burst": 1},
            {"bytes_per_second": 0, "byte_burst": 2},
        ):
            server = await self.start_server(**limits)
            host, guest, _, _ = await self.room(server)
            for _ in range(4 if "packets_per_second" in limits else 1):
                await host.send_bytes(b"\x0212345")
                self.assertEqual(await guest.receive_bytes(), b"\x0112345")
            await host.send_bytes(b"\x02x")
            self.assertEqual(
                (await self.receive(host, "error"))["code"], "rate_limited"
            )
            self.assertEqual((await host.receive()).type, WSMsgType.CLOSE)

    async def test_binary_and_control_size_limits(self):
        for payload in (b"a" * (MAX_PACKET_BYTES + 2), "a" * 4097):
            client = await self.connect()
            if isinstance(payload, bytes):
                await client.send_bytes(payload)
            else:
                await client.send_str(payload)
            self.assertEqual(
                (await asyncio.wait_for(client.receive(), 2)).type, WSMsgType.CLOSE
            )
            self.assertEqual(client.close_code, 1009)

    async def test_origins_and_health_do_not_disclose_rooms(self):
        with self.assertRaises(WSServerHandshakeError) as error:
            await self.connect(origin="https://untrusted.example")
        self.assertEqual(error.exception.status, 403)
        server = await self.start_server(
            allowed_origins=frozenset({"https://game.example"})
        )
        client = await self.connect(server, origin="https://game.example")
        await self.command(client, "host")
        hosted = await self.receive(client, "hosted")
        async with self.clients.get(server.make_url("/healthz")) as response:
            data = await response.json()
            self.assertEqual(data["status"], "ok")
            self.assertNotIn(hosted["code"], str(data))
            self.assertNotIn(hosted["resume_token"], str(data))

    async def test_room_capacity_and_idle_cleanup(self):
        server = await self.start_server(
            max_rooms=1, idle_seconds=0.1, grace_seconds=0.08
        )
        first = await self.connect(server)
        await self.command(first, "host")
        await self.receive(first, "hosted")
        second = await self.connect(server)
        await self.command(second, "host")
        self.assertEqual((await self.receive(second, "error"))["code"], "server_full")
        self.assertEqual((await self.receive(second, "error"))["code"], "idle_timeout")
        self.assertEqual((await second.receive()).type, WSMsgType.CLOSE)
        await first.close()
        await asyncio.sleep(0.15)
        self.assertFalse(server.app[RELAY_KEY].rooms)
        self.assertFalse(server.app[RELAY_KEY].tokens)

    async def test_duplicate_nonfinite_and_extra_control_fields_are_rejected(self):
        client = await self.connect()
        for raw in (
            '{"op":"ping","op":"host"}',
            '{"op":"ping","id":NaN}',
            '{"op":"ping","id":Infinity}',
            '{"op":"ping","method":"host"}',
        ):
            await client.send_str(raw)
            self.assertEqual(
                (await self.receive(client, "error"))["code"], "invalid_request"
            )
        self.assertFalse(self.server.app[RELAY_KEY].rooms)
        await self.command(client, "ping", id=2**54)
        self.assertEqual(
            (await self.receive(client, "error"))["code"], "invalid_request"
        )
        await self.command(client, "host", name="Mara\u202erehctartnI")
        self.assertEqual((await self.receive(client, "error"))["code"], "invalid_name")

    async def test_guess_budget_survives_new_sockets_and_spoofed_forwarding(self):
        server = await self.start_server(attempts_per_second=0, attempt_burst=2)
        for index in range(2):
            client = await self.connect(
                server, headers={"X-Forwarded-For": f"198.51.100.{index + 1}"}
            )
            await self.command(client, "join", code="ABCDEF")
            self.assertEqual(
                (await self.receive(client, "error"))["code"], "room_not_found"
            )
            await client.close()
        client = await self.connect(server, headers={"X-Forwarded-For": "203.0.113.90"})
        await self.command(client, "resume", token="unknown")
        self.assertEqual((await self.receive(client, "error"))["code"], "rate_limited")
        self.assertEqual((await client.receive()).type, WSMsgType.CLOSE)
        self.assertEqual(client.close_code, 1008)
        self.assertEqual(len(server.app[RELAY_KEY].addresses), 1)

    async def test_empty_null_and_duplicate_origins_do_not_bypass_allowlist(self):
        server = await self.start_server(
            allowed_origins=frozenset({"https://game.example"})
        )
        for headers in (
            [("Origin", "")],
            [("Origin", "null")],
            [("Origin", "https://game.example"), ("Origin", "https://evil.example")],
        ):
            with self.assertRaises(WSServerHandshakeError) as error:
                await self.connect(server, headers=headers)
            self.assertEqual(error.exception.status, 403)
        self.assertFalse(server.app[RELAY_KEY].connections)

    async def test_handshake_budget_and_pending_capacity_are_strict(self):
        server = await self.start_server(max_connections=2)
        results = await asyncio.gather(
            *(self.connect(server) for _ in range(8)), return_exceptions=True
        )
        successes = [value for value in results if not isinstance(value, Exception)]
        self.assertEqual(len(successes), 2)
        self.assertEqual(server.app[RELAY_KEY].pending, 0)
        self.assertEqual(len(server.app[RELAY_KEY].connections), 2)
        limited = await self.start_server(handshakes_per_second=0, handshake_burst=1)
        client = await self.connect(limited)
        await client.close()
        with self.assertRaises(WSServerHandshakeError) as error:
            await self.connect(limited)
        self.assertEqual(error.exception.status, 429)

    async def test_failed_handshake_releases_reservation(self):
        async with self.clients.get(self.server.make_url("/ws")) as response:
            self.assertEqual(response.status, 400)
        relay = self.server.app[RELAY_KEY]
        self.assertEqual(relay.pending, 0)
        self.assertTrue(
            all(
                not budget.pending and not budget.active
                for budget in relay.addresses.values()
            )
        )
        await self.connect()

    async def test_native_control_frames_share_control_limit(self):
        server = await self.start_server(controls_per_second=0, control_burst=2)
        client = await self.connect(server)
        for _ in range(3):
            await client.ping(b"probe")
        self.assertEqual(
            (await asyncio.wait_for(client.receive(), 2)).type, WSMsgType.CLOSE
        )
        self.assertEqual(client.close_code, 1008)

    async def test_trusted_proxy_budget_uses_last_untrusted_hop_and_is_bounded(self):
        server = await self.start_server(
            trusted_proxies=("127.0.0.1/32",), max_addresses=2
        )
        await self.connect(
            server, headers={"X-Forwarded-For": "192.0.2.123, 198.51.100.1"}
        )
        await self.connect(
            server, headers={"X-Forwarded-For": "192.0.2.124, 198.51.100.2"}
        )
        self.assertEqual(
            set(server.app[RELAY_KEY].addresses), {"198.51.100.1", "198.51.100.2"}
        )
        with self.assertRaises(WSServerHandshakeError) as error:
            await self.connect(server, headers={"X-Forwarded-For": "198.51.100.3"})
        self.assertEqual(error.exception.status, 503)
        self.assertEqual(len(server.app[RELAY_KEY].addresses), 2)

    async def test_address_budget_is_reaped_only_after_idle_ttl(self):
        server = await self.start_server(address_idle_seconds=0.03)
        client = await self.connect(server)
        await asyncio.sleep(0.04)
        relay = server.app[RELAY_KEY]
        relay.expire_addresses()
        self.assertEqual(len(relay.addresses), 1)
        await client.close()
        await asyncio.sleep(0.04)
        relay.expire_addresses()
        self.assertFalse(relay.addresses)

    async def test_ipv6_privacy_addresses_share_admission_budget(self):
        server = await self.start_server(
            trusted_proxies=("127.0.0.1/32",), attempts_per_second=0, attempt_burst=1
        )
        first = await self.connect(server, headers={"X-Forwarded-For": "2001:db8:1::1"})
        await self.command(first, "join", code="ABCDEF")
        await self.receive(first, "error")
        second = await self.connect(
            server, headers={"X-Forwarded-For": "2001:db8:1::ffff"}
        )
        await self.command(second, "join", code="ABCDEF")
        self.assertEqual((await self.receive(second, "error"))["code"], "rate_limited")
        self.assertEqual(set(server.app[RELAY_KEY].addresses), {"2001:db8:1::/64"})

    async def test_invalid_origin_configuration_fails_closed(self):
        for origin in (
            "*",
            "null",
            "",
            "https://game.example/path",
            "https://user@game.example",
        ):
            with self.assertRaises(ValueError):
                create_app(
                    dataclasses.replace(Settings(), allowed_origins=frozenset({origin}))
                )

    async def test_resume_accepts_actual_godot_control_shape(self):
        host, guest, _, joined = await self.room()
        await guest.close()
        await self.receive(host, "peer_left")
        replacement = await self.connect()
        await self.command(
            replacement, "resume", token=joined["resume_token"], name="Partner"
        )
        self.assertEqual((await self.receive(replacement, "resumed"))["role"], "guest")

    async def test_slow_recipient_send_is_bounded(self):
        server = await self.start_server(send_timeout=0.03)
        host, guest, hosted, _ = await self.room(server)
        connection = (
            server.app[RELAY_KEY].rooms[hosted["code"]].seats["guest"].connection
        )

        async def blocked(_data, **_kwargs):
            await asyncio.Event().wait()

        connection.socket.send_bytes = blocked
        await host.send_bytes(b"\x02slow consumer")
        self.assertEqual(
            (await asyncio.wait_for(guest.receive(), 0.5)).type, WSMsgType.CLOSE
        )
        self.assertEqual(guest.close_code, 1013)


if __name__ == "__main__":
    unittest.main(verbosity=2)
