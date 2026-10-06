"""Build an offline gallery from actual Godot captures and generated plates."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/all-level-layers"


def encode_previews(clean_frames: bool = False) -> None:
    directories = sorted(OUTPUT.glob("*/frames"))
    if len(directories) != 13:
        raise ValueError(f"Expected 13 complete previews, found {len(directories)}")
    for directory in directories:
        extension = "jpg" if (directory / "0000.jpg").exists() else "png"
        expected = {f"{index:04d}.{extension}" for index in range(48)}
        if {path.name for path in directory.iterdir()} != expected:
            raise ValueError(f"Incomplete or unexpected preview files: {directory}")
        target = directory.parent / "parallax.mp4"
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-framerate", "24", "-i", str(directory / f"%04d.{extension}"),
            "-c:v", "libx264", "-threads", "2", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(target),
        ], check=True)
        probe = json.loads(subprocess.check_output([
            "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
            "stream=width,height,nb_frames,duration", "-of", "json", str(target),
        ]))["streams"][0]
        if (probe["width"], probe["height"], int(probe["nb_frames"])) != (1920, 1080, 48):
            raise ValueError(f"Unexpected encoded preview: {target}: {probe}")
        if abs(float(probe["duration"]) - 2.0) > .01:
            raise ValueError(f"Unexpected preview duration: {target}: {probe}")
        if clean_frames:
            shutil.rmtree(directory)
        print(f"Encoded and verified {target.relative_to(ROOT)}")


def build() -> None:
    report = json.loads((OUTPUT / "verification-rendered.json").read_text())
    entries = report["locations"]
    for entry in entries:
        entry["plates"] = ["../../" + path.removeprefix("res://") for path in entry["plates"]]
        entry["video"] = (OUTPUT / entry["id"] / "parallax.mp4").exists()
        entry["sampling_previews"] = entry["id"] in {"mountain_pass", "ash_foundry", "abandoned_harbor"}
    html = r'''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bunkercrew · Tiefenebenen aller Schauplätze</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#121c1c;color:#eee7d1;font:16px/1.5 system-ui}main{max-width:1600px;margin:auto;padding:28px 24px}h1{font-size:30px;margin:0 0 12px}h2{font-size:22px;margin:0}p{max-width:100ch;color:#b8c3b7}a{color:#e2be6c}nav{display:flex;flex-wrap:wrap;gap:8px;margin:20px 0}button{font:inherit;border:1px solid #4b6159;border-radius:7px;color:#eee7d1;background:#25362f;padding:8px 12px;cursor:pointer}button[aria-pressed=true]{background:#44482c;border-color:#dfbd65;color:#efcd7f}button:focus-visible,input:focus-visible,a:focus-visible{outline:2px solid #dfbd65;outline-offset:3px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}figure{margin:0;min-width:0}img,video{display:block;width:100%;height:auto;background:#192921;border:1px solid #3c5148;border-radius:8px}figcaption{padding:8px 0;color:#c0c7b5;font-size:14px}.plates{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin:20px 0}.plates img{background:repeating-conic-gradient(#29392f 0% 25%,#36473a 0% 50%) 50%/24px 24px}.single{grid-column:1/-1}.small{font-size:13px}.result{color:#d8c383}details{margin:22px 0}summary{cursor:pointer;color:#e2be6c}
.comparison-surface{--reveal:50%;position:relative;overflow:hidden;border:1px solid #3c5148;border-radius:8px;cursor:ew-resize;touch-action:pan-y;user-select:none}.comparison-surface img{border:0;border-radius:0;pointer-events:none}.comparison-before{position:absolute;inset:0;clip-path:inset(0 calc(100% - var(--reveal)) 0 0)}.comparison-before img{height:100%}.comparison-divider{position:absolute;inset:0 auto 0 var(--reveal);width:2px;background:#efcd7f;box-shadow:0 0 5px #101914;pointer-events:none}.comparison-divider::after{content:'↔';position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);display:grid;place-items:center;width:42px;height:42px;border:2px solid #efcd7f;border-radius:50%;color:#efcd7f;background:#172820;font-size:24px}.comparison-badge{position:absolute;top:12px;padding:4px 9px;background:#12201de6;border:1px solid #667368;border-radius:5px;color:#eee7d1;font-size:14px;pointer-events:none}.comparison-badge.before{left:12px}.comparison-badge.after{right:12px}.comparison-controls{display:flex;align-items:center;gap:12px;margin-top:12px}.comparison-controls label{font-size:14px;flex-shrink:0}.comparison-controls input{width:100%;min-width:0;margin:0;accent-color:#dfbd65}.comparison-links{display:flex;flex-wrap:wrap;gap:8px 20px;margin-top:8px;font-size:14px}.sampling-links{border-top:1px solid #3c5148;margin-top:16px;padding-top:12px}.sampling-links span{color:#b8c3b7;font-size:14px}.sampling-links .comparison-links{margin-top:4px}@media(max-width:850px){.grid,.plates{grid-template-columns:1fr}main{padding:20px 12px}h1{font-size:25px}.comparison-controls{gap:8px}.comparison-controls label{font-size:13px}.comparison-badge{top:8px;font-size:12px;padding:3px 6px}.comparison-badge.before{left:8px}.comparison-badge.after{right:8px}}
</style><main><h1>Alle 13 Schauplätze mit bewegten Tiefenebenen</h1>
<p>Himmel, ferne Landschaft und nähere Kulisse sind getrennte Bild-Ebenen. Kamerafahrten erzeugen Tiefe; Wolken, Nebel und örtliche Wasser- und Lichtbewegungen beleben die Umgebung. Die aktuelle Abstimmung zeigt mehr vom Quellbild und vergrößert seine Textur weniger. Nähere Felsen, Bäume und Gebäude erhalten stärkere Details und Konturen, die Ferne eine schwächere Anpassung. Der Himmel behält seine ruhigen Farbverläufe. F8 vergleicht im Spiel mit dem alten Panorama. F3 reduziert die Zusatzanimationen; Pause hält die Hintergrundzeit an.</p>
<p class="result">@@RESULT@@ · Kameraprüfung bei 1920×1080, 2560×1080 und 1280×960.</p>
<nav id="levels" aria-label="Schauplätze"></nav><h2 id="title"></h2>
<nav id="modes" aria-label="Vergleichsansichten"></nav><div id="views" class="grid"></div>
<details><summary>Die drei einzelnen Bild-Ebenen</summary><div id="plates" class="plates"></div></details>
<p class="small">Vorbereitete echte Spielszenen: ein stehender Spieler, Betonbastion links, angehaltene Wellen und sonstige Animationen. Die Hintergrundzeit und die Kamera werden kontrolliert bewegt. Videos laufen mit 24 Bildern/s und dienen der Sichtprüfung.</p>
<p class="small">Schärfevergleich und Nahzoom zeigen die bisherige Version und die aktuelle Abstimmung mit identischer Kamera und eingefrorener Spielszene. Der Bildausschnitt der Kulisse verändert sich durch die geringere Texturvergrößerung. Die lokalen Konturen bleiben innerhalb der vorhandenen Farbpalette; transparente Ränder werden geschützt. Bergpass, Aschewerk und Hafen bieten zusätzlich drei Filtervarianten mit dem aktuellen Bildausschnitt. Die gemalten Texturen und der freie Kamera-Zoom ergeben keine durchgehend ganzzahlige Pixelabbildung. <a href="sharpness/verification.json">GPU-Prüfung der bewegten Pixelkanten und Alpha-Übergänge</a>.</p>
<p class="small"><a href="verification-rendered.json">Prüfbericht</a> · <a href="gallery-verification.json">Galerieprüfung</a> · <a href="verification-summary.json">Leistungsvergleich</a> · <a href="../../assets/environments/layers/prompts.json">Prompts der 36 neuen Ebenen</a> · <a href="../../scripts/parallax_catalog.gd">Level-Konfiguration</a></p>
</main><script>'use strict';const entries=@@ENTRIES@@;const modes={'quality':'Schärfevergleich','compare':'Vorher / Nachher','pan':'Kamerafahrt','close':'Nahzoom','video':'Animationsvideo'};let selected=entries.find(e=>e.id==='mountain_pass')||entries[0],mode='quality';
function figure(src,label){const item=document.createElement('figure'),link=document.createElement('a'),img=document.createElement('img'),caption=document.createElement('figcaption');link.href=src;img.src=src;img.alt=label;link.append(img);caption.textContent=label;item.append(link,caption);return item;}
function movie(src,label,poster){const item=document.createElement('figure'),video=document.createElement('video'),caption=document.createElement('figcaption');video.controls=true;video.loop=true;video.muted=true;video.playsInline=true;video.preload='metadata';video.src=src;video.poster=poster;caption.textContent=label;item.append(video,caption);return item;}
function comparison(beforeSrc,afterSrc,description){
 const item=document.createElement('figure');item.className='single comparison';
 const surface=document.createElement('div');surface.className='comparison-surface';surface.id='comparison-surface';
 const after=document.createElement('img');after.src=afterSrc;after.alt=selected.title+' · aktuelle Abstimmung · '+description;after.draggable=false;
 const beforeLayer=document.createElement('div');beforeLayer.className='comparison-before';const before=document.createElement('img');before.src=beforeSrc;before.alt=selected.title+' · bisherige Version · '+description;before.draggable=false;beforeLayer.append(before);
 const divider=document.createElement('div');divider.className='comparison-divider';divider.setAttribute('aria-hidden','true');surface.append(after,beforeLayer,divider);
 for(const [className,text] of [['before','Bisher'],['after','Aktuell']]){const badge=document.createElement('span');badge.className='comparison-badge '+className;badge.textContent=text;badge.setAttribute('aria-hidden','true');surface.append(badge);}
 const controls=document.createElement('div');controls.className='comparison-controls';const label=document.createElement('label');label.htmlFor='comparison-reveal';label.textContent='Bildgrenze verschieben';
 const range=document.createElement('input');range.type='range';range.id='comparison-reveal';range.min='0';range.max='100';range.step='1';range.value='50';range.setAttribute('aria-label',selected.title+' · Anteil der bisherigen Version');range.setAttribute('aria-controls',surface.id);range.setAttribute('aria-describedby','comparison-instructions');
 function reveal(value){range.value=String(Math.round(Math.max(0,Math.min(100,value))));surface.style.setProperty('--reveal',range.value+'%');range.setAttribute('aria-valuetext','Bisher '+range.value+' Prozent, aktuell '+(100-Number(range.value))+' Prozent');}range.addEventListener('input',()=>reveal(Number(range.value)));reveal(50);
 function revealAt(event){const rect=surface.getBoundingClientRect();reveal((event.clientX-rect.left)/rect.width*100);}surface.addEventListener('pointerdown',event=>{if(event.button!==0)return;surface.setPointerCapture(event.pointerId);revealAt(event);});surface.addEventListener('pointermove',event=>{if(surface.hasPointerCapture(event.pointerId))revealAt(event);});surface.addEventListener('pointerup',event=>{if(surface.hasPointerCapture(event.pointerId)){revealAt(event);surface.releasePointerCapture(event.pointerId);}});
 controls.append(label,range);const caption=document.createElement('figcaption');caption.id='comparison-instructions';caption.textContent='Links bisher · rechts aktuell · '+description+'. Im Bild ziehen oder den Regler mit den Pfeiltasten bedienen.';
 const links=document.createElement('div');links.className='comparison-links';for(const [src,text] of [[beforeSrc,'Bisherige Version in voller Auflösung'],[afterSrc,'Aktuelle Version in voller Auflösung']]){const link=document.createElement('a');link.href=src;link.textContent=text;links.append(link);}
 item.append(surface,controls,caption,links);return item;
}
function samplingLinks(zoom){const item=document.createElement('div');item.className='single sampling-links';const note=document.createElement('span');note.textContent='Filtervarianten mit dem aktuellen Bildausschnitt · Zoom '+zoom.replace('.',',')+' · volle Auflösung:';const links=document.createElement('div');links.className='comparison-links';for(const [id,text]of [['linear','Weiche Filterung'],['point','Reine Pixelabtastung'],['crisp','Aktuelle Detailabstimmung']]){const link=document.createElement('a');link.href='sharpness/'+selected.id+'-'+id+'-'+zoom+'.png';link.textContent=text;links.append(link);}item.append(note,links);return item;}
function draw(){
 document.getElementById('title').textContent=selected.title;
 document.querySelectorAll('#levels button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.id===selected.id)));
 document.querySelectorAll('#modes button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.id===mode)));
 const views=document.getElementById('views');views.querySelectorAll('video').forEach(video=>video.pause());views.replaceChildren();const base=selected.id+'/';
 if(mode==='quality'){
  if(selected.sampling_previews){const prefix='sharpness/'+selected.id+'-';views.append(comparison(prefix+'previous-1.0.png',prefix+'crisp-1.0.png','Zoom 1'),samplingLinks('1.0'));}
  else{views.append(comparison(base+'normal-previous.png',base+'layers-normal.png','Zoom 1'));}
 }else if(mode==='compare'){
  views.append(figure(base+'original.png','Ursprüngliches Panorama · Zoom 0,65'),figure(base+'layers-t8.png','Drei Tiefenebenen · gleiche Kamera · Zeit 8 s'));
 }else if(mode==='pan'){
  views.append(figure(base+'layers-t8.png','Kameramitte x=720'),figure(base+'layers-pan.png','Kameramitte x=1200 · unterschiedliche Tiefenverschiebung'));
 }else if(mode==='close'){
  if(selected.sampling_previews){const prefix='sharpness/'+selected.id+'-';views.append(comparison(prefix+'previous-2.2.png',prefix+'crisp-2.2.png','Zoom 2,2'),samplingLinks('2.2'));}
  else{views.append(comparison(base+'close-previous.png',base+'layers-close.png','Zoom 2,2 · Kamera bei der Spielfigur'));}
 }else if(selected.video){
  views.append(movie(base+'parallax-previous.mp4','Bisherige Version',base+'layers-previous.png'),movie(base+'parallax.mp4','Aktuelle Abstimmung',base+'layers-t8.png'));
  const together=document.createElement('button');together.textContent='Beide Videos gemeinsam abspielen';together.className='single';
  together.onclick=()=>{for(const video of views.querySelectorAll('video')){video.currentTime=0;video.play().catch(()=>{});}};views.append(together);
 }else{const p=document.createElement('p');p.textContent='Die gerenderten Einzelbilder sind verfügbar.';views.append(p);}
 const plates=document.getElementById('plates');plates.replaceChildren();
 selected.plates.forEach((path,index)=>{const item=figure(path,['Himmel','Ferne Landschaft','Nähere Kulisse'][index]);item.querySelector('img').loading='lazy';plates.append(item);});
}
for(const entry of entries){const button=document.createElement('button');button.textContent=entry.title;button.dataset.id=entry.id;button.onclick=()=>{selected=entry;draw();};document.getElementById('levels').append(button);}for(const [id,label]of Object.entries(modes)){const button=document.createElement('button');button.textContent=label;button.dataset.id=id;button.onclick=()=>{mode=id;draw();};document.getElementById('modes').append(button);}draw();</script></html>'''
    html = html.replace("@@ENTRIES@@", json.dumps(entries, ensure_ascii=False))
    html = html.replace("@@RESULT@@", f"{report['checks'] - report['failures']} / {report['checks']} Grafik- und Verhaltensprüfungen bestanden")
    (OUTPUT / "index.html").write_text(html)
    print(OUTPUT / "index.html")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--encode", action="store_true", help="Encode all thirteen Godot frame sequences first")
    parser.add_argument("--clean-frames", action="store_true", help="Remove verified temporary frames after encoding")
    args = parser.parse_args()
    if args.clean_frames and not args.encode:
        parser.error("--clean-frames requires --encode")
    if args.encode:
        encode_previews(args.clean_frames)
    build()
