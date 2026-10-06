#!/usr/bin/env python3
"""Export immutable network test candidates without replacing a beta release.

Existing native audio binaries must match their recorded sources and hashes.
This does not certify a new native endurance run or publish a release. Run
validate_beta.py and the Internet acceptance fixtures against the resulting
executables; an export alone is not a multiplayer acceptance result.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COPY_DIRECTORIES = ("scripts", "scenes", "shaders", "assets", "locales", "tests",
                    "docs", "server", "tools", "native", "addons")


def load_builder(project):
    spec = importlib.util.spec_from_file_location("network_candidate_builder", project / "tools/build_beta.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_native_sources(project, digest):
    metadata_path = project / "assets/audio/live/native.source.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    expected_libraries = {"libbunkercrew_audio.linux.x86_64.so", "bunkercrew_audio.windows.x86_64.dll"}
    if set(metadata.get("binaries", {})) != expected_libraries or not metadata.get("native_source_sha256"):
        raise RuntimeError("Native provenance must record both desktop libraries and their sources")
    for relative, expected in metadata["native_source_sha256"].items():
        source = (project / relative).resolve()
        if not source.is_relative_to(project.resolve()) or digest(source) != expected:
            raise RuntimeError("Native source differs from recorded binary inputs: " + relative)
    libraries = {}
    for name, expected in metadata["binaries"].items():
        source = project / "assets/audio/live" / name
        actual = {"bytes": source.stat().st_size, "sha256": digest(source)}
        if actual != {key: expected[key] for key in ("bytes", "sha256")}:
            raise RuntimeError("Native library differs from provenance: " + name)
        libraries[name] = actual
    return {"libraries": libraries, "native_source_sha256": metadata["native_source_sha256"],
            "provenance_sha256": digest(metadata_path),
            "new_endurance_run": False,
            "scope": "Existing source and binary identity; exported playback is checked separately."}


def copy_project(source, destination):
    ignored = shutil.ignore_patterns(".godot", "__pycache__", ".venv", "*.pyc", "*.tmp", "build-linux", "build-windows")
    destination.mkdir()
    for directory in COPY_DIRECTORIES:
        if (source / directory).is_dir():
            shutil.copytree(source / directory, destination / directory, ignore=ignored)
    for path in source.iterdir():
        if path.is_file() and (path.suffix in (".godot", ".cfg", ".tres", ".tscn", ".gd", ".gdextension") or path.name in ("README.md", "CHANGELOG.md", "AGENTS.md", "CLAUDE.md", ".gitignore")):
            shutil.copy2(path, destination / path.name)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def copy_test_kit(project, destination):
    text = (project / "docs/beta-playtest.md").read_text(encoding="utf-8")
    text = text.replace("(beta-playtest-template.json)", "(HUMAN_TEST_TEMPLATE.json)")
    text = text.replace("(beta-coop-test.md)", "(README.md)")
    # Repository evidence is not distributed as runtime data. Keep its label
    # while avoiding broken local links in the independently usable test kit.
    text = re.sub(r"\[([^\]]+)\]\((?:\.\./(?:scripts|artifacts)/[^)]+|beta-0\.5-plan\.md)\)", r"\1", text)
    (destination / "TESTING.md").write_text(text, encoding="utf-8")
    # build_beta.package() writes machine verification to TEST_RESULTS.json.
    # Keep the unexecuted human template separate so packaging preserves it.
    shutil.copy2(project / "docs/beta-playtest-template.json", destination / "HUMAN_TEST_TEMPLATE.json")


def export_candidate(args):
    source = args.project.resolve()
    output = args.output.resolve()
    logs = args.logs.resolve()
    if output == source or source.is_relative_to(output) or logs == output or logs.is_relative_to(output):
        raise RuntimeError("Candidate output must not contain its source project or log directory")
    if output.exists() or logs.exists():
        raise RuntimeError("Candidate and log directories must be new; historical outputs are preserved")
    logs.mkdir(parents=True)
    report = {"schema_version": 1, "started_at": datetime.now(timezone.utc).isoformat(),
              "success": False, "output": str(output), "source_project": str(source),
              "release_published": False, "native_windows_tested": False,
              "two_internet_connections_tested": False, "exports": {}}
    try:
        original = load_builder(source)
        inputs = original.source_manifest()
        write_json(logs / "original-inputs.json", inputs)
        report["original_source_sha256"] = original.source_fingerprint(inputs)
        report["native"] = verify_native_sources(source, original.digest)
        with tempfile.TemporaryDirectory(prefix="bunkercrew-internet-export-") as directory:
            temporary = Path(directory)
            project = temporary / "project"
            copy_project(source, project)
            builder = load_builder(project)
            builder.LOGS = logs
            # Copy historical native evidence as evidence only, not as a new gate.
            prior = source / "artifacts/live-music/native-verification.json"
            if prior.is_file():
                shutil.copy2(prior, logs / "HISTORICAL_NATIVE_VERIFICATION.json")
                report["historical_native_verification_sha256"] = original.digest(prior)
            env = dict(os.environ)
            for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
                env[name] = str(temporary / name.lower())
            installed = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot/export_templates/4.7.2.stable"
            if not (installed / "version.txt").is_file():
                raise RuntimeError("Matching Godot 4.7.2 templates are required")
            templates = Path(env["XDG_DATA_HOME"]) / "godot/export_templates/4.7.2.stable"
            templates.parent.mkdir(parents=True)
            templates.symlink_to(installed, target_is_directory=True)
            report["engine"] = subprocess.check_output([args.godot, "--version"], text=True).strip()
            if not report["engine"].startswith("4.7.2."):
                raise RuntimeError("Candidate requires Godot 4.7.2")
            report["templates"] = {name: builder.digest(installed / name) for name in
                                   ("linux_debug.x86_64", "windows_debug_x86_64.exe", "version.txt")}
            base = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project)]
            builder.run(base + ["--editor", "--recovery-mode", "--import", "--quit"], "import.log", env, cwd=project)
            license_script = temporary / "licenses.gd"
            license_json = temporary / "godot-licenses.json"
            license_script.write_text('extends SceneTree\nfunc _initialize() -> void:\n\tvar file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)\n\tfile.store_string(JSON.stringify({"engine":Engine.get_license_text(),"licenses":Engine.get_license_info(),"copyright":Engine.get_copyright_info()},"  "))\n\tfile.close()\n\tquit()\n')
            builder.run(base + ["--script", str(license_script), "--", str(license_json)], "licenses.log", env, cwd=project)
            licenses = json.loads(license_json.read_text())
            frozen = builder.source_manifest()
            write_json(logs / "export-inputs.json", frozen)
            report["export_source_sha256"] = builder.source_fingerprint(frozen)
            report["version"] = builder.VERSION
            report["network_protocol"] = builder.PROTOCOL
            report["world_revision"] = builder.WORLD_REVISION
            builder.require_current_build_identity()
            output.mkdir(parents=True)
            for platform, (preset, binary, _) in builder.TARGETS.items():
                destination = output / platform
                destination.mkdir()
                builder.run(base + ["--editor", "--recovery-mode", "--export-debug", preset, str(destination / binary)],
                            "export-" + platform + ".log", env, cwd=project)
                builder.require_unchanged_source(frozen)
                library_name = "libbunkercrew_audio.linux.x86_64.so" if platform.startswith("ubuntu") else "bunkercrew_audio.windows.x86_64.dll"
                libraries = list(destination.rglob(library_name))
                if len(libraries) != 1 or builder.digest(libraries[0]) != report["native"]["libraries"][library_name]["sha256"]:
                    raise RuntimeError("Exported native library is missing, ambiguous or changed: " + platform)
                shutil.copy2(project / "docs/beta-coop-test.md", destination / "README.md")
                copy_test_kit(project, destination)
                notices = destination / "licenses"
                notices.mkdir()
                (notices / "Godot.txt").write_text(licenses["engine"])
                write_json(notices / "Godot-third-party.json", licenses)
                builder.copy_asset_notices(notices)
                for relative, name in (
                    ("native/bunkercrew_audio/third_party/tessel/LICENSE", "Audiote-Tessel-Bunkercrew-only.txt"),
                    ("native/bunkercrew_audio/third_party/godot-cpp/LICENSE.md", "godot-cpp-MIT.md"),
                    ("native/bunkercrew_audio/third_party/mingw-w64/NOTICE", "MinGW-runtime.txt"),
                    ("native/bunkercrew_audio/third_party/mingw-w64/GCC-NOTICE", "GCC-runtime-exception.txt"),
                ):
                    shutil.copy2(project / relative, notices / name)
                info = {key: report[key] for key in ("version", "network_protocol", "world_revision", "engine")}
                info.update({"platform": platform, "source_sha256": report["export_source_sha256"],
                             "build_type": "debug export for Internet acceptance; unaccepted test candidate",
                             "renderer": "gl_compatibility", "release_published": False,
                             "executable_sha256": builder.digest(destination / binary),
                             "live_music": {"backend": "Tessel native GDExtension", "library": str(libraries[0].relative_to(destination)),
                                            "sha256": builder.digest(libraries[0]), "new_endurance_run": False}})
                write_json(destination / "BUILD_INFO.json", info)
                report["exports"][platform] = info
            linux = output / "ubuntu-x86_64"
            launcher = linux / "Start.sh"
            launcher.write_text('#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")"\nexec ./Bunkercrew.x86_64 "$@"\n')
            launcher.chmod(0o755)
            (linux / "Bunkercrew.x86_64").chmod(0o755)
            builder.require_unchanged_source(frozen)
        original.require_unchanged_source(inputs)
        for destination in output.iterdir():
            files = sorted(path for path in destination.rglob("*") if path.is_file())
            (destination / "SHA256SUMS.txt").write_text("".join(f"{original.digest(path)}  {path.relative_to(destination).as_posix()}\n" for path in files))
        report["success"] = True
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        write_json(logs / "report.json", report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--logs", type=Path, required=True)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    args = parser.parse_args()
    try:
        export_candidate(args)
    except Exception as error:
        raise SystemExit(str(error)) from error
    print("Network export candidates prepared; native Windows and Internet acceptance remain separate.")


if __name__ == "__main__":
    main()
