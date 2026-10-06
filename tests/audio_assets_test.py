#!/usr/bin/env python3
"""Decode the shipping bank and validate levels, loops and distinct variations."""
from pathlib import Path
import hashlib
import html
import itertools
import json
import subprocess
import sys

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio"
REPORT = ROOT / "artifacts/audio-refresh"
REPORT.mkdir(parents=True, exist_ok=True)
METADATA = json.loads((OUT/"sources.json").read_text())
checks = []


def check(condition, description):
    checks.append({"passed": bool(condition), "description": description})
    print(("PASS " if condition else "FAIL ")+description)


def decode(path):
    details = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)]))["streams"][0]
    channels = int(details["channels"])
    raw = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-c:a", "pcm_f32le", "-"])
    return np.frombuffer(raw, dtype="<f4").reshape(-1, channels).astype(np.float64), int(details["sample_rate"])


def metrics(data, rate):
    mono = data.mean(axis=1)
    spectrum = np.abs(np.fft.rfft(mono))**2
    freqs = np.fft.rfftfreq(len(mono), 1/rate)
    peak = float(np.max(np.abs(data)))
    result = {"samples": len(data), "sample_rate": rate, "channels": data.shape[1],
              "seconds": len(data)/rate, "peak": peak,
              "peak_dbfs": float(20*np.log10(max(peak, 1e-12))),
              "rms": float(np.sqrt(np.mean(data**2))),
              "max_channel_dc": float(np.max(np.abs(data.mean(axis=0)))),
              "centroid_hz": float(np.sum(spectrum*freqs)/max(spectrum.sum(),1e-12)),
              "high_band_energy_above_8khz": float(spectrum[freqs>8000].sum()/max(spectrum.sum(),1e-12)),
              "seam_jump": float(np.max(np.abs(data[0]-data[-1]))),
              "step_p99": float(np.quantile(np.abs(np.diff(data,axis=0)), .99))}
    # Four-times oversampling catches reconstruction overs without claiming a certified meter.
    result["oversampled_peak_4x"] = float(np.max(np.abs(resample_poly(data, 4, 1, axis=0))))
    return result


