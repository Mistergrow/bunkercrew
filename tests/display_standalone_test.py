"""Real X11 child window -> acknowledged standalone fullscreen, no player profile."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import tkinter

ROOT = Path(__file__).resolve().parents[1]


def main():
    parent = tkinter.Tk()
    parent.title("Bunkercrew display verification")
    parent.geometry("640x400")
    parent.update()
    try:
        with tempfile.TemporaryDirectory(prefix="bunkercrew-fullscreen-") as temporary:
            folder = Path(temporary)
            (folder / "project.godot").write_text('''config_version=5
[application]
config/name="Bunkercrew Fullscreen Probe"
run/main_scene="res://main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
            shutil.copyfile(ROOT / "scripts/display_settings.gd", folder / "display_settings.gd")
            (folder / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/locale_text.gd", folder / "scripts/locale_text.gd")
            (folder / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
''')
            (folder / "probe.gd").write_text('''extends Node
var game
var started := false
var network
func _ready() -> void:
	game = self
	var display = load("res://display_settings.gd").new()
	add_child(display)
	var history: Array = []
	if FileAccess.file_exists("res://result.json"):
		history = JSON.parse_string(FileAccess.get_file_as_string("res://result.json"))
	await get_tree().create_timer(.2).timeout
	history.append({"pid":OS.get_process_id(),"embedded":display.is_embedded(),"mode":get_window().mode,"args":Array(OS.get_cmdline_args())})
	var file := FileAccess.open("res://result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(history))
	file.close()
	if history.size()==1:
		if not display.open_standalone(): get_tree().quit(1)
	else:
		# The replacement must draw and acknowledge before ending this fixture.
		await get_tree().create_timer(.4).timeout
		get_tree().quit(0 if not display.is_embedded() and get_window().mode==Window.MODE_FULLSCREEN else 1)
''')
            log_path = ROOT / "artifacts/crew-standalone-display.log"
            with log_path.open("w") as log:
                process = subprocess.Popen([shutil.which("godot"), "--path", str(folder), "--wid", str(parent.winfo_id()), "--audio-driver", "Dummy", "--", "--no-profile-save", "--no-upnp"], stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "XDG_DATA_HOME": str(folder / "user")})
                history = []
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    parent.update()
                    try:
                        history = json.loads((folder / "result.json").read_text())
                    except (OSError, ValueError):
                        pass
                    if len(history) == 2:
                        break
                    time.sleep(.05)
                if process.poll() is None:
                    process.wait(timeout=5)
                assert len(history) == 2, log_path.read_text()
                # The second process writes before its deferred quit. Keep its
                # resource directory alive until teardown has finished.
                child_status = Path(f"/proc/{history[1]['pid']}/stat")
                deadline = time.monotonic() + 5
                while child_status.exists() and time.monotonic() < deadline:
                    try:
                        if child_status.read_text().split(") ", 1)[1].startswith("Z "):
                            break
                    except FileNotFoundError:
                        break
                    parent.update()
                    time.sleep(.05)
                assert history[0]["embedded"] and not history[1]["embedded"], history
                assert history[1]["mode"] == 3 and "--wid" not in history[1]["args"], history
                (ROOT / "artifacts/crew-standalone-display.json").write_text(json.dumps(history, indent=2) + "\n")
            print("STANDALONE DISPLAY: real embedded child restarted into native fullscreen")
    finally:
        parent.destroy()


if __name__ == "__main__":
    main()
