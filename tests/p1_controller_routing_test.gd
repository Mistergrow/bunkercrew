extends SceneTree
## Real physical-key and joypad events with actual main-scene ownership.
const NetInput := preload("res://scripts/network_input.gd")
const Labels := preload("res://scripts/input_labels.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/p1-beta-readiness-20261004/onboarding-ui/"
var game
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	print("P1 PAD %s: %s" % ["PASS" if value else "FAIL", message])

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func pad_button(button: JoyButton, down: bool, device: int = 0) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func pad_axis(axis: JoyAxis, value: float, device: int = 0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - root.get_mouse_position()
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(6)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	await frames()
	var worker: Worker = game.players[0]
	worker.set_physics_process(false)
	check(NetInput.primary_controller_enabled(game), "Actual solo scene routes the first controller to P1")
	pad_axis(JOY_AXIS_LEFT_X, .7)
	check(NetInput.axis(worker, "left", "right") > .5, "A physical first-pad stick moves the solo worker")
	check(not NetInput.mouse_aim(worker), "First-pad movement selects controller aiming")
	pad_axis(JOY_AXIS_LEFT_X, 0)
	# A stationary screen pointer moves in world space when the camera follows
	# or zooms. Only actual screen-pointer movement may change the input route.
	var camera_position: Vector2 = game.camera.position
	var camera_zoom: Vector2 = game.camera.zoom
	var world_pointer: Vector2 = NetInput.aim_position(worker)
	game.camera.position += Vector2(96.0, -32.0)
	game.camera.force_update_scroll()
	check(NetInput.aim_position(worker).distance_squared_to(world_pointer) > 1.0, "Actual camera movement changes the world aim coordinate")
	check(not NetInput.mouse_aim(worker) and Labels.action(worker, "interact") == "X", "Camera movement alone preserves controller aiming and the X instruction")
	world_pointer = NetInput.aim_position(worker)
	game.camera.zoom = Vector2(1.3, 1.3)
	game.camera.force_update_scroll()
	check(NetInput.aim_position(worker).distance_squared_to(world_pointer) > 1.0, "Actual camera zoom changes the world aim coordinate")
	check(not NetInput.mouse_aim(worker) and Labels.action(worker, "interact") == "X", "Camera zoom alone preserves controller aiming and the X instruction")
	var camera_frame := NetInput.sample_local(game)
	world_pointer = NetInput.aim_position(worker)
	check(not camera_frame.mouse and Vector2(float(camera_frame.aim[0]), float(camera_frame.aim[1])).is_equal_approx(world_pointer), "Controller wire sample retains the correct global mouse target after camera changes")
	mouse_motion(root.get_mouse_position() + Vector2(180.0, 120.0))
	check(NetInput.mouse_aim(worker) and Labels.action(worker, "interact") == "E", "Actual screen-pointer movement restores mouse aiming and the E instruction")
	camera_frame = NetInput.sample_local(game)
	world_pointer = worker.get_global_mouse_position()
	check(camera_frame.mouse and NetInput.aim_position(worker).is_equal_approx(world_pointer) and Vector2(float(camera_frame.aim[0]), float(camera_frame.aim[1])).is_equal_approx(world_pointer), "Mouse mode and its wire sample preserve actual world coordinates")
	game.camera.position = camera_position
	game.camera.zoom = camera_zoom
	game.camera.force_update_scroll()
	pad_button(JOY_BUTTON_X, true)
	check(NetInput.is_pressed(worker, "interact") and NetInput.just_pressed(worker, "interact"), "Physical X supplies held work and its one press")
	check(Labels.action(worker, "interact") == "X", "Interaction guidance follows the active solo controller")
	check(Labels.menu(game, "story_journal") == LocaleText.text("Pause → Logbuch"), "Controller journal guidance names the available pause-menu route")
	key(KEY_E, true)
	var merged := NetInput.sample_local(game)
	check(merged.pressed.count("interact") == 1, "Keyboard plus controller cannot duplicate a wire press")
	pad_button(JOY_BUTTON_X, false)
	merged = NetInput.sample_local(game)
	check(merged.held.has("interact") and not "interact" in merged.released and not NetInput.just_released(worker, "interact"), "Releasing X does not release E while it remains held")
	check(Labels.action(worker, "interact") == "E", "Keyboard input restores the keyboard interaction label")
	key(KEY_E, false)
	await frames()
	worker.set_physics_process(true)
	pad_button(JOY_BUTTON_X, true)
	check(NetInput.is_pressed(worker, "interact"), "Controller work is held before opening the real help modal")
	game.hud._toggle_help()
	await frames()
	check(game.hud.overlay == "help" and paused, "Help pauses the actual solo scene while X is held")
	pad_button(JOY_BUTTON_X, false)
	await frames(6)
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	check(game.hud.overlay.is_empty() and not paused, "A separate physical Esc closes help after the completed X release")
	pad_button(JOY_BUTTON_X, true)
	check(NetInput.is_pressed(worker, "interact") and NetInput.sample_local(game).held.has("interact"), "The first fresh X immediately after help works without a second press")
	await physics_frame
	check(NetInput.is_pressed(worker, "interact") and NetInput.sample_local(game).held.has("interact"), "Fresh X remains active in the first resumed physics frame")
	await frames(5)
	check(NetInput.is_pressed(worker, "interact"), "Fresh held work continues after the first resumed ticks")
	pad_button(JOY_BUTTON_X, false)
	await frames()
	worker.set_physics_process(false)
	pad_axis(JOY_AXIS_RIGHT_Y, -.8)
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, .9)
	var pad_frame := NetInput.sample_local(game)
	check(not pad_frame.mouse and pad_frame.held.has("aim_up") and pad_frame.held.has("fire"), "Sampled online input carries real controller aim and trigger strength")
	pad_axis(JOY_AXIS_RIGHT_Y, 0)
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0)
	await frames()
	game.join_coop()
	await frames()
	var partner: Worker = game.players[1]
	partner.set_physics_process(false)
	check(not NetInput.primary_controller_enabled(game), "Joining a local partner returns the first controller to P2")
	for locale: String in ["de", "en"]:
		LocaleText.set_locale(locale, false)
		check(Labels.action(partner, "craft_next") == LocaleText.text("Num* / L3"), "Local storage hint keeps the readable numpad multiplication key: " + locale)
		check(Labels.action(partner, "cycle_weapon") == "Num 0 / " + LocaleText.text("R-Stick drücken"), "Local weapon hint keeps the readable numpad zero key: " + locale)
		check(Labels.action(partner, "deploy") == "Num. / " + LocaleText.text("Pad rechts"), "Local deployment hint keeps the readable numpad decimal key: " + locale)
	LocaleText.set_locale("de", false)
	pad_axis(JOY_AXIS_LEFT_X, .7)
	check(NetInput.axis(worker, "left", "right") == 0.0 and NetInput.axis(partner, "left", "right") > .5, "The same physical stick controls only P2 in actual local co-op")
	key(KEY_D, true)
	check(NetInput.axis(worker, "left", "right") == 1.0 and NetInput.axis(partner, "left", "right") > .5, "P1 keyboard and P2 pad remain independent")
	key(KEY_D, false)
	pad_axis(JOY_AXIS_LEFT_X, 0)
	await frames()
	InputSetup._assign_pad_prefix("p2_", 3)
	pad_axis(JOY_AXIS_LEFT_X, .7, 3)
	check(NetInput.axis(worker, "left", "right") == 0.0 and NetInput.axis(partner, "left", "right") > .5, "Prepared sparse controller IDs preserve local P2 ownership")
	pad_axis(JOY_AXIS_LEFT_X, 0, 3)
	InputSetup._sync_primary_pad()
	game.network.set_process(false)
	game.network.set_physics_process(false)
	game.network.active = true
	game.network.is_host = false
	game.network.local_player_id = 2
	game.network.state = "playing"
	game.network.peer_connected = true
	InputSetup._assign_primary_pad(3)
	pad_axis(JOY_AXIS_LEFT_X, -.7, 3)
	check(NetInput.axis(partner, "left", "right") < -.5, "Prepared reconnect to pad ID3 is honored by actual physical-event routing")
	pad_axis(JOY_AXIS_LEFT_X, 0, 3)
	pad_axis(JOY_AXIS_LEFT_X, .7, 0)
	check(NetInput.axis(partner, "left", "right") == 0.0, "A previously assigned controller cannot drive the online local slot after route replacement")
	pad_axis(JOY_AXIS_LEFT_X, 0, 0)
	InputSetup._sync_primary_pad()
	pad_axis(JOY_AXIS_LEFT_X, -.7)
	check(NetInput.axis(partner, "left", "right") < -.5 and NetInput.axis(worker, "left", "right") == 0.0, "An online guest routes their own first pad to their own slot only")
	pad_button(JOY_BUTTON_X, true)
	check(NetInput.sample_local(game).held.has("interact") and NetInput.is_pressed(partner, "interact"), "Guest X reaches the sampled stream and local ownership")
	game.hud.overlay = "help"
	check(NetInput.sample_local(game).held.is_empty() and not NetInput.is_pressed(partner, "interact"), "Online help makes actual held pad input neutral")
	game.hud.overlay = ""
	pad_button(JOY_BUTTON_X, false)
	pad_axis(JOY_AXIS_LEFT_X, 0)
	game.network.active = false
	game.network.state = "offline"
	check(NetInput.axis(worker, "left", "right") == 0.0 and not NetInput.is_pressed(partner, "interact"), "Leaving online does not retain guest controller work")
	for action_name: StringName in InputMap.get_actions():
		if not str(action_name).begins_with("primary_pad_"): continue
		var events := InputMap.action_get_events(action_name)
		check(not events.is_empty() and events.all(func(event): return (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == 0), "Primary-pad binding is device-isolated: " + str(action_name))
	# Real B is also drop. Dismissing the reader must consume the menu action,
	# including the first resumed physics tick, without discarding carried ore.
	worker.inventory = {"ore":1}
	partner.inventory = {"ore":1}
	worker.set_physics_process(true)
	partner.set_physics_process(true)
	await frames()
	game.hud._toggle_help()
	await frames()
	pad_button(JOY_BUTTON_B, true)
	await frames(6)
	check(game.hud.overlay.is_empty() and not paused, "Actual controller B returns from in-game help")
	check(int(partner.inventory.get("ore", 0)) == 1, "Closing help with B cannot drop the local controller player's cargo")
	pad_button(JOY_BUTTON_B, false)
	await frames(5)
	check(int(partner.inventory.get("ore", 0)) == 1, "Releasing the menu B cannot drop cargo on the next tick")
	check(not game.microphone.capturing and game.network.transport == null, "Physical input regression acquires no microphone or network transport")
	paused = false
	check(await Cleanup.free_scene(game, self), "Actual controller fixture releases all scene and audio handles")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + "controller-routing.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"physical_device_tested":false,"fixture":"Actual main scene and physical InputEventJoypadButton/InputEventJoypadMotion/InputEventKey routed through InputMap: solo, actual local join, arranged online guest ownership without sockets, then actual help close. Synthetic event injection is not a physical controller acceptance test. No save, microphone, UPnP or transport."}, "  "))
	quit(1 if failures else 0)
