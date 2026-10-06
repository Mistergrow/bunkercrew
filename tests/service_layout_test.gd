extends SceneTree
## Prepared wave/material fixtures, real player physics, focus and build API.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SERVICE LAYOUT %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func walk_to(player: Node2D, target_x: float) -> void:
	var direction := signf(target_x - player.position.x)
	var action: String = player.action("right" if direction > 0 else "left")
	Input.action_press(action)
	for unused in 180:
		await physics_frame
		if (target_x - player.position.x) * direction <= 2:
			break
	Input.action_release(action)
	await frames()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for mode in ["left", "center", "right"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2, {"environment":"ash_foundry", "build_type":"bastion", "position":mode})
		game.rounds.set_process(false)
		game.medic.set_physics_process(false)
		game.players[1].set_physics_process(false)
		game.players[1].position = Vector2(game.scenario_bunker.room_left + 590, 430)
		game.rounds.wave = 16
		game.rounds.phase = "build"
		game.flak_station.unlock()
		game.upgrades.owned["bunker_fortress"] = true
		game.dome.unlock()
		var left: float = game.scenario_bunker.room_left
		var worker = game.players[0]
		worker.position = Vector2(left + 130, 430)
		await frames()
		check(not game.valid_focus(worker, game.flak_station), mode + ": roof service cannot be used through the ceiling")
		var console_hit: Dictionary = game.weather.trace_rain(Vector2(left + 130, 100), Vector2(left + 130, 245), false)
		check(console_hit.get("collider") == game.flak_station and console_hit.position.y < 237 and console_hit.material == "metal", mode + ": rain contacts the painted roof console before the floor")
		worker.position = Vector2(left + 54, 430)
		worker.velocity = Vector2.ZERO
		await frames()
		Input.action_press("p1_up")
		for unused in 220:
			await physics_frame
			if worker.position.y <= 245.1 and not worker.climbing:
				break
		Input.action_release("p1_up")
		await frames()
		check(absf(worker.position.y - 245) < 2, mode + ": real main ladder reaches the service deck")
		await walk_to(worker, left + 130)
		check(absf(worker.position.x - (left + 130)) < 8 and game.get_focus(worker) == game.flak_station, mode + ": roof console is accessible and selected without target cycling")
		worker.inventory = {"steel":3, "concrete":2, "ammo":1}
		for unused in 6:
			game.flak_station.interact(worker, Balance.TRANSFER_TIME)
		game.flak_station.interact(worker, 2.6)
		check(game.flak_station.built and worker.inventory.is_empty() and game.flak_station.turret.ammo == 20, mode + ": roof controls build the tower using the exact paid recipe")
		await walk_to(worker, left + 560)
		check(absf(worker.position.x - (left + 560)) < 8 and absf(worker.position.y - 245) < 2, mode + ": rebuilt tower hatch and relocated stockpiles leave the roof walkable")
		var stocks: Array = get_nodes_in_group("supplies").filter(func(stock): return stock.game == game)
		stocks.sort_custom(func(a, b): return a.position.x < b.position.x)
		var separated := stocks.size() == 5
		var contents := {}
		for index in stocks.size():
			contents[stocks[index].kind] = stocks[index].amount
			if index > 0:
				separated = separated and stocks[index].position.x - stocks[index-1].position.x >= 62
		check(separated and contents == {"sand":12,"ore":12,"steel":8,"concrete":8,"ammo":18}, mode + ": five distinct finite crates retain the original starting supplies")
		worker.position = game.dome.site
		worker.velocity = Vector2.ZERO
		worker.inventory.clear()
		await frames()
		check(game.get_focus(worker) == game.dome, mode + ": shelter controls can be selected beside the working machinery")
		var furnace = get_nodes_in_group("stations").filter(func(station): return station.game == game and station.kind == "furnace")[0]
		furnace.output_amount = 2
		check(game.get_focus(worker) == game.dome, mode + ": furnace output does not steal the shelter interaction")
		worker.inventory = DomeController.COST.duplicate()
		for unused in 20:
			game.dome.interact(worker, Balance.TRANSFER_TIME)
		game.dome.interact(worker, DomeController.FRAME_TIME)
		for unused in 12:
			game.dome.interact(worker, Balance.TRANSFER_TIME)
		game.dome.interact(worker, DomeController.GLAZE_TIME)
		check(game.dome.built and worker.inventory.is_empty(), mode + ": wall console constructs the complete paid shelter from ground level")
		check(await Cleanup.free_scene(game, self), mode + ": fixture releases all scene resources")
	print("SERVICE LAYOUT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
