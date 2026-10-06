#!/usr/bin/env python3
"""Build a portable native music listening gallery and measured energy previews.

Nothing plays automatically. HTTP uses WebAudio; a local file keeps its native
media playback and uses an offline measured low-band envelope instead of routing
an opaque file origin through a potentially silent WebAudio MediaElementSource.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
import re
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/live-music"
DESCRIPTIONS = {
    "sector07": "Dunkles Industriemotiv, trockene Impulse und ein ruhiger Grundpuls.",
    "ash_foundry": "Trockenes Metall, kurze Räume und warmer Druck im Bass.",
    "abandoned_harbor": "Bewegliche Figuren, schwingende Zwischenräume und weite Echos.",
    "basalt_quarry": "Schwere, sparsame Schläge mit tiefem Steincharakter.",
    "overgrown_steelworks": "Organische Bewegung zwischen verwitterten Maschinen.",
    "frozen_rail_yard": "Kalte Höhen, klare Pausen und ein zurückhaltendes Motiv.",
    "iron_canyon": "Vorwärtsdrang, enge Intervalle und harte Metallakzente.",
    "flooded_power_station": "Gedämpfte Tiefe, fließende Figuren und lange Räume.",
    "mountain_pass": "Langsam, dunkel und weit; bewusster Platz zwischen den Schlägen.",
    "storm_dam": "Wasser, Spannung und ein drängender, geordneter Puls.",
    "sulfur_refinery": "Scharfe Farben, nervöse Figuren und kontrollierter Druck.",
    "radar_highlands": "Kühle Signalfiguren und sparsame, räumliche Antworten.",
    "buried_megafactory": "Tiefe Maschinen, dunkle Resonanz und schwere Betonung.",
}
SCORES = {
    "sector07":"base", "ash_foundry":"foundry", "abandoned_harbor":"tidal", "basalt_quarry":"foundry",
    "overgrown_steelworks":"base", "frozen_rail_yard":"frost", "iron_canyon":"foundry",
    "flooded_power_station":"tidal", "mountain_pass":"frost", "storm_dam":"tidal",
    "sulfur_refinery":"foundry", "radar_highlands":"frost", "buried_megafactory":"foundry",
}
GENRES = {"minimal_techno":"Minimal Techno", "schranz":"Schranz", "hip_hop":"Hip-Hop / Boom-Bap", "breakbeat":"Breakbeat"}


def legacy_path(score: str, combat: bool) -> str:
    suffix = "combat" if combat else "calm"
    infix = "" if score == "base" else score + "_"
    return f"assets/audio/music_{infix}{suffix}.ogg"


def measure(path: str) -> tuple[str, dict]:
    full = ROOT / path
    digest = hashlib.sha256(full.read_bytes()).hexdigest()
    raw = subprocess.run([
        "ffmpeg", "-v", "error", "-threads", "1", "-i", str(full), "-af", "lowpass=f=180",
        "-ar", "1600", "-ac", "1", "-f", "f32le", "-",
    ], check=True, stdout=subprocess.PIPE).stdout
    values = np.frombuffer(raw, dtype="<f4")
    padded = np.pad(values, (0, (-len(values)) % 100))
    energy = np.sqrt(np.mean(padded.reshape(-1,100).astype(np.float64) ** 2, axis=1))
    normalization = max(float(np.percentile(energy, 95)), 0.008)
    return path, {"sha256":digest,"energy_hz":16,"energy":[round(float(v),4) for v in np.clip(energy/normalization,0,1)]}


def build() -> None:
    catalog = json.loads((ROOT / "assets/environments/catalog.json").read_text())
    native = json.loads((OUT / "native-themes.json").read_text())
    genre_profiles = json.loads((OUT / "native-themes-genres.json").read_text())
    sources = json.loads((OUT / "listening-sources.json").read_text())
    entries = {item["id"]:item for item in catalog["environments"]}
    stage_sources = {(item["theme"],item["genre"],item["intensity"]):item for item in sources["intensity_clips"]}
    paths = set()
    rows = []
    for id in native:
        profile = native[id]
        default_genre = list(GENRES)[profile["genre"]]
        styles = {}
        for genre in GENRES if id == "ash_foundry" else [default_genre]:
            tracks = []
            for stage in range(4):
                clip = stage_sources[(id,genre,stage)]
                paths.add(clip["preview"])
                tracks.append({"stage":stage,"source":clip["preview"],"seconds":clip["seconds"],"sha256_pcm":clip["sha256_pcm"]})
            styles[genre] = {"bpm":genre_profiles[id+"|"+genre]["bpm"], "stages":tracks}
        live = f"artifacts/live-music/listening/{id}/live.ogg"
        quiet = legacy_path(SCORES[id],False)
        combat = legacy_path(SCORES[id],True)
        paths.update([live,quiet,combat])
        rows.append({"id":id,"title":entries[id]["title"],"description":DESCRIPTIONS[id],"bpm":profile["bpm"],"genre":default_genre,"genres":styles,"seed":12345,"engine_seed":profile["seed"],"key":profile["key"],"mode":profile["scale"],"phrase_bars":profile["phrase_bars"],"stages":styles[default_genre]["stages"],"arrangement":live,"legacy":[quiet,combat]})
    paths.add(sources["long_arrangement"]["preview"])
    for path in paths:
        if not (ROOT/path).is_file():
            raise FileNotFoundError(path)
    energy_path = OUT / "gallery-energy.json"
    old_energy = json.loads(energy_path.read_text()) if energy_path.exists() else {}
    pending = [path for path in sorted(paths) if path not in old_energy or old_energy[path].get("sha256") != hashlib.sha256((ROOT/path).read_bytes()).hexdigest()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        for path, value in executor.map(measure,pending):
            old_energy[path] = value
    energy = {path:old_energy[path] for path in sorted(paths)}
    energy_path.write_text(json.dumps(energy,separators=(",",":")))
    data = {"themes":rows,"genres":GENRES,"energy":energy,"long":sources["long_arrangement"],"loudness":json.loads((OUT/"theme-loudness.json").read_text())}
    html = TEMPLATE.replace("__DATA__",json.dumps(data,ensure_ascii=False,separators=(",",":")))
    (OUT/"index.html").write_text(html)
    clip_count = sum(len(row["genres"])*4 for row in rows)
    (OUT/"gallery-sources.json").write_text(json.dumps({"themes":13,"intensity_clips":clip_count,"ash_foundry_genres":list(GENRES),"arrangements":13,"long_audio_seconds":640,"native_source":"listening-sources.json","legacy_sources":sorted({path for row in rows for path in row["legacy"]}),"energy_files":len(energy),"human_listening_validation":"pending; rendered previews are available for assessment"},indent=2))
    print(f"LIVE MUSIC GALLERY: 13 themes, {clip_count} intensity clips, 13 arrangements; {len(energy)} measured energy previews")


TEMPLATE = r'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bunkercrew · Musik hören</title>
<style>
:root{color-scheme:dark;--bg:#101715;--panel:#19221e;--line:#435147;--gold:#e0b768;--text:#e5e8d8;--muted:#aab6a6}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,sans-serif}button,input,select,textarea{font:inherit}button,select,input,textarea{border:1px solid var(--line);border-radius:4px;background:#141e19;color:var(--text)}button{padding:10px 14px;cursor:pointer}button:hover,button:focus-visible{border-color:var(--gold)}button[aria-pressed=true]{background:#343323;border-color:var(--gold);color:#ffda91}a{color:var(--gold)}main{max-width:1380px;margin:auto;padding:30px}header{display:flex;align-items:flex-start;justify-content:space-between;gap:24px}h1{font-size:clamp(26px,4vw,42px);line-height:1.12;margin:4px 0 15px}h2{margin:0 0 10px;font-size:23px}.eyebrow{letter-spacing:.14em;color:var(--gold);font-size:13px}.muted{color:var(--muted)}.intro{max-width:850px;margin:0 0 26px}.layout{display:grid;grid-template-columns:250px minmax(0,1fr);gap:24px}nav{display:grid;gap:7px;align-content:start}nav button{text-align:left;min-height:44px}.hero{position:relative;overflow:hidden;min-height:230px;padding:26px;border:1px solid var(--line);border-radius:6px;background:#23342c}.hero img{position:absolute;width:100%;height:100%;object-fit:cover;inset:0;opacity:.35}.hero:after{content:"";position:absolute;inset:0;background:linear-gradient(90deg,rgba(12,22,16,.7),rgba(12,22,16,.35))}.hero div{position:relative;z-index:1}.hero p{max-width:660px}.chips{display:flex;gap:8px;flex-wrap:wrap}.chip{background:#121d16bb;border:1px solid #59614b;padding:3px 9px;border-radius:3px;font-size:14px}.panel{margin-top:16px;padding:20px;border:1px solid var(--line);border-radius:6px;background:var(--panel)}.row{display:flex;gap:9px;align-items:center;flex-wrap:wrap}.stages button{flex:1;min-width:120px}.sources{margin:14px 0}.sources button{flex:1;min-width:150px}audio{display:block;width:100%;margin:16px 0 6px}.meter{display:flex;align-items:center;gap:20px;min-height:108px;padding:12px 4px}.pulse{width:64px;height:64px;border:1px solid #dab366;border-radius:50%;background:#51442a;flex-shrink:0;transform:scale(.87);box-shadow:inset 0 0 12px #0005;transition:background .1s}.meter canvas{width:100%;height:72px;display:block;background:#101a14;border:1px solid #344536}.meter div:last-child{min-width:0;flex:1}#beatText{font-variant-numeric:tabular-nums;font-size:14px;color:var(--muted);margin-top:6px}.small{font-size:14px}.notice{padding-left:12px;border-left:3px solid var(--gold)}textarea{width:100%;min-height:78px;padding:10px;resize:vertical}label{display:block;margin:12px 0 5px}select{padding:9px;width:100%}.feedback-grid{display:grid;grid-template-columns:150px 1fr;gap:16px}.footer{margin:28px 0;color:var(--muted);font-size:14px}.links{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0}.time{font-variant-numeric:tabular-nums}details{margin-top:20px}summary{cursor:pointer;color:var(--gold)}code{background:#101815;padding:1px 4px}.download{display:inline-block;margin-top:10px}@media(max-width:760px){main{padding:16px}header{display:block}.layout{grid-template-columns:1fr}nav{grid-template-columns:repeat(2,minmax(0,1fr));gap:5px}nav button{font-size:14px;padding:8px}.hero{min-height:210px;padding:18px}.panel{padding:15px}.feedback-grid{grid-template-columns:1fr;gap:0}.stages button{min-width:40%}.meter{gap:12px}.pulse{width:44px;height:44px}}
@media(prefers-reduced-motion:reduce){.pulse{transform:none!important;box-shadow:none!important}}
</style>
<main><header><div><div class="eyebrow">BUNKERCREW / NATIVE MUSIK</div><h1>Dein Stil. Dein Leitthema.</h1></div><a href="../rhythm-music/index.html">Tanzstile &amp; Musik-Labor ansehen</a></header>
<p class="intro muted">Die native Engine erzeugt diese Stücke aus denselben Leitthemen wie das Spiel. Getragener Einstieg, Aufbau und klarer Drop. Dreizehn Leitthemen und vier Stile im Aschewerk: Minimal Techno, Schranz, Hip-Hop und Breakbeat. Wähle einen Schauplatz und starte die Wiedergabe selbst.</p>
<div class="layout"><nav id="themes" aria-label="Schauplatz"></nav><section><div class="hero"><img id="cover" alt=""><div><div class="eyebrow">LEITTHEMA</div><h2 id="title"></h2><p id="description"></p><div class="chips"><span class="chip" id="tempo"></span><span class="chip" id="mode"></span><span class="chip" id="phrase"></span><span class="chip" id="seed"></span></div></div></div>
<div class="panel"><h2>Hörvergleich</h2><label for="genre">Musikstil</label><select id="genre" aria-label="Musikstil"></select><p class="small muted" id="genreNotice"></p><div class="row stages" id="stages" aria-label="Musikintensität"></div><div class="row sources" id="sources"><button data-source="native" aria-pressed="true">Neue native Engine</button><button data-source="legacy" aria-pressed="false">Bisherige OGG-Musik</button><button data-source="arrangement" aria-pressed="false">120 s Arrangement</button></div>
<p class="muted small" id="clipLabel"></p><audio id="audio" controls preload="metadata"></audio><div class="row"><button id="play">Abspielen</button><button id="stop">Stoppen</button><a id="download" class="small" download>Audiodatei laden</a></div>
<div class="meter" aria-hidden="true"><div class="pulse" id="pulse"></div><div><canvas id="energy" width="700" height="80"></canvas><div id="beatText">Wiedergabe gestoppt</div></div></div><p class="small muted" id="analysisMode"></p>
<p class="small notice">Dies sind gerenderte Hörproben. Die musikalische Beurteilung durch ausgiebiges Anhören ist noch offen. Die Anzeige hier folgt der Browser-Wiedergabe; im Spiel folgt die Beat-Uhr direkt den hörbaren Mixer-Samples.</p></div>
<div class="panel"><h2>Aschewerk über 20 Wellen</h2><p class="muted small">10:40 Minuten mit vorbereiteten Bau-, Warn-, Angriffs- und Ruhephasen. Audio-Simulation; der komplette Spielablauf wurde für diese Datei nicht aufgenommen.</p><button id="long">20-Wellen-Hörprobe laden</button><span class="small muted"> · startet erst nach „Abspielen“</span></div>
<div class="panel"><h2>Dein Höreindruck</h2><p class="muted small">Bewertungen bleiben in diesem Browser. Du kannst sie als JSON herunterladen und im Musik-Labor mit einer konkreten Variante weiterarbeiten.</p><div class="feedback-grid"><div><label for="rating">Bewertung</label><select id="rating"><option value="0">Noch unbewertet</option><option value="1">1 · stört</option><option value="2">2 · anstrengend</option><option value="3">3 · brauchbar</option><option value="4">4 · angenehm</option><option value="5">5 · Lieblingsvariante</option></select></div><div><label for="feedback">Was funktioniert, was nervt?</label><textarea id="feedback" placeholder="Zum Beispiel: guter Grundpuls, aber die Höhen im Angriff sind zu scharf."></textarea></div></div><div class="row"><button id="save">Bewertung lokal speichern</button><button id="export">Bewertungen als JSON laden</button><button id="labExport">Aktuelle Variante fürs Labor</button><span id="saved" class="small muted" role="status"></span></div></div>
<details><summary>Messungen, Quelle und Spielvorschau</summary><p class="small muted">13 eigene Leitthemen · 64 Clips mit je 16 Takten, davon 16 Stilvergleiche im Aschewerk · 13 Arrangements mit je 120 Sekunden. Die nativen Arrangements sind auf ungefähr −16,5 LUFS abgestimmt. Die Intensitätsstufen verändern Besetzung und Spannung. Der Hörvergleich nutzt die Originaldateien mit gleichem Reglerwert; er ist kein Lautheitsblindtest.</p><div class="links"><a href="listening-sources.json">Native Renderquelle</a><a href="theme-loudness.json">Lautheitsmessung</a><a href="native-profiles-verification.json">Native Gleichheitsprüfung</a><a href="../rhythm-music/dance-styles.mp4">Animierte Tanzstile</a><a href="../rhythm-music/example-feedback.json">Labor-Feedback JSON</a></div><p class="small muted">Im Spiel: Hauptmenü → Musik-Labor. Dort lassen sich Leitthema, Musikstil, Seed, Tempo, Intensität und Tanzstil pro Figur anhören und ansehen. Das Labor beeinflusst keine Partie.</p></details></section></div>
<div class="footer">Tessel · Godot-Mixer · lokale Erzeugung. Die vorhandenen OGG-Dateien bleiben die automatische Absicherung, wenn die Erweiterung fehlt.</div></main>
<script>
const DATA=__DATA__;
const $=id=>document.getElementById(id), audio=$('audio'),ctx=$('energy').getContext('2d');
const stages=['0 · Ruhe','1 · Aufbau','2 · Spannung','3 · Angriff'];
const notes=['C','Des','D','Es','E','F','Fis','G','As','A','B','H'], modes=['Moll-Pentatonik','Dur-Pentatonik','Dorisch','Phrygisch'];
let selected=DATA.themes.find(row=>row.id==='ash_foundry'),genre=selected.genre,stage=0,source='native',path='',audioContext=null,analyser=null,measure=null,history=Array(70).fill(0),ratings={};
try{ratings=JSON.parse(localStorage.getItem('bunkercrew-listening-feedback-v1')||'{}')}catch{}
for(const row of DATA.themes){const button=document.createElement('button');button.textContent=row.title;button.dataset.id=row.id;button.addEventListener('click',()=>{selected=row;genre=row.genre;source='native';setTheme()});$('themes').append(button)}
for(let value=0;value<4;value++){const button=document.createElement('button');button.textContent=stages[value];button.dataset.stage=value;button.addEventListener('click',()=>{stage=value;source='native';loadTrack()});$('stages').append(button)}
function href(value){return '../../'+value}
function profile(){return selected.genres[genre]||selected.genres[selected.genre]}
function scoreGenre(){return source==='arrangement'||source==='long'?selected.genre:genre}
function audibleBpm(){return source==='arrangement'||source==='long'?selected.bpm:profile().bpm}
function updateGenre(){const current=$('genre');current.replaceChildren();for(const id of Object.keys(selected.genres)){const option=document.createElement('option');option.value=id;option.textContent=DATA.genres[id]+(id===selected.genre?' · Schauplatz-Empfehlung':'');current.append(option)}current.value=genre;current.disabled=current.options.length===1;$('genreNotice').textContent=selected.id==='ash_foundry'?'Vier Stile, dasselbe Motiv und derselbe Seed. Ruhe ist der getragene Einstieg; Angriff ist der volle Groove.':'Diese Hörprobe zeigt den kuratierten Schauplatz-Stil. Alle vier Stile kannst du im Musik-Labor für dieses Leitthema erzeugen.'}
function loadTrack(){audio.pause();history.fill(0);path=source==='legacy'?selected.legacy[stage>=2?1:0]:source==='arrangement'?selected.arrangement:source==='long'?DATA.long.preview:profile().stages[stage].source;audio.src=href(path);audio.load();$('download').href=href(path);$('download').download=path.split('/').pop();for(const button of $('stages').children)button.setAttribute('aria-pressed',String(Number(button.dataset.stage)===stage));for(const button of $('sources').children)button.setAttribute('aria-pressed',String(button.dataset.source===source));$('clipLabel').textContent=source==='native'?`${DATA.genres[genre]} · ${stages[stage]} · 16 Takte · ${Math.round(profile().stages[stage].seconds)} Sekunden · gleicher Seed und gleiches Motiv`:source==='legacy'?`Bisherige ${stage>=2?'Kampf-':'Ruhe-'}Musik · Originalaufnahme`:source==='long'?'Aschewerk · vorbereitete 20-Wellen-Audio-Simulation · 640 Sekunden':'Native Entwicklung der Besetzung über 120 Sekunden';$('play').textContent='Abspielen';$('analysisMode').textContent=location.protocol==='file:'?'Energie: gemessener Bassbereich der Audiodatei · Takt: Browser-Hörposition':'Energie: WebAudio im Bassbereich · Takt: Browser-Hörposition';$('tempo').textContent=`${audibleBpm()} BPM · ${DATA.genres[source==='arrangement'||source==='long'?selected.genre:genre]}`;loadFeedback()}
function setTheme(){for(const button of $('themes').children)button.setAttribute('aria-pressed',String(button.dataset.id===selected.id));$('title').textContent=selected.title;$('description').textContent=selected.description;$('cover').src=`../../assets/environments/v3/${selected.id}.png`;$('tempo').textContent=`${selected.bpm} BPM`;$('mode').textContent=`${notes[selected.key]} · ${modes[selected.mode]}`;$('phrase').textContent=`${selected.phrase_bars} Takte pro Phrase`;$('seed').textContent=`Seed ${selected.seed}`;updateGenre();loadTrack()}
$('genre').addEventListener('change',()=>{genre=$('genre').value;source='native';loadTrack()});
for(const button of $('sources').children)button.addEventListener('click',()=>{source=button.dataset.source;loadTrack()});
$('long').addEventListener('click',()=>{selected=DATA.themes.find(row=>row.id==='ash_foundry');genre=selected.genre;setTheme();source='long';loadTrack()});
async function prepareAnalysis(){if(location.protocol==='file:'||audioContext)return;try{audioContext=new(window.AudioContext||window.webkitAudioContext)();const media=audioContext.createMediaElementSource(audio);media.connect(audioContext.destination);const low=audioContext.createBiquadFilter();low.type='lowpass';low.frequency.value=180;analyser=audioContext.createAnalyser();analyser.fftSize=256;measure=new Float32Array(analyser.fftSize);media.connect(low);low.connect(analyser);await audioContext.resume()}catch{analyser=null;$('analysisMode').textContent='Energie: gemessener Bassbereich der Datei · Takt: Browser-Hörposition'}}
$('play').addEventListener('click',async()=>{if(!audio.paused){audio.pause();return}await prepareAnalysis();if(audioContext?.state==='suspended')await audioContext.resume();try{await audio.play()}catch(error){$('analysisMode').textContent='Wiedergabe konnte nicht starten: '+error.message}});
$('stop').addEventListener('click',()=>{audio.pause();audio.currentTime=0;history.fill(0)});
audio.addEventListener('play',()=>{$('play').textContent='Pausieren';prepareAnalysis()});audio.addEventListener('pause',()=>{$('play').textContent='Abspielen'});
function feedbackKey(){return selected.id+':'+scoreGenre()+':'+stage+':'+source}
function loadFeedback(){const value=ratings[feedbackKey()]||{};$('rating').value=value.rating||0;$('feedback').value=value.feedback||'';$('saved').textContent=''}
$('save').addEventListener('click',()=>{ratings[feedbackKey()]={theme_id:selected.id,genre:scoreGenre(),seed:selected.seed,music_intensity:stage,source,rating:Number($('rating').value),feedback:$('feedback').value.slice(0,2000),timestamp:new Date().toISOString()};try{localStorage.setItem('bunkercrew-listening-feedback-v1',JSON.stringify(ratings));$('saved').textContent='Lokal gespeichert'}catch{$('saved').textContent='In dieser Sitzung gespeichert; JSON-Download verfügbar'}});
$('export').addEventListener('click',()=>{const blob=new Blob([JSON.stringify({version:1,ratings:Object.values(ratings)},null,2)],{type:'application/json'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='bunkercrew-music-listening-feedback.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000)});
$('labExport').addEventListener('click',()=>{const payload={version:2,theme_id:selected.id,genre:scoreGenre(),seed:selected.seed,bpm:audibleBpm(),music_intensity:stage,dance_intensity:1,dance_profiles:{},reduced_motion:false,feedback:($('rating').value==='0'?'':'Bewertung '+$('rating').value+'/5. ')+$('feedback').value.slice(0,1970)};const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='bunkercrew-music-lab-variant.json';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000)});
function animate(){let energy=0;if(!audio.paused&&!audio.ended){if(analyser){analyser.getFloatTimeDomainData(measure);energy=Math.min(1,Math.sqrt(measure.reduce((sum,v)=>sum+v*v,0)/measure.length)*12)}else{const measured=DATA.energy[path];energy=measured?.energy[Math.min(measured.energy.length-1,Math.floor(audio.currentTime*measured.energy_hz))]||0}history.push(energy);history.shift()}const beat=audio.currentTime*audibleBpm()/60,pulse=audio.paused?0:energy;$('pulse').style.transform=`scale(${.87+pulse*.12})`;$('pulse').style.background=`rgba(171,130,48,${.19+pulse*.46})`;$('beatText').textContent=audio.paused?'Wiedergabe gestoppt':source==='legacy'?`Aufnahme ${audio.currentTime.toFixed(1)} s · Energie ${Math.round(energy*100)} %`:`Takt ${Math.floor(beat/4)+1} · Schlag ${Math.floor(beat%4)+1} · ${audio.currentTime.toFixed(1)} s · Energie ${Math.round(energy*100)} %`;ctx.clearRect(0,0,700,80);for(let index=0;index<history.length;index++){const height=history[index]*64;ctx.fillStyle=index>62?'#dfb96e':'#63866c';ctx.fillRect(index*10+2,74-height,6,Math.max(2,height))}requestAnimationFrame(animate)}
setTheme();animate();
window.galleryState=()=>({theme:selected.id,genre:scoreGenre(),stage,source,path,playing:!audio.paused,energyMode:analyser?'webaudio':'measured',feedbackCount:Object.keys(ratings).length});
</script></html>'''

if __name__ == "__main__":
    build()
