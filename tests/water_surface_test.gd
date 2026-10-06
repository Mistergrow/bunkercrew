extends SceneTree
## Explicit flat V3 panorama fallback and sprite atlas on a real renderer.
## The default depth plates and polygon masks have separate native regressions.
class WeatherProbe extends Node:
	var reduced_effects := false
class WorldProbe extends Node2D:
	var weather: WeatherProbe
var checks := 0
var failures := 0
const OUTPUT := "res://artifacts/water-refresh"

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	print("WATER %s: %s"%["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func frame(viewport: SubViewport,scenery: ScenarioScenery,seconds: float) -> Image:
	scenery.elapsed = seconds
	scenery.offset = Vector2.ZERO
	scenery._process(0)
	scenery.sky_material.set_shader_parameter("sky_cutoff",0.0)
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func changes(a: Image,b: Image,rect: Rect2i,threshold: int = 1) -> int:
	var first := a.get_data()
	var second := b.get_data()
	var count := 0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var at := (y*a.get_width()+x)*4
			if maxi(absi(first[at]-second[at]),maxi(absi(first[at+1]-second[at+1]),absi(first[at+2]-second[at+2])))>=threshold:
				count += 1
	return count

func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-profile-save" in OS.get_cmdline_user_args():
		push_error("Water regression needs a graphical renderer and --no-profile-save")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for environment in ["abandoned_harbor","flooded_power_station"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1536,512)
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var world := WorldProbe.new()
		world.weather = WeatherProbe.new()
		world.add_child(world.weather)
		viewport.add_child(world)
		var scenery := ScenarioScenery.new()
		scenery.adaptive_background = false
		scenery.environment_id = environment
		scenery.game = world
		scenery.position.x = 48
		world.add_child(scenery)
		scenery.set_process(false)
		scenery.cloud_layer.hide()
		scenery.mist_layer.hide()
		scenery.lighting_layer.effects_enabled = false
		scenery.particle_layer.hide()
		scenery.props_layer.hide()
		scenery.surface_layer.hide()
		var water_rect := scenery.region_rect(scenery.data.water_regions[0])
		var top := ceili(water_rect.position.y)+4
		var surface_rect := Rect2i(32,top,1472,508-top)
		# Rect2i takes a height, not the bottom coordinate. The first wet source
		# row is ceil(water_top); preserve every full screen row above that edge.
		var land_rect := Rect2i(32,8,1472,maxi(0,floori(water_rect.position.y)-8))
		var first := await frame(viewport,scenery,0)
		var later := await frame(viewport,scenery,3.7)
		var moving := changes(first,later,surface_rect,6)
		check(moving>12000,"%s reflected water visibly moves across %d pixels"%[environment,moving])
		check(changes(first,later,land_rect)==0,"%s buildings and shoreline above the water mask remain pixel-identical"%environment)
		first.save_png(OUTPUT+"/"+environment+"-reflections-0.png")
		later.save_png(OUTPUT+"/"+environment+"-reflections-3s.png")
		scenery.surface_layer.show()
		var detailed := await frame(viewport,scenery,3.7)
		check(changes(later,detailed,Rect2i(0,top-18,1536,430-top+18),3)>100,"%s authored foam and rain/outlet sprites contribute visible surface detail"%environment)
		detailed.save_png(OUTPUT+"/"+environment+"-surface.png")
		var valid_bounds := true
		var clipped := water_rect
		clipped.size.y = minf(clipped.size.y,430-clipped.position.y)
		for time in 12:
			scenery.elapsed = time*.71
			for index in 28:
				var sample := scenery.water_crest_sample(clipped,index)
				if float(sample.alpha)>.01 and not clipped.grow(1).encloses(sample.rect): valid_bounds = false
			for index in 26:
				var sample := scenery.water_rain_sample(clipped,index)
				if not clipped.grow(1).encloses(sample.rect): valid_bounds = false
		check(valid_bounds,"%s crests and rain rings stay inside the authored water surface"%environment)
		world.weather.reduced_effects = true
		var reduced_first := await frame(viewport,scenery,0)
		var reduced_later := await frame(viewport,scenery,3.7)
		check(is_equal_approx(float(scenery.sky_material.get_shader_parameter("water_amplitude")),.45),"%s F3 limits reflection displacement to less than one source pixel"%environment)
		check(changes(reduced_first,reduced_later,surface_rect,6)<moving,"%s reduced mode visibly lowers surface motion"%environment)
		var before_clock := scenery.elapsed
		scenery._process(4.0)
		check(is_equal_approx(scenery.elapsed-before_clock,1.0),"%s reduced water clock advances at quarter speed"%environment)
		scenery.set_process(true)
		await process_frame
		paused = true
		var paused_clock := scenery.elapsed
		await RenderingServer.frame_post_draw
		var paused_first := viewport.get_texture().get_image()
		for tick in 4: await RenderingServer.frame_post_draw
		check(is_equal_approx(scenery.elapsed,paused_clock) and paused_first.get_data()==viewport.get_texture().get_image().get_data(),"%s pause freezes every reflection, wave and foam pixel"%environment)
		paused = false
		await preload("res://tests/scene_cleanup.gd").free_scene(viewport,self)
	print("WATER SURFACE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
