extends SceneTree
## Visual inspection fixture: late wave, paid tower construction from arranged
## cargo, live enemies and real effects. This is not a campaign balance test.
var game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(2)
	game.rounds.set_process(false)
	var late:=OS.get_cmdline_user_args().has("--late")
	game.rounds.wave=18 if late else 7
	game.rounds.phase="attack"
	game.set_view_stage(4 if late else 2)
	var worker=game.players[0]
	var station=game.flak_station
	station.unlock()
	for kind in {"steel":3,"concrete":2,"ammo":1}:
		worker.add_item(kind,{"steel":3,"concrete":2,"ammo":1}[kind])
	for i in 30: station.interact(worker,0.3)
	if late:
		for recipe in [{"steel":4,"glass":2},{"alloy":3,"glass":3}]:
			for kind in recipe: worker.add_item(kind,recipe[kind])
			for i in 30: station.interact(worker,0.3)
	station.turret.autonomous=false
	worker.position=Vector2(530,430)
	game.players[1].position=Vector2(730,245)
	if late:
		for pane in game.dome.segments:
			pane.set_frame()
			pane.glaze()
		game.dome.built=true
		game.dome.frame_built=true
	game.camera.zoom=Vector2.ONE*game.camera_target_zoom
	game.camera.position=game.camera_target_center
	game.notice_time=0
	for index in (3 if late else 2):
		var machine=load("res://scenes/air_enemy.tscn").instantiate()
		machine.game=game
		machine.kind=["sky_fortress","shield_airship","interceptor"][index] if late else "scout_drone"
		machine.wave=game.rounds.wave
		machine.position=Vector2(1400+index*140,90+index*36)
		game.add_child(machine)
	for index in 3:
		var machine=load("res://scenes/enemy.tscn").instantiate()
		machine.game=game
		machine.kind=["bastion","shield_guard","lancer"][index] if late else ["assault","shield_guard","strider"][index]
		machine.wave=game.rounds.wave
		machine.position=Vector2(1250+index*165,430)
		game.add_child(machine)
	await create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/air-defense-%s.png" % ("dome" if late else "wave7"))
	if OS.get_cmdline_user_args().has("--interactive"):
		await create_timer(90).timeout
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit()
