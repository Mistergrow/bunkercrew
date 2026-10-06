#!/usr/bin/env python3
"""Deterministic reload edits from archived CC0 mechanical recordings."""
from pathlib import Path
import hashlib
import json
import wave
from functools import lru_cache

import numpy as np
from scipy.signal import butter, sosfilt, resample_poly
from scipy.io import wavfile

OUT = Path(__file__).resolve().parents[1] / "assets/audio"
RATE = 32000
RECORDINGS = OUT / "source_recordings/weapon_reload"
PROFILES = {
    "rifle": {"seed": 410711, "modes": [337, 721, 1219, 2101], "weight": .46,
              "description": "Magazine catch, sliding magazine and spring-loaded rifle bolt."},
    "shotgun": {"seed": 518903, "modes": [183, 389, 853, 1409], "weight": .65,
                "description": "Hollow receiver, brass cartridge contacts and a short pump closure."},
    "arc": {"seed": 635227, "modes": [243, 557, 997, 1777], "weight": .38,
            "description": "Recorded cell latch, magazine contacts and a dry slide closure; no electrical tone."},
    "cannon": {"seed": 741719, "modes": [119, 263, 491, 1031], "weight": .90,
               "description": "Heavy feed cover, linked ammunition ratchets and a damped bolt lock."},
    "flak": {"seed": 882491, "modes": [83, 173, 367, 691], "weight": 1.15,
             "description": "Large breech latch, staggered shell-clip contacts and a heavy spring lock."},
}
SPECS = {}
for family, profile in PROFILES.items():
    for phase, seconds in [("open", .25), ("load", .32), ("close", .29)]:
        SPECS[f"reload_{family}_{phase}"] = {"family": family, "phase": phase, "seconds": seconds,
            "seed": profile["seed"] + {"open": 0, "load": 1009, "close": 2027}[phase], "peak": .68}
SPECS["weapon_mount"] = {"family": "cannon", "phase": "mount", "seconds": .29, "seed": 994951, "peak": .57}
SPECS["weapon_switch"] = {"family": "rifle", "phase": "switch", "seconds": .27, "seed": 1093711, "peak": .55}


def envelope(t, at, decay, attack=.001):
    age = np.maximum(0, t-at)
    return (1-np.exp(-age/attack))*np.exp(-age/decay)*(t >= at)


def legacy_handling(kind, variant):
    spec = SPECS[kind]
    profile = PROFILES[spec["family"]]
    rng = np.random.default_rng(spec["seed"] + variant*373)
    t = np.arange(round(RATE*spec["seconds"]))/RATE
    count = len(t)

    def noise(low, high):
        raw = sosfilt(butter(2, [low, high], btype="bandpass", fs=RATE, output="sos"), rng.normal(size=count))
        return raw/max(np.std(raw), 1e-9)

    low, body, bright, friction = noise(55, 340), noise(210, 2100), noise(1050, 6200), noise(480, 3100)
    signal = np.zeros(count)
    weight = profile["weight"]

    def contact(at, strength, decay=.025, metallic=.32):
        nonlocal signal
        at += rng.uniform(0, .003)
        age = np.maximum(t-at, 0)
        modes = sum(np.sin(2*np.pi*f*rng.uniform(.965, 1.035)*age + .13*i)/(1+i)**1.4
                    for i, f in enumerate(profile["modes"]))
        signal += strength * (body*envelope(t, at, decay*.27)*.28
            + bright*envelope(t, at, .004, .0005)*.095
            + low*envelope(t, at, decay*1.12)*weight*.24
            + modes*envelope(t, at, decay, .0006)*metallic)

    def scrape(start, length, strength):
        nonlocal signal
        phase = np.clip((t-start)/length, 0, 1)
        shape = np.sin(np.pi*phase)**1.2
        grain = .65 + .20*np.sin(2*np.pi*(43+rng.uniform(-7,7))*t) + .15*np.sin(2*np.pi*91*t)
        signal += friction*shape*grain*strength

    phase = spec["phase"]
    if phase == "open":
        contact(.006, .85, .022)
        scrape(.022, .105, .16)
        contact(.093+rng.uniform(-.009,.009), .53, .017)
        contact(.153, .22, .025)
    elif phase == "load":
        scrape(.005, .15, .12)
        for i in range(4 if spec["family"] in ("cannon","flak") else 2):
            contact(.032+i*.032+rng.uniform(-.005,.005), .27+rng.uniform(0,.19), .014, .40)
        contact(.188, 1.0, .033, .25)
        contact(.214, .20, .016)
    elif phase == "close":
        scrape(.004, .102, .19)
        for i in range(4):
            contact(.018+i*.021, .18+i*.07, .013, .25)
        contact(.117+rng.uniform(-.008,.008), 1.0, .041, .29)
        contact(.148, .22, .018)
    elif phase == "mount":
        scrape(.001, .145, .22)
        contact(.054, .55, .025, .16)
        contact(.144, .80, .043, .18)
    else:
        scrape(.003, .129, .24)
        contact(.076, .47, .020, .15)
        contact(.145, .65, .024, .23)

    if spec["family"] == "shotgun":
        contact(.055 if phase == "open" else .151, .31, .025, .46)
    elif spec["family"] == "flak":
        scrape(.045, .11, .085)
        contact(.203, .33, .029, .37)
    elif spec["family"] == "arc":
        # Irregular current noise behind the mechanical cell; no UI tone or melody.
        buzz = np.sin(2*np.pi*173*t) + .25*np.sin(2*np.pi*347*t)
        signal += (.65*friction+.35*buzz)*envelope(t,.026,.058,.012)*(.095 if phase == "load" else .042)

    signal = sosfilt(butter(2, [48, 6100], btype="bandpass", fs=RATE, output="sos"), signal)
    # Small body reflections are embedded; room acoustics remain a runtime effect.
    for delay, gain in [(int(.0097*RATE), .08), (int(.0193*RATE), -.04)]:
        signal[delay:] += signal[:-delay].copy()*gain
    fade = np.sin(np.minimum(t/.0015, 1)*np.pi/2)**2
    fade *= np.sin(np.clip((t[-1]-t)/.039, 0, 1)*np.pi/2)**2
    signal *= fade
    dc_window = np.sin(np.pi*np.arange(count)/(count-1))**2
    signal -= dc_window*signal.sum()/dc_window.sum()
    return signal*spec["peak"]/max(np.abs(signal).max(), 1e-9)


