#!/usr/bin/env python3
"""Prepare real campaign boundaries, then inspect menus in isolated fresh games."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/expedition/menu-progression"


def run(script, env, name, no_save=False):
    command = [os.environ.get("GODOT") or shutil.which("godot"), "--headless", "--debug",
               "--audio-driver", "Dummy", "--path", str(ROOT), "--script", script,
               "--", "--no-upnp"]
    if no_save:
        command.append("--no-profile-save")
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    (OUTPUT / f"{name}.log").write_text(result.stdout)
    assert result.returncode == 0 and not any(marker in result.stdout for marker in
        ("ERROR:", "SCRIPT ERROR", "WARNING:")), result.stdout


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bunkercrew-menu-progress-") as temporary:
        base = Path(temporary)
        env = {**os.environ, "XDG_DATA_HOME": str(base / "writer"),
               "BUNKERCREW_MENU_FIXTURES": str(base)}
        run("tests/menu_progression_test.gd", env, "fixtures", True)
        cases = json.loads((base / "manifest.json").read_text())
        for name, fixture in cases.items():
            profile_root = base / name
            profile = profile_root / "godot/app_userdata/Bunkercrew"
            profile.mkdir(parents=True)
            save = profile / "campaign_v1.json"
            if "checkpoint" in fixture:
                save.write_text(json.dumps(fixture["checkpoint"]))
            elif "raw" in fixture:
                save.write_text(fixture["raw"])
            if "backup" in fixture:
                save.with_suffix(".json.bak").write_text(json.dumps(fixture["backup"]))
            before = {path.name: path.read_bytes() for path in profile.glob("campaign*")}
            env = {**os.environ, "XDG_DATA_HOME": str(profile_root),
                   "BUNKERCREW_MENU_ISOLATED": "1",
                   "BUNKERCREW_MENU_EXPECTED": fixture["environment"],
                   "BUNKERCREW_MENU_HAS_SAVE": "1" if fixture["has_campaign"] else "0"}
            run("tests/menu_progression_restart_peer.gd", env, name, fixture.get("disabled", False))
            after = {path.name: path.read_bytes() for path in profile.glob("campaign*")}
            assert before == after, f"Menu mutated a durable checkpoint in {name}"
            print("PASS fresh menu and unchanged checkpoint:", name, flush=True)
    print(f"MENU PROGRESSION RESTART: {len(cases)} isolated fresh game processes passed.")


if __name__ == "__main__":
    main()
