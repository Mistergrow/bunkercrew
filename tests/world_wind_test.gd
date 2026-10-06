extends SceneTree
## Actual scenarios test wind storage, outdoor shelter and shared gust state.
## --capture additionally renders only wind on alpha, then the normal scene.
const OUTPUT := "res://artifacts/movement-effects/wind/"
const Wind := preload("res://scripts/world_wind.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("WORLD WIND %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int=3) -> void:
	for index in count:
		await process_frame
		await physics_frame

func advance(weather,wind,seconds: float) -> void:
	for index in ceili(seconds*60):
		weather.elapsed += 1.0/60.0
		wind._process(1.0/60.0)

func image_of(viewport: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func capture(game,id: String) -> void:
	var wind = game.weather.world_wind
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.notice_time = 0
	game.camera.position = Vector2(720,450)
	game.camera.zoom = Vector2.ONE
	game.weather.elapsed = 3.0
	wind.set_reduced(true)
	advance(game.weather,wind,.5)
	wind.queue_redraw()
	var full := await image_of(root)
	full.save_png(OUTPUT+id+"-scene-0s.png")
	advance(game.weather,wind,2.0)
	var later := await image_of(root)
	later.save_png(OUTPUT+id+"-scene-2s.png")
	# A transparent isolated layer proves the moving pixels belong to wind,
	# not rain/clouds. It also tests alpha and the full lower bunker region.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,900)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var parent: Node = wind.get_parent()
	wind.reparent(viewport)
	wind.set_process(false)
	wind.queue_redraw()
	var first := await image_of(viewport)
	advance(game.weather,wind,2.0)
	var second := await image_of(viewport)
	first.save_png(OUTPUT+id+"-wind-alpha-0s.png")
	second.save_png(OUTPUT+id+"-wind-alpha-2s.png")
	var visible := 0
	var changed := 0
	var forbidden := 0
	var dense_cards := 0
	var data := first.get_data()
	var after := second.get_data()
	var left := int(game.scenario_bunker.room_left)
	var right := int(game.scenario_bunker.room_right)
	for y in 900:
		var dense_run := 0
		for x in 1440:
			var index := (y*1440+x)*4
			var alpha := int(data[index+3])
			var next := int(after[index+3])
			if alpha>=8: visible += 1
			if absi(alpha-next)>=8: changed += 1
			if maxi(alpha,next)>0 and (y>=430 or (x>=left and x<=right and y>=245)): forbidden += 1
			# A leaf vein may overlap its opaque body. A wide solid alpha run
			# would instead expose an unwanted filled particle card/background.
			dense_run = dense_run+1 if alpha>240 else 0
			if dense_run==24: dense_cards += 1
	check(visible>500 and changed>500,"%s isolated wind visibly changes after 2s: %d material pixels, %d changed" % [id,visible,changed])
	check(forbidden==0 and dense_cards==0,"%s rendered alpha has no indoor/underground pixels or opaque cards (%d / %d)" % [id,forbidden,dense_cards])
	wind.reparent(parent)
	viewport.queue_free()
	await process_frame

func run() -> void:
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rendered := "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	for environment: Dictionary in ScenarioCatalog.environments():
		var id: String = environment.id
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.rounds.running = false
		game.notice = ""
		game.notice_time = 0
		await frames(4)
		var weather = game.weather
		var wind = weather.world_wind
		check(is_instance_valid(wind) and wind.environment_id==id,"%s actual scenario installs its own material profile" % id)
		var first_time: float = wind.elapsed
		var first_point: Vector2 = wind.particles[0].point
		await frames(4)
		check(wind.elapsed>first_time and Vector2(wind.particles[0].point).distance_to(first_point)>.1,"%s live updates visibly translate windborne material" % id)
		weather.set_process(false)
		wind.set_process(false)
		var indoor := Vector2(game.scenario_bunker.room_left+54,310)
		check(not wind.outdoors(indoor) and not wind.outdoors(Vector2(1080,455)),"%s open service shaft/interior and underground never receive wind" % id)
		var bounded := true
		var sheltered := true
		var gust_low := 1.0
		var gust_high := 0.0
		for frame in 2400:
			weather.elapsed += 1.0/60.0
			wind._process(1.0/60.0)
			bounded = bounded and wind.particles.size()<=Wind.MAX_PARTICLES and wind.plumes.size()<=Wind.MAX_PLUMES
			for particle: Dictionary in wind.particles+wind.plumes:
				sheltered = sheltered and wind.outdoors(particle.point,4)
			gust_low = minf(gust_low,weather.wind_strength())
			gust_high = maxf(gust_high,weather.wind_strength())
		check(bounded and sheltered and wind.spawned>80 and wind.culled>40,"%s 40s gust/calm circulation remains bounded, outdoors and replaces old particles" % id)
		check(gust_low>=0 and gust_high<=1 and gust_high-gust_low>.35,"%s shared gust varies smoothly within 0..1 (%.2f..%.2f)" % [id,gust_low,gust_high])
		var props = game.scenery.props_layer
		var roots: Array = props.tree_nodes.map(func(tree): return tree.transform)
		props._process(.04)
		var shared := true
		for material_index: int in props.tree_materials:
			if not props.entries[material_index].displayed or bool(props.entries[material_index].get("broken",false)): continue
			var material: ShaderMaterial = props.tree_materials[material_index]
			shared = shared and is_equal_approx(float(material.get_shader_parameter("gust_strength")),.06+weather.gust_at(props.to_global(props.entries[material_index].position))*.94)
		check(shared and props.tree_nodes.map(func(tree): return tree.transform)==roots,"%s trees use shared gust with stationary planted roots" % id)
		paused = true
		var stopped: float = wind.elapsed
		var positions: String = var_to_str(wind.particles)
		wind._process(.5)
		await create_timer(.03,true,false,true).timeout
		check(wind.elapsed==stopped and var_to_str(wind.particles)==positions,"%s shared pause freezes wind" % id)
		paused = false
		weather.set_reduced_effects(true)
		wind._process(.5)
		check(wind.particles.is_empty() and wind.plumes.is_empty(),"%s F3 removes airborne material and its update work" % id)
		weather.set_reduced_effects(false)
		weather.elapsed = 3.0
		advance(weather,wind,.2)
		check(not wind.particles.is_empty() and not wind.plumes.is_empty(),"%s F3 restores wind" % id)
		if id=="frozen_rail_yard": check(wind.diagnostics().kind=="snow","Snow biome carries snow, not brown dust")
		if id=="overgrown_steelworks": check(wind.diagnostics().kind=="leaf","Green biome carries fluttering leaves")
		if id=="sector07":
			# Looking deep underground must not continue spawning/updating unseen
			# exterior material, even with active rain elsewhere in the world.
			game.set_process(false)
			game.camera.position = Vector2(720,1600)
			game.camera.force_update_scroll()
			wind._process(.2)
			var births: int = wind.spawned
			advance(weather,wind,1.0)
			check(wind.particles.is_empty() and wind.plumes.is_empty() and wind.spawned==births,"Underground camera skips unseen wind emission and particle work")
			game.camera.position = Vector2(720,450)
			game.camera.force_update_scroll()
			advance(weather,wind,1.0)
			check(not wind.particles.is_empty(),"Returning camera repopulates exterior wind")
		if rendered and id in ["sector07","iron_canyon","overgrown_steelworks","frozen_rail_yard"]:
			await capture(game,id)
		if not await preload("res://tests/scene_cleanup.gd").free_scene(game,self): failures += 1
	print("WORLD WIND: %d/%d checks passed%s" % [checks-failures,checks," (GPU alpha and motion included)" if rendered else ""])
	quit(1 if failures else 0)
