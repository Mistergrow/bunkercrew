extends SceneTree
## Compare the shared smoke mesh with the original per-polygon rasterization.
## A real renderer is required; also checks pause, F3 and offscreen chimneys.
class WeatherProbe extends Node:
	var reduced_effects := false
class WorldProbe extends Node2D:
	var weather: WeatherProbe
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool,label: String) -> void:
	checks += 1
	print("SMOKE %s: %s"%["PASS" if condition else "FAIL",label])
	if not condition:
		failures += 1
		push_error(label)

func viewport() -> SubViewport:
	var result := SubViewport.new()
	result.size = Vector2i(2048,400)
	result.world_2d = World2D.new()
	result.transparent_bg = true
	result.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(result)
	return result

func draw_reference(canvas: Node2D,scenery: ScenarioScenery) -> void:
	var base := Color(scenery.profile.haze).darkened(.28)
	for emitter in scenery.data.smoke_anchors.size():
		for index in range(0,scenery.SMOKE_PUFF_COUNT,3 if scenery.reduced() else 1):
			var puff := scenery.smoke_sample(emitter,index)
			if float(puff.alpha)<.005: continue
			for cluster in 5:
				var radius := maxf(2,roundf(float(puff.size)*(.4+float(cluster%3)*.09)))
				var center: Vector2 = puff.position+Vector2.from_angle(cluster*TAU/5+float(puff.phase)*.7)*float(puff.size)*.4
				var points := PackedVector2Array()
				for direction: Vector2 in scenery.OCTAGON: points.append((direction*radius).round())
				var color := base.lightened(.03*(cluster%3))
				color.a = float(puff.alpha)
				canvas.draw_set_transform(center.round())
				canvas.draw_colored_polygon(points,color)
	canvas.draw_set_transform(Vector2.ZERO)

func compare_pixels(expected: Image,actual: Image,label: String) -> void:
	expected.convert(Image.FORMAT_RGBA8)
	actual.convert(Image.FORMAT_RGBA8)
	var a := expected.get_data()
	var b := actual.get_data()
	var visible := 0
	var changed := 0
	for pixel in range(0,a.size(),4):
		if a[pixel+3]<2 and b[pixel+3]<2: continue
		visible += 1
		var max_difference := 0
		for component in 4: max_difference = maxi(max_difference,absi(int(a[pixel+component])-int(b[pixel+component])))
		if max_difference>4: changed += 1
	var ratio := float(changed)/maxi(1,visible)
	var minimum_pixels := mini(12000,floori(expected.get_width()*expected.get_height()/50.0))
	check(visible>minimum_pixels and ratio<.025,"%s retains the original pixel silhouettes and alpha (%.3f%% changed, %d smoke pixels)"%[label,ratio*100,visible])

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("The smoke regression requires the graphical renderer")
		quit(1)
		return
	var rendered := viewport()
	var expected := viewport()
	var world := WorldProbe.new()
	world.weather = WeatherProbe.new()
	world.add_child(world.weather)
	world.position = Vector2(304,0)
	rendered.add_child(world)
	var scenery := ScenarioScenery.new()
	scenery.environment_id = "sector07"
	scenery.game = world
	world.add_child(scenery)
	scenery.set_process(false)
	scenery.self_modulate.a = 0
	scenery.cloud_texture = null
	for layer in [scenery.panorama,scenery.cloud_layer,scenery.surface_layer,scenery.particle_layer,scenery.props_layer]: layer.hide()
	var reference := Node2D.new()
	reference.position = world.position
	expected.add_child(reference)
	reference.draw.connect(draw_reference.bind(reference,scenery))
	check(scenery.smoke_nodes.size()==5,"All five authored chimney plumes are retained")
	check(scenery.smoke_nodes[0].mesh==scenery.smoke_nodes[4].mesh,"Every chimney shares the immutable mesh")
	for reduced in [false,true]:
		world.weather.reduced_effects = reduced
		for clock in [0.0,1.3,7.0,12.0,26.95]:
			scenery.elapsed = clock
			scenery._process(0)
			reference.queue_redraw()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			compare_pixels(expected.get_texture().get_image(),rendered.get_texture().get_image(),"clock %.2f, %s"%[clock,"F3" if reduced else "full"])
			if clock==7.0 and not reduced:
				DirAccess.make_dir_recursive_absolute("res://artifacts/graphics-refresh")
				rendered.get_texture().get_image().save_png("res://artifacts/graphics-refresh/smoke-after.png")
				expected.get_texture().get_image().save_png("res://artifacts/graphics-refresh/smoke-reference.png")
	# The emitter itself is 25 pixels left of this viewport; its moving plume
	# must remain visible because the mesh bounds include shader displacement.
	rendered.size = Vector2i(100,160)
	expected.size = rendered.size
	world.position = Vector2(-scenery.smoke_anchor(1).x-25,-scenery.smoke_anchor(1).y+130)
	reference.position = world.position
	world.weather.reduced_effects = false
	scenery.elapsed = 7.0
	scenery._process(0)
	reference.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	compare_pixels(expected.get_texture().get_image(),rendered.get_texture().get_image(),"Offscreen chimney")
	scenery.set_process(true)
	paused = true
	var paused_clock := scenery.elapsed
	var paused_image := rendered.get_texture().get_image().get_data()
	await create_timer(.08,true,false,true).timeout
	await RenderingServer.frame_post_draw
	check(scenery.elapsed==paused_clock and rendered.get_texture().get_image().get_data()==paused_image,"Pause freezes both the animation clock and every rendered smoke pixel")
	paused = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check(scenery.elapsed>paused_clock,"Smoke animation resumes after pause")
	await preload("res://tests/scene_cleanup.gd").free_scene(rendered,self)
	await preload("res://tests/scene_cleanup.gd").free_scene(expected,self)
	print("SMOKE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
