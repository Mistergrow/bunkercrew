extends SceneTree
## Close-up frame strip of a burning tree and a burning ground prop in the real
## main scene (scenery reactions, flames, smoke, embers, glow and the fire
## light), every 5 simulated frames. Graphical display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_scenery_fire_capture.gd -- --no-profile-save [--world=ash_foundry] [--out=<folder>] [--scale=3]
const FRAMES := 12
const CELL := Vector2i(150, 120)
var output := "res://artifacts/visual-pass3-fire/scenery-fire"

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
	var world := _argument("--world=", "ash_foundry")
	output = _argument("--out=", output)
	var pixel_scale := float(_argument("--scale=", "3"))
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
	var props: Node2D = game.scenery.props_layer
	var bunker_right: float = float(game.scenario_bunker.room_right)
	# The nearest standing tree right of the bunker, and the nearest ground prop.
	var tree := -1
	var ground := -1
	for entry: Dictionary in props.entries:
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if state.is_empty() or float(entry.position.x) < bunker_right + 40.0: continue
		if entry.kind == "tree" and (tree < 0 or float(entry.position.x) < float(props.entries[tree].position.x)): tree = int(entry.index)
		elif entry.kind in ["grass", "brush", "reeds", "frost_grass", "vines"] and (ground < 0 or float(entry.position.x) < float(props.entries[ground].position.x)): ground = int(entry.index)
	if tree < 0:
		print("VFX SCENERY FIRE: no tree in ", world)
		quit(1)
		return
	for index in [tree, ground]:
		if index < 0: continue
		props.reactions.damage_entry(index, 1, "arcgun", props.reactions.target_point(index), Vector2.RIGHT)
	for frame in 30: await physics_frame
	var entry: Dictionary = props.entries[tree]
	var focus: Vector2 = props.to_global(Vector2(entry.position)) + Vector2(0, -float(entry.size.y) * .45)
	game.player_camera.set_process(false)
	var grid: GDScript = load("res://scripts/pixel_grid.gd")
	game.camera.zoom = grid.zoom_for(pixel_scale, root)
	game.camera.position = grid.snap_center(focus, game.camera.zoom, root)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	var size := CELL * int(pixel_scale)
	var strip := Image.create(size.x * FRAMES, size.y * 2, false, Image.FORMAT_RGBA8)
	for frame in FRAMES:
		for step in 5: await physics_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var center := Vector2i(image.get_size() / 2)
		strip.blit_rect(image, Rect2i(center - Vector2i(size.x / 2, size.y), Vector2i(size.x, size.y * 2)), Vector2i(frame * size.x, 0))
		if frame == 0: image.save_png(ProjectSettings.globalize_path(output) + "/%s-frame.png" % world)
	strip.save_png(ProjectSettings.globalize_path(output) + "/%s.png" % world)
	print("VFX SCENERY FIRE: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
