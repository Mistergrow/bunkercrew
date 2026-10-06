extends SceneTree
## A separate disposable game process exits through the actual native Quit button.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var marker := OS.get_environment("BUNKERCREW_QUIT_MARKER")
	if marker.is_empty() or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	LocaleText.set_locale("de", false)
	root.size = Vector2i(1440, 900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 6: await process_frame
	var panel = game.hud.main_menu_panel
	if not is_instance_valid(panel.quit_button) or panel.quit_button.disabled or game.started or game.network.active:
		push_error("Quit requires the actual idle main menu and an enabled native action.")
		quit(1)
		return
	panel.quit_button.grab_focus()
	await process_frame
	var file := FileAccess.open(marker, FileAccess.WRITE)
	file.store_string(JSON.stringify({"native_quit_button": true, "focused": panel.quit_button.has_focus(), "menu_paused": paused, "match_started": game.started, "network_active": game.network.active, "audio_menu_active": game.audio.menu_music.playing}))
	file.close()
	print("MAIN_MENU_QUIT_REQUESTED")
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	# A broken connection cannot produce a false pass merely by waiting for the
	# driver timeout: normal application exit must happen before this fails.
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline: await process_frame
	push_error("Native Quit activation did not terminate the disposable game process.")
	quit(1)
