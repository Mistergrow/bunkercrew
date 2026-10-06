extends SceneTree
## Actual main scenes at the normal 1440x900 camera. Waves are stopped;
## scenery, workers and weather run at normal speed. No enlarged prop gallery.
## Gallery: godot --path . --script tests/scenario_props_preview.gd -- --no-profile-save
## Movie: add --fixed-fps 30 --write-movie artifacts/scenery-props/props.avi
## before --script, and --movie after the user-argument separator.
const OUTPUT := "res://artifacts/scenery-props/"
const MOVIE_WORLDS := ["overgrown_steelworks", "frozen_rail_yard", "mountain_pass"]
const MOVIE_FRAMES := 180

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Scenery prop captures require the graphical renderer")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	AudioServer.set_bus_mute(0, true)
	var movie := "--movie" in OS.get_cmdline_user_args()
	var worlds: Array = MOVIE_WORLDS if movie else ScenarioCatalog.environments().map(func(entry): return entry.id)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--world="):
			worlds = [argument.trim_prefix("--world=")]
	var manifest := {
		"scene": "res://scenes/main.tscn",
		"viewport": [1440, 900],
		"camera": "Normal initial game camera, zoom 1",
		"prepared_state": "Solo, bastion, west bunker; waves stopped. Scenery and weather run normally.",
		"movie": movie,
		"fps": 30 if movie else 0,
		"frames_per_world": MOVIE_FRAMES if movie else 8,
		"worlds": worlds,
	}
	for id: String in worlds:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1, {"environment": id, "build_type": "bastion", "position": "left"})
		game.rounds.set_process(false)
		game.rounds.running = false
		game.notice = ""
		game.notice_time = 0
		game.camera.position = Vector2(720, 450)
		game.camera.zoom = Vector2.ONE
		var count := MOVIE_FRAMES if movie else 8
		for frame in count:
			await RenderingServer.frame_post_draw
			if frame == count - 1 or (movie and frame in [0, 90]):
				var name := "%s-%03d.png" % [id, frame] if movie else "%s.png" % id
				root.get_texture().get_image().save_png(OUTPUT + name)
			await process_frame
		if not await preload("res://tests/scene_cleanup.gd").free_scene(game, self):
			quit(1)
			return
	var state_name := "movie-state.json" if movie else "gallery-state.json"
	if movie and worlds.size() == 1:
		state_name = str(worlds[0]) + "-movie-state.json"
	var file := FileAccess.open(OUTPUT + state_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("SCENERY PROP PREVIEW: %d real scenes captured; normal camera, waves stopped" % worlds.size())
	quit()
