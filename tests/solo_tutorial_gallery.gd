extends SceneTree
## Native Compatibility views of a prepared actual solo world. Guidance reads
## real stations and camera transforms; only lesson records/phase are prepared.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
const NetInput := preload("res://scripts/network_input.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
const OUTPUT := "res://artifacts/solo-tutorial-20261005/gallery/"
var output_directory := OUTPUT
var view: SubViewport
var game
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var rendered := false
var _pad_motion: InputEventJoypadMotion

func _initialize() -> void:
	# The developer may be running a separate playtest on the same display.
	# Native gallery work must neither steal its focus nor change its settings.
	root.unfocusable = true
	root.position = Vector2i(-10000,-10000)
	_run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("TUTORIAL VIEW %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func _refresh() -> void:
	game.solo_tutorial._process(.25)
	game.hud.solo_tutorial_panel.refresh_view()

func _device(controller: bool) -> void:
	if controller:
		_pad_motion = InputEventJoypadMotion.new()
		_pad_motion.device = 0
		_pad_motion.axis = JOY_AXIS_LEFT_X
		_pad_motion.axis_value = .7
		# Hold the real input through the rendered capture. An unfocusable
		# private window still sees the desktop pointer move during a playtest;
		# releasing before drawing would correctly select the mouse again.
		Input.parse_input_event(_pad_motion)
		Input.flush_buffered_events()
		NetInput._primary_mouse_aim(game)
		_refresh()
	else:
		if _pad_motion!=null:
			var release_motion := InputEventJoypadMotion.new()
			release_motion.device = _pad_motion.device
			release_motion.axis = _pad_motion.axis
			release_motion.axis_value = 0
			Input.parse_input_event(release_motion)
			_pad_motion = null
		var event := InputEventKey.new()
		event.keycode = KEY_D
		event.physical_keycode = KEY_D
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		NetInput._primary_mouse_aim(game)
		var release_key := InputEventKey.new()
		release_key.keycode = KEY_D
		release_key.physical_keycode = KEY_D
		release_key.pressed = false
		Input.parse_input_event(release_key)
		Input.flush_buffered_events()
		_refresh()

func _fixture(resolution: Vector2i,locale: String) -> void:
	view.size = resolution
	L.set_locale(locale,false)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(6)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	for worker in game.players: worker.set_physics_process(false)
	game.notice_time = 0
	game.hud.combat_overlay.banners.clear()
	game.hud.combat_overlay.boss.clear()
	game.hud._layout_viewport()
	await frames()
	_refresh()

func _capture(id: String,role: String) -> void:
	_refresh()
	await frames()
	var card: Control = game.hud.solo_tutorial_panel
	var layout: Dictionary = card.card_layout()
	var state := {"id":id,"file":id+".png","resolution":[view.size.x,view.size.y],"locale":L.current_locale(),"role":role,"prepared":{"environment":"ash_foundry","players":1,"worker_physics_held":true,"waves_held":true,"dialogue_held":true,"profile_saving":false,"master_muted":true},"canvas_scale":game.hud.canvas.scale.x,"step":str(card._view.get("id","")),"body":str(card._view.get("body","")),"target":[],"card":[],"marker":card.marker_layout()}
	if game.hud.overlay.is_empty():
		if id.ends_with("-move-controller"):
			check(Input.get_action_strength("primary_pad_right")>.1 and not NetInput.mouse_aim(game.players[0]),id+" uses actual held and flushed primary controller input")
			check(str(card._view.get("body","")).contains(L.text("Linker Stick")) and str(card._view.get("body","")).contains(L.text("Pause → Handbuch")) and InputLabels.action(game.players[0],"jump")=="A",id+" rendered lesson retains actual controller movement, jump and manual labels")
		elif id.ends_with("-move-keyboard"):
			check(not str(card._view.get("body","")).contains(L.text("Linker Stick")) and str(card._view.get("body","")).contains("F1"),id+" rendered lesson retains actual keyboard movement and manual labels")
		check(not layout.is_empty(),id+" has a real current lesson")
		if not layout.is_empty():
			var bounds: Rect2 = layout.rect
			check(game.hud.screen_rect().encloses(bounds),id+" card fits the full native viewport")
			check(float(layout.body_size)*game.hud.canvas.scale.x>=12.99,id+" body retains at least13outputpixels")
			check(float(layout.secondary_size)*game.hud.canvas.scale.x>=10.99,id+" secondary guidance retains at least11outputpixels")
			state.card = [bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]
			for worker: Node2D in game.players:
				var head: Vector2 = game.hud.world_to_ui(worker.global_position+Vector2(-26,-70))
				var foot: Vector2 = game.hud.world_to_ui(worker.global_position+Vector2(26,10))
				check(not bounds.intersects(Rect2(head,foot-head).abs().grow(8)),id+" leaves the actual worker unobscured")
		var target: Vector2 = game.solo_tutorial.target_position()
		if target.is_finite():
			var projected: Vector2 = game.hud.world_to_ui(target)
			state.target = [projected.x,projected.y]
			if not layout.is_empty(): check(not layout.rect.grow(6).has_point(projected),id+" leaves its actual interaction target visible")
	else:
		var manual: Control = game.hud.help_panel
		check(layout.is_empty(),id+" suppresses the gameplay card below the manual")
		check(game.hud.screen_rect().encloses(manual.reading_scroll.get_rect()),id+" native reader stays inside the viewport")
		check(manual.reading_content.size.x<=manual.reading_scroll.size.x+1,id+" complete localized tutorial controls wrap inside the reader")
		state["manual_actions"] = [manual.tutorial_start_button.text,manual.tutorial_stop_button.text,manual.tutorial_restart_button.text]
	if rendered:
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		check(picture.get_size()==view.size and picture.save_png(output_directory+str(state.file))==OK,id+" saves the actual native rendered pixels")
	captures.append(state)

func _dispose() -> void:
	check(not game.network.active and not game.microphone.capturing,"Gallery leaves network and microphone closed")
	paused = false
	check(await Cleanup.free_scene(game,self),"Gallery frees actual world and playback handles")
	game = null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	rendered = "--capture" in OS.get_cmdline_user_args()
	if rendered and DisplayServer.get_name()=="headless": quit(2); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--artifact-dir="):
			output_directory = argument.trim_prefix("--artifact-dir=")
			if not output_directory.begins_with("res://artifacts/") or not output_directory.ends_with("/"): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	AudioServer.set_bus_mute(0,true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	for resolution: Vector2i in [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080),Vector2i(2560,1440)]:
		for locale: String in ["de","en"]:
			await _fixture(resolution,locale)
			var prefix := "tutorial-"+str(resolution.x)+"-"+locale
			_device(false)
			await _capture(prefix+"-move-keyboard","Fresh guide in an actual solo bunker; keyboard input route")
			_device(true)
			await _capture(prefix+"-move-controller","Same real solo world; actual joypad motion held through capture selects the controller input route while worker physics is frozen")
			_device(false)
			game.solo_tutorial.records.mark("move")
			_refresh()
			await _capture(prefix+"-material","Movement lesson record prepared as learned; guide selects a real remaining supply and projects its target")
			if resolution==Vector2i(1920,1080) and locale=="de":
				var target: Vector2 = game.solo_tutorial.target_position()
				if target.is_finite():
					game.player_camera.set_process(false)
					game.camera.zoom = Vector2.ONE*2.0
					var desired_ui: Vector2 = game.hud.screen_rect().position+Vector2(150,170)
					var desired_screen: Vector2 = game.hud.canvas.get_global_transform_with_canvas()*desired_ui
					game.camera.position = target-(desired_screen-Vector2(view.size)*.5)/game.camera.zoom
					game.camera.force_update_scroll()
					await _capture(prefix+"-material-close-edge","Actual supply projected into the preferred left card slot at close zoom; tutorial must choose an unobstructed alternate edge")
					game.player_camera.set_process(true)
			game.hud._toggle_help()
			await frames()
			game.hud.help_panel.select_page("first_shift")
			await _capture(prefix+"-manual","Actual F1 reader over the locally paused bunker with native tutorial control actions")
			await _dispose()
	var report := {"checks":checks,"failures":failures,"rendered":rendered,"captures":captures,"fixture":"Actual Godot Compatibility SubViewport; offline solo Aschewerk. Four native resolutions and DE/EN; actual keyboard/joypad events select the input route. Movement records are prepared for material targets, and waves/worker physics/dialogue are held for layout evidence. No public network, microphone, player-profile writes or FPS claims. Unfocusable offscreen gallery window avoids interrupting a separate playtest."}
	FileAccess.open(output_directory+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var html := "<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Bunkercrew · Solo-Tutorial</title><style>body{max-width:1440px;margin:32px auto;padding:0 20px;background:#111a18;color:#e0decb;font:17px system-ui,sans-serif}p{line-height:1.5;color:#a1a18c}a{color:#d9ac60}figure{margin:36px 0}img{width:100%;display:block}figcaption{margin:10px 0;color:#a1a18c}</style><h1>Bunkercrew · Solo-Tutorial</h1><p>Native Spielansichten der geführten Solo-Schicht und der Handbuch-Aktionen. Deutsch und Englisch, Tastatur und Controller bei vier Auflösungen. Für den Layoutvergleich sind Wellen, Figurenphysik und Dialoge angehalten; die Materialansichten haben eine vorbereitete Lernmarkierung für Bewegung. Kein Spielerprofil wird gespeichert.</p><p><a href='gallery.json'>Prüfzustände und Ergebnisse</a> · <a href='../ui-test.json'>Bedienungsprüfung</a></p>"
	for entry: Dictionary in captures:
		html += "<figure><img loading='lazy' src='%s' alt='%s'><figcaption>%s · %d×%d · %s</figcaption></figure>" % [entry.file,entry.id,entry.locale,entry.resolution[0],entry.resolution[1],entry.role]
	FileAccess.open(output_directory+"index.html",FileAccess.WRITE).store_string(html+"</html>")
	view.queue_free()
	await process_frame
	print("SOLO TUTORIAL GALLERY: %d/%d checks passed; %d native views" % [checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
