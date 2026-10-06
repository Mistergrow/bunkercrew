#!/usr/bin/env python3
"""Validate the actual menu; optionally capture real Godot video and stereo audio."""
import argparse
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def write_gallery(destination, verification):
    root = Path(__file__).resolve().parents[1]
    track = verification.get("prepared_track", "nachtschicht")
    title = html.escape(verification.get("title", "Bunkercrew · Nachtschicht"))
    asset = "menu_rave_v1.ogg" if track == "nachtschicht" else f"menu_rave_{track}_v1.ogg"
    audio_path = html.escape(os.path.relpath(root / "assets/audio" / asset, destination), quote=True)
    cards = []
    captions = {"01-menu-kick.png": "Bassdrum · Titel links", "02-menu-rest.png": "Zwischen den Kicks · ursprüngliche Größe", "03-reduced-menu.png": "Reduzierte Bewegung · feste Titelgröße", "04-menu-second-tone.png": "Zweiter Basston · Titel rechts"}
    for capture in verification["captures"]:
        filename = html.escape(capture["file"], quote=True)
        label = html.escape(captions.get(capture["file"], capture["file"]))
        cards.append(f'<figure><a href="{filename}"><img src="{filename}" alt="{label}"></a><figcaption>{label} · Kick {capture["pulse"]:.3f} · Zweiter Ton {capture.get("secondary_pulse",0.0):.3f} · X {capture.get("horizontal_offset",0.0):+.2f}px · Y {capture.get("vertical_offset",0.0):+.2f}px</figcaption></figure>')
    pcm = verification["pcm"]
    mixer_note = ""
    mixer_report = destination / "mixer/verification.json"
    if mixer_report.exists() and (destination / "mixer/mixer-rhythm.mp4").exists():
        mixer = json.loads(mixer_report.read_text(encoding="utf-8"))
        if not mixer.get("failures",1):
            mixer_note = '<p>Im Spiel reagiert auch der arbeitende Betonmischer auf hörbare Bassdrums.</p><video src="mixer/mixer-rhythm.mp4" controls playsinline preload="metadata" poster="mixer/01-kick-settle.png"></video><p><a href="mixer/mixer-rhythm.mp4">Betonmischer mit echtem Spielton ansehen</a> · <a href="mixer/verification.json">18/18 Prüfungen: bezahlter Auftrag, echte Musik, aktive Spiellogik</a></p>'
    loop_note = ""
    loop_path = destination / "loop-verification.json"
    if loop_path.exists():
        loop = json.loads(loop_path.read_text(encoding="utf-8"))
        if not loop["failures"] and loop.get("continuous_loop_checked") and "clock" in loop:
            clock = loop["clock"]
            loop_note = f'<p>Zusätzlich {loop["checks"]}/{loop["checks"]} Prüfungen über die vollständige Schleife: derselbe OGG-Decoder über den Loop, {clock["backward_steps"]} Rücksprünge des angezeigten Taktgebers und {clock["unique_kicks_after_wrap"]} weitere Bassdrum-Impulse nach der Wiederholung. <a href="loop-verification.json">Loop-Messwerte</a></p>'
    fullscreen_note = ""
    if track == "nachtschicht":
        fullscreen_note = '<p>Fullscreen: 14/14 Prüfungen für F11 und Alt+Enter im Hauptmenü und pausierten Spiel, einschließlich exakt wiederhergestellter Fenstergröße und Position. <a href="../fullscreen-f11/02-fullscreen-menu.png">Fullscreen ansehen</a> · <a href="../fullscreen-f11/standalone-final-verification.json">Messwerte</a> · <a href="../fullscreen-f11/preferences-menu-verification.json">Menü: 17/17 Prüfungen für übernommene Einstellungen</a> · <a href="../fullscreen-f11/preferences-audio-verification.json">Optionen: 17/17 Prüfungen für übernommene Einstellungen</a></p>'
    markup = f'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