def main():
    bank = {}
    measurements = {}
    # Validate this declared bank; movement_sources.json owns footsteps and wind.
    effects = [OUT/f"{kind}_{index:02}.wav" for kind,count in METADATA["variants"].items() for index in range(1,count+1)]
    score_names = ["music_calm.ogg", "music_combat.ogg"] + [
        f"music_{kind}_{phase}.ogg" for kind in METADATA["music"]["sets"] for phase in ("calm", "combat")]
    music = [OUT/name for name in score_names]
    for path in sorted(effects) + sorted(music):
        data, rate = decode(path)
        item = metrics(data, rate)
        measurements[path.name] = item
        bank[path.name] = data
        check(np.isfinite(data).all() and .0001 < item["rms"] < .35, path.name+": finite, audible signal with bounded RMS")
        check(item["peak"] < .90 and item["oversampled_peak_4x"] < .93, path.name+": decoded and reconstructed peaks leave headroom")
        # The preserved legacy combat recording has 0.00088 DC (-61 dBFS).
        # Keep a stated legacy ceiling while requiring the new bank below -74 dBFS.
        legacy_score = path.name in METADATA["original_score"]["sha256"]
        dc_limit = .001 if legacy_score else .0002
        check(item["max_channel_dc"] < dc_limit, path.name+f": channel DC below {dc_limit:g}")
        if path.suffix == ".wav":
            check(rate == 32000 and data.shape[1] == 1 and .1 < item["seconds"] <= 2,
                  path.name+": mono 32 kHz effect with bounded duration")
            check(np.max(np.abs(data[[0,-1]])) <= 1/32768, path.name+": zero-valued event edges")
        else:
            check(rate == 32000 and data.shape[1] == 2 and len(data) == 48*32000,
                  path.name+": exact 48-second stereo loop at 32 kHz")
            check(item["seam_jump"] < max(.008, item["step_p99"]*2.0),
                  path.name+": loop boundary is below conservative adjacent-sample threshold")
            check(item["high_band_energy_above_8khz"] < .001,
                  path.name+": restrained high-frequency content")
    check(len(effects) == 50 and all(path.exists() for path in effects), "All fifty declared gameplay effect variations ship")
    check(len(music) == 8 and all(path.exists() for path in music), "Four musical worlds each provide two arrangements")
    variation_correlations = {}
    for kind, count in METADATA["variants"].items():
        values = []
        for first, second in itertools.combinations(range(1,count+1),2):
            a,b = bank[f"{kind}_{first:02}.wav"].ravel(), bank[f"{kind}_{second:02}.wav"].ravel()
            values.append(float(np.corrcoef(a,b)[0,1]))
        if values:
            variation_correlations[kind] = values
            check(max(values)<.998, kind+": alternatives differ in waveform, not only volume")
    musical_correlations = {}
    for name in ("foundry", "tidal", "frost"):
        calm, combat = bank[f"music_{name}_calm.ogg"], bank[f"music_{name}_combat.ogg"]
        pair = float(np.corrcoef(calm.ravel()[::16], combat.ravel()[::16])[0,1])
        musical_correlations[name] = pair
        check(.70 < pair < .999, name+": combat retains the shared score and adds distinct activity")
        check(np.sqrt(np.mean(combat**2)) > np.sqrt(np.mean(calm**2)), name+": combat adds energy above calm arrangement")
    for first, second in itertools.combinations(("foundry", "tidal", "frost"),2):
        correlation = float(np.corrcoef(bank[f"music_{first}_calm.ogg"].ravel()[::16],
                                       bank[f"music_{second}_calm.ogg"].ravel()[::16])[0,1])
        check(abs(correlation)<.40, f"{first}/{second}: distinct musical waveforms")
    for name, checksum in METADATA["original_score"]["sha256"].items():
        check(hashlib.sha256((OUT/name).read_bytes()).hexdigest()==checksum, name+": original score is byte-identical")
    # A representative impact is regenerated to verify the declared PCM seed path.
    sys.path.insert(0, str(ROOT/"tools"))
    import generate_audio_expansion as generator
    regenerated = np.round(generator.improved_effect("impact_metal", 1)*32767).astype("<i2")
    check(np.array_equal(regenerated, np.round(bank["impact_metal_02.wav"].ravel()*32768).astype("<i2")),
          "Seeded synthesis reproduces the exact shipped impact PCM")
    summary = {"passed": sum(c["passed"] for c in checks), "failed": sum(not c["passed"] for c in checks),
               "measurements": measurements, "variation_correlations": variation_correlations,
               "arrangement_correlations": musical_correlations, "checks": checks,
               "listening": "No human or agent listening assessment performed. Use the browser audio controls for listening review.",
               "peak_method": "Decoded PCM and scipy resample_poly at 4x; this is not a certified loudness/true-peak meter."}
    (REPORT/"measurements.json").write_text(json.dumps(summary, indent=2)+"\n")
    write_gallery(summary)
    print(f"AUDIO ASSET CHECKS: {summary['passed']} passed, {summary['failed']} failed")
    return 1 if summary["failed"] else 0


