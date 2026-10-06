extends SceneTree
## Real expanded scenes with prepared room materials and assembled dome panes.
## These fixtures inspect presentation; gameplay progression is not simulated.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var view: SubViewport
var output := "res://artifacts/style-layout/after"
var captures: Array[Dictionary] = []
var failures := 0

class EquipmentGrid extends Node2D:
	const KINDS := ["shield_guard","lancer","sniper","demolisher","repair_crawler","bastion"]
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("111b20"))
		Art.text(self,Vector2(30,45),"MASCHINEN / GEHÄUSE UND WAFFENMODULE",25,Art.LIGHT)
		Art.text(self,Vector2(30,73),"Echte Gegnerobjekte · vorbereitete Angriffspose · 1,8× vergrößert",14,Art.MUTED)
		for index in 6:
			var x := 25+(index%3)*530
			var y := 100+floori(index/3.0)*385
			draw_rect(Rect2(x,y,505,365),Color("222d2c"))
			Art.text(self,Vector2(x+20,y+30),str(EnemyCatalog.profile(KINDS[index]).label),18,Art.LIGHT)
			draw_line(Vector2(x+20,y+335),Vector2(x+485,y+335),Color("73735f"),2)

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 8) -> void:
	for unused in count:
		await process_frame

func capture(game: Node, label: String) -> void:
	game.player_camera.update_view(0, true)
	await frames(12)
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var filename := str(game.scenario_options.position) + "-" + label + ".png"
	if picture.save_png(output + "/" + filename) != OK or picture.get_size() != view.size:
		failures += 1
	var actors: Array[Dictionary] = []
	for object in get_nodes_in_group("interactables"):
		if object.get("game") != game:
			continue
		var at: Vector2 = object.interaction_point() if object.has_method("interaction_point") else object.global_position
		var screen: Vector2 = view.get_final_transform() * (view.get_canvas_transform() * at)
		actors.append({"script":object.get_script().resource_path,"kind":str(object.get("kind")),"world":[at.x,at.y],"screen":[screen.x,screen.y]})
	captures.append({"file":filename,"wave":game.rounds.wave,"zoom":game.camera.zoom.x,"camera":[game.camera.position.x,game.camera.position.y],"room_left":game.scenario_bunker.room_left,"room_right":game.scenario_bunker.room_right,"flak_console":[game.flak_station.position.x,game.flak_station.position.y],"dome_console":[game.dome.site.x,game.dome.site.y],"interactables":actors})
	print("STYLE_LAYOUT_CAPTURE ", filename)

func prepare(game: Node, position: String, wave: int = 16) -> void:
	game.start_scenario(2, {"environment":"ash_foundry","build_type":"bastion","position":position})
	game.rounds.set_process(false)
	game.rounds.wave = wave
	game.rounds.phase = "build"
	game.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
		worker.focus = null
	for index in ScenarioRoomCatalog.ROOMS.size():
		if wave < 16:
			break
		if not await preload("res://tests/scenario_excavation_fixture.gd").build_room(game,index,game.players[0]):
			failures += 1
	if wave >= 6:
		game.flak_station.unlock()
		game.flak_station._complete()
	if wave >= 16:
		game.dome.unlock()
		game.dome.frame_built = true
		game.dome.built = true
		for pane in game.dome.segments:
			pane.set_frame()
			pane.glaze()
	game.dome._process(0)
	game.notice_time = 0
	game.dialogue.reset()
	game.scenery.elapsed = 6.0
	await frames()
	for field in game.scenario_bunker.fields:
		if field.remaining_count() != 12:
			failures += 1
			push_error("Prepared field lost real mineable cells before capture")

func staged_view(game: Node, center: Vector2, zoom: float, first: Vector2, second: Vector2) -> void:
	game.players[0].position = first
	game.players[1].position = second
	for worker in game.players:
		worker.focus = null
	game.player_camera.mode = "overview"
	game.player_camera.view_zoom = zoom
	game.camera_target_center = center
	game.camera_target_zoom = 1.0

