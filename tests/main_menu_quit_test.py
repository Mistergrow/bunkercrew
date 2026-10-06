#!/usr/bin/env python3
"""Run the real Quit action in a separate Godot process and isolated profile."""
import json
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/menu-rave/quit"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true', help='Run the same native Quit action with a real graphical window.')
    args = parser.parse_args()
    output = OUTPUT.with_name('quit-rendered') if args.render else OUTPUT
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bunkercrew-menu-quit-") as directory:
        environment = os.environ.copy()
        environment.update({"XDG_DATA_HOME": directory + "/data", "XDG_CONFIG_HOME": directory + "/config",
                            "XDG_CACHE_HOME": directory + "/cache", "BUNKERCREW_QUIT_MARKER": directory + "/quit.json"})
        command = ["godot"] + ([] if args.render else ["--headless"]) + ["--path", str(ROOT), "--script", "tests/main_menu_quit_peer.gd",
                   "--", "--no-profile-save", "--no-upnp"]
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=20)
        log = result.stdout + result.stderr
        (output / "process.log").write_text(log)
        marker = Path(directory) / "quit.json"
        if result.returncode != 0 or "MAIN_MENU_QUIT_REQUESTED" not in log or "ERROR:" in log or "WARNING:" in log or not marker.exists():
            raise RuntimeError("The actual main-menu Quit action failed; inspect " + str(output / "process.log"))
        state = json.loads(marker.read_text())
        if not state["native_quit_button"] or not state["focused"] or not state["menu_paused"] or state["match_started"] or state["network_active"]:
            raise RuntimeError("Quit did not run from the ordinary focused main menu")
        state.update({"exit_code": result.returncode, "actual_application_exit": True, "isolated_profile": True, "rendered": args.render})
        (output / "verification.json").write_text(json.dumps(state, indent=2) + "\n")
    print("MAIN MENU QUIT: actual native Enter activation terminated its isolated game process cleanly")


if __name__ == "__main__":
    main()
