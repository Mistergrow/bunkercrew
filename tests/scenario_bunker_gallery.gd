extends SceneTree
## Arranged scenes rendered by the game itself. Room materials are added as
## fixture stock and passed through the real shared deposit/construction API.
var game

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var error := picture.save_png(path)
	assert(error==OK,"Could not save live room preview")
	print("CAPTURE "+path)

func run() -> void:
	root.size=Vector2i(1440,900)
	var styles := ["bastion","workshop","stronghold"]
	var positions := ["left","center","right"]
	var environments := ["ash_foundry","abandoned_harbor","mountain_pass"]
	for index in 3:
		game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		await process_frame
		game.start_scenario(2,{"build_type":styles[index],"position":positions[index],"environment":environments[index]})
		game.rounds.set_process(false)
		game.rounds.phase="build"
		game.camera.position=game.camera_target_center
		game.camera.zoom=Vector2.ONE*game.camera_target_zoom
		game.notice=""
		game.notice_time=0
		for player in game.players:
			player.velocity=Vector2.ZERO
		await create_timer(0.5).timeout
		await capture("res://artifacts/scenario-%s-start.png"%styles[index])
		game.rounds.wave=16
		for room_index in ScenarioRoomCatalog.ROOMS.size():
			var player=game.players[0]
			assert(await preload("res://tests/scenario_excavation_fixture.gd").build_room(game,room_index,player),"Gallery room did not complete excavation and paid construction")
			await physics_frame
		game.update_scenario_camera()
		game.camera.position=game.camera_target_center
		game.camera.zoom=Vector2.ONE*game.camera_target_zoom
		game.players[0].position=Vector2(game.scenario_bunker.room_left+185,1250)
		game.players[1].position=Vector2(game.scenario_bunker.room_left+345,635)
		game.notice=""
		game.notice_time=0
		await create_timer(0.6).timeout
		await capture("res://artifacts/scenario-%s-expanded.png"%styles[index])
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("SCENARIO ROOM GALLERY: six actual Godot frames captured")
	quit()
