extends SceneTree
## Real scenario, lighting and contact shadows: three hostile ground units walk
## in, are defeated by real damage and leave their staged collapse/wreck.
## Prepared positions; waves stopped. Presentation fixture, not a playthrough.
## Usage: godot --path . --script tests/animation_pass_world_capture.gd -- --no-profile-save --no-upnp --environment=frozen_rail_yard
const CLEANUP := preload("res://tests/scene_cleanup.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("World capture requires a graphical display")
		quit(1)
		return
	var environment := "ash_foundry"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--environment="): environment = argument.trim_prefix("--environment=")
	Engine.max_fps = 60
	root.size = Vector2i(1440,900)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.player_camera.mode = "follow"
	game.player_camera._save_delay = -1.0
	game.player_camera.view_zoom = 2.2
	var actor: Node2D = game.players[0]
	actor.global_position = Vector2(850,430)
	for frame in 4: await physics_frame
	game.player_camera.update_view(1,true)
	var units: Array[Node2D] = []
	var kinds := ["rifle_guard","heavy_gunner","strider"]
	for index in kinds.size():
		var kind: String = kinds[index]
		units.append(game._entity("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy",Vector2(960+index*70,430),{"kind":kind,"wave":6}))
	var directory := "res://artifacts/visual-pass-animation/world-%s" % environment
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 150:
		if frame==60:
			for unit in units:
				if is_instance_valid(unit): unit.take_damage(100000)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame>=40 and frame%4==0:
			root.get_texture().get_image().save_png(directory+"/%04d.png" % frame)
	print("ANIMATION PASS WORLD CAPTURE environment=",environment)
	await CLEANUP.free_scene(game,self)
	quit(0)
