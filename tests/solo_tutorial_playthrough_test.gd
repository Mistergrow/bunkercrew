extends SceneTree
## Real finite transfers and construction observed by the adaptive solo guide.
## Worker destinations and combat phase are prepared; no lesson flag is fabricated.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/solo-tutorial-20261005/playthrough-verification.json"
var game: Node
var checks := 0
var failures := 0
var cases: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("SOLO TUTORIAL PLAYTHROUGH %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for _frame in count:
		await physics_frame

func _button(controller: bool, pressed: bool) -> void:
	if controller:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_X
		event.pressed = pressed
		Input.parse_input_event(event)
	else:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _move(controller: bool, pressed: bool) -> void:
	if controller:
		var event := InputEventJoypadMotion.new()
		event.device = 0
		event.axis = JOY_AXIS_LEFT_X
		event.axis_value = 0.85 if pressed else 0.0
		Input.parse_input_event(event)
	else:
		var event := InputEventKey.new()
		event.keycode = KEY_D
		event.physical_keycode = KEY_D
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _wait_for(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())

func _hold(controller: bool, condition: Callable) -> bool:
	_button(controller, true)
	var reached := await _wait_for(condition)
	_button(controller, false)
	await frames()
	game.solo_tutorial.observe()
	return reached

func _place(worker: Worker, target: Node2D) -> void:
	worker.global_position = target.global_position + Vector2(-18, 0)
	worker.velocity = Vector2.ZERO
	worker.preferred_focus = target
	await frames()
	check(game.valid_focus(worker, target), "Prepared destination passes the real interaction reach check")

func _freeze_clock() -> void:
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.expedition.set_process(false)
	game.network.set_process(false)
	game.social_bridge.set_process(false)

func _learned(id: String) -> bool:
	game.solo_tutorial.observe()
	return id in game.solo_tutorial.records.learned

func _case(controller: bool) -> void:
	LocaleText.set_locale("en" if controller else "de", false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.story_mode = true
	game.start_scenario(1, {"environment": "ash_foundry", "position": "left", "build_type": "bastion"})
	_freeze_clock()
	Engine.time_scale = 4.0
	await frames()
	var worker: Worker = game.players[0]
	check(game.solo_tutorial.is_available() and game.solo_tutorial.enabled and worker.inventory.is_empty(),
		"Actual fresh solo starts a guide and an empty worker without granting tutorial materials")
	_move(controller, true)
	check(await _wait_for(func() -> bool: return _learned("move")),
		"Normal keyboard or controller movement teaches movement through the real worker physics")
	_move(controller, false)
	await frames()
	var supplies: Dictionary = {}
	var stations: Dictionary = {}
	for supply: Node in get_nodes_in_group("supplies"):
		if supply.game == game and supply.global_position.y < 300.0:
			supplies[supply.kind] = supply
	for station: Node in get_nodes_in_group("stations"):
		if station.game == game:
			stations[station.kind] = station
	var sand: Supply = supplies.sand
	var ore: Supply = supplies.ore
	var initial_sand := sand.amount
	var initial_ore := ore.amount
	await _place(worker, sand)
	check(await _hold(controller, func() -> bool: return int(worker.inventory.get("sand", 0)) >= 2),
		"Actual held interaction collects sand from the finite roof crate")
	await _place(worker, ore)
	check(await _hold(controller, func() -> bool: return int(worker.inventory.get("ore", 0)) >= 2),
		"Actual held interaction collects ore from a separate finite crate")
	check(_learned("gather") and initial_sand - sand.amount == int(worker.inventory.get("sand", 0))
		and initial_ore - ore.amount == int(worker.inventory.get("ore", 0)),
		"Guide recognizes collection while all carried ingredients equal their real crate debits")
	var mixer: ProductionStation = stations.mixer
	var furnace: ProductionStation = stations.furnace
	var initial_binder := mixer.binder
	await _place(worker, mixer)
	check(await _hold(controller, func() -> bool: return mixer.working), "Normal interaction pays for a mixer batch")
	check(await _wait_for(func() -> bool: return mixer.output_amount == 2), "Actual mixer timer completes two concrete units")
	check(await _hold(controller, func() -> bool: return int(worker.inventory.get("concrete", 0)) == 2), "Actual interaction collects the finished concrete")
	await _place(worker, furnace)
	check(await _hold(controller, func() -> bool: return furnace.working), "Normal interaction pays for a furnace batch")
	check(await _wait_for(func() -> bool: return furnace.output_amount == 2), "Actual furnace timer completes two steel units")
	check(await _hold(controller, func() -> bool: return int(worker.inventory.get("steel", 0)) == 2), "Actual interaction collects the finished steel")
	check(_learned("production") and mixer.binder == initial_binder - 1
		and mixer.output_amount == 0 and furnace.output_amount == 0,
		"Guide recognizes genuine production done out of lesson order; binder and products remain conserved")
	var wall: DefenseWall = game.story.wall
	check(wall.state == DefenseWall.State.EMPTY and game.story.blocks_build(), "The genuine initial story gate remains unbuilt and blocks the first wave")
	await _place(worker, wall)
	check(await _hold(controller, func() -> bool: return wall.state == DefenseWall.State.FRESH), "Normal interaction builds the paid reinforced front")
	check(await _wait_for(func() -> bool: return wall.state == DefenseWall.State.HARD), "The real curing clock hardens the first defense")
	check(_learned("wall") and wall.reinforced and wall.hp == Balance.REINFORCED_HP
		and int(worker.inventory.get("steel", 0)) == 0 and int(worker.inventory.get("concrete", 0)) == 0,
		"Guide recognizes the actual paid wall without altering its cost or defensive strength")
	check(not game.workshop.accessible() and not _learned("workshop"),
		"Locked underground workbench is never reported as a completed crafting lesson")
	await _place(worker, game.turret)
	check(await _hold(controller, func() -> bool: return game.turret.occupant == worker), "Actual held interaction enters the rooftop gun")
	check(_learned("turret") and game.turret.ammo > 0, "Guide learns occupation of a genuinely loaded finite gun")
	game.rounds._set_phase("attack", 0.0)
	game.solo_tutorial.observe()
	check(str(game.solo_tutorial.current_step().get("id", "")) == "danger" and not _learned("defend"),
		"Prepared attack replaces all manufacturing instructions with defense guidance")
	game.rounds._set_phase("build", 20.0)
	var inventory_before: Dictionary = worker.inventory.duplicate(true)
	var stats_before: Dictionary = game.stats.duplicate(true)
	var ammo_before: int = game.turret.ammo
	var wave_before: int = game.rounds.wave
	var timer_before: float = game.rounds.time_left
	for _poll in 100:
		game.solo_tutorial.observe()
		game.solo_tutorial.current_step()
		game.solo_tutorial.target_position()
	check(worker.inventory == inventory_before and game.stats == stats_before and game.turret.ammo == ammo_before
		and game.rounds.wave == wave_before and game.rounds.time_left == timer_before,
		"Repeated guidance observations spend no resources, ammunition or wave time and fabricate no combat progress")
	game.solo_tutorial.stop()
	var retained: Dictionary = game.solo_tutorial.session_records()
	var debited_sand := initial_sand - sand.amount
	var debited_ore := initial_ore - ore.amount
	check(not game.solo_tutorial.enabled and not game.solo_tutorial.active, "Stopping guidance leaves the existing mission playable")
	Engine.time_scale = 1.0
	var previous_id := game.get_instance_id()
	check(game.restart(), "The real local restart accepts the actual started solo mission")
	check(await _wait_for(func() -> bool:
		return is_instance_valid(current_scene) and current_scene.get_instance_id() != previous_id and bool(current_scene.get("started")), 10.0),
		"Actual scene replacement loads a fresh solo world")
	game = current_scene
	_freeze_clock()
	check(game.solo_tutorial.session_records() == retained and not game.solo_tutorial.enabled,
		"No-save restart retains confirmed lessons and the local Stop choice through session metadata")
	check(not game.campaign.checkpoint().has("solo_tutorial") and not game.network.active,
		"Tutorial preferences never enter campaign state or open a network transport")
	game.solo_tutorial.restart()
	game.join_coop()
	game.solo_tutorial.observe()
	check(game.players.size() == 1 and game.solo_tutorial.is_available(),
		"The existing solo-story guard still rejects a local join without hiding its solo guide")
	var previous_story_id := game.get_instance_id()
	var restarted_records: Dictionary = game.solo_tutorial.session_records()
	check(game.return_to_menu(), "Actual return-to-menu accepts the completed test session")
	check(await _wait_for(func() -> bool:
		return is_instance_valid(current_scene) and current_scene.get_instance_id() != previous_story_id and not bool(current_scene.get("started")), 10.0),
		"Actual return-to-menu replaces the started story with a fresh menu owner")
	game = current_scene
	check(game.solo_tutorial.session_records() == restarted_records and not game.solo_tutorial.is_available(),
		"Tutorial preferences cross the real menu transition without starting a hidden world")
	game.start_scenario(1, {"environment": "ash_foundry", "position": "left", "build_type": "bastion"})
	_freeze_clock()
	await frames()
	check(not game.story_mode and not game.solo_story.enabled and game.solo_tutorial.is_available(),
		"A fresh free-shift world uses its existing solo tutorial without becoming the guarded story")
	game.join_coop()
	game.solo_tutorial.observe()
	check(game.players.size() == 2 and not game.solo_tutorial.is_available() and not game.solo_tutorial.active,
		"An actual permitted free-shift local partner join removes the solo guide without changing the cooperative crew")
	cases.append({"locale": LocaleText.current_locale(), "input": "physical joypad events" if controller else "physical keyboard events",
		"sand_debited": debited_sand, "ore_debited": debited_ore, "before_restart": retained,
		"after_local_join_players": game.players.size()})
	_button(controller, false)
	_move(controller, false)
	paused = false
	check(await Cleanup.free_scene(game, self), "Actual solo and cooperative fixture releases its nodes and native audio")
	game = null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	InputSetup.install()
	for controller: bool in [false, true]:
		await _case(controller)
	Engine.time_scale = 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases,
		"prepared_state": "Two actual solo ash_foundry story worlds with physical keyboard/joypad events. Normal finite rooftop crates, live mixer/furnace production and real reinforced formwork/pour/cure/turret interaction. Destinations are prepared, spawning/story timers frozen, simulation4x for transfers. An attack phase is prepared only to inspect safe guidance; no combat/wave completion or learned flags are fabricated. Real game.restart scene replacement retains local preferences; the existing story join guard is respected before a real free-shift scenario and permitted game.join_coop. No human or regular campaign acceptance claimed."}, "\t") + "\n")
	file.close()
	print("SOLO TUTORIAL PLAYTHROUGH: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
