extends SceneTree
## Actual level rendering at each legal player edge, with only outer growth
## toggled for comparisons. No fauna, asset, camera or terrain is fabricated.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/vegetation-outskirts-20261005"
const SIZE := Vector2i(1920,1080)
var checks := 0
var failures := 0
var capture_enabled := false
var records: Array[Dictionary] = []
var classic_only := false
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
	for index in 2: await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image.get_size()==SIZE,"actual rendered image is exactly 1920x1080")
	check(image.save_png(path)==OK,"save "+path.get_file())

func _case(environment: String,classic: bool=false) -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	view.add_child(game)
	check(game.has_method("start") and game.has_method("start_scenario"),environment+": actual scene script compiled")
	if not game.has_method("start") or not game.has_method("start_scenario"):
		await CLEANUP.free_scene(game,self)
		return
	if classic: game.start(1)
	else: game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.notice = ""
	game.notice_time = 0.0
	game.weather.lightning_enabled = false
	game.weather.set_reduced_effects(false)
	game.scenery.elapsed = 37.5
	game.weather.elapsed = 37.5
	game.hud._process(0.0)
	freeze(game)
	game.camera.make_current()
	var vegetation: Node2D = game.scenery.vegetation_layer
	var outskirts: Node2D = vegetation.outskirts
	var folder := environment+("_classic" if classic else "")
	var directory := OUTPUT+"/"+folder
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var views: Array[Dictionary] = []
	for side in ["west","east"]:
		game.players[0].position = Vector2(float(game.world_left) if side=="west" else float(game.world_right),430.0)
		game.players[0].velocity = Vector2.ZERO
		var camera_x := float(game.players[0].position.x)+60.0
		game.camera.position = Vector2(camera_x,200.0)
		game.camera.zoom = Vector2.ONE*.6
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		game.scenery._process(0.0)
		vegetation.elapsed = 37.5
		vegetation._update_presentation()
		await process_frame
		var stats: Dictionary = outskirts.diagnostics()
		check(int(stats.active_plants)>0 and int(stats.active_trees)>0,folder+": actual "+side+" boundary exposes new rooted outskirts growth")
		outskirts.hide()
		await capture(directory+"/"+side+"-before.png")
		outskirts.show()
		await capture(directory+"/"+side+"-after.png")
		views.append({"side":side,"player_position":[game.players[0].position.x,game.players[0].position.y],"camera":[camera_x,200.0],"zoom":.6,"stats":stats,"before":folder+"/"+side+"-before.png","after":folder+"/"+side+"-after.png"})
	# One reduced comparison uses the same camera and world positions.
	game.weather.set_reduced_effects(true)
	vegetation.set_reduced_preview(1)
	await capture(directory+"/east-reduced.png")
	records.append({"environment":environment,"classic":classic,"views":views,"reduced":outskirts.diagnostics(),"reduced_capture":folder+"/east-reduced.png"})
	check(await CLEANUP.free_scene(game,self),folder+": rendered scene cleanup")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	capture_enabled = DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	classic_only = "--only-classic" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	root.size = Vector2i(1280,720)
	view = SubViewport.new()
	view.size = SIZE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	if not classic_only:
		for location: Dictionary in ScenarioCatalog.environments(true): await _case(str(location.id))
	await _case("sector07",true)
	check(records.size()==(1 if classic_only else 14),"all requested habitats completed their gallery fixtures")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := {"checks":checks,"failures":failures,"capture_enabled":capture_enabled,"size":[SIZE.x,SIZE.y],"fixture":"Actual main scenes for all 13 habitats and classic Sector07; one crew moved to each normal legal world boundary. Waves, AI and callbacks held, camera at worker x+60,y200,zoom0.6. Weather/scenery clocks fixed37.5, lightning off, ordinary fauna and accessible props unchanged. Before/after changes only VegetationOutskirts.visible. Actual rendered SubViewport readback. Reduced image uses real weather F3 and prepared outer meshes. This is a visual fixture, not live-combat FPS evidence.","worlds":records}
	var file := FileAccess.open(OUTPUT+("/classic-gallery.json" if classic_only else "/gallery.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	await CLEANUP.free_scene(view,self)
	print("VEGETATION OUTSKIRTS GALLERY: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
