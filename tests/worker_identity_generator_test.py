#!/usr/bin/env python3
"""Check native identity geometry and reproducible authoring without writes to assets."""
from pathlib import Path
import hashlib
from itertools import combinations
import json
import sys
import tempfile
from PIL import Image, ImageChops

PROJECT = Path(__file__).resolve().parents[1]
ASSETS = PROJECT / "assets/workers"
sys.path.insert(0, str(ASSETS))
import generate_character_workers as author
import generate_recruits as recruits
import generate_solo_recruits as solo

PROTECTED = {
    "worker_1_body.png":"a64fe63e019777ddeeee90010e9011403b51d6afa030b3a2900e1e485419e072",
    "worker_1_arms.png":"323f50b33a489637df156b3ba90a6b1d16ccbde08b2feffa9f79c9af122e04bb",
    "worker_2_body.png":"4be1dddf0be9f844accc06d375139ff4fc883444cd6b8c5eb3230397afdd4bb5",
    "worker_2_arms.png":"323f50b33a489637df156b3ba90a6b1d16ccbde08b2feffa9f79c9af122e04bb",
    "identities/prompts.json":"918baf8447d62a4632593c720c4071809c5daf58fe6809f03fc4e1fd30a70c27",
    "character_motion_frames.json":"1d38b305b6f797680096cee069eaab11463e23a394004562e318d988187a5e03",
    "worker_frames.json":"5df3ad40627fdbb60806cd9cd05ca2f44a08160d978a6075412d45399ba489fa",
    "armor_anchors.json":"30de7a4022ec6edb8cd8e0ddbe46cf1b1adcca53445ae3e57ced44f05c4281a6",
}
checks = 0


def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_difference(a, b):
    histogram = ImageChops.difference(a.getchannel("A"), b.getchannel("A")).histogram()
    return sum(histogram[1:])


def main():
    catalog = json.loads((ASSETS / "character_visuals.json").read_text())
    check(tuple(catalog["identities"]) == author.IDS, "Catalog includes all eight in stable character order")
    check(catalog["visual_contract"]["view"] == "side and rear only", "Front view remains excluded")
    check(set(catalog["motion_profiles"]) == set(author.IDS), "No generator loses five character motion profiles")
    images = {identity:{} for identity in author.IDS}
    source_hash = sha(ASSETS / "generate_character_workers.py")
    history = json.loads((ASSETS / "identities/source-history-20261005.json").read_text())["sources"]
    for identity in author.IDS:
        notice = json.loads((ASSETS / f"{identity}.source.json").read_text())
        check(notice["source_sha256"] == source_hash, f"{identity} notice identifies the actual generator")
        check(notice["license"] == author.LICENSE, f"{identity} preserves Bunkercrew-only distribution")
        check(notice["previous_source_sha256"] == history[identity]["notice_sha256"], f"{identity} retains original provenance")
        check(notice["motion_frames_sha256"] == PROTECTED["character_motion_frames.json"], f"{identity} keeps all original trajectories")
        for piece in author.PARTS:
            name = f"{identity}_{piece}.png"
            image = Image.open(ASSETS / name).convert("RGBA")
            images[identity][piece] = image
            check(notice["sha256"][name] == sha(ASSETS / name), f"{name} matches its source notice")
            check(image.size == ((896,2128) if piece in ("body","arms") else (112,112)), f"{name} preserves rig dimensions")
            check(set(image.getchannel("A").tobytes()) <= {0,255}, f"{name} uses native opaque/transparent pixels without filtering")
        for row,(state,count) in enumerate(author.rig.STATES.items()):
            for frame in range(count):
                cell = images[identity]["body"].crop((frame*112,row*112,(frame+1)*112,(row+1)*112))
                bounds = cell.getbbox()
                check(bounds is not None and 0 < bounds[0] < bounds[2] < 112 and 0 < bounds[1] < bounds[3] < 112, f"{identity} {state} {frame}: body/head remain inside the original cell")
        for piece in ("head","back_head"):
            check(images[identity][piece].getbbox()[3] < 65, f"{identity} {piece} contains no old torso or limbs")
        for piece in ("torso","back_torso"):
            check(images[identity][piece].getbbox()[3] < 80, f"{identity} {piece} contains no old feet or cargo")
    minimums = {}
    for piece,threshold in (("head",80),("back_head",40),("torso",100),("back_torso",30)):
        scores=[]
        for left,right in combinations(author.IDS,2):
            difference = alpha_difference(images[left][piece],images[right][piece])
            scores.append(difference)
            check(difference >= threshold, f"{left}/{right} {piece}: silhouette differs in {difference} pixels, not just palette")
        minimums[piece] = min(scores)
    before = {name:sha(ASSETS/name) for name in PROTECTED}
    with tempfile.TemporaryDirectory(prefix="bunkercrew-identity-generator-") as folder:
        destination = Path(folder)
        author.main(output=destination)
        for identity in author.IDS:
            for piece in author.PARTS:
                name=f"{identity}_{piece}.png"
                check(sha(destination/name) == sha(ASSETS/name), f"Fresh source geometry reproduces {name}")
            name=f"{identity}.source.json"
            check((destination/name).read_bytes() == (ASSETS/name).read_bytes(), f"Reproducible {identity} provenance")
        check((destination/"character_visuals.json").read_bytes() == (ASSETS/"character_visuals.json").read_bytes(), "Rebuilding is catalog-idempotent")
        for wrapper,expected in ((recruits,recruits.IDS),(solo,solo.IDS)):
            target=destination/wrapper.__name__
            wrapper.main(output=target)
            check(len(list(target.glob("*.png"))) == len(expected)*6, f"{wrapper.__name__} writes only its own character sprites")
            check(set(json.loads((target/"character_visuals.json").read_text())["identities"]) == set(author.IDS), f"{wrapper.__name__} retains the eight-character catalog")
            for identity in expected:
                for piece in author.PARTS:
                    name=f"{identity}_{piece}.png"
                    check(sha(target/name) == sha(ASSETS/name), f"Compatibility entry point preserves current {name}")
        # The legacy back-piece generator imports these functions directly.
        check(recruits.head is author.head and recruits.torso is author.torso, "Back-piece entry point uses canonical new shapes")
    for name,expected in PROTECTED.items():
        check(before[name] == sha(ASSETS/name) == expected, f"Generator leaves protected original {name} unchanged")
    print(f"WORKER IDENTITY GENERATOR: {checks}/{checks} checks passed; minimum alpha differences {minimums}")


if __name__ == "__main__":
    main()
