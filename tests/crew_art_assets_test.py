#!/usr/bin/env python3
"""Pass 6A-2 art assets: the logo lockup and the v2 crew busts are reproducible
from their constructions, pixel-clean, and keep their predecessors for
comparison. No asset is written (rebuilds go to a temporary folder)."""
from pathlib import Path
import hashlib
import importlib.util
import json
import tempfile
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
checks = 0


def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, PROJECT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def colours(image):
    data = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    return {pixel for pixel in data if pixel[3]}


def main():
    logo_tool = load("tools/build_bunkercrew_logo.py", "bunkercrew_logo")
    bust_tool = load("tools/build_crew_portraits.py", "crew_portraits")
    logo_dir = PROJECT / "assets/ui/logo"
    busts = PROJECT / "assets/workers/portraits"
    with tempfile.TemporaryDirectory(prefix="bunkercrew-crew-art-") as folder:
        out = Path(folder)
        logo_tool.main(output=out / "logo")
        for name in ("bunkercrew_logo_v1.png", "bunkercrew_logo_v1_small.png", "bunkercrew_logo_v1.source.json"):
            check((out / "logo" / name).read_bytes() == (logo_dir / name).read_bytes(), f"Logo construction reproduces {name}")
        bust_tool.main_v2(output=out / "busts")
        for name in ("portraits_v2.png", "portraits_v2.source.json"):
            check((out / "busts" / name).read_bytes() == (busts / name).read_bytes(), f"Bust construction reproduces {name}")
    title = Image.open(logo_dir / "bunkercrew_logo_v1.png").convert("RGBA")
    small = Image.open(logo_dir / "bunkercrew_logo_v1_small.png").convert("RGBA")
    for label, image in (("title", title), ("small", small)):
        check(set(image.getchannel("A").tobytes()) <= {0, 255}, f"The {label} lockup has hard alpha, no soft fringe")
        check(len(colours(image)) <= 24, f"The {label} lockup keeps a small authored palette")
        check(image.getchannel("A").getbbox() == (0, 0) + image.size, f"The {label} lockup is cropped to its art")
    check(small.width <= 160, "The small lockup reads at 1x within 160 px")
    check(title.width > small.width * 2 - 20 and title.height >= 48, "The title lockup is the large variant")
    notice = json.loads((logo_dir / "bunkercrew_logo_v1.source.json").read_text())
    check(notice["tool_sha256"] == sha(PROJECT / "tools/build_bunkercrew_logo.py"), "Logo provenance names its construction")
    check(all(notice["assets"][name]["sha256"] == sha(logo_dir / name) for name in notice["assets"]), "Logo provenance hashes match")
    v1 = Image.open(busts / "portraits_v1.png").convert("RGBA")
    v2 = Image.open(busts / "portraits_v2.png").convert("RGBA")
    check(v1.size == v2.size == (640, 80), "v2 keeps the 80 px cells of v1, which is kept for comparison")
    check(set(v2.getchannel("A").tobytes()) <= {0, 255}, "v2 busts have hard alpha")
    for index, identity in enumerate(bust_tool.ORDER):
        cell = v2.crop((index * 80, 0, index * 80 + 80, 80))
        cell_colours = colours(cell)
        check(len(cell_colours) <= 40, f"{identity} bust uses the sprite ramps, not noisy shading ({len(cell_colours)} colours)")
        sprite = Image.open(PROJECT / f"assets/workers/{identity}_head.png").convert("RGBA")
        torso = Image.open(PROJECT / f"assets/workers/{identity}_torso.png").convert("RGBA")
        sprite_colours = colours(sprite) | colours(torso)
        shared = len(cell_colours & sprite_colours) / max(1, len(cell_colours))
        check(shared >= 0.6, f"{identity} bust shares its sprite's colours ({shared:.0%})")
        # No dither speckle: count pixels sharing their colour with no neighbour.
        pixels = cell.load()
        orphans = 0
        for y in range(1, 79):
            for x in range(1, 79):
                p = pixels[x, y]
                if p[3] and all(pixels[x + dx, y + dy] != p for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))):
                    orphans += 1
        check(orphans <= 40, f"{identity} bust has clean clusters ({orphans} lone pixels)")
    notice = json.loads((busts / "portraits_v2.source.json").read_text())
    check(notice["sha256"] == sha(busts / "portraits_v2.png") and notice["tool_sha256"] == sha(PROJECT / "tools/build_crew_portraits.py"), "v2 provenance names its construction and hash")
    check(notice["geometry_sha256"] == sha(PROJECT / "assets/workers/generate_character_workers.py"), "v2 provenance names the sprite geometry it was drawn from")
    print(f"CREW ART ASSETS: {checks}/{checks} checks passed")


if __name__ == "__main__":
    main()
