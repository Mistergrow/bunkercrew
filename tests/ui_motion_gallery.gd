extends SceneTree
## Interface motion: contract checks (always) and slowed frame sequences of the
## real screens (`--capture`, needs a display). The fixture is the disposable
## main scene used by the UI audit; nothing is saved and no session is opened.
const L := preload("res://scripts/locale_text.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
const OUTPUT := "res://artifacts/visual-pass-ui/motion/"
const SLOW := 0.125
var game
var view: SubViewport
var checks := 0
var failures := 0
var capturing := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func contract() -> void:
	UiMotion.force(null)
	check(not UiMotion.enabled(), "Script-driven runs default to the settled state")
	check(is_equal_approx(UiMotion.progress(UiMotion.now(), 0.2), 1.0), "Disabled motion reports completed progress")
	check(is_equal_approx(UiMotion.approach(0.0, 100.0, 0.016), 100.0), "Disabled motion snaps to the target")
	check(is_equal_approx(UiMotion.pulse(), 0.0), "Disabled motion has no pulse")
	UiMotion.force(true)
	UiMotion.set_manual_clock(10.0)
	check(is_equal_approx(UiMotion.progress(10.0, 0.2), 0.0), "Progress starts at zero")
	UiMotion.set_manual_clock(10.1)
	var half := UiMotion.progress(10.0, 0.2)
	check(half > 0.5 and half < 1.0, "Ease-out is past the midpoint at half time")
	check(is_equal_approx(UiMotion.progress(10.0, 0.2, 0.1), 0.0), "A delayed stage has not begun")
	UiMotion.set_manual_clock(10.25)
	check(is_equal_approx(UiMotion.progress(10.0, 0.2), 1.0) and not UiMotion.running(10.0, 0.2), "Progress ends at one and stops")
	var step := UiMotion.approach(0.0, 100.0, 1.0 / 60.0)
	check(step > 0.0 and step < 100.0, "Approach travels part of the way per frame")
	var value := 0.0
	for unused in 30: value = UiMotion.approach(value, 100.0, 1.0 / 60.0)
	check(is_equal_approx(value, 100.0), "Approach settles exactly within half a second")
	check(UiMotion.QUICK >= 0.12 and UiMotion.SLOW <= 0.22 and UiMotion.BASE >= UiMotion.QUICK and UiMotion.BASE <= UiMotion.SLOW, "Transitions stay within 120-220 ms")
	check(1.0 / UiMotion.PULSE_PERIOD < 1.0, "Warning pulse stays below 1 Hz, far from the 3 Hz flash limit")
	UiMotion.reduced = true
	UiMotion.force(null)
	check(not UiMotion.enabled(), "Reduced effects switch interface motion off")
	UiMotion.reduced = false
	UiMotion.set_manual_clock(-1.0)
	# Device prompts follow the last deliberate input.
	var key := InputEventKey.new()
	key.pressed = true
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	InputLabels.pad_active = false
	check(InputLabels.note_event(pad) and InputLabels.pad_active and InputLabels.confirm_glyphs() == ["A"], "Controller input switches the prompts to controller glyphs")
	check(not InputLabels.note_event(pad), "Repeated input from one device reports no change")
	var drift := InputEventJoypadMotion.new()
	drift.axis_value = 0.2
	InputLabels.pad_active = false
	check(not InputLabels.note_event(drift), "Stick drift does not switch the prompts")
	InputLabels.pad_active = true
	check(InputLabels.note_event(key) and not InputLabels.pad_active and InputLabels.confirm_glyphs() == ["Enter"], "Keyboard input switches the prompts back")
	# Shared screen: each player's card names only the device that player used;
	# nothing is learned outside a shared session.
	var second := InputEventJoypadButton.new()
	second.pressed = true
	for action: StringName in InputMap.get_actions():
		if str(action) == "p2_interact":
			for bound: InputEvent in InputMap.action_get_events(action):
				if bound is InputEventJoypadButton:
					second.button_index = bound.button_index
					second.device = bound.device
	InputLabels.note_event(second, false)
	check(InputLabels._player_pad.is_empty(), "Solo input never assigns a device to a second player")
	InputLabels.note_event(second, true)
	check(not InputMap.has_action("p2_interact") or InputLabels._player_pad.get("p2") == true, "A shared-screen controller press marks that player's device")
	InputLabels.note_event(key, false)
	check(InputLabels._player_pad.is_empty(), "Leaving the shared session forgets per-player devices")
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		for pad_mode in [false, true]:
			InputLabels.pad_active = pad_mode
			check(UiArt.hints(null, Vector2.ZERO, InputLabels.navigation_hints(true), pad_mode, UiArt.TEXT_BODY, UiArt.MUTED, true) <= 386.0, "Hint row fits the menu column: %s pad=%s" % [locale, pad_mode])
	InputLabels.pad_active = false
	L.set_locale("de", false)
	check(UiArt.TEXT_MICRO >= 12, "Smallest shared text size is 12 design pixels")
	check(UiArt.theme().get_stylebox("normal", "Button") == UiArt.skin("normal") and UiArt.theme().default_font == UiArt.FONT, "One Theme carries the shared button surfaces and body face")
	check(UiArt.skin("normal").bg_color != UiArt.skin("disabled").bg_color and UiArt.skin("normal").border_width_bottom > UiArt.skin("disabled").border_width_bottom, "Enabled and disabled buttons differ in surface and edge")

func shot(sequence: String, index: int) -> void:
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.save_png("%s%s-%02d.png" % [OUTPUT, sequence, index]) == OK, "Frame saved: " + sequence)

