extends SceneTree
## Close-up frame strips of the blast family, the flak airburst and the impact
## sparks, every family at the same ages on a sky/ground stage at a whole-pixel
## camera scale. Deterministic seeds; graphical display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_family_capture.gd -- --no-profile-save [--out=<folder>] [--scale=3] [--night] [--reduced] [--bench]
## Writes <family>.png strips (one cell per age) and a contact sheet.
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const AGES := [.017, .05, .10, .17, .26, .38, .55, .80, 1.10, 1.45, 1.85, 2.30]
const CELL := Vector2i(170, 170)
var output := "res://artifacts/visual-pass2-vfx/family"
var pixel_scale := 3.0
var night := false

class Stage extends Node2D:
	var night := false
	# Enough of a game for combat_feel.gd to attach: scorch marks and the
	# muzzle/blast layers appear as in play (no camera rig: no shake).
	var player_camera := Node.new()
	func impact(_point, _kind, _normal = Vector2.LEFT, _strength = 1.0) -> void: pass
	func _draw() -> void:
		draw_rect(Rect2(-3000,-2000,6000,2000),Color("1c2433") if night else Color("7d97b2"))
		draw_rect(Rect2(-3000,0,6000,900),Color("1d1c1a") if night else Color("3a3631"))
		draw_rect(Rect2(-3000,0,6000,3),Color("5b5a52") if night else Color("c9d3d6"))
		draw_rect(Rect2(-3000,3,6000,5),Color("2a2824") if night else Color("6b6255"))

func _initialize() -> void:
	run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func _burst(stage: Node2D, kind: String, family: String, at: Vector2, power: float, seed_number: int, reduced: bool) -> ImpactBurst:
	var burst := ImpactBurst.new()
	burst.surface_material = kind
	burst.class_hint = family
	burst.position = at
	burst.direction = Vector2.UP if kind != "metal" else Vector2(-1,-.35).normalized()
	burst.power = power
	burst.seed_value = seed_number
	burst.reduced = reduced
	stage.add_child(burst)
	return burst

## --bench: 24 blasts and 12 airbursts kept alive with 60 metal impacts a
## second, mean frame time over 5 s after a 1 s warm-up.
func bench(stage: Node2D) -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	var families := ["ground","mech","vehicle","aircraft","structure","grenade"]
	for frame in 360:
		var live := get_nodes_in_group(ImpactBurst.GROUP).size()
		if frame % 6 == 0 and live < 36:
			var index := floori(frame / 6.0)
			var family: String = families[index % families.size()]
			var air := family == "aircraft"
			_burst(stage, "explosion", family, Vector2(-500 + (index * 97) % 1000, -160 if air else -12), 1.4, 300 + index, false)
			_burst(stage, "flak", "", Vector2(-480 + (index * 61) % 960, -260), 1.0, 900 + index, false)
		_burst(stage, "metal", "", Vector2(-400 + (frame * 37) % 800, -30), 1.2, 1300 + frame, false)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame >= 60: samples.append(float(now - previous) / 1000.0)
		previous = now
	for burst in get_nodes_in_group(ImpactBurst.GROUP): burst.retire()
	await process_frame
	var total := 0.0
	for sample in samples: total += sample
	return {"frames": samples.size(), "mean_ms": snappedf(total / samples.size(), .001)}

func run() -> void:
	output = _argument("--out=", output)
	pixel_scale = float(_argument("--scale=", "3"))
	night = "--night" in OS.get_cmdline_user_args()
	var reduced := "--reduced" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	await process_frame
	var stage := Stage.new()
	stage.night = night
	root.add_child(stage)
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(6000, 40)
	shape.shape = box
	shape.position = Vector2(0, 20)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.zoom = PixelGrid.zoom_for(pixel_scale, root)
	camera.make_current()
	if "--bench" in OS.get_cmdline_user_args():
		camera.zoom = PixelGrid.zoom_for(2.0, root)
		camera.position = Vector2(0, -150)
		await process_frame
		var result := await bench(stage)
		print("VFX FAMILY BENCH ", RenderingServer.get_video_adapter_name(), " ", JSON.stringify(result))
		quit(0)
		return
	# One subject per take, framed at its own height; cells crop the same
	# world rectangle around it so frames line up.
	var takes := [
		["ground", "explosion", "ground", Vector2(0, -12), 1.6],
		["mech", "explosion", "mech", Vector2(0, -30), 1.2],
		["vehicle", "explosion", "vehicle", Vector2(0, -24), 1.1],
		["aircraft", "explosion", "aircraft", Vector2(0, -150), 1.0],
		["structure", "explosion", "structure", Vector2(0, -20), 1.5],
		["grenade", "explosion", "grenade", Vector2(0, -6), 1.2],
		["flak", "flak", "", Vector2(0, -150), 1.0],
		["metal", "metal", "", Vector2(0, -30), 1.2],
	]
	var sheet := Image.create(CELL.x * int(pixel_scale) * AGES.size(), CELL.y * int(pixel_scale) * takes.size(), false, Image.FORMAT_RGBA8)
	var row := 0
	for take in takes:
		var at: Vector2 = take[3]
		var focus: Vector2 = at + Vector2(0, -50 if take[0] != "aircraft" and take[0] != "flak" else -10)
		camera.position = PixelGrid.snap_center(focus, camera.zoom, root)
		await process_frame
		var burst := _burst(stage, take[1], take[2], at, take[4], 4242, reduced)
		var strip := Image.create(CELL.x * int(pixel_scale) * AGES.size(), CELL.y * int(pixel_scale), false, Image.FORMAT_RGBA8)
		var shown := 0
		while shown < AGES.size():
			await physics_frame
			if not is_instance_valid(burst) or burst.retired or burst.age >= float(AGES[shown]):
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				var screen: Vector2 = root.get_final_transform() * (root.get_canvas_transform() * focus)
				var size := CELL * int(pixel_scale)
				var region := Rect2i(Vector2i(screen) - Vector2i(size.x >> 1, size.y >> 1), size)
				strip.blit_rect(image, region, Vector2i(shown * size.x, 0))
				shown += 1
		strip.save_png(ProjectSettings.globalize_path(output) + "/%s.png" % take[0])
		sheet.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(0, row * strip.get_height()))
		row += 1
		if is_instance_valid(burst): burst.retire()
		await process_frame
	sheet.save_png(ProjectSettings.globalize_path(output) + "/sheet.png")
	print("VFX FAMILY: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
