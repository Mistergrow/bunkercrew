extends SceneTree
## Native rendering of the genuine solo controller, world NPC and eight crew
## controls. Small host window; all evidence comes from sized SubViewports.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const OUTPUT := "res://artifacts/solo-story/ui/gallery/"
var view: SubViewport
var game
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var rendered := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("SOLO VIEW %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int=7) -> void:
	for unused in count: await process_frame

func _fixture(resolution: Vector2i,locale: String) -> void:
	CrewRoster.unlocked.clear()
	view.size = resolution
	L.set_locale(locale,false)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(9)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.solo_story.records.persistence_enabled = false
	game.hud._layout_viewport()

func _dispose() -> void:
	check(not game.network.active and not game.microphone.capturing,"Capture leaves transport and microphone closed")
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled and not game.solo_story.records.persistence_enabled and not CrewRoster.persistence_enabled,"Capture leaves all saved profiles untouched")
	paused = false
	check(await Cleanup.free_scene(game,self),"Native scene and audio handles release")
	game = null

func _capture(id: String,kind: String,prepared: String) -> void:
	await frames()
	if is_instance_valid(game.hud.solo_story_panel):
		var panel: Control = game.hud.solo_story_panel
		var bounds: Rect2 = game.hud.screen_rect()
		check(bounds.encloses(panel.reading_scroll.get_rect()) and bounds.encloses(panel.close_button.get_rect()),id+" reader and Close fit the native screen")
		check(panel.reading_content.size.x<=panel.reading_scroll.size.x+1,id+" authored and translated prose wraps within its reading column")
		var labels: Array[Node] = panel.reading_content.find_children("*","Label",true,false)
		check(labels.all(func(label): return not label.clip_text and label.max_lines_visible==-1 and label.get_line_count()>0),id+" native labels retain every authored line")
		check(panel.mode!="encounter" or bounds.encloses(panel.recruit_button.get_rect()),id+" explicit recruitment action stays inside the screen")
	var filename := id+".png"
	if rendered:
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		check(picture.get_size()==view.size and picture.save_png(OUTPUT+filename)==OK,id+" captures genuine native "+str(view.size))
	var state := {"id":id,"file":filename,"kind":kind,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"prepared":prepared,"started":game.started,"players":game.players.size(),"overlay":game.hud.overlay,"site":game.solo_story.site_id(),"native_renderer":RenderingServer.get_video_adapter_name(),"profile_saving":false,"master_muted":true}
	if kind=="world" and game.solo_story.npcs.has("oskar"):
		var npc: Node2D = game.solo_story.npcs.oskar
		var actual_screen: Vector2 = npc.get_global_transform_with_canvas()*Vector2(0,-76)
		var projected_screen: Vector2 = game.hud.canvas.get_global_transform_with_canvas()*game.hud.world_to_ui(game.solo_story.target_position())
		state.marker_projection = {"actual_npc_target":[actual_screen.x,actual_screen.y],"hud_target":[projected_screen.x,projected_screen.y],"distance":actual_screen.distance_to(projected_screen),"camera_frozen":not game.player_camera.is_processing()}
		state.objective_panels = []
		state.story_status = {"director":game.story.get_instance_id(),"displays":game.story.displays_objectives(),"solo_enabled":game.solo_story.enabled,"group_count":get_nodes_in_group("story_objective_panels").size(),"canvas_controls":game.hud.canvas.get_children().map(func(child): return [child.name,child.get_script().resource_path if child.get_script()!=null else ""])}
		for objective in get_nodes_in_group("story_objective_panels"):
			if objective.director==game.story:
				state.objective_panels.append({"visible":objective.is_visible_in_tree(),"processing":objective.is_processing(),"has_layout":not objective.objective_layout().is_empty(),"position":[objective.position.x,objective.position.y],"size":[objective.size.x,objective.size.y]})
	if is_instance_valid(game.hud.solo_story_panel):
		var panel: Control = game.hud.solo_story_panel
		state.mode = panel.mode
		state.selected_site = panel.selected_site
		state.scroll = panel.reading_scroll.scroll_vertical
		state.max_scroll = roundi(panel.reading_scroll.get_v_scroll_bar().max_value-panel.reading_scroll.get_v_scroll_bar().page)
		state.encounter = panel.encounter_id
		state.can_recruit = not panel.recruit_button.disabled if panel.recruit_button.visible else false
		state.reason = str(panel._encounter.get("reason",""))
	captures.append(state)

