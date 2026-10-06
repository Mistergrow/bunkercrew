#!/usr/bin/env python3
"""Exercise the real renderer restart API in an isolated disposable project.

Needs a graphics display. The fixture copies the production display controller;
no game profile, microphone or desktop setting is touched. Both launches use
Dummy audio and exit themselves after Compatibility -> Vulkan -> Compatibility.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RendererRestartTest(unittest.TestCase):
    def test_real_renderer_roundtrip(self):
        with tempfile.TemporaryDirectory(prefix="lastshift-renderer-restart-") as temporary:
            folder = Path(temporary)
            (folder / "project.godot").write_text('''config_version=5
[application]
config/name="Lastshift Renderer Probe"
run/main_scene="res://main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
''')
            shutil.copyfile(ROOT / "scripts/display_settings.gd", folder / "display_settings.gd")
            (folder / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/locale_text.gd", folder / "scripts/locale_text.gd")
            shutil.copytree(ROOT / "locales", folder / "locales")
            (folder / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
''')
            (folder / "probe.gd").write_text('''extends Node
var game
var started:=false
var network
func _ready() -> void:
	game=self
	var display=load("res://display_settings.gd").new()
	add_child(display)
	var path:="res://result.json"
	var history:Array=[]
	if FileAccess.file_exists(path): history=JSON.parse_string(FileAccess.get_file_as_string(path))
	history.append(display.renderer_status())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(history))
	file.close()
	if history.size()==3:
		get_tree().quit()
	elif not display.restart_with_renderer("vulkan" if history.size()==1 else "compatibility"):
		push_error("Renderer restart rejected from standalone main-menu fixture")
		get_tree().quit(1)
''')
            log_path = ROOT / "artifacts/ui-camera-troops/renderer-switch.log"
            log_path.parent.mkdir(parents=True, exist_ok=True)
            with log_path.open("w") as log:
                process = subprocess.Popen([shutil.which("godot"), "--path", str(folder), "--audio-driver", "Dummy", "--", "--no-profile-save", "--no-upnp"], stdout=log, stderr=subprocess.STDOUT, env={**os.environ, "XDG_DATA_HOME": str(folder / "user")})
                result = folder / "result.json"
                history = []
                deadline = time.monotonic() + 45
                try:
                    while time.monotonic() < deadline:
                        try:
                            history = json.loads(result.read_text())
                        except (OSError, ValueError):
                            pass
                        if len(history) >= 3:
                            break
                        time.sleep(.1)
                    process.wait(timeout=5)
                    # Allow the self-terminating final child to flush its log.
                    time.sleep(.3)
                    log.flush()
                    text = log_path.read_text()
                    self.assertEqual([item["current"] for item in history], ["compatibility", "vulkan", "compatibility"], text)
                    self.assertTrue(all(item["can_restart"] for item in history), text)
                    self.assertNotIn("ERROR:", text)
                    self.assertNotIn("WARNING:", text)
                    print("Real renderer API roundtrip: Compatibility -> Vulkan -> Compatibility")
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