## Photograph `count` frames spread over `seconds` of real motion time.
func sequence(id: String, seconds: float, count: int = 10) -> void:
	var started := UiMotion.now()
	for index in count:
		var due := started + seconds * float(index) / float(count - 1)
		while UiMotion.now() < due: await process_frame
		await shot(id, index)

func fixture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.hud._layout_viewport()

func captures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size = Vector2i(1440, 900)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	L.set_locale("de", false)
	await fixture()
	var hud = game.hud
	# Settled stills of every menu panorama for the contrast measurement.
	UiMotion.force(false)
	for index in hud.main_menu_panel.environments.size():
		hud.main_menu_panel.browse_environment(1)
		await frames(4)
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png("%smenu-site-%02d.png" % [OUTPUT, index])
	InputLabels.pad_active = true
	hud._redraw_locale_tree(hud.canvas)
	await frames(3)
	await shot("menu-controller-prompts", 0)
	InputLabels.pad_active = false
	UiMotion.force(true)
	UiMotion.time_scale = SLOW
	# Focus glide between two main-menu actions.
	hud.main_menu_panel.mode_buttons[0].grab_focus()
	await frames(4)
	hud.main_menu_panel.story_button.grab_focus()
	await sequence("focus-glide", UiMotion.QUICK, 8)
	# Options: screen fade-in, then a tab change.
	hud.audio_return_overlay = "menu"
	hud.overlay = "audio"
	hud._apply_overlay_pause()
	await frames(2)
	await sequence("options-open", UiMotion.BASE, 8)
	hud.options_panel.select_tab(2)
	await sequence("options-tab", UiMotion.BASE, 8)
	game.start_scenario(2, {"environment": "ash_foundry", "position": "left", "build_type": "bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.camera.position = Vector2(670, 70)
	game.camera.zoom = Vector2.ONE
	for actor in game.players: actor.set_physics_process(false)
	hud.overlay = ""
	hud._apply_overlay_pause()
	await frames(6)
	# Toast enters, then leaves.
	game.notice = L.text("Welle abgewehrt · Schrott und Technikpunkte bergen · Schäden reparieren")
	game.notice_time = 5.0
	await frames(1)
	await sequence("toast-enter", UiMotion.BASE, 8)
	game.notice_time = UiMotion.SLOW
	game.set_process(false)
	var leaving := UiMotion.now()
	for index in 8:
		game.notice_time = UiMotion.SLOW * (1.0 - float(index) / 7.0) + 0.0001
		await frames(1)
		await shot("toast-leave", index)
	game.notice_time = 0.0
	check(UiMotion.now() >= leaving, "Toast leave sequence captured")
	# Wave start announcement in the status strip.
	game.rounds.phase = "build"
	await frames(3)
	game.rounds.phase = "attack"
	await frames(1)
	await sequence("wave-start", 1.4, 12)
	game.rounds.phase = "salvage"
	await frames(1)
	await sequence("wave-clear", 1.4, 12)
	# Damage trail and the slow low-health pulse.
	var worker = game.players[0]
	worker.hp = worker.max_hp
	await frames(4)
	worker.hp = 28.0
	game.core.hp = game.core.max_hp * 0.3
	await sequence("damage-trail", 1.6, 12)
	await sequence("low-health-pulse", UiMotion.PULSE_PERIOD, 10)
	worker.hp = worker.max_hp
	game.core.hp = game.core.max_hp
	# Pause opens with staggered actions; the marker settles on the next row.
	hud.overlay = "pause"
	hud._apply_overlay_pause()
	await frames(2)
	await sequence("pause-open", UiMotion.BASE + UiMotion.STAGE * 4.0, 10)
	hud.pause_buttons.research.grab_focus()
	await sequence("pause-marker", UiMotion.QUICK * 1.5, 8)
	# Button press sweep.
	hud.pause_buttons.help.grab_focus()
	await frames(3)
	UiArt._button_pressed(hud.pause_buttons.help)
	await sequence("button-press", UiMotion.SLOW, 8)
	# Technik: point total counts up, category marker travels.
	hud.overlay = "upgrades"
	hud._apply_overlay_pause()
	await frames(2)
	await sequence("technik-open", UiMotion.BASE, 6)
	game.upgrades.points += 12
	hud.upgrade_panel.select_category(2)
	await sequence("technik-count", UiMotion.COUNT, 10)
	# Convoy chart: the selection ring travels between sites.
	var state: CampaignState = game.campaign
	if state.active and not state.complete_mission(state.mission_id, 20, game.players, game.upgrades, {"steel": 12, "ammo": 6, "concrete": 18, "scrap": 8}).is_empty():
		state.select_destination("harbor")
		hud.overlay = "expedition"
		hud._apply_overlay_pause()
		await frames(4)
		hud.expedition_panel._choose_route("quarry")
		await sequence("convoy-ring", UiMotion.BASE * 1.5, 8)
	# Result sequences.
	for result in ["victory", "defeat"]:
		game.rounds.phase = result
		game.elapsed = 2183.0
		game.core.hp = game.core.max_hp * (0.0 if result == "defeat" else 0.72)
		hud.overlay = result
		hud._apply_overlay_pause()
		await frames(2)
		await sequence(result + "-sequence", UiMotion.STAGE * 5.0 + UiMotion.COUNT + 0.1, 12)
	# Input completes the sequence at once and still reaches the focused button.
	hud.last_overlay = "!"
	await frames(2)
	var click := InputEventKey.new()
	click.keycode = KEY_F24
	click.pressed = true
	hud._input(click)
	check(not UiMotion.running(hud._overlay_started, UiMotion.COUNT, UiMotion.STAGE * 8.0), "Any input completes the result sequence")
	UiMotion.time_scale = 1.0
	UiMotion.force(null)
	await Cleanup.free_scene(game, self)
	view.queue_free()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	Roster.persistence_enabled = false
	contract()
	capturing = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capturing: await captures()
	print("UI MOTION: %d/%d checks passed%s" % [checks - failures, checks, "; sequences captured" if capturing else ""])
	quit(1 if failures else 0)
