extends SceneTree
## Staged combat moments for before/after comparison of muzzle flashes, tracers,
## impacts, explosions, gunfire light and camera feel. Run with --fixed-fps 60 on
## a graphical display. Arguments after "--": --no-profile-save [--out=<folder>]
## [--bench] [--reduced]. Every event is scheduled by frame, so two runs of the
## same build show the same moments.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var output := "res://artifacts/visual-pass-combatvfx/after/"
var failures := 0
var bench := false
var reduced := false
var timings: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func shot(folder: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png(output+folder+"/"+label+".png")!=OK:
		failures += 1
		push_error("capture failed "+label)

func enemy(game, scene: String, kind: String, where: Vector2, wave: int) -> Node2D:
	var actor = load("res://scenes/%s.tscn"%scene).instantiate()
	actor.kind = kind
	actor.wave = wave
	actor.game = game
	actor.position = where
	game.add_child(actor)
	return actor

func aim(game, weapon) -> void:
	# Aim like a player would: the pointer rests to the right, slightly above
	# the weapon, so gun pose, flash and bullets share one direction.
	var screen: Vector2 = game.get_viewport().get_canvas_transform()*(weapon.global_position+Vector2(420,-50))
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	root.warp_mouse(screen)
	weapon._aim_hold = .75

func stage(environment: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+environment))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":environment,"position":"left","build_type":"workshop"})
	game.rounds.set_process(false)
	game.rounds.wave = 14
	game.story.enabled = false
	game.dialogue.reset()
	game.dialogue.set_process(false)
	game.notice_time = 0
	game.hud.visible = false
	game.weather.set_reduced_effects(reduced)
	if is_instance_valid(game.medic): game.medic.set_physics_process(false)
	var worker = game.players[0]
	worker.position = Vector2(760,430)
	worker.facing = 1
	worker.hp = 100000.0
	worker.max_hp = 100000.0
	var weapon = worker.get_node("WorkerWeapon")
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.initial_state = 4
	wall.position = Vector2(900,430)
	game.add_child(wall)
	wall.hp = 50000
	wall.max_hp = 50000
	var troops: Array = []
	var kinds: Array = ["rifle_guard","heavy_gunner","marksman"]
	for index in kinds.size():
		var soldier := enemy(game,"ground_infantry",kinds[index],Vector2(1080+index*70,430),14)
		soldier.squad_slot = index
		soldier.hp = 100000.0
		soldier.max_hp = 100000.0
		troops.append(soldier)
	var machines: Array = []
	var machine_kinds: Array = ["breaker","battle_tank","siege"]
	for index in machine_kinds.size():
		var machine := enemy(game,"enemy",machine_kinds[index],Vector2(1330+index*150,430),14)
		machine.hp = 100000.0
		machine.max_hp = 100000.0
		machines.append(machine)
	game.player_camera.set_mode("follow")
	game.player_camera.set_zoom(1.25)
	for frame in 20: await process_frame
	game.player_camera.update_view(1,true)
	await shot(environment,"00-approach")
	var samples: Array[float] = []
	var total := 60 if not bench else 600
	# Segment 1: automatic rifle, then shotgun, from the worker over the wall;
	# the wave returns fire with its own AI.
	var seen := {}
	for frame in 260 if not bench else 0:
		aim(game,weapon)
		if frame>=20 and frame<80:
			weapon.loaded[weapon.weapon_kind] = 30
			weapon.fire()
		await process_frame
		if frame>=20 and frame<34: await shot(environment,"10-rifle-%03d"%frame)
		if frame in [60,90,120,150]: await shot(environment,"20-exchange-%03d"%frame)
		for actor in troops+machines:
			# The first frames of each enemy class's own, AI-triggered discharge.
			if actor.muzzle_flash>0 and int(seen.get(actor.kind,0))<3:
				seen[actor.kind] = int(seen.get(actor.kind,0))+1
				await shot(environment,"25-enemy-%s-%d"%[actor.kind,seen[actor.kind]])
	# Segment 2: surface impacts and one large explosion in view.
	var at := Vector2(1010,424)
	for frame in total:
		var before := Time.get_ticks_usec()
		if bench:
			aim(game,weapon)
			weapon.loaded[weapon.weapon_kind] = 30
			weapon.fire()
			if frame%6==0: game.impact(at+Vector2(frame%90,-30-frame%50),["metal","concrete","earth","glass"][int(frame/6.0)%4],Vector2.LEFT,1.0)
			if frame%40==0: game.impact(at+Vector2(60+frame%140,0),"explosion",Vector2.UP,1.4)
		else:
			if frame==2:
				game.impact(Vector2(894,380),"metal",Vector2.LEFT,1.2)
				game.impact(Vector2(894,340),"concrete",Vector2.LEFT,1.2)
				game.impact(Vector2(980,428),"earth",Vector2.UP,1.2)
		await process_frame
		if bench: samples.append((Time.get_ticks_usec()-before)/1000.0)
		elif frame in [3,4,5,7,10,14,20,30,45]: await shot(environment,"30-impact-%03d"%frame)
	if bench:
		samples.sort()
		var sum := 0.0
		for value in samples: sum += value
		timings[environment] = {"mean_ms":sum/samples.size(),"p95_ms":samples[ceili(samples.size()*.95)-1],"max_ms":samples[-1],"frames":samples.size()}
	else:
		for frame in 110:
			if frame==2: game.impact(at,"explosion",Vector2.UP,1.6)
			await process_frame
			if frame in [3,4,5,6,8,10,13,17,22,28,36,46,58,72,90,108]: await shot(environment,"40-explosion-%03d"%frame)
	if not bench:
		# Segment 4: the replicated hit timer on every class at once (set
		# directly: this fixture shows the read, it does not test damage).
		for frame in 16:
			if frame==2:
				for actor in troops+machines: actor.hit_flash = .2
			await process_frame
			if frame in [1,3,4,6,8,11]: await shot(environment,"50-hit-%03d"%frame)
	if not await Cleanup.free_scene(game,self): failures += 1