func _prepare_story(site: String="quarry") -> void:
	var options := {"environment":"basalt_quarry" if site=="quarry" else "flooded_power_station","position":"center","build_type":"bastion"}
	check(game.campaign.begin_new(options,["mara"],1),"Prepared native solo campaign initializes")
	var ancestors: Array[String] = ["last_shift","harbor"]
	if site=="power_station": ancestors.assign(["last_shift","harbor","quarry","steelworks","rail_yard","canyon"])
	game.campaign.completed.assign(ancestors)
	check(game.campaign.select_destination(site) and not game.campaign.mission_start().is_empty(),"Prepared secured ancestors authorize "+site)
	game.story_mode = true
	game.start_scenario(1,options)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	await frames()
	for ancestor: String in ancestors: game.solo_story.records.mark("visited",ancestor)
	var npc_id := "oskar" if site=="quarry" else "rika"
	check(game.solo_story.enabled and game.solo_story.npcs.has(npc_id),"Real world contains native "+npc_id+" encounter")
	var npc: Node2D = game.solo_story.npcs[npc_id]
	game.players[0].position = npc.position+Vector2(52,0)
	game.players[0].preferred_focus = npc
	game.players[0].focus = npc
	game.players[0].set_physics_process(false)
	game.players[0].inventory.clear()
	game.rounds.phase = "build"
	await frames()

func _freeze_world_camera() -> void:
	game.player_camera.update_view(0,true)
	game.player_camera.set_process(false)
	await frames(3)
	var objectives := get_nodes_in_group("story_objective_panels").filter(func(panel): return panel.director==game.story)
	check(objectives.size()==1,"Actual solo story creates one native objective panel")
	for objective: Control in objectives:
		check(objective.is_visible_in_tree() and objective.is_processing() and not objective.objective_layout().is_empty(),"Actual objective panel remains visible, processing and populated")
		objective.queue_redraw()
	await frames(3)
	var npc: Node2D = game.solo_story.npcs.oskar
	var native_target: Vector2 = npc.get_global_transform_with_canvas()*Vector2(0,-76)
	var hud_target: Vector2 = game.hud.canvas.get_global_transform_with_canvas()*game.hud.world_to_ui(game.solo_story.target_position())
	check(native_target.distance_to(hud_target)<.2,"Native NPC and HUD objective projection agree after prepared camera freeze")
	check(game.players[0].focus==npc and game.players[0].position.distance_to(npc.position)==52.0,"Separated worker and physical Oskar retain actual nearby interaction focus")

func _story_views(suffix: String) -> void:
	await _prepare_story()
	await _freeze_world_camera()
	var npc: Node2D = game.solo_story.npcs.oskar
	var worker: Worker = game.players[0]
	await _capture("world-npc-"+suffix,"world","Actual quarry world, one worker 52px beside physical Oskar with real NPC focus; three-wave requirement unmet, waves held; follow camera snapped and held for capture; native objective marker sits above the helmet")
	check(npc.interact(worker,0.0),"Native nearby Oskar interaction opens dialogue")
	await frames()
	var panel: Control = game.hud.solo_story_panel
	check(panel.recruit_button.disabled and panel.close_button.has_focus(),"Fresh encounter explains missing defended waves and focuses Close")
	await _capture("encounter-locked-"+suffix,"encounter","Physical Oskar encounter before three defended waves, no concrete; native recruitment disabled")
	game.hud._close_solo_story()
	await frames()
	game.solo_story._cleared_wave = 3
	worker.inventory.concrete = 2
	check(npc.interact(worker,0.0),"Prepared wave evidence and genuinely carried concrete allow another native encounter")
	await frames()
	panel = game.hud.solo_story_panel
	check(not panel.recruit_button.disabled,"Prepared safe encounter exposes explicit recruitment")
	panel.recruit_button.grab_focus()
	await _capture("encounter-ready-"+suffix,"encounter","Physical Oskar, three-wave evidence prepared for UI, two actual carried concrete; recruitment is available and intentionally focused")
	panel.recruit_button.pressed.emit()
	await frames()
	check(game.hud.solo_story_panel==panel and panel.recruit_button.disabled and "oskar" in game.solo_story.records.recruited,"Genuine recruitment keeps the accepted conversation on screen")
	await _capture("encounter-joined-"+suffix,"encounter","Genuine roster/controller recruitment consumed exactly two concrete; after-conversation remains open, Close owns focus; no profile saving")
	game.hud._close_solo_story()
	await frames()
	check(game.solo_story.records.mark("events","quarry:wave_3"),"Prepared journal evidence accepts three defended waves")
	for entry_id: String in ["quarry:find_1","quarry:find_2"]:
		var find: Node2D = game.solo_story.finds[entry_id]
		worker.position = find.position+Vector2(8,0)
		check(find.interact(worker,0.0),"Physical field record opens its actual authored journal section")
		await frames(9)
		panel = game.hud.solo_story_panel
		var sections: Array = panel.reading_content.get_children().filter(func(section): return str(section.get_meta("entry_id",""))==entry_id)
		check(sections.size()==1 and panel.reading_scroll.get_global_rect().encloses(sections[0].get_child(0).get_global_rect()),"Genuine find locator reveals "+entry_id+" inside the native reader")
		if entry_id=="quarry:find_2": await _capture("journal-find-"+suffix,"journal","Actual worker physically read both quarry records. Latest field record opened its matching section and consumed the one-time locator; Oskar rescued, three-wave evidence prepared")
		game.hud._close_solo_story()
		await frames()
	game.hud._open_solo_story("journal")
	await frames()
	panel = game.hud.solo_story_panel
	panel.select_site("quarry")
	panel.reading_scroll.grab_focus()
	await frames()
	check(panel.site_buttons.size()==12 and panel._entry("power_station").details.is_empty(),"Twelve-station journal contains only already-discovered details")
	panel.reading_scroll.scroll_vertical = 0
	await _capture("journal-"+suffix,"journal","Actual quarry mission, secured ancestors and Oskar rescue; three-wave evidence prepared, both field records physically read, future stations anonymous")
	panel.reading_scroll.scroll_vertical = roundi(panel.reading_scroll.get_v_scroll_bar().max_value)
	await _capture("journal-bottom-"+suffix,"journal","Same authored journal at the bottom of its native scroll; all paragraphs remain reachable")
	game.hud._close_solo_story()
	await frames()

