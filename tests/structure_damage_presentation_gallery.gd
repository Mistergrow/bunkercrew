extends SceneTree
## Identical native fixture runs on the pre-pass source and current source.
## Health values are prepared directly for review; no profile is saved.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const RATIOS := [1.0, 0.80, 0.49, 0.10]
var output := "res://artifacts/pixel-animation-pass-20261005/structures/after"
var records: Array[Dictionary] = []
var size := Vector2i(1440, 900)

class Board extends Node2D:
	var kind := "walls"
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 900), Color("18211e"))
		Art.text(self, Vector2(30, 40), "BUNKERCREW · STRUCTURE CONDITION · NATIVE + 2x", 21)
		for column in 4:
			Art.text(self, Vector2(220 + column * 285, 85), ["100 %", "80 %", "49 %", "10 %"][column], 18)
		if kind == "walls":
			for row in 4:
				Art.text(self, Vector2(25, 143 + row * 188), "Tier %d" % (row + 1), 18)
		else:
			Art.text(self, Vector2(30, 470), "Original machinery atlas · prepared HP · hit flash inactive", 18, Art.MUTED)
			Art.text(self, Vector2(30, 501), "Native size above, 2x below · no added light, particle or collision", 16, Art.MUTED)

func _initialize() -> void: run.call_deferred()

func capture(node: Node2D, name: String, prepared: Dictionary) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("%dx%d-%s.png" % [size.x, size.y, name])
	var picture := root.get_texture().get_image()
	var result := picture.save_png(path)
	assert(result == OK, "Native structure capture failed")
	records.append({"path":path.get_file(), "pixels":[picture.get_width(), picture.get_height()], "prepared":prepared})
	if node != null: assert(await Cleanup.free_scene(node, self), "Native structure fixture cleanup failed")

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Structure gallery requires rendering and --no-profile-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	AudioServer.set_bus_mute(0, true)
	LocaleText.set_locale("de", false)
	root.content_scale_size = Vector2i(1440, 900)
	for dimensions in [Vector2i(1440, 900), Vector2i(1920, 1080)]:
		size = dimensions
		root.size = size
		for frame in 3: await process_frame
		await board_walls()
		await board_core()
		for environment in ["ash_foundry", "mountain_pass"]:
			for tier in [1, 4]:
				for ratio in RATIOS:
					await live_scene(environment, tier, ratio)
		await motion()
	var file := FileAccess.open(output.path_join("gallery.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string, "renderer":RenderingServer.get_current_rendering_method(), "records":records, "prepared_state":"Direct fixture HP values, real wall/core and main scenes; production, combat and profile writes held. No claim of regulary played battle or human perception acceptance."}, "\t") + "\n")
	file.close()
	print("STRUCTURE PRESENTATION GALLERY: %d actual rendered captures" % records.size())
	quit()

func board_walls() -> void:
	var board := Board.new()
	board.position.x = (root.get_visible_rect().size.x - 1440.0) * 0.5
	root.add_child(board)
	for row in 4:
		for column in 4:
			for enlargement in [1, 2]:
				var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
				wall.initial_state = DefenseWall.State.HARD
				wall.initial_tier = row + 1
				wall.position = Vector2(230 + column * 285 + (100 if enlargement == 2 else 0), 265 + row * 188)
				wall.scale = Vector2.ONE * enlargement
				board.add_child(wall)
				wall.set_process(false)
				wall.hp = wall.max_hp * RATIOS[column]
				wall.queue_redraw()
	await capture(board, "wall-stages", {"kind":"wall_board", "tiers":[1, 2, 3, 4], "ratios":RATIOS, "magnifications":[1, 2], "reinforced":false})

func board_core() -> void:
	var board := Board.new()
	board.kind = "core"
	board.position.x = (root.get_visible_rect().size.x - 1440.0) * 0.5
	root.add_child(board)
	for column in 4:
		for enlargement in [1, 2]:
			var core: BunkerCore = load("res://scenes/core.tscn").instantiate()
			core.position = Vector2(260 + column * 285, 265 if enlargement == 1 else 820)
			core.scale = Vector2.ONE * enlargement
			board.add_child(core)
			core.set_process(false)
			core.hp = core.max_hp * RATIOS[column]
			core.elapsed = 2.4
			core.queue_redraw()
	await capture(board, "core-stages", {"kind":"core_board", "ratios":RATIOS, "magnifications":[1, 2], "elapsed":2.4, "hit_flash":0.0})

func live_scene(environment: String, tier: int, ratio: float) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(4, {"environment":environment, "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	game.rounds.running = false
	game.set_process(false)
	game.player_camera.set_process(false)
	game.notice_time = 0.0
	for frame in 4: await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.camera.position = Vector2(440, 360)
	game.camera.zoom = Vector2.ONE * 1.35
	game.camera.force_update_scroll()
	game.scenery._process(0.0)
	for actor in game.players:
		actor.velocity = Vector2.ZERO
		actor.queue_redraw()
	for wall: Node in get_nodes_in_group("walls"):
		if not wall is DefenseWall or not game.is_ancestor_of(wall): continue
		wall.tier = tier
		wall.max_hp = wall.completed_max_hp()
		wall.hp = wall.max_hp * ratio
		wall.hit_flash = 0.0
		wall.queue_redraw()
	game.core.hp = game.core.max_hp * ratio
	game.core.elapsed = 2.4
	game.core.hit_flash = 0.0
	game.core.queue_redraw()
	await capture(game, "%s-tier%d-hp%02d" % [environment, tier, roundi(ratio * 100.0)], {"kind":"prepared_game", "environment":environment, "players":4, "tier":tier, "health_ratio":ratio, "camera":[440, 360, 1.35], "core_elapsed":2.4, "hit_flash":0.0, "enemy_count":0})

func motion() -> void:
	var board := Board.new()
	board.kind = "core"
	board.position.x = (root.get_visible_rect().size.x - 1440.0) * 0.5
	root.add_child(board)
	var cores: Array[BunkerCore] = []
	for column in 4:
		var core: BunkerCore = load("res://scenes/core.tscn").instantiate()
		core.position = Vector2(260 + column * 285, 350)
		core.scale = Vector2.ONE * 2.0
		board.add_child(core)
		core.set_process(false)
		core.hp = core.max_hp * RATIOS[column]
		core.hit_flash = 0.15
		cores.append(core)
	for frame in 24:
		for core in cores: core._process(1.0 / 24.0)
		await capture(null, "core-motion-%02d" % frame, {"kind":"core_motion", "frame":frame, "fps":24, "ratios":RATIOS, "magnification":2, "elapsed":cores[0].elapsed, "hit_flash":cores[0].hit_flash, "note":"Original hit tint decays over its established0.15s; pixel scan uses existing7px/s clock."})
	assert(await Cleanup.free_scene(board, self), "Core motion fixture cleanup failed")
