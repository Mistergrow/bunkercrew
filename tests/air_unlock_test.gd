extends SceneTree
## Real scenario factories and paid Flak I construction; prepared waves, no aiming bot.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",label)
	if not value:
		failures += 1
		push_error(label)

func warning(game: Node, wave: int) -> void:
	game.rounds.wave = wave
	game.rounds.phase = "build"
	game.rounds.begin_warning()

func spawn_wave(game: Node, wave: int) -> Array:
	var actors: Array = []
	var count: int = Balance.WAVE_COUNTS[wave-1]
	for index in count:
		game.spawn_enemy(wave,index,count)
		var actor: Node = game.get_children()[-1]
		actor.set_physics_process(false)
		actors.append(actor)
	return actors

func remove_actors(actors: Array) -> void:
	for actor: Node in actors:
		actor.free()

func run() -> void:
	for mode: String in ["legacy","left","center","right"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		if mode == "legacy": game.start(1)
		else: game.start_scenario(2 if mode == "center" else 1,{"environment":"sector07","build_type":"bastion","position":mode})
		game.rounds.set_process(false)
		await process_frame
		check(not game.air_defense_ready(),"%s has no commissioned AA on entry"%mode)
		for wave: int in [7,11,20]:
			warning(game,wave)
			check(not game.rounds.air_wave_enabled and not "LUFTALARM" in game.notice,"%s wave %d announces ground contacts without AA"%[mode,wave])
			if mode != "legacy" and wave==7:
				game.story.phase_changed()
				check(game.story._said.has("warning_ground") and not game.story._said.has("warning_air"),"%s crew dialogue follows actual ground-only warning"%mode)
			game.rounds._begin_attack()
			var actors := spawn_wave(game,wave)
			check(actors.size()==Balance.WAVE_COUNTS[wave-1] and actors.all(func(actor):return not actor is AirMachine),"%s wave %d preserves full wave size with ground replacements"%[mode,wave])
			if wave==20: check(actors[-1] is BossMachine,"%s retains the final boss without AA"%mode)
			remove_actors(actors)
		warning(game,7)
		game.rounds._begin_attack()
		var station: FlakStation = game.flak_station
		station.unlock()
		var worker: Node = game.players[0]
		worker.inventory = {"steel":3,"concrete":2,"ammo":1}
		for kind: String in ["steel","concrete","ammo"]:
			worker.selected_kind = kind
			while int(worker.inventory.get(kind,0))>0:
				station.interact(worker,Balance.TRANSFER_TIME)
		station.interact(worker,3.0)
		check(station.built and game.air_defense_ready() and worker.carried_count()==0,"%s commissions real Flak I with exactly its paid materials"%mode)
		var mid_wave := spawn_wave(game,7)
		check(mid_wave.all(func(actor):return not actor is AirMachine),"%s building mid-wave cannot introduce unannounced aircraft"%mode)
		remove_actors(mid_wave)
		warning(game,6)
		check(not game.rounds.air_wave_enabled,"%s AA cannot introduce aircraft before wave 7"%mode)
		warning(game,7)
		check(game.rounds.air_wave_enabled and "LUFTALARM" in game.notice,"%s next warning announces aircraft after AA completion"%mode)
		if mode != "legacy":
			game.story.phase_changed()
			check(game.story._said.has("warning_air"),"%s crew announces air contacts only after AA completion"%mode)
		game.rounds._begin_attack()
		var enabled_wave := spawn_wave(game,7)
		check(enabled_wave.filter(func(actor):return actor is AirMachine).size()==1,"%s commissioned tower enables the canonical air quota"%mode)
		station.turret.hp = 0
		var disabled_wave := spawn_wave(game,7)
		check(disabled_wave.all(func(actor):return not actor is AirMachine) and enabled_wave.any(func(actor):return actor is AirMachine),"%s disabled AA replaces future slots while existing aircraft remain"%mode)
		remove_actors(enabled_wave)
		remove_actors(disabled_wave)
		warning(game,11)
		check(not game.rounds.air_wave_enabled,"%s disabled AA also prevents a new air warning"%mode)
		station.turret.hp = station.turret.max_hp
		station.turret.ammo = 0
		station.turret.reserve = 0
		warning(game,11)
		check(game.rounds.air_wave_enabled,"%s repairs restore eligibility; deliberately emptying ammo does not remove threats"%mode)
		if mode != "legacy":
			var world := preload("res://scripts/network_world.gd").new()
			world.bind(game)
			var snapshot := world.capture()
			check(world._validate(snapshot),"%s new air-wave flag is valid in the actual world snapshot: %s"%[mode,world.last_error])
			var round_state: Dictionary = snapshot.entities.filter(func(entry):return entry.type=="round_controller")[0].state
			check(round_state.air_wave_enabled,"%s captures the announced wave composition for remote players"%mode)
		game.rounds.start_round()
		check(not game.rounds.air_wave_enabled,"%s a new shift clears previous aircraft eligibility"%mode)
		check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"%s releases real scene services"%mode)
	print("AIR UNLOCK: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
