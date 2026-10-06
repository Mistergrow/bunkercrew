"""Owned X11 child + real editor debugger: F11/options handoff and failures.

The existing user editor/game/profile are never touched. Optional baseline
comparison prepares a replacement that exits before rendering; it demonstrates
the old unguarded close, without claiming every editor restart is unsupported.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import tkinter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "artifacts/fullscreen-handoff"
GODOT = shutil.which("godot")

PROBE = '''extends Node
var game
var started := false
var network
var notice := ""
class NetworkFixture extends RefCounted:
	var active := false
class FailureDisplay extends "res://display_settings.gd":
	func _launch_standalone(arguments: PackedStringArray) -> int:
		if "--fixture=spawn_fail" in OS.get_cmdline_user_args(): return -1
		if "--fixture=crash" in OS.get_cmdline_user_args(): arguments.append("--fixture-child-crash")
		if "--fixture=no_ack" in OS.get_cmdline_user_args(): arguments.append("--fixture-child-no-ack")
		return super._launch_standalone(arguments)
func notify(message: String) -> void:
	notice = message
func record(role: String, detail: Dictionary = {}) -> void:
	var history: Array = []
	if FileAccess.file_exists("res://history.json"):
		history = JSON.parse_string(FileAccess.get_file_as_string("res://history.json"))
	detail.merge({"role":role,"pid":OS.get_process_id(),"embedded":Engine.is_embedded_in_editor(),"debugger":EngineDebugger.is_active(),"mode":get_window().mode,"user_args":Array(OS.get_cmdline_user_args())})
	history.append(detail)
	var file := FileAccess.open("res://history.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(history))
	file.close()
func key(code: Key, alt: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.alt_pressed = alt
		event.pressed = down
		get_tree().root.push_input(event)
		await get_tree().process_frame
func _ready() -> void:
	game = self
	network = NetworkFixture.new()
	if "--fixture-child-crash" in OS.get_cmdline_user_args():
		record("child_crash")
		get_tree().quit(23)
		return
	if "--fixture-child-no-ack" in OS.get_cmdline_user_args():
		record("child_no_ack")
		await get_tree().create_timer(5.0).timeout
		get_tree().quit(24)
		return
	var current_source := FileAccess.get_file_as_string("res://display_settings.gd").contains("_launch_standalone")
	var display = FailureDisplay.new() if current_source else load("res://display_settings.gd").new()
	add_child(display)
	await get_tree().create_timer(.25).timeout
	if display.is_embedded():
		started = "--fixture=running" in OS.get_cmdline_user_args()
		network.active = "--fixture=online" in OS.get_cmdline_user_args()
		if "--fixture=quitting" in OS.get_cmdline_user_args(): set_meta("quit_requested", true)
		record("source", {"started":started,"network":network.active})
		if "--fixture=options" in OS.get_cmdline_user_args():
			var choice := OptionButton.new()
			choice.add_item("Window")
			choice.add_item("Fullscreen")
			choice.item_selected.connect(func(index: int):
				var full := get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]
				if full != (index == 1): display.toggle_fullscreen())
			add_child(choice)
			choice.item_selected.emit(1)
		else:
			await key(KEY_F11)
		if current_source:
			var first_pid: int = display._standalone_pid
			if first_pid > 0: display._process(60.0)
			await key(KEY_F11)
			record("source_after_key", {"child_pid":display._standalone_pid,"same_child":first_pid==display._standalone_pid,"restart_on_exit":OS.is_restart_on_exit_set(),"standalone_args":Array(display.standalone_arguments())})
		if "--fixture=f11" in OS.get_cmdline_user_args() or "--fixture=options" in OS.get_cmdline_user_args():
			# A real window/renderer may take a few seconds to initialize. The
			# production acknowledgment ends this source process on success.
			await get_tree().create_timer(13.0).timeout
		await get_tree().create_timer(.40).timeout
		if "--fixture=no_ack" in OS.get_cmdline_user_args(): display._handoff_deadline_msec = Time.get_ticks_msec() - 1
		if "--fixture=crash" in OS.get_cmdline_user_args():
			while display._standalone_pid > 0: await get_tree().create_timer(.05).timeout
		await get_tree().create_timer(.35).timeout
		record("source_retained", {"notice":notice,"pending":display._standalone_pid if current_source else -1})
		get_tree().quit(0)
	else:
		record("replacement")
		await get_tree().create_timer(.55).timeout
		await key(KEY_F11)
		await get_tree().create_timer(.15).timeout
		record("return_windowed", {"size":[get_window().size.x,get_window().size.y]})
		await key(KEY_ENTER,true)
		await get_tree().create_timer(.15).timeout
		record("return_fullscreen")
		get_tree().quit(0)
'''


def history(folder):
    try:
        return json.loads((folder / "history.json").read_text())
    except (OSError, ValueError):
        return []


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def process_alive(pid):
    try:
        os.kill(int(pid), 0)
        stat = Path(f"/proc/{int(pid)}/stat")
        return not stat.exists() or not stat.read_text().split(") ", 1)[1].startswith("Z ")
    except (ProcessLookupError, FileNotFoundError):
        return False


def wait_until(parent, predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        parent.update()
        if predicate():
            return True
        time.sleep(.03)
    return False


def write_project(folder, source):
    (folder / "project.godot").write_text('''config_version=5
[application]
config/name="Bunkercrew Fullscreen Handoff Regression"
run/main_scene="res://main.tscn"
[display]
window/size/viewport_width=640
window/size/viewport_height=400
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    shutil.copyfile(source, folder / "display_settings.gd")
    (folder / "scripts").mkdir()
    shutil.copyfile(ROOT / "scripts/locale_text.gd", folder / "scripts/locale_text.gd")
    shutil.copytree(ROOT / "locales", folder / "locales")
    (folder / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
''')
    # The baseline module predates this override: remove the subclass so both
    # fixtures parse, while leaving the same actual native F11 event route.
    probe = PROBE
    if "_launch_standalone" not in source.read_text():
        begin = probe.index('class FailureDisplay extends')
        end = probe.index('func notify', begin)
        baseline = '''class BaselineFailureDisplay extends "res://display_settings.gd":
\tfunc standalone_arguments() -> PackedStringArray:
\t\tvar arguments := super.standalone_arguments()
\t\targuments.append("--fixture-child-crash")
\t\treturn arguments
'''
        probe = probe[:begin] + baseline + probe[end:]
        probe = probe.replace('FailureDisplay.new() if current_source else load("res://display_settings.gd").new()', 'BaselineFailureDisplay.new()')
    (folder / "probe.gd").write_text(probe)


def run_case(parent, label, source, expected_success):
    with tempfile.TemporaryDirectory(prefix="bunkercrew-handoff-") as temporary:
        folder = Path(temporary)
        write_project(folder, source)
        env = {**os.environ, "XDG_DATA_HOME": str(folder / "user"), "XDG_CONFIG_HOME": str(folder / "config")}
        port = free_port()
        editor = None
        child = None
        records = []
        log_path = OUTPUT / f"{label}.log"
        with log_path.open("w") as log:
            try:
                # This is our isolated debugger/editor, not the user's editor.
                editor = subprocess.Popen([GODOT, "--headless", "--editor", "--path", str(folder), "--debug-server", f"tcp://127.0.0.1:{port}"], env=env, stdout=log, stderr=subprocess.STDOUT)
                def server_ready():
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=.04):
                            return True
                    except OSError:
                        return False
                assert wait_until(parent, server_ready), log_path.read_text()
                args = [GODOT, "--path", str(folder), "--wid", str(parent.winfo_id()), "--remote-debug", f"tcp://127.0.0.1:{port}", "--audio-driver", "Dummy", "--", "--no-profile-save", "--no-upnp", f"--fixture={label}"]
                child = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
                assert wait_until(parent, lambda: bool(history(folder))), log_path.read_text()
                assert wait_until(parent, lambda: child.poll() is not None), log_path.read_text()
                if expected_success:
                    assert wait_until(parent, lambda: any(r["role"] == "return_fullscreen" for r in history(folder))), log_path.read_text()
                elif label == "baseline":
                    # A deliberately failing replacement demonstrates the
                    # difference between quitting first and waiting for ACK.
                    assert wait_until(parent, lambda: any(r["role"] == "child_crash" for r in history(folder))), log_path.read_text()
                records = history(folder)
                source_record = next(r for r in records if r["role"] == "source")
                assert source_record["embedded"] and source_record["debugger"], records
                replacements = [r for r in records if r["role"] == "replacement"]
                if expected_success:
                    assert len(replacements) == 1, records
                    assert not replacements[0]["embedded"] and not replacements[0]["debugger"] and replacements[0]["mode"] == 3, records
                    after = next(r for r in records if r["role"] == "source_after_key")
                    assert after["same_child"] and not after["restart_on_exit"], records
                    assert next(r for r in records if r["role"] == "return_windowed")["mode"] == 0, records
                    assert next(r for r in records if r["role"] == "return_fullscreen")["mode"] == 3, records
                    assert not any(r["role"] == "source_retained" for r in records), records
                elif label == "baseline":
                    assert not replacements and not any(r["role"] == "source_retained" for r in records), records
                else:
                    assert not replacements, records
                    retained = next(r for r in records if r["role"] == "source_retained")
                    assert retained["mode"] == 0, records
                    assert not retained["notice"] if label == "quitting" else retained["notice"], records
                    assert retained["pending"] <= 0, records
                assert child.returncode == 0, (child.returncode, records)
                (OUTPUT / f"{label}.json").write_text(json.dumps(records, indent=2) + "\n")
                print(f"FULLSCREEN HANDOFF: {label} passed (real embedded window + active editor debugger)")
                return {"case":label, "passed":True, "history":records}
            finally:
                (OUTPUT / f"{label}-latest-history.json").write_text(json.dumps(history(folder), indent=2) + "\n")
                # Kill only PIDs created by this fixture. Keep temporary assets
                # until those children have released all renderer resources.
                for record in records or history(folder):
                    pid = int(record["pid"])
                    if child is not None and pid != child.pid and process_alive(pid):
                        os.kill(pid, 15)
                        wait_until(parent, lambda p=pid: not process_alive(p), timeout=3)
                for process in [child, editor]:
                    if process is not None and process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-source", type=Path)
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    parent = tkinter.Tk()
    parent.title("Bunkercrew owned fullscreen regression parent")
    parent.geometry("640x400")
    parent.update()
    results = []
    try:
        if args.baseline_source:
            results.append(run_case(parent, "baseline", args.baseline_source, False))
        for label in ["f11", "options", "spawn_fail", "crash", "no_ack", "running", "online", "quitting"]:
            results.append(run_case(parent, label, ROOT / "scripts/display_settings.gd", label in ["f11", "options"]))
    finally:
        parent.destroy()
    (OUTPUT / "verification.json").write_text(json.dumps({"prepared_scene":"Minimal display fixture embedded in owned X11 window with isolated real Godot editor debugger; native F11 and OptionButton selection; profile saves disabled", "cases":results}, indent=2) + "\n")
    print(f"FULLSCREEN HANDOFF: {len(results)}/{len(results)} scenarios passed")


if __name__ == "__main__":
    main()
