#!/usr/bin/env python3
"""Build a local review of the 33 added dances and real native audio timeline."""
from __future__ import annotations

import html
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts" / "dance-collection"

PAGE = r'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · 33 neue Tänze</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#11191c;color:#eee7cf;font:16px/1.5 system-ui}main{max-width:1540px;margin:auto;padding:28px 24px}h1{margin:0 0 12px;font-size:30px}h2{margin:26px 0 8px;font-size:23px}p{max-width:105ch;color:#bbc6b8}a{color:#e4c578}nav{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}button{font:inherit;cursor:pointer;border:1px solid #506056;background:#24352c;color:#eee7cf;border-radius:6px;padding:8px 12px}button[aria-pressed=true]{border-color:#e4c578;background:#44432a;color:#f2d496}button:focus-visible,a:focus-visible,summary:focus-visible{outline:2px solid #e4c578;outline-offset:3px}.result{color:#e4c578}.small{font-size:14px}.sheet{display:block;width:100%;height:auto;border:1px solid #4a5c51;border-radius:8px;image-rendering:pixelated}video{display:block;width:100%;height:auto;border:1px solid #4a5c51;border-radius:8px;background:#11191c}.facts{display:flex;gap:8px;flex-wrap:wrap}.badge{border:1px solid #45574b;border-radius:4px;padding:5px 9px;color:#cad3bd}details{margin:22px 0}summary{cursor:pointer;color:#e4c578}pre{overflow:auto;background:#18231f;padding:14px;font-size:13px}footer{border-top:1px solid #435248;margin-top:26px;padding-top:12px;font-size:14px}@media(max-width:700px){main{padding:20px 12px}h1{font-size:25px}button{font-size:14px;padding:7px 9px}}
</style><main>
<h1>33 neue Tänze mit den vertrauten Seitenansichten</h1>
<p>Drei gemeinsame Moves und je fünf eigene Tänze für Mara, Branko, Ivo, Nora, Levin und Selma. Schritte, Kopf, Arme und Beine folgen der musikalischen Beatposition; die vorhandenen Köpfe und Oberkörper bleiben erhalten. Die neuen Charaktertänze werden im Spiel auf den Charakterleveln 2, 4, 6, 8 und 10 freigeschaltet.</p>
<p class="result">__RESULT__</p>
<h2>Musik und Bewegung gemeinsam</h2>
<p class="small">Die Aufnahme öffnet das echte Musiklabor über die Audiooptionen. Minimal Techno bei 118 BPM und Intensität 2 läuft durch den nativen Audiomischer. Sechs vorbereitete Charaktere zeigen eigene Tänze bei voller Tanzintensität. Das ist eine Entwicklungs-Vorschau mit allen Freischaltungen; der Spielstand wird nicht verändert.</p>
<video controls playsinline preload="metadata" poster="native-lab-compare.png" src="native.mp4"></video>
<p class="small"><a href="native.mp4">Video mit echter Spielmusik</a> · <a href="native-verification.json">Beat- und Bewegungsmessung</a></p>
<h2>Alle Moves ansehen</h2>
<p class="small">Die Bildtafeln zeigen sechs feste Beatpositionen derselben Choreografie im echten Godot-Renderer. Sie dienen zur Kontrolle von Gelenken, Bodenkontakt und Silhouette. Die Auswahl zeigt auch noch gesperrte Moves ausschließlich in dieser Entwicklungs-Vorschau.</p>
<nav id="characters" aria-label="Charakter wählen"></nav><nav id="moves" aria-label="Tanz wählen"></nav>
<h2 id="title"></h2><div class="facts" id="facts"></div>
<nav id="scales" aria-label="Bildgröße wählen"><button data-scale="2" aria-pressed="false">2× · normale Größe</button><button data-scale="4" aria-pressed="true">4× · Gelenke ansehen</button></nav>
<a id="full" href="#"><img class="sheet" id="sheet" alt="Gerenderte Tanzposen an sechs musikalischen Beatpositionen"></a>
<p class="small"><a id="download" href="#">Bildtafel in voller Auflösung</a> · 1440×960 Pixel · nächste Nachbarn bei der Texturskalierung</p>
<details><summary>Die sechs ursprünglichen Seitenansichten</summary><a href="side-crew.png"><img class="sheet" src="side-crew.png" alt="Mara, Branko, Ivo, Nora, Levin und Selma mit ihren ursprünglichen Seitenansichten" loading="lazy"></a></details>
<details><summary>Messdaten des ausgewählten Moves</summary><pre id="record"></pre></details>
<footer><a href="verification-rendered.json">Renderprüfung und vorbereiteter Szenenzustand</a> · <a href="gallery-verification.json">Vollständigkeit der Galerie</a> · <a href="../../tests/dance_collection_gallery.gd">Bildtafel-Runner</a> · <a href="../../tests/rhythm_dance_native_preview.gd">Aufnahme mit nativem Audio</a></footer>
</main><script>
'use strict';
const entries=__ENTRIES__;
const characters={shared:'Gemeinsame Moves',mara:'Mara',branko:'Branko',ivo:'Ivo',nora:'Nora',levin:'Levin',selma:'Selma'};
let group='mara',selected=entries.find(item=>item.character==='mara'&&item.owner)||entries[0],scale=4;
function draw(){
 document.querySelectorAll('#characters button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.id===group)));
 const moves=document.getElementById('moves');moves.replaceChildren();
 for(const entry of entries.filter(item=>group==='shared'?!item.owner:item.owner===group)){const button=document.createElement('button');button.textContent=entry.label;button.setAttribute('aria-pressed',String(entry===selected));button.onclick=()=>{selected=entry;draw();};moves.append(button);}
 document.querySelectorAll('#scales button').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.scale)===scale)));
 document.getElementById('title').textContent=selected.label;
 const facts=document.getElementById('facts');facts.replaceChildren();
 for(const text of [selected.owner?characters[selected.owner]:'Gemeinsamer Move','Ab Charakterlevel '+selected.level,'Originale Seitenansicht']){const badge=document.createElement('span');badge.className='badge';badge.textContent=text;facts.append(badge);}
 const file=selected.captures.find(path=>path.endsWith('-'+scale+'x.png'));document.getElementById('sheet').src=file;document.getElementById('sheet').alt=selected.label+' · sechs Beatpositionen bei '+scale+'facher Größe';document.getElementById('full').href=file;document.getElementById('download').href=file;
 document.getElementById('record').textContent=JSON.stringify(selected,null,2);
}
for(const [id,label]of Object.entries(characters)){const button=document.createElement('button');button.dataset.id=id;button.textContent=label;button.onclick=()=>{group=id;selected=entries.find(item=>id==='shared'?!item.owner:item.owner===id);draw();};document.getElementById('characters').append(button);}
document.querySelectorAll('#scales button').forEach(button=>button.onclick=()=>{scale=Number(button.dataset.scale);draw();});draw();
</script></html>
'''


def image_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if not header.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Not a PNG: {path.name}")
    return struct.unpack(">II", header[16:24])


def main() -> int:
    report = json.loads((OUTPUT / "verification-rendered.json").read_text())
    native = json.loads((OUTPUT / "native-verification.json").read_text())
    styles = report["styles"]
    files = [name for entry in styles for name in entry["captures"]] + [report["side_crew"]]
    missing = [name for name in files if not (OUTPUT / name).is_file()]
    invalid_sizes = [name for name in files if (OUTPUT / name).is_file() and image_size(OUTPUT / name) != (1440, 960)]
    clip = OUTPUT / "native.mp4"
    media = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(clip)
    ], text=True))
    audio = [stream for stream in media["streams"] if stream["codec_type"] == "audio"]
    verification = {
        "styles": len(styles), "shared": sum(not entry["owner"] for entry in styles),
        "character_moves": sum(bool(entry["owner"]) for entry in styles),
        "images": len(files), "videos": 1, "missing": missing, "invalid_sizes": invalid_sizes,
        "render_checks": report["checks"], "render_failures": report["failures"],
        "native_checks": native["checks"], "native_failures": native["failures"],
        "original_side_art": all(entry.get("side_art") for entry in styles),
        "native_video_seconds": float(media["format"]["duration"]),
        "native_audio_streams": len(audio), "prepared_state": report["fixture"],
    }
    (OUTPUT / "gallery-verification.json").write_text(json.dumps(verification, indent=2) + "\n")
    if (missing or invalid_sizes or len(styles) != 33 or len(files) != 67 or
        report["failures"] or native["failures"] or not audio or not verification["original_side_art"]):
        print(json.dumps(verification, indent=2))
        return 1
    result = (f'33 neue Moves · 67 Renderbilder · echte Musik bei 118 BPM · '
              f'{report["checks"]}/{report["checks"]} Renderprüfungen und '
              f'{native["checks"]}/{native["checks"]} Audio-/Bewegungsprüfungen bestanden')
    data = json.dumps(styles, ensure_ascii=False).replace("</", "<\\/")
    (OUTPUT / "index.html").write_text(PAGE.replace("__RESULT__", html.escape(result)).replace("__ENTRIES__", data))
    print(json.dumps(verification, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
