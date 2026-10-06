"""Private friends, presence and invitations beside the opaque game relay.

The database stores only SHA-256 hashes of random 256-bit credentials. All SQLite
work runs on a serialized worker thread, never on the relay's event loop. Codes
are identifiers, not login credentials; presence is visible to mutual friends.
"""
from __future__ import annotations

import asyncio
import contextlib
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import sqlite3
import time
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from aiohttp import WSMsgType, web

VERSION = 1
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_RE = re.compile(r"[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}\Z")
ROOM_RE = re.compile(r"[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}\Z")
ROOM_SECONDS = 30.0
MAX_FRIENDS = 64
MAX_REQUESTS = 32
MAX_BLOCKS = 128
MAX_INVITES = 16
MAX_MESSAGE = 4096
MAX_STATE = 49152
INVITE_SECONDS = 120.0


def default_database() -> str:
    data = os.getenv("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return str(Path(data) / "bunkercrew-relay" / "social.sqlite3")


def safe_name(value: object) -> str | None:
    if not isinstance(value, str) or value != value.strip():
        return None
    value = unicodedata.normalize("NFC", value)
    if not 1 <= len(value) <= 24 or len(value.encode("utf-8")) > 96:
        return None
    if any(unicodedata.category(char).startswith("C") or char in "\u2028\u2029" for char in value):
        return None
    return value


def safe_relay_url(value: object) -> bool:
    if not isinstance(value, str) or len(value) > 256:
        return False
    if value == "":
        return True  # Direct ENet invitation, including its authenticated code.
    try:
        parsed = urlsplit(value)
        if (parsed.scheme not in ("ws", "wss") or not parsed.hostname or
                parsed.username or parsed.password or parsed.query or parsed.fragment or
                parsed.path not in ("", "/", "/ws") or any(ord(char) < 33 for char in value)):
            return False
        if parsed.port is not None and not 1 <= parsed.port <= 65535:
            return False
        return parsed.scheme == "wss" or parsed.hostname.lower() in ("localhost", "127.0.0.1", "::1")
    except ValueError:
        return False


def safe_room_code(value: object, relay_url: str) -> bool:
    if not isinstance(value,str) or len(value)>64:
        return False
    alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    if relay_url:
        return bool(re.fullmatch(r"[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}",value))
    code = value.replace("-", "").replace(" ", "")
    if len(code) not in (24,27) or any(char not in alphabet for char in code):
        return False
    base = code[:-16]
    number = 0
    for char in base:
        number = (number<<5)|alphabet.index(char)
    extended = len(base)==11
    width = 7 if extended else 8
    checksum = number & ((1<<width)-1)
    number >>= width
    port = 24777
    if extended:
        port = number & 65535
        number >>= 16
    octets = [(number>>shift)&255 for shift in (24,16,8,0)]
    if port == 0 or octets[0] == 0 or octets[0] >= 224:
        return False
    values = octets+[(port>>8)&255,port&255] if extended else octets
    if extended:
        crc = 0x27
        for item in values:
            for bit in range(8):
                mix = ((crc>>6)^(item>>(7-bit)))&1
                crc = ((crc<<1)&127)^(0x09 if mix else 0)
    else:
        crc = 0xA7
        for item in values:
            crc ^= item
            for _ in range(8):
                crc = ((crc<<1)^0x07)&255 if crc&128 else (crc<<1)&255
    return checksum == crc


class Limit:
    def __init__(self, rate: float, capacity: float):
        self.rate, self.capacity, self.tokens = rate, capacity, capacity
        self.updated = time.monotonic()

    def take(self) -> bool:
        now = time.monotonic()
        self.tokens = min(self.capacity, self.tokens + (now-self.updated)*self.rate)
        self.updated = now
        if self.tokens < 1:
            return False
        self.tokens -= 1
        return True


class SocialError(Exception):
    def __init__(self, code: str):
        self.code = code


class Store:
    def __init__(self, path: str, max_profiles: int = 100000):
        self.path = path
        self.max_profiles = max_profiles
        self.connection: sqlite3.Connection | None = None
        self.lock = asyncio.Lock()
        self.waiting = 0

    async def open(self) -> None:
        try:
            await self.call("open")
        except (OSError,sqlite3.Error):
            await self.close()
            raise

    def _open(self) -> None:
        if self.path != ":memory:":
            directory = Path(self.path).expanduser().parent
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.connection = sqlite3.connect(self.path, timeout=1.0, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys=ON")
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("PRAGMA synchronous=NORMAL")
        self.connection.executescript("""
            CREATE TABLE IF NOT EXISTS profiles(
                id INTEGER PRIMARY KEY, secret_hash TEXT NOT NULL UNIQUE,
                code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, created INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS friends(
                a INTEGER NOT NULL REFERENCES profiles(id),
                b INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(a,b), CHECK(a<b)
            );
            CREATE TABLE IF NOT EXISTS requests(
                sender INTEGER NOT NULL REFERENCES profiles(id),
                target INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(sender,target), CHECK(sender<>target)
            );
            CREATE TABLE IF NOT EXISTS blocks(
                owner INTEGER NOT NULL REFERENCES profiles(id),
                target INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(owner,target), CHECK(owner<>target)
            );
            CREATE INDEX IF NOT EXISTS friend_b ON friends(b);
            CREATE INDEX IF NOT EXISTS request_target ON requests(target);
            CREATE INDEX IF NOT EXISTS block_target ON blocks(target);
        """)
        self.connection.commit()
        if self.path != ":memory:":
            os.chmod(self.path, 0o600)

    async def call(self, operation: str, *arguments):
        if self.waiting >= 128:
            raise SocialError("service_unavailable")
        self.waiting += 1
        try:
            async with self.lock:
                worker = asyncio.create_task(asyncio.to_thread(getattr(self, "_"+operation), *arguments))
                try:
                    return await asyncio.shield(worker)
                except asyncio.CancelledError:
                    # Cancellation cannot release the serialization lock while
                    # its database worker is still committing a transaction.
                    with contextlib.suppress(Exception):
                        await asyncio.shield(worker)
                    raise
        finally:
            self.waiting -= 1

    async def close(self) -> None:
        async with self.lock:
            if self.connection is not None:
                await asyncio.to_thread(self.connection.close)
                self.connection = None

    def _profile(self, secret_hash: str, name: str) -> dict:
        db = self.connection
        row = db.execute("SELECT id,code,name FROM profiles WHERE secret_hash=?", (secret_hash,)).fetchone()
        if row:
            return dict(row)
        if db.execute("SELECT COUNT(*) FROM profiles").fetchone()[0] >= self.max_profiles:
            raise SocialError("service_unavailable")
        with db:
            for _ in range(8):
                code = "".join(secrets.choice(ALPHABET) for _ in range(12))
                try:
                    cursor = db.execute("INSERT INTO profiles(secret_hash,code,name,created) VALUES(?,?,?,?)",
                                        (secret_hash, code, name, int(time.time())))
                    return {"id":cursor.lastrowid, "code":code, "name":name}
                except sqlite3.IntegrityError:
                    continue
        raise SocialError("service_unavailable")

    def _view(self, profile_id: int) -> dict:
        db = self.connection
        friends = [dict(row) for row in db.execute("""
            SELECT p.id,p.code,p.name FROM profiles p JOIN friends f
            ON (f.a=? AND f.b=p.id) OR (f.b=? AND f.a=p.id) ORDER BY p.name,p.code
        """, (profile_id,profile_id))]
        requests = [dict(row) for row in db.execute("""
            SELECT p.id,p.code,p.name FROM profiles p JOIN requests r ON r.sender=p.id
            WHERE r.target=? ORDER BY p.name,p.code
        """, (profile_id,))]
        blocked = [dict(row) for row in db.execute("""
            SELECT p.id,p.code,p.name FROM profiles p JOIN blocks b ON b.target=p.id
            WHERE b.owner=? ORDER BY p.name,p.code
        """, (profile_id,))]
        outgoing = [dict(row) for row in db.execute("""
            SELECT p.id,p.code,p.name FROM profiles p JOIN requests r ON r.target=p.id
            WHERE r.sender=? ORDER BY p.name,p.code
        """, (profile_id,))]
        return {"friends":friends, "requests":requests, "outgoing_requests":outgoing, "blocked":blocked}

    def _name(self, profile_id: int, name: str) -> None:
        with self.connection:
            self.connection.execute("UPDATE profiles SET name=? WHERE id=?", (name,profile_id))

    def _related(self, first: int, second: int) -> bool:
        a,b = sorted((first,second))
        return self.connection.execute("SELECT 1 FROM friends WHERE a=? AND b=?", (a,b)).fetchone() is not None

    def _blocked_pair(self, first: int, second: int) -> bool:
        return self.connection.execute("SELECT 1 FROM blocks WHERE (owner=? AND target=?) OR (owner=? AND target=?)",(first,second,second,first)).fetchone() is not None

    def _mutate(self, profile_id: int, operation: str, code: str) -> int:
        db = self.connection
        row = db.execute("SELECT id FROM profiles WHERE code=?", (code,)).fetchone()
        if not row or row[0] == profile_id:
            raise SocialError("not_found")
        target = int(row[0])
        a,b = sorted((profile_id,target))
        both = (profile_id,target,target,profile_id)
        with db:
            if operation == "block_friend":
                count = db.execute("SELECT COUNT(*) FROM blocks WHERE owner=?", (profile_id,)).fetchone()[0]
                already_blocked = db.execute("SELECT 1 FROM blocks WHERE owner=? AND target=?", (profile_id,target)).fetchone()
                if count >= MAX_BLOCKS and not already_blocked:
                    raise SocialError("friend_limit")
                db.execute("INSERT OR IGNORE INTO blocks VALUES(?,?)", (profile_id,target))
                db.execute("DELETE FROM friends WHERE a=? AND b=?", (a,b))
                db.execute("DELETE FROM requests WHERE (sender=? AND target=?) OR (sender=? AND target=?)", both)
                return target
            if operation == "unblock_friend":
                db.execute("DELETE FROM blocks WHERE owner=? AND target=?", (profile_id,target))
                return target
            if db.execute("SELECT 1 FROM blocks WHERE (owner=? AND target=?) OR (owner=? AND target=?)", both).fetchone():
                raise SocialError("not_found")
            if operation == "remove_friend":
                db.execute("DELETE FROM friends WHERE a=? AND b=?", (a,b))
                db.execute("DELETE FROM requests WHERE (sender=? AND target=?) OR (sender=? AND target=?)", both)
            elif operation == "decline_friend":
                db.execute("DELETE FROM requests WHERE sender=? AND target=?", (target,profile_id))
            elif operation in ("add_friend", "accept_friend"):
                if db.execute("SELECT 1 FROM friends WHERE a=? AND b=?", (a,b)).fetchone():
                    return target
                incoming = db.execute("SELECT 1 FROM requests WHERE sender=? AND target=?", (target,profile_id)).fetchone()
                if operation == "accept_friend" and not incoming:
                    raise SocialError("not_found")
                if operation == "accept_friend":
                    for owner in (profile_id,target):
                        count = db.execute("SELECT COUNT(*) FROM friends WHERE a=? OR b=?", (owner,owner)).fetchone()[0]
                        if count >= MAX_FRIENDS:
                            raise SocialError("friend_limit")
                    db.execute("INSERT INTO friends VALUES(?,?)", (a,b))
                    db.execute("DELETE FROM requests WHERE (sender=? AND target=?) OR (sender=? AND target=?)", both)
                else:
                    if db.execute("SELECT 1 FROM requests WHERE sender=? AND target=?", (profile_id,target)).fetchone():
                        return target
                    outgoing = db.execute("SELECT COUNT(*) FROM requests WHERE sender=?", (profile_id,)).fetchone()[0]
                    incoming_count = db.execute("SELECT COUNT(*) FROM requests WHERE target=?", (target,)).fetchone()[0]
                    if outgoing >= MAX_REQUESTS or incoming_count >= MAX_REQUESTS:
                        raise SocialError("request_limit")
                    db.execute("INSERT OR IGNORE INTO requests VALUES(?,?)", (profile_id,target))
            else:
                raise SocialError("invalid_request")
        return target


@dataclass(eq=False)
class Session:
    socket: web.WebSocketResponse
    address: str
    authority: str
    profile: dict | None = None
    peer_key: bytes = field(default_factory=lambda: secrets.token_bytes(32))
    identities: Limit = field(default_factory=lambda: Limit(2,8))
    resolves: Limit = field(default_factory=lambda: Limit(1,4))
    controls: Limit = field(default_factory=lambda: Limit(4,16))
    actions: Limit = field(default_factory=lambda: Limit(0.5,8))
    queue: asyncio.Queue = field(default_factory=lambda: asyncio.Queue(maxsize=16))
    sender: asyncio.Task | None = None
    opened: float = field(default_factory=time.monotonic)
    touched: float = field(default_factory=time.monotonic)
    last_presence: float = 0.0
    presence_dirty: bool = False
    violations: int = 0
    closing: bool = False
    ready_sent: bool = False
    presence: dict = field(default_factory=lambda: {"status":"menu", "environment":"", "joinable":False, "room_code":"", "relay_url":"", "room_token":""})


class SocialService:
    def __init__(self, relay, database: str, game_build: str):
        self.relay = relay
        self.game_build = game_build
        self.store = Store(database)
        self.sessions: set[Session] = set()
        self.online: dict[int,Session] = {}
        self.invites: dict[str,dict] = {}
        self.room_aliases: dict[str,dict] = {}
        self.profile_aliases: dict[int,str] = {}
        self.profile_limits: dict[int,Limit] = {}
        self.sweeper: asyncio.Task | None = None
        self.stopping = False
        self.pending = 0
        self.pending_states: set[int] = set()
        self.pending_publishes: set[int] = set()

    async def start(self) -> None:
        try:
            await self.store.open()
        except (OSError,sqlite3.Error) as error:
            # Do not expose secrets, profile payloads or database contents.
            raise RuntimeError("Cannot initialize social database; check SOCIAL_DB and directory permissions") from error
        self.sweeper = asyncio.create_task(self.sweep())

    async def stop(self) -> None:
        self.stopping = True
        if self.sweeper:
            self.sweeper.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.sweeper
        await asyncio.gather(*(session.socket.close(code=1001) for session in list(self.sessions)), return_exceptions=True)
        for session in list(self.sessions):
            if session.sender:
                session.sender.cancel()
        await asyncio.gather(*(session.sender for session in self.sessions if session.sender), return_exceptions=True)
        self.online.clear()
        self.invites.clear()
        self.room_aliases.clear()
        self.profile_aliases.clear()
        self.pending_states.clear()
        self.pending_publishes.clear()
        await self.store.close()

    def send(self, session: Session | None, payload: dict) -> None:
        if session is None or session.socket.closed or session.closing:
            return
        wire = json.dumps(payload, ensure_ascii=False, separators=(",",":"))
        if len(wire.encode("utf-8")) > MAX_STATE or session.queue.full():
            session.closing = True
            asyncio.create_task(session.socket.close(code=1008, message=b"Social queue limit"))
            return
        session.queue.put_nowait(wire)

    async def writer(self, session: Session) -> None:
        try:
            while not session.socket.closed:
                wire = await session.queue.get()
                await asyncio.wait_for(session.socket.send_str(wire),2.0)
        except (ConnectionError,asyncio.TimeoutError,RuntimeError):
            await session.socket.close(code=1008)

    async def error(self, session: Session, code: str) -> None:
        self.send(session,{"op":"error", "code":code})
        if code == "rate_limited":
            session.violations += 1
            if session.violations >= 4:
                await session.socket.close(code=1008, message=b"Social rate limit")

    def joinable(self, session: Session) -> bool:
        data = session.presence
        if data["status"] != "lobby" or not data["joinable"] or not data["room_code"]:
            return False
        if data["relay_url"]:
            code = data["room_code"]
            room = self.relay.rooms.get(code)
            token = data["room_token"]
            seat = self.relay.tokens.get(token)
            local_authority = urlsplit(data["relay_url"]).netloc.lower() == session.authority
            if room or seat or local_authority:
                return bool(room and seat and seat.role == "host" and seat.room is room and
                            seat.connection and not room.started and len(room.seats) < 4 and
                            secrets.compare_digest(seat.token,token))
        return True  # Remote relay/direct capacity remains enforced by its host.

    def current_invite(self, invitation: dict) -> bool:
        sender = self.online.get(invitation["sender"])
        return bool(sender and invitation["expires"] > time.time() and self.joinable(sender) and
                    invitation["room_code"] == sender.presence["room_code"] and
                    invitation["relay_url"] == sender.presence["relay_url"])

    def revoke_room(self, profile_id: int) -> None:
        code = self.profile_aliases.pop(profile_id,"")
        if code:
            self.room_aliases.pop(code,None)

    def sync_room(self, session: Session) -> str:
        identity = session.profile["id"]
        if not self.joinable(session):
            self.revoke_room(identity)
            return ""
        code = self.profile_aliases.get(identity,"")
        room = self.room_aliases.get(code)
        if room and (room["expires"] <= time.time() or
                     (room["room_code"],room["relay_url"]) != (session.presence["room_code"],session.presence["relay_url"])):
            self.revoke_room(identity)
            code = ""
        if not code:
            for _ in range(32):
                candidate = "".join(secrets.choice(ALPHABET) for _ in range(6))
                if candidate not in self.room_aliases and candidate not in self.relay.rooms:
                    code = candidate
                    break
            if not code: return ""
            self.profile_aliases[identity] = code
            self.room_aliases[code] = {"owner":identity,"room_code":session.presence["room_code"],"relay_url":session.presence["relay_url"],"expires":0.0}
        self.room_aliases[code]["expires"] = time.time() + ROOM_SECONDS
        return code

    @staticmethod
    def observed_ipv4(session: Session) -> str:
        try:
            address = ipaddress.ip_address(session.address)
            return str(address) if isinstance(address,ipaddress.IPv4Address) and address.is_global else ""
        except ValueError:
            return ""

    async def state(self, session: Session, ready: bool = False) -> None:
        if session.profile is None or self.online.get(session.profile["id"]) is not session:
            return
        identity = session.profile["id"]
        self.pending_states.add(identity)
        ready = ready or not session.ready_sent
        view = await self.store.call("view",session.profile["id"])
        result = {"op":"ready" if ready else "state", "friends":[], "requests":[], "outgoing_requests":[], "blocked":[], "invitations":[], "room_alias":self.profile_aliases.get(session.profile["id"],"")}
        if ready:
            result.update(code=session.profile["code"],name=session.profile["name"],peer_key=session.peer_key.hex(),observed_address=self.observed_ipv4(session))
        for friend in view["friends"]:
            online = self.online.get(friend["id"])
            data = online.presence if online else None
            result["friends"].append({"code":friend["code"], "name":friend["name"],
                "status":data["status"] if data else "offline", "environment":data["environment"] if data else "",
                "joinable":bool(online and self.joinable(online))})
        for key in ("requests","outgoing_requests","blocked"):
            result[key] = [{"code":row["code"],"name":row["name"]} for row in view[key]]
        for invitation in self.invites.values():
            if invitation["target"] == session.profile["id"] and self.current_invite(invitation):
                result["invitations"].append({key:invitation[key] for key in ("id","from_code","name","room_code","relay_url","expires")})
        self.send(session,result)
        session.ready_sent = True
        self.pending_states.discard(identity)

    async def publish(self, profile_id: int, include_self: bool = True) -> None:
        self.pending_publishes.add(profile_id)
        view = await self.store.call("view",profile_id)
        ids = {friend["id"] for friend in view["friends"]}
        if include_self:
            ids.add(profile_id)
        for identity in ids:
            session = self.online.get(identity)
            if session:
                await self.state(session)
        self.pending_publishes.discard(profile_id)

    async def command(self, session: Session, payload: dict) -> None:
        operation = payload.get("op")
        if session.profile is None:
            if (operation != "auth" or set(payload) != {"op","version","build","secret","name"} or
                    type(payload.get("version")) is not int or payload["version"] != VERSION or payload.get("build") != self.game_build):
                raise SocialError("version_mismatch" if operation == "auth" else "invalid_request")
            if not self.relay.budget(session.address).attempts.take():
                raise SocialError("rate_limited")
            secret = payload.get("secret")
            name = safe_name(payload.get("name"))
            if not isinstance(secret,str) or re.fullmatch(r"[a-f0-9]{64}",secret) is None or name is None:
                raise SocialError("invalid_request")
            profile = await self.store.call("profile",hashlib.sha256(bytes.fromhex(secret)).hexdigest(),name)
            current = self.online.get(profile["id"])
            if current and not current.socket.closed:
                # Existing session remains authoritative. A second login is
                # rejected explicitly, rather than silently taking over a user.
                self.send(session,{"op":"error","code":"session_replaced"})
                return
            session.profile = profile
            self.online[profile["id"]] = session
            self.pending_publishes.add(profile["id"])
            if profile["id"] not in self.profile_limits:
                if len(self.profile_limits) >= 8192:
                    inactive = [identity for identity in self.profile_limits if identity not in self.online]
                    oldest = min(inactive,key=lambda identity:self.profile_limits[identity].updated)
                    self.profile_limits.pop(oldest,None)
                self.profile_limits[profile["id"]] = Limit(0.25,8)
            await self.state(session,True)
            await self.publish(profile["id"],False)
            return
        profile_id = session.profile["id"]
        if self.online.get(profile_id) is not session:
            raise SocialError("session_replaced")
        if operation == "ping" and set(payload) == {"op"}:
            previous_alias = self.profile_aliases.get(profile_id,"")
            self.sync_room(session)
            self.send(session,{"op":"pong"})
            # A resumed application can renew after its old alias expired.
            # Ordinary heartbeats renew the deadline without a database read.
            if self.profile_aliases.get(profile_id,"") != previous_alias:
                await self.state(session)
            return
        if operation == "resolve_room" and set(payload) == {"op","request","code"}:
            if (not isinstance(payload["request"],str) or not re.fullmatch(r"[a-f0-9]{32}",payload["request"]) or
                    not isinstance(payload["code"],str) or not ROOM_RE.fullmatch(payload["code"])):
                raise SocialError("invalid_request")
            response = {"op":"room_resolved","request":payload["request"],"code":payload["code"],"room_code":"","relay_url":"","expires":0.0,"error_code":"room_unavailable"}
            if not session.resolves.take() or not self.relay.budget(session.address).attempts.take():
                response["error_code"] = "rate_limited"
                self.send(session,response)
                return
            room = self.room_aliases.get(payload["code"])
            owner = self.online.get(room["owner"]) if room else None
            valid = bool(room and owner and room["owner"] != profile_id and room["expires"] > time.time() and self.joinable(owner) and
                         (room["room_code"],room["relay_url"]) == (owner.presence["room_code"],owner.presence["relay_url"]))
            if valid and not await self.store.call("blocked_pair",profile_id,room["owner"]):
                response.update(room_code=room["room_code"],relay_url=room["relay_url"],expires=room["expires"],error_code="")
            self.send(session,response)
            return
        if operation == "verify_crew" and set(payload) == {"op","request","code","context","proof"}:
            if (not isinstance(payload["request"],str) or not re.fullmatch(r"[a-zA-Z0-9:_-]{1,80}",payload["request"]) or
                    not isinstance(payload["code"],str) or not CODE_RE.fullmatch(payload["code"]) or
                    not isinstance(payload["context"],str) or not re.fullmatch(r"[a-f0-9]{48}",payload["context"]) or
                    not isinstance(payload["proof"],str) or not re.fullmatch(r"[a-f0-9]{64}",payload["proof"])):
                raise SocialError("invalid_request")
            if not session.identities.take():
                raise SocialError("rate_limited")
            target = next((item for item in self.online.values() if item.profile["code"] == payload["code"]),None)
            expected = hmac.new(target.peer_key, ("bunkercrew-crew1:"+self.game_build+":"+payload["context"]+":"+payload["code"]).encode(),hashlib.sha256).hexdigest() if target else ""
            valid = bool(target and hmac.compare_digest(expected,payload["proof"]))
            self.send(session,{"op":"crew_verified","request":payload["request"],"code":payload["code"],"name":target.profile["name"] if valid else "","valid":valid})
            return
        if operation == "presence" and set(payload) == {"op","data"}:
            data = payload["data"]
            allowed = {"status","environment","joinable","room_code","relay_url","room_token"}
            if (not isinstance(data,dict) or set(data)-allowed or data.get("status") not in ("menu","lobby","playing") or
                    not isinstance(data.get("environment"),str) or not re.fullmatch(r"[a-z0-9_]{0,48}",data["environment"]) or
                    type(data.get("joinable")) is not bool or not isinstance(data.get("room_code"),str) or len(data["room_code"])>64 or
                    not safe_relay_url(data.get("relay_url")) or not isinstance(data.get("room_token",""),str) or len(data.get("room_token",""))>128):
                raise SocialError("invalid_request")
            if data["joinable"] and (data["status"] != "lobby" or not safe_room_code(data["room_code"],data["relay_url"])):
                raise SocialError("invalid_request")
            next_presence = {key:data.get(key,"") for key in allowed}
            if not next_presence["joinable"]:
                next_presence.update(room_code="",relay_url="",room_token="")
            previous_room = (session.presence["room_code"],session.presence["relay_url"])
            next_room = (next_presence["room_code"],next_presence["relay_url"])
            if previous_room != next_room or not next_presence["joinable"]:
                self.invites = {key:row for key,row in self.invites.items() if row["sender"]!=profile_id}
            session.presence = next_presence
            self.sync_room(session)
            session.presence_dirty = True
            if time.monotonic()-session.last_presence >= 0.2:
                await self.publish(profile_id)
                session.last_presence = time.monotonic()
                session.presence_dirty = False
            return
        if not session.actions.take() or not self.profile_limits[profile_id].take():
            raise SocialError("rate_limited")
        if operation == "name" and set(payload) == {"op","name"}:
            name = safe_name(payload["name"])
            if name is None:
                raise SocialError("invalid_name")
            await self.store.call("name",profile_id,name)
            session.profile["name"] = name
            self.send(session,{"op":"name_saved","name":name})
            await self.publish(profile_id)
            return
        friend_ops = {"add_friend","accept_friend","decline_friend","remove_friend","block_friend","unblock_friend"}
        if operation in friend_ops and set(payload) == {"op","code"}:
            if not isinstance(payload["code"],str) or not CODE_RE.fullmatch(payload["code"]):
                raise SocialError("invalid_request")
            target = await self.store.call("mutate",profile_id,operation,payload["code"])
            if operation in ("remove_friend","block_friend"):
                self.invites = {key:row for key,row in self.invites.items() if {row["sender"],row["target"]} != {profile_id,target}}
            self.pending_publishes.update((profile_id,target))
            await self.publish(profile_id)
            await self.publish(target)
            return
        if operation == "invite" and set(payload) == {"op","code"}:
            view = await self.store.call("view",profile_id)
            friend = next((row for row in view["friends"] if row["code"] == payload["code"]),None)
            if not friend or friend["id"] not in self.online:
                raise SocialError("not_friends")
            if not self.joinable(session):
                raise SocialError("not_joinable")
            target = friend["id"]
            # One live invitation per friend pair; refresh without flooding.
            existing = next((row for row in self.invites.values() if row["sender"]==profile_id and row["target"]==target),None)
            if existing:
                if self.current_invite(existing):
                    return
                self.invites.pop(existing["id"],None)
            if sum(row["target"]==target for row in self.invites.values())>=MAX_INVITES or len(self.invites)>=2048:
                raise SocialError("request_limit")
            identity = secrets.token_hex(16)
            self.invites[identity] = {"id":identity,"sender":profile_id,"target":target,
                "from_code":session.profile["code"],"name":session.profile["name"],
                "room_code":session.presence["room_code"],"relay_url":session.presence["relay_url"],"expires":time.time()+INVITE_SECONDS}
            await self.state(self.online[target])
            return
        if operation in ("take_invite","decline_invite") and set(payload) == {"op","id"}:
            invitation = self.invites.get(payload["id"]) if isinstance(payload["id"],str) else None
            if not invitation or invitation["target"] != profile_id or invitation["expires"]<=time.time():
                raise SocialError("invite_expired")
            if operation == "take_invite" and (not self.current_invite(invitation) or
                    not await self.store.call("related",profile_id,invitation["sender"])):
                raise SocialError("invite_expired")
            self.invites.pop(invitation["id"],None)
            await self.state(session)
            return
        raise SocialError("invalid_request")

    async def websocket(self, request: web.Request) -> web.WebSocketResponse:
        origins = request.headers.getall("Origin", [])
        if origins and (len(origins)!=1 or origins[0] not in self.relay.settings.allowed_origins):
            raise web.HTTPForbidden(text="Origin is not allowed")
        address = self.relay.address(request)
        try:
            loopback = ipaddress.ip_address(address).is_loopback
        except ValueError:
            loopback = False
        peer = ipaddress.ip_address(request.remote or "0.0.0.0")
        trusted = any(peer in network for network in self.relay.trusted_proxies)
        secure = request.secure or (trusted and request.headers.get("X-Forwarded-Proto") == "https")
        if not loopback and not secure:
            raise web.HTTPForbidden(text="TLS is required for social profiles")
        budget = self.relay.budget(address)
        if not budget.handshakes.take():
            raise web.HTTPTooManyRequests(text="Connection rate exceeded")
        if (len(self.sessions)+self.pending>=256 or
                len(self.sessions)+self.pending+len(self.relay.connections)+self.relay.pending>=self.relay.settings.max_connections or
                budget.active+budget.pending>=self.relay.settings.max_connections_per_ip):
            raise web.HTTPServiceUnavailable(text="Social capacity reached")
        socket = web.WebSocketResponse(heartbeat=15,receive_timeout=35,timeout=1,max_msg_size=MAX_MESSAGE,compress=False)
        self.pending += 1
        budget.pending += 1
        try:
            await asyncio.wait_for(socket.prepare(request),self.relay.settings.handshake_timeout)
        finally:
            self.pending -= 1
            budget.pending -= 1
        session = Session(socket,address,request.host.lower())
        budget.active += 1
        self.sessions.add(session)
        session.sender = asyncio.create_task(self.writer(session))
        try:
            async for message in socket:
                session.touched = time.monotonic()
                if message.type != WSMsgType.TEXT:
                    if message.type in (WSMsgType.ERROR,WSMsgType.CLOSE,WSMsgType.CLOSED):
                        break
                    await socket.close(code=1008,message=b"Social text protocol required")
                    break
                if not session.controls.take():
                    await self.error(session,"rate_limited")
                    continue
                try:
                    def strict_object(pairs):
                        result = {}
                        for key,value in pairs:
                            if key in result:
                                raise ValueError("duplicate key")
                            result[key] = value
                        return result
                    def reject_number(_value):
                        raise ValueError("nonfinite number")
                    payload = json.loads(message.data,object_pairs_hook=strict_object,parse_constant=reject_number)
                    if not isinstance(payload,dict):
                        raise SocialError("invalid_request")
                    await self.command(session,payload)
                except SocialError as error:
                    await self.error(session,error.code)
                except (ValueError,TypeError,RecursionError):
                    await self.error(session,"invalid_request")
                except sqlite3.Error:
                    await self.error(session,"service_unavailable")
        except (ConnectionError,asyncio.TimeoutError):
            pass
        finally:
            self.sessions.discard(session)
            budget.active = max(0,budget.active-1)
            if session.sender:
                session.sender.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await session.sender
            if session.profile and self.online.get(session.profile["id"]) is session:
                profile_id = session.profile["id"]
                self.online.pop(profile_id,None)
                self.revoke_room(profile_id)
                affected = {row["target"] for row in self.invites.values() if row["sender"]==profile_id}
                self.invites = {key:row for key,row in self.invites.items() if profile_id not in (row["sender"],row["target"])}
                if not self.stopping:
                    try:
                        await self.publish(profile_id,False)
                    except (SocialError,sqlite3.Error):
                        # Presence invalidation remains queued for the sweeper;
                        # transient storage pressure cannot leak a web traceback.
                        pass
                    for target in affected:
                        if target in self.online:
                            try:
                                await self.state(self.online[target])
                            except (SocialError,sqlite3.Error):
                                pass
        return socket

    async def sweep(self) -> None:
        while True:
            await asyncio.sleep(1)
            now = time.monotonic()
            for _code,room in list(self.room_aliases.items()):
                if room["expires"] <= time.time():
                    self.revoke_room(room["owner"])
                    if room["owner"] in self.online:
                        self.pending_states.add(room["owner"])
            for session in list(self.sessions):
                if (not session.profile and now-session.opened>5) or now-session.touched>30:
                    await session.socket.close(code=1008,message=b"Social handshake/heartbeat timeout")
                elif session.profile and session.presence_dirty:
                    try:
                        await self.publish(session.profile["id"])
                    except (SocialError,sqlite3.Error):
                        continue
                    session.last_presence = now
                    session.presence_dirty = False
            expired = [key for key,row in self.invites.items() if not self.current_invite(row)]
            affected = {self.invites[key]["target"] for key in expired}
            for key in expired:
                self.invites.pop(key,None)
            for target in affected:
                if target in self.online:
                    try:
                        await self.state(self.online[target])
                    except (SocialError,sqlite3.Error):
                        pass
            # Both disconnect and expired-invite notifications survive temporary
            # SQLite busy/queue pressure. Bound retries independently of traffic.
            for identity in list(self.pending_publishes)[:16]:
                try:
                    await self.publish(identity,identity in self.online)
                except (SocialError,sqlite3.Error):
                    pass
            for identity in list(self.pending_states)[:32]:
                session = self.online.get(identity)
                if not session:
                    self.pending_states.discard(identity)
                    continue
                try:
                    await self.state(session)
                except (SocialError,sqlite3.Error):
                    pass


SOCIAL_KEY = web.AppKey("social",SocialService)
