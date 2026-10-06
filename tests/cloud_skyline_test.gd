extends SceneTree
## Skyline geometry guards moving clouds from crossing painted solid landmarks.
const Skyline = preload("res://scripts/cloud_skyline.gd")
const Landmarks := preload("res://scripts/panorama_landmarks.gd")
static var PROBES: Dictionary = _probes()
static var OPEN_SKY_PIXELS: Dictionary = _pixel_probes("sky")
static var SOLID_PIXELS: Dictionary = _pixel_probes("land")

static func _pixel_probes(kind: String) -> Dictionary:
	var result := {}
	for id: String in Landmarks.data.environments:
		var samples: Array[Vector2i] = []
		for pixel: Array in Landmarks.entry(id).probes[kind]:
			samples.append(Vector2i(int(pixel[0]),int(pixel[1])))
		result[id] = samples
	return result

static func _probes() -> Dictionary:
	var result := {}
	for id: String in Landmarks.data.environments:
		result[id] = {"sky": [], "land": []}
		for kind: String in ["sky","land"]:
			for pixel: Array in Landmarks.entry(id).probes[kind]:
				result[id][kind].append(Vector2(float(pixel[0])/1672.0,float(pixel[1])/941.0))
	return result

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	print("SKYLINE %s: %s" % ["PASS" if value else "FAIL", label])

func check_shader(environment_id: String, mask: Texture2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(mask.get_size())
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_2d = World2D.new()
	root.add_child(viewport)
	var surface := ColorRect.new()
	surface.size = Vector2(viewport.size)
	surface.color = Color.WHITE
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = preload("res://shaders/scenario_cloud.gdshader")
	cloud_material.set_shader_parameter("cloud_tint", Color.WHITE)
	cloud_material.set_shader_parameter("mask_landmarks", true)
	cloud_material.set_shader_parameter("skyline", mask)
	cloud_material.set_shader_parameter("panorama_bounds", Vector4(0, 0, viewport.size.x, viewport.size.y))
	surface.material = cloud_material
	viewport.add_child(surface)
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var solid_hidden := true
	var sky_open := true
	for surface_kind: String in ["land", "sky"]:
		for point: Vector2 in PROBES[environment_id][surface_kind]:
			var pixel := Vector2i(point * Vector2(viewport.size))
			var opacity := result.get_pixel(pixel.x, pixel.y).a
			if surface_kind == "land":
				solid_hidden = solid_hidden and opacity < .004
			else:
				sky_open = sky_open and opacity > .015
	check(solid_hidden and sky_open, "%s actual cloud shader hides solid landmarks and keeps sky windows visible" % environment_id)
	var holes_visible := true
	for pixel: Vector2i in OPEN_SKY_PIXELS.get(environment_id,[]):
		holes_visible = holes_visible and result.get_pixel(pixel.x,pixel.y).a>.05
		var clear_neighbors := 0
		for dy in range(-2,3):
			for dx in range(-2,3):
				if result.get_pixel(pixel.x+dx,pixel.y+dy).a>.05: clear_neighbors += 1
		holes_visible = holes_visible and clear_neighbors>=8
	var solids_covered := true
	for pixel: Vector2i in SOLID_PIXELS.get(environment_id,[]):
		solids_covered = solids_covered and result.get_pixel(pixel.x,pixel.y).a<.004
	check(holes_visible and solids_covered,"%s actual GPU mask keeps inspected sky open and metal/rock covered"%environment_id)
	DirAccess.make_dir_recursive_absolute("res://artifacts/cloud-edges")
	result.save_png("res://artifacts/cloud-edges/%s-gpu-mask.png"%environment_id)
	viewport.queue_free()
	await process_frame

func run() -> void:
	for environment_id: String in PROBES:
		var outline := Skyline.points(environment_id)
		var valid := outline.size() > 20 and outline[0].x == 0.0 and outline[-1].x == 1.0
		for index in outline.size():
			valid = valid and outline[index].x >= 0.0 and outline[index].x <= 1.0
			valid = valid and outline[index].y >= 0.0 and outline[index].y <= 1.0
			if index > 0:
				valid = valid and outline[index].x > outline[index - 1].x
		check(valid, "%s normalized skyline covers the full image in ascending order" % environment_id)
		var started := Time.get_ticks_usec()
		var mask := Skyline.texture(environment_id)
		var first_load := Time.get_ticks_usec()-started
		check(mask != null and mask.get_width() == 1672 and mask.get_height() == 941, "%s mask matches original source pixels in both dimensions" % environment_id)
		check(mask == Skyline.texture(environment_id), "%s repeated calls reuse the cached texture" % environment_id)
		started = Time.get_ticks_usec()
		for sample in 1000: Skyline.texture(environment_id)
		print("SKYLINE LOAD ",environment_id,": first_us=",first_load,", cached_mean_us=",float(Time.get_ticks_usec()-started)/1000.0)
		var image := mask.get_image()
		var bounded := true
		var minimum := 1.0
		var maximum := 0.0
		for row in range(0,image.get_height(),8):
			for column in range(0,image.get_width(),8):
				var value := image.get_pixel(column,row).r
				bounded = bounded and value >= 0.0 and value <= 1.0
				minimum = minf(minimum, value)
				maximum = maxf(maximum, value)
		check(bounded and maximum - minimum > .05, "%s mask retains the uneven silhouette instead of a horizontal cutoff" % environment_id)
		for surface: String in ["land", "sky"]:
			for point: Vector2 in PROBES[environment_id][surface]:
				var column := clampi(int(point.x * image.get_width()), 0, image.get_width() - 1)
				var row := clampi(int(point.y * image.get_height()),0,image.get_height()-1)
				var visible_sky := image.get_pixel(column,row).r>.5
				check(visible_sky == (surface == "sky"), "%s authored %s probe at %s" % [environment_id, surface, point])
		for pixel: Vector2i in OPEN_SKY_PIXELS.get(environment_id,[]):
			check(image.get_pixel(pixel.x,pixel.y).r>.5,"%s keeps inspected sky visible at %s"%[environment_id,pixel])
		for pixel: Vector2i in SOLID_PIXELS.get(environment_id,[]):
			check(image.get_pixel(pixel.x,pixel.y).r<.5,"%s protects actual metal/rock at %s"%[environment_id,pixel])
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await check_shader(environment_id, mask)
	check(Skyline.texture("sector07") != null and Skyline.texture("unknown") == null, "Opaque v3 sector has its own mask; unknown IDs remain unsupported")
	print("CLOUD SKYLINE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
