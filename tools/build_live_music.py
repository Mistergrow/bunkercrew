#!/usr/bin/env python3
"""Build the pinned Godot 4.7.2 Tessel extension and verify generated audio.

First-party Tessel is vendored, so builds never depend on another worktree.
Godot bindings are generated from the checked-in API dumped by the actual engine.
No JUCE code or dependency is linked into the game.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/bunkercrew_audio"
ARTIFACTS = ROOT / "artifacts/live-music"
DEST = ROOT / "assets/audio/live"
GODOT_CPP_REVISION = "507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"
CACHE = Path.home() / ".cache"
GENRES = ["minimal_techno", "schranz", "hip_hop", "breakbeat"]


def run(args: list[str], log: str, cwd: Path = ROOT) -> subprocess.CompletedProcess:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    with (ARTIFACTS / log).open("w") as handle:
        result = subprocess.run(args, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        tail = (ARTIFACTS / log).read_text(errors="replace")[-6000:]
        raise RuntimeError(f"{' '.join(args)} failed ({result.returncode})\n{tail}")
    return result


def bindings_checkout() -> Path:
    checkout = Path(os.environ.get("BUNKERCREW_GODOT_CPP", str(CACHE / "bunkercrew-godot-cpp")))
    if not checkout.exists():
        run(["git", "clone", "--no-checkout", "--filter=blob:none", "https://github.com/godotengine/godot-cpp.git", str(checkout)], "godot-cpp-clone.log")
    revision = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
    if revision != GODOT_CPP_REVISION:
        run(["git", "-C", str(checkout), "fetch", "--depth=1", "origin", GODOT_CPP_REVISION], "godot-cpp-fetch.log")
        run(["git", "-C", str(checkout), "checkout", "--detach", GODOT_CPP_REVISION], "godot-cpp-checkout.log")
    api = NATIVE / "api/extension_api.json"
    provenance = json.loads((NATIVE / "third_party/godot-cpp/SOURCE.json").read_text())
    if hashlib.sha256(api.read_bytes()).hexdigest() != provenance["api_sha256"]:
        raise RuntimeError("Godot API dump differs from its recorded source checksum")
    if json.loads(api.read_text())["header"]["version_patch"] != 2:
        raise RuntimeError("Godot API dump must target installed Godot 4.7.2")
    return checkout


def mingw_root() -> Path | None:
    if shutil.which("x86_64-w64-mingw32-g++-posix"):
        return None
    base = Path(os.environ.get("BUNKERCREW_MINGW_ROOT", str(CACHE / "bunkercrew-mingw")))
    compiler = base / "usr/bin/x86_64-w64-mingw32-g++-posix"
    if not compiler.exists():
        packages = base / "packages"
        packages.mkdir(parents=True, exist_ok=True)
        names = ["g++-mingw-w64-x86-64-posix", "gcc-mingw-w64-x86-64-posix", "gcc-mingw-w64-x86-64-posix-runtime", "gcc-mingw-w64-base", "mingw-w64-x86-64-dev", "mingw-w64-common", "binutils-mingw-w64-x86-64"]
        run(["apt-get", "download", *names], "mingw-download.log", packages)
        for package in packages.glob("*.deb"):
            run(["dpkg-deb", "-x", str(package), str(base)], "mingw-extract.log")
    return base


def atomic_copy(source: Path, target: Path) -> None:
    # A running Godot process may map the old inode. Never truncate its library.
    fd, temporary = tempfile.mkstemp(prefix=".native-", suffix=".tmp", dir=target.parent)
    os.close(fd)
    temporary_path = Path(temporary)
    try:
        shutil.copy2(source, temporary_path)
        os.replace(temporary_path, target)
    finally:
        temporary_path.unlink(missing_ok=True)


def build(platform: str, bindings: Path, jobs: int) -> Path:
    directory = NATIVE / f"build-{platform}"
    args = ["cmake", "-S", str(NATIVE), "-B", str(directory), "-DCMAKE_BUILD_TYPE=Release", "-DBUNKERCREW_EXTENSION=ON", f"-DGODOT_CPP_PATH={bindings}"]
    if platform == "windows":
        toolchain = mingw_root()
        args += [f"-DCMAKE_TOOLCHAIN_FILE={NATIVE / 'mingw-toolchain.cmake'}"]
        if toolchain:
            args += [f"-DMINGW_ROOT={toolchain}"]
        else:
            args += ["-DMINGW_ROOT=/"]
    run(args, f"cmake-{platform}.log")
    run(["cmake", "--build", str(directory), "--parallel", str(jobs)], f"build-{platform}.log")
    name = "libbunkercrew_audio.linux.x86_64.so" if platform == "linux" else "bunkercrew_audio.windows.x86_64.dll"
    DEST.mkdir(parents=True, exist_ok=True)
    atomic_copy(directory / name, DEST / name)
    return directory / ("bunkercrew_audio_tests" if platform == "linux" else "bunkercrew_audio_tests.exe")


def theme_arguments(settings: dict) -> list[str]:
    keys = {"seed": "seed", "composition_version":"composition-version", "score_form":"score-form", "melody_level":"melody", "genre": "genre", "bpm": "bpm", "key": "key", "scale": "scale", "personality": "personality", "kick_sound": "kick", "phrase_bars": "phrase-bars", "rest_every": "rest-every", "tone": "tone", "punch": "punch", "dust": "dust", "swing": "swing", "bass_weight": "bass", "pad_level": "pad", "room": "room", "effects": "effects", "density": "density", "phrase_variation": "variation", "normalization_db": "normalization-db"}
    args = []
    for key, flag in keys.items():
        if key in settings:
            args += [f"--{flag}", str(settings[key])]
    args += ["--motif", ",".join(map(str, settings["motif"]))]
    return args


def measure_theme(executable: Path, id_: str, settings: dict, seconds: float) -> dict:
    environment, separator, genre = id_.partition("|")
    label = id_.replace("|", "-")
    path = ARTIFACTS / "listening" / environment
    if separator:
        path /= genre
    path.mkdir(parents=True, exist_ok=True)
    wav = path / "live.wav"
    run([str(executable), "--seconds", str(seconds), "--wav", str(wav), *theme_arguments(settings)], f"render-{label}.json")
    run(["ffmpeg", "-hide_banner", "-i", str(wav), "-af", "ebur128=peak=true", "-f", "null", "-"], f"loudness-{label}.log")
    log = (ARTIFACTS / f"loudness-{label}.log").read_text()
    integrated = float(re.findall(r"I:\s+(-?\d+\.\d+) LUFS", log)[-1])
    true_peak = float(re.findall(r"Peak:\s+(-?\d+\.\d+) dBFS", log)[-1])
    # The quiet/attack phrase mix keeps musical dynamics; integrated target is
    # around -16 LUFS rather than a per-frame gain servo that would pump rests.
    if not -18.0 <= integrated <= -15.0 or true_peak > -0.5:
        raise RuntimeError(f"{id_}: loudness/true peak outside budget: {integrated} LUFS, {true_peak} dBTP")
    ogg = path / "live.ogg"
    run(["ffmpeg", "-y", "-hide_banner", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", str(ogg)], f"encode-{label}.log")
    record = {"profile":id_, "theme": environment, "genre":genre or GENRES[settings.get("genre",0)], "settings": settings, "seconds": seconds, "integrated_lufs": integrated, "true_peak_db": true_peak, "sha256_pcm": hashlib.sha256(wav.read_bytes()).hexdigest(), "native": json.loads((ARTIFACTS / f"render-{label}.json").read_text()), "preview": str(ogg.relative_to(ROOT))}
    wav.unlink()
    return record


def listening_clip(executable: Path, environment: str, settings: dict, intensity: int,
                   default: bool, long: bool = False) -> dict:
    genre = GENRES[settings.get("genre", 0)]
    directory = ARTIFACTS / "listening" / environment
    if not default and not long:
        directory /= genre
    directory.mkdir(parents=True, exist_ok=True)
    name = "20-waves" if long else f"intensity-{intensity}"
    label = f"{environment}-{genre}-{name}"
    wav = directory / f"{name}.wav"
    seconds = 640.0 if long else 16 * 4 * 60 / settings["bpm"]
    mode = ["--session-waves", "20"] if long else ["--intensity", str(intensity)]
    run([str(executable), "--seconds", str(seconds), "--wav", str(wav),
         *mode, *theme_arguments(settings)], f"listen-{label}.json")
    run(["ffmpeg", "-hide_banner", "-i", str(wav), "-af", "ebur128=peak=true",
         "-f", "null", "-"], f"listen-{label}-loudness.log")
    loudness = (ARTIFACTS / f"listen-{label}-loudness.log").read_text()
    integrated = float(re.findall(r"I:\s+(-?\d+\.\d+) LUFS", loudness)[-1])
    true_peak = float(re.findall(r"Peak:\s+(-?\d+\.\d+) dBFS", loudness)[-1])
    if true_peak > -0.5:
        raise RuntimeError(f"{label}: preview source true peak exceeds headroom: {true_peak} dBTP")
    ogg = directory / f"{name}.ogg"
    run(["ffmpeg", "-y", "-hide_banner", "-i", str(wav), "-c:a", "libvorbis",
         "-q:a", "6", str(ogg)], f"listen-{label}-encode.log")
    record = {"theme": environment, "genre": genre, "profile": f"{environment}|{genre}",
              "bpm": settings["bpm"], "default": default, "intensity": intensity,
              "bars": None if long else 16, "seconds": seconds,
              "preview": str(ogg.relative_to(ROOT)), "sha256_pcm": hashlib.sha256(wav.read_bytes()).hexdigest(),
              "integrated_lufs": integrated, "true_peak_db": true_peak,
              "native": json.loads((ARTIFACTS / f"listen-{label}.json").read_text())}
    if long:
        record.update({"waves": 20, "simulation": "Prepared 32-second build/warning/attack/release rounds; audio simulation, not a gameplay recording."})
    wav.unlink()
    return record


def render_listening(executable: Path, defaults: dict, variants: dict, jobs: int) -> dict:
    tasks = [(environment, settings, stage, True)
             for environment, settings in defaults.items() for stage in range(4)]
    ash_default = GENRES[defaults["ash_foundry"]["genre"]]
    tasks += [("ash_foundry", variants[f"ash_foundry|{genre}"], stage, False)
              for genre in GENRES if genre != ash_default for stage in range(4)]
    with ThreadPoolExecutor(max_workers=min(jobs, 4)) as pool:
        clips = list(pool.map(lambda args: listening_clip(executable, *args), tasks))
    long = listening_clip(executable, "ash_foundry", variants["ash_foundry|minimal_techno"],
                          0, True, long=True)
    result = {"intensity_clips": clips, "long_arrangement": long,
              "settings_sha256": hashlib.sha256((ARTIFACTS / "native-themes-genres.json").read_bytes()).hexdigest(),
              "status": "Native instrumental renders; musical taste and listening comfort require listening assessment."}
    (ARTIFACTS / "listening-sources.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def verify(executable: Path, hours: float, sample_seconds: float, jobs: int, godot: str) -> dict:
    run([str(executable), "--seconds", "40"], "native-unit.json")
    run([str(executable), "--hours", str(hours), "--themes", "13"], "native-endurance.json")
    run([godot, "--headless", "--path", str(ROOT), "--script", "tests/live_music_export_themes.gd", "--", "--no-profile-save"], "theme-export.log")
    themes = json.loads((ARTIFACTS / "native-themes-genres.json").read_text())
    defaults = json.loads((ARTIFACTS / "native-themes.json").read_text())
    if len(themes) != 52:
        raise RuntimeError("Expected 13 worlds times 4 native music genres")
    with ThreadPoolExecutor(max_workers=min(jobs, 4)) as pool:
        records = list(pool.map(lambda item: measure_theme(executable, item[0], item[1], sample_seconds), themes.items()))
    for environment, settings in defaults.items():
        source = ARTIFACTS / "listening" / environment / GENRES[settings.get("genre",0)] / "live.ogg"
        shutil.copy2(source, ARTIFACTS / "listening" / environment / "live.ogg")
    (ARTIFACTS / "theme-loudness.json").write_text(json.dumps(records, indent=2) + "\n")
    listening = render_listening(executable, defaults, themes, jobs)
    result = {"unit": json.loads((ARTIFACTS / "native-unit.json").read_text()), "endurance": json.loads((ARTIFACTS / "native-endurance.json").read_text()), "loudness": records, "listening": listening, "settings_sha256": listening["settings_sha256"], "listening_status": "Rendered listening material; no human listening judgement is asserted."}
    (ARTIFACTS / "native-verification.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["linux", "windows", "all"], default="all")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--verify", action="store_true", help="Compatibility flag; verification is enabled by default")
    parser.add_argument("--skip-verification", action="store_true", help="Development-only build; beta release must not use this")
    parser.add_argument("--endurance-hours", type=float, default=2.0)
    parser.add_argument("--sample-seconds", type=float, default=120.0)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    jobs = max(1, min(6, args.jobs))
    bindings = bindings_checkout()
    executables = {}
    for platform in (["linux", "windows"] if args.platform == "all" else [args.platform]):
        executables[platform] = build(platform, bindings, jobs)
    if not args.skip_verification:
        executable = executables.get("linux")
        if executable is None:
            executable = build("linux", bindings, jobs)
        verify(executable, args.endurance_hours, args.sample_seconds, jobs, args.godot)
    binaries = {path.name: {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in DEST.iterdir() if path.suffix in [".so", ".dll"]}
    profile_source = ARTIFACTS / "native-themes-genres.json"
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted((NATIVE / "src").glob("*")) if path.is_file()}
    manifest_path = DEST / "native.source.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    manifest = {"engine": "Tessel", "version": 2, "composition_versions":[1,2], "godot_api": "4.7.2", "godot_cpp_revision": GODOT_CPP_REVISION, "tessel_source": "native/bunkercrew_audio/third_party/tessel/SOURCE.json", "license": "Distribution only together with Bunkercrew", "genres": GENRES, "normalization_source": "assets/audio/live/normalization.json", "profile_settings_sha256": hashlib.sha256(profile_source.read_bytes()).hexdigest() if profile_source.exists() else None, "native_source_sha256": source_hashes, "binaries": binaries}
    history = previous.get("runtime_history", [])
    if previous and (previous.get("native_source_sha256") != source_hashes or previous.get("binaries") != binaries):
        history.append({"record":"Previous native runtime", "native_source_sha256":previous.get("native_source_sha256", {}), "binaries":previous.get("binaries", {}), "profile_settings_sha256":previous.get("profile_settings_sha256")})
    if history:
        manifest["runtime_history"] = history
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Native live music built for {', '.join(executables)}; verification {'skipped (development)' if args.skip_verification else 'passed'}")

if __name__ == "__main__":
    main()
