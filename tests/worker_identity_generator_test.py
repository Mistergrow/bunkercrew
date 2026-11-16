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
import generate_tool_turns as tools
import generate_crew_layers as crew_layers
sys.path.insert(0, str(PROJECT / "tools"))
import bake_infantry_turns as infantry_turns

PROTECTED = {
    "worker_1_body.png":"a64fe63e019777ddeeee90010e9011403b51d6afa030b3a2900e1e485419e072",
    "worker_1_arms.png":"323f50b33a489637df156b3ba90a6b1d16ccbde08b2feffa9f79c9af122e04bb",
    "worker_2_body.png":"4be1dddf0be9f844accc06d375139ff4fc883444cd6b8c5eb3230397afdd4bb5",
    "worker_2_arms.png":"323f50b33a489637df156b3ba90a6b1d16ccbde08b2feffa9f79c9af122e04bb",
    # Publication copy: the three absolute home-directory "source" paths became
    # "local-archive:generated_images/..."; ids, files and prompts are unchanged.
    "identities/prompts.json":"9d1c8d60cb9c2fbb2177e3964f7a87d3914b02521f2870440a83049e8ce5f8eb",
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
    layer_notice = json.loads((ASSETS / "crew_layers.source.json").read_text())
    check(layer_notice["source_sha256"] == sha(ASSETS / "generate_crew_layers.py") and layer_notice["author_sha256"] == source_hash, "Follow-through layers identify their generator and the canonical author")
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
        # Turned pieces: every attitude is the authored piece re-drawn upright,
        # never a resampled colour; step 0 is the piece itself, texel for texel.
        name = f"{identity}_turns.png"
        turns = Image.open(ASSETS / name).convert("RGBA")
        check(notice["sha256"][name] == sha(ASSETS / name), f"{name} matches its source notice")
        check(turns.size == (author.TURN_CELL*author.TURN_STEPS, author.TURN_CELL*4), f"{name} holds four rows of turned pieces")
        check(set(turns.getchannel("A").tobytes()) <= {0,255}, f"{name} uses native opaque/transparent pixels without filtering")
        for row, piece in enumerate(("torso", "head")):
            origin = author.TURN_PIECES[piece]
            upright = Image.new("RGBA", (author.TURN_CELL, author.TURN_CELL))
            upright.alpha_composite(images[identity][piece].crop((origin[0]-author.TURN_ORIGIN[0], origin[1]-author.TURN_ORIGIN[1], origin[0]-author.TURN_ORIGIN[0]+author.TURN_CELL, origin[1]-author.TURN_ORIGIN[1]+author.TURN_CELL)))
            cell = turns.crop((0, row*author.TURN_CELL, author.TURN_CELL, (row+1)*author.TURN_CELL))
            check(ImageChops.difference(cell, upright).getbbox() is None, f"{identity} {piece} step 0 is the authored piece")
            source_colours = {pixel for pixel in images[identity][piece].getdata() if pixel[3]}
            sheet_row = turns.crop((0, row*author.TURN_CELL, turns.width, (row+1)*author.TURN_CELL))
            check({pixel for pixel in sheet_row.getdata() if pixel[3]} <= source_colours, f"{identity} turned {piece} adds no colour")
            for step in range(author.TURN_STEPS):
                bounds = turns.crop((step*author.TURN_CELL, row*author.TURN_CELL, (step+1)*author.TURN_CELL, (row+1)*author.TURN_CELL)).getbbox()
                check(bounds is not None and bounds[0] > 0 and bounds[1] > 0 and bounds[2] < author.TURN_CELL and bounds[3] < author.TURN_CELL, f"{identity} {piece} step {step} fits its cell")
        # Follow-through layers: coat over gear and head over hair at rest are
        # the authored pieces texel for texel; swung variants add no colour.
        name = f"{identity}_layers.png"
        layers = Image.open(ASSETS / name).convert("RGBA")
        cell = author.TURN_CELL
        check(layer_notice["sha256"][name] == sha(ASSETS / name), f"{name} matches its source notice")
        check(layers.size == (cell*(2*crew_layers.LAYER_STEPS+1), cell*len(crew_layers.LAYER_ROWS)), f"{name} holds every layer at every near-upright step")
        check(set(layers.getchannel("A").tobytes()) <= {0,255}, f"{name} uses native opaque/transparent pixels without filtering")
        for piece, under, over in (("torso", "gear", "coat"), ("head", "hair", "head")):
            upright = turns.crop((0, (0 if piece == "torso" else 1)*cell, cell, (1 if piece == "torso" else 2)*cell))
            composite = Image.new("RGBA", (cell, cell))
            for layer in (under, over):
                row = crew_layers.LAYER_ROWS.index(layer)
                composite.alpha_composite(layers.crop((crew_layers.LAYER_STEPS*cell, row*cell, (crew_layers.LAYER_STEPS+1)*cell, (row+1)*cell)))
            check(ImageChops.difference(composite, upright).getbbox() is None, f"{identity} {piece} layers at rest are the authored piece")
            # Hair hidden under headwear (Rika's crop) may hold tones the
            # finished head never shows; turning and swinging add none.
            source_colours = {pixel for pixel in images[identity][piece].getdata() if pixel[3]}
            rest = layers.crop((crew_layers.LAYER_STEPS*cell, crew_layers.LAYER_ROWS.index(under)*cell, (crew_layers.LAYER_STEPS+1)*cell, (crew_layers.LAYER_ROWS.index(under)+1)*cell))
            source_colours |= {pixel for pixel in rest.getdata() if pixel[3]}
            for row, layer in enumerate(crew_layers.LAYER_ROWS):
                if layer.startswith(under) or layer == over:
                    strip = layers.crop((0, row*cell, layers.width, (row+1)*cell))
                    check({pixel for pixel in strip.getdata() if pixel[3]} <= source_colours, f"{identity} {layer} layer adds no colour")
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
            name=f"{identity}_turns.png"
            check(sha(destination/name) == sha(ASSETS/name), f"Fresh source geometry reproduces {name}")
            name=f"{identity}.source.json"
            check((destination/name).read_bytes() == (ASSETS/name).read_bytes(), f"Reproducible {identity} provenance")
        check((destination/"character_visuals.json").read_bytes() == (ASSETS/"character_visuals.json").read_bytes(), "Rebuilding is catalog-idempotent")
        for wrapper,expected in ((recruits,recruits.IDS),(solo,solo.IDS)):
            target=destination/wrapper.__name__
            wrapper.main(output=target)
            check(len(list(target.glob("*.png"))) == len(expected)*(len(author.PARTS)+len(author.TURN_PARTS)), f"{wrapper.__name__} writes only its own character sprites")
            check(set(json.loads((target/"character_visuals.json").read_text())["identities"]) == set(author.IDS), f"{wrapper.__name__} retains the eight-character catalog")
            for identity in expected:
                for piece in author.PARTS:
                    name=f"{identity}_{piece}.png"
                    check(sha(target/name) == sha(ASSETS/name), f"Compatibility entry point preserves current {name}")
        crew_layers.main(output=destination)
        for identity in author.IDS:
            name=f"{identity}_layers.png"
            check(sha(destination/name) == sha(ASSETS/name), f"Fresh recorded geometry reproduces {name}")
        check((destination/"crew_layers.source.json").read_bytes() == (ASSETS/"crew_layers.source.json").read_bytes(), "Reproducible follow-through layer provenance")
        tools.main(output=destination)
        check(sha(destination/"tool_turns.png") == sha(ASSETS/"tool_turns.png"), "Fresh source geometry reproduces the pick and weapon attitudes")
        check((destination/"tool_turns.source.json").read_bytes() == (ASSETS/"tool_turns.source.json").read_bytes(), "Reproducible tool provenance")
        infantry_turns.main(output=destination)
        check(sha(destination/"infantry_turns_v1.png") == sha(PROJECT/"assets/enemies/infantry_turns_v1.png"), "Fresh RotSprite turns reproduce the infantry defeat attitudes")
        check((destination/"infantry_turns_v1.source.json").read_bytes() == (PROJECT/"assets/enemies/infantry_turns_v1.source.json").read_bytes(), "Reproducible infantry turn provenance")
        # The legacy back-piece generator imports these functions directly.
        check(recruits.head is author.head and recruits.torso is author.torso, "Back-piece entry point uses canonical new shapes")
    for name,expected in PROTECTED.items():
        check(before[name] == sha(ASSETS/name) == expected, f"Generator leaves protected original {name} unchanged")
    print(f"WORKER IDENTITY GENERATOR: {checks}/{checks} checks passed; minimum alpha differences {minimums}")


if __name__ == "__main__":
    main()
