#!/usr/bin/env python3
"""Read the unchanged old exported game's actual schemas and handshake packets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.file_digest(path.open("rb"), "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.1.4-beta.20261003")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/hardening-followup/network/compatibility")
    args = parser.parse_args()
    source = ROOT / "beta" / args.version / "ubuntu-x86_64"
    binary = source / "Bunkercrew.x86_64"
    before = digest(binary)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    log_path = output / f"export-{args.version}.log"
    with tempfile.TemporaryDirectory(prefix="bunkercrew-legacy-export-") as temporary:
        directory = Path(temporary)
        os.link(binary, directory / binary.name)
        shutil.copy2(source / "libbunkercrew_audio.linux.x86_64.so", directory)
        probe = ROOT / "tests/network_legacy_binary_probe.gd"
        (directory / "override.cfg").write_text(
            '[application]\nrun/main_scene="res://tests/beta_empty.tscn"\n'
            f'[autoload]\nCompatProbe="*{probe}"\n')
        env = {**os.environ, "XDG_DATA_HOME": str(directory / "data"),
               "XDG_CONFIG_HOME": str(directory / "config"),
               "XDG_CACHE_HOME": str(directory / "cache"),
               "BUNKERCREW_COMPAT_PACKET_DIR": str(output)}
        with log_path.open("w") as log:
            result = subprocess.run([str(directory / binary.name), "--headless", "--audio-driver", "Dummy",
                                     "--", "--no-profile-save", "--no-upnp"], cwd=directory, env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=25)
    text = log_path.read_text()
    payload = next(json.loads(line.removeprefix("CAMPAIGN_BINARY_COMPAT "))
                   for line in text.splitlines() if line.startswith("CAMPAIGN_BINARY_COMPAT "))
    assert result.returncode == 0 and not any(marker in text for marker in ["ERROR:", "SCRIPT ERROR", "WARNING:"]), text
    assert before == digest(binary), "The exported binary changed"
    assert payload["normal_checkpoint_valid"] and payload["stock_10000"]
    report = {"success": True, "version": args.version, "binary_sha256": before,
              "unchanged_export": True, "result": payload, "log": str(log_path),
              "profile_writes": False, "upnp": False}
    (output / f"export-{args.version}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
