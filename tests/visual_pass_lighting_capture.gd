extends SceneTree
## Before/after captures and frame intervals for the lighting and ground pass.
## Usage: --script tests/visual_pass_lighting_capture.gd -- --no-profile-save --no-upnp --label=after [--bench] [--reduced]
const ROOT := "res://artifacts/visual-pass-lighting"
var view: SubViewport
var game: Node
var dest := ""
var timings := {}

func _initialize() -> void: run.call_deferred()

func frames(count: int = 3) -> void:
	for index in count: await process_frame

func shot(label: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(dest + "/" + label + ".png")
	print("CAPTURE ", label)

func open(environment: String, count: int = 1, position: String = "left", stage: int = 0) -> void:
	if is_instance_valid(game):
		await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(count, {"environment":environment, "build_type":"bastion", "position":position})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.weather.set_reduced_effects("--reduced" in OS.get_cmdline_user_args())
	if "--no-fixture-lights" in OS.get_cmdline_user_args() and is_instance_valid(game.scenario_bunker.get("lighting")):
		game.scenario_bunker.lighting.effects_enabled = false
	if is_instance_valid(game.dialogue): game.dialogue.reset()
	game.notice_time = 0
	if stage > 0: game.set_view_stage(stage)
	for index in game.players.size():
		game.players[index].position = Vector2(game.scenario_bunker.room_left + 300 + index * 52, 430)
	await frames(40)

func look(center: Vector2, zoom: float) -> void:
	game.set_process(false)
	game.camera.position = center
	game.camera.zoom = Vector2.ONE * zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()

func resize(pixels: Vector2i, logical: Vector2i) -> void:
	view.size = pixels
	view.size_2d_override = logical
	view.size_2d_override_stretch = true
	await frames(2)
	if is_instance_valid(game): game.hud._layout_viewport()

func bench(label: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for frame in 60: await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 300:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	timings[label] = {"mean_ms":snappedf(total / samples.size(), .001), "p50_ms":snappedf(samples[150], .001), "p95_ms":snappedf(samples[285], .001),
		"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("BENCH ", label, " ", timings[label])

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	var label := "after"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	var benchmark := "--bench" in OS.get_cmdline_user_args()
	dest = ROOT + "/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(320, 180)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await resize(Vector2i(1440, 900), Vector2i(1440, 900))
	var worlds: Array[String] = ["mountain_pass", "frozen_rail_yard", "iron_canyon", "ash_foundry", "abandoned_harbor", "overgrown_steelworks"]
	if "--quick" in OS.get_cmdline_user_args(): worlds.assign(["mountain_pass"])
	if "--all" in OS.get_cmdline_user_args():
		worlds.clear()
		for entry: Dictionary in ScenarioCatalog.environments(true): worlds.append(str(entry.id))
	for environment in worlds:
		await open(environment, 2)
		look(Vector2(560, 400), 1.0)
		await shot("world-" + environment)
		if benchmark and environment in ["mountain_pass", "frozen_rail_yard"]: await bench("world-" + environment)
	if "--quick" in OS.get_cmdline_user_args():
		print("TIMINGS ", JSON.stringify(timings))
		await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
		quit(0)
		return
	# Hostiles outside at night: darkness must never hide them.
	await open("mountain_pass", 2)
	for index in 5:
		var kind: String = EnemyCatalog.GROUND_CLASSES[index * 3 % EnemyCatalog.GROUND_CLASSES.size()]
		var hostile = game._entity("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy", Vector2(900 + index * 70, 430), {"kind":kind, "wave":8})
		hostile.set_physics_process(false)
	await frames(20)
	look(Vector2(960, 330), 1.6)
	await shot("night-hostiles")
	await open("ash_foundry", 2)
	look(Vector2(410, 370), 2.0)
	await shot("interior-close")
	look(Vector2(160, 420), 2.0)
	await shot("doorway-close")
	await open("frozen_rail_yard", 2, "center", 4)
	look(Vector2(720, 880), .62)
	await shot("underground-deep")
	if benchmark: await bench("underground-deep")
	look(Vector2(720, 640), 1.25)
	await shot("underground-rooms")
	await open("ash_foundry", 4, "center", 4)
	await resize(Vector2i(2560, 1440), Vector2i(1600, 900))
	look(Vector2(720, 520), .52)
	await shot("coop4-2560")
	if benchmark: await bench("coop4-2560")
	await resize(Vector2i(960, 600), Vector2i(1440, 900))
	look(Vector2(560, 400), 1.0)
	await shot("small-960")
	if benchmark:
		var file := FileAccess.open(dest + "/timings.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(), "gpu":RenderingServer.get_video_adapter_name(), "cases":timings}, "\t"))
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	quit(0)
