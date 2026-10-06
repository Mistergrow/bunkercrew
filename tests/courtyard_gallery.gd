extends SceneTree
## Actual game art for all 13 habitats, all three fronts, classic, raised/half/
## lowered gates and destroyed mesh. This is prepared visual proof, not FPS.
const MAIN = preload("res://scenes/main.tscn")
const CLEANUP = preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/courtyard-art-20261004"
const SIZE := Vector2i(1600,900)
var view: SubViewport
var checks := 0
var failures := 0
var records: Array[Dictionary] = []

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

func capture(game: Node2D,label: String,point: Vector2,zoom: float) -> void:
	game.camera.position = point
	game.camera.zoom = Vector2.ONE * zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.scenery._process(0.0)
	game.scenery.vegetation_layer._update_presentation()
	for index in 2: await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size() == SIZE,label + ": actual 1600x900 render")
	check(picture.save_png(OUTPUT + "/" + label + ".png") == OK,label + ": saved")
	records.append({"image":label + ".png","camera":[point.x,point.y],"zoom":zoom})

func prepare(environment: String,mode: String,classic: bool=false) -> Node2D:
	var game := MAIN.instantiate() as Node2D
	view.add_child(game)
	if classic: game.start(1)
	else: game.start_scenario(1,{"environment":environment,"position":mode,"build_type":"bastion"})
	game.rounds.running = false
	game.notice = ""
	game.notice_time = 0.0
	game.weather.lightning_enabled = false
	game.scenery.elapsed = 37.5
	game.weather.elapsed = 37.5
	var target: Node2D
	for site in game.perimeter.sites:
		if site.role != "fence": continue
		target = site
		if site.side > 0: break
	if is_instance_valid(target):
		game.players[0].position = target.position - Vector2(float(target.side) * 150.0,0.0)
		game.players[0].velocity = Vector2.ZERO
		game.medic.position = target.position - Vector2(float(target.side) * 250.0,0.0)
		var enemy = preload("res://scenes/enemy.tscn").instantiate()
		enemy.game = game
		enemy.kind = "strider"
		enemy.position = target.position + Vector2(float(target.side) * 95.0,0.0)
		enemy.attack_direction = -float(target.side)
		game.add_child(enemy)
		for site in game.perimeter.sites:
			site.gate_amount = 0.0
			site.gate_open = false
			site.sync_replica()
	game.hud._process(0.0)
	freeze(game)
	game.camera.make_current()
	return game

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960,540)
	view = SubViewport.new()
	view.size = SIZE
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var display := TextureRect.new()
	display.texture = view.get_texture()
	display.size = Vector2(960,540)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(display)
	for environment in ScenarioCatalog.environments(true):
		var game: Node2D = prepare(str(environment.id),"center")
		await capture(game,str(environment.id) + "-wide",Vector2(720,275),.6)
		var courtyard: Node2D = game.perimeter.get_node("ServiceCourtyard")
		courtyard.hide()
		await capture(game,str(environment.id) + "-before",Vector2(1200,370),1.55)
		courtyard.show()
		await capture(game,str(environment.id) + "-close",Vector2(1200,370),1.55)
		check(await CLEANUP.free_scene(game,self),str(environment.id) + ": cleanup")
	for mode in ["left","right"]:
		var game: Node2D = prepare("ash_foundry",mode)
		var target: Node2D
		for site in game.perimeter.sites:
			if site.role == "fence": target = site; break
		var point := Vector2(target.position.x - float(target.side) * 200.0,370.0)
		await capture(game,"ash_foundry-" + mode,point,1.65)
		if mode == "left":
			for amount in [.0,.25,.5,.75,1.0]:
				target.gate_amount = float(amount)
				target.sync_replica()
				await capture(game,"gate-" + str(roundi(float(amount) * 100.0)),Vector2(target.position.x - 10.0,391.0),3.2)
			target.gate_amount = 0.0
			target.take_damage(50.0)
			await capture(game,"gate-damaged",Vector2(target.position.x - 10.0,391.0),3.2)
			target.take_damage(9999.0)
			await capture(game,"gate-destroyed",Vector2(target.position.x - 10.0,391.0),3.2)
		check(await CLEANUP.free_scene(game,self),mode + ": cleanup")
	var classic: Node2D = prepare("sector07","left",true)
	await capture(classic,"classic-courtyard",Vector2(1010,350),1.35)
	check(await CLEANUP.free_scene(classic,self),"classic cleanup")
	var report := {"checks":checks,"failures":failures,"size":[SIZE.x,SIZE.y],"fixture":"Actual main scenes: all 13 habitats in center placement at zoom0.6 and zoom1.55, plus west/east placement and classic. One real worker, SAN-1 and one strider at prepared courtyard/front locations. Waves, AI and input callbacks held; clocks37.5 and lightning disabled. Before/after changes only courtyard visibility; outer gates and enemy are present in both. Gate poses are prepared matching visual/collision fractions. This is visual evidence, not live-combat performance or human playtesting.","images":records}
	var file := FileAccess.open(OUTPUT + "/gallery.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	view.queue_free()
	display.queue_free()
	await process_frame
	print("Courtyard gallery: %d/%d checks passed" % [checks - failures,checks])
	quit(1 if failures else 0)
