extends SceneTree
## Arranged late rooms, paid through the normal recipe API; subsequent hatch
## movement uses real worker InputMap actions and physical cover geometry.
var game
func _initialize(): run.call_deferred()
func frames(count: int):
	for i in count: await physics_frame
func capture(path: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ",path)
func run():
	root.size=Vector2i(1440,900)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	game.rounds.wave=6
	var worker=game.players[0]
	for index in 2:
		assert(await preload("res://tests/scenario_excavation_fixture.gd").build_room(game,index,worker))
	game.camera_target_zoom=.87
	game.camera_target_center=Vector2(600,490)
	game.camera.zoom=Vector2.ONE*.87
	game.camera.position=game.camera_target_center
	worker.position=Vector2(game.scenario_bunker.room_left+54,478)
	worker._ladder=game.ladders[0]
	worker.climbing=true
	worker.collision_mask=0
	game.players[1].position=Vector2(370,635)
	game.notice=""
	game.notice_time=0
	await frames(25)
	await capture("res://artifacts/passage-open-live.png")
	Input.action_press("p1_up")
	while worker.position.y>431: await physics_frame
	Input.action_release("p1_up")
	await frames(30)
	assert(not worker.climbing and absf(worker.position.y-430)<1)
	await capture("res://artifacts/passage-closed-live.png")
	game.flak_station.unlock()
	for kind: String in FlakStation.SPECS[1].cost:
		for unit in int(FlakStation.SPECS[1].cost[kind]):
			worker.add_item(kind,1)
			game.flak_station.interact(worker,Balance.TRANSFER_TIME+.01)
	game.flak_station.interact(worker,3)
	worker.position=Vector2(game.flak_station.access.get_center().x,294)
	worker._ladder=game.flak_station.access
	worker.climbing=true
	worker.collision_mask=0
	game.notice=""
	game.notice_time=0
	game.camera_target_zoom=1.0
	game.camera_target_center=Vector2(640,370)
	game.camera.position=game.camera_target_center
	game.camera.zoom=Vector2.ONE
	await frames(25)
	await capture("res://artifacts/passage-flak-live.png")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit()
