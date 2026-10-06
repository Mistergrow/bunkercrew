#!/usr/bin/env python3
"""Four real games behind bounded, seeded UDP fault proxies; never WAN certification."""
from __future__ import annotations

import argparse
import asyncio
import collections
import datetime
import heapq
import json
import math
import os
from pathlib import Path
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import verify_beta_stability as stability
from network_stream_fault_proxy import StreamFaultProxy

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = "tests/network_impairment_peer.gd"


class FaultPolicy:
    """Bernoulli loss and independently seeded one-way jitter, including ENet ACKs."""

    def __init__(self, seed: int, delay_ms: float, jitter_ms: float, loss: float):
        if not (math.isfinite(delay_ms) and math.isfinite(jitter_ms) and 0 <= jitter_ms <= delay_ms
                and math.isfinite(loss) and 0 <= loss <= 1):
            raise ValueError("Require finite 0 <= jitter <= delay and 0 <= loss <= 1")
        self.random = random.Random(seed)
        self.delay = delay_ms / 1000
        self.jitter = jitter_ms / 1000
        self.loss = loss
        self.blocked_until = 0.0
        self.stats = collections.Counter()

    def schedule(self, now: float, size: int) -> float | None:
        self.stats["received_packets"] += 1
        self.stats["received_bytes"] += size
        if now < self.blocked_until:
            self.stats["outage_dropped_packets"] += 1
            return None
        if self.random.random() < self.loss:
            self.stats["random_dropped_packets"] += 1
            return None
        return now + self.delay + self.random.uniform(-self.jitter, self.jitter)


class DatagramSide(asyncio.DatagramProtocol):
    def __init__(self, proxy: "FaultProxy", direction: str):
        self.proxy, self.direction = proxy, direction

    def connection_made(self, transport):
        if self.direction == "up":
            self.proxy.listener = transport
        else:
            self.proxy.upstream = transport

    def datagram_received(self, data, address):
        self.proxy.receive(self.direction, data, address)

    def error_received(self, error):
        self.proxy.errors.append({"direction": self.direction, "error": type(error).__name__ + ": " + str(error),
                                  "monotonic": time.monotonic(), "proxy_closed": self.proxy.closed})


class FaultProxy:
    MAX_PACKETS = 512
    MAX_BYTES = 4 * 1024 * 1024

    def __init__(self, slot: int, seed: int, delay_ms: float, jitter_ms: float, loss: float):
        self.slot = slot
        self.policies = {direction: FaultPolicy(seed + slot * 1009 + index * 65537, delay_ms, jitter_ms, loss)
                         for index, direction in enumerate(("up", "down"))}
        self.listener = self.upstream = None
        self.client_address = None
        self.queue = []
        self.sequence = 0
        self.queued_bytes = self.maximum_bytes = self.maximum_packets = 0
        self.errors = []
        self.closed = False
        self.events = []
        self._task = None

    async def open(self, port: int, host_port: int):
        loop = asyncio.get_running_loop()
        await loop.create_datagram_endpoint(lambda: DatagramSide(self, "up"), local_addr=("127.0.0.1", port))
        try:
            await loop.create_datagram_endpoint(lambda: DatagramSide(self, "down"), remote_addr=("127.0.0.1", host_port))
        except BaseException:
            self.listener.close()
            raise
        self._task = asyncio.create_task(self.drain())

    def receive(self, direction: str, data: bytes, address):
        if self.closed:
            return
        if direction == "up":
            if address[0] != "127.0.0.1":
                self.policies[direction].stats["foreign_source_dropped_packets"] += 1
                return
            self.client_address = address
        elif self.client_address is None:
            return
        policy = self.policies[direction]
        at = policy.schedule(time.monotonic(), len(data))
        if at is None:
            return
        if len(self.queue) >= self.MAX_PACKETS or self.queued_bytes + len(data) > self.MAX_BYTES:
            policy.stats["queue_limit_dropped_packets"] += 1
            return
        self.sequence += 1
        heapq.heappush(self.queue, (at, self.sequence, direction, bytes(data), self.client_address))
        self.queued_bytes += len(data)
        self.maximum_bytes = max(self.maximum_bytes, self.queued_bytes)
        self.maximum_packets = max(self.maximum_packets, len(self.queue))

    async def drain(self):
        while not self.closed:
            now = time.monotonic()
            while self.queue and self.queue[0][0] <= now:
                _, _, direction, data, address = heapq.heappop(self.queue)
                self.queued_bytes -= len(data)
                policy = self.policies[direction]
                # A cut drops datagrams that were already in flight too.
                if now < policy.blocked_until:
                    policy.stats["inflight_outage_dropped_packets"] += 1
                    continue
                if direction == "up":
                    self.upstream.sendto(data)
                else:
                    self.listener.sendto(data, address)
                policy.stats["forwarded_packets"] += 1
                policy.stats["forwarded_bytes"] += len(data)
            await asyncio.sleep(.001)

    def outage(self, seconds: float, label: str):
        if not math.isfinite(seconds) or seconds < 0:
            raise ValueError("Outage must be finite and nonnegative")
        now = time.monotonic()
        for policy in self.policies.values():
            policy.blocked_until = now + seconds
        self.events.append({"label": label, "started_monotonic": now, "duration_seconds": seconds})

    def report(self):
        return {"slot": self.slot, "max_queued_packets": self.maximum_packets, "max_queued_bytes": self.maximum_bytes,
                "queue_packet_limit": self.MAX_PACKETS, "queue_byte_limit": self.MAX_BYTES,
                "remaining_packets": len(self.queue), "directions": {key: dict(policy.stats) for key, policy in self.policies.items()},
                "events": self.events, "errors": self.errors}

    async def close(self):
        self.closed = True
        if self._task is not None:
            await self._task
        for transport in (self.listener, self.upstream):
            if transport is not None:
                transport.close()
        self.queue.clear()
        self.queued_bytes = 0


