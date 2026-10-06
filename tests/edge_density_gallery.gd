extends SceneTree
## Native prepared views of the existing legal edges and cosmetic outskirts.
## This fixture compares frozen source versions; it does not fabricate terrain.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/edge-density-20261005"
const SIZE := Vector2i(1920,1080)
const DETAIL_ENVIRONMENTS: Array[String] = ["sector07","ash_foundry","mountain_pass","overgrown_steelworks","frozen_rail_yard"]
var checks := 0
var failures := 0
var stage := "before"
var capture_enabled := false
var records: Array[Dictionary] = []
var view: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child: Node in node.get_children(): freeze(child)

func capture(path: String) -> void:
	if not capture_enabled: return
	for index in 3: await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size()==SIZE,"native image is exactly 1920x1080")
	check(picture.save_png(path)==OK,"save "+path.get_file())

func _percentile(samples: Array[int],fraction: float) -> int:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size())*fraction)-1,0,sorted.size()-1)]

func _ecology_sample(vegetation: Node2D) -> Dictionary:
	var outskirts: Node2D = vegetation.outskirts
	var bounds: Rect2 = vegetation.get_global_transform_with_canvas().affine_inverse()*vegetation.get_viewport_rect()
	var rebuilds := int(outskirts.diagnostics().rebuilds)
	var samples: Array[int] = []
	for index in 120:
		var start := Time.get_ticks_usec()
		outskirts.update_view(bounds,false,37.5+float(index)*.05,.7)
		samples.append(Time.get_ticks_usec()-start)
	check(int(outskirts.diagnostics().rebuilds)==rebuilds,"static camera wind ticks reuse meshes")
	var full: Dictionary = outskirts.diagnostics()
	outskirts.update_view(bounds,true,44.0,.7)
	var reduced: Dictionary = outskirts.diagnostics()
	check(int(reduced.rebuilds)==rebuilds,"reduced effects switch reuses prepared meshes")
	outskirts.update_view(bounds,false,37.5,.7)
	return {"full":full,"reduced":reduced,"unchanged_camera_tick_us_p50":_percentile(samples,.5),"unchanged_camera_tick_us_p95":_percentile(samples,.95),"samples":samples.size(),"scope":"CPU time for existing outskirts update_view only; no FPS or minimum-device claim"}

func _level_shot(game: Node2D,environment: String,id: String,side: String,zoom: float,outward: float=0.0,reduced: bool=false) -> void:
	var edge := float(game.world_left) if side=="west" else float(game.world_right)
	game.players[0].position = Vector2(edge,430.0)
	game.players[0].velocity = Vector2.ZERO
	game.players[0].facing = -1 if side=="west" else 1
	game.camera.position = Vector2(edge+60.0+outward,200.0)
	game.camera.zoom = Vector2.ONE*zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.weather.set_reduced_effects(reduced)
	game.scenery._process(0.0)
	var vegetation: Node2D = game.scenery.vegetation_layer
	vegetation.elapsed = 37.5
	var initial_rebuilds := int(vegetation.outskirts.diagnostics().rebuilds)
	var camera_change_started := Time.get_ticks_usec()
	vegetation._update_presentation()
	var camera_change_us := Time.get_ticks_usec()-camera_change_started
	var camera_change_tick_us := int(vegetation.outskirts.diagnostics().tick_us)
	var camera_change_rebuilds := int(vegetation.outskirts.diagnostics().rebuilds)-initial_rebuilds
	vegetation.set_reduced_preview(1 if reduced else -1)
	game.players[0].get_node("PixelVisual")._process(0.0)
	game.players[0].get_node("PixelVisual").queue_redraw()
	await process_frame
	var metrics := _ecology_sample(vegetation)
	metrics["prepared_camera_change_us"] = camera_change_us
	metrics["prepared_camera_change_outskirts_tick_us"] = camera_change_tick_us
	metrics["prepared_camera_change_rebuilds"] = camera_change_rebuilds
	metrics["prepared_camera_change_scope"] = "One explicitly sampled _update_presentation CPU call after camera framing changed; includes any actual mesh rebuild, not FPS"
	if reduced:
		var bounds: Rect2 = vegetation.get_global_transform_with_canvas().affine_inverse()*vegetation.get_viewport_rect()
		vegetation.outskirts.update_view(bounds,true,37.5,.7)
	check(int(metrics.full.active_plants)>0 and int(metrics.full.active_trees)>0,environment+": actual cosmetic outskirts visible at "+id)
	var folder := OUTPUT+"/"+stage+"/"+environment
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await capture(folder+"/"+id+".png")
	records.append({"environment":environment,"classic":environment.ends_with("_classic"),"type":"bunker","id":id,"file":stage+"/"+environment+"/"+id+".png","side":side,"player_position":[edge,430.0],"camera":[game.camera.position.x,game.camera.position.y],"zoom":zoom,"outward_camera_offset":outward,"reduced_effects":reduced,"legal_world_bounds":[game.world_left,game.world_right],"outskirts":metrics})

