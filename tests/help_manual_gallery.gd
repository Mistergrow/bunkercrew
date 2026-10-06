extends SceneTree
## True Compatibility rendering at four native output sizes. Main-menu pages
## retain the selected landscape; in-game help retains its paused actual world.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/help_manual_catalog.gd")
const L := preload("res://scripts/locale_text.gd")
const OUTPUT := "res://artifacts/archive-review/guide/gallery/"
var output_directory := OUTPUT
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
	print("MANUAL VIEW %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int=5) -> void:
	for unused in count: await process_frame

func _fixture(resolution: Vector2i,locale: String) -> void:
	view.size = resolution
	L.set_locale(locale,false)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.hud._layout_viewport()
	game.hud.main_menu_panel.restore_navigation({"environment":"mountain_pass","focus":"help"})
	game.hud._toggle_help()
	await frames()

func _dispose() -> void:
	check(not game.network.active and not game.microphone.capturing,"Native capture leaves transports and microphone closed")
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled,"Native capture leaves all saved profiles untouched")
	paused = false
	check(await Cleanup.free_scene(game,self),"Native capture releases its scene and audio handles")
	game = null

func _capture(id: String,page: String,role: String,at_end: bool=false) -> void:
	var panel: Control = game.hud.help_panel
	panel.select_page(page)
	await frames()
	panel.page_buttons[panel._page_index()].grab_focus()
	panel.reading_scroll.scroll_vertical = roundi(panel.reading_scroll.get_v_scroll_bar().max_value) if at_end else 0
	await frames()
	var bounds: Rect2 = game.hud.screen_rect()
	check(bounds.encloses(panel.reading_scroll.get_rect()),id+" reader fits the actual viewport")
	check(bounds.encloses(panel.back_button.get_rect()) and bounds.encloses(panel.options_button.get_rect()),id+" footer actions fit the actual viewport")
	check(panel.reading_content.size.x<=panel.reading_scroll.size.x+1,id+" translated prose stays inside the reading column")
	var labels: Array[Node] = panel.reading_content.find_children("*","Label",true,false)
	var all_text := true
	for label: Label in labels:
		if not label.visible: continue
		all_text = all_text and label.max_lines_visible==-1 and not label.clip_text and label.get_line_count()>0
	check(all_text,id+" native labels retain every line")
	var filename := id+".png"
	if rendered:
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		check(picture.get_size()==view.size and picture.save_png(output_directory+filename)==OK,id+" captures true native "+str(view.size))
	var state := {"id":id,"file":filename,"page":page,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"role":role,"scroll":panel.reading_scroll.scroll_vertical,"max_scroll":roundi(panel.reading_scroll.get_v_scroll_bar().max_value-panel.reading_scroll.get_v_scroll_bar().page),"sections":Catalog.sections(page,game).size(),"body_font":18,"heading_font":22,"canvas_scale":game.hud.canvas.scale.x,"prepared":{"started":game.started,"players":game.players.size(),"environment":"mountain_pass","wave_held":game.started,"profile_saving":false,"master_muted":true}}
	captures.append(state)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--artifact-dir="):
			output_directory = argument.trim_prefix("--artifact-dir=")
			if not output_directory.begins_with("res://artifacts/") or not output_directory.ends_with("/"): quit(2); return
	rendered = "--capture" in OS.get_cmdline_user_args()
	if rendered and DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	AudioServer.set_bus_mute(0,true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	for locale: String in ["de","en"]:
		await _fixture(Vector2i(1920,1080),locale)
		for entry: Dictionary in Catalog.PAGES:
			await _capture("manual-"+str(entry.id)+"-"+locale,str(entry.id),"Actual menu landscape; no worker, no mission state prepared")
		await _capture("manual-controls-end-"+locale,"controls","Bottom of complete native control reference",true)
		await _dispose()
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(2560,1440)]:
		for locale: String in ["de","en"]:
			await _fixture(resolution,locale)
			await _capture("manual-workshop-"+str(resolution.x)+"-"+locale,"workshop","Actual native menu at alternate viewport")
			if "--p1-entry" in OS.get_cmdline_user_args():
				await _capture("manual-first-shift-"+str(resolution.x)+"-"+locale,"first_shift","Current short starter at alternate native viewport")
				await _capture("manual-travel-"+str(resolution.x)+"-"+locale,"travel","Current tire roles at alternate native viewport")
			await _dispose()
	await _fixture(Vector2i(1920,1080),"de")
	game.hud._close_help()
	await frames()
	game.start_scenario(2,{"environment":"mountain_pass","position":"center","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.players[0].inventory["ore"] = game.players[0].capacity()
	await frames()
	game.hud._toggle_help()
	await frames()
	check(game.hud.help_panel._landscape.is_empty(),"In-game manual retains the actual bunker and creates no menu landscape")
	check(game.hud.help_panel._advice.id=="inventory_full" and game.hud.help_panel.context_button.visible,"Actual prepared carried load presents Production advice")
	await _capture("manual-inventory-advice-de","first_shift","Two actual mountain-pass workers; first worker inventory filled for the advice fixture; waves held")
	L.set_locale("en",false)
	await frames()
	await _capture("manual-inventory-advice-en","first_shift","Same actual paused mountain-pass world with translated current advice")
	await _dispose()
	var report := {"checks":checks,"failures":failures,"rendered":rendered,"captures":captures,"fixture":"Actual Godot Compatibility SubViewport. Menu at 1920×1080, 1280×720, 1440×900 and 2560×1440; selected mountain_pass. Final images use a paused real two-worker scenario and prepared carried ore to inspect current advice. No shaders or images replaced; no public sockets, microphone or profile writes; master muted. Screens are layout evidence, not an FPS benchmark."}
	FileAccess.open(output_directory+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Bunkercrew · Feldhandbuch</title><style>body{margin:32px auto;max-width:1400px;padding:0 22px;background:#0f1719;color:#e4e2cf;font:17px system-ui,sans-serif}p{line-height:1.5;color:#abb5a6}a{color:#dfbb79}figure{margin:38px 0}img{width:100%;display:block;border:0}figcaption{margin:12px 0;color:#b2bfac}code{color:#dfbb79}</style><h1>Bunkercrew · Feldhandbuch</h1><p>Sechs native Seiten mit echten Rezepten, Baukosten, Tasten und eigener Hilfestellung. Deutsche und englische Spielansichten bei vier Auflösungen. Die letzten Ansichten zeigen einen vorbereiteten, tatsächlich pausierten Zweispieler-Bunker. Das Inventar ist für die Hilfestellung gefüllt; die Wellen sind angehalten. Kein Profil wird gespeichert.</p><p><a href='gallery.json'>Prüfzustände und Ergebnisse</a> · <a href='../manual-test.json'>Navigationstest</a></p>"
	for entry: Dictionary in captures:
		html += "<figure><img loading='lazy' src='%s' alt='%s'><figcaption>%s · %s · %d×%d · Leseposition %d/%d</figcaption></figure>" % [entry.file,entry.id,entry.page,entry.locale,entry.resolution[0],entry.resolution[1],entry.scroll,entry.max_scroll]
	html += "</html>"
	FileAccess.open(output_directory+"index.html",FileAccess.WRITE).store_string(html)
	view.queue_free()
	await process_frame
	print("HELP MANUAL GALLERY: %d/%d checks passed; %d native captures" % [checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