def publish(prefix: Path, stage: str, value=None):
    destination = Path(str(prefix) + "." + stage + ".json")
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(json.dumps(value or {"ready": True}) + "\n")
    temporary.replace(destination)


async def marker(prefix: Path, stage: str, processes, timeout=40):
    destination = Path(str(prefix) + "." + stage + ".json")
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if destination.exists():
            return json.loads(destination.read_text())
        if any(process.poll() is not None for process in processes):
            raise RuntimeError("Peer exited before " + stage)
        await asyncio.sleep(.025)
    raise RuntimeError("Timeout waiting for " + stage)


def retire_all(processes):
    errors, leftovers = [], []
    for process in processes:
        try:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
            live = stability.live_process_group_members(process.pid)
            leftovers += live
            if live:
                os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, subprocess.TimeoutExpired, OSError) as error:
            errors.append({"pid": process.pid, "error": str(error)})
    return errors, leftovers


async def run_case(project, base, output, options, godot, repeat):
    prefix = base / "sync"
    processes, proxies = [], []
    relay = None
    relay_url = ""
    result = {"success": False, "repeat": repeat, "seed": options.seed + repeat - 1, "transport": "UDP/ENet via independent userspace datagram proxies" if options.transport == "enet" else "WebSocket over bounded opaque FIFO TCP stream proxies; no byte loss",
              "actual_os_processes": 4, "wan_acceptance": False, "error": None}
    began = time.monotonic()
    try:
        if options.transport == "relay":
            relay_url = "ws://127.0.0.1:" + str(options.port + 5) + "/ws"
            with (output / "relay.log").open("x") as log:
                relay = subprocess.Popen([sys.executable, "server/relay.py"], cwd=project,
                    env={**os.environ, "RELAY_HOST": "127.0.0.1", "PORT": str(options.port + 5), "SOCIAL_DB": ":memory:", "PYTHONDONTWRITEBYTECODE": "1"},
                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if relay.poll() is not None:
                    raise RuntimeError("Local relay exited during startup")
                try:
                    reader, writer = await asyncio.open_connection("127.0.0.1", options.port + 5)
                    writer.write(b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                    await writer.drain()
                    response = await asyncio.wait_for(reader.read(4096), 1)
                    writer.close()
                    await writer.wait_closed()
                    if response.startswith(b"HTTP/1.1 200"):
                        break
                except (OSError, asyncio.TimeoutError):
                    pass
                await asyncio.sleep(.05)
            else:
                raise RuntimeError("Local relay health did not become ready")
        for slot in (2, 3, 4):
            proxy = (FaultProxy(slot, result["seed"], options.delay_ms, options.jitter_ms, options.loss) if options.transport == "enet" else
                     StreamFaultProxy(slot, result["seed"], options.delay_ms, options.jitter_ms))
            proxies.append(proxy)
            await proxy.open(options.port + slot, options.port if options.transport == "enet" else options.port + 5)
        for slot in range(1, 5):
            environment = stability.private_environment(base / ("profile" + str(slot)), godot)
            environment.update({"LASTSHIFT_GAMEPLAY_ROLE": "host" if slot == 1 else "guest" + str(slot),
                                "LASTSHIFT_PARTY_SLOT": str(slot), "LASTSHIFT_GAMEPLAY_PATH": str(prefix),
                                "LASTSHIFT_TEST_PORT": str(options.port), "LASTSHIFT_TEST_DISCOVERY_PORT": str(options.port + 1),
                                "BUNKERCREW_IMPAIRMENT_PROXY_PORT": str(options.port + slot),
                                "BUNKERCREW_IMPAIRMENT_RELAY_URL": relay_url if slot == 1 or not relay_url else "ws://127.0.0.1:" + str(options.port + slot) + "/ws",
                                "BUNKERCREW_IMPAIRMENT_PHASE_SECONDS": str(options.phase_seconds)})
            command = [godot, "--headless", "--debug", "--audio-driver", "Dummy", "--path", str(project), "--script", FIXTURE,
                       "--", "--no-profile-save", "--no-upnp"]
            with (output / ("slot" + str(slot) + ".log")).open("x") as log:
                process = subprocess.Popen(command, cwd=project, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            processes.append(process)
            joined = await marker(prefix, "room" if slot == 1 else "joined" + str(slot), processes)
            if slot > 1 and joined["player_id"] != slot:
                raise RuntimeError("Join order does not match authenticated ownership")
        for slot in range(1, 5):
            await marker(prefix, "started" + str(slot), processes)
        publish(prefix, "phase_run")
        await asyncio.sleep(3)
        proxies[0].outage(.5, "short-burst-guest2")
        await asyncio.sleep(4)
        proxies[1].outage(2, "short-burst-guest3")
        for slot in range(1, 5):
            await marker(prefix, "phase_done" + str(slot), processes, 35)
        await marker(prefix, "phase_verified", processes)
        publish(prefix, "outage_run")
        cut_at = time.monotonic()
        proxies[1].outage(7, "silent-cut-guest3")
        detection = await marker(prefix, "cut_detected", processes, 12)
        result["disconnect_detection_seconds"] = time.monotonic() - cut_at
        if not 3.5 <= result["disconnect_detection_seconds"] <= 7.5:
            raise RuntimeError("Silent-loss detection outside actual five-second deadline tolerance")
        result["cut_detected"] = detection
        for slot in range(1, 5):
            await marker(prefix, "recovered" + str(slot), processes, 35)
        result["recovery_from_cut_seconds"] = time.monotonic() - cut_at
        publish(prefix, "pause_run")
        for slot in range(1, 5):
            await marker(prefix, "paused" + str(slot), processes)
        publish(prefix, "resume_run")
        for slot in range(1, 5):
            await marker(prefix, "resumed" + str(slot), processes)
        publish(prefix, "post_run")
        for slot in range(1, 5):
            await marker(prefix, "post_done" + str(slot), processes)
        await marker(prefix, "post_verified", processes)
        # Reports are written after each peer's final queue/state checks. Keep
        # all four sockets alive until forwarding has retired: otherwise a
        # fast host exits while delayed UDP datagrams still target its port,
        # producing real ICMP connection-refused errors from fixture teardown.
        # Errors during the active network test are never waived or discarded.
        for slot in range(1, 5):
            await marker(prefix, "report" + str(slot), processes)
        for proxy in proxies:
            await proxy.close()
        result["forwarding_retired_before_peer_exit"] = True
        publish(prefix, "finish_run")
        until = time.monotonic() + 15
        while any(process.poll() is None for process in processes) and time.monotonic() < until:
            await asyncio.sleep(.05)
        peers = []
        for slot, process in enumerate(processes, 1):
            text = (output / ("slot" + str(slot) + ".log")).read_text()
            if process.poll() != 0 or stability.DIAGNOSTIC.search(text) or "NETWORK_IMPAIRMENT_PASS" not in text:
                raise RuntimeError("Actual peer failed: slot" + str(slot))
            peer = json.loads(Path(str(prefix) + ".report" + str(slot) + ".json").read_text())
            if peer["failures"] or peer["microphone_open"] or peer["network_error"]:
                raise RuntimeError("Failed peer report")
            peers.append(peer)
        for proxy in proxies:
            stats = proxy.report()
            for direction in stats["directions"].values():
                if options.transport == "enet":
                    if direction.get("queue_limit_dropped_packets", 0) or direction.get("forwarded_packets", 0) < 10:
                        raise RuntimeError("Fault proxy overflow/no forwarding invalidates the requested UDP profile")
                elif (direction["max_queued_chunks"] > proxy.MAX_QUEUE_CHUNKS or direction["max_buffered_bytes"] > proxy.MAX_DIRECTION_BYTES
                      or direction["bytes_forwarded"] < 100):
                    raise RuntimeError("TCP forwarding buffers exceed their declared bound or no real traffic forwarded")
        result["peers"] = peers
        result["success"] = True
    except Exception as error:
        result["error"] = type(error).__name__ + ": " + str(error)
    finally:
        result["elapsed_seconds"] = time.monotonic() - began
        for proxy in proxies:
            result.setdefault("proxies", []).append(proxy.report())
            await proxy.close()
        result["cleanup_errors"], result["leftover_pids"] = retire_all(processes)
        if relay is not None:
            errors, leftovers = retire_all([relay])
            result["cleanup_errors"] += errors
            result["leftover_pids"] += leftovers
        if result["cleanup_errors"] or result["leftover_pids"] or any(proxy.errors for proxy in proxies):
            result["success"] = False
        for path in base.glob("sync.*.json"):
            shutil.copy2(path, output / path.name)
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--transport", choices=("enet", "relay"), default="enet")
    parser.add_argument("--seed", type=int, default=50121)
    parser.add_argument("--port", type=int, default=25331)
    parser.add_argument("--delay-ms", type=float, default=75)
    parser.add_argument("--jitter-ms", type=float, default=15)
    parser.add_argument("--loss", type=float, default=.01)
    parser.add_argument("--phase-seconds", type=float, default=12)
    options = parser.parse_args()
    if options.runs < 1 or not 1024 <= options.port <= 65529 or not math.isfinite(options.phase_seconds) or options.phase_seconds < 12:
        parser.error("Require runs >=1, phase >=12 seconds and four unprivileged ports")
    try:
        FaultPolicy(options.seed, options.delay_ms, options.jitter_ms, options.loss)
    except ValueError as error:
        parser.error(str(error))
    godot = shutil.which(options.godot)
    if not godot:
        parser.error("Godot not found")
    godot = str(Path(godot).resolve())
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (options.output or ROOT / "artifacts" / ("network-impairment-" + stamp)).resolve()
    if output.is_relative_to(ROOT) and not output.is_relative_to(ROOT / "artifacts"):
        parser.error("Repository reports must be under artifacts/")
    output.mkdir(parents=True, exist_ok=False)
    report = {"success": False, "wan_acceptance": False, "profile_user_agreed": False, "transport": options.transport,
              "scope": "Four actual locally running games. UDP: per-datagram delay/jitter/loss on both directions including ENet ACKs and native reliable retransmission. WebSocket: independent bounded FIFO byte streams with latency/jitter and blackouts/backpressure; bytes are never individually discarded or reordered. Local fault injection is not two independent Internet connections, Windows or exported TLS-relay acceptance.",
              "profile": {"nominal_network_rtt_ms": options.delay_ms * 2, "rtt_jitter_bound_ms": options.jitter_ms * 2,
                          "random_loss_per_direction": options.loss if options.transport == "enet" else None, "stream_byte_loss": False,
                          "burst_blackout_seconds": [.5, 2], "silent_outage_seconds": 7,
                          "session_silence_deadline_seconds": 5, "reconnect_grace_seconds": 30,
                          "steady_workload_seconds": options.phase_seconds, "seed": options.seed, "runs": options.runs},
              "runs": [], "error": None}
    try:
        report["godot"] = subprocess.check_output([godot, "--version"], text=True).strip()
        if not report["godot"].startswith("4.7.2."):
            raise RuntimeError("Godot 4.7.2 required")
        source = options.project.resolve()
        manifest = stability.source_manifest(source)
        (output / "runtime-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
        report["fixture_sha256"] = {name: stability.digest(ROOT / name) for name in (FIXTURE, "tools/verify_network_impairment.py", "tools/network_stream_fault_proxy.py")}
        with tempfile.TemporaryDirectory(prefix="bunkercrew-network-impairment-") as folder:
            base = Path(folder)
            project = base / "project"
            stability.copy_snapshot(source, project, manifest)
            shutil.copy2(ROOT / FIXTURE, project / FIXTURE)
            imported = stability.run_check([godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), "--editor", "--recovery-mode", "--import", "--quit"], project,
                stability.private_environment(base / "import-profile", godot), output / "import.log", 120)
            report["import"] = imported
            if not imported["success"]:
                raise RuntimeError("Private import failed")
            frozen = stability.source_manifest(project)
            for repeat in range(1, options.runs + 1):
                case_base = base / ("run" + str(repeat))
                case_output = output / ("run" + str(repeat))
                case_base.mkdir()
                case_output.mkdir()
                result = asyncio.run(run_case(project, case_base, case_output, options, godot, repeat))
                report["runs"].append(result)
                if not result["success"]:
                    raise RuntimeError(result["error"] or "Cleanup/proxy failure")
            report["private_runtime_changed"] = stability.changed_files(frozen, stability.source_manifest(project))
            if report["private_runtime_changed"]:
                raise RuntimeError("Frozen runtime changed")
        report["fixture_changed"] = [name for name, digest in report["fixture_sha256"].items() if stability.digest(ROOT / name) != digest]
        if report["fixture_changed"]:
            raise RuntimeError("Fixture changed while running")
        report["success"] = True
    except Exception as error:
        report["error"] = type(error).__name__ + ": " + str(error)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"success": report["success"], "error": report["error"], "report": str(output / "report.json")}, indent=2))
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
