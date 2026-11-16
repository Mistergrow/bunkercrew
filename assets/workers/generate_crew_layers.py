#!/usr/bin/env python3
"""Author the follow-through layers of the eight crew identities (pass 6A-2).

The idle, hit, collapse and work keys let a worker's pack, bag, aerial and
hanging hair trail the body by a beat. That needs those parts as separate
pieces: the coat without its gear, the gear alone, the head without its
hanging hair and the hair alone, each turned for the near-upright attitudes,
plus the gear and hair swung one step behind (-1) and forward (+1).

No geometry is duplicated here. generate_character_workers.py stays the only
author: its torso() and head() drawing calls are recorded and split where the
gear and the hair end (both are drawn first, under the coat and the face),
then replayed. A swung variant replays the same calls bent about the part's
root: what hangs (braid, bob, satchel, bag, cable) trails below its root,
what springs up (Nora's tube, Levin's aerial) bends above it; rigid packs do
not bend and only shift as a whole at runtime. Turned like the turns sheet
(RotSprite). At rest, coat over gear and head over hair are the authored
pieces texel for texel (checked by tests/worker_identity_generator_test.py).

Rebuild: python3 assets/workers/generate_crew_layers.py (Pillow required).
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
import generate_character_workers as author

rig = author.rig
ROOT = Path(__file__).resolve().parent
LAYER_STEPS = 3
LAYER_ROWS = ("coat", "gear", "gear_back", "gear_forward", "head", "hair", "hair_back", "hair_forward")
SHOULDER, HIP, HEAD_AT = (0, -42), (0, -25), (1, -57)
# Swing fields in piece pixels (feet anchor rig.OX, rig.OY): root row, rows to
# full reach, reach in texels, and whether the part hangs (+1: trails below
# the root) or springs up (-1: bends above it). Missing: rigid, no bend.
HAIR_SWING = {
    "mara": (rig.OY + HEAD_AT[1] + 5, 18, 2, 1),
    "nora": (rig.OY + HEAD_AT[1] + 6, 8, 1, 1),
    "selma": (rig.OY + HEAD_AT[1] + 6, 8, 1, 1),
    "rika": (rig.OY + HEAD_AT[1] + 4, 6, 1, 1),
}
GEAR_SWING = {
    "mara": (rig.OY + SHOULDER[1] + 8, 8, 1, 1),
    "nora": (rig.OY + HIP[1] + 8, 31, 1, -1),
    "levin": (rig.OY + SHOULDER[1] + 6, 26, 2, -1),
    "selma": (rig.OY + SHOULDER[1] + 6, 2, 1, 1),
    "rika": (rig.OY + HIP[1] + 1, 4, 1, 1),
}


class Recorder:
    """Stands in for ImageDraw and keeps every primitive the author draws."""
    def __init__(self):
        self.calls = []

    def _keep(self, name, xy, **kwargs):
        self.calls.append((name, [tuple(point) for point in (xy if len(xy) != 4 or not isinstance(xy[0], (int, float)) else [xy[:2], xy[2:]])], kwargs))

    def polygon(self, xy, **kwargs): self._keep("polygon", xy, **kwargs)
    def line(self, xy, **kwargs): self._keep("line", xy, **kwargs)
    def rectangle(self, xy, **kwargs): self._keep("rectangle", xy, **kwargs)
    def ellipse(self, xy, **kwargs): self._keep("ellipse", xy, **kwargs)


def record(draw_piece):
    recorder = Recorder()
    draw_piece(recorder)
    return recorder.calls


def replay(calls):
    image = Image.new("RGBA", (rig.CELL, rig.CELL))
    draw = ImageDraw.Draw(image)
    for name, points, kwargs in calls:
        if name in ("rectangle", "ellipse"):
            getattr(draw, name)([points[0][0], points[0][1], points[1][0], points[1][1]], **kwargs)
        else:
            getattr(draw, name)(points, **kwargs)
    return image


def split(full, rest, label):
    """`full` draws a part first and then exactly the `rest`: return the part."""
    if full[len(full) - len(rest):] != rest:
        raise ValueError(f"{label}: the authored piece no longer draws its part first")
    return full[:len(full) - len(rest)]


def bend(calls, field, swing):
    """Replay `calls` bent by one swing step about the field's root row."""
    if not swing or field is None:
        return calls
    root, length, reach, direction = field

    def shift(y):
        along = (y - root) * direction / length
        return swing * round(reach * min(1.0, max(0.0, along)))

    bent = []
    for name, points, kwargs in calls:
        if name in ("rectangle", "ellipse"):
            dx = shift((points[0][1] + points[1][1]) / 2)
            bent.append((name, [(x + dx, y) for x, y in points], kwargs))
        elif name == "line" and len(points) == 2 and points[0][1] != points[1][1]:
            # Long straps and aerials bend along their length, not as a stick.
            (x0, y0), (x1, y1) = points
            pieces = max(1, abs(y1 - y0) // 4)
            chain = [(round(x0 + (x1 - x0) * i / pieces), round(y0 + (y1 - y0) * i / pieces)) for i in range(pieces + 1)]
            chain = [(x + shift(y), y) for x, y in chain]
            for start, end in zip(chain, chain[1:]):
                bent.append((name, [start, end], kwargs))
        else:
            bent.append((name, [(x + shift(y), y) for x, y in points], kwargs))
    return bent


def layer_pieces(identity):
    """The LAYER_ROWS pieces of one identity, each a full 112 px piece image."""
    rig.C = dict(author.BASE_PALETTE, **author.PROFILES[identity]["palette"])
    torso = record(lambda d: author.torso(d, SHOULDER, HIP, identity))
    coat = record(lambda d: author.torso(d, SHOULDER, HIP, identity, pack=False))
    gear = split(torso, coat, f"{identity} torso")
    head = record(lambda d: author.head(d, *HEAD_AT, identity))
    # The hanging hair is what head() draws before the face and headwear:
    # the same head with an identity that has no hanging hair shows where.
    face_start = _face_start(identity, head)
    hair, face = head[:face_start], head[face_start:]
    pieces = {"coat": replay(coat), "head": replay(face)}
    for prefix, part, field in (("gear", gear, GEAR_SWING.get(identity)), ("hair", hair, HAIR_SWING.get(identity))):
        pieces[prefix] = replay(part)
        pieces[f"{prefix}_back"] = replay(bend(part, field, -1))
        pieces[f"{prefix}_forward"] = replay(bend(part, field, 1))
    return pieces


# Number of primitives head() draws for the hanging hair before anything else:
# Mara's braid (outlined polygon, line, tie), the bob and the crop (outlined
# polygon, line). Validated against the recorded calls below.
HAIR_CALLS = {"mara": 4, "nora": 3, "selma": 3, "rika": 3}
HAIR_TONES = {"mara": "#322a29", "nora": "#372d2b", "selma": "#6a3e2c", "rika": "#312c2c"}


def _face_start(identity, head):
    count = HAIR_CALLS.get(identity, 0)
    if count and (head[0][0] != "polygon" or head[0][2].get("fill") != HAIR_TONES[identity]):
        raise ValueError(f"{identity}: head() no longer starts with its hanging hair")
    return count


def layer_sheet(pieces):
    columns = 2 * LAYER_STEPS + 1
    cell = author.TURN_CELL
    sheet = Image.new("RGBA", (cell * columns, cell * len(LAYER_ROWS)))
    for row, name in enumerate(LAYER_ROWS):
        prepared = author._Turnable(pieces[name], author.TURN_PIECES["head" if name.startswith("h") else "torso"])
        for index, step in enumerate(range(-LAYER_STEPS, LAYER_STEPS + 1)):
            sheet.alpha_composite(author.turned_piece(prepared, step), (index * cell, row * cell))
    return sheet


def main(output=None):
    destination = Path(output) if output is not None else ROOT
    destination.mkdir(parents=True, exist_ok=True)
    assets = {}
    for identity in author.IDS:
        name = f"{identity}_layers.png"
        layer_sheet(layer_pieces(identity)).save(destination / name)
        assets[name] = hashlib.sha256((destination / name).read_bytes()).hexdigest()
    notice = {
        "source": "generate_crew_layers.py",
        "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "author": "generate_character_workers.py",
        "author_sha256": hashlib.sha256((ROOT / "generate_character_workers.py").read_bytes()).hexdigest(),
        "method": "Follow-through layers: the canonical torso()/head() drawing calls are recorded, split where the gear and the hanging hair end, and replayed; swung variants replay the same calls bent one step about the part's root (hanging parts trail below it, Nora's tube and Levin's aerial bend above it, rigid packs unchanged). RotSprite-turned like the turns sheets. No new colour, no imported image.",
        "rows": list(LAYER_ROWS),
        "steps": [-LAYER_STEPS, LAYER_STEPS],
        "cell": author.TURN_CELL,
        "origin": list(author.TURN_ORIGIN),
        "hair_swing": {key: list(value) for key, value in HAIR_SWING.items()},
        "gear_swing": {key: list(value) for key, value in GEAR_SWING.items()},
        "sha256": assets,
        "license": author.LICENSE,
    }
    (destination / "crew_layers.source.json").write_text(json.dumps(notice, indent=2) + "\n")
    print(f"Authored follow-through layers for {len(assets)} crew identities")


if __name__ == "__main__":
    main()
