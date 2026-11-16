#!/usr/bin/env python3
"""Render the fixed visual-review shot list of the real game, or compare two renders.

Render (every process: isolated profile, timeout, never the desktop display):
    python3 tools/visual_review.py --out artifacts/visual-review/<label>
        [--project PATH] [--only 'ui.*,world.*.wide'] [--size 1920x1080] [--locale de|en]

Compare two finished renders shot by shot (left: first, right: second):
    python3 tools/visual_review.py --compare DIR_A DIR_B --out DIR [--labels baseline pass-1]

The shot list itself comes from tests/visual_review_shots.gd, which reads the
game's catalogs. index.json describes every shot; index.html is a contact sheet.
"""
import argparse
import datetime
import fnmatch
import html
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # contact sheets and comparisons need Pillow; rendering does not
    Image = None

SCRIPT = "tests/visual_review_capture.gd"
SHOT_SECONDS = 150
STYLE = (":root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#10161a;color:#dcdccb;font:15px/1.5 system-ui,sans-serif}"
         "main{max-width:2200px;margin:auto;padding:24px}h1{font-size:26px;margin:0 0 6px}h2{font-size:18px;margin:34px 0 10px;border-bottom:1px solid #2c3a36;padding-bottom:6px}"
         "p,li{color:#a4a593}a{color:#d9ac60}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:18px}.wide{grid-template-columns:1fr}"
         "figure{margin:0;background:#161f23;padding:8px}img{display:block;width:100%;height:auto;image-rendering:auto}figcaption{font-size:13px;padding-top:6px}"
         "code{color:#c9d2b4}.bad{color:#e0705c}table{border-collapse:collapse}td,th{padding:4px 12px;border-bottom:1px solid #2c3a36;text-align:left}")


def fail(message):
    raise SystemExit("visual_review: " + message)


def environment(display, renderer, profile, extra=None):
    env = dict(os.environ)
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("__GLX_VENDOR_LIBRARY_NAME", None)
    env["DISPLAY"] = display
    env["XDG_DATA_HOME"] = profile
    env["BUNKERCREW_SOCIAL_DB"] = ":memory:"
    if renderer == "gpu":
        env["__GLX_VENDOR_LIBRARY_NAME"] = "nvidia"
    env.update(extra or {})
    return env


def godot_command(godot, project, headless, user_arguments, movie=None):
    command = [godot, "--audio-driver", "Dummy", "--fixed-fps", "60", "--path", str(project)]
    if movie:
        # The movie writer mixes audio in step with the simulation (needed for
        # music-driven motion); the recording itself is discarded.
        command += ["--write-movie", str(movie)]
    if headless:
        command.append("--headless")
    return command + ["--script", SCRIPT, "--", "--no-profile-save", "--no-upnp"] + user_arguments


def list_shots(args, work):
    target = work / "shots.json"
    command = godot_command(args.godot, args.project, True, [f"--list={target}", f"--size={args.size}", f"--locale={args.locale}"])
    with tempfile.TemporaryDirectory(prefix="visual-review-profile-") as profile, (work / "list.log").open("w") as log:
        env = environment(args.display, "software", profile)
        env.pop("DISPLAY", None)
        try:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
        except subprocess.TimeoutExpired:
            fail(f"listing the shots timed out; see {work / 'list.log'}")
    if not target.exists():
        fail(f"the project did not produce a shot list; see {work / 'list.log'}")
    return json.loads(target.read_text(encoding="utf-8"))


def selected(shots, patterns):
    if not patterns:
        return shots
    wanted = [p.strip() for p in patterns.split(",") if p.strip()]
    chosen = [s for s in shots if any(fnmatch.fnmatchcase(s["id"], p) for p in wanted)]
    pairs = {s.get("pair") for s in chosen if s.get("pair")}
    return [s for s in shots if s in chosen or (s.get("pair") in pairs and s.get("pair"))]


