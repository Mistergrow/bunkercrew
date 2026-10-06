#!/usr/bin/env python3
"""Record the real SAN-1 repertoire and native score, including task preemption."""
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    output = root / "artifacts/san-bunker-dance"
    output.mkdir(parents=True, exist_ok=True)
    movie = output / "san-bunker-dance.avi"
    video = output / "san-bunker-dance.mp4"
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot or not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise SystemExit("Godot, ffmpeg, ffprobe and a graphical display are required")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-san-dance-") as profile:
        with (output / "render.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(
                [godot, "--disable-vsync", "--path", str(root), "--script",
                 "tests/medic_dance_capture.gd", "--write-movie", str(movie),
                 "--", "--no-profile-save", "--no-upnp"], cwd=root,
                env={**os.environ, "XDG_DATA_HOME": profile}, stdout=log,
                stderr=subprocess.STDOUT, timeout=300)
    log = (output / "render.log").read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(issue in log for issue in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    report = json.loads((output / "render-verification.json").read_text())
    if report["failures"] or not report["actual_native_audio"] or len(report["seen_moves"]) != 5:
        raise SystemExit("Actual native SAN-1 gameplay verification failed")
    start = max(0.0, report["capture_start_seconds"] - 0.15)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-ss", str(start),
                    "-i", str(movie), "-c:v", "libx264", "-preset", "medium", "-crf", "19",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(video)], check=True)
    media = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                     "stream=codec_name,width,height,sample_rate,channels",
                                     "-show_entries", "format=duration,size", "-of", "json", str(video)], text=True)
    (output / "media.json").write_text(media, encoding="utf-8")
    if not any(stream.get("codec_name") == "aac" and stream.get("channels") == 2 for stream in json.loads(media)["streams"]):
        raise SystemExit("The gameplay clip must retain Godot's actual mixed stereo sound")
    figures = []
    for capture in report["captures"]:
        caption = capture.get("label") or {
            "06-reduced-motion": "Reduzierte Bewegung: normale Bereitschaft",
            "07-new-medical-task": "Echte Verletzung: Auftrag übernimmt sofort",
            "08-blocked-route": "Blockierter Weg: SAN-1 sucht einen Zugang",
        }.get(capture["name"], capture["name"])
        figures.append(f'<figure><img src="{html.escape(capture["name"])}.png"><figcaption>{html.escape(caption)}</figcaption></figure>')
    page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SAN-1 · Bunker Dance</title><style>body{margin:0;background:#131c18;color:#d9dcc9;font:16px system-ui;max-width:1200px;padding:30px;margin:auto}h1{font-weight:600}p{line-height:1.6;color:#abb7a4}video{width:100%;background:#0c110f}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:18px;margin-top:24px}figure{margin:0}img{width:100%;image-rendering:pixelated}figcaption{padding:8px 0;color:#ccb77e}</style><h1>SAN-1 · Bunker Dance</h1><p>Fünf Softwarestufen: Kern-Takt, Servo-Lock, Ketten-Shuffle, Hydraulik-Welle und Bunker-Freeze. Der echte native Beat steuert Kopf, Arm und Ketten; die Maschine bleibt physisch an ihrer Station.</p><video controls src="san-bunker-dance.mp4"></video><p>Aufnahme einer normalen Solo-Partie im Aschewerk mit vorbereitetem Forschungsbudget und angehaltener Gegnererzeugung. SAN-1, Physik und Musik bleiben aktiv. Danach übernehmen eine echte Verletzung und ein gebautes Hindernis: Auftrag und Suche unterbrechen den Tanz. Der Film enthält den direkt aufgenommenen Spielton.</p><section>''' + "".join(figures) + f'''</section><p>{report["checks"]} Prüfungen bestanden; fünf Moves im echten Rendering.</p></html>'''
    (output / "index.html").write_text(page, encoding="utf-8")
    movie.unlink()
    print(f"Actual native SAN-1 gameplay capture passed: {video}")


if __name__ == "__main__":
    main()
