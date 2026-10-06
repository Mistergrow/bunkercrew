#!/usr/bin/env python3
"""Build a local, self-contained review page from actual Godot captures."""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "living-ecology"

PAGE = r'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Vegetation und Tierleben</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#101919;color:#eee7cf;font:16px/1.5 system-ui}main{max-width:1600px;margin:auto;padding:28px 24px}h1{margin:0 0 12px;font-size:30px}h2{margin:24px 0 8px;font-size:23px}p{max-width:110ch;color:#bdc6b8}a{color:#e4c578}nav{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}button{font:inherit;cursor:pointer;border:1px solid #506056;background:#24352c;color:#eee7cf;border-radius:7px;padding:8px 12px}button[aria-pressed=true]{border-color:#e4c578;background:#44432a;color:#f2d496}button:focus-visible,input:focus-visible,a:focus-visible{outline:2px solid #e4c578;outline-offset:3px}.small{font-size:14px}.result{color:#e4c578}.compare{--reveal:50%;position:relative;overflow:hidden;cursor:ew-resize;touch-action:pan-y;border:1px solid #4a5c51;border-radius:8px;user-select:none}.compare img{display:block;width:100%;height:auto;pointer-events:none}.before{position:absolute;inset:0;clip-path:inset(0 calc(100% - var(--reveal)) 0 0)}.before img{height:100%}.divider{position:absolute;top:0;bottom:0;left:var(--reveal);width:2px;background:#e4c578;pointer-events:none}.divider:after{content:'↔';position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);display:grid;place-items:center;width:40px;height:40px;background:#16291ee8;border:2px solid #e4c578;border-radius:50%;font-size:23px}.badge{position:absolute;top:12px;background:#132119ed;border:1px solid #62715f;border-radius:4px;padding:4px 8px;font-size:14px;pointer-events:none}.badge.old{left:12px}.badge.new{right:12px}.controls{display:flex;align-items:center;gap:12px;margin:14px 0}.controls input{width:100%;accent-color:#e4c578}.controls label{white-space:nowrap}.links{display:flex;flex-wrap:wrap;gap:20px;margin-top:10px}.detail{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}figure{margin:0}figure img,video{display:block;width:100%;height:auto;border:1px solid #4a5c51;border-radius:8px;background:#132119}figcaption{margin:8px 0;color:#bdc6b8}.metrics{display:flex;flex-wrap:wrap;gap:8px}.metric{border:1px solid #435248;border-radius:5px;padding:6px 9px;color:#c9d2bd}details{margin:22px 0}summary{cursor:pointer;color:#e4c578}pre{overflow:auto;background:#15231c;padding:16px;font-size:13px}footer{border-top:1px solid #435248;margin-top:28px;padding-top:12px;font-size:14px}@media(max-width:800px){main{padding:20px 12px}h1{font-size:25px}.detail{grid-template-columns:1fr}.controls{gap:8px}.badge{font-size:12px;top:8px;padding:3px 5px}.controls label{font-size:13px}}
</style>
<main><h1>Mehr Vegetation und Tierleben in allen 13 Schauplätzen</h1>
<p>Neue Büsche und Bodengewächse ergänzen die vorhandenen Bäume und Industriebauten. Die Tierwelt bleibt zurückhaltend: höchstens zwei kleine Bodentiere je Schauplatz, mit langen Ruhephasen und passenden Arten für das Klima. Der Bildvergleich zeigt dieselbe Kamera mit den neuen Systemen ausgeblendet und eingeblendet.</p>
<p class="result">__RESULT__</p>
<nav id="levels" aria-label="Schauplatz wählen"></nav>
<h2 id="title"></h2><nav id="modes" aria-label="Ansicht wählen"></nav>
<div id="views"></div><div id="metrics" class="metrics"></div>
<p class="small">Alle Bilder stammen aus echten Godot-Spielszenen bei 1920×1080: Betonbastion links, ein gehaltener Spieler, angehaltene Wellen und bestehende Atmosphäre. Die Vegetation und Tiere laufen mit ihren normalen Spielsystemen. Vorher/Nachher hält zusätzlich die neuen Systeme für die zwei Vergleichsbilder an. Die Nahansicht nutzt Zoom 2,2.</p>
<p class="small">Das Video zeigt eine vorbereitete Annäherung an eine einzelne Maus. Das vorhandene Bodentier wurde dafür einmal in einen Lebensraum rechts vom Bunker versetzt. Die Kamera bleibt stehen; der Spieler nähert sich ab Sekunde 3 und geht ab Sekunde 6 zurück. Die normalen Vergleichsbilder nutzen natürliche Spawns. Die Darstellung ist ein Sichttest, kein Nachweis für Kampf-FPS.</p>
<details><summary>Konfiguration und Messdaten der gewählten Szene</summary><pre id="record"></pre></details>
<details><summary>Pausiertes Hauptmenü ohne zusätzliche Bodentiere</summary><figure><a href="menu-paused.png"><img src="menu-paused.png" alt="Echtes pausiertes Hauptmenü, ohne neue Bodengewächse oder Tiere über dem Panorama" loading="lazy"></a><figcaption>Die Spielwelt steht; das Hauptmenü nutzt seine eigene Darstellung.</figcaption></figure></details>
<details><summary>Die neu generierten Bildassets</summary><div class="detail"><figure><a href="../../assets/environments/life/vegetation_v1.png"><img src="../../assets/environments/life/vegetation_v1.png" alt="Vegetationsatlas mit 16 Pflanzenarten" loading="lazy"></a><figcaption>16 Pflanzenarten · <a href="../../assets/environments/life/vegetation_v1.source.json">Prompt und Herkunft</a></figcaption></figure><div><p>Die aktive Tierwelt nutzt Mäuse, Frösche und Kaninchen. Die ersten generierten Vogel- und Flattertierentwürfe sind im Spiel deaktiviert.</p><p><a href="../../assets/environments/life/fauna_v1.source.json">Prompts und Herkunft des Tieratlas</a> · <a href="../../scripts/fauna_catalog.gd">Aktuelle Artwahl und Häufigkeit</a></p></div></div></details>
<footer><a href="verification-rendered.json">Prüfbericht mit vorbereiteten Szenenzuständen</a> · <a href="gallery-verification.json">Vollständigkeit der Galerie</a> · <a href="../../tests/living_ecology_gallery.gd">Reproduzierbarer Godot-Runner</a></footer>
</main><script>
'use strict';
const entries=__ENTRIES__;
let selected=entries.find(entry=>entry.id==='overgrown_steelworks')||entries[0];let mode='normal';
const labels={normal:'Vorher / Nachher',close:'Nahzoom',reduced:'Reduzierte Effekte',video:'Tierleben in Bewegung'};
function comparison(before,after){
const wrap=document.createElement('div');const surface=document.createElement('div');surface.className='compare';surface.id='comparison';
const current=document.createElement('img');current.src=after;current.alt=selected.title+' · mit neuer Vegetation und Fauna';current.draggable=false;
const prior=document.createElement('div');prior.className='before';const image=document.createElement('img');image.src=before;image.alt=selected.title+' · bisherige Umgebung';image.draggable=false;prior.append(image);
const divider=document.createElement('div');divider.className='divider';divider.setAttribute('aria-hidden','true');surface.append(current,prior,divider);
for(const [kind,text]of [['old','Bisher'],['new','Mit Vegetation und Tierleben']]){const tag=document.createElement('span');tag.className='badge '+kind;tag.textContent=text;surface.append(tag);}
const controls=document.createElement('div');controls.className='controls';const label=document.createElement('label');label.htmlFor='reveal';label.textContent='Bildgrenze verschieben';
const range=document.createElement('input');range.type='range';range.id='reveal';range.min='0';range.max='100';range.value='50';range.setAttribute('aria-controls','comparison');range.setAttribute('aria-label','Anteil der bisherigen Umgebung');
function reveal(value){const bounded=Math.max(0,Math.min(100,Math.round(value)));range.value=String(bounded);surface.style.setProperty('--reveal',bounded+'%');range.setAttribute('aria-valuetext','Bisher '+bounded+' Prozent, neu '+(100-bounded)+' Prozent');}
range.addEventListener('input',()=>reveal(Number(range.value)));reveal(50);
function at(event){const bounds=surface.getBoundingClientRect();reveal((event.clientX-bounds.left)/bounds.width*100);}
surface.addEventListener('pointerdown',event=>{if(event.button!==0)return;surface.setPointerCapture(event.pointerId);at(event);});surface.addEventListener('pointermove',event=>{if(surface.hasPointerCapture(event.pointerId))at(event);});surface.addEventListener('pointerup',event=>{if(surface.hasPointerCapture(event.pointerId)){at(event);surface.releasePointerCapture(event.pointerId);}});
controls.append(label,range);wrap.append(surface,controls);const links=document.createElement('div');links.className='links small';
for(const [src,text]of [[before,'Bisher · volle Auflösung'],[after,'Neu · volle Auflösung']]){const link=document.createElement('a');link.href=src;link.textContent=text;links.append(link);}wrap.append(links);return wrap;}
function figure(src,label){const item=document.createElement('figure');const link=document.createElement('a');link.href=src;const img=document.createElement('img');img.src=src;img.alt=label;link.append(img);const caption=document.createElement('figcaption');caption.textContent=label;item.append(link,caption);return item;}
function draw(){
document.getElementById('title').textContent=selected.title;document.querySelectorAll('#levels button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.id===selected.id)));document.querySelectorAll('#modes button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.id===mode)));
const views=document.getElementById('views');views.querySelectorAll('video').forEach(video=>video.pause());views.replaceChildren();const base=selected.id+'/';
if(mode==='normal'||mode==='close'){views.append(comparison(base+mode+'-before.png',base+mode+'-after.png'));}
else if(mode==='reduced'){const grid=document.createElement('div');grid.className='detail';grid.append(figure(base+'normal-after.png','Volle Vegetation und Fauna'),figure(base+'normal-reduced.png','F3 · reduzierte Effekte'));views.append(grid);}
else if(selected.video){const video=document.createElement('video');video.controls=true;video.muted=true;video.loop=true;video.playsInline=true;video.preload='metadata';video.src=base+'life.mp4';video.poster=base+'close-after.png';views.append(video);}
else{const p=document.createElement('p');p.textContent='Für diesen Schauplatz sind die gerenderten Einzelbilder verfügbar.';views.append(p);}
const metrics=document.getElementById('metrics');metrics.replaceChildren();const plants=selected.plants||{},fauna=selected.fauna||{};
const values=[['Pflanzen',plants.active_count??plants.entries],['Vegetationsgruppen',plants.mesh_batches],['Tiere',fauna.population],['Sichtbare Tiere',fauna.visible]];
for(const [label,value]of values){if(value===undefined||typeof value==='object')continue;const badge=document.createElement('span');badge.className='metric';badge.textContent=label+': '+value;metrics.append(badge);}
document.getElementById('record').textContent=JSON.stringify(selected,null,2);}
for(const entry of entries){const button=document.createElement('button');button.textContent=entry.title;button.dataset.id=entry.id;button.onclick=()=>{selected=entry;draw();};document.getElementById('levels').append(button);}
for(const [id,label]of Object.entries(labels)){const button=document.createElement('button');button.textContent=label;button.dataset.id=id;button.onclick=()=>{mode=id;draw();};document.getElementById('modes').append(button);}draw();
</script></html>
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    output = args.output.resolve()
    report_path = output / "verification-rendered.json"
    report = json.loads(report_path.read_text())
    entries = report["locations"]
    missing: list[str] = []
    for entry in entries:
        for capture in entry["captures"]:
            path = output / entry["id"] / capture
            if not path.is_file():
                missing.append(str(path.relative_to(output)))
        entry["video"] = (output / entry["id"] / "life.mp4").is_file()
    menu_capture = report.get("menu", {}).get("capture", "")
    if menu_capture and not (output / menu_capture).is_file():
        missing.append(menu_capture)
    verification = {
        "locations": len(entries),
        "images": sum(len(entry["captures"]) for entry in entries) + int(bool(menu_capture)),
        "videos": sum(entry["video"] for entry in entries),
        "missing": missing,
        "render_checks": report["checks"],
        "render_failures": report["failures"],
    }
    (output / "gallery-verification.json").write_text(json.dumps(verification, indent=2) + "\n")
    if missing or len(entries) != 13 or report["failures"]:
        print(json.dumps(verification, indent=2))
        return 1
    result = f'{len(entries)} Schauplätze · {verification["images"]} Renderbilder · {verification["videos"]} Videos · {report["checks"]-report["failures"]}/{report["checks"]} Galerieprüfungen bestanden'
    page = PAGE.replace("__RESULT__", html.escape(result)).replace(
        "__ENTRIES__", json.dumps(entries, ensure_ascii=False).replace("</", "<\\/")
    )
    (output / "index.html").write_text(page)
    print(json.dumps(verification, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
