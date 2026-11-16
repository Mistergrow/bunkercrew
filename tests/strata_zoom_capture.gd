extends SceneTree
## GPU stills of the underground rock (TerrainStrata) of every world at the
## player camera's minimum, default and maximum zoom, for seam, band and
## tiling checks. Writes artifacts/strata-zoom/<world>-<zoom>.png, or the folder
## given after --out (relative to the project).
## Needs a display: godot --path . --script tests/strata_zoom_capture.gd -- --no-profile-save [--out DIR]
const STRATA := preload("res://scripts/terrain_strata.gd")
const CAMERA := preload("res://scripts/player_camera.gd")
const ZOOMS := {"min":CAMERA.MIN_ZOOM, "default":CAMERA.DEFAULT_ZOOM, "max":CAMERA.MAX_ZOOM}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in args:
		quit(1)
		return
	var output := "res://artifacts/strata-zoom/"
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size(): output = "res://" + args[at + 1].trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var only := ""
	at = args.find("--only")
	if at >= 0 and at + 1 < args.size(): only = args[at + 1]
	# Every world with a rock profile, content-pack worlds included.
	for id: String in STRATA.PROFILES:
		if not only.is_empty() and not id in only.split(","): continue
		var world := Node2D.new()
		var strata: Node2D = STRATA.new()
		strata.environment_id = id
		world.add_child(strata)
		var camera := Camera2D.new()
		world.add_child(camera)
		root.add_child(world)
		camera.make_current()
		for label: String in ZOOMS:
			var zoom: float = ZOOMS[label]
			camera.zoom = Vector2(zoom, zoom)
			# The ground line near the top of the view, the rock below it.
			var half := Vector2(root.get_visible_rect().size) * .5 / zoom
			camera.position = Vector2(1300.0, 430.0 - 30.0 / zoom + half.y)
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			image.save_png(output + "%s-%s.png" % [id, label])
		world.queue_free()
		await process_frame
	quit(0)
