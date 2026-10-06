#!/usr/bin/env python3
"""Capture the production research UI and compare it with archived native views."""
import argparse
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def build_gallery(output: Path) -> None:
    verification = json.loads((output / "after/render-verification.json").read_text())
    if verification["failures"] or not verification["native_capture"]:
        raise SystemExit("A successful native production capture is required")
    for resolution in ("small", "desktop", "qhd"):
        for locale in ("de", "en"):
            for category in range(4):
                name = f"{resolution}-{locale}-{category}.png"
                if not all((output / version / name).exists() for version in ("before", "after")):
                    raise SystemExit(f"Missing real before/after screenshot: {name}")
    additional = []
    for locale in ("de", "en"):
        for name, caption in (
            (f"desktop-{locale}-crew-earned", "SAN-1: alle fünf Softwarestufen durch echte Käufe freigeschaltet"),
            (f"qhd-{locale}-vehicle-ready", "Fahrzeug: tatsächliche freigeschaltete Vorbereitung"),
        ):
            additional.append(f'<figure><a href="after/{name}.png"><img src="after/{name}.png" loading="lazy"></a><figcaption>{html.escape(caption)} · {locale.upper()}</figcaption></figure>')
    page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bunkercrew · Technik vorher/jetzt</title>
<style>body{background:#101915;color:#e0decb;font:16px system-ui;margin:0;padding:24px;max-width:1500px;margin:auto}h1{font-size:27px;font-weight:600}p{line-height:1.6;max-width:1050px;color:#b8bca7}nav{display:flex;gap:15px;flex-wrap:wrap;margin:20px 0;align-items:center}label{display:flex;gap:8px;align-items:center}select,button{font:inherit;padding:8px;background:#253329;color:#e0decb;border:1px solid #63726c}a{color:#d9ac60}#comparison{position:relative;width:100%;aspect-ratio:1.6;background:#080c0a}#comparison img{position:absolute;inset:0;width:100%;height:100%;image-rendering:pixelated}#before{clip-path:inset(0 50% 0 0)}#rail{position:absolute;left:50%;top:0;bottom:0;border-left:2px solid #d9ac60;pointer-events:none}#before-label,#after-label{position:absolute;top:8px;background:#101915e8;padding:5px 10px;pointer-events:none}#before-label{left:8px}#after-label{right:8px}input[type=range]{width:100%;accent-color:#d9ac60;margin:18px 0}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:20px;margin-top:30px}figure{margin:0}figure img{width:100%;image-rendering:pixelated}figcaption{line-height:1.5;color:#b8bca7}small{color:#a1a18c}</style>
<h1>Technik: echte Spielaufnahmen vorher und jetzt</h1>
<p>Lesbare Forschungsgruppen statt eines weit auseinandergezogenen Diagramms. Die Liste scrollt nur vertikal; Vorgänger, Wellengrenzen, Status und Preise stehen direkt an den Forschungen. Arbeitsausrüstung und alle fünf SAN-Softwarestufen passen gemeinsam auf die Besatzungsseite. Originale Pixel-Schrift, Olive, Messing und Materialsymbole bleiben erhalten.</p>
<nav><label>Auflösung <select id="resolution"><option value="desktop">1440 × 900</option><option value="small">960 × 600</option><option value="qhd">2560 × 1440</option></select></label><label>Sprache <select id="locale"><option value="de">Deutsch</option><option value="en">English</option></select></label><label>Forschung <select id="category"><option value="2">Besatzung</option><option value="0">Basis</option><option value="1">Waffen</option><option value="3">Fahrzeug</option></select></label><a id="original" target="_blank">Jetzt in Originalgröße öffnen</a></nav>
<div id="comparison"><img id="after" alt="Aktuelles Technik-UI"><img id="before" alt="Archiviertes Technik-UI vor dem Umbau"><div id="rail"></div><span id="before-label">Vorher</span><span id="after-label">Jetzt</span></div><input type="range" id="split" min="0" max="100" value="50" aria-label="Vorher/Nachher-Vergleich"><small>Regler nach links: aktuelles UI vollständig. Nach rechts: ursprüngliches UI.</small>
<p>Identischer vorbereiteter Spielstand: Sektor 07, Welle 16, 19 gemeinsame Technikpunkte, fünf vorhandene Forschungen und angehaltene Gegnererzeugung. Vorher-Bilder stammen aus der unmittelbar davor geprüften echten Galerie. Besatzung zeigt jeweils Stufe V im Detail; die Forschungsliste zeigt jetzt alle fünf Stufen gleichzeitig. Die zusätzlichen Bilder unten entstehen nach ausdrücklichen realen Forschungskäufen oder im vorbereiteten Fahrzeugzustand.</p>
<p>CHECK_COUNT Prüfungen bestanden: alle 41 Forschungen erreichbar, keine Überschneidungen, DE/EN und drei Auflösungen, jedes echte Fokusziel vollständig sichtbar, reale Tastatur-/Controller-/Mauseingaben, keine Punktkosten beim Auswählen und korrekte explizite Forschungskäufe. <a href="after/render-verification.json">Vorbereiteter Zustand und Prüfbericht</a> · <a href="plan-render.log">Nativer Renderlauf</a></p>
<section>ADDITIONAL</section>
<script>const ids=['resolution','locale','category'];function update(){const [r,l,c]=ids.map(id=>document.getElementById(id).value);const name=`${r}-${l}-${c}.png`;document.getElementById('after').src=`after/${name}`;document.getElementById('before').src=`before/${name}`;document.getElementById('original').href=`after/${name}`;document.getElementById('comparison').style.aspectRatio=r==='qhd'?'16 / 9':'1.6';}ids.forEach(id=>document.getElementById(id).addEventListener('change',update));document.getElementById('split').addEventListener('input',event=>{const x=+event.target.value;document.getElementById('before').style.clipPath=`inset(0 ${100-x}% 0 0)`;document.getElementById('rail').style.left=`${x}%`;});update();</script></html>'''
    (output / "index.html").write_text(page.replace("CHECK_COUNT", str(verification["checks"])).replace("ADDITIONAL", "".join(additional)), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gallery-only", action="store_true")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / "artifacts/research-refresh"
    if not options.gallery_only:
        godot = os.environ.get("GODOT") or shutil.which("godot")
        if not godot or not os.environ.get("DISPLAY"):
            raise SystemExit("Godot and a graphical display are required")
        with tempfile.TemporaryDirectory(prefix="bunkercrew-research-") as profile, (output / "plan-render.log").open("w") as log:
            result = subprocess.run([godot, "--path", str(root), "--script", "tests/research_categories_preview.gd", "--", "--no-profile-save", "--no-upnp", "--capture"], cwd=root, env={**os.environ, "XDG_DATA_HOME":profile}, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        log_text = (output / "plan-render.log").read_text(errors="replace")
        if result.returncode or any(issue in log_text for issue in ("SCRIPT ERROR", "ERROR:", "WARNING:")):
            raise SystemExit(log_text)
    build_gallery(output)
    print(output / "index.html")


if __name__ == "__main__":
    main()
