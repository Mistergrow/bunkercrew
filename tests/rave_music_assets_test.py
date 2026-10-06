#!/usr/bin/env python3
"""Verify decoded masters, exact native markers and preserved menu recordings."""
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/music-beat-refresh"
ORIGINAL = "7a859c7489b99168b24850472810dd93eb11e24f6711976c4d1254c24b04728c"
NACHTSTROM = "6c1d4a42a8e7ee13fc5ab09479354bac62ddb8a4307158403c347ecd6eeaf3db"
SCHICHTWECHSEL = "6adccb3bc00000a05415668ae3e84b83db753bb1b8b76c1013f211f1652525a5"


def main():
    manifest = json.loads((OUT / "tracks.json").read_text())
    assert manifest["companion_tracks"] == 12 and manifest["recorded_arrangements"] == 21
    assert manifest["refreshed_world_scores"] == 9 and manifest["new_menu_scores"] == 1
    assert manifest["newly_generated_arrangements"] == 19 and manifest["refreshed_compositions"] == 10
    assert hashlib.sha256((ROOT / "assets/audio/menu_rave_v1.ogg").read_bytes()).hexdigest() == ORIGINAL
    assert hashlib.sha256((ROOT / "assets/audio/menu_rave_nachtstrom_v1.ogg").read_bytes()).hexdigest() == NACHTSTROM
    assert hashlib.sha256((ROOT / "assets/audio/menu_rave_schichtwechsel_v1.ogg").read_bytes()).hexdigest() == SCHICHTWECHSEL
    tracks = {}
    comparisons = []
    checks = 4
    new_menu_sections = {}
    revised_worlds = set()
    for source in manifest["tracks"]:
        asset = ROOT / "assets/audio" / source["asset"]
        provenance = json.loads(asset.with_suffix(".source.json").read_text())
        assert provenance == source and hashlib.sha256(asset.read_bytes()).hexdigest() == source["sha256"]
        assert "only together with Bunkercrew" in asset.with_suffix(".LICENSE.txt").read_text()
        assert source["bars"] == 32 and 128 <= source["bpm"] <= 132
        target = round(32 * 4 * 60 / source["bpm"] * 48000)
        decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", str(asset), "-f", "f32le", "-acodec", "pcm_f32le", "-"], capture_output=True, check=True)
        pcm = np.frombuffer(decoded.stdout, dtype="<f4").reshape(-1, 2)
        assert len(pcm) == target and np.isfinite(pcm).all()
        assert .07 < np.sqrt(np.mean(pcm.astype(np.float64) ** 2)) < .25
        assert np.max(np.abs(pcm)) < .9 and np.max(np.abs(pcm[-1] - pcm[0])) < .005
        quiet_v2 = source["role"] == "world" and source["arrangement"] == "calm" and source["version"] == 2
        assert (-24.0 if quiet_v2 else -17.1) < source["measurements"]["integrated_lufs"] < -15.9
        assert source["measurements"]["true_peak_dbtp"] < -1.8
        if source["id"] == "kernimpuls":
            assert source["version"] == 2 and source["native_settings"]["composition_version"] == 2
            assert source["native_settings"]["score_form"] == 1
            assert [(item["bar"], item["intensity"], item["section"]) for item in source["form"]] == [(0,0,"intro"),(8,1,"build"),(16,2,"drop"),(24,1,"relief")]
            assert 0 < len(source["kick_samples"]) < 128
            assert 0 < len(source["secondary_samples"]) < 128
            bar_frames = target / 32
            sections = {}
            for name, first_bar in [("intro",0),("build",8),("drop",16),("relief",24)]:
                first, end = round(first_bar * bar_frames), round((first_bar + 8) * bar_frames)
                section = pcm[first:end].astype(np.float64)
                mono = section.mean(axis=1)
                frequency = np.fft.rfftfreq(len(mono),1/48000)
                spectrum = np.fft.rfft(mono)
                band = (frequency >= 20) & (frequency < 160)
                sections[name] = {"rms":float(np.sqrt(np.mean(section ** 2))),
                                  "bass_rms":float(np.sqrt(2*np.sum(np.abs(spectrum[band]) ** 2))/len(mono)),
                                  "kicks":sum(first <= marker < end for marker in source["kick_samples"])}
            assert sections["intro"]["kicks"] < sections["drop"]["kicks"]
            assert sections["drop"]["kicks"] == 32
            assert sections["drop"]["bass_rms"] > sections["intro"]["bass_rms"] * 1.12
            new_menu_sections = sections
            checks += 8
        else:
            assert len(source["kick_samples"]) == len(source["secondary_samples"]) == 128
            if source["role"] == "world":
                assert source["version"] == 2 and source["native_settings"]["composition_version"] == 2 and "_v2_" in source["asset"]
                revised_worlds.add(source["id"])
                checks += 1
        for native_track, prefix in [(0, "kick"), (8, "secondary")]:
            events = sorted([event for event in source["native_events"] if event["track"] == native_track], key=lambda event: event["sample"])
            assert [round(event["sample"] * 48000 / source["native_rate"]) for event in events] == source[prefix + "_samples"]
            assert source[prefix + "_samples"] == sorted(set(source[prefix + "_samples"]))
            assert all(0 <= marker < target for marker in source[prefix + "_samples"])
            assert len(source[prefix + "_strengths"]) == len(source[prefix + "_samples"])
            assert all(np.isfinite(strength) and 0 < strength <= 1 for strength in source[prefix + "_strengths"])
        tracks.setdefault(source["id"], {})[source["arrangement"]] = source
        if source["arrangement"] == "combat": comparisons.append((source["id"], pcm[:48000 * 8].copy()))
        checks += 20
    assert len(tracks) == 12 and len(revised_worlds) == 9 and all(len(arrangements) == (1 if identifier in ["nachtstrom","schichtwechsel","kernimpuls"] else 2) for identifier, arrangements in tracks.items())
    for identifier in revised_worlds:
        calm, combat = tracks[identifier]["calm"], tracks[identifier]["combat"]
        assert calm["gain_db"] == combat["gain_db"], identifier
        assert calm["measurements"]["integrated_lufs"] < combat["measurements"]["integrated_lufs"] - 0.5, identifier
        checks += 2
    minimum_difference = float("inf")
    for index, (name, pcm) in enumerate(comparisons):
        for other_name, other in comparisons[:index]:
            difference = float(np.sqrt(np.mean((pcm.astype(np.float64) - other.astype(np.float64)) ** 2)))
            minimum_difference = min(minimum_difference, difference)
            assert difference > .02, (name, other_name, difference)
            checks += 1
    new_menu = dict(comparisons)["schichtwechsel"].astype(np.float64)
    menu_differences = {}
    for name, filename in [("nachtschicht","menu_rave_v1.ogg"),("nachtstrom","menu_rave_nachtstrom_v1.ogg")]:
        decoded = subprocess.run(["ffmpeg","-v","error","-i",str(ROOT / "assets/audio" / filename),"-t","8","-f","f32le","-acodec","pcm_f32le","-"],capture_output=True,check=True)
        original = np.frombuffer(decoded.stdout,dtype="<f4").reshape(-1,2).astype(np.float64)
        difference = float(np.sqrt(np.mean((new_menu - original) ** 2)))
        assert difference > .05,(name,difference)
        menu_differences[name] = difference
        checks += 1
    checks += 1
    report = {"checks":checks,"failures":0,"companion_tracks":12,"decoded_arrangements":21,"regenerated_worlds":len(revised_worlds),
              "original_menu_sha256":ORIGINAL,"nachtstrom_menu_sha256":NACHTSTROM,"schichtwechsel_menu_sha256":SCHICHTWECHSEL,"minimum_distinct_track_pcm_rms_difference":minimum_difference,
              "third_menu_pcm_rms_difference":menu_differences,
              "new_menu_sections":new_menu_sections,
              "all_finite":True,"no_clipping":True,"real_native_markers":True,"exact_32_bar_lengths":True}
    (OUT / "asset-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"RAVE MUSIC ASSETS: {checks}/{checks} passed; nine regenerated world scores, twenty-one verified arrangements, sparse new-menu intro and actual drop")


if __name__ == "__main__": main()
