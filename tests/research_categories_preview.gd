extends SceneTree
## Prepared wave16 workshop state; real controls, group context and explicit
## transactions at native QHD, 1440 and 960, in both supported languages.
const L = preload("res://scripts/locale_text.gd")
const OUTPUT := "res://artifacts/research-refresh/after/"
var game
var view: SubViewport
var checks := 0
var failures := 0
var capture_enabled := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames() -> void:
	for index in 3: await process_frame

func check_text_fit(panel) -> void:
	for button: Button in panel.tab_buttons + [panel.purchase_button, panel.prerequisite_button, panel.close_button]:
		if not button.visible: continue
		var face := button.get_theme_font("font")
		var font_size := button.get_theme_font_size("font_size")
		var style := button.get_theme_stylebox("normal")
		var content_width: float = button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT)
		check(face.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= content_width, "Translated research action fits its actual native control")
	var entry: Dictionary = game.upgrades.node_data(panel.selected_id)
	check(UiArt.wrap_text(panel._research_title(str(entry.title)), panel.DETAIL_RECT.size.x-76, 24, UiArt.MENU_FONT).size() <= 2, "Research title clears the actual inspector scope label")
	var status: String = panel._selection_status(entry, game.upgrades.requirement(panel.selected_id))
	check(UiArt.wrap_text(status, panel.DETAIL_RECT.size.x, 15).size() <= 2, "Research requirements clear the purchase button")
	var price := L.format("Kosten: %d Technikpunkte", entry.cost)
	check(UiArt.FONT.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x <= panel.DETAIL_RECT.size.x, "Research price fits the details column")

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args(): quit(2); return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	game.start_scenario(1, {"environment":"sector07", "build_type":"bastion", "position":"left"})
	game.rounds.wave = 16
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	game.upgrades.points = 19
	game.upgrades.owned = {"bunker_workshop":true, "core_resilience":true, "medic_logistics":true, "weapon_handling":true, "boots":true}
	game.hud.overlay = "upgrades"
	game.hud._apply_overlay_pause()
	await frames()
	var panel = game.hud.upgrade_panel
	check(panel._button_for("bunker_workshop").has_focus(), "Research opens with a usable keyboard and gamepad focus")
	for resolution in ["qhd", "desktop", "small"]:
		view.size = Vector2i(2560,1440) if resolution == "qhd" else Vector2i(1440,900) if resolution == "desktop" else Vector2i(960,600)
		view.size_2d_override = Vector2i(1600,900) if resolution == "qhd" else Vector2i(1440,900)
		game.hud._layout_viewport()
		for locale in ["de", "en"]:
			L.set_locale(locale, false)
			for category in 4:
				panel.select_category(category)
				panel._select(["precision_lines", "weapon_capacitor", "craftsmanship", "convoy_stabilizer"][category])
				await frames()
				check_text_fit(panel)
				check(panel.selected_category == category and panel.tab_buttons[category].button_pressed, "%s %s category%d is active" % [resolution, locale, category])
				var visible := 0
				for index in panel.node_buttons.size():
					var entry: Dictionary = UpgradeSystem.NODES[index]
					var button: Button = panel.node_buttons[index]
					check(button.visible == (int(entry.branch) == category), "Only current category's controls accept interaction")
					if not button.visible: continue
					visible += 1
					var title_width: float = panel._node_title_width(str(entry.id))
					var title_size: int = panel._node_title_size(str(entry.title))
					check(panel.node_title_lines(entry).size() <= 2 and title_size >= 16, "Translated research and software titles stay readable inside their actual status-column budget")
					for line: String in panel.node_title_lines(entry):
						check(UiArt.FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x <= title_width, "Research title fits its actual row or software stage")
					var requirement_lines: Array = UiArt.wrap_text(panel._row_requirement(entry),button.size.x-panel.ROW_TITLE_INSET-6,14)
					check(requirement_lines.size() <= 2,"Actual predecessor and wave requirement fit the authored two-line subtitle")
					for line: String in requirement_lines:
						check(UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x <= button.size.x-panel.ROW_TITLE_INSET-6,"Wrapped research requirements fit their actual drawing budget")
					var description: Array = panel._detail_lines(str(entry.detail))
					check(354+(description.size()-1)*23+UiArt.FONT.get_descent(panel.BODY_SIZE)<557-UiArt.FONT.get_ascent(12),"Actual translated description glyphs clear the prerequisite heading")
					check(Rect2(Vector2.ZERO, panel.tree_content.size).encloses(button.get_rect()) and button.size.y == panel.CARD_HEIGHT and button.size.x == panel._card_width,"Research rows and software stages retain their actual authored bounds")
					check(button.size.y >= 69+19*(requirement_lines.size()-1)+6,"Two-line research subtitle clears the row divider")
					for other in range(index):
						if panel.node_buttons[other].visible:
							check(not button.get_rect().intersects(panel.node_buttons[other].get_rect()), "Research controls do not overlap")
					if not str(entry.parent).is_empty():
						var parent_button: Button = panel._button_for(str(entry.parent))
						check(button.focus_neighbor_left == button.get_path_to(panel.tab_buttons[category]) and is_instance_valid(parent_button),"Left focus reaches the actual category; explicit prerequisite retains the genuine dependency")
					check(button.tooltip_text.is_empty(), "Cards do not spawn duplicate text over the diagram")
				check(is_equal_approx(panel.tree_content.size.y, panel.tree_content.custom_minimum_size.y), "Category changes shrink the actual content instead of keeping an old oversized branch")
				check(panel.tree_scroll.scroll_horizontal == 0 and panel.tree_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "All categories are reachable without horizontal scrolling")
				var unique: Dictionary = {}
				for group: Dictionary in panel._groups:
					check(UiArt.FONT.get_string_size(L.text(str(group.title)), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x < panel._card_width-90, "Translated group heading leaves space for progress")
					for id: String in group.ids:
						check(not unique.has(id), "Research occurs in exactly one functional group")
						unique[id] = true
				var points_before: int = game.upgrades.points
				for entry: Dictionary in panel._visible_entries:
					panel._select(str(entry.id))
					await frames()
					var control: Button = panel._button_for(str(entry.id))
					check(control.has_focus() and panel.tree_scroll.get_global_rect().encloses(control.get_global_rect()), "Every keyboard/gamepad selection scrolls its entire real control into view")
					check(game.upgrades.points == points_before, "Focusing each real research control never spends points")
				if category == 2:
					check(panel.tree_scroll.get_v_scroll_bar().visible,"Long crew software page exposes its actual native vertical scrollbar")
					var previous_top := -1.0
					for id: String in panel._stage_ids:
						panel._select(id)
						await frames()
						var software: Button = panel._button_for(id)
						check(software.position.y>previous_top and panel.tree_scroll.get_global_rect().encloses(software.get_global_rect()),"Every vertical SAN stage is separately readable and fully revealed by its actual selection")
						previous_top=software.position.y
					check(panel.tree_scroll.scroll_vertical>0,"Reaching the fifth SAN stage scrolls its actual native list")
				panel._select(["precision_lines", "weapon_capacitor", "bunker_dance_5", "convoy_stabilizer"][category])
				await frames()
				check(visible == game.upgrades.nodes_for_category(category).size(), "No research is lost when filtering")
				check(panel.tree_scroll.get_rect().end.y <= panel.purchase_button.get_rect().end.y + 3, "Research list stays above footer")
				if capture_enabled:
					await RenderingServer.frame_post_draw
					var picture := view.get_texture().get_image()
					check(picture.get_size() == view.size and picture.save_png(OUTPUT + "%s-%s-%d.png" % [resolution, locale, category]) == OK, "Native category capture saved")
	view.size = Vector2i(1440,900)
	view.size_2d_override = Vector2i(1440,900)
	game.hud._layout_viewport()
	panel.select_category(0)
	panel._button_for("bunker_workshop").grab_focus()
	await frames()
	var focus_key := InputEventKey.new()
	focus_key.keycode = KEY_RIGHT
	focus_key.pressed = true
	view.push_input(focus_key, true)
	await frames()
	check(panel.selected_id == "bunker_workshop" and panel.close_button.has_focus(),"Real keyboard right moves to the usable inspector/footer when the selected root research is owned")
	focus_key.pressed = false
	view.push_input(focus_key, true)
	focus_key = InputEventKey.new()
	focus_key.keycode = KEY_LEFT
	focus_key.pressed = true
	view.push_input(focus_key, true)
	await frames()
	check(panel.selected_id == "bunker_workshop", "Real keyboard left keeps the inspected research while navigating columns")
	focus_key.pressed = false
	view.push_input(focus_key, true)
	var saved_points: int = game.upgrades.points
	panel._button_for("bunker_workshop").grab_focus()
	await frames()
	focus_key = InputEventKey.new()
	focus_key.keycode = KEY_DOWN
	focus_key.pressed = true
	view.push_input(focus_key, true)
	await frames()
	check(panel.selected_id == "medic_logistics", "Real keyboard down selects the next functional row")
	focus_key.pressed = false
	view.push_input(focus_key, true)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	view.push_input(pad, true)
	await frames()
	check(panel.selected_id == "logistics_drive", "Real controller down selects the following research row")
	pad.pressed = false
	view.push_input(pad, true)
	focus_key = InputEventKey.new()
	focus_key.keycode = KEY_ENTER
	focus_key.pressed = true
	view.push_input(focus_key, true)
	focus_key.pressed = false
	view.push_input(focus_key, true)
	await frames()
	check(game.upgrades.points == saved_points and not game.upgrades.has_upgrade("logistics_drive"), "Activating a focused row inspects research without authorizing purchase")
	panel.select_category(2)
	await frames()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	panel._select("bunker_dance_4")
	await frames()
	click.position = panel._button_for("bunker_dance_4").get_global_transform_with_canvas()*(panel._button_for("bunker_dance_4").size*.5)
	click.pressed = true
	view.push_input(click, true)
	click.pressed = false
	view.push_input(click, true)
	await frames()
	check(panel.selected_id == "bunker_dance_4" and game.upgrades.points == saved_points, "Actual mouse click inspects a software stage without purchasing")
	panel._select("logistics_drive")
	panel.prerequisite_button.pressed.emit()
	check(panel.selected_id == "medic_logistics", "Prerequisite button navigates to actual parent")
	var before: int = game.upgrades.points
	panel._select("precision_lines")
	panel.node_buttons[UpgradeSystem.NODES.find(game.upgrades.node_data("precision_lines"))].pressed.emit()
	check(game.upgrades.points == before, "Card inspection does not spend shared points")
	panel.purchase_button.pressed.emit()
	check(game.upgrades.points == before - 5 and game.upgrades.has_upgrade("precision_lines"), "Explicit confirmation purchases real selected research")
	var dance_budget: int = game.upgrades.points
	for id: String in ["bunker_dance","bunker_dance_2","bunker_dance_3","bunker_dance_4","bunker_dance_5"]:
		panel._select(id)
		check(not panel.purchase_button.disabled, "Sequential software research enables only its genuine affordable successor")
		panel.purchase_button.pressed.emit()
		check(game.upgrades.has_upgrade(id), "Explicit software confirmation executes the real research transaction")
	check(game.upgrades.points == dance_budget-14 and game.upgrades.medic_dance_level() == 5, "All software confirmations conserve the actual 14 point cost and unlock all five moves")
	await frames()
	for id: String in panel._stage_ids:
		check(UiArt.FONT.get_string_size(L.text("Freigeschaltet"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= panel.ROW_STATUS_WIDTH, "Owned software stage label fits its actual status-column budget")
	for locale in ["de","en"]:
		L.set_locale(locale, false)
		panel._refresh()
		await frames()
		if capture_enabled:
			await RenderingServer.frame_post_draw
			check(view.get_texture().get_image().save_png(OUTPUT+"desktop-"+locale+"-crew-earned.png") == OK, "Actual paid software progression capture saved")
	# Separate prepared garage state verifies vehicle controls after the wave20 gate.
	game.campaign.active = true
	game.campaign.expedition.vehicle.unlocked = true
	game.campaign.expedition.stage = "preparation"
	game.upgrades.points = 19
	game.upgrades.owned["convoy_mg"] = true
	panel._select("convoy_reload")
	check(not panel.purchase_button.disabled, "Prepared vehicle garage enables affordable dependent research")
	game.campaign.expedition.stage = "travel"
	panel._refresh()
	check(panel.purchase_button.disabled, "Vehicle research cannot be purchased while driving")
	game.campaign.expedition.stage = "preparation"
	view.size = Vector2i(2560, 1440)
	view.size_2d_override = Vector2i(1600, 900)
	game.hud._layout_viewport()
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		panel._refresh()
		await frames()
		if capture_enabled:
			await RenderingServer.frame_post_draw
			check(view.get_texture().get_image().save_png(OUTPUT + "qhd-" + locale + "-vehicle-ready.png") == OK, "Prepared vehicle garage capture saved")
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	view.queue_free()
	await process_frame
	var report := {"checks":checks,"failures":failures,"native_capture":capture_enabled,"resolutions":[[2560,1440],[1440,900],[960,600]],"locales":["de","en"],"catalog_nodes":UpgradeSystem.NODES.size(),"fixture":{"wave":16,"tech_points":19,"owned":["bunker_workshop","core_resilience","medic_logistics","weapon_handling","boots"],"enemy_spawning":"held","selected":["precision_lines","weapon_capacitor","bunker_dance_5","convoy_stabilizer"]}}
	var verification := FileAccess.open(OUTPUT+("render-verification.json" if capture_enabled else "headless-verification.json"),FileAccess.WRITE)
	verification.store_string(JSON.stringify(report,"\t"))
	verification.close()
	print("RESEARCH PLAN: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
