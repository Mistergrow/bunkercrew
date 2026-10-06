#!/usr/bin/env python3
"""Original contact foley and periodic wind, generated offline without recordings."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, sosfilt

OUT = Path(__file__).resolve().parents[1]/"assets/audio"
RATE = 32000
WIND_SECONDS = 16
SPECS = {
    "step_dry": {"seconds": .26, "peak": .40, "seed": 374119,
                 "layers": "soft heel, loose gravel grains, short dusty sole scrape"},
    "step_metal": {"seconds": .25, "peak": .42, "seed": 718103,
                   "layers": "rubber heel, damped steel panel resonances, short toe contact"},
    "step_water": {"seconds": .36, "peak": .36, "seed": 890341,
                   "layers": "shallow splash, displaced water hiss, small decaying bubble modes"},
    "step_ice": {"seconds": .30, "peak": .38, "seed": 453127,
                 "layers": "packed snow compression, irregular ice grains, soft sole contact"},
    "step_heavy": {"seconds": .39, "peak": .56, "seed": 630911,
                   "layers": "damped mechanical foot weight, low panel flex, restrained gritty contact"},
}


def band_noise(count, rng, low, high):
    spectrum = np.fft.rfft(rng.normal(size=count))
    frequency = np.fft.rfftfreq(count, 1/RATE)
    response = 1/np.sqrt(1+(frequency/high)**8)
    response *= (frequency/low)**2/(1+(frequency/low)**2)
    result = np.fft.irfft(spectrum*response, count)
    return result/max(float(np.std(result)), 1e-9)


def burst(t, at, decay, attack=.003):
    age = np.maximum(t-at, 0)
    return (1-np.exp(-age/attack))*np.exp(-age/decay)*(t>=at)


def contact(kind, variant):
    spec = SPECS[kind]
    rng = np.random.default_rng(spec["seed"] + variant*499)
    t = np.arange(round(spec["seconds"]*RATE))/RATE
    # Independent textures and mode offsets make variants differ beyond gain/pitch.
    low = band_noise(len(t), rng, 45, 420)
    middle = band_noise(len(t), rng, 280, 2200)
    grit = band_noise(len(t), rng, 1100, 5200)
    toe_at = .046+rng.uniform(-.007, .012)
    signal = low*burst(t, 0, .019)*.30

    def modes(at, frequencies, gain, decay):
        age = np.maximum(t-at, 0)
        pressure = np.zeros(len(t))
        for i, frequency in enumerate(frequencies):
            detune = rng.uniform(.955, 1.045)
            pressure += np.sin(2*np.pi*frequency*detune*age)/(i+1)**1.6
        return pressure*burst(t,at,decay,.0008)*gain

    def grains(count, start, end, strength, bright=True):
        output = np.zeros(len(t))
        for _ in range(count):
            at = rng.uniform(start,end)
            decay = rng.uniform(.0016,.0065)
            texture = np.roll(grit if bright else middle, int(rng.integers(1,len(t))))
            output += texture*burst(t,at,decay,.0004)*strength*rng.uniform(.45,1)
        return output

    if kind == "step_dry":
        signal += middle*burst(t,.006,.024)*.16
        signal += grit*burst(t,.028,.037,.013)*.072
        signal += grains(17,.014,.15,.11)
        signal += low*burst(t,toe_at,.032,.006)*.14
    elif kind == "step_metal":
        signal += modes(0,[117,243,431,763],.34,.035)
        signal += modes(toe_at,[161,319,581],.10,.023)
        signal += middle*burst(t,0,.009,.0007)*.16
        signal += grit*burst(t,toe_at,.007)*.035
    elif kind == "step_water":
        signal += middle*burst(t,.008,.043,.006)*.28
        signal += grit*burst(t,.023,.052,.018)*.16
        signal += low*burst(t,toe_at,.047,.009)*.19
        signal += grains(11,.043,.195,.055)
        for at in rng.uniform(.018,.145,5):
            age = np.maximum(t-at,0)
            frequency = rng.uniform(470,910)
            phase = 2*np.pi*(frequency*age-frequency*1.1*age**2)
            signal += np.sin(phase)*burst(t,at,.007,.001)*rng.uniform(.012,.032)
    elif kind == "step_ice":
        signal += middle*burst(t,.006,.043,.009)*.24
        signal += grit*burst(t,.028,.048,.018)*.13
        signal += grains(24,.007,.18,.092)
        signal += modes(toe_at,[213,371],.050,.017)
    elif kind == "step_heavy":
        signal += modes(0,[57,98,161],.71,.067)
        signal += low*burst(t,0,.043,.002)*.29
        signal += modes(toe_at+.012,[81,176,319],.17,.033)
        signal += middle*burst(t,.002,.014,.001)*.12
        signal += grains(7,.037,.16,.022,False)
    # Restrained upper frequencies and zero endpoints for freely scheduled contacts.
    signal = sosfilt(butter(2,[38,6400],"bandpass",fs=RATE,output="sos"),signal)
    fade_in = np.sin(np.minimum(t/.0015,1)*np.pi/2)**2
    fade_out = np.sin(np.clip((spec["seconds"]-1/RATE-t)/.035,0,1)*np.pi/2)**2
    signal *= fade_in*fade_out
    window = np.sin(np.pi*np.arange(len(t))/(len(t)-1))**2
    signal -= window*signal.sum()/window.sum()
    return signal*spec["peak"]/max(float(np.max(np.abs(signal))),1e-9)


def wind():
    rng = np.random.default_rng(1467301)
    count = WIND_SECONDS*RATE
    t = np.arange(count)/RATE
    phase = 2*np.pi*t/WIND_SECONDS
    # All envelopes use integral cycles over sixteen seconds; noise is periodic FFT data.
    gust = .50 + .20*np.sin(phase-.7) + .13*np.sin(phase*3+.4) + .07*np.sin(phase*5)
    eddy = .65 + .20*np.sin(phase*2+1.1) + .10*np.sin(phase*7-.3)
    low = band_noise(count,rng,43,300)
    middle = band_noise(count,rng,210,1150)
    high = band_noise(count,rng,780,2900)
    side_left = band_noise(count,rng,320,1900)
    side_right = band_noise(count,rng,320,1900)
    common = low*gust*.33 + middle*eddy*gust*.14 + high*gust**2*.023
    left = common + side_left*gust*.058
    right = np.roll(common,19) + side_right*gust*.058
    result = np.stack([left,right],axis=1)
    result -= result.mean(axis=0)
    return result*(.43/np.max(np.abs(result)))


def save_wav(path,data):
    with wave.open(str(path),"wb") as file:
        file.setnchannels(1 if data.ndim==1 else data.shape[1])
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(np.round(data*32767).astype("<i2").tobytes())


def protected_bank():
    protected = sorted(p for p in OUT.iterdir() if (p.suffix in (".wav",".ogg") or p.name=="sources.json")
                       and not p.name.startswith(("step_", "reload_rifle_", "reload_shotgun_", "reload_arc_",
                           "reload_cannon_", "reload_flak_", "weapon_mount_", "weapon_switch_"))
                       and p.name!="ambience_wind.ogg")
    return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}


def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    before = protected_bank()
    for kind in SPECS:
        for variant in range(3):
            save_wav(OUT/f"{kind}_{variant+1:02}.wav",contact(kind,variant))
        print(f"Rendered {kind}: three original variations",flush=True)
    with tempfile.TemporaryDirectory(prefix="lastshift-wind-") as temporary:
        source = Path(temporary)/"wind.wav"
        save_wav(source,wind())
        subprocess.run(["ffmpeg","-v","error","-y","-i",str(source),"-c:a","libvorbis","-q:a","6",
                        str(OUT/"ambience_wind.ogg")],check=True)
    assert before==protected_bank(),"Existing audio bank changed"
    source = {
        "origin":"Original procedural contact foley and filtered-noise wind. No samples, recordings, or melodies.",
        "generator":"tools/generate_movement_audio.py", "dependencies":["numpy","scipy","ffmpeg/libvorbis"],
        "sample_rate":RATE,"variants":{kind:3 for kind in SPECS},"contacts":SPECS,
        "wind":{"file":"ambience_wind.ogg","seconds":WIND_SECONDS,"channels":2,"seed":1467301,
                "pcm_peak":.43,"design":"Five filtered-noise layers, periodic 1/2/3/5/7-cycle gust envelopes and restrained stereo width.",
                "loop":"Full-period FFT noise and periodic modulation; no fade-out, seam crossfade, or silent gap."},
        "preserved_files":len(before),
        "preserved_bank_sha256":hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest(),
        "generation":"Deterministic PCM; Vorbis container serials may change between encodes.",
        "validation":{"command":"python3 tests/movement_audio_assets_test.py","report":"artifacts/movement-effects/audio-measurements.json"},
        "review":"Signal measurements and browser listening gallery; no listening assessment claimed."
    }
    (OUT/"movement_sources.json").write_text(json.dumps(source,indent=2)+"\n")
    print("Rendered 15 contact effects and one 16-second wind loop; existing audio assets and sources unchanged.")


if __name__=="__main__":
    generate()