def write_gallery(summary):
    runtime_logs = [("audio_world_score_test.log", "Weltwechsel und Klangvarianten"),
                    ("audio_gameplay_effects_test.log", "Klangzuordnung im Spiel"),
                    ("audio_world_score_display.log", "Weltmusik mit grafischer Ausgabe"),
                    ("audio_network_score_test.log", "Musik beim Netzwerkbeitritt"),
                    ("audio_settings_test.log", "Lautstärkeeinstellungen"),
                    ("audio_teardown_test.log", "Freigabe der Wiedergabe"),
                    ("runtime-metrics.json", "Controller-Messwerte")]
    runtime_links = " · ".join(f'<a href="{name}">{label}</a>' for name,label in runtime_logs if (REPORT/name).exists())
    runtime_section = (f'<section><h2>Wiedergabe im Spiel</h2><p>Beim Schichtbeginn bestimmt der gewählte Schauplatz die Musik aus vier vorgeladenen Sets. '
                       'Ein anderes Musikset blendet über 2,4 Sekunden an derselben Phrasenposition ein. '
                       'Zwölf Effektstimmen berücksichtigen Prioritäten; Klangvarianten wiederholen sich nicht unmittelbar.</p>'
                       f'<p>{runtime_links}</p><p><a href="verification.md">Prüfbericht mit Ergebnissen und Messgrenzen</a></p></section>'
                       if runtime_links else "")
    cards = []
    for name, spec in METADATA["music"]["sets"].items():
        tracks = "".join(f'<div><strong>{label}</strong><audio controls loop preload="none" src="../../assets/audio/music_{name}_{phase}.ogg"></audio></div>'
                         for phase,label in [("calm","Ruhe"),("combat","Kampf")])
        cards.append(f'<article><h2>{html.escape(spec["title"])}</h2><p>{html.escape(spec["key"])} · 80 BPM · 48 s</p><p>{html.escape(spec["instruments"])}</p>{tracks}</article>')
    sounds = []
    for kind in ["shot", "shotgun", "cannon", "arc", "impact_metal", "impact_stone", "impact_wood", "glass_break", "reload", "explosion", "warning", "thunder"]:
        sources = "".join(f'<div><small>Variante {i}</small><audio controls preload="none" src="../../assets/audio/{kind}_{i:02}.wav"></audio></div>'
                          for i in range(1, METADATA["variants"][kind]+1))
        sounds.append(f'<article><h3>{kind}</h3>{sources}</article>')
    document = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LETZTE SCHICHT · Musik und Klang</title><style>
*{box-sizing:border-box}body{margin:0;background:#111719;color:#e1e5dc;font:16px/1.55 system-ui,sans-serif}main{max-width:1140px;margin:auto;padding:40px 24px}h1{font-size:2.2rem}h2{font-size:1.25rem}p{color:#bac5c4}a{color:#c9b27c}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:18px}article{padding:20px;border:1px solid #354243;background:#182124;border-radius:5px}audio{width:100%;margin:8px 0 17px}small{color:#c8b798}strong{display:block}header{margin-bottom:32px}section{margin:34px 0}.note{padding:16px;border-left:3px solid #b4a06f;background:#20292b}</style><main>
<header><a href="../graphics-refresh/index.html">Zur Projektvorschau</a><h1>Musik und Klang</h1><p>Drei neue Originalkompositionen, sechs synchronisierte Arrangements und 50 überarbeitete oder neue Geräusche.</p></header>
<p class="note">Die Vorschau spielt einzelne Dateien. Im Spiel werden Ruhe und Kampf synchron überblendet. Bitte nur einen Player gleichzeitig starten. Die technische Prüfung bewertet Pegel, DC, Loopgrenzen und Varianten; eine Hörprüfung wird nicht behauptet.</p>
<section><h2>Neue Musik</h2><div class="grid">MUSIC_CARDS</div></section>
<section><h2>Klangfamilien und Varianten</h2><div class="grid">SOUND_CARDS</div></section>
RUNTIME_SECTION
<p>Das ursprüngliche Musikpaar bleibt unverändert. Alle Klänge sind lokal aus Oszillatoren, Rauschen und Resonanzmodellen erzeugt; keine Fremdsamples.</p>
<p><a href="measurements.json">Messwerte und Prüfergebnisse</a> · <a href="../../assets/audio/sources.json">Herkunft und Kompositionsdaten</a> · <a href="../../tools/generate_audio_expansion.py">Reproduzierbarer Generator</a></p>
</main></html>'''.replace("MUSIC_CARDS", "".join(cards)).replace("SOUND_CARDS", "".join(sounds)).replace("RUNTIME_SECTION", runtime_section)
    (REPORT/"index.html").write_text(document)


if __name__ == "__main__":
    raise SystemExit(main())
