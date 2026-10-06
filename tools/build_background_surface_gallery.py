#!/usr/bin/env python3
"""Build the local review page from captured game frames and reviewed masks."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/background-surfaces"


def main() -> None:
    data = json.loads((ROOT / "assets/environments/background_surface_regions.json").read_text())
    masks = json.loads((ROOT / "assets/environments/surface_masks/catalog.json").read_text())
    native = json.loads((OUTPUT / "native/verification.json").read_text())
    if native["failures"]:
        raise ValueError("Native gameplay surface verification failed")
    names = {e["id"]: e["title"] for e in json.loads((ROOT / "assets/environments/catalog.json").read_text())["environments"]}
    records = []
    for key, entry in data["environments"].items():
        counts = {material: sum(r["material"] == material for r in entry["regions"]) for material in ["water", "flow", "ice"]}
        parts = [f"{counts[k]} {label}" for k, label in [("water", "Wasserbereiche"), ("flow", "Überläufe"), ("ice", "Eisbereiche")] if counts[k]]
        records.append(f'<tr><td>{html.escape(names[key])}</td><td>{", ".join(parts) or "Feste Landschaft"}</td><td><a href="masks/{key}-mask-overlay.png">Maske ansehen</a></td></tr>')
    locations = ["abandoned_harbor", "flooded_power_station", "storm_dam", "mountain_pass", "radar_highlands"]
    for key in locations:
        for zoom in ["0.6", "1.0", "2.2"]:
            for mode in ["before", "after-t0", "after-t7", "reduced"]:
                if not (OUTPUT / "native" / f"{key}-{zoom}-{mode}.png").is_file():
                    raise ValueError(f"Missing actual gameplay capture: {key}-{zoom}-{mode}")
        for mode in ["before", "after"]:
            for detail in ["", "-surface"]:
                if not (OUTPUT / "native" / f"{key}-{mode}{detail}.mp4").is_file():
                    raise ValueError(f"Missing normal-speed gameplay clip: {key}-{mode}{detail}")
    page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Wasser, Eis und Assetprüfung</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#111a18;color:#e3e1ce;font:16px/1.6 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:32px 24px}h1{font-size:clamp(27px,4vw,38px);font-weight:650}h2{font-size:23px}p{max-width:85ch;color:#b5c0b1}a{color:#ddaf66}section{margin-top:32px;padding-top:20px;border-top:1px solid #3a4a40}figure{margin:22px 0}figcaption{color:#cabb9c;margin-bottom:10px}video,img{width:100%;height:auto;display:block}video{background:#0b100f}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:10px 8px;border-bottom:1px solid #344339}th{font-weight:500;color:#b5c0b1}.toolbar{display:flex;gap:15px;flex-wrap:wrap;align-items:center;margin:20px 0}select{font:inherit;background:#27342d;color:#e3e1ce;border:1px solid #586657;padding:8px}label{color:#b5c0b1}input[type=range]{width:100%;accent-color:#ddaf66}details{margin:22px 0}summary{cursor:pointer;color:#ddaf66}.compare{position:relative;background:#121917;aspect-ratio:1440/900;overflow:hidden}.compare img{position:absolute;inset:0;object-fit:contain}.compare #after-image{clip-path:inset(0 50% 0 0)}.small{font-size:13px}.legend{display:flex;gap:18px;flex-wrap:wrap}.water{color:#57c7ff}.flow{color:#ecc35b}.ice{color:#d19cff}:focus-visible{outline:2px solid #ddaf66;outline-offset:3px}
@media(max-width:560px){main{padding:22px 14px}td,th{font-size:13px;padding:8px 4px}}
.video-pair{display:grid;grid-template-columns:1fr 1fr;gap:18px}.video-pair figure{margin:0}@media(max-width:700px){.video-pair{grid-template-columns:1fr}}button{font:inherit;color:#e3e1ce;background:#27342d;border:1px solid #586657;padding:8px 16px;cursor:pointer}
</style><main><h1>Bewegtes Wasser aus den Hintergrundbildern</h1>
<p>Die vorhandenen gemalten Wasserflächen sind über einzeln geprüfte Effektmasken abgetrennt. Ihre eigenen Pixel bewegen die Reflexe: waagerecht auf Seen und Tümpeln, senkrecht in den Überläufen. Eis bekommt schwache Lichtreflexe bei festen Texturkoordinaten. Stil, Details und Originalbilder bleiben erhalten.</p>
<p>Alle 13 Level geprüft: 22 Wasserbereiche, elf Überläufe und zwei Eisbereiche. Ufer, Schilf, Bäume und Bauwerke sind ausgespart. Frostbahnhof, Eisenschlucht und Megafabrik behalten ihre festen Geländeoberflächen.</p>
<section><h2>Bewegung im Spiel</h2><p>Die Videos zeigen vorbereitete echte Spielwelten mit einem stehenden Spieler. Gegnerwellen und andere Animationen sind angehalten, damit die Wasser- und Eiseffekte sichtbar werden. Die Hintergrundzeit läuft in den Videosegmenten mit normaler Geschwindigkeit. Der bisherige Farb-/Rechteckfilter wird mit den neuen Flächenmasken verglichen.</p>
<div class="toolbar"><label for="video-location">Schauplatz</label><select id="video-location"></select><label for="video-detail">Ansicht</label><select id="video-detail"><option value="-surface">Oberer Bildausschnitt</option><option value="">Ganze Spielansicht</option></select><button id="play-pair" type="button">Beide abspielen</button></div>
<div class="video-pair"><figure><figcaption>Bisher</figcaption><video id="before-video" controls loop muted playsinline preload="metadata"></video></figure><figure><figcaption>Neue Pixelbewegung</figcaption><video id="after-video" controls loop muted playsinline preload="metadata"></video></figure></div><p class="small">Drei Sekunden bei 60 Bildern/s, ohne Ton. Beide Clips verwenden denselben Zeitverlauf und dieselbe Kamera. Aufnahmerenderer: ''' + html.escape(native["renderer"]) + '''. Die separaten Pixel- und Uferprüfungen liefen zusätzlich auf der RTX 4090. Diese vorbereiteten Aufnahmen sind kein Leistungsbenchmark.</p></section>
<section><h2>Vorher / jetzt bei drei Zoomstufen</h2><div class="toolbar"><label for="location">Schauplatz</label><select id="location"></select><label for="zoom">Zoom</label><select id="zoom"><option value="0.6">Weit · 0,6</option><option value="1.0" selected>Normal · 1,0</option><option value="2.2">Nah · 2,2</option></select></div>
<div class="compare"><img id="before-image" alt="Bisheriger Hintergrundeffekt"><img id="after-image" alt="Hintergrund mit maskierter Pixelbewegung"></div><label for="split">Neue Darstellung links · bisherige Darstellung rechts</label><input id="split" type="range" min="0" max="100" value="50"><p class="small">Beide Aufnahmen verwenden dieselbe Szene, Kamera und Hintergrundzeit (7 Sekunden). Licht, Nebel und Wolken sind für den Vergleich angehalten. F3 stoppt die zusätzlichen Materialbewegungen; eine Spielpause hält die Hintergrundzeit an.</p></section>
<section><h2>Die geprüften Flächen</h2><p class="legend"><span class="water">Blau: Wasser</span><span class="flow">Gold: Überläufe</span><span class="ice">Violett: Eis</span></p><table><thead><tr><th>Schauplatz</th><th>Animation</th><th>Geprüfte Region</th></tr></thead><tbody>''' + "".join(records) + '''</tbody></table>
<details><summary>Wasser und Auslässe am Kraftwerk</summary><img loading="lazy" src="masks/flooded_power_station-mask-overlay.png" alt="Geprüfte Kraftwerkflächen: Wasser blau, Überläufe gold, Gebäude und Pflanzen ausgespart"></details>
<details><summary>Stationäre Eisflächen auf den Radarhöhen</summary><img loading="lazy" src="masks/radar_highlands-mask-overlay.png" alt="Zwei eng begrenzte Eisflächen auf den Radarhöhen, violett markiert"></details></section>
<section><h2>Assetprüfung und Aufwand</h2><p>209 PNGs, 664 Audiodateien und neun Schriften technisch geprüft. Alle 52 ursprünglichen Panorama- und Ebenenbilder haben ihre bisherigen Datei-Hashes. Die veralteten Herkunftsverweise im Umgebungskatalog sind berichtigt.</p><p>Die Masken sind zugeschnitten und sparen ''' + f"{masks['texture_area_saved_percent']:.1f}".replace(".", ",") + ''' % Texturfläche gegenüber vollständigen Maskenbildern. Sie werden einmal geladen und wiederverwendet. Die Animation läuft im vorhandenen Shader, ohne zusätzliche Zeichenebene, Bildanalyse oder GPU-Bildrücklesen im Spiel. Die separate Menüvorschau behält ihre bisherigen Panoramen und Effekte.</p><p><a href="asset-audit.html">Vollständiger Asset-Audit</a> · <a href="semantic-probes.json">44 unabhängige Material- und Schutzpunkte</a> · <a href="gpu/verification.json">GPU-Pixelprüfung</a> · <a href="native/mask-stage-summary.json">Uferprüfung aller 13 Level</a> · <a href="native/verification.json">Gerenderte Vergleichsszenen</a> · <a href="native/video-verification.json">Videogeschwindigkeit und Bewegung</a> · <a href="verification.json">Gesamtnachweis</a></p></section></main>
<script>
const entries=''' + json.dumps({key: names[key] for key in locations}, ensure_ascii=False) + ''';
const locationSelect=document.querySelector('#location'),zoom=document.querySelector('#zoom'),split=document.querySelector('#split');
for(const [id,title] of Object.entries(entries)){const option=document.createElement('option');option.value=id;option.textContent=title;locationSelect.append(option)}
function update(){const prefix=`native/${locationSelect.value}-${zoom.value}`;document.querySelector('#before-image').src=prefix+'-before.png';document.querySelector('#after-image').src=prefix+'-after-t7.png'}
locationSelect.addEventListener('change',update);zoom.addEventListener('change',update);split.addEventListener('input',()=>{document.querySelector('#after-image').style.clipPath=`inset(0 ${100-split.value}% 0 0)`});update();
const videoLocation=document.querySelector('#video-location'),videoDetail=document.querySelector('#video-detail'),beforeVideo=document.querySelector('#before-video'),afterVideo=document.querySelector('#after-video'),playPair=document.querySelector('#play-pair');
for(const [id,title] of Object.entries(entries)){const option=document.createElement('option');option.value=id;option.textContent=title;videoLocation.append(option)}
function updateVideo(){beforeVideo.pause();afterVideo.pause();playPair.textContent='Beide abspielen';beforeVideo.src=`native/${videoLocation.value}-before${videoDetail.value}.mp4`;afterVideo.src=`native/${videoLocation.value}-after${videoDetail.value}.mp4`}
videoLocation.addEventListener('change',updateVideo);videoDetail.addEventListener('change',updateVideo);
playPair.addEventListener('click',async()=>{if(!beforeVideo.paused||!afterVideo.paused){beforeVideo.pause();afterVideo.pause();playPair.textContent='Beide abspielen';return}beforeVideo.currentTime=0;afterVideo.currentTime=0;const result=await Promise.allSettled([beforeVideo.play(),afterVideo.play()]);if(result.some(r=>r.status==='rejected')){beforeVideo.pause();afterVideo.pause();playPair.textContent='Beide abspielen'}else playPair.textContent='Anhalten'});updateVideo();
</script></html>'''
    (OUTPUT / "index.html").write_text(page)
    print("SURFACE GALLERY", len(records), "maps", len(locations) * 4, "videos")


if __name__ == "__main__":
    main()
