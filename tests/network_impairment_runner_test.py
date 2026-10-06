#!/usr/bin/env python3
"""Fault decisions, actual forwarding, queue limits and all-peer cleanup."""
from __future__ import annotations

import asyncio
from pathlib import Path
import subprocess
import socket
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import verify_network_impairment as faults
from network_stream_fault_proxy import StreamFaultProxy


class PolicyTests(unittest.TestCase):
    def test_seed_reproduces_loss_and_jitter(self):
        first = faults.FaultPolicy(123, 75, 15, .01)
        second = faults.FaultPolicy(123, 75, 15, .01)
        self.assertEqual([first.schedule(10, 1200) for _ in range(1000)],
                         [second.schedule(10, 1200) for _ in range(1000)])
        self.assertEqual(first.stats, second.stats)
        self.assertGreater(first.stats["random_dropped_packets"], 0)

    def test_jitter_stays_inside_real_one_way_bounds(self):
        policy = faults.FaultPolicy(44, 75, 15, 0)
        for _ in range(1000):
            at = policy.schedule(10, 900)
            self.assertGreaterEqual(at, 10.060)
            self.assertLessEqual(at, 10.090)
        self.assertEqual(policy.stats["received_packets"], 1000)
        self.assertEqual(policy.stats["received_bytes"], 900000)

    def test_outage_restores_at_exact_boundary(self):
        policy = faults.FaultPolicy(44, 0, 0, 0)
        policy.blocked_until = 5
        self.assertIsNone(policy.schedule(4.999, 100))
        self.assertEqual(policy.schedule(5, 100), 5)
        self.assertEqual(policy.stats["outage_dropped_packets"], 1)

    def test_invalid_or_nonfinite_profiles_are_rejected(self):
        for delay, jitter, loss in [(-1, 0, 0), (75, 76, 0), (75, -1, 0), (75, 0, -1), (75, 0, 1.1),
                                    (float("nan"), 0, 0), (75, float("inf"), 0), (75, 0, float("nan"))]:
            with self.subTest(profile=(delay, jitter, loss)), self.assertRaises(ValueError):
                faults.FaultPolicy(1, delay, jitter, loss)

    def test_packet_and_byte_queue_caps_are_enforced(self):
        proxy = faults.FaultProxy(2, 1, 75, 15, 0)
        for _ in range(proxy.MAX_PACKETS + 30):
            proxy.receive("up", b"a", ("127.0.0.1", 33333))
        self.assertEqual(len(proxy.queue), proxy.MAX_PACKETS)
        self.assertEqual(proxy.policies["up"].stats["queue_limit_dropped_packets"], 30)
        byte_proxy = faults.FaultProxy(2, 1, 75, 15, 0)
        for _ in range(30):
            byte_proxy.receive("up", b"a" * (256 * 1024), ("127.0.0.1", 33333))
        self.assertEqual(byte_proxy.queued_bytes, byte_proxy.MAX_BYTES)
        self.assertEqual(len(byte_proxy.queue), 16)
        self.assertEqual(byte_proxy.policies["up"].stats["queue_limit_dropped_packets"], 14)

    def test_foreign_source_is_never_forwarded(self):
        proxy = faults.FaultProxy(2, 1, 75, 15, 0)
        proxy.receive("up", b"other", ("203.0.113.44", 33333))
        self.assertIsNone(proxy.client_address)
        self.assertEqual(len(proxy.queue), 0)
        self.assertEqual(proxy.policies["up"].stats["foreign_source_dropped_packets"], 1)

    def test_all_own_groups_retired_after_a_wait_timeout(self):
        class Peer:
            def __init__(self, pid, broken=False):
                self.pid, self.broken, self.waited = pid, broken, False
            def poll(self): return None
            def wait(self, timeout):
                self.waited = True
                if self.broken: raise subprocess.TimeoutExpired("peer", timeout)
                return 0
        peers = [Peer(101, True), Peer(102), Peer(103), Peer(104)]
        with patch.object(faults.os, "killpg") as kill, patch.object(faults.stability, "live_process_group_members", return_value=[]):
            errors, leftovers = faults.retire_all(peers)
        self.assertEqual([call.args[0] for call in kill.call_args_list], [101, 102, 103, 104])
        self.assertTrue(all(peer.waited for peer in peers))
        self.assertEqual(len(errors), 1)
        self.assertEqual(leftovers, [])


