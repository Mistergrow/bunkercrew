#!/usr/bin/env python3
"""Readability captures and the enemy-vs-background contrast measure.

Runs tests/threat_read_capture.gd (the visual-review driver plus a "read"
stage) on an isolated X display, then measures, per lineup strip, how well
the enemies separate from the ground behind them with the team read on and
off (actor_wet.gdshader `team`, BackdropGrade):
  edge   mean |luma inside - luma outside| over every enemy silhouette pixel
         pair (4-neighbours across the silhouette boundary);
  ring   |mean luma of the enemy pixels - mean luma of a 6 px ring around
         them| (the "enemy against its local background" figure);
  legible share of boundary pairs whose luma step is at least 0.12.
The enemy mask is the difference between the frame with and without the
enemies, so it works for every class without knowing its art.

  python3 tests/threat_read_capture.py --out artifacts/visual-pass2-read/measure [--display :78] [--software] [--perf] [--worlds]
Exit code 0 when every capture ran; the numbers are printed and written to
<out>/contrast.json. Needs Pillow and numpy.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent


def perf_shots(size):
    common = {"size": [1920, 1080], "locale": "de", "kind": "still", "frames": 1, "captures": False, "wall_seconds": 900}
    return [dict(common, id="read.perf.night", stage="read", method="perf", seed=7105, args={"environment": "ash_foundry", "seconds": 8.0})]


def shots(size):
    common = {"size": list(size), "locale": "de", "kind": "still", "frames": 1, "captures": False, "wall_seconds": 240}
    return [
        dict(common, id="read.lineup.night", stage="read", method="lineup", seed=7101, args={"environment": "ash_foundry", "zoom": 2.0}),
        dict(common, id="read.lineup.bright", stage="read", method="lineup", seed=7102, args={"environment": "frozen_rail_yard", "zoom": 2.0}),
        dict(common, id="read.hud_wave.night", stage="read", method="hud_wave", seed=7103, args={"environment": "ash_foundry", "zoom": 2.0, "seconds": 14}),
        dict(common, id="read.hud_wave.bright", stage="read", method="hud_wave", seed=7104, args={"environment": "frozen_rail_yard", "zoom": 1.0, "seconds": 18}),
    ]


WORLDS = ["sector07", "ash_foundry", "abandoned_harbor", "basalt_quarry", "overgrown_steelworks", "frozen_rail_yard", "iron_canyon",
          "flooded_power_station", "mountain_pass", "storm_dam", "sulfur_refinery", "radar_highlands", "buried_megafactory"]


def world_shots(size):
    """One lineup strip per environment: every world's backdrop behind the same machines."""
    common = {"size": list(size), "locale": "de", "kind": "still", "frames": 1, "captures": False, "wall_seconds": 240}
    return [dict(common, id=f"read.world.{world}", stage="read", method="lineup", seed=7200 + index,
                 args={"environment": world, "zoom": 1.5, "strips": 1}) for index, world in enumerate(WORLDS)]


def render(out, display, software, size, chosen, mobile=False):
    out.mkdir(parents=True, exist_ok=True)
    shot_file = out / "shots.json"
    shot_file.write_text(json.dumps(chosen), encoding="utf-8")
    env = dict(os.environ)
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("__GLX_VENDOR_LIBRARY_NAME", None)
    env["DISPLAY"] = display
    env["BUNKERCREW_SOCIAL_DB"] = ":memory:"
    if not software:
        env["__GLX_VENDOR_LIBRARY_NAME"] = "nvidia"
    with tempfile.TemporaryDirectory(prefix="threat-read-") as profile:
        env["XDG_DATA_HOME"] = profile
        renderer = ["--rendering-method", "mobile", "--rendering-driver", "vulkan"] if mobile else []
        command = [os.environ.get("GODOT", "godot"), "--audio-driver", "Dummy", "--fixed-fps", "60"] + renderer + ["--path", str(PROJECT),
                   "--script", "tests/threat_read_capture.gd", "--", "--no-profile-save", "--no-upnp",
                   f"--out={out}", f"--shots={shot_file}", "--results=results.jsonl"]
        with (out / "godot.log").open("w") as log:
            result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1500)
    rows = [json.loads(line) for line in (out / "results.jsonl").read_text().splitlines() if line.strip()]
    ended = [row for row in rows if row.get("event") == "end"]
    return result.returncode, ended


def luma(image):
    import numpy as np
    array = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    return array[..., 0] * 0.2126 + array[..., 1] * 0.7152 + array[..., 2] * 0.0722


