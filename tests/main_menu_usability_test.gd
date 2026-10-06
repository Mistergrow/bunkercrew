extends SceneTree
## Real menus, native key/controller events and a disposable checkpoint. The
## tests never write the player's profile or begin a match/network connection.
const L := preload("res://scripts/locale_text.gd")
const OUTPUT := "res://artifacts/ui-hardening/menu/"
var game
var checks := 0
var failures := 0
var fixture := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for frame in count: await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "Rendered menu capture is saved")

func _navigation_routes(saved: bool) -> void:
	var panel = game.hud.main_menu_panel
	var first: Button = panel.continue_button if saved else panel.mode_buttons[0]
	first.grab_focus()
	await frames()
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(panel.preview_previous.has_focus(), "Right reaches preview from the action column with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_UP)
	check(panel.quit_button.has_focus(), "Up from preview reaches Quit with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(panel.preview_previous.has_focus(), "Right from Quit reaches the first preview arrow with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(panel.preview_next.has_focus(), "Right retains the second preview arrow with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.quit_button.has_focus(), "Down from preview returns to Quit with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.preview_next.has_focus(), "Left from Quit reaches the second preview arrow with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.preview_previous.has_focus(), "Left moves between the two preview arrows with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.friends_button.has_focus(), "Left from preview reaches the nearest friends utility with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_UP)
	check(panel.story_button.has_focus(), "Up from utilities reaches the final game action with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.utility_buttons[0].has_focus(), "Down from story reaches the utility row with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(panel.quit_button.has_focus(), "Down from utilities reaches Quit with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_UP)
	check(panel.utility_buttons[0].has_focus(), "Up from Quit reaches Help with save=%s" % saved)
	await joy(JOY_BUTTON_DPAD_DOWN)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(first.has_focus(), "Down from Quit wraps to the first enabled action with save=%s" % saved)
	var controls: int = panel._ordered_buttons().size()
	check(controls == (13 if saved else 12), "Clean focus traversal contains the visible game/utility/Quit/changelog controls with save=%s" % saved)
	var seen: Dictionary = {}
	for index in controls:
		var focused := root.gui_get_focus_owner()
		if focused != null: seen[focused.get_instance_id()] = true
		await key(KEY_TAB)
	check(seen.size() == controls and first.has_focus(), "Tab reaches each enabled control once with save=%s" % saved)
	check(not game.started and not game.network.active and not game.rounds.running, "Navigation never activates gameplay or network")

func _return_navigation() -> void:
	var panel = game.hud.main_menu_panel
	panel.browse_environment(3)
	await frames()
	var expected: String = panel.preview.environment_id
	for index in 3:
		panel = game.hud.main_menu_panel
		panel.utility_buttons[index].grab_focus()
		await key(KEY_ENTER)
		check(game.hud.overlay == ["help", "audio", "personal"][index], "Enter opens the selected utility")
		await joy(JOY_BUTTON_B)
		panel = game.hud.main_menu_panel
		check(game.hud.overlay == "menu" and panel.utility_buttons[index].has_focus(), "Returning from a utility restores its keyboard/controller focus")
		check(panel.preview.environment_id == expected, "Returning from a utility keeps the same preview")
	panel.mode_buttons[1].grab_focus()
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	panel = game.hud.main_menu_panel
	check(panel.mode_buttons[1].has_focus() and panel.preview.environment_id == expected, "Cancelled local setup restores its action and preview")
	panel.utility_buttons[1].grab_focus()
	await key(KEY_F4)
	check(game.hud.overlay == "audio" and is_instance_valid(game.hud.options_panel), "Language preferences remain available through F4")
	game.hud.options_panel.tab_buttons[4].grab_focus()
	await key(KEY_ENTER)
	check(game.hud.options_panel.tab == 4 and game.hud.language_buttons.size() == 2, "The actual options language page retains both choices")
	game.hud.language_buttons[1].grab_focus()
	await key(KEY_ENTER)
	check(L.current_locale() == "en" and game.hud.language_buttons[1].has_focus(), "Switching language through options retains native control focus")
	await key(KEY_ESCAPE)
	panel = game.hud.main_menu_panel
	check(game.hud.overlay == "menu" and panel.utility_buttons[1].has_focus() and panel.preview.environment_id == expected, "Language options return to the original menu focus and preview")
	var state: Dictionary = panel.navigation_state()
	panel.restore_navigation({"environment": "not_a_site", "focus": "not_a_button", "elapsed": INF})
	await frames()
	check(panel.preview.environment_id == state.environment and is_finite(panel.elapsed), "Stale navigation metadata cannot select an unknown site or invalid clock")

func _hint_layout() -> void:
	var panel = game.hud.main_menu_panel
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		for button in panel._ordered_buttons():
			button.grab_focus()
			await frames(1)
			var hint: String = panel.selection_hint()
			check(not hint.is_empty() and UiArt.wrap_text(hint, 452, 15).size() <= 2, "Each translated action hint fits the existing two-line slot")
			check(L.text(hint) != hint if locale == "en" and "%s" not in hint and not hint.begins_with("Continue") else true, "English action hints are translated")
		panel.mode_buttons[0].grab_focus()
		await frames()
		await capture("after-" + locale + "-fresh")
	L.set_locale("de", false)

func _stale_save() -> void:
	fixture = OUTPUT + "checkpoint-%d.json" % Time.get_ticks_usec()
	game.campaign.save_path = fixture
	game.campaign.persistence_enabled = true
	check(game.campaign.begin_new({"environment": "frozen_rail_yard"}, ["ivo"], 1), "Disposable campaign checkpoint is valid")
	check(game.campaign.save_checkpoint(), "Disposable campaign checkpoint can be written")
	game.hud._rebuild_buttons()
	await frames()
	var panel = game.hud.main_menu_panel
	check(is_instance_valid(panel.continue_button), "Valid saved campaign exposes Continue")
	await _navigation_routes(true)
	panel.continue_button.grab_focus()
	await frames()
	var resume_hint: String = panel.selection_hint()
	panel.browse_environment(4)
	await frames()
	check(panel.selection_hint() == resume_hint, "Saved location hint is independent of the browsed preview")
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		panel.continue_button.grab_focus()
		await frames()
		check(UiArt.wrap_text(panel.selection_hint(), 452, 15).size() <= 2, "Saved location hint fits its existing slot")
		await capture("after-" + locale + "-continue")
	L.set_locale("de", false)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture + suffix))
	panel.continue_button.grab_focus()
	await key(KEY_ENTER)
	check(game.hud.overlay == "menu" and not game.started and panel.continue_button.disabled, "Disappeared checkpoint leaves Continue disabled and the menu usable")
	check(panel.mode_buttons[0].has_focus() and not panel._resume_error.is_empty(), "Failed Continue shows an explanation and focuses New game")
	check(UiArt.wrap_text(panel.selection_hint(), 452, 15).size() <= 2, "Continue failure message stays inside the original hint area")
	await capture("after-de-missing-save")
	await key(KEY_TAB)
	check(panel.mode_buttons[1].has_focus(), "Disabled Continue is skipped by native focus traversal")
	await key(KEY_ENTER)
	check(game.hud.overlay == "scenario", "A failed Continue does not block another menu action")
	game.campaign.persistence_enabled = false

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or ("--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() == "headless"):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(8)
	await _navigation_routes(false)
	await _return_navigation()
	await _hint_layout()
	await _stale_save()
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "Main menu resources release cleanly")
	print("MAIN MENU USABILITY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
