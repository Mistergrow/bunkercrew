extends Node
## Display controls; renderer changes explicitly restart from the main menu.
const L := preload("res://scripts/locale_text.gd")

var windowed_size := Vector2i(1440,900)
var windowed_position := Vector2i.ZERO
var windowed_mode := Window.MODE_WINDOWED
var settings_path := "user://display.cfg"
const WINDOW_STATE_META := "bunkercrew_windowed_state"
const HANDOFF_ARGUMENT := "--standalone-handoff="
const HANDOFF_TIMEOUT_MSEC := 12000
var _standalone_pid := -1
var _handoff_path := ""
var _handoff_request_path := ""
var _handoff_deadline_msec := 0
var _incoming_handoff_token := ""
var _handoff_preferences_ready := false
var _finishing_handoff := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var window := get_window()
	var stored: Dictionary = window.get_meta(WINDOW_STATE_META,{})
	if not stored.is_empty():
		windowed_size = stored.size
		windowed_position = stored.position
		windowed_mode = stored.mode
	elif window.mode in [Window.MODE_WINDOWED,Window.MODE_MAXIMIZED]:
		windowed_size = window.size
		windowed_position = window.position
		windowed_mode = window.mode
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		var config:=ConfigFile.new()
		if config.load(settings_path)==OK:
			var value: Variant=config.get_value("display","vsync",true)
			if value is bool: _apply_vsync(value)
	_incoming_handoff_token = _handoff_token()
	if not _incoming_handoff_token.is_empty():
		# HUD is being built after audio/camera/weather. Restore unsaved choices
		# here, before its first visible menu and before acknowledging handoff.
		_handoff_preferences_ready = _restore_handoff_preferences(_incoming_handoff_token)
	_acknowledge_standalone.call_deferred()

func _process(_delta: float) -> void:
	if _standalone_pid <= 0: return
	if not _standalone_allowed():
		_cancel_standalone()
		return
	if FileAccess.file_exists(_handoff_path):
		var response: Variant = JSON.parse_string(FileAccess.get_file_as_string(_handoff_path))
		if response is Dictionary and int(response.get("pid", -1)) == _standalone_pid and response.get("fullscreen", false) == true:
			# The independent replacement has already drawn its fullscreen window.
			# The editor can now close its embedded child without losing the game.
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_handoff_path))
			if FileAccess.file_exists(_handoff_request_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(_handoff_request_path))
			_handoff_path = ""
			_handoff_request_path = ""
			_standalone_pid = -1
			_finishing_handoff = true
			_finish_handoff.call_deferred()
			return
	if not OS.is_process_running(_standalone_pid) or Time.get_ticks_msec() >= _handoff_deadline_msec:
		_cancel_standalone()
		_notify("Das Vollbildfenster konnte nicht gestartet werden. Dein aktuelles Fenster bleibt geöffnet.")

func _finish_handoff() -> void:
	var current_game = _game()
	if is_instance_valid(current_game): current_game.set_meta("quit_requested", true)
	if is_instance_valid(current_game) and "audio" in current_game and is_instance_valid(current_game.audio) and current_game.audio.has_method("drain_for_exit"):
		await current_game.audio.drain_for_exit()
	get_tree().quit()

func _exit_tree() -> void:
	# A scene reload or menu exit can cancel a pending handoff. Retire only the
	# exact replacement process created by this node, never the editor or room.
	_cancel_standalone()

func _cancel_standalone() -> void:
	if _standalone_pid > 0 and OS.is_process_running(_standalone_pid): OS.kill(_standalone_pid)
	_standalone_pid = -1
	if not _handoff_path.is_empty() and FileAccess.file_exists(_handoff_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_handoff_path))
	if not _handoff_request_path.is_empty() and FileAccess.file_exists(_handoff_request_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_handoff_request_path))
	_handoff_path = ""
	_handoff_request_path = ""
	_handoff_deadline_msec = 0

func _handoff_token() -> String:
	var token := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(HANDOFF_ARGUMENT): token = argument.trim_prefix(HANDOFF_ARGUMENT)
	if token.length() != 32: return ""
	for digit in token:
		if digit not in "0123456789abcdef": return ""
	return token