@lru_cache(maxsize=6)
def recording(name):
    rate, raw = wavfile.read(RECORDINGS/name)
    signal = raw.astype(np.float64)/np.iinfo(raw.dtype).max
    if signal.ndim > 1:
        signal = signal[:, np.argmax(np.mean(signal**2, axis=0))]
    signal = resample_poly(signal, RATE, rate)
    return sosfilt(butter(2,[95,7200],btype="bandpass",fs=RATE,output="sos"),signal)


# Seconds in the untouched, attributed source recordings. Actual catches,
# magazine contacts and spring closures replace all synthesized reload tones.
CUTS = {
    "rifle_catch": ("assaultriflereload1.wav", .16, .39),
    "rifle_seat": ("assaultriflereload1.wav", 1.005, 1.17),
    "rifle_bolt": ("assaultriflereload1.wav", 1.175, 1.44),
    "pistol_catch": ("gunreload1.wav", .105, .315),
    "pistol_slide": ("gunreload1.wav", 1.245, 1.46),
    "pump_back": ("shotguncock.wav", .010, .169),
    "pump_forward": ("shotguncock.wav", .188, .371),
    "magazine_a": ("clipload1.wav", .010, .235),
    "magazine_b": ("clipload2.wav", .009, .195),
    "cartridge": ("singlebullet1.wav", .050, .240),
}


