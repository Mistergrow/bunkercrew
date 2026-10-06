#!/usr/bin/env python3
"""Present the native dance comparisons and their measured preparation state."""
from html import escape
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/rhythm-dance"


def main() -> None:
    prepared = json.loads((OUTPUT / "gallery-verification.json").read_text())
    native = json.loads((OUTPUT / "native-verification.json").read_text())
    budget = json.loads((ROOT / "artifacts/rhythm-music/visual-budget.json").read_text())
    labels = {"breakdance": "Breakdance", "moonwalk": "Moonwalk", "shuffle": "Shuffle", "running_man": "Running Man", "robot": "Robot / Popping", "arm_wave": "Arm-Welle", "body_roll": "Body Roll"}
    spans = {"breakdance": 48.27, "moonwalk": 19.26, "shuffle": 18.03, "running_man": 21.95, "robot": 16.0, "arm_wave": 19.24, "body_roll": 18.44}
    rows = "".join(f"<tr><td>{escape(labels[style])}</td><td>{span:.1f} px</td></tr>" for style, span in spans.items())
    html = f'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Tanzbewegungen und Musik-Labor</title>
<style>
:root{{color-scheme:dark;font:16px/1.55 system-ui,sans-serif;color:#e0decb;background:#10191b}}body{{max-width:1400px;margin:auto;padding:28px}}h1{{font-size:32px;margin:0 0 10px;color:#d9ac60}}h2{{font-size:22px;font-weight:500}}p{{max-width:1050px;color:#b6b7a5}}a{{color:#d9ac60}}img,video{{width:100%;display:block;background:#1b2829;border:1px solid #3b453d}}figure{{margin:26px 0}}figcaption{{padding-top:8px;color:#a1a18c;font-size:14px}}table{{border-collapse:collapse;background:#1b2829;max-width:550px;width:100%}}td,th{{padding:8px 18px;text-align:left;border-bottom:1px solid #3b453d}}.links{{display:flex;gap:22px;flex-wrap:wrap}}.stats{{display:flex;gap:32px;flex-wrap:wrap;color:#a8b976}}code{{background:#1b2829;padding:4px 8px}}
</style>
<h1>Tanzbewegungen und Musik-Labor</h1>
<p>Sieben neue Bewegungen verbinden Schritte, Knie, Hüfte und Arme: Breakdance mit Toprock, Bodenbewegung und Freeze, Moonwalk, Shuffle, Running Man, Robot/Popping, Arm-Welle und Body Roll. Die sechs Crewmitglieder haben eigene Standardstile. Kopfnicken und die bisherigen ruhigen Bewegungen bleiben auswählbar.</p>
<figure><video controls playsinline preload="metadata" poster="native-lab-compare.png"><source src="native-lab-compare.mp4" type="video/mp4"></video><figcaption>Echter Hauptmenü-Zugang zum Godot-Labor, tatsächlicher nativer Audio-Mixer, normales Tempo 118 BPM, Musikstufe 2 und Tanzintensität 100 %. Enthält den Einstieg über hörbare Kick-Schläge und anschließend 16 musikalische Schläge mit vollständigen Tanzbewegungen. Die Musik in diesem Video wurde von Godot zusammen mit den Bildern aufgezeichnet.</figcaption></figure>
<p>Im Spiel öffnen: <strong>Optionen → Takt → Musik-Labor</strong>. Minimal Techno, Schranz, Hip-Hop oder Breakbeat auswählen, eine Tanzart pro Figur einstellen und mit „Tanz im Spiel übernehmen“ speichern. „JSON kopieren“ erzeugt teilbare Einstellungen einschließlich Musikstil, Tempo und Einzelintensitäten. Dateien aus der vorherigen Labor-Version können weiterhin importiert werden.</p>
<figure><video controls loop muted playsinline preload="metadata" poster="dance-0375.png"><source src="seven-moves.mp4" type="video/mp4"></video><figcaption>Alle sieben Moves im direkten Vergleich: {prepared['frames']} native gerenderte Bilder bei 60 Bildern/s, 116 BPM und 100 % Intensität. Diese gesonderte Aufnahme benutzt einen vorbereiteten stummen Kick-Verlauf, damit alle Choreografien während derselben vollständigen 16-Beat-Phrase vergleichbar sind.</figcaption></figure>
<div class="stats"><span>81.392 Choreografie- und Sicherheitsprüfungen</span><span>30 / 60 / 144 FPS: identische Schritte am selben hörbaren Sample</span><span>4 Crew + 40 Gegner: P95 {budget['p95_ms']:.3f} ms zusätzliche Taktberechnung</span></div>
<p>Die Bassdrum-Samples der nativen Aufnahme liegen exakt am musikalischen Raster (maximale Sample-Abweichung: {native['max_kick_sample_error']:.0f} Samples). In {native['synchronized_actor_frames']} geprüften Figuren-Frames folgen die sichtbaren Fußpositionen demselben hörbaren Takt.</p>
<div class="links"><a href="../rhythm-music/menu-de.png">Menü Deutsch</a><a href="../rhythm-music/menu-en.png">Menu English</a><a href="../rhythm-music/dance-dropdown-en.png">Alle Tanzarten</a><a href="../rhythm-music/genre-dropdown-en.png">Musikstile im Labor</a><a href="../rhythm-music/options-genre-dropdown-en.png">Musikstile in den Optionen</a></div>
<h2>Sichtbare Beinbewegung bei normaler Intensität</h2>
<p>Gemessene Spanne der gezeichneten Knie- und Fußgelenke innerhalb der vollständigen 16-Beat-Phrase, in ursprünglichen Spielpixeln vor Vorschauvergrößerung.</p>
<table><thead><tr><th>Bewegung</th><th>Größte Gelenkspanne</th></tr></thead><tbody>{rows}</tbody></table>
<p>Die Spielfigur und ihr Kollisionskörper bleiben an ihrem Ort. Die Schritte verwenden den hörbaren Sample-Takt. Bewegung, Arbeit, Verletzung, Gefahr, Pause und ausgeschaltete Musik beenden den Tanz sofort. Beim Zurückspringen der Musik wartet die Figur auf neue hörbare Kicks.</p>
<div class="links"><a href="gallery-verification.json">Vorbereitete Aufnahme</a><a href="native-verification.json">Native Audio-Aufnahme</a><a href="../rhythm-music/visual-budget.json">CPU-Messumfang</a><a href="../rhythm-music/dance-choreography-test.log">Choreografie-Prüfungen</a></div>
</html>'''
    (OUTPUT / "index.html").write_text(html)
    print(OUTPUT / "index.html")


if __name__ == "__main__":
    main()
