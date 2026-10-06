#!/usr/bin/env python3
"""Original multigrain diesel and contact foley; v1/v2 and user gains stay intact.

The preserved v2 generator supplies the basic physical modes. V3 adds uneven
cylinder loads, broadband contact grains and separate wheel/ground contacts.
Loops use circular envelopes and periodic FFT filtering, never an end fade.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio'
spec = importlib.util.spec_from_file_location('convoy_v2_design', ROOT/'tools/generate_convoy_audio.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
RATE = base.RATE
LICENSE = base.LICENSE
SEED = 601943
SPECS = dict(base.SPECS)
SPECS['jack'] = (.55, False, 'One loaded hydraulic pump stroke with ratchet teeth; 1.8 Hz visual cadence')
SPECS['wrench'] = (.52, False, 'Socket travel, irregular ratchet return and short loaded pull')
SPECS['tire_puncture'] = (2.1, False, 'Sharp rubber tear, escaping air flutter, folded rubber and chassis drop')
SPECS['fit'] = (.65, False, 'Hands shifting a heavy rubber spare; seating contact is separate')
SPECS['lower'] = (.90, False, 'Hydraulic return and loaded jack release; tire ground contact is separate')
SPECS['fit_contact'] = (.42, False, 'Heavy rim seats on the axle, close steel contact without a musical cue')
SPECS['lower_contact'] = (.55, False, 'Rubber compression at ground contact followed by body-panel settling')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _periodic_filter(data, low=27.0, high=6000.0):
    frequency = np.fft.rfftfreq(len(data), 1/RATE)
    highpass = frequency**2/(low**2+frequency**2)
    lowpass = 1/np.sqrt(1+(frequency/high)**8)
    return np.fft.irfft(np.fft.rfft(data)*highpass*lowpass, len(data))


def _circular_envelope(t, at, decay, attack=.0012):
    age = np.mod(t-at, base.LOOP_SECONDS)
    return (1-np.exp(-age/attack))*np.exp(-age/decay)


def _level(data, target_rms, ceiling):
    data = data - data.mean()
    data /= max(float(np.sqrt(np.mean(data**2))), 1e-12)
    # Pressure/contact saturation belongs to this offline physical model.
    # Fit its smooth crest response to the old role's RMS without clipping
    # exceptional grains or changing any runtime bus/effect/slider settings.
    low, high = 0.0, 4.0
    for unused in range(24):
        drive = (low+high)*.5
        shaped = ceiling*np.tanh(data*drive/ceiling)
        if np.sqrt(np.mean(shaped**2)) < target_rms: low = drive
        else: high = drive
    data = _periodic_filter(ceiling*np.tanh(data*(low+high)*.5/ceiling))
    data -= data.mean()
    data *= target_rms/max(float(np.sqrt(np.mean(data**2))), 1e-12)
    data *= min(1.0, ceiling/max(float(np.abs(data).max()), 1e-12))
    return data


def _loop(kind, rng):
    count = round(base.LOOP_SECONDS*RATE)
    t = np.arange(count)/RATE
    angle = base.TAU*t/base.LOOP_SECONDS
    original = base.render(kind)
    low = base.periodic_noise(count, rng, 30, 440)
    mid = base.periodic_noise(count, rng, 220, 1800)
    grit = base.periodic_noise(count, rng, 1050, 5500)
    if kind in ('idle', 'torque'):
        cycles = 234 if kind == 'idle' else 336  # Six cylinders, whole loop.
        combustion = cycles*t/base.LOOP_SECONDS+.045*np.sin(angle*13)
        fraction = np.mod(combustion, 1)
        cylinder = np.floor(combustion).astype(int) % 6
        loads = np.array([1.08, .91, 1.02, .87, 1.12, .98])[cylinder]
        impulse = np.sin(np.pi*fraction)**.75*np.exp(-fraction/.18)*loads
        pressure = (low*.42+mid*.18)*impulse
        exhaust = np.sin(angle*cycles)*.15 + np.sin(angle*cycles*2-.6)*.047
        cooling = mid*(.007 if kind == 'idle' else .017)
        texture = pressure+exhaust+cooling+grit*impulse*.017
        if kind == 'torque': texture += mid*(.012+.008*np.sin(angle*7))
        data = original*.45 + texture*.80
    elif kind == 'road':
        data = original*.55 + mid*.028 + grit*(.012+.006*np.sin(angle*29))
        for unused in range(38):
            at, decay = rng.uniform(0, 8), rng.uniform(.015, .05)
            envelope = _circular_envelope(t, at, decay)
            data += (low*.19+mid*.08)*envelope*rng.uniform(.5, 1)
    else:
        data = original*.45 + mid*.004
        for unused in range(29):
            at, decay = rng.uniform(0, 8), rng.uniform(.009, .038)
            envelope = _circular_envelope(t, at, decay, .0008)
            # Broadband contact grains avoid a repeated resonant bell.
            data += (low*.24+mid*.15+grit*.018)*envelope*rng.uniform(.35, 1)
    return _level(_periodic_filter(data), float(np.sqrt(np.mean(original**2))), .64)


def _effect(kind, rng):
    seconds = SPECS[kind][0]
    t = np.arange(round(seconds*RATE))/RATE
    low = base.periodic_noise(len(t), rng, 35, 440)
    mid = base.periodic_noise(len(t), rng, 180, 2100)
    grit = base.periodic_noise(len(t), rng, 850, 5700)
    data = np.zeros_like(t)

    def contact(at, power=.25, decay=.05):
        return (low*.58+mid*.27+grit*.018)*base.burst(t, at, decay, .0007)*power

    def tooth(at, power=.065):
        return base.modes(t, at, (417, 937, 1871), power, .007, rng) + mid*base.burst(t, at, .006, .0005)*power*.22

    if kind == 'tire_puncture':
        data += contact(.003, 1.1, .052)+grit*base.burst(t, .006, .012, .0004)*.16
        pressure = base.burst(t, .014, .48, .011)
        flutter = .69+.21*np.sin(base.TAU*(23*t+17*t*t))+.1*np.sin(base.TAU*71*t)
        data += (mid*.21+grit*.22)*pressure*flutter
        for at, power in [(.19,.12),(.29,.27),(.42,.08)]: data += contact(at, power, .065)
        data += low*base.burst(t, .32, .14, .014)*.09
    elif kind == 'jack':
        data += contact(.016, .3, .055)
        data += mid*base.burst(t, .025, .14, .035)*.055
        for index in range(5): data += tooth(.035+index*.039+rng.uniform(-.002,.002))
        data += contact(.27, .24, .043)
    elif kind == 'wrench':
        data += tooth(.012, .12)
        for index in range(7): data += tooth(.062+index*.029+rng.uniform(-.003,.003), rng.uniform(.04,.075))
        data += contact(.30, .42, .042)+low*base.burst(t,.31,.047,.012)*.035
    elif kind in ('fit', 'lower'):
        data += (mid*.11+grit*.025)*base.burst(t,.012,.17,.038)
        data += low*base.burst(t,.07,.13,.037)*.09
        data += tooth(.036,.025)
    elif kind in ('fit_contact', 'lower_contact'):
        data += contact(.007,.76,.065)
        data += base.modes(t,.011,(71,159,337),.14,.04,rng)
        if kind == 'fit_contact': data += tooth(.065,.09)
        else:
            data += low*base.burst(t,.03,.10,.016)*.13
            data += contact(.11,.19,.029)
    else:
        original = base.render(kind)
        data += original*.78
        if kind in ('door_open','door_close','bolt_success','tool_miss','gear','repair_done'):
            data += contact(.009,.35 if kind=='door_close' else .11,.055 if kind=='door_close' else .02)
            if kind=='door_close': data += tooth(.086,.045)
        elif kind in ('start','stop','accelerate'):
            data += (low*.035+mid*.012)*base.burst(t,.018,.27,.02)
        elif kind == 'brake': data += grit*base.burst(t,.028,.15,.018)*.034
    data = _periodic_filter(data)
    fade = np.sin(np.clip(t/.001,0,1)*np.pi/2)**2
    fade *= np.sin(np.clip((seconds-1/RATE-t)/.055,0,1)*np.pi/2)**2
    data *= fade
    window = np.sin(np.pi*np.arange(len(t))/(len(t)-1))**2
    data -= window*data.sum()/window.sum()
    # Preserve the old role's perceived source level; contact roles are short
    # and sit below the rupture. Bus/slider gains are never normalized to100%.
    target = float(np.sqrt(np.mean(base.render(kind)**2))) if kind in base.SPECS else .11
    data *= target/max(float(np.sqrt(np.mean(data**2))),1e-12)
    data *= min(1.0,.68/max(float(np.abs(data).max()),1e-12))
    data[[0,-1]] = 0
    return data


def render(kind):
    rng = np.random.default_rng(SEED+list(SPECS).index(kind)*997)
    return _loop(kind,rng) if SPECS[kind][1] else _effect(kind,rng)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    protected = {p.name:digest(p) for p in OUT.iterdir() if p.is_file() and not p.name.endswith(('_v3.wav','_v3.source.json','_v3.LICENSE.txt')) and p.name!='convoy_v3_sources.json'}
    source_hash = digest(Path(__file__))
    assets = {}
    for kind,(seconds,looping,layers) in SPECS.items():
        pcm = np.round(render(kind)*32767).astype('<i2')
        path = OUT/f'convoy_{kind}_v3.wav'
        with wave.open(str(path),'wb') as stream:
            stream.setparams((1,2,RATE,len(pcm),'NONE','not compressed'))
            stream.writeframes(pcm.tobytes())
        metadata = {'asset':str(path.relative_to(ROOT)),'generator':'tools/generate_convoy_audio_v3.py','generator_sha256':source_hash,'base_generator':'tools/generate_convoy_audio.py','base_generator_sha256':digest(ROOT/'tools/generate_convoy_audio.py'),'source':'Original deterministic physical multigrain foley; no external samples or music.','license':LICENSE,'role':kind,'layers':layers,'seed':SEED+list(SPECS).index(kind)*997,'sample_rate':RATE,'channels':1,'pcm_bits':16,'frames':len(pcm),'seconds':seconds,'loop':looping,'sha256':digest(path),'loop_method':'Periodic FFT and circular mechanical envelopes' if looping else 'Silent edges and55ms final fade','playback':'Existing positional SFX voices and user50% baseline gains; separate fit/lower impact at actual work contact.'}
        path.with_suffix('.source.json').write_text(json.dumps(metadata,indent=2)+'\n')
        path.with_suffix('.LICENSE.txt').write_text(LICENSE+'\n'+metadata['source']+'\n')
        assets[path.name] = metadata
    assert all(digest(OUT/name)==value for name,value in protected.items()),'Existing sound or provenance changed'
    manifest = {'generator':'tools/generate_convoy_audio_v3.py','generator_sha256':source_hash,'license':LICENSE,'assets':assets,'preserved_assets_sha256':protected,'validation':'python3 tests/convoy_audio_v3_assets_test.py; Godot tests/convoy_audio_test.gd and convoy_audio_contact_test.gd','review':'Technical signal verification and actual Godot audition; no human listening acceptance claim.'}
    (OUT/'convoy_v3_sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Rendered{len(assets)} original v3 convoy sounds; earlier audio and gain defaults preserved.')


if __name__ == '__main__':
    main()
