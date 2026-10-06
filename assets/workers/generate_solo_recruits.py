#!/usr/bin/env python3
"""Compatibility entry point for Oskar and Rika's original source geometry.

Only these twelve sprites and notices are written. The all-eight catalog and
original 110-frame trajectories remain intact; no existing image is edited.
Historical source and license notices are preserved alongside the author.
"""
from pathlib import Path
import generate_character_workers as author

ROOT = Path(__file__).resolve().parent
rig = author.rig
IDS = ("oskar", "rika")
PROFILES = {identity: author.PROFILES[identity] for identity in IDS}
MOTION = {identity: author.MOTION[identity] for identity in IDS}
LICENSE = author.LICENSE
head = author.head
torso = author.torso
pose = author.character_pose


def main(output=None):
    author.main(IDS, output)


if __name__ == "__main__":
    main()