def enemy_mask(pairs):
    """Pixels that change when the enemies are hidden, in any of the pairs."""
    import numpy as np
    from PIL import Image
    mask = None
    for frame, background in pairs:
        a = np.asarray(Image.open(frame).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(background).convert("RGB"), dtype=np.int16)
        changed = np.abs(a - b).sum(axis=2) > 24
        mask = changed if mask is None else (mask | changed)
    return mask


def measure(frame, mask):
    import numpy as np
    from PIL import Image
    if mask is None or mask.sum() < 50:
        return None
    y = luma(Image.open(frame))
    steps = []
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        # an enemy pixel whose neighbour at (y-dy, x-dx) is background
        inside = mask & ~np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
        neighbour = np.roll(np.roll(y, dy, axis=0), dx, axis=1)
        steps.append(np.abs(y[inside] - neighbour[inside]))
    steps = np.concatenate(steps)
    grown = mask.copy()
    for _ in range(6):
        grown = grown | np.roll(grown, 1, 0) | np.roll(grown, -1, 0) | np.roll(grown, 1, 1) | np.roll(grown, -1, 1)
    ring = grown & ~mask
    return {"pixels": int(mask.sum()), "edge": float(steps.mean()), "legible": float((steps >= 0.12).mean()),
            "ring": float(abs(y[mask].mean() - y[ring].mean())), "enemy_luma": float(y[mask].mean()), "ring_luma": float(y[ring].mean())}


def summarize(out, ended):
    report = {}
    for row in ended:
        if not (row["id"].startswith("read.lineup") or row["id"].startswith("read.world")):
            continue
        strips = int(row.get("strips", 0))
        totals = {"on": [], "off": []}
        for index in range(strips):
            pairs = [(out / f"{row['id']}.s{index}.{state}.png", out / f"{row['id']}.s{index}.bg_{state}.png") for state in ("on", "off")]
            if not all(a.exists() and b.exists() for a, b in pairs):
                continue
            # One silhouette for both states: the read recolours pixels inside
            # it; it never adds or removes any.
            mask = enemy_mask(pairs)
            for state, (frame, _background) in zip(("on", "off"), pairs):
                value = measure(frame, mask)
                if value:
                    totals[state].append(value)
        entry = {}
        for state, values in totals.items():
            if not values:
                continue
            weight = sum(v["pixels"] for v in values)
            entry[state] = {key: round(sum(v[key] * v["pixels"] for v in values) / weight, 4) for key in ("edge", "legible", "ring", "enemy_luma", "ring_luma")}
            entry[state]["pixels"] = weight
        report[row["id"]] = entry
    (out / "contrast.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--display", default=":78")
    parser.add_argument("--software", action="store_true")
    parser.add_argument("--mobile", action="store_true", help="Vulkan Forward Mobile instead of the project's Compatibility renderer")
    parser.add_argument("--size", default="1920x1080")
    parser.add_argument("--measure-only", action="store_true")
    parser.add_argument("--ids", default="", help="comma-separated shot ids to render (default: all)")
    parser.add_argument("--perf", action="store_true", help="frame time of a four-player wave with the read on/off instead of the captures")
    parser.add_argument("--worlds", action="store_true", help="one lineup strip in each of the 13 environments instead of the default shots")
    args = parser.parse_args()
    out = (PROJECT / args.out).resolve() if not os.path.isabs(args.out) else Path(args.out)
    size = tuple(int(v) for v in args.size.split("x"))
    chosen = perf_shots(size) if args.perf else (world_shots(size) if args.worlds else shots(size))
    if args.ids:
        wanted = [part.strip() for part in args.ids.split(",") if part.strip()]
        chosen = [shot for shot in chosen if shot["id"] in wanted]
    if args.perf:
        code, ended = render(out, args.display, args.software, size, chosen, args.mobile)
        for row in ended:
            print(row["id"], row.get("status"), row.get("notes"))
            for key in ("perf_on", "perf_no_overlay", "perf_off", "perf_on_again"):
                print(" ", key, row.get(key))
        return 0 if code == 0 and all(row.get("status") == "ok" for row in ended) and ended else 1
    if args.measure_only:
        ended = [json.loads(line) for line in (out / "results.jsonl").read_text().splitlines() if '"end"' in line]
        code = 0
    else:
        code, ended = render(out, args.display, args.software, size, chosen, args.mobile)
    failed = [row for row in ended if row.get("status") != "ok"]
    report = summarize(out, ended)
    print(json.dumps(report, indent=2))
    for row in failed:
        print("FAILED", row["id"], row.get("reason"), file=sys.stderr)
    return 0 if code == 0 and not failed and len(ended) == len(chosen) else 1


if __name__ == "__main__":
    sys.exit(main())
