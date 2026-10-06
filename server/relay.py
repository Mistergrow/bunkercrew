#!/usr/bin/env python3
"""Four-player, opaque WebSocket relay for Bunkercrew.

Only room control is JSON. Game packets remain opaque bytes; this process never
deserializes them and never grants guests authority over the simulation.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import ipaddress
import logging
import os
import secrets
import time
import unicodedata
from urllib.parse import urlsplit
from dataclasses import dataclass, field

from aiohttp import WSMsgType, web
if __package__:
    from .social import SOCIAL_KEY, SocialService, default_database
else:
    try:
        from social import SOCIAL_KEY, SocialService, default_database
    except ModuleNotFoundError as error:
        if error.name != "social":
            raise
        from server.social import SOCIAL_KEY, SocialService, default_database


PROTOCOL_VERSION = 1
GAME_BUILD = "bunkercrew-net-20"
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
MAX_PACKET_BYTES = 512 * 1024
MAX_WIRE_BYTES = MAX_PACKET_BYTES + 1  # Authenticated routing envelope.
LOGGER = logging.getLogger("lastshift.relay")


@dataclass(frozen=True)
class Settings:
    # Explicit Settings() instances used by tests are isolated in memory.
    # Production entry points use from_env() and durable user-data storage.
    social_db: str | None = None
    grace_seconds: float = 30.0
    idle_seconds: float = 20.0
    max_rooms: int = 256
    max_connections: int = 768
    # Sustained game traffic has ample room above the expected 150 KiB/s.
    bytes_per_second: float = 2 * 1024 * 1024
    byte_burst: float = 4 * 1024 * 1024
    # Includes up to 50 microphone frames plus snapshots, inputs and effects.
    packets_per_second: float = 160.0
    packet_burst: float = 320.0
    controls_per_second: float = 12.0
    control_burst: float = 32.0
    send_timeout: float = 2.0
    allowed_origins: frozenset[str] = frozenset()
    max_connections_per_ip: int = 64
    max_addresses: int = 4096
    address_idle_seconds: float = 600.0
    handshakes_per_second: float = 2.0
    handshake_burst: float = 64.0
    attempts_per_second: float = 0.2
    attempt_burst: float = 16.0
    handshake_timeout: float = 3.0
    trusted_proxies: tuple[str, ...] = ()

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            social_db=os.getenv("SOCIAL_DB") or default_database(),
            max_rooms=max(1, int(os.getenv("RELAY_MAX_ROOMS", "256"))),
            max_connections=max(2, int(os.getenv("RELAY_MAX_CONNECTIONS", "768"))),
            max_connections_per_ip=max(
                2, int(os.getenv("RELAY_MAX_CONNECTIONS_PER_IP", "64"))
            ),
            trusted_proxies=tuple(
                value.strip()
                for value in os.getenv("RELAY_TRUSTED_PROXIES", "").split(",")
                if value.strip()
            ),
            allowed_origins=frozenset(
                origin.strip()
                for origin in os.getenv("RELAY_ALLOWED_ORIGINS", "").split(",")
                if origin.strip()
            ),
        )


class Bucket:
    def __init__(self, rate: float, capacity: float):
        self.rate = rate
        self.capacity = capacity
        self.tokens = capacity
        self.updated = time.monotonic()

    def take(self, amount: float = 1) -> bool:
        now = time.monotonic()
        self.tokens = min(self.capacity, self.tokens + (now - self.updated) * self.rate)
        self.updated = now
        if amount > self.tokens:
            return False
        self.tokens -= amount
        return True


class VoiceGuard:
    """Ignore catch-up bursts; reject threefold excess maintained for two seconds."""
    def __init__(self):
        self.updated = None
        self.count = 0
        self.over_since = None

    def observe(self, now: float, streams: int = 1) -> bool:
        if self.updated is None:
            self.updated = now
        self.count += 1
        elapsed = now - self.updated
        if elapsed < 0.25:
            return True
        if self.count / elapsed > 55 * 3 * streams:
            if self.over_since is None:
                self.over_since = self.updated
        else:
            self.over_since = None
        self.updated = now
        self.count = 0
        return self.over_since is None or now - self.over_since < 2.0


@dataclass(eq=False)
class Connection:
    socket: web.WebSocketResponse
    packets: Bucket
    controls: Bucket
    traffic: Bucket
    seat: "Seat | None" = None
    created: float = field(default_factory=time.monotonic)
    address: str = ""
    outbound: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=64))
    outbound_bytes: int = 0
    sender: asyncio.Task | None = None
    voice: Bucket = field(default_factory=lambda: Bucket(55, 36))
    voice_guard: VoiceGuard = field(default_factory=VoiceGuard)


@dataclass
class AddressBudget:
    handshakes: Bucket
    attempts: Bucket
    active: int = 0
    pending: int = 0
    touched: float = field(default_factory=time.monotonic)


@dataclass(eq=False)
class Seat:
    role: str
    name: str
    token: str
    room: "Room"
    connection: Connection | None
    expires: float = 0.0


@dataclass(eq=False)
class Room:
    code: str
    started: bool = False
    seats: dict[str, Seat] = field(default_factory=dict)


class Relay:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.rooms: dict[str, Room] = {}
        self.tokens: dict[str, Seat] = {}
        self.connections: set[Connection] = set()
        self.stopping = False
        self.sweeper: asyncio.Task | None = None
        self.addresses: dict[str, AddressBudget] = {}
        self.pending = 0
        self.trusted_proxies = tuple(
            ipaddress.ip_network(value, strict=False)
            for value in settings.trusted_proxies
        )
        for origin in settings.allowed_origins:
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in ("http", "https")
                or not parsed.hostname
                or parsed.path
                or parsed.query
                or parsed.fragment
                or parsed.username
                or parsed.password
            ):
                raise ValueError(
                    "RELAY_ALLOWED_ORIGINS must contain exact HTTP(S) origins"
                )

    def address(self, request: web.Request) -> str:
        # Forwarding headers are untrusted unless the actual socket peer is an
        # explicitly configured proxy. Walk right-to-left through proxy hops.
        peer = ipaddress.ip_address(request.remote or "0.0.0.0")
        if any(peer in network for network in self.trusted_proxies):
            forwarded = request.headers.getall("X-Forwarded-For", [])
            if len(forwarded) > 1:
                raise web.HTTPBadRequest(text="Invalid forwarding header")
            hops = forwarded[0].split(",") if forwarded else []
            if len(hops) > 8:
                raise web.HTTPBadRequest(text="Too many proxy hops")
            try:
                for hop in reversed(hops):
                    if not any(peer in network for network in self.trusted_proxies):
                        break
                    peer = ipaddress.ip_address(hop.strip())
            except ValueError as error:
                raise web.HTTPBadRequest(text="Invalid proxy address") from error
        if isinstance(peer, ipaddress.IPv6Address):
            if peer.ipv4_mapped:
                return str(peer.ipv4_mapped)
            if peer.is_loopback:
                return str(peer)
            # IPv6 privacy-address rotation must not reset admission budgets.
            return str(ipaddress.ip_network(f"{peer}/64", strict=False))
        return str(peer)

    def budget(self, address: str) -> AddressBudget:
        if address not in self.addresses:
            self.expire_addresses()
            if len(self.addresses) >= self.settings.max_addresses:
                raise web.HTTPServiceUnavailable(text="Address capacity reached")
            self.addresses[address] = AddressBudget(
                Bucket(
                    self.settings.handshakes_per_second, self.settings.handshake_burst
                ),
                Bucket(self.settings.attempts_per_second, self.settings.attempt_burst),
            )
        result = self.addresses[address]
        result.touched = time.monotonic()
        return result

    def expire_addresses(self) -> None:
        now = time.monotonic()
        for address, budget in list(self.addresses.items()):
            if (
                not budget.active
                and not budget.pending
                and now - budget.touched > self.settings.address_idle_seconds
            ):
                del self.addresses[address]

    async def _drain_outbound(self, connection: Connection) -> None:
        try:
            while not connection.socket.closed:
                payload, size, delivered = await connection.outbound.get()
                try:
                    await asyncio.wait_for(
                        (connection.socket.send_bytes(payload) if isinstance(payload, bytes)
                         else connection.socket.send_json(payload)),
                        timeout=self.settings.send_timeout,
                    )
                    if delivered is not None and not delivered.done():
                        delivered.set_result(True)
                finally:
                    if delivered is not None and not delivered.done():
                        delivered.set_result(False)
                    connection.outbound_bytes -= size
                    connection.outbound.task_done()
        except (OSError, RuntimeError, asyncio.TimeoutError):
            await connection.socket.close(code=1013, message=b"Slow connection")
        except asyncio.CancelledError:
            pass

    async def send(self, connection: Connection | None, payload: dict | bytes,
                   droppable: bool = False) -> bool:
        if connection is None or connection.socket.closed:
            return False
        # A single writer preserves ordering between opaque game packets and
        # relay events, especially a guest's final leave and peer_left.
        size = len(payload) if isinstance(payload, bytes) else len(json.dumps(payload).encode("utf-8"))
        if (connection.outbound.full() or
                connection.outbound_bytes + size > 4 * MAX_PACKET_BYTES):
            if not droppable:
                asyncio.create_task(connection.socket.close(
                    code=1013, message=b"Outbound queue full"))
            return False
        delivered = None if isinstance(payload, bytes) else asyncio.get_running_loop().create_future()
        connection.outbound.put_nowait((payload, size, delivered))
        connection.outbound_bytes += size
        if connection.sender is None or connection.sender.done():
            connection.sender = asyncio.create_task(self._drain_outbound(connection))
        if delivered is None:
            return True
        try:
            # Control callers may close the socket immediately afterwards;
            # wait for delivery, with a bound covering the preceding queue too.
            return await asyncio.wait_for(delivered, timeout=self.settings.send_timeout)
        except (OSError, RuntimeError, asyncio.TimeoutError):
            await connection.socket.close(code=1013, message=b"Slow or unavailable connection")
            return False

    async def error(self, connection: Connection, code: str, message: str) -> None:
        await self.send(connection, {"op": "error", "code": code, "message": message})

    @staticmethod
    def slot(seat: Seat) -> int:
        return {"host": 1, "guest": 2, "guest3": 3, "guest4": 4}[seat.role]

    @staticmethod
    def role(slot: int) -> str:
        return {1: "host", 2: "guest", 3: "guest3", 4: "guest4"}[slot]

    def others(self, seat: Seat) -> list[Seat]:
        if seat.role == "host":
            return [other for other in seat.room.seats.values() if other is not seat]
        host = seat.room.seats.get("host")
        return [host] if host else []

    def other(self, seat: Seat) -> Seat | None:
        return next(iter(self.others(seat)), None)

    def make_seat(
        self, room: Room, role: str, name: str, connection: Connection
    ) -> Seat:
        seat = Seat(role, name, secrets.token_urlsafe(24), room, connection)
        room.seats[role] = seat
        self.tokens[seat.token] = seat
        connection.seat = seat
        self.configure_game_budgets(connection, role)
        return seat

    def configure_game_budgets(self, connection: Connection, role: str) -> None:
        # Host fanout: 3 guests * (3 incoming voices * 50Hz + 20Hz world)
        # is 510 packets/s before effects. A reconnect must retain this budget.
        packets = 4 if role == "host" else 1
        traffic = 3 if role == "host" else 1
        connection.voice = Bucket(55 * (9 if role == "host" else 1), 36 * (9 if role == "host" else 1))
        connection.voice_guard = VoiceGuard()
        connection.packets = Bucket(
            self.settings.packets_per_second * packets,
            self.settings.packet_burst * packets,
        )
        connection.traffic = Bucket(
            self.settings.bytes_per_second * traffic,
            self.settings.byte_burst * traffic,
        )

    async def announce_peer(self, seat: Seat, resumed: bool = False) -> None:
        if seat.room.seats.get(seat.role) is not seat or not seat.connection:
            return
        for other in self.others(seat):
            if not other.connection:
                continue
            await self.send(
                other.connection,
                {
                    "op": "peer_joined",
                    "role": "host" if seat.role == "host" else "guest",
                    "player_id": self.slot(seat),
                    "name": seat.name,
                    "resumed": resumed,
                },
            )
            if (
                seat.room.seats.get(seat.role) is seat
                and seat.room.seats.get(other.role) is other
            ):
                await self.send(
                    seat.connection,
                    {
                        "op": "peer_joined",
                        "role": "host" if other.role == "host" else "guest",
                        "player_id": self.slot(other),
                        "name": other.name,
                        "resumed": resumed,
                    },
                )

    def forget_seat(self, seat: Seat) -> None:
        self.tokens.pop(seat.token, None)
        seat.room.seats.pop(seat.role, None)
        if seat.connection:
            seat.connection.seat = None
            seat.connection.created = time.monotonic()
        seat.connection = None

    async def close_room(self, room: Room, reason: str) -> None:
        if self.rooms.get(room.code) is not room:
            return
        self.rooms.pop(room.code, None)
        connections = [seat.connection for seat in room.seats.values()]
        for seat in list(room.seats.values()):
            self.forget_seat(seat)
        for connection in connections:
            await self.send(connection, {"op": "room_closed", "reason": reason})

    async def leave(self, connection: Connection) -> None:
        seat = connection.seat
        if not seat:
            await self.send(connection, {"op": "left"})
            return
        if seat.role == "host":
            await self.close_room(seat.room, "host_left")
        else:
            other = self.other(seat)
            self.forget_seat(seat)
            if other:
                await self.send(
                    other.connection,
                    {
                        "op": "peer_left",
                        "role": "guest",
                        "player_id": self.slot(seat),
                        "reason": "left",
                        "reconnect_seconds": 0,
                    },
                )
        await self.send(connection, {"op": "left"})

    async def disconnected(self, connection: Connection) -> None:
        if connection.sender is not None:
            connection.sender.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await connection.sender
        if connection in self.connections and connection.address in self.addresses:
            budget = self.addresses[connection.address]
            budget.active -= 1
            budget.touched = time.monotonic()
        self.connections.discard(connection)
        seat = connection.seat
        if not seat or seat.connection is not connection:
            return
        seat.connection = None
        connection.seat = None
        seat.expires = time.monotonic() + self.settings.grace_seconds
        if not self.stopping:
            for other in self.others(seat):
                await self.send(
                    other.connection,
                    {
                        "op": "peer_left",
                        "role": "host" if seat.role == "host" else "guest",
                        "player_id": self.slot(seat),
                        "reason": "connection_lost",
                        "reconnect_seconds": self.settings.grace_seconds,
                    },
                )

    async def expire(self) -> None:
        self.expire_addresses()
        now = time.monotonic()
        for room in list(self.rooms.values()):
            host = room.seats.get("host")
            if not host or (not host.connection and host.expires <= now):
                await self.close_room(room, "host_timeout")
                continue
            for guest in list(room.seats.values()):
                if guest is not host and not guest.connection and guest.expires <= now:
                    self.forget_seat(guest)
                    await self.send(
                        host.connection,
                        {
                            "op": "peer_left",
                            "role": "guest",
                            "player_id": self.slot(guest),
                            "reason": "timeout",
                            "reconnect_seconds": 0,
                        },
                    )
        for connection in list(self.connections):
            if (
                not connection.seat
                and now - connection.created > self.settings.idle_seconds
            ):
                await self.error(connection, "idle_timeout", "Bitte erneut verbinden.")
                await connection.socket.close(code=1008, message=b"Idle timeout")

    async def sweep(self) -> None:
        try:
            while True:
                await asyncio.sleep(
                    min(1.0, max(0.05, self.settings.grace_seconds / 4))
                )
                await self.expire()
        except asyncio.CancelledError:
            pass

    async def control(self, connection: Connection, payload: dict) -> None:
        op = payload.get("op")
        fields = {
            "ping": {"op", "id"},
            "leave": {"op"},
            "kick": {"op", "player_id"},
            "status": {"op", "started"},
            "host": {"op", "version", "build", "name"},
            "join": {"op", "version", "build", "name", "code"},
            "resume": {"op", "version", "build", "token", "name"},
        }
        if (
            not isinstance(op, str)
            or op not in fields
            or not payload.keys() <= fields[op]
        ):
            await self.error(
                connection, "invalid_request", "Ungültige Netzwerkanfrage."
            )
            return
        if op == "ping":
            ping_id = payload.get("id", 0)
            if (
                type(ping_id) not in (int, str)
                or (isinstance(ping_id, str) and len(ping_id) > 64)
                or (type(ping_id) is int and abs(ping_id) > 2**53)
            ):
                await self.error(
                    connection, "invalid_request", "Ungültige Ping-Kennung."
                )
                return
            await self.send(connection, {"op": "pong", "id": ping_id})
            return
        if op == "leave":
            await self.leave(connection)
            return
        if op == "kick":
            if not connection.seat or connection.seat.role != "host":
                await self.error(
                    connection,
                    "host_only",
                    "Nur der Gastgeber kann einen Beitritt ablehnen.",
                )
                return
            slot = payload.get("player_id", 2)
            if type(slot) is not int or slot not in (2, 3, 4):
                await self.error(
                    connection, "invalid_request", "Ungültiger Spielerplatz."
                )
                return
            guest = connection.seat.room.seats.get(self.role(slot))
            if guest:
                guest_connection = guest.connection
                self.forget_seat(guest)
                await self.send(
                    guest_connection, {"op": "room_closed", "reason": "host_rejected"}
                )
                await self.send(
                    connection,
                    {
                        "op": "peer_left",
                        "role": "guest",
                        "player_id": slot,
                        "reason": "host_rejected",
                        "reconnect_seconds": 0,
                    },
                )
            await self.send(connection, {"op": "kicked"})
            return
        if op == "status":
            if not connection.seat or connection.seat.role != "host":
                await self.error(
                    connection,
                    "host_only",
                    "Nur der Gastgeber kann die Schicht starten.",
                )
                return
            if type(payload.get("started")) is not bool:
                await self.error(
                    connection, "invalid_request", "Ungültiger Raumstatus."
                )
                return
            room = connection.seat.room
            room.started = payload["started"]
            for seat in list(room.seats.values()):
                await self.send(
                    seat.connection, {"op": "status", "started": room.started}
                )
            return
        if op not in ("host", "join", "resume"):
            await self.error(
                connection, "unknown_operation", "Unbekannte Netzwerkanfrage."
            )
            return
        if connection.seat:
            await self.error(
                connection, "already_in_room", "Du bist bereits in einem Raum."
            )
            return
        # This budget survives socket replacement and covers both code guesses
        # and resume attempts. Invalid build/name requests consume it as well.
        if not self.budget(connection.address).attempts.take():
            await self.error(
                connection, "rate_limited", "Zu viele Anfragen. Bitte kurz warten."
            )
            await connection.socket.close(code=1008, message=b"Admission limit")
            return
        if (
            type(payload.get("version")) is not int
            or payload["version"] != PROTOCOL_VERSION
            or payload.get("build") != GAME_BUILD
        ):
            await self.error(
                connection,
                "version_mismatch",
                "Beide Spieler benötigen dieselbe Spielversion.",
            )
            return
        if op == "resume":
            if "name" in payload and (
                not isinstance(payload["name"], str)
                or not 1 <= len(payload["name"]) <= 24
            ):
                await self.error(
                    connection,
                    "invalid_name",
                    "Der Name muss 1 bis 24 Zeichen lang sein.",
                )
                return
            token = payload.get("token")
            seat = (
                self.tokens.get(token)
                if isinstance(token, str) and len(token) <= 128
                else None
            )
            if not seat or (not seat.connection and seat.expires <= time.monotonic()):
                await self.error(
                    connection,
                    "resume_expired",
                    "Die Wiederverbindung ist abgelaufen. Bitte erneut beitreten.",
                )
                return
            if seat.connection:
                await self.error(
                    connection,
                    "already_connected",
                    "Dieser Spieler ist bereits verbunden.",
                )
                return
            self.tokens.pop(seat.token, None)
            seat.token = secrets.token_urlsafe(24)
            self.tokens[seat.token] = seat
            seat.connection = connection
            seat.expires = 0
            connection.seat = seat
            self.configure_game_budgets(connection, seat.role)
            other = self.other(seat)
            await self.send(
                connection,
                {
                    "op": "resumed",
                    "code": seat.room.code,
                    "role": "host" if seat.role == "host" else "guest",
                    "player_id": self.slot(seat),
                    "resume_token": seat.token,
                    "started": seat.room.started,
                    "peer_connected": bool(other and other.connection),
                },
            )
            await self.announce_peer(seat, resumed=True)
            return
        name = payload.get("name", "Spieler")
        if (
            not isinstance(name, str)
            or not 1 <= len(name.strip()) <= 24
            or any(unicodedata.category(char).startswith("C") for char in name)
        ):
            await self.error(
                connection, "invalid_name", "Der Name muss 1 bis 24 Zeichen lang sein."
            )
            return
        name = name.strip()
        if op == "host":
            if len(self.rooms) >= self.settings.max_rooms:
                await self.error(
                    connection,
                    "server_full",
                    "Der Server ist ausgelastet. Bitte später erneut versuchen.",
                )
                return
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
            while code in self.rooms:
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(6))
            room = Room(code)
            self.rooms[code] = room
            seat = self.make_seat(room, "host", name, connection)
            await self.send(
                connection,
                {
                    "op": "hosted",
                    "code": code,
                    "role": "host",
                    "player_id": 1,
                    "token": seat.token,
                    "resume_token": seat.token,
                    "started": False,
                },
            )
            return
        code = payload.get("code")
        if not isinstance(code, str) or len(code) > 24:
            await self.error(
                connection,
                "invalid_code",
                "Bitte einen sechsstelligen Beitrittscode eingeben.",
            )
            return
        code = code.strip().upper().replace("-", "").replace(" ", "")
        if len(code) != 6 or any(char not in CODE_ALPHABET for char in code):
            await self.error(
                connection,
                "invalid_code",
                "Bitte einen sechsstelligen Beitrittscode eingeben.",
            )
            return
        room = self.rooms.get(code)
        if not room:
            await self.error(
                connection,
                "room_not_found",
                "Dieser Raum wurde nicht gefunden oder ist geschlossen.",
            )
            return
        available = next(
            (slot for slot in (2, 3, 4) if self.role(slot) not in room.seats), None
        )
        if available is None:
            await self.error(
                connection, "room_full", "In diesem Raum spielen bereits vier Spieler."
            )
            return
        host = room.seats.get("host")
        if not host or not host.connection:
            await self.error(
                connection,
                "host_unavailable",
                "Der Gastgeber verbindet sich gerade erneut. Bitte kurz warten.",
            )
            return
        seat = self.make_seat(room, self.role(available), name, connection)
        await self.send(
            connection,
            {
                "op": "joined",
                "code": code,
                "role": "guest",
                "player_id": available,
                "resume_token": seat.token,
                "started": room.started,
                "peer_connected": True,
            },
        )
        await self.announce_peer(seat)

    async def websocket(self, request: web.Request) -> web.WebSocketResponse:
        origins = request.headers.getall("Origin", [])
        if origins and (
            len(origins) != 1
            or not origins[0]
            or origins[0] == "null"
            or origins[0] not in self.settings.allowed_origins
        ):
            raise web.HTTPForbidden(text="Origin is not allowed")
        address = self.address(request)
        budget = self.budget(address)
        if not budget.handshakes.take():
            raise web.HTTPTooManyRequests(text="Connection rate exceeded")
        social = request.app.get(SOCIAL_KEY)
        social_connections = len(social.sessions) + social.pending if social else 0
        if (
            len(self.connections) + self.pending + social_connections >= self.settings.max_connections
            or budget.active + budget.pending >= self.settings.max_connections_per_ip
        ):
            raise web.HTTPServiceUnavailable(text="Relay is full")
        socket = web.WebSocketResponse(
            heartbeat=15,
            receive_timeout=45,
            timeout=1.0,
            autoping=False,
            max_msg_size=MAX_WIRE_BYTES,
            compress=False,
        )
        self.pending += 1
        budget.pending += 1
        try:
            await asyncio.wait_for(
                socket.prepare(request), self.settings.handshake_timeout
            )
        finally:
            self.pending -= 1
            budget.pending -= 1
        connection = Connection(
            socket,
            Bucket(self.settings.packets_per_second, self.settings.packet_burst),
            Bucket(self.settings.controls_per_second, self.settings.control_burst),
            Bucket(self.settings.bytes_per_second, self.settings.byte_burst),
            address=address,
        )
        self.connections.add(connection)
        budget.active += 1
        try:
            async for message in socket:
                if message.type == WSMsgType.BINARY:
                    voice = bool(message.data and message.data[0] & 128)
                    if voice:
                        streams = 9 if connection.seat and connection.seat.role == "host" else 1
                        if (len(message.data) > 1201 or
                                not connection.voice_guard.observe(time.monotonic(), streams)):
                            await self.error(connection, "rate_limited", "Zu viele Netzwerkdaten. Bitte erneut verbinden.")
                            await socket.close(code=1008, message=b"Sustained voice flood")
                            break
                        if not connection.voice.take():
                            continue
                    if not connection.packets.take() or not connection.traffic.take(
                        len(message.data)
                    ):
                        await self.error(
                            connection,
                            "rate_limited",
                            "Zu viele Netzwerkdaten. Bitte erneut verbinden.",
                        )
                        await socket.close(code=1008, message=b"Traffic limit")
                        break
                    if not connection.seat:
                        await self.error(
                            connection,
                            "not_in_room",
                            "Bitte zuerst einen Raum erstellen oder beitreten.",
                        )
                        continue
                    # One untrusted destination byte; source is always supplied
                    # by the authenticated relay seat, never by the client.
                    if len(message.data) < 2 or len(message.data) > MAX_WIRE_BYTES:
                        await self.error(
                            connection, "invalid_route", "Ungültiges Netzwerkpaket."
                        )
                        continue
                    destination = message.data[0] & 127
                    droppable = bool(message.data[0] & 128)
                    source = self.slot(connection.seat)
                    if (
                        destination not in (0, 1, 2, 3, 4)
                        or destination == source
                        or (source != 1 and destination != 1)
                    ):
                        await self.error(
                            connection, "invalid_route", "Ungültiger Empfänger."
                        )
                        continue
                    targets = (
                        [seat for role, seat in connection.seat.room.seats.items()
                         if role != "host"] if destination == 0 else
                        [connection.seat.room.seats.get(self.role(destination))]
                    )
                    for target in targets:
                        if target:
                            await self.send(target.connection,
                                            bytes([source]) + message.data[1:],
                                            droppable=droppable)
                elif message.type == WSMsgType.TEXT:
                    if len(message.data.encode("utf-8")) > 4096:
                        await socket.close(
                            code=1009, message=b"Control message too large"
                        )
                        break
                    if not connection.controls.take():
                        await self.error(
                            connection,
                            "rate_limited",
                            "Zu viele Anfragen. Bitte kurz warten.",
                        )
                        await socket.close(code=1008, message=b"Control limit")
                        break
                    try:
                        payload = json.loads(
                            message.data,
                            object_pairs_hook=strict_object,
                            parse_constant=reject_constant,
                        )
                    except (ValueError, RecursionError):
                        await self.error(
                            connection, "invalid_request", "Ungültige Netzwerkanfrage."
                        )
                        continue
                    if not isinstance(payload, dict):
                        await self.error(
                            connection, "invalid_request", "Ungültige Netzwerkanfrage."
                        )
                        continue
                    await self.control(connection, payload)
                elif message.type in (WSMsgType.PING, WSMsgType.PONG):
                    if not connection.controls.take():
                        await socket.close(code=1008, message=b"Control frame limit")
                        break
                    if message.type == WSMsgType.PING:
                        await asyncio.wait_for(
                            socket.pong(message.data), self.settings.send_timeout
                        )
                elif message.type == WSMsgType.ERROR:
                    break
        except (ConnectionError, asyncio.TimeoutError):
            pass
        finally:
            await self.disconnected(connection)
        return socket


def strict_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate control key")
        result[key] = value
    return result


def reject_constant(_value: str) -> None:
    raise ValueError("Nonfinite JSON number")


RELAY_KEY = web.AppKey("relay", Relay)


def create_app(settings: Settings | None = None) -> web.Application:
    app = web.Application(client_max_size=4096)
    relay = Relay(settings or Settings.from_env())
    app[RELAY_KEY] = relay
    app.router.add_get("/ws", relay.websocket)
    social = SocialService(relay, relay.settings.social_db or ":memory:", GAME_BUILD)
    app[SOCIAL_KEY] = social
    app.router.add_get("/social", social.websocket)

    async def health(_request: web.Request) -> web.Response:
        return web.json_response(
            {"status": "ok", "protocol": PROTOCOL_VERSION, "build": GAME_BUILD}
        )

    async def lifecycle(_app: web.Application):
        await social.start()
        relay.sweeper = asyncio.create_task(relay.sweep())
        yield
        await social.stop()
        relay.stopping = True
        relay.sweeper.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await relay.sweeper
        await asyncio.gather(
            *(
                connection.socket.close(code=1001, message=b"Server shutdown")
                for connection in list(relay.connections)
            ),
            return_exceptions=True,
        )
        relay.rooms.clear()
        relay.tokens.clear()

    app.router.add_get("/healthz", health)
    app.cleanup_ctx.append(lifecycle)
    return app


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO, format="%(levelname)s %(name)s: %(message)s"
    )
    # Access logs are disabled: they are unnecessary for operating this relay.
    web.run_app(
        create_app(),
        host=os.getenv("RELAY_HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "8765")),
        access_log=None,
    )
