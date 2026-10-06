extends "res://tests/ground_infantry_test.gd"
## Vehicle AI, real swept projectiles, ordinary cover and canonical network state.
## Fixtures prepare floor/target positions; damage uses the production attack path.

func _state(node: Node,entity_kind: String) -> Dictionary:
	var result: Dictionary={}
	for field in SCHEMA.fields(entity_kind): result[field]=node.get(field)
	return result

func _clear_rounds() -> void:
	for shot in get_nodes_in_group("air_projectiles"): shot.free()

func _cycle(unit) -> void:
	unit.attack_clock=0
	unit.windup=0
	unit.burst_remaining=0
	unit._physics_process(float(unit.profile.windup)*.65)
	unit._physics_process(float(unit.profile.windup)*.36)
	for index in int(unit.profile.burst)-1:
		unit._physics_process(float(unit.profile.burst_gap)+.01)

func _check_rosters() -> void:
	check(EnemyCatalog.VEHICLE_CLASSES==["scout_car","mortar_carrier","battle_tank"],"Three stable vehicle IDs have an explicit class family")
	check(EnemyCatalog.CLASS_ORDER.size()==33 and EnemyCatalog.GROUND_CLASSES.size()==21,"Catalog includes twelve walkers, three vehicles, six humans and twelve aircraft")
	var seen: Dictionary={}
	var vehicle_waves: Dictionary={"scout_car":[],"mortar_carrier":[],"battle_tank":[]}
	for allow_air in [false,true]:
		for wave in range(1,21):
			var count: int=Balance.WAVE_COUNTS[wave-1]
			var roster:=EnemyCatalog.wave_roster(wave,count,allow_air)
			check(roster.size()==count and roster==EnemyCatalog.wave_roster(wave,count,allow_air),"Wave%d air=%s preserves its deterministic finite population"%[wave,allow_air])
			check(roster.all(func(kind):return EnemyCatalog.INTRO_WAVES[kind]<=wave),"Wave%d air=%s never spawns a class before its introduction"%[wave,allow_air])
			var humans: Array[String]=[]
			for kind in roster:
				if EnemyCatalog.is_human(kind): humans.append(kind)
				if allow_air: seen[kind]=true
			check(humans==EnemyCatalog.human_fireteam(wave),"Wave%d air=%s preserves the exact three-person role pattern"%[wave,allow_air])
			check(roster.filter(func(kind):return AirEnemyCatalog.is_air(kind)).size()==(EnemyCatalog.air_limit(wave) if allow_air else 0),"Wave%d air=%s preserves its aircraft budget"%[wave,allow_air])
			for kind in EnemyCatalog.VEHICLE_CLASSES:
				if allow_air and kind in roster: vehicle_waves[kind].append(wave)
				if wave==EnemyCatalog.INTRO_WAVES[kind]: check(roster[0]==kind,"%s keeps dedicated introduction slot zero with air=%s"%[kind,allow_air])
			for kind in AirEnemyCatalog.CLASS_ORDER:
				if allow_air and wave==AirEnemyCatalog.INTRO_WAVES[kind]: check(kind in roster,"Aircraft %s retains its real introduction wave"%kind)
			if wave in [5,10,15,20]:
				var last_kind: String="breaker" if wave==5 else ("siege" if wave==20 else "colossus")
				check(roster[-1]==last_kind and EnemyCatalog.is_elite(wave,count-1,count),"Wave%d retains its final elite or boss chassis"%wave)
	for wave in range(1,21):
		var count: int=int(ceil(Balance.WAVE_COUNTS[wave-1]*Balance.wave_multiplier(2)))
		for allow_air in [false,true]:
			var roster:=EnemyCatalog.wave_roster(wave,count,allow_air)
			check(roster.size()==count and roster.all(func(kind):return EnemyCatalog.INTRO_WAVES[kind]<=wave),"Coop wave%d air=%s preserves its scaled count and unlocks"%[wave,allow_air])
			var human_roles:=roster.filter(func(kind):return EnemyCatalog.is_human(kind))
			check(human_roles==EnemyCatalog.human_fireteam(wave),"Coop wave%d air=%s keeps one bounded three-person fireteam"%[wave,allow_air])
	check(seen.size()==33,"All thirty-three classes occur in the actual solo campaign")
	for kind in EnemyCatalog.VEHICLE_CLASSES:
		check(vehicle_waves[kind].size()>=5 and vehicle_waves[kind][-1]>=18,"%s returns meaningfully after its introduction: %s"%[kind,vehicle_waves[kind]])
	check(not EnemyCatalog.is_vehicle("scout") and not EnemyCatalog.is_human("scout_car"),"Recon infantry and wheeled reconnaissance remain separate families")

