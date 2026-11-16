extends SceneTree
## Flak barrage in the real game: the flak tower on watch engages three
## aircraft for four simulated seconds; frames every 8 simulated frames, framed
## on the tower and the aircraft lane at a whole-pixel scale. Shows the
## presentation fuse (airbursts beside aircraft, timed bursts, contact bursts)
## from combat_feel.gd. Graphical display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_flak_capture.gd -- --no-profile-save [--out=<folder>] [--environment=<id>] [--reduced]
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PixelGrid := preload("res://scripts/pixel_grid.gd")
var output := "res://artifacts/visual-pass2-vfx/flak"

func _initialize() -> void:
	run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func run() -> void:
	output = _argument("--out=", output)
	var environment := _argument("--environment=", "frozen_rail_yard")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	seed(4242)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 10: await process_frame
	game.start_scenario(1, {"environment": environment, "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	game.notice_time = 0
	game.hud.visible = false
	if is_instance_valid(game.dialogue) and game.dialogue.has_method("reset"): game.dialogue.reset()
	game.weather.set_reduced_effects("--reduced" in OS.get_cmdline_user_args())
	var station = game.flak_station
	station.unlock()
	if not bool(station.built): station._complete()
	var tower = station.turret
	tower.ammo = 80
	tower.reserve = 200
	tower.autonomous = true
	var kinds: Array = Array(AirEnemyCatalog.CLASS_ORDER).slice(0, 3)
	var gun: Vector2 = tower.global_position
	var aircraft: Array = []
	for index in kinds.size():
		var at := Vector2(gun.x + 520.0 + index * 150.0, gun.y - 180.0 - index * 40.0)
		var plane = game._entity("air_enemy", at, {"kind": kinds[index], "wave": int(AirEnemyCatalog.INTRO_WAVES.get(kinds[index], 1))})
		plane.hp = 1000000.0
		plane.max_hp = 1000000.0
		aircraft.append(plane)
	for frame in 150: await physics_frame
	# Frame the tower and wherever the aircraft flew to on their lanes.
	var area := Rect2(gun - Vector2(60, 60), Vector2(120, 100))
	for plane in aircraft:
		if is_instance_valid(plane): area = area.expand(plane.global_position + Vector2(80, 0)).expand(plane.global_position - Vector2(0, 80))
	area = area.grow(40.0)
	var view: Vector2 = root.get_visible_rect().size
	var factor: Vector2 = PixelGrid.stretch(root)
	var fit := minf(view.x / area.size.x, view.y / area.size.y) * minf(factor.x, factor.y)
	game.player_camera.set_process(false)
	game.camera.zoom = PixelGrid.zoom_for(PixelGrid.fit_scale(fit), root)
	game.camera.position = PixelGrid.snap_center(area.get_center(), game.camera.zoom, root)
	game.camera.force_update_scroll()
	var feel = game.get_meta(&"combat_feel") if game.has_meta(&"combat_feel") else null
	for index in 30:
		for step in 8: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output) + "/f%02d.png" % index)
	var bursts: int = int(feel.airbursts) if is_instance_valid(feel) else -1
	print("VFX FLAK: airbursts %d, shots left %d, captured into %s" % [bursts, int(tower.ammo), ProjectSettings.globalize_path(output)])
	await Cleanup.free_scene(game, self)
	quit(0)
