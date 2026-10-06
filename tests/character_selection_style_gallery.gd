extends "res://tests/ui_audit_gallery.gd"
## Actual character selection and shared options/lobby backgrounds before/after.
## Native viewports, both locales, all party sizes and last rescued/locked row.
const CAPTURE_SIZES := [Vector2i(1280,720),Vector2i(960,600)]

func _capture_checked(id: String) -> void:
	await capture(id)
	var bounds := view.get_visible_rect()
	for control: Dictionary in visible_controls():
		var values: Array = control.rect
		var rectangle := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
		check(bounds.grow(1.0).encloses(rectangle),id+": native viewport contains "+str(control.path))
	check(game.players.is_empty() and not game.started,id+": preparing selection creates no gameplay actors")
	if game.hud.overlay=="characters":
		var panel: CharacterSelectPanel = game.hud.character_panel
		entries[-1].merge({"player_count":panel.player_count,"active_slot":panel.active_slot,"characters":game.selected_characters.duplicate(),"unlocked_characters":Roster.unlocked.keys(),"scroll_vertical":panel.card_scroll.scroll_vertical,"preview_character":str(panel.get("preview_character_id")) if "preview_character_id" in panel else game.selected_characters[panel.active_slot]})

func _hold_panel(panel: CharacterSelectPanel) -> void:
	panel.elapsed = 3.8
	panel.set_process(false)
	if "_landscape" in panel:
		var landscape: Dictionary = panel.get("_landscape")
		var scenery: Node = landscape.get("preview")
		if is_instance_valid(scenery):
			scenery.set_process(false)
	panel.queue_redraw()
	for card: Button in panel.cards:
		card.queue_redraw()

func _fixture() -> void:
	Roster.unlocked.clear()
	Roster._loaded = true
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	actual_network = game.network
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
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
	await overlay("menu")
	for count in [1,2,3,4]:
		game.hud._open_character_selection(count)
		await frames()
		var count_panel: CharacterSelectPanel = game.hud.character_panel
		count_panel.select_slot(count-1)
		count_panel.cards[count-1].grab_focus()
		_hold_panel(count_panel)
		await _capture_checked("solo-mara" if count==1 else "coop-%d-slot-%d"%[count,count])
		check(count_panel.slot_buttons.filter(func(button: Button): return button.visible).size()==count,"Party exposes exactly "+str(count)+" usable slot selectors")
		if count<4:
			game.hud._close_character_selection()
			await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	panel.cards[-1].grab_focus()
	panel._reveal_card(panel.cards[-1])
	await frames()
	check(not CharacterCatalog.is_unlocked("rika"),"Actual final recruit row remains locked before a rescue")
	await _capture_checked("last-row-locked-rika")
	var previous: Array = game.selected_characters.duplicate()
	panel.select_character("rika")
	check(game.selected_characters==previous,"Locked last row cannot change actual party selection")
	for id: String in Roster.RECRUITS:
		check(Roster.unlock(id),"Prepared local rescue entitlement: "+id)
	panel.refresh_locale()
	panel.cards[-1].grab_focus()
	panel._reveal_card(panel.cards[-1])
	await frames()
	panel.select_character("rika")
	await _capture_checked("last-row-rescued-rika")
	check(game.selected_characters[3]=="rika","Actually rescued final recruit can become player four")
	panel.select_slot(0)
	panel.cards[0].grab_focus()
	panel._reveal_card(panel.cards[0])
	await frames()
	await _capture_checked("all-rescued-first-row")
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled and not Roster.persistence_enabled,"Prepared UI states never persist settings, unlocks or progress")
	await Cleanup.free_scene(game,self)
	game = null
	await frames()

func _write_gallery() -> void:
	var all_entries := entries.duplicate()
	var other := "baseline" if phase=="final" else "final"
	var previous_path := output_directory+other+"/report.json"
	if FileAccess.file_exists(previous_path):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(previous_path))
		if previous is Dictionary:
			all_entries.append_array(previous.get("screens",[]))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Figurenwahl</title><style>body{background:#111c19;color:#dddcc9;font:15px system-ui;margin:24px}a{color:#d6ad64}select{padding:8px;margin:4px;background:#26342d;color:#dddcc9;border:1px solid #687168}nav{position:sticky;top:0;padding:8px;background:#111c19}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}figure[hidden]{display:none}</style><h1>Bunkercrew · Figurenwahl im gemeinsamen Menüstil</h1><p>Echte Hauptszene, Figurenwahl, Optionen und Netzwerklobby. Solo sowie zwei, drei und vier Spieler; letzte Figur gesperrt und nach vorbereiteter Rettung. DE/EN, native 1280×720 und 960×600. Kein HTML-Mock, keine Verbindung, Mikrofonaufnahme oder Profiländerung.</p><nav><select id='size' onchange='filter()'><option selected>1280</option><option>960</option></select><select id='lang' onchange='filter()'><option selected>de</option><option>en</option></select><select id='stage' onchange='filter()'><option selected>final</option><option>baseline</option></select><a href='"+phase+"/report.json'>Messwerte und Zustände</a></nav><main>"
	for entry: Dictionary in all_entries:
		var stage: String = str(entry.file).get_slice("/",0)
		html += "<figure data-size='%d' data-lang='%s' data-stage='%s'><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d · %s</figcaption></figure>"%[entry.resolution[0],entry.locale,stage,entry.file,entry.file,entry.screen,entry.screen,entry.locale.to_upper(),entry.resolution[0],entry.resolution[1],stage]
	html += "</main><script>function filter(){document.querySelectorAll('figure').forEach(e=>e.hidden=e.dataset.size!==size.value||e.dataset.lang!==lang.value||e.dataset.stage!==stage.value)}filter()</script></html>"
	var file := FileAccess.open(output_directory+"index.html",FileAccess.WRITE)
	file.store_string(html)
	file.close()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	phase = "baseline"
	output_directory = "res://artifacts/character-selection-style-20261005/qa/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=").simplify_path().trim_suffix("/")+"/"
	if phase not in ["baseline","final"]:
		quit(2)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless":
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	Roster.persistence_enabled = false
	Roster._loaded = true
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
	var report := {"phase":phase,"checks":checks,"failures":failures,"rendered":capture_enabled,"screens":entries,"findings":findings,"prepared_state":"Actual main scene and native SubViewport without 2D size override. Shared mountain_pass menu selection; actual offline options/lobby references. Solo and 2/3/4 local selection, focused final locked row, then local explicit unlocks for the four recruits and actual Rika selection. Menu preview timing held at3.8. All persistence disabled, no actors created, master muted, no transport/microphone, --no-profile-save."}
	var file := FileAccess.open(output_directory+phase+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	if capture_enabled:
		_write_gallery()
	view.queue_free()
	await process_frame
	print("CHARACTER SELECTION STYLE GALLERY %s: %d/%d checks; %d captures; %d label findings"%[phase,checks-failures,checks,entries.size(),findings.size()])
	quit(1 if failures or not findings.is_empty() else 0)
