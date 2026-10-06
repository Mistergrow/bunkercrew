#!/usr/bin/env python3
"""Reproducible PCM, source levels, loop wraps and isolated contact recordings."""
from pathlib import Path
import hashlib
import importlib.util
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
REPORT = ROOT / 'artifacts/convoy-quality-v3-20261005/audio'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


generator = module('convoy_v3_design', ROOT / 'tools/generate_convoy_audio_v3.py')
analysis = module('convoy_pcm_analysis', ROOT / 'tests/convoy_audio_assets_test.py')
checks = []


def check(ok, label):
    checks.append({'passed': bool(ok), 'label': label})
    print(('PASS ' if ok else 'FAIL ') + label)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pcm(path):
    with wave.open(str(path), 'rb') as stream:
        rate, channels, size = stream.getframerate(), stream.getnchannels(), stream.getsampwidth()
        raw = np.frombuffer(stream.readframes(stream.getnframes()), dtype='<i2').copy()
    return raw, rate, channels, size


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((OUT / 'convoy_v3_sources.json').read_text())
    source_hash = digest(ROOT / manifest['generator'])
    check(source_hash == manifest['generator_sha256'], 'Bank matches the current v3 generator')
    check(len(manifest['assets']) == 23, 'Four loops and nineteen foley roles including two physical contacts')
    bank, measurements = {}, {}
    for kind, (seconds, looping, unused_layers) in generator.SPECS.items():
        name = f'convoy_{kind}_v3.wav'
        path = OUT / name
        raw, rate, channels, size = pcm(path)
        data = raw.astype(np.float64) / 32768
        bank[kind] = data
        metrics = analysis.measure(data, rate)
        measurements[name] = metrics
        adjacent = json.loads(path.with_suffix('.source.json').read_text())
        check(adjacent == manifest['assets'][name] and adjacent['sha256'] == digest(path), name + ': exact adjacent provenance')
        check(adjacent['generator_sha256'] == source_hash and adjacent['base_generator_sha256'] == digest(ROOT / adjacent['base_generator']), name + ': both generators recorded')
        check(path.with_suffix('.LICENSE.txt').read_text().startswith(generator.LICENSE), name + ': original Bunkercrew-only distribution license')
        check(rate == 48000 and channels == 1 and size == 2 and len(raw) == round(seconds * rate), name + ': exact 48 kHz mono PCM16 length')
        check(np.array_equal(raw, np.round(generator.render(kind) * 32767).astype('<i2')), name + ': deterministic shipped PCM')
        check(np.isfinite(data).all() and .01 < metrics['rms'] < .4 and metrics['peak'] <= .681, name + ': source headroom and audible finite signal')
        check(metrics['reconstructed_peak_4x'] < .76 and abs(metrics['dc']) < .00002, name + ': reconstructed peak and DC bounded')
        check(metrics['above_8khz_fraction'] < .005, name + ': restrained high-frequency noise')
        if looping:
            check(metrics['seam_jump'] < max(.004, metrics['sample_step_p99'] * 1.5), name + ': ordinary seam step without a gap')
            energy = np.sqrt(np.mean(data.reshape(8, rate) ** 2, axis=1))
            check(energy.min() > .4 * energy.max(), name + ': no silent loop fade')
            if kind in ('road', 'clatter'):
                check(metrics['largest_bin_fraction'] < .09, name + ': broadband road/metal texture')
        else:
            check(np.abs(raw[[0, -1]]).max() <= 1, name + ': silent one-shot edges')
        if kind in generator.base.SPECS:
            before = pcm(OUT / f'convoy_{kind}_v2.wav')[0].astype(np.float64) / 32768
            ratio = metrics['rms'] / np.sqrt(np.mean(before ** 2))
            metrics['v2_rms_ratio'] = float(ratio)
            # A source with a higher crest factor can require less global
            # gain to retain transient headroom, but never raises old RMS.
            check(.2 < ratio < 1.015, name + ': existing audible role level is not increased')
    missing_or_changed = [name for name, sha in manifest['preserved_assets_sha256'].items()
                          if not (OUT / name).is_file() or digest(OUT / name) != sha]
    check(not missing_or_changed, f'{len(manifest["preserved_assets_sha256"])} prior audio/provenance files preserved')
    correlations = {}
    for first, second in [('fit', 'fit_contact'), ('lower', 'lower_contact'), ('jack', 'wrench'),
                          ('tire_puncture', 'brake'), ('road', 'clatter')]:
        count = min(len(bank[first]), len(bank[second]))
        value = float(np.corrcoef(bank[first][:count], bank[second][:count])[0, 1])
        correlations[first + '/' + second] = value
        check(abs(value) < .9, first + '/' + second + ': physically distinct recordings')
    result = {'passed': sum(c['passed'] for c in checks), 'failed': sum(not c['passed'] for c in checks),
              'checks': checks, 'measurements': measurements, 'correlations': correlations,
              'changed_earlier_assets': missing_or_changed,
              'peak_method': '4x scipy resample_poly estimate, not certified true peak.',
              'review': 'Signal and source-level checks. Human listening assessment is still separate.'}
    (REPORT / 'audio-measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'CONVOY V3 AUDIO ASSETS: {result["passed"]} passed, {result["failed"]} failed')
    return 1 if result['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
