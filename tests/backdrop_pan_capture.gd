extends SceneTree
## Visual fixture (graphical display required): a steady horizontal camera pan
## over a running scenario, to judge backdrop crawl and shimmer frame by
## frame. Writes PNG frames; tools/pixel_density_report.py and a frame diff
## measure them. Not a played campaign state.
##   godot --path . --script tests/backdrop_pan_capture.gd -- --no-profile-save
##       --environment=frozen_rail_yard --scale=2 --frames=24 --speed=1.5 --out=DIR
##       [--x=START_X --y=CENTRE_Y] (default: beside the bunker, sky in view)

const PixelGrid := preload("res://scripts/pixel_grid.gd")

func _initialize() -> void:
	call_deferred("_run")

func _option(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name): return argument.get_slice("=", 1)
	return fallback

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("BACKDROP PAN: graphical display required")
		quit(0)
		return
	root.size = Vector2i(1920, 1080)
	var environment := _option("environment", "frozen_rail_yard")
	var scale := float(_option("scale", "2"))
	var count := int(_option("frames", "24"))
	var speed := float(_option("speed", "1.5"))
	var out := _option("out", "res://artifacts/backdrop-pan")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	seed(1)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 12: await process_frame
	game.start_scenario(1, {"environment": environment, "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	game.hud.visible = false
	for frame in 45: await process_frame
	game.player_camera.set_process(false)
	var zoom := PixelGrid.zoom_for(scale, root)
	var start := Vector2(float(_option("x", str(float(game.scenario_bunker.room_right) + 260.0))), float(_option("y", "250")))
	for frame in count:
		var center := start + Vector2(speed * frame, 0.0)
		game.camera.zoom = zoom
		game.camera.position = PixelGrid.snap_center(center, zoom, root)
		game.camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var base := out if not out.begins_with("res://") else ProjectSettings.globalize_path(out)
		image.save_png(base.path_join("pan_%s_s%d_%02d.png" % [environment, int(scale), frame]))
	print("BACKDROP PAN: %d frames of %s at %d px per unit" % [count, environment, int(scale)])
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	quit(0)
