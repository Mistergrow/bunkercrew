#!/usr/bin/env python3
"""Validate shipped contact sounds and wind after decoding, without GPU work."""
from pathlib import Path
import hashlib
import itertools
import json
import subprocess
import sys

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/"assets/audio"
REPORT = ROOT/"artifacts/movement-effects"
sys.path.insert(0,str(ROOT/"tools"))
import generate_movement_audio as generator

checks = []


def check(condition,label):
    checks.append({"passed":bool(condition),"label":label})
    print(("PASS " if condition else "FAIL ")+label)


def decode(path):
    details = json.loads(subprocess.check_output(["ffprobe","-v","error","-show_streams","-of","json",str(path)]))["streams"][0]
    raw = subprocess.check_output(["ffmpeg","-v","error","-i",str(path),"-f","f32le","-c:a","pcm_f32le","-"])
    return np.frombuffer(raw,dtype="<f4").reshape(-1,int(details["channels"])).astype(np.float64),int(details["sample_rate"])


def measure(data,rate):
    mono = data.mean(axis=1)
    spectrum = np.abs(np.fft.rfft(mono))**2
    frequency = np.fft.rfftfreq(len(mono),1/rate)
    return {"samples":len(data),"rate":rate,"channels":data.shape[1],"seconds":len(data)/rate,
            "peak":float(np.abs(data).max()),"rms":float(np.sqrt(np.mean(data**2))),
            "oversampled_peak_4x":float(np.abs(resample_poly(data,4,1,axis=0)).max()),
            "dc":float(np.abs(data.mean(axis=0)).max()),
            "centroid_hz":float(np.sum(spectrum*frequency)/spectrum.sum()),
            "above_8khz_fraction":float(spectrum[frequency>8000].sum()/spectrum.sum()),
            "largest_frequency_bin_fraction":float(spectrum.max()/spectrum.sum()),
            "seam_jump":float(np.abs(data[0]-data[-1]).max()),
            "sample_step_p99":float(np.quantile(np.abs(np.diff(data,axis=0)),.99))}


def main():
    REPORT.mkdir(parents=True,exist_ok=True)
    source = json.loads((OUT/"movement_sources.json").read_text())
    files = [OUT/f"{kind}_{variant:02}.wav" for kind,count in source["variants"].items() for variant in range(1,count+1)]
    files.append(OUT/source["wind"]["file"])
    bank = {}
    measurements = {}
    for path in files:
        data,rate = decode(path)
        bank[path.name]=data
        metrics=measure(data,rate)
        measurements[path.name]=metrics
        check(np.isfinite(data).all() and .005<metrics["rms"]<.25,path.name+": finite signal and bounded energy")
        check(metrics["peak"]<.58 and metrics["oversampled_peak_4x"]<.62,path.name+": decoded/reconstructed peaks leave mix headroom")
        check(metrics["dc"]<.0002,path.name+": negligible DC")
        check(metrics["above_8khz_fraction"]<.002,path.name+": restrained highest frequencies")
        if path.suffix==".wav":
            kind=path.stem.rsplit("_",1)[0]
            variant=int(path.stem[-2:])-1
            spec=source["contacts"][kind]
            check(rate==32000 and data.shape[1]==1 and len(data)==round(spec["seconds"]*rate),path.name+": exact declared mono contact length")
            check(np.abs(data[[0,-1]]).max()<=1/32768,path.name+": zero event edges")
            raw=np.round(generator.contact(kind,variant)*32767).astype("<i2")
            check(np.array_equal(raw,np.round(data.ravel()*32768).astype("<i2")),path.name+": deterministic PCM matches shipped asset")
        else:
            check(rate==32000 and data.shape[1]==2 and len(data)==16*rate,path.name+": exact sixteen-second stereo loop")
            check(metrics["seam_jump"]<max(.008,metrics["sample_step_p99"]*1.5),path.name+": wrap step remains inside the conservative signal-step bound")
            seconds_rms=np.sqrt(np.mean(data.reshape(16,rate,2)**2,axis=(1,2)))
            check(seconds_rms.min()>.18*seconds_rms.max(),path.name+": gusts have no silent gap or boundary fade-out")
            check(metrics["largest_frequency_bin_fraction"]<.01,path.name+": broad wind spectrum without a dominant oscillator tone")
            channel_correlation=float(np.corrcoef(data[:,0],data[:,1])[0,1])
            measurements[path.name]["stereo_correlation"]=channel_correlation
            check(.25<channel_correlation<.99,path.name+": coherent stereo width without duplicated channels")
    correlations={}
    for kind,count in source["variants"].items():
        pair_values=[]
        for first,second in itertools.combinations(range(1,count+1),2):
            pair_values.append(float(np.corrcoef(bank[f"{kind}_{first:02}.wav"].ravel(),bank[f"{kind}_{second:02}.wav"].ravel())[0,1]))
        correlations[kind]=pair_values
        check(max(pair_values)<.95,kind+": contact variants differ beyond volume")
    # The recorded fingerprint covers the expansion bank present when these
    # contacts were authored; later independent banks are not that historical set.
    original=json.loads((OUT/"sources.json").read_text())
    original_names={"sources.json",*original["original_score"]["sha256"]}
    for kind,count in original["variants"].items():
        original_names.update(f"{kind}_{index:02}.wav" for index in range(1,count+1))
    for kind in original["music"]["sets"]:
        original_names.update(f"music_{kind}_{phase}.ogg" for phase in ["calm","combat"])
    protected={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in sorted(original_names)}
    check(len(protected)==source["preserved_files"],"Historical protected-bank membership matches its declared count")
    fingerprint=hashlib.sha256(json.dumps(protected,sort_keys=True).encode()).hexdigest()
    check(fingerprint==source["preserved_bank_sha256"],"Existing score, effects, and sources.json preserved byte for byte")
    check(sum(source["variants"].values())==15,"Exactly fifteen contact variants declared")
    result={"passed":sum(item["passed"] for item in checks),"failed":sum(not item["passed"] for item in checks),
            "measurements":measurements,"variant_correlations":correlations,"checks":checks,
            "review":"Technical signal checks only. No listening assessment performed.",
            "peak_method":"Four-times scipy resample_poly; not a certified true-peak meter."}
    (REPORT/"audio-measurements.json").write_text(json.dumps(result,indent=2)+"\n")
    gallery(result)
    print(f"MOVEMENT AUDIO ASSETS: {result['passed']} passed, {result['failed']} failed")
    return 1 if result["failed"] else 0


