#!/usr/bin/env python3
"""Real relay chat reconnect with monotonic and Godot frame clocks recorded."""
import argparse
import json
import os
import pathlib
import time

import network_chat_test as chat


def summarize(path):
    frames = []
    for line in path.read_text().splitlines():
        if line.startswith("NETWORK_CLOCK "):
            frames.append(json.loads(line.removeprefix("NETWORK_CLOCK ")))
    assert frames, f"Missing real clock records in {path}"
    wall = frames[-1]["wall_seconds"] - frames[0]["wall_seconds"]
    engine = frames[-1]["engine_elapsed"] - frames[0]["engine_elapsed"]
    network = frames[-1]["network_clock"] - frames[0]["network_clock"]
    reconnect = [f for f in frames if f["state"] == "reconnecting"]
    intervals = []
    reconnect_started = None
    for frame in frames:
        if frame["state"] == "reconnecting" and reconnect_started is None:
            reconnect_started = frame["wall_seconds"]
        elif frame["state"] != "reconnecting" and reconnect_started is not None:
            intervals.append(frame["wall_seconds"] - reconnect_started)
            reconnect_started = None
    return {"role": frames[-1]["role"], "sample_count": len(frames),
            "wall_elapsed": wall, "engine_elapsed": engine,
            "engine_minus_wall": engine - wall,
            "network_elapsed": network, "network_minus_wall": network - wall,
            "max_wall_frame": max(f["max_wall_delta"] for f in frames),
            "max_engine_frame": max(f["max_engine_delta"] for f in frames),
            "completed_reconnect_wall_intervals": intervals,
            "terminal_teardown_reconnect": reconnect_started is not None,
            "reconnect_samples": len(reconnect), "log": str(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=chat.ROOT / "artifacts/hardening-followup/network/relay-clock")
    parser.add_argument("--stall-ms", type=int, default=0)
    args = parser.parse_args()
    chat.OUTPUT = args.output
    if args.stall_ms:
        os.environ["BUNKERCREW_CLOCK_STALL_MS"] = str(min(max(args.stall_ms, 0), 4000))
    started = time.monotonic()
    passed = False
    try:
        chat.run_case(2, True, peer_script="tests/network_chat_clock_peer.gd")
        passed = True
    finally:
        case = chat.OUTPUT / "relay-2"
        clients = [summarize(case / f"{role}.log") for role in ["host", "guest2"]]
        report = {"success": passed, "seconds": time.monotonic() - started,
                  "clients": clients, "timeouts_changed": False,
                  "production_instrumentation": False, "injected_stall_ms": args.stall_ms}
        (chat.OUTPUT / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
