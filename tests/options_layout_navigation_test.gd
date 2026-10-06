extends SceneTree
## Exercise the actual options controls with keyboard and controller events.
## No match transport, microphone capture, renderer restart or profile writes.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("OPTIONS NAVIGATION %s: %s" % ["PASS" if ok else "FAIL", label])

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func key(code: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
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

func focusable(panel: Node) -> Array[Control]:
	var result: Array[Control] = []
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		pending.append_array(current.get_children())
		if not current is Control or not current.is_visible_in_tree(): continue
		if current.focus_mode == Control.FOCUS_NONE: continue
		if current is BaseButton and current.disabled: continue
		if current is Slider and not current.editable: continue
		result.append(current)
	return result

func focus_is_visible(panel: Node) -> bool:
	var current := root.gui_get_focus_owner()
	return is_instance_valid(current) and current.is_visible_in_tree() and panel.is_ancestor_of(current)

func tab_cycle(options: Control, label: String) -> void:
	var expected := focusable(options)
	options.tab_buttons[options.tab].grab_focus()
	await frames()
	var start := root.gui_get_focus_owner()
	var reached: Dictionary = {}
	var visible := true
	for unused in expected.size():
		var current := root.gui_get_focus_owner()
		visible = visible and focus_is_visible(options)
		if is_instance_valid(current): reached[current.get_instance_id()] = true
		await key(KEY_TAB)
	var complete := reached.size() == expected.size()
	for control in expected: complete = complete and reached.has(control.get_instance_id())
	check(visible, label + " Tab never enters a hidden or unrelated control")
	check(complete and root.gui_get_focus_owner() == start, label + " Tab reaches each enabled control exactly once and wraps")
	await key(KEY_TAB, true)
	check(focus_is_visible(options) and root.gui_get_focus_owner() != start, label + " Shift-Tab reverses the visible focus cycle")
	await key(KEY_TAB)
	check(root.gui_get_focus_owner() == start, label + " Forward traversal reverses Shift-Tab without a focus trap")

func _categories(options: Control, locale: String) -> void:
	for index in 5:
		options.tab_buttons[index].grab_focus()
		await joy(JOY_BUTTON_A)
		check(options.tab == index and game.hud.options_tab == index, locale + " controller activates category %d" % index)
		check(options.pages[index].visible and options.pages.filter(func(page): return page.visible).size() == 1, locale + " category %d exposes one settings page" % index)
		await key(KEY_RIGHT)
		var current := root.gui_get_focus_owner()
		check(is_instance_valid(current) and options.pages[index].is_ancestor_of(current) and current.is_visible_in_tree(), locale + " Right enters category %d settings" % index)
		await joy(JOY_BUTTON_DPAD_UP)
		check(options.tab_buttons[index].has_focus(), locale + " controller Up from the first setting returns to its category")
		await key(KEY_RIGHT)
		var page_controls := focusable(options.pages[index])
		var reached: Dictionary = {}
		for unused in page_controls.size():
			current = root.gui_get_focus_owner()
			if is_instance_valid(current): reached[current.get_instance_id()] = true
			await joy(JOY_BUTTON_DPAD_DOWN)
		var complete := reached.size() == page_controls.size()
		for control in page_controls: complete = complete and reached.has(control.get_instance_id())
		check(complete and options.back_button.has_focus(), locale + " controller Down reaches every category %d setting and then Back" % index)
		options.tab_buttons[index].grab_focus()
		await key(KEY_RIGHT)
		current = root.gui_get_focus_owner()
		if is_instance_valid(current) and not current is HSlider:
			await key(KEY_LEFT)
			check(options.tab_buttons[index].has_focus() and options.tab == index, locale + " Left returns to category %d without changing settings" % index)
		await tab_cycle(options, locale + " category %d" % index)
	options.tab_buttons[0].grab_focus()
	await frames()
	for index in range(1, 5):
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(options.tab_buttons[index].has_focus() and options.tab == index, locale + " controller Down focuses and selects category %d" % index)
	await joy(JOY_BUTTON_DPAD_UP)
	check(options.tab_buttons[3].has_focus() and options.tab == 3, locale + " controller Up selects the previous category")
	await joy(JOY_BUTTON_DPAD_DOWN)
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(options.support_button.has_focus(), locale + " controller Down reaches Error Report after the last category")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(options.release_button.has_focus(), locale + " controller Down reaches Changes after Error Report")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(options.microphone_button.has_focus(), locale + " controller Down reaches Microphone after Changes")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(options.back_button.has_focus(), locale + " controller Down reaches Back after Microphone")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(options.tab_buttons[0].has_focus(), locale + " controller wraps Back to the first category")
	await joy(JOY_BUTTON_DPAD_UP)
	check(options.back_button.has_focus(), locale + " controller Up reaches Back from the first category")

func _settings(options: Control) -> void:
	options.select_tab(1)
	await frames()
	options.zoom_slider.grab_focus()
	var initial_zoom: float = options.zoom_slider.value
	await key(KEY_RIGHT)
	check(options.zoom_slider.has_focus() and options.zoom_slider.value > initial_zoom, "Right adjusts camera zoom without leaving its slider")
	await key(KEY_LEFT)
	check(options.zoom_slider.has_focus() and is_equal_approx(options.zoom_slider.value, initial_zoom), "Left reverses camera zoom without entering category navigation")
	game.set_camera_mode("overview")
	game.set_camera_zoom(.85)
	await frames()
	check(options.camera_mode.selected == 1 and is_equal_approx(options.zoom_slider.value, .85), "Camera controls synchronize changes made by the real backend")
	options.select_tab(0)
	await frames()
	var reduced: bool = game.weather.reduced_effects
	options.effects.grab_focus()
	await key(KEY_SPACE)
	check(game.weather.reduced_effects != reduced and options.effects.button_pressed == game.weather.reduced_effects, "Space toggles the focused weather control and backend together")
	await key(KEY_SPACE)
	check(game.weather.reduced_effects == reduced, "Repeated Space restores the weather setting")
	options.select_tab(2)
	await frames()
	var music_slider: HSlider = game.hud.sliders[0]
	music_slider.grab_focus()
	var music: float = game.audio.music_volume
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(music_slider.has_focus() and game.audio.music_volume > music, "Controller Right changes music volume through the focused slider")
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(music_slider.has_focus() and is_equal_approx(game.audio.music_volume, music), "Controller Left restores music volume without changing category")
	options.tab_buttons[2].grab_focus()
	game.audio.set_music_volume(.41)
	game.audio.set_sfx_volume(.62)
	game.audio.set_voice_volume(.53)
	await frames()
	check(is_equal_approx(game.hud.sliders[0].value, .41) and is_equal_approx(game.hud.sliders[1].value, .62) and is_equal_approx(game.hud.sliders[2].value, .53), "All three audio sliders synchronize independent backend values")
	options.select_tab(3)
	var saved_intensity: float = game.audio.dance_intensity
	game.audio.set_dance_configuration(.75, game.audio.dance_profiles)
	await frames()
	options.dance_gain_slider.grab_focus()
	var intensity: float = game.audio.dance_intensity
	await key(KEY_RIGHT)
	check(options.dance_gain_slider.has_focus() and game.audio.dance_intensity > intensity, "Rhythm intensity adjusts from the native slider")
	await key(KEY_LEFT)
	check(is_equal_approx(game.audio.dance_intensity, intensity), "Rhythm slider restores the original saved preference")
	game.audio.set_dance_configuration(saved_intensity, game.audio.dance_profiles)
	game.audio.set_rhythm_motion_reduced(not game.audio.rhythm_motion_reduced)
	await frames()
	check(options.rhythm_reduced_check.button_pressed == game.audio.rhythm_motion_reduced, "Rhythm toggle synchronizes backend changes")

func _returns(options: Control) -> void:
	options.select_tab(4)
	L.set_locale("de", false)
	await frames()
	game.hud.language_buttons[1].grab_focus()
	await key(KEY_ENTER)
	await frames()
	check(L.current_locale() == "en" and game.hud.options_panel == options and options.tab == 4, "Native language selection preserves the options instance and category")
	check(focus_is_visible(options) and game.hud.language_buttons[1].has_focus(), "Locale refresh retains the language control focus")
	await key(KEY_ENTER)
	check(game.hud.language_buttons[1].button_pressed and not game.hud.language_buttons[0].button_pressed and L.current_locale() == "en", "Accepting the current language keeps exactly that language selected")
	options.select_tab(3)
	await frames()
	for kind: String in ["calibration", "music_lab"]:
		var opener: Button = options.calibration_button if kind == "calibration" else options.music_lab_button
		opener.grab_focus()
		if kind == "calibration": await key(KEY_ENTER)
		else: options._open_music_lab(false)
		await frames()
		check(options.has_modal_subpanel(), "Opening " + kind + " retains the options page behind the modal")
		await key(KEY_F7)
		check(game.hud.overlay == "audio" and options.has_modal_subpanel(), "Friends shortcut preserves unfinished " + kind)
		await joy(JOY_BUTTON_B)
		check(not options.has_modal_subpanel() and game.hud.overlay == "audio" and options.tab == 3, "Controller Back closes only " + kind + " and restores Rhythm")
		check(focus_is_visible(options) and opener.has_focus(), "Closing " + kind + " restores its opener focus")
		check(not game.audio.calibration_active, "Closing " + kind + " restores normal music routing")
	options.microphone_button.grab_focus()
	await key(KEY_ENTER)
	check(game.hud.overlay == "microphone" and not game.microphone.capturing, "Microphone options open without acquiring the device")
	await joy(JOY_BUTTON_B)
	await frames()
	options = game.hud.options_panel
	check(game.hud.overlay == "audio" and options.tab == 3 and focus_is_visible(options), "Microphone Back restores the selected settings category and visible focus")
	await key(KEY_F4)
	check(game.hud.overlay == "menu" and paused, "F4 closes main-menu settings to their original route")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	L.set_locale("de", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	await key(KEY_F4)
	var options: Control = game.hud.options_panel
	check(is_instance_valid(options) and options.tab_buttons.size() == 5, "F4 opens the actual five-category settings panel")
	check(paused and focus_is_visible(options), "Options starts paused with a visible native focus target")
	for locale: String in ["de", "en"]:
		L.set_locale(locale, false)
		await frames()
		await _categories(options, locale)
	await _settings(options)
	await _returns(options)
	game.start_scenario(2, {"environment":"ash_foundry", "position":"center", "build_type":"bastion"})
	game.rounds.set_process(false)
	await frames()
	await key(KEY_ESCAPE)
	game.hud.pause_buttons.options.grab_focus()
	await key(KEY_ENTER)
	check(game.hud.overlay == "audio" and paused, "Paused-match Options enters settings without resuming the world")
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay == "pause" and game.hud.pause_buttons.options.has_focus() and paused, "Controller Back returns to the original pause action")
	check(not game.network.active and not game.microphone.capturing, "Settings navigation never starts a connection or microphone capture")
	for path: String in ["user://audio.cfg", "user://language.cfg", "user://camera.cfg", "user://display.cfg", "user://violence.cfg"]:
		check(not FileAccess.file_exists(path), "No-profile-save leaves " + path + " untouched")
	await Cleanup.free_scene(game, self)
	print("OPTIONS LAYOUT NAVIGATION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
