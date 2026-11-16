extends SceneTree
## Frame strip of damaged aircraft in flight in the real main scene: below 45 %
## hull they trail smoke (aircraft_art.gd), heavier the worse the damage. The
## camera follows the first aircraft at a whole-pixel scale; every 6 simulated
## frames. Graphical display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_aircraft_trail_capture.gd -- --no-profile-save [--world=frozen_rail_yard] [--out=<folder>] [--scale=2]
const FRAMES := 8
const CELL := Vector2i(300, 150)
var output := "res://artifacts/visual-pass3-fire/aircraft-trail"

func _initialize() -> void:
	run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var world := _argument("--world=", "frozen_rail_yard")
	output = _argument("--out=", output)
	var pixel_scale := float(_argument("--scale=", "2"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1, {"environment":world, "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(0)
	game.weather.lightning_enabled = false
	for frame in 3: await physics_frame
	var right: float = float(game.get("world_right")) if game.get("world_right") != null else 1600.0
	var planes: Array = []
	for row in [["scout_drone", .40], ["gunship", .18]]:
		var plane = game._entity("air_enemy", Vector2(right - 260.0 + planes.size() * 120.0, 140.0 + planes.size() * 40.0), {"kind": row[0], "wave": 8})
		plane.hp = plane.max_hp * float(row[1])
		planes.append(plane)
	for frame in 90: await physics_frame
	game.player_camera.set_process(false)
	var grid: GDScript = load("res://scripts/pixel_grid.gd")
	game.camera.zoom = grid.zoom_for(pixel_scale, root)
	var size := CELL * int(pixel_scale)
	var strip := Image.create(size.x * FRAMES, size.y * planes.size(), false, Image.FORMAT_RGBA8)
	for frame in FRAMES:
		for step in 6: await physics_frame
		for index in planes.size():
			var plane = planes[index]
			if not is_instance_valid(plane): continue
			game.camera.position = grid.snap_center(plane.global_position + Vector2(40, 0), game.camera.zoom, root)
			game.camera.reset_smoothing()
			game.camera.force_update_scroll()
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var center := Vector2i(image.get_size() / 2)
			strip.blit_rect(image, Rect2i(center - size / 2, size), Vector2i(frame * size.x, index * size.y))
	strip.save_png(ProjectSettings.globalize_path(output) + "/%s.png" % world)
	print("VFX AIRCRAFT TRAIL: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
