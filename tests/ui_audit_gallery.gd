extends SceneTree
## Disposable real panels, DE/EN and three native outputs. No connection,
## recording, calibration playback, profile write or research purchase occurs.
const L := preload("res://scripts/locale_text.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var output_directory := "res://artifacts/ui-hardening/"
const RESOLUTIONS := [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080)]
var game
var view: SubViewport
var phase := "baseline"
var capture_enabled := false
var checks := 0
var failures := 0
var entries: Array[Dictionary] = []
var findings: Array[Dictionary] = []
var actual_network: Node
var additional_ui: Node
var presentation_role := "offline"
var requested_screens := PackedStringArray()

class GuestUiProbe extends Node:
	# UI conditions only. This node owns no transport, socket or connection.
	var active := true
	var is_host := false
	var local_player_id := 2
	var state := "playing"
	var match_paused := true
	var peer_connected := true
	var max_players := 4
	var relay_url := ""
	var room_social_service := ""
	# The session contract reads this field externally.
	@warning_ignore("unused_private_class_variable")
	var _authenticated := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func overlay(id: String) -> void:
	game.hud.overlay = id
	game.hud._apply_overlay_pause()
	await frames()

func visible_controls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Array[Node] = [game.hud.canvas]
	if is_instance_valid(additional_ui): pending.append(additional_ui)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is Control or not node.is_visible_in_tree(): continue
		if not node is BaseButton and not node is LineEdit and not node is Range: continue
		var bounds: Rect2 = node.get_global_rect()
		var clipped := false
		var ancestor: Node = node.get_parent()
		while ancestor != null and ancestor != game.hud.canvas:
			if ancestor is Control and ancestor.clip_contents:
				var intersection := bounds.intersection(ancestor.get_global_rect())
				if not intersection.has_area(): clipped = true
			ancestor = ancestor.get_parent()
		if clipped: continue
		var text_value := ""
		var label_width := 0.0
		var available: float = node.size.x
		if node is Button and not node.text.is_empty():
			text_value = L.text(node.text)
			label_width = node.get_theme_font("font").get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x
			var style: StyleBox = node.get_theme_stylebox("normal")
			available -= style.get_content_margin(SIDE_LEFT)+style.get_content_margin(SIDE_RIGHT)
			if node is OptionButton: available -= 18.0
			elif node is CheckButton: available -= 32.0
		var clipped_by_scroll := false
		ancestor = node.get_parent()
		while ancestor!=null:
			if ancestor is ScrollContainer:
				bounds = bounds.intersection(ancestor.get_global_rect())
				clipped_by_scroll = true
			ancestor = ancestor.get_parent()
		result.append({"path":str(view.get_path_to(node)),"type":node.get_class(),"label":text_value,"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"width":label_width,"available":available,"focus":node.has_focus(),"disabled":node.disabled if node is BaseButton else false,"label_fits":label_width<=available+1.0,"scroll_clipped":clipped_by_scroll})
	return result

func capture(id: String) -> void:
	if not requested_screens.is_empty() and id not in requested_screens: return
	await frames()
	var controls := visible_controls()
	var focus := view.gui_get_focus_owner()
	for control: Dictionary in controls:
		if not control.label_fits:
			findings.append({"screen":id,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"kind":"control_label_overflow","control":control.path,"label":control.label,"width":control.width,"available":control.available})
	var name := "%s-%s-%s" % [str(view.size.x),L.current_locale(),id]
	if capture_enabled:
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		check(picture.get_size()==view.size,"Native output size: "+name)
		check(picture.save_png(output_directory+phase+"/"+name+".png")==OK,"Capture saved: "+name)
	entries.append({"screen":id,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"file":phase+"/"+name+".png","overlay":game.hud.overlay,"started":game.started,"paused":paused,"controls":controls,"focus_owner":str(view.get_path_to(focus)) if is_instance_valid(focus) else "","microphone_capturing":game.microphone.capturing,"network_active":actual_network.active,"presentation_role":presentation_role})
	check(not game.microphone.capturing and not actual_network.active,"UI inspection has no microphone or network activation: "+id)

func fixture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(5)
	actual_network = game.network
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	game.combat_events.dance_levels.clear()
	game.campaign.persistence_enabled = false
	game.hud._layout_viewport()
	if is_instance_valid(game.hud.main_menu_panel):
		game.hud.main_menu_panel.set_process(false)
		game.hud.main_menu_panel.preview.set_process(false)
	await capture("main")
	game.hud._open_scenario_selection(4)
	await frames()
	game.hud.scenario_panel.choose("environment","mountain_pass")
	game.hud.scenario_panel.choose("position","center")
	await capture("scenario")
	game.hud.scenario_panel.confirm()
	await frames()
	game.hud.character_panel.set_process(false)
	await capture("characters-four")
	await overlay("network")
	await capture("network-offline")
	game.hud.network_panel.show_server_options = true
	game.hud.network_panel.server_field.text = "wss://relay.example.invalid"
	game.hud.network_panel.public_address_field.text = "203.0.113.5"
	game.hud.network_panel.code_field.text = "BCEXAMPLE123"
	await capture("network-server-options")
	game.network.state = "error"
	game.network.error_message = L.text("Beide Spieler benötigen dieselbe Spielversion.")
	await capture("network-error")
	game.network.state = "offline"
	game.network.error_message = ""
	game.hud.audio_return_overlay = "menu"
	await overlay("audio")
	for tab in 5:
		game.hud.options_panel.select_tab(tab)
		await capture("options-"+["display","camera","audio","rhythm","language"][tab])
	game.hud.options_panel.select_tab(3)
	game.hud.options_panel._open_calibration()
	await capture("calibration-idle")
	var calibration: Control = game.hud.options_panel.calibration_panel
	calibration.closed.emit()
	calibration.queue_free()
	await frames()
	if phase=="final":
		game.hud.options_panel._open_music_lab(false)
		await frames()
		var lab: CanvasLayer = game.hud.options_panel.music_lab
		additional_ui = lab
		lab.set_process(false)
		lab.preview_clock.playing = false
		lab.preview_clock.advance(0.0)
		check(not lab.preview_session.native_active,"Music-lab audit never starts its native audio preview")
		check(lab.get_parent()==view and lab.theme_choice.has_focus(),"Music-lab controls open with focus inside the actual game viewport")
		await capture("music-lab-idle")
		lab.close()
		additional_ui = null
		await frames()
	game.hud._open_microphone()
	await frames()
	await capture("microphone-idle")
	await overlay("help")
	await capture("help-menu")
	game.hud.personnel_tab = "skills"
	await overlay("personal")
	await capture("personal-menu-skills")
	game.hud.personal_panel.select_tab("dances")
	await capture("personal-menu-dances")
	game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.camera.position = Vector2(670,70)
	game.camera.zoom = Vector2.ONE
	for actor in game.players:
		actor.set_physics_process(false)
		actor.progression.award_damage(1500.0)
	game.upgrades.points = 12
	game.elapsed = 2183.0
	await capture("gameplay-four")
	await overlay("pause")
	await capture("pause")
	if phase=="final":
		for action: String in ["restart","main_menu"]:
			game.hud.pause_buttons[action].grab_focus()
			await capture("pause-"+action+"-selected")
		game.hud.pause_buttons.continue_match.grab_focus()
		game.hud._restart_match()
		await frames()
		await capture("confirm-restart")
		game.hud._cancel_restart()
		await frames()
		game.hud._request_main_menu()
		await frames()
		await capture("confirm-menu")
		game.hud._cancel_restart()
		var guest := GuestUiProbe.new()
		game.add_child(guest)
		game.network = guest
		presentation_role = "Prepared online guest UI, no sockets or handshake; actual session remains offline"
		game.hud.last_overlay = "!"
		await frames()
		check(game.hud.pause_buttons.restart.disabled,"Guest presentation disables the actual pause restart button")
		game.hud._restart_match()
		check(not game.hud.restart_dialog.visible,"Guest presentation cannot open a restart confirmation")
		await capture("pause-online-guest")
		game.hud.pause_buttons.main_menu.grab_focus()
		await capture("pause-online-guest-leave-selected")
		game.network = actual_network
		presentation_role = "offline"
		guest.queue_free()
		await frames()
	await overlay("help")
	await capture("help-match")
	await overlay("personal")
	for tab in ["skills","achievements","dances"]:
		game.hud.personal_panel.select_tab(tab)
		await capture("personal-"+tab)
	game.hud.personal_panel.select_tab("achievements")
	game.hud.personal_panel.change_achievement_page(2)
	await capture("personal-achievements-last")
	await overlay("upgrades")
	for category in UpgradeSystem.CATEGORIES.size():
		game.hud.upgrade_panel.tab_buttons[category].grab_focus()
		game.hud.upgrade_panel.select_category(category)
		await capture("upgrades-"+str(category))
	var state: CampaignState = game.campaign
	check(state.active and state.mission_running,"Actual campaign defense fixture is initialized")
	var reward := state.complete_mission(state.mission_id,20,game.players,game.upgrades,{"steel":12,"ammo":6,"concrete":18,"scrap":8})
	check(not reward.is_empty(),"Actual mission completion prepares convoy UI")
	state.select_destination("harbor")
	state.expedition.vehicle.cargo = {"steel":4,"ammo":3,"concrete":6}
	await overlay("expedition")
	game.hud.expedition_panel._choose_route("harbor")
	await capture("expedition-harbor")
	game.hud.expedition_panel._choose_route("quarry")
	await capture("expedition-locked")
	for result in ["victory","defeat","campaign_victory"]:
		game.rounds.phase = result
		game.core.hp = 0 if result=="defeat" else game.core.max_hp
		await overlay(result)
		await capture(result)
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not state.persistence_enabled,"All fixture progress and audio writes remain disabled")
	await Cleanup.free_scene(game,self)
	game = null
	await frames()

func write_index() -> void:
	var html := "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew UI review</title><style>body{background:#17251f;color:#e0decb;font:15px system-ui;margin:24px}a{color:#d9ac60}nav{position:sticky;top:0;padding:12px;background:#17251f}select{margin:4px;padding:8px;background:#29362f;color:#e0decb;border:1px solid #63726c}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}figure[hidden]{display:none}</style><h1>Bunkercrew · UI-Prüfung</h1><p>Echte UI-Panels, DE/EN, 960×600 / 1440×900 / 1920×1080. Vorbereitete Vier-Spieler-Schicht und Konvoi; keine Profiländerungen, Verbindungen oder Mikrofonaufnahmen. Die Bestands-Grafik bleibt erhalten.</p><nav><select id='size' onchange='filter()'><option>960</option><option selected>1440</option><option>1920</option></select><select id='lang' onchange='filter()'><option selected>de</option><option>en</option></select><select id='stage' onchange='filter()'><option selected>final</option><option>baseline</option></select><a href='inventory.json'>Inventar und Befunde</a></nav><main>"
	var all_entries := entries.duplicate()
	var other_phase := "baseline" if phase=="final" else "final"
	if FileAccess.file_exists(output_directory+other_phase+"/report.json"):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(output_directory+other_phase+"/report.json"))
		if previous is Dictionary: all_entries.append_array(previous.get("screens",[]))
	for entry: Dictionary in all_entries:
		var stage: String = str(entry.file).get_slice("/",0)
		html += "<figure data-size='%d' data-lang='%s' data-stage='%s'><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d · %s</figcaption></figure>" % [entry.resolution[0],entry.locale,stage,entry.file,entry.file,entry.screen,entry.screen,entry.locale.to_upper(),entry.resolution[0],entry.resolution[1],stage]
	html += "</main><script>function filter(){document.querySelectorAll('figure').forEach(e=>e.hidden=e.dataset.size!==size.value||e.dataset.lang!==lang.value||e.dataset.stage!==stage.value)}filter()</script>"
	var file := FileAccess.open(output_directory+"index.html",FileAccess.WRITE)
	file.store_string(html)
	file.close()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=").simplify_path().trim_suffix("/")+"/"
			if not output_directory.begins_with("res://artifacts/"): quit(2); return
		if argument.begins_with("--only="): requested_screens = argument.trim_prefix("--only=").split(",",false)
	if phase not in ["baseline","final"]: quit(2); return
	capture_enabled = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	AudioServer.set_bus_mute(0,true)
	Roster.persistence_enabled = false
	Roster.unlocked.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory+phase))
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for resolution: Vector2i in RESOLUTIONS:
		view.size = resolution
		view.size_2d_override = Vector2i(1600,900) if resolution.x==1920 else Vector2i(1440,900)
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			await fixture()
	var current_captures := entries.size()
	var complete_matrix_checks := checks
	if not requested_screens.is_empty() and FileAccess.file_exists(output_directory+phase+"/report.json"):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(output_directory+phase+"/report.json"))
		if previous is Dictionary:
			complete_matrix_checks = int(previous.get("complete_matrix_checks",previous.get("checks",checks)))
			for entry: Dictionary in previous.get("screens",[]):
				if str(entry.screen) not in requested_screens: entries.append(entry)
			for finding: Dictionary in previous.get("findings",[]):
				if str(finding.screen) not in requested_screens: findings.append(finding)
	var report := {"phase":phase,"checks":checks,"complete_matrix_checks":complete_matrix_checks,"failures":failures,"rendered":capture_enabled,"last_run_only":Array(requested_screens),"fixture":"Disposable actual main scene, empty roster unlocks/achievements, held four-player ash_foundry gameplay and completed initial mission for actual convoy. Master audio muted; no connect, recording, calibration or lab audition start or purchase; every persistence flag disabled. Guest pause uses a role-only node with no transport; the actual session remains offline.","screens":entries,"findings":findings,"assets":{"shared_renderer":"scripts/ui_art.gd","active_style":"Existing painted steel, body/menu/title fonts, procedural steel grain and atlas icons reused.","new_bitmap_required":false,"reason":"The reviewed interactions are native controls already covered by UiArt. Bitmap generation would not repair focus, stale state or modal navigation."}}
	for path in [output_directory+phase+"/report.json",output_directory+"inventory.json"]:
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	if capture_enabled: write_index()
	view.queue_free()
	await process_frame
	print("UI AUDIT %s: %d/%d checks passed; %d captured screens; %d total gallery screens; %d label findings" % [phase,checks-failures,checks,current_captures,entries.size(),findings.size()])
	quit(1 if failures else 0)
