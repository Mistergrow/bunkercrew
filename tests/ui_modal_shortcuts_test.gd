extends SceneTree
## Native HUD shortcuts must preserve unconfirmed modal work and its focus.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count:
		await process_frame

func press(action: String) -> void:
	for down in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	for kind: String in ["calibration", "music_lab"]:
		game.hud.overlay = "audio"
		game.hud._apply_overlay_pause()
		await frames()
		var options: Control = game.hud.options_panel
		options.select_tab(3)
		if kind == "calibration":
			options._open_calibration()
		else:
			options._open_music_lab(false)
		await frames()
		var modal: Node = options.calibration_panel if kind == "calibration" else options.music_lab
		var modal_ref: WeakRef = weakref(modal)
		var focused: WeakRef = weakref(root.gui_get_focus_owner())
		await press("friends")
		check(game.hud.overlay == "audio", "F7 preserves the settings route during " + kind)
		check(modal_ref.get_ref() != null and options == game.hud.options_panel, "F7 cannot destroy unconfirmed " + kind + " work")
		check(focused.get_ref() != null and focused.get_ref() == root.gui_get_focus_owner(), "F7 leaves focus inside " + kind)
		if is_instance_valid(options):
			options.close_modal_subpanel()
		await frames()
		check(not game.audio.calibration_active, "Closing " + kind + " restores normal music routing")
	game.hud.overlay = "audio"
	game.hud._apply_overlay_pause()
	await frames()
	await press("friends")
	check(game.hud.overlay == "friends" and is_instance_valid(game.hud.social_panel), "F7 still opens friends when no modal is active")
	await press("friends")
	check(game.hud.overlay == "audio", "Friends returns to its originating settings route")
	check(not game.network.active and not game.microphone.capturing, "Shortcut regression creates no connection or microphone capture")
	await Cleanup.free_scene(game, self)
	print("UI MODAL SHORTCUTS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
