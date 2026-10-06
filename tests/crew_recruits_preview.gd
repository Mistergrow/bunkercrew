extends SceneTree
## Prepared locked/rescued roster states; real character and network panel controls.
const Roster = preload("res://scripts/crew_roster.gd")
const L = preload("res://scripts/locale_text.gd")
const OUTPUT := "res://artifacts/expedition/crew/"
var view: SubViewport
var game
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func frames() -> void:
	for index in 4: await process_frame
func capture(name: String) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size() == view.size and picture.save_png(OUTPUT+name+".png") == OK, "Native crew capture saved")
func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args(): quit(2); return
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Roster.persistence_enabled = false
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	for resolution in ["qhd","small"]:
		view.size = Vector2i(2560,1440) if resolution == "qhd" else Vector2i(960,600)
		view.size_2d_override = Vector2i(1600,900) if resolution == "qhd" else Vector2i(1440,900)
		game.hud._layout_viewport()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			Roster.unlocked.clear()
			game.selected_characters.assign(["mara","branko"])
			game.hud._open_character_selection(2)
			await frames()
			var panel = game.hud.character_panel
			check(panel.cards.size() == CharacterCatalog.CHARACTERS.size(), "Every authored selection card exists")
			check(panel.card_scroll.get_rect().end.y<panel.begin_button.position.y,"Native scrolling card board clears Start and Back")
			for index in panel.cards.size():
				var card: Button = panel.cards[index]
				check(Rect2(Vector2.ZERO,panel.card_content.size).encloses(card.get_rect()), "Crew card fits its native scroll content")
				for other in range(index): check(not card.get_rect().intersects(panel.cards[other].get_rect()), "Crew cards retain independent focus areas")
			for id in Roster.RECRUITS:
				check(CharacterCatalog.selection_title(id) == L.text("VERMISST"), "Missing crew titles reveal no identity")
				check(CharacterCatalog.selection_detail(id) == L.text("Identität unbekannt. Halte auf der Reise Ausschau."), "Missing crew details reveal no role or traits")
			for index in range(Roster.BASE_CREW.size(),CharacterCatalog.CHARACTERS.size()):
				var tooltip: String = panel.cards[index].tooltip_text
				check(not CharacterCatalog.CHARACTERS[index].title.to_lower() in tooltip.to_lower() and not "%" in tooltip, "Locked native tooltip does not disclose recruit")
			panel.select_character("levin")
			check(game.selected_characters[0] == "mara", "Locked local crew cannot be selected")
			panel.cards[-1].grab_focus()
			await frames()
			check(panel.card_scroll.get_global_rect().encloses(panel.cards[-1].get_global_rect()),"Last anonymous recruit scrolls completely into view")
			await capture(resolution+"-"+locale+"-locked")
			for site in ["refinery_archive","radar_archive","dam_vault"]: CharacterCatalog.unlock_for_site(site)
			for id in ["oskar","rika"]: check(Roster.unlock(id),"Prepared explicit encounter entitlement unlocks "+id)
			panel._refresh()
			panel.select_character("levin")
			panel.select_slot(1)
			panel.select_character("selma")
			check(game.selected_characters.slice(0,2) == ["levin","selma"], "The two active crew slots select rescued characters independently")
			panel.cards[-1].grab_focus()
			await frames()
			check(panel.card_scroll.get_global_rect().encloses(panel.cards[-1].get_global_rect()),"Last rescued character remains fully accessible")
			await capture(resolution+"-"+locale+"-rescued")
			game.hud.overlay = "network"
			game.hud._apply_overlay_pause()
			await frames()
			var network_panel = game.hud.network_panel
			check(network_panel.character_buttons.size() == CharacterCatalog.CHARACTERS.size(), "Network panel retains every authored character choice")
			check(network_panel.character_scroll.get_rect().end.y<network_panel.start_button.position.y,"Coop scrolling choices clear map/start controls")
			for button in network_panel.character_buttons:
				check(button.get_rect().size.y>=61 and button.size.x<=network_panel.character_scroll.size.x,"Coop crew retains full readable character rows")
			network_panel.character_scroll.scroll_vertical = roundi(network_panel.character_scroll.get_v_scroll_bar().max_value)
			await frames()
			check(network_panel.character_scroll.get_global_rect().encloses(network_panel.character_buttons[-1].get_global_rect()),"Last coop character is reachable in native scroll")
			await capture(resolution+"-"+locale+"-coop")
			Roster.unlocked.clear()
			game.selected_characters.assign(["mara","branko"])
			network_panel._refresh()
			await capture(resolution+"-"+locale+"-coop-missing")
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("CREW PREVIEW: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
