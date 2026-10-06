#!/usr/bin/env python3
"""Check the revised mechanical bank's source licenses, edits and spectrum."""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"assets/audio"
REPORT=ROOT/"artifacts/audio-remix"
checks=[]


def check(value,label):
    checks.append({"passed":bool(value),"label":label})
    if not value: print("FAIL",label)


def spectral(path):
    with wave.open(str(path)) as source:
        signal=np.frombuffer(source.readframes(source.getnframes()),dtype="<i2").astype(float)/32768
    spectrum=np.abs(np.fft.rfft(signal))**2
    return {"eight_bin_fraction":float(np.sort(spectrum)[-8:].sum()/spectrum.sum()),
            "rms":float(np.sqrt(np.mean(signal**2)))}


def main():
    metadata=json.loads((OUT/"weapon_sources.json").read_text())
    check(metadata.get("revision")==2,"Revision 2 explicitly declares recording-based reload edits")
    for item in metadata["recordings"]:
        path=OUT/"source_recordings/weapon_reload"/item["file"]
        check(item["license"]=="CC0-1.0" and item["page"].startswith("https://opengameart.org/content/"),item["file"]+": source and CC0 license are explicit")
        check(hashlib.sha256(path.read_bytes()).hexdigest()==item["sha256"],item["file"]+": archived original recording retains its hash")
    current={};previous={}
    old=REPORT/"before"
    for name in [f"reload_{family}_{phase}_{variant:02}.wav" for family in ["rifle","shotgun","arc","cannon","flak"] for phase in ["open","load","close"] for variant in range(1,4)]:
        current[name]=spectral(OUT/name)
        if (old/name).exists():
            previous[name]=spectral(old/name)
            check((OUT/name).read_bytes()!=(old/name).read_bytes(),name+": regenerated recording differs from the rejected version")
    check(len(current)==45,"All forty-five reload phases are present")
    median=float(np.median([m["eight_bin_fraction"] for m in current.values()]))
    check(median<.13,"Revised bank is not dominated by a small group of ringing frequency bins")
    prior_median=None
    if len(previous)==45:
        prior_median=float(np.median([m["eight_bin_fraction"] for m in previous.values()]))
        check(median<prior_median*.5,"Median narrow-band concentration falls by more than half against the archived rejected bank")
    result={"passed":sum(x["passed"] for x in checks),"failed":sum(not x["passed"] for x in checks),
            "median_eight_bin_fraction":median,"previous_median_eight_bin_fraction":prior_median,
            "measurements":current,"checks":checks,
            "limits":"Spectral concentration is a tone-dominance indicator, not proof of subjective realism. No listening assessment performed."}
    REPORT.mkdir(exist_ok=True,parents=True)
    (REPORT/"source-measurements.json").write_text(json.dumps(result,indent=2)+"\n")
    print(f'AUDIO REMIX ASSETS: {result["passed"]}/{len(checks)} passed; eight-bin median {prior_median} -> {median}')
    return int(result["failed"]>0)


if __name__=="__main__": raise SystemExit(main())
