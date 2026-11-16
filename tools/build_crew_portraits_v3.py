#!/usr/bin/env python3
"""Menu bust portraits v3: the v1 busts with a controlled palette.

v1 (tools/build_crew_portraits.py --v1) reduces the production references to
80 px busts but keeps 2,000-2,800 colours per bust, which reads as noisy,
semi-realistic shading next to the sprites (review 5, D21). v2 rebuilds the
busts from sprite geometry; it matches the sprites but loses most of the
portrait quality. v3 keeps the v1 drawing and limits every bust to its own
40-colour palette (max-coverage quantisation, no dither) with hard alpha, so
the shading falls into clean clusters like hand-placed pixel art.

Deterministic: same v1 in, same v3 out. Writes portraits_v3.png and its
.source.json next to the other versions; v1 and v2 stay unchanged.
"""
import hashlib
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
FOLDER = ROOT / "assets/workers/portraits"
SOURCE = FOLDER / "portraits_v1.png"
TARGET = FOLDER / "portraits_v3.png"
CELL = 80
COLOURS = 40


def sha(path: pathlib.Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def build() -> Image.Image:
	source = Image.open(SOURCE).convert("RGBA")
	width, height = source.size
	result = Image.new("RGBA", (width, height), (0, 0, 0, 0))
	for index in range(width // CELL):
		bust = source.crop((index * CELL, 0, (index + 1) * CELL, height))
		alpha = bust.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
		flat = bust.convert("RGB").quantize(colors=COLOURS, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE).convert("RGB")
		flat.putalpha(alpha)
		result.paste(flat, (index * CELL, 0))
	return result


def main() -> None:
	image = build()
	image.save(TARGET, optimize=True)
	notice = {
		"asset": TARGET.name,
		"tool": "tools/build_crew_portraits_v3.py",
		"tool_sha256": sha(pathlib.Path(__file__)),
		"source": SOURCE.name,
		"source_sha256": sha(SOURCE),
		"method": f"per-bust {COLOURS}-colour max-coverage palette, no dither, alpha thresholded at 128",
		"cell": CELL,
		"order": ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"],
		"sha256": sha(TARGET),
		"previous": "portraits_v1.png (detailed, 2,000+ colours) and portraits_v2.png (rebuilt from sprite geometry), both kept for comparison",
	}
	(FOLDER / "portraits_v3.source.json").write_text(json.dumps(notice, indent=2) + "\n")
	print(f"wrote {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