func _rika_view(suffix: String) -> void:
	await _prepare_story("power_station")
	var npc: Node2D = game.solo_story.npcs.rika
	var worker: Worker = game.players[0]
	game.solo_story._cleared_wave = 3
	worker.inventory.steel = 2
	check(npc.interact(worker,0.0),"Physical Rika encounter opens beside the flooded power station")
	await frames()
	check(not game.hud.solo_story_panel.recruit_button.disabled,"Rika uses genuine steel and prepared safe wave evidence")
	await _capture("encounter-rika-"+suffix,"encounter","Actual flooded power station, physical Rika and one worker; three defended waves prepared and two steel genuinely carried; no profile saving")
	game.hud._close_solo_story()
	await frames()

func _crew_views(suffix: String) -> void:
	game.hud._open_character_selection(1)
	await frames()
	var panel: CharacterSelectPanel = game.hud.character_panel
	panel.cards[7].grab_focus()
	await frames()
	check(panel.cards.size()==8 and panel.card_scroll.get_global_rect().encloses(panel.cards[7].get_global_rect()),"Native eighth locked card remains fully visible above the footer")
	await _capture("crew-locked-"+suffix,"crew","Actual native solo character selection; four starter identities are known and four recruits remain anonymous; native last-row focus")
	for id: String in CrewRoster.RECRUITS: CrewRoster.unlock(id)
	panel._refresh()
	panel.cards[0].grab_focus()
	await _capture("crew-top-"+suffix,"crew","All four recruit entitlements deliberately prepared in unsaved memory; actual first row of eight existing worker choices")
	panel.cards[7].grab_focus()
	panel.select_character("rika")
	await frames()
	check(panel.card_scroll.get_global_rect().encloses(panel.cards[7].get_global_rect()),"Native Rika portrait and controls remain completely visible")
	await _capture("crew-bottom-"+suffix,"crew","All eight genuine worker identities unlocked in isolated unsaved roster; eighth identity selected and native scroll reveals Oskar/Rika")
	game.hud._close_character_selection()
	await frames()
	game.hud._open_network()
	await frames()
	var lobby: Control = game.hud.network_panel
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	game.network.active = true
	game.network.is_host = true
	game.network.state = "lobby"
	lobby._refresh()
	await frames()
	lobby.character_buttons[7].grab_focus()
	await frames()
	check(lobby.character_scroll.get_global_rect().encloses(lobby.character_buttons[7].get_global_rect()),"Native lobby reveals eighth character above the scene/start footer")
	await _capture("lobby-eight-"+suffix,"lobby","Only authentication presentation is prepared; no network transport, room, hub request or socket exists. Eight genuine local roster entitlements show inside native lobby scroll")
	game.network.active = false
	game.network.state = "offline"
	game.hud.overlay = "menu"
	await frames()
	game.hud._toggle_audio()
	await frames()
	var options: Control = game.hud.options_panel
	options.tab_buttons[3].pressed.emit()
	options._open_music_lab(false)
	await frames(10)
	var lab: CanvasLayer = options.music_lab
	check(is_instance_valid(lab) and lab.preview_world.actors.size()==8 and not lab.preview_session.native_active,"Actual Options/Takt entry exposes eight silent genuine rigs")
	lab.interface_scroll.scroll_vertical = maxi(0,roundi(lab.preview_container.position.y)-12)
	await frames()
	check(lab.preview_view.canvas_transform.get_scale().x==lab.preview_view.canvas_transform.get_scale().y,"Music preview retains equal horizontal and vertical pixel scale")
	await _capture("music-eight-"+suffix,"music","Actual main-menu Options > Takt > Music lab with audition disabled; eight real WorkerVisual rigs, one silent clock, two balanced rows of four; no settings applied")
	lab.gains.rika.grab_focus()
	await frames()
	check(lab.interface_scroll.get_global_rect().encloses(lab.gains.rika.get_global_rect()),"Lower-row native Rika intensity control scrolls completely into view")
	await _capture("music-profiles-"+suffix,"music","Same native music lab after focusing Rika's lower-row profile slider; all eight profile controls retain their original settings and feedback behavior")
	lab.close()
	await frames(9)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	rendered = "--capture" in OS.get_cmdline_user_args()
	if rendered and DisplayServer.get_name()=="headless": quit(2); return
	if rendered: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled = false
	CrewRoster._loaded = true
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		for locale: String in ["de","en"]:
			var suffix := str(resolution.x)+"-"+locale
			await _fixture(resolution,locale)
			if "--world-only" in OS.get_cmdline_user_args():
				await _prepare_story()
				await _freeze_world_camera()
				await _capture("world-npc-"+suffix,"world","Actual quarry world, one worker 52px beside physical Oskar with real NPC focus; three-wave requirement unmet, waves held; follow camera snapped and held for capture; objective marker sits above the helmet")
				await _dispose()
				continue
			await _story_views(suffix)
			await _dispose()
			await _fixture(resolution,locale)
			await _rika_view(suffix)
			await _dispose()
			await _fixture(resolution,locale)
			await _crew_views(suffix)
			await _dispose()
	if "--world-only" in OS.get_cmdline_user_args():
		var world_report := {"checks":checks,"failures":failures,"captures":captures,"fixture":"Final native 720p/QHD-DE/EN world capture after objective-marker correction; physical NPC focus, 52px separation within actual 64px contact range; isolated unsaved profiles and muted master."}
		FileAccess.open(OUTPUT+"world-refresh.json",FileAccess.WRITE).store_string(JSON.stringify(world_report,"  "))
		var old_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"gallery.json"))
		if old_report is Dictionary:
			for entry: Dictionary in captures:
				for index in old_report.captures.size():
					if old_report.captures[index].id==entry.id: old_report.captures[index] = entry
			old_report.world_refresh = {"checks":checks,"failures":failures,"report":"world-refresh.json"}
			FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(old_report,"  "))
		view.queue_free()
		await process_frame
		print("SOLO STORY WORLD REFRESH: %d/%d checks passed; %d native captures" % [checks-failures,checks,captures.size()])
		quit(1 if failures else 0)
		return
	var report := {"checks":checks,"failures":failures,"rendered":rendered,"captures":captures,"fixture":"Actual Godot Compatibility SubViewport at 1280×720 and 2560×1440, both DE/EN. Real quarry/power-station NPC interactions and recruitment; named ancestor completion and three-wave evidence prepared for UI capture; both field records physically read. Eight real local worker identities, native scrolling character/lobby/music controls. No profiles, microphone, public or local transports; master muted and music audition disabled. Native layout evidence, not a performance benchmark."}
	FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Bunkercrew · Solo-Geschichte</title><style>body{margin:32px auto;max-width:1500px;padding:0 22px;background:#10191b;color:#e4e2cf;font:17px system-ui,sans-serif}p{line-height:1.5;color:#abb5a6}a{color:#dfbb79}figure{margin:38px 0}img{width:100%;display:block}figcaption{margin:12px 0;color:#b2bfac}</style><h1>Bunkercrew · Solo-Geschichte und acht Figuren</h1><p>Echte Godot-Ansichten des Logbuchs, körperlicher Begegnungen und ausdrücklich bestätigter Crewaufnahme. Deutsche und englische Ansichten bei 720p und QHD. Gesicherte Vorstationen, Wellenbelege und einzelne Fundtexte wurden für die UI-Prüfung vorbereitet; Materialverbrauch und Aufnahme laufen über den echten Controller. Alle Profile bleiben ungespeichert.</p><p><a href='gallery.json'>Prüfzustände und Ergebnisse</a> · <a href='../ui-test.json'>Tasten- und Controllerprüfung</a></p>"
	for entry: Dictionary in captures:
		html += "<figure><img loading='lazy' src='%s' alt='%s'><figcaption>%s · %s · %d×%d<br>%s</figcaption></figure>" % [entry.file,entry.id,entry.kind,entry.locale,entry.resolution[0],entry.resolution[1],entry.prepared]
	html += "</html>"
	FileAccess.open(OUTPUT+"index.html",FileAccess.WRITE).store_string(html)
	view.queue_free()
	await process_frame
	print("SOLO STORY GALLERY: %d/%d checks passed; %d native captures" % [checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