func _handoff_preferences() -> Dictionary:
	var snapshot := {"version":1, "locale":L.current_locale(), "vsync_enabled":DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED}
	var game = _game()
	if is_instance_valid(game) and game.has_method("session_preferences"):
		snapshot.preferences = game.session_preferences()
	if is_instance_valid(game) and "combat_gore" in game and is_instance_valid(game.combat_gore): snapshot.violence = game.combat_gore.level
	var hud := get_parent()
	if is_instance_valid(hud):
		if "options_tab" in hud: snapshot.options_tab = hud.options_tab
		if "overlay" in hud and hud.overlay in ["menu", "audio", "help", "personal"]: snapshot.overlay = hud.overlay
		if "main_menu_panel" in hud and is_instance_valid(hud.main_menu_panel):
			snapshot.menu = hud.main_menu_panel.navigation_state()
		elif "_main_menu_navigation" in hud:
			snapshot.menu = hud._main_menu_navigation.duplicate()
	return snapshot

func _restore_handoff_preferences(token: String) -> bool:
	var path := "user://fullscreen-handoff-" + token + ".request"
	if not FileAccess.file_exists(path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1: return false
	var locale: Variant = parsed.get("locale", "de")
	if locale is String: L.set_locale(locale, false)
	var vsync: Variant = parsed.get("vsync_enabled", true)
	if vsync is bool: _apply_vsync(vsync)
	var game = _game()
	if is_instance_valid(game) and "combat_gore" in game and is_instance_valid(game.combat_gore): game.combat_gore.set_level(clampi(int(parsed.get("violence", game.combat_gore.level)), 0, 2))
	var preferences: Variant = parsed.get("preferences", {})
	if preferences is Dictionary and is_instance_valid(game) and game.has_method("restore_session_preferences"):
		# JSON numbers are floats. Restore integer profile counters/levels before
		# passing them to the existing validated in-memory profile interface.
		var records: Variant = preferences.get("records", {})
		if records is Dictionary:
			for key in ["dance_levels", "counters"]:
				var values: Variant = records.get(key, {})
				if values is Dictionary:
					for id: String in values:
						var value: Variant = values[id]
						if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)):
							values[id] = int(value)
		game.restore_session_preferences(preferences)
	var hud := get_parent()
	if is_instance_valid(hud):
		if "options_tab" in hud: hud.options_tab = clampi(int(parsed.get("options_tab", 0)), 0, 4)
		var overlay: Variant = parsed.get("overlay", "menu")
		if "overlay" in hud and overlay is String and overlay in ["menu", "audio", "help", "personal"]: hud.overlay = overlay
		var navigation: Variant = parsed.get("menu", {})
		if navigation is Dictionary and "_main_menu_navigation" in hud:
			hud._main_menu_navigation = navigation
			if "main_menu_panel" in hud and is_instance_valid(hud.main_menu_panel): hud.main_menu_panel.restore_navigation(navigation)
	return true

func _acknowledge_standalone() -> void:
	var token := _incoming_handoff_token
	if token.is_empty() or not _handoff_preferences_ready: return
	if is_embedded() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if get_window().mode not in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]: return
	var file := FileAccess.open("user://fullscreen-handoff-" + token + ".ready", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"pid":OS.get_process_id(), "fullscreen":true}))
	file.close()
	get_window().grab_focus()

func _notify(message: String) -> void:
	var game = _game()
	if is_instance_valid(game): game.notify(L.text(message))

func _apply_vsync(enabled: bool) -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)

func set_vsync(enabled: bool) -> void:
	_apply_vsync(enabled)
	if "--no-profile-save" in OS.get_cmdline_user_args(): return
	var config:=ConfigFile.new()
	config.set_value("display","vsync",enabled)
	config.save(settings_path)

func renderer_status() -> Dictionary:
	var driver:=RenderingServer.get_current_rendering_driver_name()
	var current: String="vulkan" if driver=="vulkan" else ("compatibility" if driver.begins_with("opengl") else "other")
	var hud=get_parent()
	var game=hud.game if is_instance_valid(hud) and "game" in hud else null
	var can_restart: bool=OS.get_name() in ["Linux","Windows"] and DisplayServer.get_name()!="headless" and not EngineDebugger.is_active()
	if Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"): can_restart=false
	can_restart=can_restart and is_instance_valid(game) and not game.started and not _exit_requested()
	if is_instance_valid(game) and is_instance_valid(game.network) and game.network.active: can_restart=false
	return {"current":current,"driver":driver,"can_restart":can_restart}

