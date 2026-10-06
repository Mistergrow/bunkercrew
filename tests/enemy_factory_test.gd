extends SceneTree
## Main-scene factory and actual damage-credit integration for all registered enemy IDs.
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	game.rounds.set_process(false)
	game.players[0].set_physics_process(false)
	game.combat_events.persistence_enabled = false
	# Aircraft require a commissioned tower. Prepare its paid construction buffer;
	# the separate air-unlock integration covers the actual material transfers.
	game.rounds.wave = 6
	game.flak_station.unlock()
	game.flak_station.materials = FlakStation.SPECS[1].cost.duplicate()
	game.flak_station.interact(game.players[0],3.0)
	var seen: Dictionary = {}
	for wave in range(1,21):
		game.rounds.wave = wave
		game.rounds.phase = "build"
		game.rounds.begin_warning()
		var count: int = Balance.WAVE_COUNTS[wave-1]
		var roster := EnemyCatalog.wave_roster(wave,count)
		for i in count:
			var kind: String = roster[i]
			if seen.has(kind): continue
			game.spawn_enemy(wave,i,count)
			var enemy = get_nodes_in_group("enemies")[-1]
			enemy.set_physics_process(false)
			var airborne := AirEnemyCatalog.is_air(kind)
			check(enemy.kind==kind and ((enemy is AirMachine and enemy.is_in_group("air_enemies")) if airborne else (enemy is SiegeMachine and not enemy.is_in_group("air_enemies"))),"Main factory instantiates %s with its correct movement scene and target group" % kind)
			seen[kind] = true
			enemy.free()
	check(seen.size()==EnemyCatalog.CLASS_ORDER.size(),"Every registered enemy class is reachable through the actual twenty-wave factory")
	for position_mode in ["left","center","right"]:
		check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Previous factory fixture releases before changing scenario")
		game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(1,{"environment":"sector07","build_type":"workshop","position":position_mode})
		game.rounds.set_process(false)
		game.players[0].set_physics_process(false)
		game.combat_events.persistence_enabled=false
		check(game.scenario_combat!=null and game.scenario_combat.position_mode==position_mode,"Factory fixture uses the actual "+position_mode+" scenario")
		for vehicle_kind in EnemyCatalog.VEHICLE_CLASSES:
			var intro_wave: int=EnemyCatalog.INTRO_WAVES[vehicle_kind]
			game.spawn_enemy(intro_wave,0,Balance.WAVE_COUNTS[intro_wave-1])
			var vehicle=get_nodes_in_group("enemies")[-1]
			vehicle.set_physics_process(false)
			check(vehicle.kind==vehicle_kind and vehicle.get_script().resource_path=="res://scripts/enemy.gd" and vehicle.profile.legs==0,"%s: vehicle %s uses its own wheeled/tracked profile in the real first spawn slot"%[position_mode,vehicle_kind])
			check(vehicle.attack_direction==(-1.0 if vehicle.position.x>game.scenario_combat.core_x else 1.0),"%s: vehicle %s points toward the actual scenario defenses"%[position_mode,vehicle_kind])
			vehicle.free()
		for team_wave in [6,8,10,12,14,20]:
			var team_roster:=EnemyCatalog.wave_roster(team_wave,Balance.WAVE_COUNTS[team_wave-1],false)
			var direction:=0.0
			var slots: Array[int]=[]
			for slot in team_roster.size():
				if not EnemyCatalog.is_human(team_roster[slot]): continue
				game.spawn_enemy(team_wave,slot,team_roster.size())
				var unit=get_nodes_in_group("human_enemies")[-1]
				unit.set_physics_process(false)
				if direction==0: direction=unit.attack_direction
				check(unit.kind==team_roster[slot] and unit.attack_direction==direction and unit.get_script().resource_path=="res://scripts/ground_infantry.gd","%s wave%d: complete fireteam enters one shared side with its actual role"%[position_mode,team_wave])
				slots.append(unit.squad_slot)
			check(slots==[0,1,2],"%s wave%d: all three formation slots stay distinct without a required grenadier leader"%[position_mode,team_wave])

	var player = game.players[0]
	var guard = game.ENEMY.instantiate()
	guard.kind = "shield_guard"
	guard.game = game
	guard.position = Vector2(1040,430)
	game.add_child(guard)
	guard.set_physics_process(false)
	var hp: float = guard.hp
	var xp: float = player.progression.xp
	check(game.combat_hit(guard,40,player)==0 and guard.hp==hp and player.progression.xp==xp,"A real absorbed shield hit awards no false damage XP")
	check(game.combat_hit(guard,35,player)==15 and guard.hp==hp-15 and is_equal_approx(player.progression.xp-xp,1.5),"Shield overflow credits only fifteen HP actually removed")
	guard.abilities.update(GroundMachineAbilities.SHIELD_CLOSED_TIME+0.01)
	check(game.combat_hit(guard,20,player)==20,"The real combat dispatcher sees the vulnerable shield interval")
	var bastion = game.ENEMY.instantiate()
	bastion.kind = "bastion"
	bastion.game = game
	game.add_child(bastion)
	bastion.set_physics_process(false)
	xp = player.progression.xp
	check(is_equal_approx(game.combat_hit(bastion,20,player),13) and is_equal_approx(player.progression.xp-xp,1.3),"Armor reduction also credits only actual health removed")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Factory scene and audio release cleanly")
	print("ENEMY FACTORY: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
