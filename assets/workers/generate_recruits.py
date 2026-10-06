#!/usr/bin/env python3
"""Compatibility entry point for Nora, Levin and Selma's original pixel rig.

The canonical eight-identity author now supplies their independent silhouettes.
No imported raster is read or edited, and existing motion files are preserved.
Historical source notices remain in identities/source-history-20261005.json.
"""
from pathlib import Path
import generate_character_workers as author

ROOT = Path(__file__).resolve().parent
rig = author.rig
IDS = ("nora", "levin", "selma")
PROFILES = {identity: author.PROFILES[identity] for identity in IDS}
MOTION = {identity: author.MOTION[identity] for identity in IDS}
# Retain the head/torso exports used by generate_locomotion_parts.py.
head = author.head
torso = author.torso
pose = author.character_pose


def main(output=None):
    author.main(IDS, output)


if __name__ == "__main__":
    main()
