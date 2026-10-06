extends SceneTree
## Real factory/Flak/round/input integration. Saves are isolated under artifacts.
const SAVE := "res://artifacts/air-raid-intro/test-campaign.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1
		push_error(label)

func commission(game: Node) -> void:
	game.rounds.wave = maxi(6,game.rounds.wave)
	game.flak_station.unlock()
	var worker: Node = game.players[0]
	worker.inventory = {"steel":3,"concrete":2,"ammo":1}
	for kind: String in ["steel","concrete","ammo"]:
		worker.selected_kind = kind
		for transfer in 8:
			if int(worker.inventory.get(kind,0)) <= 0: break
			game.flak_station.interact(worker,Balance.TRANSFER_TIME)
	game.flak_station.interact(worker,3.0)
	check(game.air_defense_ready() and worker.carried_count()==0,"Real Flak I commissions with finite construction materials")

func air_slot(wave: int) -> int:
	var roster := EnemyCatalog.wave_roster(wave,Balance.WAVE_COUNTS[wave-1],true)
	for index in roster.size():
		if AirEnemyCatalog.is_air(roster[index]): return index
	return -1

func prepare(game: Node, wave: int=7) -> int:
	game.rounds.wave = wave
	game.rounds.phase = "build"
	game.rounds.begin_warning()
	game.rounds._begin_attack()
	game.rounds.spawned = air_slot(wave)
	game.rounds.spawn_clock = 0.0
	return game.rounds.spawned

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func clear_actors() -> void:
	for enemy in get_nodes_in_group("enemies"): enemy.free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/air-raid-intro"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"storm_dam","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	await process_frame
	var intro: Node = game.air_raid_intro
	intro.set_process(false)
	check(not intro.already_seen() and not intro.active,"Fresh campaign has no consumed air introduction")
	prepare(game)
	check(not intro.before_spawn(7,air_slot(7),Balance.WAVE_COUNTS[6]),"No introduction without commissioned AA")
	commission(game)
	prepare(game,6)
	check(not intro.before_spawn(6,0,Balance.WAVE_COUNTS[5]),"Flak cannot trigger introduction before wave seven")
	var index := prepare(game)
	check(not intro.before_spawn(7,0,Balance.WAVE_COUNTS[6]),"Ground spawn does not consume introduction")
	game.story.phase_changed()
	check(game.story._said.has("warning_air") == false,"Attack phase itself does not duplicate an air warning")
	game.rounds.phase = "warning"
	game.story.phase_changed()
	check(game.story._said.has("warning_air"),"Existing SAN air warning remains available")
	check(not game.dialogue.pending.any(func(item):return item.id=="crew_air"),"First solo crew-air recording is reserved for preview")
	game.rounds.phase = "attack"
	game.flak_station.turret.hp = 0
	check(not intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Destroyed AA cannot consume first-air preview")
	game.flak_station.turret.hp = game.flak_station.turret.max_hp
	game.network.active = true
	check(not intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Online host with only one current worker never opens solo preview")
	game.network.active = false
	game.player_count = 2
	check(not intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Local co-op remains excluded even if only one worker survives")
	game.player_count = 1
	game.hud.overlay = "pause"
	paused = true
	check(not intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Paused settings/menu cannot start or steal intro pause")
	game.hud.overlay = ""
	paused = false
	game.spawn_enemy(7,0,Balance.WAVE_COUNTS[6])
	var ground: Node2D = get_nodes_in_group("enemies")[0]
	var original_position: Vector2 = ground.position
	var worker_position: Vector2 = game.players[0].position
	var hp: float = game.core.hp
	var game_time: float = game.elapsed
	var weather_time: float = game.weather.elapsed
	var team_time: float = game.combat_events.team.elapsed
	game.rounds._process(.01)
	check(intro.active and paused and game.hud.overlay=="air_raid_intro","Actual round scheduler opens paused first-air preview")
	check(game.rounds.spawned==index and game.rounds.spawn_clock==0.0 and not get_nodes_in_group("enemies").any(func(actor):return actor is AirMachine),"First aircraft and its slot/clock are held until presentation ends")
	check(intro.context.character_id==game.players[0].character_id and intro.context.enemy_kind=="scout_drone" and intro.context.environment=="storm_dam" and intro.context.wave==7,"Context uses actual worker, aircraft and current environment")
	check(intro.duration==8.0 and intro.elapsed==0.0 and game.campaign.air_raid_intro_seen,"Eight-second preview is consumed once at entry")
	intro.skip()
	check(intro.active,"Initial input grace prevents a held confirm key skipping immediately")
	game.join_coop()
	check(game.player_count==1 and game.players.size()==1,"Local join cannot mutate party during paused presentation")
	for key: Key in [KEY_F2,KEY_F4,KEY_F5,KEY_T,KEY_P,KEY_N]: press(key)
	await process_frame
	for frame in 5: await process_frame
	check(game.hud.overlay=="air_raid_intro" and intro.active,"Menu, restart, join and research shortcuts cannot steal the intro")
	check(game.elapsed==game_time and game.weather.elapsed==weather_time and game.combat_events.team.elapsed==team_time,"Simulation, weather and XP participation clocks stay frozen")
	check(ground.position==original_position and game.players[0].position==worker_position and game.core.hp==hp,"Real enemy, worker and bunker remain frozen across render frames")
	game.rounds._process(100.0)
	check(game.rounds.spawned==index and game.rounds.spawn_clock==0.0,"Even explicit round advancement cannot bypass active preview")
	intro.advance(INF)
	intro.advance(-1.0)
	check(intro.elapsed==0.0,"Invalid/negative time cannot advance or corrupt preview")
	intro.advance(7.99)
	check(intro.active and paused,"World remains paused throughout the authored duration")
	Input.action_press("p1_fire")
	press(KEY_SPACE)
	await process_frame
	await process_frame
	check(not intro.active and not paused and game.hud.overlay.is_empty(),"Space skips and releases only the intro pause")
	check(not Input.is_action_pressed("p1_fire") and not Input.is_action_pressed("p1_jump"),"Skip does not leak a held shot or jump into resumed gameplay")
	game.rounds._process(.01)
	check(game.rounds.spawned==index+1 and get_nodes_in_group("enemies").any(func(actor):return actor is AirMachine),"Exactly the held aircraft spawns after preview")
	clear_actors()
	index = prepare(game,11)
	check(not intro.before_spawn(11,index,Balance.WAVE_COUNTS[10]),"Subsequent aircraft do not replay preview")
	var retry: Dictionary = {"checkpoint":game.campaign.checkpoint(),"mode":"defense","options":game.scenario_options.duplicate()}
	check(preload("res://scripts/expedition_controller.gd").valid_transition(retry),"Seen marker remains valid in real retry/transition payload")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"First real scene releases audio and input services")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	check(game.expedition.restore(retry) and game.air_raid_intro.already_seen(),"Fresh scene retry restores campaign introduction state")
	game.rounds.set_process(false)
	commission(game)
	index = prepare(game)
	check(not game.air_raid_intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Retrying a lost mission does not repeat the introduction")
	# Prepared fresh presentation state exercises automatic completion separately
	# from the input-driven first sequence; this never writes a player profile.
	game.campaign.air_raid_intro_seen = false
	intro = game.air_raid_intro
	intro.set_process(false)
	check(intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Fresh presentation fixture opens automatically")
	intro.advance(8.0)
	await process_frame
	await process_frame
	check(not intro.active and not paused and game.hud.overlay.is_empty(),"Eight seconds completes automatically without waiting for input")
	game.campaign.air_raid_intro_seen = false
	check(intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Independent cancellation fixture owns its pause")
	game.hud.overlay = "help"
	intro.advance(.1)
	await process_frame
	await process_frame
	check(not intro.active and paused and game.hud.overlay=="help","Cancelling presentation never closes or unpauses an unrelated overlay")
	game.hud.overlay = ""
	paused = false
	game.join_coop()
	game.campaign.air_raid_intro_seen = false
	check(game.players.size()==2 and not intro.before_spawn(7,index,Balance.WAVE_COUNTS[6]),"Real two-worker local co-op never enters solo presentation")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Retry scene releases cleanly")
	test_persistence()
	print("AIR RAID INTRO: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)

func test_persistence() -> void:
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
	var state := CampaignState.new(SAVE,false)
	state.persistence_enabled = true
	check(state.begin_new(ScenarioCatalog.validate({}),["mara"],1),"Isolated test campaign saves initial safe state")
	var safe := state.checkpoint()
	state.mission_start()
	# These intentionally unsafe live changes must never enter a cosmetic save.
	state.player_count = 4
	state.expedition.tech_points = 99
	state.expedition.garage_stock = {"steel":777}
	check(state.mark_air_raid_intro_seen(),"Seen marker updates the durable safe departure")
	var loaded := CampaignState.new(SAVE,false)
	loaded.persistence_enabled = true
	check(loaded.load_checkpoint() and loaded.air_raid_intro_seen,"Quit/continue keeps the introduction consumed")
	safe.air_raid_intro_seen = true
	check(JSON.parse_string(JSON.stringify(loaded.checkpoint()))==JSON.parse_string(JSON.stringify(safe)),"Cosmetic persistence changes only seen flag, never party/research/materials")
	var legacy := safe.duplicate(true)
	legacy.erase("air_raid_intro_seen")
	check(CampaignState.valid_checkpoint(legacy),"Existing version-two checkpoint remains accepted")
	loaded._restore(legacy)
	check(not loaded.air_raid_intro_seen,"Legacy checkpoint migration defaults to an unseen introduction")
	var invalid := safe.duplicate(true)
	invalid.air_raid_intro_seen = "true"
	check(not CampaignState.valid_checkpoint(invalid),"Malformed presentation flag is rejected before state mutation")
	loaded.persistence_enabled = false
	check(loaded.begin_new(ScenarioCatalog.validate({}),["mara"],1) and not loaded.air_raid_intro_seen,"A genuinely new campaign resets introduction state")
	loaded.save_path = "res://artifacts/air-raid-intro/missing-parent/test.json"
	loaded.persistence_enabled = true
	check(not loaded.mark_air_raid_intro_seen() and loaded.air_raid_intro_seen,"Failed cosmetic write preserves in-memory once state without fabricating a combat save")
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))
