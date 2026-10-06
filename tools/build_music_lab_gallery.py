#!/usr/bin/env python3
"""Assemble native lab captures and a shareable parameter reference."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/rhythm-music"

def main() -> None:
    budget = json.loads((OUTPUT / "visual-budget.json").read_text())
    verified = json.loads((OUTPUT / "environment-verification.json").read_text())
    html = '''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Musik-Labor</title>
<style>
:root{color-scheme:dark;font:16px/1.55 system-ui,sans-serif;color:#e0decb;background:#10191b}body{max-width:1250px;margin:auto;padding:28px}h1{font-size:34px;margin:0 0 10px;color:#d9ac60}h2{font-size:22px;font-weight:500}p{max-width:900px;color:#b6b7a5}a{color:#d9ac60}img,video{width:100%;display:block;background:#1b2829;border:1px solid #3b453d}figure{margin:26px 0}figcaption{padding-top:8px;color:#a1a18c;font-size:14px}code,pre{background:#1b2829;border:1px solid #3b453d;font-family:monospace}pre{white-space:pre-wrap;padding:16px}button{padding:11px 18px;background:#29362f;color:#e0decb;border:1px solid #63726c;cursor:pointer}.links{display:flex;gap:22px;flex-wrap:wrap}.stats{display:flex;gap:32px;flex-wrap:wrap;color:#a8b976}details{margin:22px 0}summary{cursor:pointer;color:#d9ac60}
</style>
<h1>Musik-Labor</h1>
<p><strong>Aktuelle vollständige Tanzbewegungen und native Audio-Vorschau: <a href="../rhythm-dance/index.html">Neue Tanzgalerie öffnen</a></strong></p>
<p>Im Spiel: <strong>Optionen → Takt → Musik-Labor</strong>. Wähle ein Leitthema, Tempo und Musikspannung. Passe Tanzart und Intensität für jede Figur an. Die Vorschau verwendet die tatsächlichen Godot-Figuren; das Musikstück der Partie bleibt erhalten.</p>
<figure><video controls loop muted playsinline preload="metadata" poster="dashboard-styles.png"><source src="dance-styles.mp4" type="video/mp4"></video><figcaption>Vier Sekunden, 60 Bilder/s. Vorbereitete, stumme Taktvorschau mit sechs Tanzarten bei hoher Intensität. Frühere ruhige Vergleichsaufnahme. Die vollständigen neuen Schritte und Bodentänze sind in der neuen Tanzgalerie zu sehen.</figcaption></figure>
<div class="stats"><span>4 Figuren + 40 Gegner: P95 __BUDGET__ ms</span><span>__CHECKS__ Shaderprüfungen bestanden</span><span>13 Schauplätze · 0 zusätzliche Draw Calls</span></div>
<h2>Einstellungen teilen</h2>
<p>Im Labor auf <strong>JSON kopieren</strong> klicken und den Text im Chat senden. <strong>Feedback speichern</strong> legt zusätzlich <code>music-lab-feedback.json</code> im Godot-Nutzerdatenordner ab. Gespeicherte Varianten können mit <strong>JSON importieren</strong> erneut geladen werden. Ein Textfeld nimmt deine Meinung zur Musik und zu den Bewegungen auf. <strong>Tanz im Spiel übernehmen</strong> speichert die bevorzugten Bewegungen für deine Partie.</p>
<details><summary>Beispielkonfiguration ansehen</summary><pre id="feedback"></pre><button id="copy">Beispiel kopieren</button><span id="copy-status" role="status"></span></details>
<figure><a href="dashboard-defaults.png"><img src="dashboard-defaults.png" alt="Die sechs individuellen Standardbewegungen im Musik-Labor"></a><figcaption>Jede Figur besitzt ihre eigene Standardbewegung. Zwölf weitere Stile sind frei wählbar; Einzel- und Gesamtintensität reichen von 0 bis 150 %.</figcaption></figure>
<figure><a href="dashboard-reduced.png"><img src="dashboard-reduced.png" alt="Die reduzierte Taktbewegung im Musik-Labor"></a><figcaption>Reduzierte Taktbewegung senkt die Amplitude. Arbeit, Eingabe, Verletzung, Gefahr und ausgeschaltete Musik unterbrechen die Bewegung im Spiel sofort.</figcaption></figure>
<h2>Eigenständig starten</h2><pre>godot --path . --script tests/music_lab_launcher.gd -- --no-profile-save</pre>
<p>Wenn die native Musikbibliothek fehlt, ist das Labor ausdrücklich als stumme, kontrollierte Animationsvorschau beschriftet. Die Partie verwendet dann ihre vorhandene OGG-Musik.</p>
<div class="links"><a href="example-feedback.json">Beispiel-JSON</a><a href="visual-budget.json">Messumfang und Laufzeiten</a><a href="environment-verification.json">Shadernachweis für alle Level</a><a href="gallery-verification.json">Aufnahmezustände</a></div>
<script>
const feedback=__FEEDBACK__;
document.getElementById('feedback').textContent=JSON.stringify(feedback,null,2);
document.getElementById('copy').onclick=async()=>{try{await navigator.clipboard.writeText(JSON.stringify(feedback,null,2));document.getElementById('copy-status').textContent=' Kopiert';}catch{document.getElementById('copy-status').textContent=' JSON oben markieren und kopieren';}};
</script></html>'''
    feedback = json.loads((OUTPUT / "example-feedback.json").read_text())
    html = html.replace("__BUDGET__", f'{budget["p95_ms"]:.3f}')
    html = html.replace("__CHECKS__", str(verified["checks"] - verified["failures"]))
    html = html.replace("__FEEDBACK__", json.dumps(feedback, ensure_ascii=False).replace("<", "\\u003c"))
    (OUTPUT / "index.html").write_text(html)
    print(OUTPUT / "index.html")

if __name__ == "__main__":
    main()
