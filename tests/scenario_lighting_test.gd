extends SceneTree
## Actual v3 panoramas with moving cameras, frozen light ticks and GPU masks.
const OUTPUT := "res://artifacts/v3-effects/lighting"
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Landmarks := preload("res://scripts/panorama_landmarks.gd")
class WorldProbe extends Node2D:
	var camera: Camera2D
var checks := 0
var failures := 0
var records: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("LIGHTING PASS ",label)
func picture(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var gpu := DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for environment: String in ["abandoned_harbor","basalt_quarry","overgrown_steelworks","flooded_power_station"]:
		var view := SubViewport.new()
		view.size = Vector2i(1440,900)
		view.transparent_bg = true
		view.world_2d = World2D.new()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var world := WorldProbe.new()
		view.add_child(world)
		world.camera = Camera2D.new()
		world.camera.position = Vector2(720,-180)
		world.add_child(world.camera)
		world.camera.make_current()
		var scenery := ScenarioScenery.new()
		scenery.environment_id = environment
		scenery.game = world
		world.add_child(scenery)
		scenery.set_process(false)
		# This fixture verifies the original v3 panorama's separate shaft mask.
		# Depth plates have their own lighting and intentionally hide this layer.
		scenery.set_layered_enabled(false)
		for layer in [scenery.cloud_layer,scenery.mist_layer,scenery.particle_layer,scenery.props_layer,scenery.surface_layer,scenery.upper_sky,scenery.distant_water,scenery.distant_horizon,scenery.frozen_outskirts]: layer.hide()
		var lights = scenery.lighting_layer
		var mask: Image = preload("res://scripts/cloud_skyline.gd").texture(environment).get_image()
		check(mask.get_size()==Vector2i(1672,941),environment+" uses a v3-sized mask")
		for camera_state: Vector3 in [Vector3(720,-180,.6),Vector3(1200,-180,.6),Vector3(380,-260,1),Vector3(820,-75,2.2)]:
			world.camera.position = Vector2(camera_state.x,camera_state.y)
			world.camera.zoom = Vector2.ONE*camera_state.z
			world.camera.force_update_scroll()
			scenery.elapsed = 6.7
			scenery._process(0.0)
			var bounds: Rect2 = scenery.panorama_rect
			var uniform: Vector4 = lights.shaft_material.get_shader_parameter("panorama_bounds")
			check(uniform==Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y),environment+" mask follows the current panorama at zoom "+str(camera_state.z))
			var normalized: Rect2 = Rect2((lights._shaft_rect.position-bounds.position)/bounds.size,lights._shaft_rect.size/bounds.size)
			var previous_updates: int = lights.uniform_updates
			for repeat in 8:
				scenery._process(0.0)
				lights.update_lighting(6.7,false)
			check(lights.uniform_updates==previous_updates,environment+" fixed ticks still avoid clock uploads")
			# Reposition within the same tick: the mask and the ray's normalized
			# image position must update before the throttled clock can return.
			scenery.panorama_rect = Rect2(bounds.position+Vector2(37,-12),bounds.size*1.04)
			lights.update_lighting(6.7,false)
			var moved: Rect2 = scenery.panorama_rect
			var moved_normalized := Rect2((lights._shaft_rect.position-moved.position)/moved.size,lights._shaft_rect.size/moved.size)
			check(normalized.is_equal_approx(moved_normalized),environment+" rays keep the same image anchor inside a frozen tick")
			check(lights.uniform_updates==previous_updates,environment+" camera motion does not increase light-clock uploads")
			scenery.panorama_rect = bounds
			lights.update_lighting(6.7,false)
			if gpu and is_equal_approx(camera_state.z,.6):
				var label := environment+"-x"+str(int(camera_state.x))
				(await picture(view)).save_png(OUTPUT+"/"+label+".png")
				scenery.self_modulate.a = 0
				scenery.panorama.hide()
				var rays := await picture(view)
				var inverse := scenery.get_global_transform_with_canvas().affine_inverse()
				var leaked := 0
				var visible_pixels := 0
				for y in range(0,900,3):
					for x in range(0,1440,3):
						if rays.get_pixel(x,y).a < .005: continue
						visible_pixels += 1
						var uv: Vector2 = ((inverse*Vector2(x+.5,y+.5))-bounds.position)/bounds.size
						if not Rect2(0,0,1,1).has_point(uv): leaked += 1; continue
						var pixel := Vector2i((uv*Vector2(mask.get_size())).floor())
						if mask.get_pixel(pixel.x,pixel.y).r<.5: leaked += 1
				check(visible_pixels>30 and leaked==0,label+" actual GPU rays stay in sky (%d visible, %d leaks)"%[visible_pixels,leaked])
				records.append({"environment":environment,"camera":camera_state,"panorama":bounds,"visible_ray_pixels":visible_pixels,"land_leaks":leaked})
				scenery.self_modulate.a = 1
				scenery.panorama.show()
		lights.update_lighting(7.0,true)
		check(not lights.visible,environment+" reduced effects hides extra rays")
		lights.update_lighting(7.0,false)
		check(lights.visible,environment+" restoring effects resumes the layer")
		scenery._update_background_view(true)
		check(not lights.visible,environment+" background framing cannot restore rays while effects are reduced")
		scenery.set_layered_enabled(true)
		lights.update_lighting(7.0,false)
		check(not lights.visible,environment+" depth plates keep the unrelated flat-panorama rays disabled")
		await Cleanup.free_scene(view,self)
	var file := FileAccess.open(OUTPUT+"/verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"prepared":"v3 backgrounds, no entities, frozen t=6.7, zoom .6/1/2.2, moving camera", "records":records},"  "))
	file.close()
	print("SCENARIO LIGHTING: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
