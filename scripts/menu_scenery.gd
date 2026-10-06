extends "res://scripts/scenario_scenery.gd"
## The menu uses the same authored world and effects with its own presentation
## clock. Gameplay stays paused; this preview never creates gameplay entities.
var _redraw_clock := 0.0
var _sky_extension: Node2D
var atmosphere: Node2D
var landmark_effects: Node2D
var distant_sky_lights: Node2D

func _ready() -> void:
	adaptive_background = false
	super()
	process_mode = Node.PROCESS_MODE_ALWAYS
	props_layer.set_process(false)
	# Gameplay props stand on the bunker floor. The menu panoramas already
	# contain their own foreground; a second floor floats over water and valleys.
	props_layer.hide()
	vegetation_layer.hide()
	vegetation_layer.set_process(false)
	# Only airborne wildlife belongs over the menu's painted terrain. Ground
	# animals and undergrowth use the actual playable outdoor floor instead.
	fauna_layer.set_menu_mode(true)
	# The menu camera is fixed. A narrower edge fade preserves architecture
	# near the painted border; MenuComposition keeps this blend off screen.
	var edge_fade := 0.0 if continuous_background else preload("res://scripts/menu_composition.gd").EDGE_FADE
	sky_material.set_shader_parameter("edge_fade", edge_fade)
	lighting_layer.set_edge_fade(edge_fade)
	for layer in cloud_layers:
		layer.material.set_shader_parameter("panorama_edge_fade", edge_fade)
	atmosphere = preload("res://scripts/menu_atmosphere.gd").new()
	atmosphere.scenery = self
	add_child(atmosphere)
	if continuous_background:
		distant_sky_lights = preload("res://scripts/sky_traffic.gd").new()
		distant_sky_lights.configure(environment_id,true)
		add_child(distant_sky_lights)
		move_child(distant_sky_lights,get_children().find(panorama)+1)
		distant_sky_lights.configure_sky_mask(preload("res://scripts/cloud_skyline.gd").texture(environment_id))
	landmark_effects = preload("res://scripts/menu_landmark_effects.gd").new()
	landmark_effects.scenery = self
	add_child(landmark_effects)
	props_layer.presentation_weather = atmosphere
	fauna_layer.presentation_weather = atmosphere
	# MenuAtmosphere replaces the inherited sparse particle layer with the
	# same family across the complete preview, including the upper sky.
	particle_layer.hide()
	if not continuous_background and not data.has("city_path") and panorama.texture!=null:
		# Blend the authored top row into the extended sky. A short fade avoids
		# both a hard panorama edge and vertical streaks from a stretched row.
		_sky_extension = Node2D.new()
		_sky_extension.name = "PreviewSkyExtension"
		_sky_extension.draw.connect(_draw_sky_extension)
		add_child(_sky_extension)
		move_child(_sky_extension,0)

func _process(delta: float) -> void:
	var is_reduced := reduced()
	var step := delta*(.25 if is_reduced else 1.0)
	elapsed += step
	atmosphere.seconds = elapsed
	cloud_motion.advance(step,[cloud_speed(0),cloud_speed(1),cloud_speed(2)],atmosphere)
	_redraw_clock += delta
	if _redraw_clock<1.0/(12.0 if is_reduced else 30.0): return
	_redraw_clock = fposmod(_redraw_clock, 1.0/(12.0 if is_reduced else 30.0))
	sky_material.set_shader_parameter("sky_clock",elapsed)
	lighting_layer.update_lighting(elapsed,is_reduced)
	atmosphere.update_at(elapsed,is_reduced)
	landmark_effects.update_at(elapsed,is_reduced,atmosphere.wind_at(elapsed))
	if is_instance_valid(_sky_extension):
		var light := 1.0+sin(elapsed*.17)*.006
		_sky_extension.modulate = Color(light,light,light)
	if is_reduced!=_last_reduced:
		_last_reduced = is_reduced
		sky_material.set_shader_parameter("water_amplitude",.45 if is_reduced else 4.5)
		sky_material.set_shader_parameter("water_glint",.012 if is_reduced else .070)
	_visible_rect = (get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()).grow(64)
	_update_background_view(is_reduced)
	if is_instance_valid(distant_sky_lights): distant_sky_lights.update_view(panorama_rect,_visible_rect,elapsed,is_reduced)
	var gust: float = atmosphere.wind_strength()
	if _has_surface:
		sky_material.set_shader_parameter("water_turbulence", .45 + gust * .42)
		sky_material.set_shader_parameter("water_amplitude", .45 if is_reduced else 3.4 + gust * 1.6)
		if is_instance_valid(distant_water.water_material):
			distant_water.water_material.set_shader_parameter("turbulence", .45 + gust * .42)
			distant_water.water_material.set_shader_parameter("motion_strength", .25 if is_reduced else .70 + gust * .40)
	distant_horizon.update_view(_visible_rect)
	_redraw_clouds()
	update_cloud_shape(elapsed,is_reduced,atmosphere.wind_strength())
	mist_layer.queue_redraw()

	if _has_surface: surface_layer.queue_redraw()

func _draw_sky_extension() -> void:
	var at := panorama_rect.position
	var width := panorama_rect.size.x
	var row := .5/float(panorama.texture.get_height())
	var points := PackedVector2Array([at+Vector2(0,-80),at+Vector2(width,-80),at+Vector2(width,0),at])
	var colors := PackedColorArray([Color(1,1,1,0),Color(1,1,1,0),Color.WHITE,Color.WHITE])
	var uv := PackedVector2Array([Vector2(0,row),Vector2(1,row),Vector2(1,row),Vector2(0,row)])
	_sky_extension.draw_polygon(points,colors,uv,panorama.texture)

func _draw() -> void:
	super()
	draw_rect(Rect2(-2000,430,5440,1000),Color("111a1b"))
	draw_line(Vector2(-2000,430),Vector2(3440,430),Color("46504b"),4)


func cloud_period(depth: int) -> float:
	if data.has("city_path") and depth == 0: return super(depth)
	return preload("res://scripts/menu_cloud_composition.gd").period(environment_id, depth)

func _draw_cloud_depth(layer: Node2D, depth: int) -> void:
	if cloud_depth_texture == null: return
	if data.has("city_path") and depth == 0:
		_draw_sector_clouds(layer)
		return
	var travel := elapsed * cloud_speed(depth) + cloud_motion.wind_distance[depth]
	var banks := preload("res://scripts/menu_cloud_composition.gd").tiles(environment_id, depth, _visible_rect, panorama_rect, travel, cloud_camera_offset(depth))
	for bank: Dictionary in banks:
		var rect: Rect2 = bank.rect
		var vertices := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
		var uv := preload("res://scripts/menu_cloud_composition.gd").source_uvs(depth, bank.mirror, cloud_depth_texture.get_height())
		var tint := Color(1, 1, 1, float(bank.alpha))
		layer.draw_polygon(vertices, PackedColorArray([tint, tint, tint, tint]), uv, cloud_depth_texture)