def render(kind, variant):
    if not kind.startswith("reload_"):
        return legacy_handling(kind,variant)
    spec = SPECS[kind]
    family, phase = spec["family"], spec["phase"]
    rng = np.random.default_rng(spec["seed"]+variant*373)
    signal = np.zeros(round(RATE*spec["seconds"]))
    heavy = family in ("cannon","flak")
    speed = {"rifle":1.09,"shotgun":1.04,"arc":1.13,"cannon":.86,"flak":.74}[family]

    def place(cut, at, gain=1.0, pitch=1.0, maximum=None):
        nonlocal signal
        name, start, end = CUTS[cut]
        segment = recording(name)[round(start*RATE):round(end*RATE)].copy()
        segment /= max(float(np.abs(segment).max()),1e-6)
        # Suppress the room noise between actual contacts; retain attack edges.
        envelope_rms = np.sqrt(np.convolve(segment**2,np.ones(65)/65,mode="same"))
        segment *= np.clip((envelope_rms-.006)/.018,0,1)
        playback = speed*pitch*[1.0,.975,1.025][variant]
        segment = resample_poly(segment,1000,round(1000*playback))
        if maximum is not None: segment=segment[:round(maximum*RATE)]
        fade = min(round(.004*RATE),len(segment)//2)
        segment[:fade] *= np.linspace(0,1,fade)**2
        segment[-fade:] *= np.linspace(1,0,fade)**2
        start_sample = round((at+rng.uniform(0,.002))*RATE)
        length = min(len(segment),len(signal)-start_sample)
        if length > 0: signal[start_sample:start_sample+length] += segment[:length]*gain

    magazine = ["magazine_a","magazine_b","rifle_seat"][variant]
    if phase == "open":
        main = {"rifle":"rifle_catch","shotgun":"pump_back","arc":"pistol_catch",
                "cannon":"pump_back","flak":"rifle_catch"}[family]
        place(main,.004,1.0,maximum=.19)
        place("cartridge" if heavy else magazine,.149,.22,1.17,maximum=.063)
        if heavy: place("pistol_catch",.064,.38,.88,maximum=.10)
    elif phase == "load":
        if heavy:
            # A short ammunition train, then a larger seating contact; no hiss bed.
            for index in range(3 if family=="cannon" else 2):
                place("cartridge",.008+index*.055,.30+index*.10,1.16,maximum=.074)
            place(magazine,.115,1.0,.92,maximum=.18)
        elif family == "shotgun":
            place("cartridge",.004,.74,maximum=.15)
            place(magazine,.124,.81,1.12,maximum=.16)
        else:
            place(magazine,.015,1.0,maximum=.23)
            place("rifle_seat" if family=="rifle" else "cartridge",.196,.38,1.13,maximum=.08)
    else:
        main = {"rifle":"rifle_bolt","shotgun":"pump_forward","arc":"pistol_slide",
                "cannon":"pump_forward","flak":"pistol_slide"}[family]
        place("rifle_catch" if heavy else "cartridge",.002,.29,1.23,maximum=.071)
        place(main,.062,1.0,maximum=.19)
        if heavy: place("rifle_seat",.154,.36,.89,maximum=.10)
    # Soft peak containment increases contact body without a synthetic sustain.
    signal = sosfilt(butter(2,[110 if heavy else 165,6400],btype="bandpass",fs=RATE,output="sos"),signal)
    signal /= max(float(np.abs(signal).max()),1e-6)
    signal = np.tanh(signal*1.55)/np.tanh(1.55)
    signal = sosfilt(butter(4,5900,btype="lowpass",fs=RATE,output="sos"),signal)
    edge = round(.004*RATE)
    signal[:edge] *= np.linspace(0,1,edge)**2
    signal[-edge:] *= np.linspace(1,0,edge)**2
    window = np.sin(np.linspace(0,np.pi,len(signal)))**2
    signal -= window*signal.sum()/window.sum()
    return signal*spec["peak"]/max(float(np.abs(signal).max()),1e-9)


def names():
    return {f"{kind}_{variant:02}.wav" for kind in SPECS for variant in range(1,4)}


def protected_bank():
    owned = names()
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.iterdir())
            if p.is_file() and (p.suffix in (".wav", ".ogg") or p.name in ("sources.json", "movement_sources.json"))
            and p.name not in owned}


def generate():
    before = protected_bank()
    for kind in SPECS:
        for variant in range(3):
            pcm = np.round(render(kind, variant)*32767).astype("<i2")
            with wave.open(str(OUT/f"{kind}_{variant+1:02}.wav"), "wb") as file:
                file.setnchannels(1)
                file.setsampwidth(2)
                file.setframerate(RATE)
                file.writeframes(pcm.tobytes())
        print(f"Rendered {kind}: three mechanical variations", flush=True)
    assert before == protected_bank(), "Existing audio changed"
    source = json.loads((RECORDINGS/"sources.json").read_text())
    metadata = {"origin": "Reload revision 2: deterministic edits of CC0 airsoft/mechanical recordings by SpringySpringo and Brian MacIntosh (BMacZero). Mount/switch retain original procedural synthesis. No paid APIs.",
        "generator": "tools/generate_weapon_audio.py", "dependencies": ["numpy", "scipy"],
        "sample_rate": RATE, "channels": 1, "pcm_bits": 16, "variants": {kind:3 for kind in SPECS},
        "profiles": PROFILES, "events": SPECS, "preserved_sha256": before,
        "revision": 2, "recordings": source["recordings"], "source_cuts": CUTS,
        "processing": "Mono selection, 32 kHz resampling, fixed-speed short source cuts, low noise gate, dry contact layering, mild soft compression, edge fades. No pitch sweep, oscillator or continuous synthetic noise in reloads.",
        "timing": "Open at accepted reload start, load at 48% elapsed, close after ammunition transfers. Cancelled actions omit future phases.",
        "validation": "python3 tests/weapon_audio_assets_test.py",
        "review": "Signal and runtime measurements; no subjective listening assessment performed."}
    (OUT/"weapon_sources.json").write_text(json.dumps(metadata, indent=2)+"\n")


if __name__ == "__main__":
    generate()
