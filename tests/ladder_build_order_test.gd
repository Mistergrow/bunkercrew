extends SceneTree
## Regression: the second excavation must extend its own shaft, regardless of
## whether the flak appended a service ladder before or after the first shaft.
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	checks += 1
	print("LADDER ORDER ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func frames(count: int):
	for index in count: await physics_frame
func hold(action: String, seconds: float):
	Input.action_press(action)
	await create_timer(seconds,false,true).timeout
	Input.action_release(action)
	await frames(3)
func tower(game, player):
	# Prepared materials are limited to the real first-tier recipe. Access is the
	# subject of this test; finite original-stock transport has its own regression.
	for kind in FlakStation.SPECS[1].cost:
		var amount: int = FlakStation.SPECS[1].cost[kind]
		check(player.add_item(kind,amount)==amount,"Prepared %s fits" % kind)
		for unit in amount: game.flak_station.interact(player,Balance.TRANSFER_TIME+0.01)
	game.flak_station.interact(player,2.6)
	check(game.flak_station.built and player.carried_count()==0,"Tower consumes complete prepared recipe")
func run():
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	for tower_first in [true,false]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await process_frame
		game.start(1)
		game.rounds.set_process(false)
		game.rounds.wave = 11
		game._round_phase_changed()
		var player = game.players[0]
		if tower_first: tower(game,player)
		check(game.expansion.excavate(1),"First shaft opens")
		if not tower_first: tower(game,player)
		check(game.expansion.excavate(2),"Deeper shaft extends")
		check(game.ladders.count(FlakStation.ACCESS)==1,"Flak ladder preserved, tower-first=%s" % tower_first)
		check(game.ladders[game.expansion.shaft_ladder_index].end.y==1245,"Shaft reaches deepest floor")
		player.position = Vector2(530,430)
		player.velocity = Vector2.ZERO
		await frames(5)
		await hold("p1_up",2.8)
		check(absf(player.position.y-35)<2,"Real input still climbs flak after both excavations")
		await hold("p1_down",2.8)
		check(absf(player.position.y-430)<2,"Real input returns inside bunker")
		player.position = Vector2(420,800)
		player.velocity = Vector2.ZERO
		await frames(5)
		await hold("p1_down",3.1)
		check(absf(player.position.y-1240)<2,"Real input descends continuous deep shaft")
		await hold("p1_up",3.2)
		check(absf(player.position.y-800)<3,"Real input returns onto mine floor: y=%.1f" % player.position.y)
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("LADDER ORDER: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
