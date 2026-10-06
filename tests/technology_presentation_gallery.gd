extends "res://tests/technology_presentation_test.gd"
## Native original research UI and options reference at identical prepared states.
const CAPTURE_SIZES := [Vector2i(960,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var output_directory := "res://artifacts/technology-style-20261005/gallery/"
var phase := "baseline"
var screens: Array[Dictionary] = []

func _controls() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Array[Node] = [game.hud.canvas]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children(true))
		if not node is Control or not node.is_visible_in_tree(): continue
		if not node is BaseButton and not node is Range: continue
		var bounds := canvas_bounds(node)
		var ancestor: Node = node.get_parent()
		while ancestor!=null:
			if ancestor is Control and ancestor.clip_contents:
				bounds = bounds.intersection(canvas_bounds(ancestor))
			ancestor = ancestor.get_parent()
		if not bounds.has_area(): continue
		var label := ""
		var width := 0.0
		var available: float = node.size.x
		if node is Button:
			label = node.text
			width = node.get_theme_font("font").get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x
			var style: StyleBox = node.get_theme_stylebox("normal")
			available -= style.get_content_margin(SIDE_LEFT)+style.get_content_margin(SIDE_RIGHT)
		result.append({"path":str(view.get_path_to(node)),"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"label":label,"label_width":width,"available":available,"label_fits":width<=available+1.0,"focus":node.has_focus(),"disabled":node.disabled if node is BaseButton else false})
	return result

func _capture(id: String) -> void:
	await frames(4)
	var controls := _controls()
	var label := "%dx%d-%s-%s"%[view.size.x,view.size.y,L.current_locale(),id]
	for control: Dictionary in controls:
		var values: Array = control.rect
		var bounds := Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
		check(view.get_visible_rect().grow(1.0).encloses(bounds),label+": actual native control is inside the screen")
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size()==view.size and picture.save_png(output_directory+phase+"/"+label+".png")==OK,label+": actual native framebuffer capture saved")
	var focused := view.gui_get_focus_owner()
	var entry := {"screen":id,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"file":phase+"/"+label+".png","overlay":game.hud.overlay,"points":game.upgrades.points,"owned":game.upgrades.owned.keys(),"wave":game.rounds.wave,"controls":controls,"focus":str(view.get_path_to(focused)) if is_instance_valid(focused) else ""}
	if game.hud.overlay=="upgrades":
		var panel: Control = game.hud.upgrade_panel
		entry.merge({"category":panel.selected_category,"selected":panel.selected_id,"scroll":panel.tree_scroll.scroll_vertical,"rows":panel._visible_entries.size(),"medic_dance_level":game.upgrades.medic_dance_level()})
	screens.append(entry)
	check(not game.network.active and not game.microphone.capturing,label+": capture opens neither connection nor microphone")

func _prepared_fixture(resolution: Vector2i,locale: String) -> void:
	await fixture(resolution,locale)
	var panel: Control = game.hud.upgrade_panel
	for category in UpgradeSystem.CATEGORIES.size():
		panel.select_category(category)
		panel._select(["precision_lines","weapon_capacitor","bunker_dance_5","convoy_stabilizer"][category])
		await _capture("research-"+str(category))
	# Additional requested reproduction: first weapons research, four points.
	seed_research(1,4,[])
	panel._select("weapon_handling")
	await _capture("first-weapons-wave1")
	seed_research()
	for id: String in CampaignCatalog.MEDIC_UPGRADES:
		panel._select(id)
		await frames()
		check(not panel.purchase_button.disabled,"Actual affordable software successor is enabled: "+id)
		panel.purchase_button.pressed.emit()
		check(game.upgrades.has_upgrade(id),"Actual software research is paid: "+id)
	panel._select("bunker_dance_5")
	check(game.upgrades.points==5 and game.upgrades.medic_dance_level()==5,"Prepared native paid software state conserves14 of19 points")
	await _capture("san-five-earned")
	game.campaign.active = true
	game.campaign.expedition.vehicle.unlocked = true
	game.campaign.expedition.stage = "preparation"
	seed_research(16,19,PREPARED_OWNED+["convoy_mg","convoy_reload"])
	panel._select("convoy_stabilizer")
	check(not panel.purchase_button.disabled,"Actual garage state enables its affordable vehicle successor")
	await _capture("vehicle-preparation")
	game.campaign.active = false
	game.hud.audio_return_overlay = "upgrades"
	game.hud.overlay = "audio"
	game.hud._apply_overlay_pause()
	await frames()
	game.hud.options_panel.select_tab(0)
	await _capture("reference-options")
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled,"Gallery does not persist options, researches or campaign fixtures")
	await retire()

func _write_gallery() -> void:
	var combined := screens.duplicate()
	var other := "baseline" if phase=="final" else "final"
	var path := output_directory+other+"/report.json"
	if FileAccess.file_exists(path):
		var previous = JSON.parse_string(FileAccess.get_file_as_string(path))
		if previous is Dictionary:
			combined.append_array(previous.get("screens",[]))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Technik</title><style>body{background:#111c19;color:#dddcc9;font:15px system-ui;margin:24px}a{color:#d6ad64}select{padding:8px;margin:4px;background:#26342d;color:#dddcc9;border:1px solid #687168}nav{position:sticky;top:0;padding:8px;background:#111c19}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:20px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}figure[hidden]{display:none}</style><h1>Technik im gemeinsamen Optionen-/Lobby-Stil</h1><p>Echte Hauptszene und native Techniksteuerung in DE/EN: Welle16,19 Technikpunkte und fünf vorhandene Forschungen. Vier Forschungsbereiche, fünf tatsächlich bezahlte SAN-Softwarestufen, freigeschaltete Fahrzeugvorbereitung und Welle1 mit4 Punkten. Die Optionen dienen als native Stilreferenz. Keine HTML-Mocks; vorbereitete Zustände, kein Profil- oder Speicherstandwechsel.</p><nav><label>Auflösung <select id='size' onchange='filter()'><option>960</option><option selected>1280</option><option>1920</option><option>2560</option></select></label><label>Sprache <select id='lang' onchange='filter()'><option selected>de</option><option>en</option></select></label><label>Ansicht <select id='screen' onchange='filter()'><option value='research-0'>Basis</option><option value='research-1'>Waffen</option><option value='research-2'>Besatzung</option><option value='research-3'>Fahrzeug gesperrt</option><option value='first-weapons-wave1'>Welle1/Waffen</option><option value='san-five-earned'>SAN-1 Stufe5 bezahlt</option><option value='vehicle-preparation'>Fahrzeugvorbereitung</option><option value='reference-options'>Optionenreferenz</option></select></label><a href='"+phase+"/report.json'>Zustände und Kontrollmesswerte</a></nav><main>"
	for entry: Dictionary in combined:
		var stage: String = str(entry.file).get_slice("/",0)
		html += "<figure data-size='%d' data-lang='%s' data-screen='%s'><a href='%s'><img loading='lazy' src='%s' alt='Native Technikansicht'></a><figcaption>%s · %s · %s · %d×%d · TP%d</figcaption></figure>"%[entry.resolution[0],entry.locale,entry.screen,entry.file,entry.file,stage,entry.screen,entry.locale.to_upper(),entry.resolution[0],entry.resolution[1],entry.points]
	html += "</main><script>function filter(){const a=document.getElementById('size').value,b=document.getElementById('lang').value,c=document.getElementById('screen').value;document.querySelectorAll('figure').forEach(e=>e.hidden=e.dataset.size!==a||e.dataset.lang!==b||e.dataset.screen!==c)}filter()</script></html>"
	var file := FileAccess.open(output_directory+"index.html",FileAccess.WRITE)
	file.store_string(html)
	file.close()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output="):
			output_directory = argument.trim_prefix("--output=").simplify_path().trim_suffix("/")+"/"
	if phase not in ["baseline","final"]:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory+phase))
	AudioServer.set_bus_mute(0,true)
	for resolution: Vector2i in CAPTURE_SIZES:
		for locale: String in ["de","en"]:
			await _prepared_fixture(resolution,locale)
	var file := FileAccess.open(output_directory+phase+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phase":phase,"checks":checks,"failures":failures,"rendered":true,"screens":screens,"prepared":"Actual Sector07 solo, wave16 TP19 plus five research entitlements, paused real UpgradePanel. Native SubViewports without2Doverride, DE/EN,960x600/1280x720/1920x1080/2560x1440; actual paid SAN progression and staged original unlocked garage. Live world remains underneath both options and technology. Master muted, persistence disabled, no transport/microphone."},"  "))
	file.close()
	_write_gallery()
	print("TECHNOLOGY STYLE GALLERY %s: %d/%d checks; %d native captures"%[phase,checks-failures,checks,screens.size()])
	quit(1 if failures else 0)
