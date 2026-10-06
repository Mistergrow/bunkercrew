"""Sample panorama extension colors offline; runtime never reads back the GPU."""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/environments/panorama_edges.json"


def main():
    catalog = json.loads((ROOT / "assets/environments/catalog.json").read_text())
    entries = list(catalog["environments"])
    if not any(entry["id"] == "sector07" for entry in entries):
        entries.insert(0, {"id": "sector07", "path": "res://assets/skyline.png"})
    result = {"generator": "tools/generate_panorama_edges.py", "environments": {}}
    for entry in entries:
        source = ROOT / entry["path"].removeprefix("res://")
        image = Image.open(source).convert("RGBA")
        sides = []
        for side in range(2):
            colors = []
            for band in range(17):
                samples = []
                for column in range(4):
                    u = .008 + column * .018
                    if side:
                        u = 1 - u
                    for row in range(3):
                        v = min(1, max(0, band / 16 + (row - 1) * .012))
                        samples.append(image.getpixel((int(u * (image.width - 1)), int(v * (image.height - 1)))))
                colors.append([sum(pixel[channel] for pixel in samples) / (12 * 255) for channel in range(4)])
            sides.append(colors)
        result["environments"][entry["id"]] = {
            "source": entry["path"], "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "colors": sides,
        }
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Sampled {len(entries)} panoramas into {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
