#!/usr/bin/env python3
"""Check deterministic convoy PCM, provenance, reconstructed peaks and loop seams."""
from pathlib import Path
import hashlib
import importlib.util
import json
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
REPORT = ROOT / 'artifacts/convoy-drive/audio'
spec = importlib.util.spec_from_file_location('convoy_generator', ROOT / 'tools/generate_convoy_audio.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
checks = []


def check(ok, label):
    checks.append({'passed': bool(ok), 'label': label})
    print(('PASS ' if ok else 'FAIL ') + label)


def measure(data, rate):
    energy = np.abs(np.fft.rfft(data)) ** 2
    frequency = np.fft.rfftfreq(len(data), 1 / rate)
    return {'frames': len(data), 'sample_rate': rate, 'seconds': len(data) / rate,
            'peak': float(np.abs(data).max()), 'rms': float(np.sqrt(np.mean(data ** 2))),
            'dc': float(data.mean()), 'reconstructed_peak_4x': float(np.abs(resample_poly(data, 4, 1)).max()),
            'seam_jump': float(abs(data[0] - data[-1])),
            'largest_sample_step': float(np.abs(np.diff(data)).max()),
            'sample_step_p99': float(np.quantile(np.abs(np.diff(data)), .99)),
            'above_8khz_fraction': float(energy[frequency > 8000].sum() / energy.sum()),
            'largest_bin_fraction': float(energy.max() / energy.sum()),
            'centroid_hz': float((energy * frequency).sum() / energy.sum())}


def gallery(result):
    cards = []
    for kind, (_, looping, layers) in generator.SPECS.items():
        filename = f'convoy_{kind}_v2.wav'
        cards.append(f'<article><h2>{kind.replace("_", " ")}</h2><p>{layers}</p><audio controls {"loop" if looping else ""} preload="none" src="../../../assets/audio/{filename}"></audio><small>{"Loop · 8 Sekunden" if looping else "Einmaliges Ereignis"}</small></article>')
    page = '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bunkercrew · Konvoi-Audio</title><style>body{background:#111719;color:#e1e5dc;font:16px/1.5 system-ui;margin:0}main{max-width:1080px;margin:auto;padding:32px 22px}p{color:#b8c2bc}a{color:#dcc078}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:18px}article{padding:18px;border:1px solid #354243;background:#192124}h2{font-size:1.2rem}audio{width:100%}small{color:#bdad86}</style><main><h1>Konvoi · Motor, Straße und Reparatur</h1><p>21 eigene, deterministisch erzeugte Geräusche. Vier Fahrzeugschichten reagieren unabhängig auf Fahrt und Motorlast; 17 kurze Aufnahmen begleiten Türen, Bremsen und den Reifenwechsel. Diese Einzelplayer geben den Dateipegel wieder. Die Runtime mischt deutlich leiser über die vorhandenen SFX-Einstellungen.</p><p><a href="runtime-demo.wav">Echte Godot-Mischeraufnahme: Einstieg, Fahrt, Panne und Reparatur</a> · <a href="verification.json">Laufzeitprüfung</a> · <a href="audio-measurements.json">Signalmessungen</a> · <a href="../../../assets/audio/convoy_v2_sources.json">Herkunft</a></p><div class="grid">CARDS</div><p>CHECKS technische Prüfungen bestanden. Die Messungen prüfen Signalqualität und Schleifen; sie ersetzen keine menschliche Hörbewertung.</p><script>document.querySelectorAll('audio').forEach(p=>p.addEventListener('play',()=>document.querySelectorAll('audio').forEach(o=>{if(o!==p)o.pause()})));</script></main></html>'''
    (REPORT / 'index.html').write_text(page.replace('CARDS', ''.join(cards)).replace('CHECKS', str(result['passed'])))


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((OUT / 'convoy_v2_sources.json').read_text())
    source_hash = generator.digest(ROOT / manifest['generator'])
    check(source_hash == manifest['generator_sha256'], 'Manifest matches the current deterministic generator')
    check(len(manifest['assets']) == 21, 'Exactly four loop layers and seventeen separate foley roles declared')
    measurements = {}
    bank = {}
    for kind, (seconds, looping, _) in generator.SPECS.items():
        name = f'convoy_{kind}_v2.wav'
        path = OUT / name
        with wave.open(str(path), 'rb') as stream:
            rate, channels, bits = stream.getframerate(), stream.getnchannels(), stream.getsampwidth()
            raw = np.frombuffer(stream.readframes(stream.getnframes()), dtype='<i2').copy()
        data = raw.astype(np.float64) / 32768
        bank[kind] = data
        metrics = measure(data, rate)
        measurements[name] = metrics
        adjacent = json.loads(path.with_suffix('.source.json').read_text())
        check(adjacent == manifest['assets'][name] and adjacent['sha256'] == generator.digest(path), name + ': adjacent provenance and exact file digest match the bank manifest')
        check(adjacent['generator_sha256'] == source_hash and path.with_suffix('.LICENSE.txt').read_text().startswith(generator.LICENSE), name + ': current generator and original-asset license declared')
        check(rate == 48000 and channels == 1 and bits == 2 and len(raw) == round(seconds * rate), name + ': exact 48 kHz mono PCM16 duration')
        check(np.array_equal(raw, np.round(generator.render(kind) * 32767).astype('<i2')), name + ': reproducible synthesis matches shipped PCM sample for sample')
        check(np.isfinite(data).all() and .01 < metrics['rms'] < .40 and metrics['peak'] <= .681, name + ': finite audible signal with source headroom')
        check(metrics['reconstructed_peak_4x'] < .76 and abs(metrics['dc']) < .00002, name + ': bounded reconstructed peak and negligible DC')
        check(metrics['above_8khz_fraction'] < .005, name + ': restrained very high frequency energy')
        if looping:
            check(metrics['seam_jump'] < max(.004, metrics['sample_step_p99'] * 1.5), name + ': loop wrap fits ordinary signal-step bound without a gap')
            rms = np.sqrt(np.mean(data.reshape(8, rate) ** 2, axis=1))
            check(rms.min() > .40 * rms.max(), name + ': no silent boundary or second-long loop fade')
            if kind in ('road', 'clatter'):
                check(metrics['largest_bin_fraction'] < .09, name + ': granular mechanical texture without a dominant pitched tone')
        else:
            check(np.abs(raw[[0, -1]]).max() <= 1, name + ': silent one-shot edges')
    for name, value in manifest['legacy_preserved_sha256'].items():
        check(generator.digest(OUT / name) == value, name + ': original v1 convoy asset preserved byte for byte')
    # Start and stop, input and completion must be physically different events.
    correlations = {}
    for first, second in [('door_open', 'door_close'), ('jack', 'lower'), ('wrench', 'bolt_success'), ('tool_miss', 'bolt_success'), ('start', 'stop'), ('road', 'clatter')]:
        count = min(len(bank[first]), len(bank[second]))
        correlation = float(np.corrcoef(bank[first][:count], bank[second][:count])[0, 1])
        correlations[first + '/' + second] = correlation
        check(abs(correlation) < .9, first + '/' + second + ': distinct physical action waveforms')
    result = {'passed': sum(c['passed'] for c in checks), 'failed': sum(not c['passed'] for c in checks),
              'checks': checks, 'measurements': measurements, 'action_correlations': correlations,
              'peak_method': 'Four-times scipy resample_poly; technical estimate, not certified true peak.',
              'review': 'Original physically inspired mechanical synthesis; signal verification only, no human listening assessment claimed.'}
    (REPORT / 'audio-measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    gallery(result)
    print(f"CONVOY AUDIO ASSETS: {result['passed']} passed, {result['failed']} failed")
    return 1 if result['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