def gallery(result):
    labels={"step_dry":("Staub und Kies","Weicher Auftritt, lose Körner und kurze Sohlenreibung."),
            "step_metal":("Metallboden","Gedämpfte Plattenresonanz mit getrenntem Fersen- und Zehenkontakt."),
            "step_water":("Flache Pfütze","Kurzer Wasserschwall, Spritzer und kleine Blasen."),
            "step_ice":("Schnee und Eis","Verdichteter Schnee und unregelmäßiges Knirschen."),
            "step_heavy":("Maschinenfuß","Schwerer, gedämpfter Kontakt mit tiefer Gehäusereaktion.")}
    cards=[]
    for kind,(title,description) in labels.items():
        players=''.join(f'<div><small>Variante {i}</small><audio controls preload="none" src="../../assets/audio/{kind}_{i:02}.wav"></audio></div>' for i in range(1,4))
        cards.append(f'<article><h2>{title}</h2><p>{description}</p>{players}</article>')
    document='''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LETZTE SCHICHT · Schritte und Wind</title><style>*{box-sizing:border-box}body{margin:0;background:#111719;color:#e1e5dc;font:16px/1.55 system-ui,sans-serif}main{max-width:1100px;margin:auto;padding:38px 24px}a{color:#c9b27c}p{color:#bac5c4}h2{font-size:1.25rem}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(285px,1fr));gap:18px}article{padding:20px;border:1px solid #354243;background:#182124;border-radius:5px}audio{display:block;width:100%;margin:7px 0 17px}small{color:#c8b798}section{margin:30px 0}</style><main>
<a href="../audio-refresh/index.html">Musik und weitere Geräusche</a><h1>Schritte und Wind</h1><p>15 neue Originalgeräusche und eine 16 Sekunden lange Windschleife. Die Player geben den Dateipegel wieder; Lautstärke und Auslösung im Spiel steuert die Audio-Runtime.</p>
<section><article><h2>Wind</h2><p>Mehrere gefilterte Rauschschichten mit sanften Böen und räumlicher Breite. Ohne Melodie.</p><audio controls loop preload="none" src="../../assets/audio/ambience_wind.ogg"></audio></article></section>
<section class="grid">CARDS</section>
<p>CHECKS technische Prüfungen bestanden. Gemessen wurden Pegel, Gleichspannungsanteil, Loopgrenze und Varianten. Eine Hörbewertung wurde nicht durchgeführt.</p>
<p><a href="audio-measurements.json">Messwerte</a> · <a href="audio-assets-test.log">Prüflog</a> · <a href="../../assets/audio/movement_sources.json">Herkunft und Parameter</a> · <a href="../../tools/generate_movement_audio.py">Generator</a></p>
RUNTIME_REPORT
<script>document.querySelectorAll('audio').forEach(player=>player.addEventListener('play',()=>document.querySelectorAll('audio').forEach(other=>{if(other!==player)other.pause()})));</script></main></html>'''
    runtime_link='<p><a href="audio-runtime-verification.md">Laufzeitprüfung: räumliche Schritte, Pause und Wind</a></p>' if (REPORT/"audio-runtime-verification.md").exists() else ""
    (REPORT/"audio.html").write_text(document.replace("CARDS","".join(cards)).replace("CHECKS",str(result["passed"])).replace("RUNTIME_REPORT",runtime_link))


if __name__=="__main__":
    raise SystemExit(main())