func fx_bench() -> void:
	# Effect cost in isolation: an empty world, one blast every ten frames and
	# two surface impacts per frame (the burst pool stays saturated).
	var world := Node2D.new()
	root.add_child(world)
	var samples: Array[float] = []
	var render_cpu := 0.0
	var render_gpu := 0.0
	var script_ms := 0.0
	var draws := 0.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for frame in 420:
		var before := Time.get_ticks_usec()
		for index in 2:
			var burst := ImpactBurst.new()
			burst.position = Vector2(300+(frame*37+index*211)%1300,300+(frame*53)%500)
			burst.surface_material = ["metal","concrete","earth","glass"][(frame+index)%4]
			world.add_child(burst)
		if frame%10==0:
			var blast := ImpactBurst.new()
			blast.position = Vector2(300+(frame*91)%1300,700)
			blast.surface_material = "explosion"
			blast.direction = Vector2.UP
			blast.power = 1.5
			world.add_child(blast)
		await process_frame
		if frame>=60:
			samples.append((Time.get_ticks_usec()-before)/1000.0)
			render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())+RenderingServer.get_frame_setup_time_cpu()
			render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			script_ms += (Performance.get_monitor(Performance.TIME_PROCESS)+Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	print("COMBAT FEEL FXBENCH render_cpu_ms=%.3f render_gpu_ms=%.3f process+physics_ms=%.3f draw_calls=%.0f"%[render_cpu/samples.size(),render_gpu/samples.size(),script_ms/samples.size(),draws/samples.size()])
	samples.sort()
	var sum := 0.0
	for value in samples: sum += value
	print("COMBAT FEEL FXBENCH mean_ms=%.3f p95_ms=%.3f max_ms=%.3f"%[sum/samples.size(),samples[ceili(samples.size()*.95)-1],samples[-1]])
	world.queue_free()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var environments: Array = ["sector07","frozen_rail_yard"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = "res://artifacts/visual-pass-combatvfx/%s/"%argument.trim_prefix("--out=")
		if argument.begins_with("--env="): environments = Array(argument.trim_prefix("--env=").split(","))
		if argument=="--bench": bench = true
		if argument=="--reduced": reduced = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	if bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if "--fxbench" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await fx_bench()
		quit(0)
		return
	for environment: String in environments:
		await stage(environment)
	if bench:
		var file := FileAccess.open(output+"bench.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(timings,"\t"))
		print("COMBAT FEEL BENCH ",JSON.stringify(timings))
	print("COMBAT FEEL CAPTURE done, failures=",failures)
	quit(1 if failures else 0)
