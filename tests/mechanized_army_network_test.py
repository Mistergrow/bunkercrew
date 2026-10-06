#!/usr/bin/env python3
"""Reuse the isolated two-process ENet harness for the actual vehicle scenes."""
import os
from pathlib import Path

from ground_infantry_network_test import main

if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    os.environ["LASTSHIFT_INFANTRY_PEER"] = "tests/mechanized_army_network_peer.gd"
    os.environ.setdefault("LASTSHIFT_INFANTRY_OUTPUT", str(root / "artifacts/mechanized-army/validation"))
    os.environ.setdefault("LASTSHIFT_TEST_PORT", "24877")
    os.environ.setdefault("LASTSHIFT_TEST_DISCOVERY_PORT", "24878")
    main()
