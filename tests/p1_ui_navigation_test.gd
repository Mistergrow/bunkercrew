extends SceneTree
## Native focus/input routing; service probes expose state without any sockets.
const Probes := preload("res://tests/social_chat_ui_test.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/p1-beta-readiness-20261004/onboarding-ui/"
var view: SubViewport
var game
var actual_network: Node
var actual_social: Node
var session: Node
var service: Node
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	print("P1 UI %s: %s" % ["PASS" if value else "FAIL", message])

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func key(code: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		view.push_input(event, true)
		await process_frame
	await frames()

func pad(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		view.push_input(event, true)
		await process_frame
	await frames()

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	view.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		view.push_input(event, true)
		await process_frame
	await frames()

func cycle(panel: Control, controls: Array[Control], title: String) -> void:
	controls[0].grab_focus()
	await frames()
	var seen: Dictionary = {}
	for unused in controls.size():
		var focus_owner := view.gui_get_focus_owner()
		check(is_instance_valid(focus_owner) and panel.is_ancestor_of(focus_owner) and focus_owner in controls, title + " Tab stays among available controls")
		if is_instance_valid(focus_owner): seen[focus_owner.get_instance_id()] = true
		await key(KEY_TAB)
	check(seen.size() == controls.size() and view.gui_get_focus_owner() == controls[0], title + " Tab reaches every available action once")
	await key(KEY_TAB, true)
	check(view.gui_get_focus_owner() == controls.back(), title + " Shift-Tab reverses the focus cycle")
	for button: JoyButton in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		for control: Control in controls:
			control.grab_focus()
			await pad(button)
			var focus_owner := view.gui_get_focus_owner()
			check(is_instance_valid(focus_owner) and focus_owner in controls, title + " D-pad stays in the active panel")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	view = SubViewport.new()
	view.size = Vector2i(1440, 900)
	view.process_mode = Node.PROCESS_MODE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(6)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	actual_network = game.network
	actual_social = game.social
	game.social_bridge.set_process(false)
	session = Probes.SessionProbe.new()
	session.game = game
	service = Probes.SocialProbe.new()
	view.add_child(session)
	view.add_child(service)
	game.network = session
	game.social = service
	game.hud.chat_panel.bind_network(session)
	session.active = true
	session.state = "lobby"
	session.peer_connected = true
	session.relay_url = "wss://relay.example/ws"
	service.connection_state = "online"
	service.friends.assign([{"code":"ABCDEFGH2345","name":"Alex","status":"menu"}])
	game.hud._open_network()
	await frames()
	var lobby: Control = game.hud.network_panel
	var chat: Control = game.hud.chat_panel
	for locale: String in ["de", "en"]:
		LocaleText.set_locale(locale, false)
		await frames()
		lobby = game.hud.network_panel
		lobby.chat_button.grab_focus()
		chat.open()
		chat.input_field.text = "Test draft"
		await frames()
		await cycle(chat.editor, chat._focus_controls(), locale + " chat")
		var calls_before: int = session.calls.size()
		await click(lobby.leave_button.get_global_transform_with_canvas() * (lobby.leave_button.size * .5))
		check(chat.composing and game.hud.overlay == "network" and session.calls.size() == calls_before, locale + " an outside chat click cannot leave or start the lobby")
		await pad(JOY_BUTTON_B)
		check(not chat.composing and lobby.chat_button.has_focus() and chat.input_field.text == "Test draft", locale + " chat Back restores its actual opener and draft")
		game.hud._open_social()
		await frames()
		var social: Control = game.hud.social_panel
		social.bind_social(service)
		await frames()
		await cycle(social, social._focus_controls(), locale + " friends")
		social.show_service_options = true
		social._refresh()
		await frames()
		social.server_field.grab_focus()
		social._toggle_service_options()
		await frames()
		check(not social.server_field.visible and social.server_options_button.has_focus(), locale + " collapsing server options restores its visible opener focus")
		var contact: Button = social.contact_buttons["ABCDEFGH2345"]
		contact.grab_focus()
		social._confirm("remove", "ABCDEFGH2345")
		await frames()
		var confirmation: Control = social.confirmation
		var social_calls: int = service.calls.size()
		for button: JoyButton in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			await pad(button)
			check(view.gui_get_focus_owner() in [confirmation.cancel_button, confirmation.confirm_button], locale + " confirmation vertical D-pad cannot focus controls behind the modal")
		await key(KEY_TAB)
		check(confirmation.confirm_button.has_focus(), locale + " confirmation Tab reaches explicit acceptance")
		await pad(JOY_BUTTON_B)
		check(not confirmation.visible and contact.has_focus() and service.calls.size() == social_calls, locale + " safe Back cancels removal and restores the exact contact")
		game.hud._close_social()
		await frames()
	game.network = actual_network
	game.social = actual_social
	game.hud.chat_panel.bind_network(actual_network)
	check(not actual_network.active and not game.microphone.capturing, "UI fixtures open neither transport nor microphone")
	paused = false
	check(await Cleanup.free_scene(game, self), "UI fixture releases actual main scene and audio handles")
	view.queue_free()
	await frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + "ui-navigation.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Actual native Controls and routed keyboard/mouse/controller events in a 1440x900 SubViewport, German and English. Explicit in-memory friend/session probes; no sockets, profile writes or microphone. Covers dynamic enabled-action focus cycles, chat outside-click containment, opener restoration, collapse focus and destructive-action modal routing."}, "  "))
	quit(1 if failures else 0)
