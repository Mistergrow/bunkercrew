extends SceneTree
## Actual menu controls over actual scenery. The continue state is a fixture;
## it never writes or loads the player's campaign checkpoint.
const L := preload("res://scripts/locale_text.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const OUTPUT := "res://artifacts/expedition/menu/"
class SavedMenu extends "res://scripts/main_menu_panel.gd":
	func _has_campaign_save() -> bool: return true
var view: SubViewport
var game
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames(count: int = 5) -> void:
	for frame in count: await process_frame
func capture(name: String) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size() == view.size and picture.save_png(OUTPUT+name+".png") == OK, "Menu capture saved at actual target resolution")
func validate_menu(panel) -> void:
	check(panel.preview_clip.get_rect() == game.hud.screen_rect(), "Animated landscape covers the entire logical display")
	check(panel.mode_buttons[0].visible and L.text(panel.mode_buttons[0].text) == L.text("Neues Spiel"), "New game remains a distinct visible action with or without a saved campaign")
	if is_instance_valid(panel.continue_button):
		check(panel.continue_button.visible and panel.mode_buttons[0].position.y > panel.continue_button.get_rect().end.y, "New game is directly below the saved campaign action")
	var controls: Array = []
	controls.append_array(panel.mode_buttons)
	controls.append_array(panel.utility_buttons)
	controls.append(panel.friends_button)
	controls.append(panel.quit_button)
	controls.append_array([panel.story_button, panel.preview_previous, panel.preview_next])
	if is_instance_valid(panel.continue_button): controls.append(panel.continue_button)
	check(panel.quit_button.visible and panel.quit_button.tr(panel.quit_button.text) == L.text("Beenden"), "Quit remains a translated native action within the existing visual style")
	for index in controls.size():
		var button: Button = controls[index]
		check(Rect2(0,0,1440,900).encloses(button.get_rect()), "Native control fits small-screen safe area")
		for previous in range(index): check(not button.get_rect().intersects(controls[previous].get_rect()), "Every menu action retains its own hit area")
		var font_size := button.get_theme_font_size("font_size")
		var button_font := button.get_theme_font("font")
		check(button_font.get_string_size(L.text(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= button.size.x-24, "Translated menu text fits native control using its actual font")
		check(button_font.get_height(font_size) <= button.size.y, "Menu face and accents fit the authored button height")
		var style: StyleBoxFlat = button.get_theme_stylebox("normal")
		check(style.bg_color.a == 0 and style.border_width_left == 0 and style.border_width_right == 0, "Resting menu action stays free of a decorative box")
		var focus: StyleBoxFlat = button.get_theme_stylebox("focus")
		check(focus.border_width_left == 2 and focus.border_width_right == 0, "Keyboard/controller focus has an explicit narrow marker")
	for id in ["nora","levin","selma"]:
		check(CharacterCatalog.selection_title(id) == L.text("VERMISST"), "Main roster conceals undiscovered character names")
	for hint in panel.MODE_DETAILS + ["Wähle deine nächste Schicht.", "Story auch im Koop in der Schauplatzauswahl aktivieren.", "Zurück zu eurem letzten gesicherten Zwischenstand."]:
		check(UiArt.wrap_text(hint, 452, 15).size() <= 2, "Translated selection description clears the utility controls")
	for entry in CharacterCatalog.CHARACTERS:
		var label: String = CharacterCatalog.selection_title(entry.id)
		var label_size := 14 if CharacterCatalog.is_unlocked(entry.id) else 12
		check(UiArt.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x < 87, "Crew labels retain space between portraits")

func validate_new_game_flow() -> void:
	# A disposable real checkpoint proves setup/cancel does not overwrite an
	# existing campaign. Its path is inside artifacts; no user profile is read.
	var fixture := OUTPUT + "new-game-checkpoint-%d.json" % Time.get_ticks_usec()
	check(game.campaign.begin_new({"environment":"ash_foundry"}, ["ivo"], 1), "Prepared existing campaign is valid")
	game.campaign.banked_salvage = 17
	game.campaign.total_salvage_earned = 17
	game.campaign.save_path = fixture
	game.campaign.persistence_enabled = true
	var written: bool = game.campaign.save_checkpoint()
	check(written, "Disposable campaign checkpoint is written outside the player profile: " + game.campaign.last_error)
	if not written:
		game.campaign.persistence_enabled = false
		return
	var before: Dictionary = game.campaign.checkpoint()
	var bytes_before := FileAccess.get_file_as_bytes(fixture)
	game.hud.story_selected = true
	game.hud.main_menu_panel.mode_buttons[0].pressed.emit()
	await frames()
	check(game.hud.overlay == "scenario" and game.hud.selection_count == 1 and not game.hud.story_selected, "New game opens fresh solo setup independently of previous Story selection")
	check(not game.started and game.campaign.checkpoint() == before and FileAccess.get_file_as_bytes(fixture) == bytes_before, "Opening New game preserves active and saved campaign progress")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	check(game.hud.overlay == "characters" and not game.started, "New game requires a separate character and start confirmation")
	check(game.campaign.checkpoint() == before and FileAccess.get_file_as_bytes(fixture) == bytes_before, "Entering character selection still preserves the existing save")
	game.hud._close_character_selection()
	await frames()
	game.hud._close_scenario_selection()
	await frames()
	check(game.hud.overlay == "menu" and game.campaign.checkpoint() == before and FileAccess.get_file_as_bytes(fixture) == bytes_before, "Cancel returns to the menu with original campaign bytes unchanged")
	check(is_instance_valid(game.hud.main_menu_panel.continue_button) and game.hud.main_menu_panel.mode_buttons[0].visible, "Cancelled setup restores both Continue and New game from the real disposable save")
	game.campaign.persistence_enabled = false
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(fixture + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture + suffix))
func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args(): quit(2); return
	Roster.persistence_enabled = false
	Roster.unlocked.clear()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	for font in [UiArt.FONT, UiArt.MENU_FONT, UiArt.TITLE_FONT]:
		var complete := true
		for glyph in "ÄÖÜäöüß0123456789!?.,:;·–…‹›←→↓◇●✓":
			complete = complete and font.has_char(glyph.unicode_at(0))
		check(complete, "Each embedded face covers German characters, controls and punctuation without a system fallback")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	for resolution in ["qhd","desktop","small"]:
		view.size = Vector2i(2560,1440) if resolution == "qhd" else Vector2i(1440,900) if resolution == "desktop" else Vector2i(960,600)
		view.size_2d_override = Vector2i(1600,900) if resolution == "qhd" else Vector2i(1440,900)
		game.hud._layout_viewport()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			var panel = game.hud.main_menu_panel
			for index in panel.environments.size():
				if str(panel.environments[index].id) == "ash_foundry": panel.environment_index = index
			panel._show_environment()
			panel.mode_buttons[0].grab_focus()
			await frames()
			validate_menu(panel)
			await capture(resolution+"-"+locale+"-fresh")
			if resolution == "qhd":
				for index in panel.environments.size():
					if str(panel.environments[index].id) == "frozen_rail_yard": panel.environment_index = index
				panel._show_environment()
				await capture(resolution+"-"+locale+"-snow")
	# Build the real menu class with only save availability overridden.
	game.hud.buttons.clear()
	game.hud.main_menu_panel.queue_free()
	await frames()
	var saved := SavedMenu.new()
	saved.game = game
	saved.hud = game.hud
	game.hud.main_menu_panel = saved
	game.hud.canvas.add_child(saved)
	for resolution in ["qhd","desktop","small"]:
		view.size = Vector2i(2560,1440) if resolution == "qhd" else Vector2i(1440,900) if resolution == "desktop" else Vector2i(960,600)
		view.size_2d_override = Vector2i(1600,900) if resolution == "qhd" else Vector2i(1440,900)
		game.hud._layout_viewport()
		await frames()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			saved.continue_button.grab_focus()
			check(saved.continue_button.has_focus(), "Saved campaign is the initial keyboard action")
			validate_menu(saved)
			await capture(resolution+"-"+locale+"-continue")
	check(not game.started and not game.rounds.running and not game.network.active, "Menu preparation never starts a match or opens a network room")
	await validate_new_game_flow()
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("MAIN MENU REDESIGN: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