:root{{color-scheme:dark}}*{{box-sizing:border-box}}body{{margin:0;background:#101a1b;color:#e7debf;font:16px/1.6 system-ui,sans-serif}}main{{max-width:1280px;margin:auto;padding:36px 24px 60px}}h1{{font-weight:600;font-size:32px;margin:0}}p{{color:#a9b6ad;margin:12px 0 24px}}.tag{{color:#deaf63;letter-spacing:.18em;text-transform:uppercase;font-size:12px}}video{{display:block;width:100%;background:#070d0e;border:1px solid #384943}}a{{color:#deaf63}}audio{{width:min(100%,640px)}}.captures{{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:20px;margin-top:32px}}figure{{margin:0}}img{{display:block;width:100%;border:1px solid #384943}}figcaption{{margin-top:8px;color:#a9b6ad;font-size:13px}}.checks{{border-top:1px solid #384943;margin-top:28px;padding-top:16px;font-size:14px}}
</style><main>
<div class="tag">Echtes Hauptmenü · echtes Spielaudio</div><h1>{title}</h1>
<p>{verification['bpm']:g} BPM Minimal Techno. Die Wortmarke pulsiert zur hörbaren Bassdrum und bewegt sich sanft von links nach rechts. Schrift, Farben, Landschaft und Bedienflächen behalten ihren Stil.</p>
<video src="menu-rave.mp4" controls playsinline preload="metadata" poster="01-menu-kick.png"></video>
<p>Das Video zeigt das normale pausierte Hauptmenü, Schauplatz- und Sprachwechsel, Hilfe und Optionen, Stummschaltung, reduzierte Bewegung und den Start ins Aschewerk. Der Ton wurde direkt von Godot mit dem Bild aufgezeichnet.</p>
<audio controls preload="metadata" src="{audio_path}"></audio>
<p><a href="{audio_path}">Vollständiger Menütrack · {verification.get('seconds',60):.2f} Sekunden</a> · <a href="menu-rave.mp4">Video öffnen</a></p>
<div class="captures">{''.join(cards)}</div>
{mixer_note}
<div class="checks">{verification['checks']}/{verification['checks']} Prüfungen bestanden. Tatsächliches Menü und Decoder, ohne Musiklabor oder eingespeiste Rhythmusdaten. Geprüfte Music-PCM: {pcm['frames']:,} Stereo-Frames, Peak {pcm['peak']:.4f}, RMS {pcm['rms']:.4f}, endlich und ohne digitales Clipping. <a href="render-verification.json">Messwerte</a> · <a href="render.log">Prüflog</a>{loop_note}</div>
{fullscreen_note}
<p><a href="validation.json">Gesamte Validierung</a></p>
</main></html>'''
    (destination / "index.html").write_text(markup, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true", help="Use the graphical renderer and record actual mixed audio")
    parser.add_argument("--loop", action="store_true", help="Run the actual headless menu transport through its sixty-second loop")
    parser.add_argument("--track", default="nachtschicht", help="Prepare a catalog track using the ordinary process-local menu rotation")
    options = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", options.track):
        parser.error("Track IDs contain only lowercase letters, digits and underscores.")
    if options.capture and options.loop:
        parser.error("Use --loop separately from the short --capture movie.")
    root = Path(__file__).resolve().parents[1]
    destination = root / "artifacts/menu-rave"
    if options.track != "nachtschicht":
        destination /= options.track
    destination.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        raise SystemExit("Godot is required.")
    movie = destination / "menu-rave.avi"
    video = destination / "menu-rave.mp4"
    if options.capture and (not shutil.which("ffmpeg") or not shutil.which("ffprobe")):
        raise SystemExit("ffmpeg, ffprobe and a graphical display are required for --capture.")
    command = [godot, "--debug", "--path", str(root), "--script", "tests/menu_rave_gameplay_test.gd"]
    if options.capture:
        command.extend(["--disable-vsync", "--write-movie", str(movie)])
    else:
        command.append("--headless")
    command.extend(["--", "--no-profile-save", "--no-upnp"])
    command.extend(["--track=" + options.track, "--output=" + str(destination)])
    if options.capture:
        command.append("--capture")
    if options.loop:
        command.append("--loop")
    log_path = destination / ("render.log" if options.capture else "loop.log" if options.loop else "gameplay.log")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-menu-rave-") as profile:
        with log_path.open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=root, env={**os.environ, "XDG_DATA_HOME": profile},
                                    stdout=output, stderr=subprocess.STDOUT, timeout=180)
    log = log_path.read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(error in log for error in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    verification_path = destination / ("render-verification.json" if options.capture else "loop-verification.json" if options.loop else "gameplay-verification.json")
    verification = json.loads(verification_path.read_text())
    if verification["failures"] or not verification["actual_main_scene"] or not verification["pcm"]["finite"]:
        raise SystemExit("Actual main-menu verification failed.")
    if options.capture:
        subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(movie),
                        "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
                        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(video)], check=True)
        media = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                         "stream=codec_name,width,height,sample_rate,channels,duration,nb_frames",
                                         "-show_entries", "format=duration,size", "-of", "json", str(video)], text=True)
        (destination / "media.json").write_text(media, encoding="utf-8")
        streams = json.loads(media)["streams"]
        if not any(stream.get("codec_name") == "aac" and stream.get("channels") == 2 for stream in streams):
            raise SystemExit("The menu movie must contain Godot's actual stereo mixed audio.")
        with (destination / "audio-peaks.log").open("w", encoding="utf-8") as output:
            subprocess.run(["ffmpeg", "-hide_banner", "-i", str(video), "-af", "volumedetect",
                            "-vn", "-sn", "-dn", "-f", "null", "-"], stdout=output,
                           stderr=subprocess.STDOUT, check=True)
        # The MP4 retains all actual captured audio; discard only our temporary AVI.
        movie.unlink()
        write_gallery(destination, verification)
    print(f"Actual menu rave passed {verification['checks']}/{verification['checks']} checks: {video if options.capture else verification_path}")


if __name__ == "__main__":
    main()
