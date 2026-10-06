"""Copy built-in generated plates without altering pixels; record provenance."""
from pathlib import Path
import hashlib
import json
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "artifacts/all-level-layers/generation.json"


def install() -> None:
    jobs = json.loads(MANIFEST.read_text())
    for job in jobs:
        source = Path(job["original_generation_path"])
        target = ROOT / job["destination"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != source.read_bytes():
            shutil.copy2(source, target)
        with Image.open(target) as image:
            alpha = image.getchannel("A") if "A" in image.getbands() else None
            extrema = list(alpha.getextrema()) if alpha else None
            if job["transparent_background"] and extrema != [0, 255]:
                raise ValueError(f"Missing alpha cutout: {target}")
            if not job["transparent_background"] and alpha and extrema[0] != 255:
                raise ValueError(f"Sky must be opaque: {target}")
            if image.width < 1600 or image.height < 900 or abs(image.width / image.height - 1672 / 941) > .003:
                raise ValueError(f"Mismatched plate size: {target}: {image.size}")
            metadata = {
                "generator": "built-in image_gen.imagegen",
                "prompt": job["prompt"],
                "reference": str(Path(job["reference"]).relative_to(ROOT)),
                "reference_sha256": hashlib.sha256(Path(job["reference"]).read_bytes()).hexdigest(),
                "original_generation_path": str(source),
                "size": list(image.size),
                "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                "transparent_background": job["transparent_background"],
                "alpha_extrema": extrema,
                "usage": "Bunkercrew gameplay depth plate. Original generated pixels and alpha preserved.",
            }
        target.with_suffix(".source.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Installed and validated {len(jobs)} generated depth plates")


if __name__ == "__main__":
    install()