func renderer_arguments(mode: String) -> PackedStringArray:
	if mode not in ["compatibility","vulkan"]: return PackedStringArray()
	var args:=PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path",ProjectSettings.globalize_path("res://")])
	var previous:=OS.get_cmdline_args()
	var pack_index:=previous.find("--main-pack")
	if pack_index>=0 and pack_index+1<previous.size(): args.append_array(["--main-pack",previous[pack_index+1]])
	args.append_array(["--rendering-method","mobile" if mode=="vulkan" else "gl_compatibility","--rendering-driver","vulkan" if mode=="vulkan" else "opengl3"])
	# Silent verification stays silent across the restart; normal playback uses
	# the system default. Never carry editor/debugger or test-script arguments.
	if AudioServer.get_driver_name()=="Dummy": args.append_array(["--audio-driver","Dummy"])
	var user_args:=PackedStringArray()
	for value in OS.get_cmdline_user_args():
		if value in ["--no-profile-save","--no-upnp"]: user_args.append(value)
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	return args

func restart_with_renderer(mode: String) -> bool:
	if mode not in ["compatibility","vulkan"] or not renderer_status().can_restart: return false
	OS.set_restart_on_exit(true,renderer_arguments(mode))
	_finishing_handoff = true
	_finish_handoff.call_deferred()
	return true

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_F11 or (event.keycode==KEY_ENTER and event.alt_pressed):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func toggle_fullscreen() -> void:
	if _exit_requested(): return
	if DisplayServer.get_name()=="headless": return
	if is_embedded():
		if can_open_standalone():
			open_standalone()
		else:
			if _standalone_pid <= 0: _notify("Vollbild im eigenen Fenster: Kehre ins Hauptmenü zurück und wähle Vollbild.")
		return
	var window := get_window()
	if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]:
		# Godot's native backend restores its pre-fullscreen client geometry.
		# Reapplying size/position races the WM decoration events on X11 and
		# subtracts a titlebar height on each return. Preserve the previous mode
		# while letting the backend perform its own single geometry restoration.
		window.mode = Window.MODE_MAXIMIZED if windowed_mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
	else:
		windowed_size = window.size
		windowed_position = window.position
		windowed_mode = window.mode
		window.set_meta(WINDOW_STATE_META,{"size":windowed_size,"position":windowed_position,"mode":windowed_mode})
		window.mode = Window.MODE_FULLSCREEN

func is_embedded() -> bool:
	return "--wid" in OS.get_cmdline_args() or (Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"))

func _game():
	var hud = get_parent()
	return hud.game if is_instance_valid(hud) and "game" in hud else null

func can_open_standalone() -> bool:
	return not _exit_requested() and _standalone_pid <= 0 and _standalone_allowed()

func _exit_requested() -> bool:
	var game = _game()
	return _finishing_handoff or (is_instance_valid(game) and bool(game.get_meta("quit_requested", false)))

func _standalone_allowed() -> bool:
	var game = _game()
	return not _exit_requested() and DisplayServer.get_name()!="headless" and OS.get_name() in ["Linux","Windows"] and is_instance_valid(game) and not game.started and not (is_instance_valid(game.network) and game.network.active)

func standalone_arguments() -> PackedStringArray:
	var mode := "vulkan" if RenderingServer.get_current_rendering_driver_name()=="vulkan" else "compatibility"
	var args := renderer_arguments(mode)
	var separator := args.find("--")
	args.insert(separator if separator>=0 else args.size(),"--fullscreen")
	return args

func open_standalone() -> bool:
	if _exit_requested(): return false
	if _standalone_pid > 0: return true
	if not can_open_standalone(): return false
	# Restart-on-exit closes the current menu before a replacement can confirm
	# a working renderer. Launch without the editor parent/debugger arguments,
	# and retain this menu until the independent window has drawn fullscreen.
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	var args := standalone_arguments()
	if "--" not in args: args.append("--")
	args.append(HANDOFF_ARGUMENT + token)
	_handoff_path = "user://fullscreen-handoff-" + token + ".ready"
	_handoff_request_path = "user://fullscreen-handoff-" + token + ".request"
	var request := FileAccess.open(_handoff_request_path, FileAccess.WRITE)
	if request == null:
		_cancel_standalone()
		_notify("Das Vollbildfenster konnte nicht gestartet werden. Dein aktuelles Fenster bleibt geöffnet.")
		return false
	request.store_string(JSON.stringify(_handoff_preferences()))
	request.close()
	_standalone_pid = _launch_standalone(args)
	# Wall time starts after launching: a cold/import frame may carry a large
	# game delta, and a paused game must still detect a failed native window.
	_handoff_deadline_msec = Time.get_ticks_msec() + HANDOFF_TIMEOUT_MSEC
	if _standalone_pid <= 0:
		_cancel_standalone()
		_notify("Das Vollbildfenster konnte nicht gestartet werden. Dein aktuelles Fenster bleibt geöffnet.")
		return false
	return true

func _launch_standalone(arguments: PackedStringArray) -> int:
	return OS.create_instance(arguments)
