#!/usr/bin/env python3
"""Actual relay close before polling must refuse each world handoff safely."""
import argparse
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path

import network_chat_test as room


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=room.ROOT / "artifacts/network-transition-transport")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []
    previous_phase = os.environ.get("BUNKERCREW_TRANSITION_PHASE")
    try:
        for phase in ["start", "restart", "expedition"]:
            os.environ["BUNKERCREW_TRANSITION_PHASE"] = phase
            room.OUTPUT = output / phase
            started = time.monotonic()
            try:
                room.run_case(2, True, peer_script="tests/network_transition_transport_peer.gd")
            except AssertionError as error:
                results.append({"phase": phase, "success": False, "seconds": time.monotonic() - started, "diagnosis": str(error)})
                break
            peers = []
            for role in ["host", "guest2"]:
                log = room.OUTPUT / "relay-2" / f"{role}.log"
                match = re.search(r"NETWORK_GAMEPLAY_PASS \w+ checks=(\d+) failures=0", log.read_text())
                assert match, f"Missing actual peer assertions: {log}"
                peers.append({"role": role, "checks": int(match.group(1)), "log": str(log.relative_to(output))})
            results.append({"phase": phase, "success": True, "seconds": time.monotonic() - started, "peers": peers})
    finally:
        if previous_phase is None:
            os.environ.pop("BUNKERCREW_TRANSITION_PHASE", None)
        else:
            os.environ["BUNKERCREW_TRANSITION_PHASE"] = previous_phase
    report = {
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "success": len(results) == 3 and all(result["success"] for result in results),
        "results": results,
        "explicit_assertions": sum(peer["checks"] for result in results for peer in result.get("peers", [])),
        "scope": "Two independent actual Godot clients per case; native host socket closes before Session polls; start, restart and departure refuse without mutations, then the same room recovers.",
    }
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["success"] else 1)


if __name__ == "__main__":
    main()