func _level(environment: String) -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	view.add_child(game)
	game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.notice_time = 0.0
	game.weather.lightning_enabled = false
	game.weather.set_reduced_effects(false)
	game.weather.elapsed = 37.5
	game.scenery.elapsed = 37.5
	game.hud.hide()
	freeze(game)
	game.camera.make_current()
	await _level_shot(game,environment,"west-boundary","west",.6)
	await _level_shot(game,environment,"east-boundary","east",.6)
	if environment in DETAIL_ENVIRONMENTS:
		await _level_shot(game,environment,"east-normal","east",1.25)
		await _level_shot(game,environment,"east-deep","east",.6,1200.0)
		await _level_shot(game,environment,"east-reduced","east",.6,0.0,true)
		await _level_shot(game,environment,"east-deep-reduced","east",.6,1200.0,true)
	check(not game.network.active and not game.microphone.capturing,environment+": gallery opens no networking or microphone")
	check(await CLEANUP.free_scene(game,self),environment+": complete actual level cleanup")

func _classic() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	view.add_child(game)
	game.start(1)
	game.rounds.running = false
	game.notice_time = 0.0
	game.weather.lightning_enabled = false
	game.weather.set_reduced_effects(false)
	game.weather.elapsed = 37.5
	game.scenery.elapsed = 37.5
	game.hud.hide()
	freeze(game)
	game.camera.make_current()
	await _level_shot(game,"sector07_classic","west-boundary","west",.6)
	await _level_shot(game,"sector07_classic","east-boundary","east",.6)
	await _level_shot(game,"sector07_classic","east-reduced","east",.6,0.0,true)
	check(await CLEANUP.free_scene(game,self),"classic: complete actual level cleanup")

func _road(environment: String) -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	view.add_child(game)
	game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.expedition.state.pending_node = "harbor"
	game.expedition.state.expedition.stage = "travel"
	game.expedition.ensure_road()
	game.weather.lightning_enabled = false
	game.weather.elapsed = 37.5
	game.hud.hide()
	freeze(game)
	var truck := load("res://scenes/convoy_vehicle.tscn").instantiate() as Node2D
	truck.game = game
	game.add_child(truck)
	truck.configure_trip(Vector2(3520,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	truck.journey_state = preload("res://scripts/convoy_journey.gd").new_state("driving")
	truck.animation_time = 37.5
	truck.sync_replica()
	freeze(truck)
	game.players[0].hide()
	game.medic.hide()
	game.camera.make_current()
	for zoom: float in [1.25,.6]:
		game.camera.position = Vector2(3560,200)
		game.camera.zoom = Vector2.ONE*zoom
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		for child: Node in game.get_children():
			if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
				child.depth._update_view()
				child.queue_redraw()
		var id := "road-end-normal" if zoom>1.0 else "road-end-wide"
		var folder := OUTPUT+"/"+stage+"/"+environment
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		await capture(folder+"/"+id+".png")
		records.append({"environment":environment,"type":"road","id":id,"file":stage+"/"+environment+"/"+id+".png","camera":[3560,200],"zoom":zoom,"vehicle_position":[3520,430],"legal_world_bounds":[game.world_left,game.world_right],"prepared_state":"Actual travel stage, road construction and convoy instance; journey/physics held for framing review"})
	check(await CLEANUP.free_scene(game,self),environment+": complete actual road cleanup")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-profile-save" not in args:
		quit(2)
		return
	if "--after" in args: stage = "after"
	capture_enabled = DisplayServer.get_name()!="headless" and "--capture" in args
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	root.size = Vector2i(1280,720)
	view = SubViewport.new()
	view.size = SIZE
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var classic_only := "--only-classic" in args
	if not classic_only:
		for environment: Dictionary in ScenarioCatalog.environments(true): await _level(str(environment.id))
	await _classic()
	if not classic_only:
		for environment: String in ["sector07","ash_foundry","mountain_pass"]: await _road(environment)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {"stage":stage,"checks":checks,"failures":failures,"capture_enabled":capture_enabled,"size":[SIZE.x,SIZE.y],"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Actual main scene for all 13 habitats with one legal-edge worker and the original level geometry. West/east cameras x=legal edge+60,y200,zoom0.6. Five habitats additionally show normal1.25 and deliberately prepared outward+1200 at0.6; outward framing is art review, not reachable player space. All scene callbacks, AI, waves and physics held. Existing scenery/vegetation sampling is explicitly reconciled to the prepared camera; clocks37.5s and lightning off; no HUD. Three actual travel roads additionally show their eastern end with an original convoy instance at3520/430. No profile writes, networking, microphone or audible output. Native SubViewport readback without rescaling/postprocessing.","captures":records}
	FileAccess.open(OUTPUT+"/"+stage+("-classic" if classic_only else "")+"-gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	await CLEANUP.free_scene(view,self)
	print("EDGE DENSITY GALLERY %s: %d/%d checks passed; %d native views"%[stage,checks-failures,checks,records.size()])
	quit(0 if failures==0 else 1)