def launch(args, out, logs, name, shots, renderer="gpu", extra_env=None):
    """Start one bounded Godot process for these shots."""
    shot_file = logs / f"{name}.shots.json"
    shot_file.write_text(json.dumps(shots), encoding="utf-8")
    results = f"logs/{name}.jsonl"
    (out / results).unlink(missing_ok=True)
    profile = tempfile.mkdtemp(prefix="visual-review-profile-")
    log = (logs / f"{name}.log").open("w")
    movie = Path(profile) / "discarded.avi" if any(s.get("movie") for s in shots) else None
    command = godot_command(args.godot, args.project, False, [f"--out={out}", f"--shots={shot_file}", f"--results={results}"], movie)
    process = subprocess.Popen(command, env=environment(args.display, renderer, profile, extra_env), stdout=log, stderr=subprocess.STDOUT)
    budget = 90 + sum(int(s.get("wall_seconds", SHOT_SECONDS)) for s in shots)
    return {"process": process, "log": log, "log_path": logs / f"{name}.log", "results": out / results, "profile": profile, "deadline": time.monotonic() + budget, "shots": shots}


def finish(run):
    process = run["process"]
    timed_out = False
    try:
        process.wait(timeout=max(1.0, run["deadline"] - time.monotonic()))
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        process.wait()
    run["log"].close()
    shutil.rmtree(run["profile"], ignore_errors=True)
    begun, ended = [], {}
    if run["results"].exists():
        for line in run["results"].read_text(encoding="utf-8").splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("event") == "begin":
                begun.append(row["id"])
            elif row.get("event") == "end":
                ended[row["id"]] = row
    return begun, ended, timed_out, process.returncode


def log_findings(path):
    """Engine errors printed between a shot's begin and end markers."""
    findings, current = {}, None
    if not path.exists():
        return findings
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("VR BEGIN "):
            current = line[9:].strip()
        elif line.startswith("VR END "):
            current = None
        elif current and ("SCRIPT ERROR" in line or line.startswith("ERROR:")):
            findings.setdefault(current, []).append(line.strip()[:300])
    return findings


def collect(run, records, name):
    begun, ended, timed_out, code = finish(run)
    findings = log_findings(run["log_path"])
    remaining = []
    for shot in run["shots"]:
        identifier = shot["id"]
        if identifier in ended:
            records[identifier] = ended[identifier]
        elif identifier in begun:
            tail = run["log_path"].read_text(encoding="utf-8", errors="replace").splitlines()[-6:]
            reason = "the process timed out during this shot" if timed_out else f"the process ended during this shot (exit code {code})"
            records[identifier] = {"status": "failed", "reason": reason, "notes": [], "files": [], "frame_times": [], "log_tail": tail}
        else:
            remaining.append(shot)
            continue
        records[identifier]["log"] = f"logs/{name}.log"
        if identifier in findings:
            records[identifier]["log_errors"] = findings[identifier][:6]
            records[identifier]["log_error_count"] = len(findings[identifier])
    return remaining, bool(begun)


def render_batches(args, out, logs, shots, records):
    # A partial re-render (--only) keeps the earlier logs of the same folder.
    prefix = "rerun-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" if args.only else ""
    queue = [s for s in shots if not s.get("pair") and not s.get("renderer") and not s.get("movie")]
    queue += [[s] for s in shots if s.get("movie")]
    counter = 0
    while queue:
        if isinstance(queue[0], list):
            batch, queue = queue[0], queue[1:]
        else:
            count = next((i for i, s in enumerate(queue) if isinstance(s, list)), len(queue))
            batch, queue = queue[:min(args.batch, count)], queue[min(args.batch, count):]
        while batch:
            counter += 1
            name = f"{prefix}batch-{counter:03d}"
            print(f"[{name}] {len(batch)} shots: {batch[0]['id']} …", flush=True)
            batch, progressed = collect(launch(args, out, logs, name, batch), records, name)
            if batch and not progressed:
                for shot in batch:
                    records[shot["id"]] = {"status": "failed", "reason": "the process ended before the shot began", "notes": [], "files": [], "frame_times": [], "log": f"logs/{name}.log"}
                batch = []
    for shot in [s for s in shots if s.get("renderer")]:
        name = prefix + "probe-" + shot["id"].replace(".", "-")
        print(f"[{name}] frame-time probe ({shot['renderer']})", flush=True)
        collect(launch(args, out, logs, name, [shot], shot["renderer"]), records, name)
        if shot["id"] not in records:
            records[shot["id"]] = {"status": "failed", "reason": "the probe process ended before the shot began", "notes": [], "files": [], "frame_times": [], "log": f"logs/{name}.log"}
    pairs = {}
    for shot in shots:
        if shot.get("pair"):
            pairs.setdefault(shot["pair"], []).append(shot)
    for pair, members in pairs.items():
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        coordination = tempfile.mkdtemp(prefix="visual-review-pair-")
        extra = {"VR_LOBBY_PATH": str(Path(coordination) / "pair"), "VR_LOBBY_PORT": str(port)}
        print(f"[pair-{pair}] {len(members)} connected processes on UDP {port}", flush=True)
        runs = []
        for shot in sorted(members, key=lambda s: s["args"].get("role") != "host"):
            name = prefix + "pair-" + shot["id"].replace(".", "-")
            runs.append((name, shot, launch(args, out, logs, name, [shot], "gpu", extra)))
            time.sleep(1.5)
        for name, shot, run in runs:
            collect(run, records, name)
            if shot["id"] not in records:
                records[shot["id"]] = {"status": "failed", "reason": "the paired process ended before the shot began", "notes": [], "files": [], "frame_times": [], "log": f"logs/{name}.log"}
        shutil.rmtree(coordination, ignore_errors=True)