func _exercise_vehicle(kind: String,direction: float,wall) -> void:
	var spec:=EnemyCatalog.profile(kind)
	var unit=machine(kind,wall.position.x-direction*(float(spec.reach)+90))
	unit.attack_direction=direction
	unit.attack_clock=0
	unit._pose_parts()
	await frames(2)
	var tag: String="%s approach%s"%[kind,"left" if direction>0 else "right"]
	for index in 240:
		if absf(unit.position.x-wall.position.x)<=unit.attack_reach+.001: break
		unit._physics_process(.05)
	check(is_equal_approx(absf(unit.position.x-wall.position.x),unit.attack_reach) and unit.attack_count==0,tag+" drives to its actual standoff distance before firing")
	check(unit.profile.legs==0 and unit.profile.chassis==kind and unit.abilities.projectile_attack(),tag+" uses its own vehicle body and physical weapon path")
	wall.hp=10000
	arena.impacts.clear()
	unit._physics_process(float(spec.windup)*.65)
	check(unit.windup>0 and unit.abilities.aim_locked and unit.attack_count==0 and wall.hp==10000 and get_nodes_in_group("ground_ordnance").is_empty(),tag+" visibly prepares without instant or hidden damage")
	if kind=="mortar_carrier": check(absf(unit.abilities.warning_point.x-wall.position.x)<22,tag+" ballistic warning marks the actual target face")
	# Observe the emission instant before the same tick applies visible recoil.
	var launch_errors: Array[float]=[]
	var launch_warnings: Array[Vector2]=[]
	var launch_alignment: Array[float]=[]
	var observe_launch:=func(child: Node):
		if child.is_in_group("ground_ordnance"):
			launch_errors.append(child.global_position.distance_to(unit.weapon_part.to_global(unit.weapon_muzzle())))
			launch_warnings.append(unit.abilities.warning_point)
			var barrel: Vector2=unit.weapon_part.to_global(unit.weapon_muzzle())-unit.weapon_part.global_position
			launch_alignment.append(barrel.normalized().dot(child.velocity.normalized()))
	arena.child_entered_tree.connect(observe_launch)
	unit._physics_process(float(spec.windup)*.36)
	arena.child_entered_tree.disconnect(observe_launch)
	check(unit.attack_count==1 and wall.hp==10000 and get_nodes_in_group("ground_ordnance").size()==1,tag+" releases one swept projectile and leaves damage to its flight")
	if not get_nodes_in_group("ground_ordnance").is_empty():
		var shot=get_nodes_in_group("ground_ordnance")[0]
		check(launch_errors.size()==1 and launch_errors[0]<.01,tag+" projectile starts exactly at the drawn barrel tip before recoil")
		check(launch_alignment.size()==1 and launch_alignment[0]>.999,tag+" projectile velocity follows the drawn elevated weapon bore")
		check(signf(shot.velocity.x)==direction and shot.flavor==("grenade" if kind=="mortar_carrier" else "tracer"),tag+" physical ordnance travels toward the target")
		check((shot.gravity==380 and shot.velocity.y<0) if kind=="mortar_carrier" else (shot.gravity==0 and is_equal_approx(shot.velocity.length(),640)),tag+" weapon has its distinct physical trajectory")
		check(SCHEMA.valid_state("hostile_air_projectile",_state(shot,"hostile_air_projectile")),tag+" physical projectile is a valid canonical network entity")
	for index in int(spec.burst)-1: unit._physics_process(float(spec.burst_gap)+.01)
	check(unit.attack_count==int(spec.burst) and unit.burst_remaining==0 and unit.attack_clock>0,tag+" ends its bounded salvo in a real cooldown")
	await settle_shots()
	check(is_equal_approx(wall.hp,10000-float(spec.burst)*unit.attack_damage),tag+" physical impacts apply exactly the intended finite damage")
	if kind=="mortar_carrier":
		var error: float=launch_warnings[0].distance_to(arena.impacts[0][0]) if not launch_warnings.is_empty() and not arena.impacts.is_empty() else INF
		check(error<2.0,tag+" warning matches the real impact after deployment (error %.2f px)"%error)
	var shots: int=unit.attack_count
	unit._physics_process(float(spec.cooldown)*.5)
	check(unit.attack_count==shots and get_nodes_in_group("ground_ordnance").is_empty(),tag+" reload interval produces no extra shot")
	check(SCHEMA.valid_state("enemy",_state(unit,"enemy")) and SCHEMA.valid_state("ground_machine_abilities",_state(unit.abilities,"ground_machine_abilities")),tag+" vehicle and ability retain canonical replication state")
	var midpoint: float=(unit.position.x+wall.position.x)*.5
	var cover=blocker(Rect2(midpoint-8,100,16,330))
	await frames(2)
	wall.hp=10000
	_cycle(unit)
	await settle_shots()
	check(wall.hp==10000,tag+" tall cover catches every real projectile without damage leaking through")
	if kind=="mortar_carrier":
		unit.abilities.prepare_attack(unit.target_attack_point())
		check(absf(unit.abilities.warning_point.x-midpoint)<10,tag+" ballistic brackets stop at the first actual intervening obstacle")
	cover.free()
	cover=blocker(Rect2(midpoint-8,374,16,56))
	await frames(2)
	wall.hp=10000
	_cycle(unit)
	await settle_shots()
	check(is_equal_approx(wall.hp,10000-(unit.attack_damage if kind=="mortar_carrier" else 0.0)),tag+" mortar clears low cover while the direct-fire car is stopped by it")
	cover.free()
	await frames(2)
	unit.abilities.aim_locked=false
	var old_aim: Vector2=unit.abilities.aim_point
	arena.network.active=true
	shots=unit.attack_count
	unit.abilities.prepare_attack(Vector2(100,100))
	check(not unit.abilities.fire_projectiles(unit.target_attack_point(),28) and unit.attack_count==shots and not unit.abilities.aim_locked and unit.abilities.aim_point==old_aim,tag+" guest cannot aim, spawn ordnance or deal authority damage")
	arena.network.active=false
	unit.weapon_recoil=0
	unit._pose_parts()
	var muzzle_box=blocker(Rect2(unit.weapon_part.global_position-Vector2(5,5),Vector2(10,10)))
	await frames(2)
	wall.hp=10000
	_cycle(unit)
	check(unit.attack_count==shots and wall.hp==10000 and get_nodes_in_group("ground_ordnance").is_empty(),tag+" obstructed weapon cannot bypass its muzzle with hitscan damage")
	muzzle_box.free()
	unit.free()
	await frames(2)

