extends "res://tests/ui_audit_gallery.gd"
## Native captures of the personal record and session confirmation in the real
## menu and held four-worker world. The fixture never saves or starts transport.
const CAPTURE_SIZES := [Vector2i(1280,720),Vector2i(960,600)]

func _fixture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	actual_network = game.network
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	game.combat_events.dance_levels.clear()
	game.campaign.persistence_enabled = false
	await frames(5)
	game.hud._layout_viewport()
	game.hud.main_menu_panel.restore_navigation({"environment":"mountain_pass","focus":"options"})
	game.hud.audio_return_overlay = "menu"
	await overlay("audio")
	game.hud.options_panel.select_tab(0)
	game.hud.options_panel.tab_buttons[0].grab_focus()
	await _capture_checked("reference-options")
	await overlay("network")
	await _capture_checked("reference-lobby")
	game.hud.personnel_return_overlay = "menu"
	game.hud.personnel_tab = "skills"
	await overlay("personal")
	for section: String in ["skills","dances","achievements"]:
		game.hud.personal_panel.select_tab(section)
		game.hud.personal_panel.tab_buttons[section].grab_focus()
		check(game.players.is_empty(),"Menu record does not construct a player: "+section)
		await _capture_checked("menu-"+section)
	check(game.hud.personal_panel.skill_buttons.values().all(func(button): return button.disabled),"Empty menu record disables every purchase")
	# The real start flow leaves its menu panel before creating the running
	# world. Keep this direct scenario fixture from retaining menu scenery.
	await overlay("menu")
	check(not is_instance_valid(game.hud.personal_panel),"Menu record is released before preparing gameplay")
	game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.camera.position = Vector2(670,70)
	game.camera.zoom = Vector2.ONE
	for actor: Node in game.players:
		actor.set_physics_process(false)
		actor.progression.award_damage(1500.0)
	game.combat_events.unlock("first_kill")
	game.combat_events.unlock("armor")
	await overlay("personal")
	var record: PersonalPanel = game.hud.personal_panel
	check(record.player_buttons.size()==4,"Prepared actual local crew has four record selectors")
	record.select_player(3)
	for section: String in ["skills","dances","achievements"]:
		record.select_tab(section)
		record.tab_buttons[section].grab_focus()
		await _capture_checked("four-"+section)
	record.change_achievement_page(2)
	await _capture_checked("four-achievements-last")
	game.players[3].progression.level = 12
	game.combat_events.record_character_dance_level(game.players[3].character_id,12)
	record.select_tab("dances")
	record.tab_buttons.dances.grab_focus()
	await _capture_checked("four-dances-unlocked")
	await overlay("pause")
	for action: String in ["restart","main_menu"]:
		var opener: Button = game.hud.pause_buttons[action]
		opener.grab_focus()
		if action=="restart": game.hud._restart_match()
		else: game.hud._request_main_menu()
		await frames()
		check(game.hud.restart_dialog.visible and game.hud.has_session_action(),"Actual "+action+" confirmation is presented")
		check(game.hud.restart_dialog.cancel_button.has_focus(),"Cancel owns initial confirmation focus: "+action)
		await _capture_checked("confirm-"+action)
		game.hud._cancel_restart()
		await frames()
		check(game.hud.overlay=="pause" and game.hud.pause_buttons[action].has_focus(),"Cancel restores held pause and opener focus: "+action)
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled,"Prepared record progress and settings remain private")
	await Cleanup.free_scene(game,self)
	game = null
	await frames()

func _capture_checked(id: String) -> void:
	await capture(id)
	var bounds := view.get_visible_rect()
	for control: Dictionary in visible_controls():
		var values: Array = control.rect
		var rectangle := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
		check(bounds.grow(1.0).encloses(rectangle),"Native viewport contains control: "+id+" / "+str(control.path))

func _write_gallery() -> void:
	var all_entries := entries.duplicate()
	var other := "baseline" if phase=="final" else "final"
	var previous_path := output_directory+other+"/report.json"
	if FileAccess.file_exists(previous_path):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(previous_path))
		if previous is Dictionary: all_entries.append_array(previous.get("screens",[]))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Akte und Bestätigungen</title><style>body{background:#111c19;color:#dddcc9;font:15px system-ui;margin:24px}a{color:#d6ad64}select{padding:8px;margin:4px;background:#26342d;color:#dddcc9;border:1px solid #687168}nav{position:sticky;top:0;padding:8px;background:#111c19}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}figure[hidden]{display:none}</style><h1>Bunkercrew · Akte und Bestätigungen</h1><p>Echte Panels und vier echte lokale Figuren; DE/EN, native 1280×720 und 960×600. Die Fortschrittsdaten wurden für diese Ansichten vorbereitet. Kein Hör-/Spieltest, keine Profiländerung, keine Verbindung und keine Mikrofonaufnahme.</p><nav><select id='size' onchange='filter()'><option selected>1280</option><option>960</option></select><select id='lang' onchange='filter()'><option selected>de</option><option>en</option></select><select id='stage' onchange='filter()'><option selected>final</option><option>baseline</option></select><a href='"+phase+"/report.json'>Messwerte</a></nav><main>"
	for entry: Dictionary in all_entries:
		var stage: String = str(entry.file).get_slice("/",0)
		html += "<figure data-size='%d' data-lang='%s' data-stage='%s'><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d · %s</figcaption></figure>" % [entry.resolution[0],entry.locale,stage,entry.file,entry.file,entry.screen,entry.screen,entry.locale.to_upper(),entry.resolution[0],entry.resolution[1],stage]
	html += "</main><script>function filter(){document.querySelectorAll('figure').forEach(e=>e.hidden=e.dataset.size!==size.value||e.dataset.lang!==lang.value||e.dataset.stage!==stage.value)}filter()</script></html>"
	var file := FileAccess.open(output_directory+"index.html",FileAccess.WRITE)
	file.store_string(html)
	file.close()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	phase = "baseline"
	output_directory = "res://artifacts/personnel-session-20261004/qa/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): phase=argument.trim_prefix("--phase=")
	if phase not in ["baseline","final"]: quit(2); return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	AudioServer.set_bus_mute(0,true)
	Roster.persistence_enabled = false
	Roster.unlocked.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory+phase))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	for resolution: Vector2i in CAPTURE_SIZES:
		view.size = resolution
		for locale: String in ["de","en"]:
			L.set_locale(locale,false)
			await _fixture()
	var report := {"phase":phase,"checks":checks,"failures":failures,"rendered":capture_enabled,"screens":entries,"findings":findings,"prepared_state":"Real main scene in a native SubViewport without 2D size override. Empty player list in the menu; four local ash_foundry workers with 1500 damage XP and P4 selected. First kill/armor achievements unlocked; P4 level12 arranged for unlocked dance presentation. Simulation held, master muted, no transport or microphone, --no-profile-save and all persistence flags disabled."}
	var file := FileAccess.open(output_directory+phase+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	if capture_enabled: _write_gallery()
	view.queue_free()
	await process_frame
	print("PERSONNEL SESSION GALLERY %s: %d/%d checks; %d captures; %d label findings" % [phase,checks-failures,checks,entries.size(),findings.size()])
	quit(1 if failures or not findings.is_empty() else 0)