def sheet(out, entry, columns=4, cell=480):
    """One contact sheet per sequence, frames in reading order."""
    if Image is None or entry["kind"] != "sequence" or not entry["files"]:
        return ""
    frames = [Image.open(out / name).convert("RGB") for name in entry["files"]]
    ratio = frames[0].height / frames[0].width
    size = (cell, round(cell * ratio))
    rows = -(-len(frames) // columns)
    board = Image.new("RGB", (columns * size[0], rows * (size[1] + 18)), (16, 22, 26))
    draw = ImageDraw.Draw(board)
    for index, frame in enumerate(frames):
        at = ((index % columns) * size[0], (index // columns) * (size[1] + 18))
        board.paste(frame.resize(size, Image.LANCZOS), (at[0], at[1] + 18))
        stamp = entry["frame_times"][index] if index < len(entry["frame_times"]) else 0
        draw.text((at[0] + 6, at[1] + 3), f"f{index:02d}  t={stamp:.3f}s", fill=(220, 220, 203))
    name = entry["id"] + ".sheet.png"
    board.save(out / name)
    return name


def write_html(out, index):
    groups = {}
    for entry in index["shots"]:
        groups.setdefault(entry["group"], []).append(entry)
    parts = [f"<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Visual review · {html.escape(index['label'])}</title><style>{STYLE}</style><main>",
             f"<h1>Visual review · {html.escape(index['label'])}</h1>",
             f"<p>{len(index['shots'])} shots · {index['summary']['ok']} rendered · {index['summary']['failed']} failed · project <code>{html.escape(index['project'])}</code> at <code>{html.escape(index['revision'])}</code> · {html.escape(index['created'])} · <a href='index.json'>index.json</a></p>"]
    failed = [e for e in index["shots"] if e["status"] != "ok"]
    if failed:
        parts.append("<h2 class='bad'>Failed shots</h2><ul>" + "".join(f"<li><code>{html.escape(e['id'])}</code> — {html.escape(e['reason'])}</li>" for e in failed) + "</ul>")
    probes = [e for e in index["shots"] if e.get("performance")]
    if probes:
        parts.append("<h2>Frame time</h2><table><tr><th>shot</th><th>renderer</th><th>mean ms</th><th>median ms</th><th>95th percentile ms</th><th>99th percentile ms</th><th>max ms</th><th>first kill ms</th><th>peak draw calls</th></tr>")
        for e in probes:
            p = e["performance"]
            parts.append(f"<tr><td><code>{html.escape(e['id'])}</code></td><td>{html.escape(str(e.get('renderer', {}).get('adapter', '')))}</td><td>{p['mean_ms']}</td><td>{p['p50_ms']}</td><td>{p.get('p95_ms', '')}</td><td>{p['p99_ms']}</td><td>{p['max_ms']}</td><td>{(p.get('kills') or {}).get('first_kill_ms', '')}</td><td>{p['peak_draw_calls']}</td></tr>")
        parts.append("</table>")
    for group, entries in groups.items():
        sequence = any(e["kind"] == "sequence" for e in entries)
        parts.append(f"<h2>{html.escape(group)} · {len(entries)}</h2><div class='grid{' wide' if sequence else ''}'>")
        for e in entries:
            picture = e.get("sheet") or (e["files"][0] if e["files"] else "")
            image = f"<a href='{html.escape(picture)}'><img loading='lazy' src='{html.escape(picture)}' alt=''></a>" if picture else "<p class='bad'>no image</p>"
            notes = "".join(f"<br>{html.escape(n)}" for n in e.get("notes", []))
            status = "" if e["status"] == "ok" else f"<br><span class='bad'>FAILED: {html.escape(e['reason'])}</span>"
            parts.append(f"<figure>{image}<figcaption><code>{html.escape(e['id'])}</code> · {e['resolution'][0]}×{e['resolution'][1]} · {e['locale'].upper()} · {len(e['files'])} file(s)<br>{html.escape(e['title'])}{notes}{status}</figcaption></figure>")
        parts.append("</div>")
    parts.append("</main></html>")
    (out / "index.html").write_text("".join(parts), encoding="utf-8")


def revision(project):
    try:
        head = subprocess.run(["git", "-C", str(project), "rev-parse", "--short", "HEAD"], capture_output=True, text=True, timeout=20).stdout.strip()
        dirty = subprocess.run(["git", "-C", str(project), "status", "--porcelain", "--untracked-files=no"], capture_output=True, text=True, timeout=60).stdout.strip()
        return head + (" + uncommitted changes" if dirty else "") if head else "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def render(args):
    out = Path(args.out).resolve()
    logs = out / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    shots = list_shots(args, logs)
    chosen = selected(shots, args.only)
    if not chosen:
        fail("no shot matches --only " + str(args.only))
    if args.list:
        for shot in chosen:
            print(f"{shot['id']:44s} {shot['kind']:9s} {shot['frames']:3d}  {shot['title']}")
        print(f"{len(chosen)} shots")
        return 0
    records = {}
    started = time.monotonic()
    render_batches(args, out, logs, chosen, records)
    entries = []
    for shot in chosen:
        record = records.get(shot["id"], {"status": "failed", "reason": "not rendered", "notes": [], "files": [], "frame_times": []})
        entry = {"id": shot["id"], "group": shot["group"], "title": shot["title"], "kind": shot["kind"], "resolution": shot["size"], "locale": shot["locale"],
                 "expected_frames": shot["frames"], "seed": shot["seed"], "status": record["status"], "reason": record.get("reason", ""), "notes": record.get("notes", []),
                 "files": record.get("files", []), "frame_times": record.get("frame_times", []), "logical_size": record.get("logical", []), "renderer": record.get("renderer", {}),
                 "render_seconds": record.get("seconds", 0), "log": record.get("log", "")}
        for key in ("performance", "log_errors", "log_error_count", "log_tail"):
            if key in record:
                entry[key] = record[key]
        missing = [name for name in entry["files"] if not (out / name).exists()]
        if missing and entry["status"] == "ok":
            entry["status"], entry["reason"] = "failed", "files missing after the run: " + ", ".join(missing[:3])
        entry["sheet"] = sheet(out, entry)
        entries.append(entry)
    # A partial re-render keeps the earlier entries of the same output folder.
    previous = out / "index.json"
    if args.only and previous.exists():
        try:
            old = json.loads(previous.read_text(encoding="utf-8"))["shots"]
            fresh = {e["id"] for e in entries}
            order = [s["id"] for s in shots]
            entries = sorted(entries + [e for e in old if e["id"] not in fresh], key=lambda e: order.index(e["id"]) if e["id"] in order else len(order))
        except (json.JSONDecodeError, KeyError):
            pass
    by_group = {}
    for entry in entries:
        group = by_group.setdefault(entry["group"], {"shots": 0, "stills": 0, "sequences": 0, "images": 0, "failed": 0})
        group["shots"] += 1
        group["stills" if entry["kind"] == "still" else "sequences"] += 1
        group["images"] += len(entry["files"])
        group["failed"] += entry["status"] != "ok"
    earlier = {}
    if args.only and previous.exists():
        try:
            earlier = json.loads(previous.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            earlier = {}
    version = subprocess.run([args.godot, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    index = {"tool": "tools/visual_review.py", "label": out.name, "project": str(args.project), "revision": revision(args.project), "engine": version,
             "created": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "default_resolution": args.size, "default_locale": args.locale, "display": args.display,
             "simulation": "60 simulated frames per second (--fixed-fps 60); frame timestamps are simulated seconds", "command": " ".join(sys.argv),
             "render_seconds": round(time.monotonic() - started, 1),
             "reruns": earlier.get("reruns", []) + ([{"command": " ".join(sys.argv), "created": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "shots": [s["id"] for s in chosen]}] if args.only else []),
             "summary": {"shots": len(entries), "ok": sum(e["status"] == "ok" for e in entries), "failed": sum(e["status"] != "ok" for e in entries), "groups": by_group},
             "performance": {e["id"]: {**e["performance"], "adapter": e["renderer"].get("adapter", "")} for e in entries if e.get("performance")}, "shots": entries}
    if args.only and earlier:
        for key in ("command", "created", "render_seconds"):
            if key in earlier:
                index[key] = earlier[key]
    (out / "index.json").write_text(json.dumps(index, indent="\t", ensure_ascii=False), encoding="utf-8")
    write_html(out, index)
    print(f"{index['summary']['ok']}/{len(entries)} shots rendered, {index['summary']['failed']} failed · {out / 'index.html'}")
    for entry in entries:
        if entry["status"] != "ok":
            print(f"  FAILED {entry['id']}: {entry['reason']}")
    return 0


def compare(args):
    if Image is None:
        fail("comparison sheets need Pillow")
    first, second = (Path(p).resolve() for p in args.compare)
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    labels = args.labels or [first.name, second.name]
    indexes = [json.loads((folder / "index.json").read_text(encoding="utf-8")) for folder in (first, second)]
    right = {e["id"]: e for e in indexes[1]["shots"]}
    rows = []
    for a in indexes[0]["shots"]:
        b = right.get(a["id"])
        row = {"id": a["id"], "group": a["group"], "title": a["title"], "kind": a["kind"], "status": [a["status"], b["status"] if b else "absent"], "file": ""}
        pictures = []
        for folder, entry in ((first, a), (second, b)):
            name = (entry.get("sheet") or (entry["files"][0] if entry["files"] else "")) if entry else ""
            pictures.append(Image.open(folder / name).convert("RGB") if name and (folder / name).exists() else None)
        row["originals"] = [str(folder / ((entry.get("sheet") or (entry["files"][0] if entry["files"] else "")) if entry else "")) for folder, entry in ((first, a), (second, b))]
        if any(p is not None for p in pictures):
            width = 1280
            sized = []
            for picture in pictures:
                if picture is None:
                    sized.append(None)
                    continue
                sized.append(picture.resize((width, round(picture.height * width / picture.width)), Image.LANCZOS) if picture.width != width else picture)
            height = max(p.height for p in sized if p is not None)
            board = Image.new("RGB", (width * 2 + 12, height + 30), (16, 22, 26))
            draw = ImageDraw.Draw(board)
            for side, picture in enumerate(sized):
                x = side * (width + 12)
                draw.text((x + 8, 8), f"{labels[side]}  ·  {a['id']}" + ("" if row["status"][side] == "ok" else f"  ·  {row['status'][side].upper()}"), fill=(220, 220, 203))
                if picture is not None:
                    board.paste(picture, (x, 30))
            row["file"] = a["id"] + ".compare.png"
            board.save(out / row["file"])
        rows.append(row)
    summary = {"left": {"label": labels[0], "path": str(first), "revision": indexes[0].get("revision", "")}, "right": {"label": labels[1], "path": str(second), "revision": indexes[1].get("revision", "")},
               "performance": {labels[0]: indexes[0].get("performance", {}), labels[1]: indexes[1].get("performance", {})}, "shots": rows}
    (out / "index.json").write_text(json.dumps(summary, indent="\t", ensure_ascii=False), encoding="utf-8")
    parts = [f"<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Visual review · {html.escape(labels[0])} vs {html.escape(labels[1])}</title><style>{STYLE}</style><main>",
             f"<h1>{html.escape(labels[0])} (left) · {html.escape(labels[1])} (right)</h1><p>{len(rows)} shots, same id, same staging and seed. Left <code>{html.escape(str(first))}</code> at <code>{html.escape(indexes[0].get('revision', ''))}</code>; right <code>{html.escape(str(second))}</code> at <code>{html.escape(indexes[1].get('revision', ''))}</code>. <a href='index.json'>index.json</a></p>"]
    names = sorted(set(indexes[0].get("performance", {})) | set(indexes[1].get("performance", {})))
    if names:
        parts.append("<h2>Frame time (ms)</h2><table><tr><th>shot</th><th>side</th><th>adapter</th><th>mean</th><th>median</th><th>95th percentile</th><th>99th percentile</th><th>max</th><th>first kill</th><th>peak draw calls</th></tr>")
        for name in names:
            for side in (0, 1):
                p = indexes[side].get("performance", {}).get(name)
                if p:
                    parts.append(f"<tr><td><code>{html.escape(name)}</code></td><td>{html.escape(labels[side])}</td><td>{html.escape(str(p.get('adapter', '')))}</td><td>{p['mean_ms']}</td><td>{p['p50_ms']}</td><td>{p.get('p95_ms', '')}</td><td>{p['p99_ms']}</td><td>{p['max_ms']}</td><td>{(p.get('kills') or {}).get('first_kill_ms', '')}</td><td>{p['peak_draw_calls']}</td></tr>")
        parts.append("</table>")
    group = None
    for row in rows:
        if row["group"] != group:
            if group is not None:
                parts.append("</div>")
            group = row["group"]
            parts.append(f"<h2>{html.escape(group)}</h2><div class='grid wide'>")
        image = f"<a href='{html.escape(row['file'])}'><img loading='lazy' src='{html.escape(row['file'])}' alt=''></a>" if row["file"] else "<p class='bad'>no image on either side</p>"
        state = "" if row["status"] == ["ok", "ok"] else f" · <span class='bad'>{html.escape(labels[0])}: {row['status'][0]}, {html.escape(labels[1])}: {row['status'][1]}</span>"
        links = " · ".join(f"<a href='{html.escape(Path(os.path.relpath(path, out)).as_posix())}'>{html.escape(labels[side])} full size</a>" for side, path in enumerate(row["originals"]) if not path.endswith("/") and Path(path).is_file())
        parts.append(f"<figure>{image}<figcaption><code>{html.escape(row['id'])}</code> · {html.escape(row['title'])}{state}<br>{links}</figcaption></figure>")
    parts.append("</div></main></html>")
    (out / "index.html").write_text("".join(parts), encoding="utf-8")
    print(f"{sum(bool(r['file']) for r in rows)} comparison sheets · {out / 'index.html'}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, help="output folder")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]), help="project checkout to render (default: this one)")
    parser.add_argument("--only", default="", help="comma-separated shot-id patterns, e.g. 'ui.*,world.*.wide'")
    parser.add_argument("--size", default="1920x1080", help="resolution of the standard shots, WxH")
    parser.add_argument("--locale", default="de", choices=["de", "en"], help="language of the standard shots")
    parser.add_argument("--display", default=os.environ.get("VISUAL_REVIEW_DISPLAY", ":78"), help="isolated X display (default :78)")
    parser.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot") or "godot")
    parser.add_argument("--batch", type=int, default=8, help="shots per process")
    parser.add_argument("--list", action="store_true", help="print the selected shots and stop")
    parser.add_argument("--compare", nargs=2, metavar=("DIR_A", "DIR_B"), help="build side-by-side sheets from two renders")
    parser.add_argument("--labels", nargs=2, help="names of the two sides of a comparison")
    args = parser.parse_args()
    if args.compare:
        return compare(args)
    args.project = Path(args.project).resolve()
    if not (args.project / SCRIPT).exists():
        fail(f"{args.project} does not contain {SCRIPT}; copy tests/visual_review_*.gd there first")
    if args.display.split(".")[0] in (":0", ":1") or not args.display.startswith(":"):
        fail("refusing the desktop display; use the isolated one (default :78)")
    return render(args)


if __name__ == "__main__":
    sys.exit(main())