func _exercise_workers(wall) -> void:
	for direction in [-1.0,1.0]:
		var car=machine("scout_car",wall.position.x-direction*220)
		car.attack_direction=direction
		car.target=wall
		car._pose_parts()
		car.attack_clock=100
		car.worker_attack_clock=0
		var victim=worker(1,Vector2(car.position.x+direction*125,430))
		victim.max_hp=1000
		victim.hp=1000
		await frames(2)
		car._physics_process(.81)
		check(car.worker_attack_count==1 and car.burst_remaining==2 and car.abilities.blocks_action(),"Recon car braces through its real player-directed three-round burst from direction%s"%direction)
		for index in 2: car._physics_process(.21)
		check(car.worker_attack_count==3 and car.attack_count==3 and car.burst_remaining==0,"Recon car player suppression ends after exactly three spawned rounds")
		await settle_shots()
		check(victim.hp<1000 and victim.hp>=985,"Recon rounds physically hit the worker with no damage beyond their finite salvo")
		car.worker_attack_clock=0
		car._physics_process(.81)
		var cover=blocker(Rect2((car.position.x+victim.position.x)*.5-5,320,10,110))
		await frames(2)
		var shots: int=car.attack_count
		car._physics_process(.21)
		check(car.attack_count==shots and car.burst_remaining==0,"New intervening cover cancels the remaining player-directed car burst")
		_clear_rounds()
		cover.free()
		victim.free()
		car.free()
		await frames(2)

func _exercise_budget(wall) -> void:
	var carrier=machine("mortar_carrier",wall.position.x+390)
	carrier.target=wall
	carrier._pose_parts()
	await frames(2)
	wall.hp=10000
	for index in GroundMachineAbilities.MAX_GROUND_ORDNANCE:
		check(carrier.abilities.fire_projectiles(carrier.target_attack_point(),28),"Available shared ordnance slot%d accepts one real shell"%index)
	var shots: int=carrier.attack_count
	check(get_nodes_in_group("ground_ordnance").size()==18 and not carrier.abilities.fire_projectiles(carrier.target_attack_point(),28),"Eighteen active rounds strictly bound the mixed ground ordnance population")
	_cycle(carrier)
	check(carrier.attack_count==shots and wall.hp==10000,"Full projectile budget cannot fall back to immediate mortar damage")
	var first=get_nodes_in_group("ground_ordnance")[0]
	first.free()
	check(carrier.abilities.fire_projectiles(carrier.target_attack_point(),28) and get_nodes_in_group("ground_ordnance").size()==18,"A released ordnance slot admits exactly one replacement shell")
	_clear_rounds()
	carrier.free()
	await frames(2)

func run() -> void:
	InputSetup.install()
	_check_rosters()
	arena=InfantryArena.new()
	root.add_child(arena)
	arena.network=SessionProbe.new()
	arena.network.active=false
	arena.add_child(arena.network)
	arena.core=CoreProbe.new()
	arena.core.position=Vector2(200,430)
	arena.add_child(arena.core)
	blocker(Rect2(0,430,1600,30))
	var wall=preload("res://scenes/wall.tscn").instantiate()
	wall.game=arena
	wall.initial_state=4
	wall.position=Vector2(700,430)
	arena.add_child(wall)
	wall.max_hp=10000
	wall.hp=10000
	await frames(2)
	for kind in EnemyCatalog.VEHICLE_CLASSES:
		for direction in [-1.0,1.0]: await _exercise_vehicle(kind,direction,wall)
	await _exercise_workers(wall)
	await _exercise_budget(wall)
	check(await preload("res://tests/scene_cleanup.gd").free_scene(arena,self),"Vehicle fixture releases all physics and ordnance cleanly")
	print("MECHANIZED ARMY: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
