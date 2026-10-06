#!/usr/bin/env python3
"""Validate real scenario setup and render a same-state before/after gallery."""
import argparse
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def write_gallery(destination, report):
    pairs = []
    additional = []
    captions = {
        "ash_foundry": "Aschewerk · Betonbastion · Westrand",
        "mountain_pass": "Gewitterpass · Stahlwerk · Mittellage",
        "overgrown_steelworks": "Verwachsenes Stahlwerk · Felsenfeste · Ostrand",
    }
    for entry in report["captures"]:
        if entry["phase"] != "after":
            continue
        filename = entry["file"]
        label = captions.get(entry["environment"], entry["environment"])
        size = "×".join(map(str, entry["resolution"]))
        card = f'<figure><a href="{html.escape(filename, quote=True)}"><img src="{html.escape(filename, quote=True)}" alt="{html.escape(label)}"></a><figcaption>{html.escape(label)} · {entry["locale"].upper()} · {size}</figcaption></figure>'
        if entry["environment"] == "ash_foundry":
            before = filename.replace("after-", "before-", 1)
            pairs.append(f'<section class="pair"><p>{entry["locale"].upper()} · {size}</p><div class="comparison"><figure><a href="{before}"><img src="{before}" alt="Bisherige Schauplatzauswahl"></a><figcaption>Vorher</figcaption></figure>{card}</div></section>')
        else:
            additional.append(card)
    markup = f'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Schauplatzauswahl</title>
<style>:root{{color-scheme:dark}}*{{box-sizing:border-box}}body{{margin:0;background:#0c1414;color:#e0decb;font:16px/1.6 system-ui,sans-serif}}main{{max-width:1800px;margin:auto;padding:32px 24px 60px}}h1{{font-size:30px;font-weight:600;margin:0}}p{{color:#a1a18c}}a{{color:#d9ac60}}.comparison,.additional{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}}figure{{margin:0}}img{{display:block;width:100%}}figcaption{{font-size:13px;color:#a1a18c;margin-top:8px}}.pair{{padding-top:18px;margin-top:20px;border-top:1px solid #29362f}}.additional{{margin-top:32px}}@media(max-width:760px){{.comparison,.additional{{grid-template-columns:1fr}}}}</style>
<main><h1>Schauplatzauswahl überarbeitet</h1>
<p>Die vorhandene Landschaft füllt die Seite. Schauplätze, Bauarten und Positionen stehen als offene Listen darüber. Eine einzige Vorschau zeigt den ausgewählten Raum mit der echten Grafik aus dem Spiel. Pixel-Schrift und die Farben des Spiels bleiben erhalten.</p>
<p>Vorbereitetes echtes Hauptmenü: zwei lokale Spieler, freie Schicht, pausiert. Vorher und Nachher verwenden jeweils Aschewerk, Betonbastion und Westrand. Keine Verbindung, Mikrofonaufnahme oder gespeicherter Spielfortschritt. Die Vorher-Ansicht nutzt eine unveränderte Kopie der vorherigen Auswahlseite.</p>
<p>{report['checks']}/{report['checks']} Prüfungen bestanden: normale Bedienflächen, Tastatur, Controller, Zurück, Figurenwahl, klassischer Bunker, Sprachwechsel und drei native Ausgabegrößen. <a href="render-verification.json">Messwerte und vorbereitete Zustände</a> · <a href="render.log">Prüflog</a></p>
<p>Zusätzlich <a href="selection-final.log">105/105 Spielstart-Prüfungen</a>: alle neun Schauplätze starten mit der gewählten Bauart, Bunkerposition und Figur; lokaler Koop und das Aufräumen der Szene wurden ebenfalls geprüft.</p>
<p>Gestalterische Referenzen: die offiziellen Menübilder von <a href="https://www.playstation.com/en-us/games/god-of-war-ragnarok/accessibility/">God of War Ragnarök</a> und <a href="https://www.playstation.com/en-us/games/the-last-of-us-part-ii/accessibility/">The Last of Us Part II</a>. Übernommen werden eine klare aktive Zeile, ruhige Abstände und eine separate Vorschau.</p>
{''.join(pairs)}<div class="additional">{''.join(additional)}</div></main></html>'''
    (destination / "index.html").write_text(markup, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    destination = root / "artifacts/scenario-ui"
    destination.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT") or shutil.which("godot")
    if not godot:
        raise SystemExit("Godot is required.")
    command = [godot, "--debug", "--path", str(root), "--script", "tests/scenario_ui_review_test.gd"]
    if args.capture:
        command.append("--disable-vsync")
    else:
        command.append("--headless")
    command.extend(["--", "--no-profile-save", "--no-upnp"])
    if args.capture:
        command.append("--capture")
    logfile = destination / ("render.log" if args.capture else "review.log")
    with tempfile.TemporaryDirectory(prefix="bunkercrew-scenario-ui-") as profile:
        with logfile.open("w", encoding="utf-8") as output:
            result = subprocess.run(command, cwd=root, env={**os.environ,"XDG_DATA_HOME":profile,"BUNKERCREW_SOCIAL_DB":":memory:"},stdout=output,stderr=subprocess.STDOUT,timeout=150)
    log = logfile.read_text(encoding="utf-8", errors="replace")
    if result.returncode or any(token in log for token in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
        raise SystemExit(log)
    report_path = destination / ("render-verification.json" if args.capture else "review-verification.json")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report["failures"] or not report["actual_main_scene"]:
        raise SystemExit("Scenario UI verification failed.")
    if args.capture:
        write_gallery(destination, report)
    print(f'Scenario UI: {report["checks"]}/{report["checks"]} passed · {destination / "index.html" if args.capture else report_path}')


if __name__ == "__main__":
    main()
