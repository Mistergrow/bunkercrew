extends SceneTree
## Follow the manual through actual finite crates, live production and wall work.
## Positions are prepared; this is input/economy coverage, not a human playtest.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/help_manual_catalog.gd")
const OUTPUT := "res://artifacts/p1-beta-readiness-20261004/onboarding-ui/"
var game
var checks := 0
var failures := 0
var traces: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	print("FIRST DEFENSE %s: %s" % ["PASS" if value else "FAIL", message])

func frames(count: int = 4) -> void:
	for unused in count: await physics_frame

func interaction(controller: bool, down: bool) -> void:
	if controller:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_X
		event.pressed = down
		Input.parse_input_event(event)
	else:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = down
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func wait_for(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline: await process_frame
	return bool(condition.call())

func place(worker: Worker, target: Node2D) -> void:
	worker.global_position = target.global_position + Vector2(-18, 0)
	worker.velocity = Vector2.ZERO
	worker.preferred_focus = target
	await frames()
	check(game.valid_focus(worker, target), "Prepared destination is genuinely reachable: " + str(target.get_class()))

func hold_until(controller: bool, condition: Callable, seconds: float = 8.0) -> bool:
	interaction(controller, true)
	var reached := await wait_for(condition, seconds)
	interaction(controller, false)
	await frames()
	return reached

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0, true)
	for controller: bool in [false, true]:
		LocaleText.set_locale("en" if controller else "de", false)
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await frames(6)
		game.audio.persistence_enabled = false
		game.combat_events.persistence_enabled = false
		game.campaign.persistence_enabled = false
		game.story_mode = true
		game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.story.set_process(false)
		# Accelerate only this deterministic regression's Godot simulation time;
		# all timers, transfers, production and construction still run normally.
		Engine.time_scale = 4.0
		await frames()
		var worker: Worker = game.players[0]
		check(worker.inventory.is_empty(), "Actual new worker begins without fabricated starter ingredients")
		var supplies: Dictionary = {}
		for supply: Node in get_nodes_in_group("supplies"):
			if supply.game == game and supply.global_position.y < 300: supplies[supply.kind] = supply
		var stations: Dictionary = {}
		for station: Node in get_nodes_in_group("stations"):
			if station.game == game: stations[station.kind] = station
		var sand: Supply = supplies.sand
		var ore: Supply = supplies.ore
		var initial_sand := sand.amount
		var initial_ore := ore.amount
		await place(worker, sand)
		check(await hold_until(controller, func(): return int(worker.inventory.get("sand", 0)) >= 2), "Real E/X hold collects sand from a finite crate")
		await place(worker, ore)
		check(await hold_until(controller, func(): return int(worker.inventory.get("ore", 0)) >= 2), "Real E/X hold collects ore from a separate finite crate")
		var sand_carried := int(worker.inventory.get("sand", 0))
		var ore_carried := int(worker.inventory.get("ore", 0))
		check(initial_sand - sand.amount == sand_carried and initial_ore - ore.amount == ore_carried, "Collected ingredients equal actual crate debits")
		var mixer: ProductionStation = stations.mixer
		var furnace: ProductionStation = stations.furnace
		var initial_binder := mixer.binder
		await place(worker, mixer)
		check(await hold_until(controller, func(): return mixer.working), "Real E/X feeds the mixer and starts a paid batch")
		check(await wait_for(func(): return mixer.output_amount == 2), "Live production produces one finished concrete batch")
		check(await hold_until(controller, func(): return int(worker.inventory.get("concrete", 0)) == 2), "Real E/X collects both concrete units before another batch")
		await place(worker, furnace)
		check(await hold_until(controller, func(): return furnace.working), "Real E/X feeds the furnace and starts a paid batch")
		check(await wait_for(func(): return furnace.output_amount == 2), "Live production produces one finished steel batch")
		check(await hold_until(controller, func(): return int(worker.inventory.get("steel", 0)) == 2), "Real E/X collects both steel units")
		check(mixer.binder == initial_binder - 1 and not mixer.working and not furnace.working and mixer.output_amount == 0 and furnace.output_amount == 0, "Production consumes real binder and leaves no duplicate or uncollected batch")
		var wall: DefenseWall = game.story.wall
		check(is_instance_valid(wall) and wall.state == DefenseWall.State.EMPTY, "Story's extra marked wall is genuinely unbuilt")
		await place(worker, wall)
		check(await hold_until(controller, func(): return wall.state == DefenseWall.State.FRESH), "One real held interaction builds formwork, reinforcement and concrete")
		check(wall.reinforced and int(worker.inventory.get("steel", 0)) == 0 and int(worker.inventory.get("concrete", 0)) == 0, "Reinforced front consumes exactly the manual's steel and concrete")
		check(await wait_for(func(): return wall.state == DefenseWall.State.HARD), "The actual curing timer completes the first secure front")
		check(wall.hp == Balance.REINFORCED_HP and wall.is_blocking(), "Completed first defense has its real reinforced health and collider")
		var gun: Node2D = game.turret
		await place(worker, gun)
		check(await hold_until(controller, func(): return gun.occupant == worker), "Real E/X enters the rooftop defense")
		check(gun.ammo > 0 and worker.mounted_turret == gun, "The occupied first defense has finite ammunition ready")
		var guide := Catalog.sections("first_shift", game)
		check(guide.size() >= 8 and str(guide[2].body).contains(str(Balance.WALL_STEEL_COST)) and str(guide[2].body).contains(str(roundi(Balance.CURE_TIME))), "Current translated starter displays the actual costs and cure duration")
		traces.append({"locale":LocaleText.current_locale(),"input":"synthetic physical first-pad X" if controller else "synthetic physical keyboard E","sand_debited":initial_sand-sand.amount,"ore_debited":initial_ore-ore.amount,"binder_debited":initial_binder-mixer.binder,"wall_hp":wall.hp,"wall_reinforced":wall.reinforced,"gun_ammo":gun.ammo,"gun_occupied":gun.occupant == worker,"simulation_time_scale":Engine.time_scale})
		check(not game.network.active and not game.microphone.capturing, "Starter coverage opens no transport or physical microphone")
		Engine.time_scale = 1.0
		paused = false
		check(await Cleanup.free_scene(game, self), "Starter fixture releases all world and audio handles")
		game = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + "first-defense.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":traces,"human_first_time_player_tested":false,"fixture":"Two independent actual solo ash_foundry story worlds. Normal finite rooftop crates, live production, real physical-key/joypad events and worker interactions, real formwork/rebar/pour/cure and turret entry. Worker destinations are prepared to isolate controls/economy, waves and story progression are held, simulation clock is4x for test duration. No recipe/cost/HP/timer state is fabricated. Not a navigation/human onboarding acceptance."}, "  "))
	quit(1 if failures else 0)