func details(game: Node) -> void:
	var left: float = game.scenario_bunker.room_left
	staged_view(game,Vector2(left+320,140),1.25,Vector2(left+130,245),Vector2(left+214,245))
	game.players[0].focus = game.flak_station
	await capture(game,"wave-16-roof-control")
	staged_view(game,Vector2(left+355,340),2.0,Vector2(left+428,430),Vector2(left+480,430))
	game.players[0].focus = game.dome
	await capture(game,"dome-console-detail")
	for depth in [0,1,2]:
		var floor_y := ScenarioRoomCatalog.floor_y(depth)
		staged_view(game,Vector2(left+330,floor_y-88),2.0,Vector2(left+180,floor_y),Vector2(left+370,floor_y))
		for station in get_nodes_in_group("interactables"):
			if station is RecipeStation and absf(station.position.y-floor_y)<1:
				station.set_process(false)
				station.working = true
				station.elapsed = 3.8
				station.production_time = station.duration()*.45
		await capture(game,"production-depth-"+str(depth+1))
	staged_view(game,Vector2(left+330,365),2.5,Vector2(left+220,430),Vector2(left+510,430))
	game.medic.position = Vector2(left+345,430)
	game.medic.logistics_cargo = "steel"
	game.medic.queue_redraw()
	await capture(game,"support-cargo-detail")
	game.medic.logistics_cargo = ""
	game.medic.climbing = true
	game.medic.position = Vector2(left+54,362)
	game.medic._motion_phase = 2.1
	game.medic.queue_redraw()
	staged_view(game,Vector2(left+185,352),2.5,Vector2(left+180,430),Vector2(left+320,430))
	await capture(game,"support-ladder-detail")
	game.medic.climbing = false
	game.medic.position = Vector2(left+315,430)
	game.players[0].position = Vector2(left+345,430)
	game.medic.target = game.players[0]
	game.medic.treating = true
	game.medic.treatment_progress = .5
	game.medic.queue_redraw()
	staged_view(game,Vector2(left+330,365),2.5,Vector2(left+345,430),Vector2(left+510,430))
	await capture(game,"support-treatment-detail")
	game.medic.treating = false
	for index in [1,4,10]:
		game.dome.segments[index].take_damage(100000)
	game.dome.front.take_damage(350)
	game.dome._process(0)
	staged_view(game,Vector2(left+320,140),1.25,Vector2(left+428,430),Vector2(left+214,245))
	await capture(game,"wave-16-broken-dome")

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	if "--before" in OS.get_cmdline_user_args():
		output = "res://artifacts/style-layout/before"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	view = SubViewport.new()
	view.size = Vector2i(2560, 1440)
	view.size_2d_override = Vector2i(1600, 900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	LocaleText.set_locale("de", false)
	for position in ["left", "center", "right"]:
		if "--machines-only" in OS.get_cmdline_user_args():
			break
		var game = load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		await prepare(game, position)
		var room_left: float = game.scenario_bunker.room_left
		game.players[0].position = Vector2(room_left + 425, 430)
		game.players[1].position = Vector2(room_left + 475, 430)
		game.player_camera.mode = "follow"
		game.player_camera.view_zoom = 1.25
		await capture(game, "control-room")
		game.player_camera.mode = "overview"
		game.player_camera.view_zoom = .65
		game.camera_target_center = Vector2(room_left + 320, 620)
		game.camera_target_zoom = 1.0
		await capture(game, "expanded-overview")
		if position == "center" and "--before" not in OS.get_cmdline_user_args():
			await details(game)
		if not await Cleanup.free_scene(game, self):
			failures += 1
	if "--before" not in OS.get_cmdline_user_args() and "--machines-only" not in OS.get_cmdline_user_args():
		for wave in [1,6]:
			var game = load("res://scenes/main.tscn").instantiate()
			view.add_child(game)
			await prepare(game,"center",wave)
			var left: float = game.scenario_bunker.room_left
			staged_view(game,Vector2(left+320,185),1.25,Vector2(left+130,245),Vector2(left+214,245))
			if wave >= 6:
				game.players[0].focus = game.flak_station
			await capture(game,"wave-"+str(wave)+"-roof-control")
			if not await Cleanup.free_scene(game,self):
				failures += 1
	if "--before" not in OS.get_cmdline_user_args():
		var gallery := EquipmentGrid.new()
		view.add_child(gallery)
		ThemeDB.fallback_font = load("res://assets/mono.ttf")
		for index in 6:
			var actor = load("res://scenes/enemy.tscn").instantiate()
			actor.kind = EquipmentGrid.KINDS[index]
			actor.show_status_labels = false
			actor.position = Vector2(280+(index%3)*530,435+floori(index/3.0)*385)
			actor.scale = Vector2.ONE*1.8
			gallery.add_child(actor)
			actor.set_physics_process(false)
			actor.set_process(false)
			actor.motion.set_process(false)
			actor.motion.automatic = false
			actor.motion.play("brace",true)
			actor.motion.advance(.36)
			var target := Node2D.new()
			target.position = actor.position+Vector2(-200,-40)
			gallery.add_child(target)
			actor.target = target
			actor.age = 3.8
			actor.windup = .4
			actor._pose_parts()
			actor.queue_redraw()
		await frames(12)
		await RenderingServer.frame_post_draw
		if view.get_texture().get_image().save_png(output+"/machine-equipment.png")!=OK:
			failures += 1
		captures.append({"file":"machine-equipment.png","fixture":"Six actual enemy scenes, explicit brace pose, no combat simulation","scale":1.8,"kinds":EquipmentGrid.KINDS})
		if not await Cleanup.free_scene(gallery,self):
			failures += 1
	view.queue_free()
	await frames()
	var file := FileAccess.open(output + ("/machines.json" if "--machines-only" in OS.get_cmdline_user_args() else "/captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"resolution":[2560,1440],"logical_resolution":[1600,900],"renderer":RenderingServer.get_current_rendering_driver_name(),"fixture":"Ash foundry, bastion, local co-op, prepared wave16 for six matching before/after views. All four rooms use prepared material buffers and actual build/cure API; Flak I assembled through completion API; all dome panes framed/glazed directly. Extra wave1 and6 views use fresh starting scenes and prepared Flak I only at wave6. Machine work, medic cargo/climbing/treatment explicitly staged for detail inspection; broken panes damaged through take_damage(). No claim of simulated progression. Actors/waves frozen, scenery/weather live, notices/dialogue cleared. Same cameras and actor positions in the six before/after pairs.","captures":captures,"failures":failures}, "\t"))
	print("STYLE_LAYOUT_PREVIEW ", captures.size(), " captures, failures=", failures)
	quit(1 if failures else 0)
