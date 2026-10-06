#!/usr/bin/env python3
"""Opaque TCP FIFO delays/backpressure; never drops individual stream bytes."""
from __future__ import annotations

import asyncio
import math
import random
import time


class StreamFaultProxy:
    CHUNK_BYTES = 16384
    MAX_QUEUE_CHUNKS = 64
    # One sender chunk and one producer chunk waiting for a slot may be
    # outside the bounded queue. Native socket buffers are separate.
    MAX_DIRECTION_BYTES = (MAX_QUEUE_CHUNKS + 2) * CHUNK_BYTES

    def __init__(self, slot: int, seed: int, delay_ms: float, jitter_ms: float):
        if not (math.isfinite(delay_ms) and math.isfinite(jitter_ms) and 0 <= jitter_ms <= delay_ms):
            raise ValueError("Require finite 0 <= jitter <= delay")
        self.slot, self.delay, self.jitter = slot, delay_ms / 1000, jitter_ms / 1000
        self.random = {direction: random.Random(seed + slot * 1009 + index * 65537)
                       for index, direction in enumerate(("up", "down"))}
        self.stats = {direction: {"bytes_read": 0, "bytes_forwarded": 0, "chunks_read": 0,
                                 "max_queued_chunks": 0, "max_buffered_bytes": 0} for direction in ("up", "down")}
        self.blocked_until = 0.0
        self.events, self.errors = [], []
        self.server = None
        self.connections = 0
        self.connection_resets = 0
        self.handlers = set()
        self.closed = False
        self.host_port = 0

    async def open(self, port: int, host_port: int):
        self.host_port = host_port
        self.server = await asyncio.start_server(self.handle, "127.0.0.1", port, limit=self.CHUNK_BYTES * 2)

    async def handle(self, client_reader, client_writer):
        handler = asyncio.current_task()
        self.handlers.add(handler)
        self.connections += 1
        relay_writer = None
        pumps = []
        try:
            relay_reader, relay_writer = await asyncio.open_connection("127.0.0.1", self.host_port, limit=self.CHUNK_BYTES * 2)
            pumps = [asyncio.create_task(self.pump(client_reader, relay_writer, "up")),
                     asyncio.create_task(self.pump(relay_reader, client_writer, "down"))]
            # EOF on either leg retires that whole old stream. Buffered bytes
            # are never transplanted into a reconnect's new WebSocket session.
            done, _ = await asyncio.wait(pumps, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        except (ConnectionResetError, BrokenPipeError):
            # A game closing its old WebSocket on timeout is the expected
            # recovery path, not a proxy infrastructure failure.
            self.connection_resets += 1
        except (ConnectionError, OSError) as error:
            if not self.closed:
                self.errors.append(type(error).__name__ + ": " + str(error))
        finally:
            for task in pumps:
                task.cancel()
            if pumps:
                await asyncio.gather(*pumps, return_exceptions=True)
            for writer in (client_writer, relay_writer):
                if writer is not None:
                    writer.close()
                    if self.closed:
                        writer.transport.abort()
                    try:
                        await asyncio.wait_for(writer.wait_closed(), 1)
                    except (ConnectionError, OSError, asyncio.TimeoutError):
                        writer.transport.abort()
            self.handlers.discard(handler)

    async def pump(self, reader, writer, direction: str):
        queue = asyncio.Queue(maxsize=self.MAX_QUEUE_CHUNKS)
        stats = self.stats[direction]
        buffered = 0

        async def receive():
            nonlocal buffered
            previous_delivery = 0.0
            while not self.closed:
                chunk = await reader.read(self.CHUNK_BYTES)
                if not chunk:
                    return
                at = max(previous_delivery, time.monotonic() + self.delay + self.random[direction].uniform(-self.jitter, self.jitter))
                previous_delivery = at
                # Waiting for a queue slot creates ordinary TCP backpressure.
                buffered += len(chunk)
                stats["max_buffered_bytes"] = max(stats["max_buffered_bytes"], buffered)
                await queue.put((at, chunk))
                stats["bytes_read"] += len(chunk)
                stats["chunks_read"] += 1
                stats["max_queued_chunks"] = max(stats["max_queued_chunks"], queue.qsize())

        async def forward():
            nonlocal buffered
            while not self.closed:
                at, chunk = await queue.get()
                # Recheck the blackout after every await. Preserving every
                # byte and FIFO order is essential for WebSocket and TLS.
                while True:
                    wait = max(at, self.blocked_until) - time.monotonic()
                    if wait <= 0:
                        break
                    await asyncio.sleep(min(wait, .05))
                writer.write(chunk)
                await writer.drain()
                buffered -= len(chunk)
                stats["bytes_forwarded"] += len(chunk)
                queue.task_done()

        tasks = [asyncio.create_task(receive()), asyncio.create_task(forward())]
        try:
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    def outage(self, seconds: float, label: str):
        if not math.isfinite(seconds) or seconds < 0:
            raise ValueError("Outage must be finite and nonnegative")
        now = time.monotonic()
        self.blocked_until = now + seconds
        self.events.append({"label": label, "started_monotonic": now, "duration_seconds": seconds})

    def report(self):
        return {"slot": self.slot, "transport": "opaque FIFO TCP stream", "connections": self.connections,
                "connection_resets": self.connection_resets,
                "individual_byte_loss": False, "queue_chunk_limit_per_direction": self.MAX_QUEUE_CHUNKS,
                "buffer_limit_per_direction_bytes": self.MAX_DIRECTION_BYTES, "directions": self.stats,
                "events": self.events, "errors": self.errors}

    async def close(self):
        self.closed = True
        if self.server is not None:
            self.server.close()
            await self.server.wait_closed()
        tasks = list(self.handlers)
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