class ProxyTests(unittest.IsolatedAsyncioTestCase):
    async def test_active_udp_destination_failure_is_preserved(self):
        # Reserve and release an isolated localhost port; sending to it must
        # produce a real ICMP error, which remains a failed proxy diagnostic.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            unused_port = reservation.getsockname()[1]
        proxy = faults.FaultProxy(2, 1, 0, 0, 0)
        try:
            await proxy.open(0, unused_port)
            proxy.receive("up", b"active-destination-failure", ("127.0.0.1", 33333))
            deadline = asyncio.get_running_loop().time() + 1
            while not proxy.errors and asyncio.get_running_loop().time() < deadline:
                await asyncio.sleep(.005)
            self.assertTrue(proxy.errors)
            error = proxy.report()["errors"][0]
            self.assertEqual(error["direction"], "down")
            self.assertIn("ConnectionRefusedError", error["error"])
            self.assertFalse(error["proxy_closed"])
            self.assertGreater(error["monotonic"], 0)
        finally:
            await proxy.close()

    async def test_tcp_blackout_preserves_exact_bytes_order_and_recovery(self):
        async def echo(reader, writer):
            try:
                while chunk := await reader.read(16384):
                    writer.write(chunk)
                    await writer.drain()
            finally:
                writer.close()
                await writer.wait_closed()
        server = await asyncio.start_server(echo, "127.0.0.1", 0)
        proxy = StreamFaultProxy(3, 77, 5, 3)
        writer = None
        try:
            await proxy.open(0, server.sockets[0].getsockname()[1])
            port = proxy.server.sockets[0].getsockname()[1]
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            payload = bytes(range(256)) * 100
            proxy.outage(.1, "unit-byte-preserving-cut")
            writer.write(payload[:12345])
            await writer.drain()
            writer.write(payload[12345:])
            await writer.drain()
            with self.assertRaises(asyncio.TimeoutError):
                await asyncio.wait_for(reader.read(1), .04)
            self.assertEqual(await asyncio.wait_for(reader.readexactly(len(payload)), 1), payload)
            writer.write(b"after-blackout")
            await writer.drain()
            self.assertEqual(await asyncio.wait_for(reader.readexactly(14), 1), b"after-blackout")
            report = proxy.report()
            self.assertFalse(report["individual_byte_loss"])
            for stats in report["directions"].values():
                self.assertLessEqual(stats["max_queued_chunks"], proxy.MAX_QUEUE_CHUNKS)
                self.assertLessEqual(stats["max_buffered_bytes"], proxy.MAX_DIRECTION_BYTES)
            self.assertEqual(report["errors"], [])
        finally:
            if writer:
                writer.close()
                await writer.wait_closed()
            await proxy.close()
            server.close()
            await server.wait_closed()

    async def test_tcp_backpressure_caps_forwarding_buffers(self):
        async def sink(reader, writer):
            try:
                while await reader.read(16384): pass
            finally:
                writer.close()
                await writer.wait_closed()
        server = await asyncio.start_server(sink, "127.0.0.1", 0)
        proxy = StreamFaultProxy(3, 77, 0, 0)
        writer = None
        try:
            await proxy.open(0, server.sockets[0].getsockname()[1])
            reader, writer = await asyncio.open_connection("127.0.0.1", proxy.server.sockets[0].getsockname()[1])
            proxy.outage(10, "bounded-backpressure")
            writer.write(b"q" * (2 * 1024 * 1024))
            await writer.drain()
            await asyncio.sleep(.05)
            stats = proxy.report()["directions"]["up"]
            self.assertEqual(stats["max_queued_chunks"], proxy.MAX_QUEUE_CHUNKS)
            self.assertLessEqual(stats["max_buffered_bytes"], proxy.MAX_DIRECTION_BYTES)
            self.assertEqual(stats["bytes_forwarded"], 0)
        finally:
            await proxy.close()
            if writer:
                writer.close()
                try: await asyncio.wait_for(writer.wait_closed(), 1)
                except (ConnectionError, asyncio.TimeoutError): writer.transport.abort()
            server.close()
            await server.wait_closed()

    async def test_actual_udp_forwarding_cut_and_recovery(self):
        class Echo(asyncio.DatagramProtocol):
            def connection_made(self, transport): self.transport = transport
            def datagram_received(self, data, address): self.transport.sendto(data, address)
        class Client(asyncio.DatagramProtocol):
            def __init__(self): self.received = asyncio.Queue()
            def datagram_received(self, data, address): self.received.put_nowait(data)
        loop = asyncio.get_running_loop()
        echo, _ = await loop.create_datagram_endpoint(Echo, local_addr=("127.0.0.1", 0))
        proxy = faults.FaultProxy(2, 1, 5, 0, 0)
        client = Client()
        transport = None
        try:
            await proxy.open(0, echo.get_extra_info("sockname")[1])
            port = proxy.listener.get_extra_info("sockname")[1]
            transport, _ = await loop.create_datagram_endpoint(lambda: client, remote_addr=("127.0.0.1", port))
            transport.sendto(b"native-udp-before-cut")
            self.assertEqual(await asyncio.wait_for(client.received.get(), 1), b"native-udp-before-cut")
            proxy.outage(.10, "unit-cut")
            transport.sendto(b"dropped")
            with self.assertRaises(asyncio.TimeoutError):
                await asyncio.wait_for(client.received.get(), .13)
            transport.sendto(b"native-udp-after-cut")
            self.assertEqual(await asyncio.wait_for(client.received.get(), 1), b"native-udp-after-cut")
            self.assertGreaterEqual(proxy.policies["up"].stats["outage_dropped_packets"], 1)
            self.assertEqual(proxy.policies["down"].stats["forwarded_packets"], 2)
        finally:
            await proxy.close()
            if transport: transport.close()
            echo.close()
        self.assertEqual(proxy.queue, [])
        self.assertEqual(proxy.queued_bytes, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
