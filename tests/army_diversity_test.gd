extends "res://tests/ground_infantry_test.gd"
## Actual profile, wave factory, projectile and treatment behavior. Positions and
## cooldowns are prepared; recipients, obstacles and projectiles remain real.

func ability_state(unit) -> Dictionary:
	var result := {}
	for field in SCHEMA.fields("ground_machine_abilities"): result[field]=unit.abilities.get(field)
	return result

func ready_medic(unit):
	unit.abilities.repair_clock=0
	unit.abilities.repair_flash=0
	unit.hit_flash=0
	unit.stagger=0

func run():
	InputSetup.install()
	var all_seen := {}
	for wave in range(1,21):
		for with_air in [false,true]:
			var count: int=Balance.WAVE_COUNTS[wave-1]
			var roster := EnemyCatalog.wave_roster(wave,count,with_air)
			check(roster.size()==count,"Wave %d air=%s preserves its finite total"%[wave,with_air])
			var humans: Array[String]=[]
			var ground_intro := true
			var air_count := 0
			for kind in roster:
				all_seen[kind]=true
				ground_intro=ground_intro and int(EnemyCatalog.INTRO_WAVES[kind])<=wave
				if EnemyCatalog.is_human(kind): humans.append(kind)
				if AirEnemyCatalog.is_air(kind): air_count+=1
			check(ground_intro,"Wave %d air=%s never introduces a class early"%[wave,with_air])
			check(humans==EnemyCatalog.human_fireteam(wave),"Wave %d air=%s selects its complete three-person team"%[wave,with_air])
			check(air_count<=EnemyCatalog.air_limit(wave) and (with_air or air_count==0),"Wave %d keeps its air budget and ground-only fallback"%wave)
			if wave in [5,10,15,20]:
				check(not EnemyCatalog.is_human(roster[-1]) and not AirEnemyCatalog.is_air(roster[-1]),"Wave %d milestone remains a ground elite/boss"%wave)
			for kind in EnemyCatalog.GROUND_CLASSES:
				if not EnemyCatalog.is_human(kind) and int(EnemyCatalog.INTRO_WAVES[kind])==wave:
					check(roster.has(kind),"Wave %d retains %s machine introduction"%[wave,kind])
	check(all_seen.size()==EnemyCatalog.CLASS_ORDER.size(),"All six human roles and existing machines/aircraft occur in the campaign")
	check(EnemyCatalog.human_fireteam(6)==["grenadier","rifle_guard","rifle_guard"],"Wave six retains its original grenadier and two covering guards")
	for count in [0,1,2,3,4]:
		check(EnemyCatalog.wave_roster(20,count).size()==count,"Small synthetic count %d never expands to fit a fireteam"%count)
	arena=InfantryArena.new()
	root.add_child(arena)
	arena.core=CoreProbe.new()
	arena.core.position=Vector2(200,430)
	arena.add_child(arena.core)
	blocker(Rect2(0,430,2600,30))
	for kind in EnemyCatalog.HUMAN_CLASSES:
		var specimen=troop(kind,2200)
		var state := {}
		for field in SCHEMA.fields("ground_infantry"): state[field]=specimen.get(field)
		check(SCHEMA.valid_state("ground_infantry",state),kind+" accepts the strict human wire type")
		check(not SCHEMA.valid_state("enemy",state),kind+" cannot masquerade as a machine on the wire")
		check(specimen.abilities.projectile_attack(),kind+" uses physical hostile ordnance")
		specimen.free()
	var medic=troop("combat_medic",1800)
	var patient=troop("heavy_gunner",1860)
	var robot=machine("strider",1850)
	medic.hp-=10
	patient.hp-=50
	robot.hp=1
	await frames(3)
	ready_medic(medic)
	var before: float=patient.hp
	check(medic.abilities.try_treat() and patient.hp==before and medic.abilities.repair_remaining==60,"Treatment announces a full channel without immediate healing")
	check(medic.abilities.blocks_action() and not medic.abilities.fire_projectiles(Vector2(1600,390),5),"Treating medic stops movement and cannot fire its rifle simultaneously")
	medic.abilities.update(.6)
	check(patient.hp==before and medic.abilities.repair_flash>0,"Partial treatment time cannot grant health")
	medic.abilities.update(.41)
	check(patient.hp==before+20 and medic.abilities.repair_remaining==40 and medic.abilities.repaired_total==20,"Completed treatment moves exactly twenty HP from finite medicine")
	check(robot.hp==1 and medic.hp==medic.max_hp-10,"Treatment neither repairs machines nor heals the medic itself")
	check(not medic.abilities.try_treat(),"Treatment cannot be repeated during its cooldown")
	check(SCHEMA.valid_state("ground_machine_abilities",ability_state(medic)),"Treatment endpoint, channel and supply use existing valid replicated fields")
	var invalid := ability_state(medic)
	invalid.repair_remaining=61.0
	check(not SCHEMA.valid_state("ground_machine_abilities",invalid),"Wire schema rejects an oversized medicine reserve")
	invalid=ability_state(medic)
	invalid.repaired_total=61.0
	check(not SCHEMA.valid_state("ground_machine_abilities",invalid),"Wire schema rejects healing beyond lifetime supply")
	ready_medic(medic)
	check(medic.abilities.try_treat(),"Second injured-ally channel begins when cooldown is ready")
	var cover=blocker(Rect2(1826,340,8,90))
	await frames(2)
	before=patient.hp
	medic.abilities.update(1.01)
	check(patient.hp==before and medic.abilities.repair_remaining==40 and not medic.abilities.blocks_action(),"New solid cover cancels treatment without spending medicine")
	ready_medic(medic)
	check(not medic.abilities.try_treat(),"Concrete also prevents treatment from starting")
	cover.free()
	await frames(2)
	patient.position.x=1900
	ready_medic(medic)
	check(not medic.abilities.try_treat(),"An ally beyond ninety-six pixels cannot receive treatment")
	patient.position.x=1860
	ready_medic(medic)
	medic.abilities.try_treat()
	patient.position.x=1940
	medic.abilities.update(1.01)
	check(patient.hp==before and medic.abilities.repair_remaining==40,"Leaving reach during the channel cancels healing")
	patient.position.x=1860
	ready_medic(medic)
	medic.abilities.try_treat()
	medic.take_damage(3)
	# Simulate a long next physics step, which has already retired hit flashes.
	medic.stagger=0
	medic.hit_flash=0
	medic.abilities.update(1.01)
	check(patient.hp==before and medic.abilities.repair_remaining==40,"Damage interrupts even if a slow next frame has retired the hit flash")
	patient.hp=0
	patient.dead=true
	ready_medic(medic)
	check(not medic.abilities.try_treat(),"No self-heal, machine heal or resurrection is available when every ally is dead")
	patient.dead=false
	patient.hp=patient.max_hp-4
	ready_medic(medic)
	medic.abilities.try_treat()
	medic.abilities.update(1.01)
	check(patient.hp==patient.max_hp and medic.abilities.repair_remaining==36,"Small wounds spend only actual restored HP without overheal")
	for unused in 4:
		patient.hp=1
		ready_medic(medic)
		if medic.abilities.try_treat(): medic.abilities.update(1.01)
	check(medic.abilities.repair_remaining==0 and medic.abilities.repaired_total==60,"Repeated real channels cannot restore more than sixty lifetime HP")
	var guest_medic=troop("combat_medic",1780)
	arena.network=SessionProbe.new()
	arena.add_child(arena.network)
	ready_medic(guest_medic)
	before=patient.hp
	check(not guest_medic.abilities.try_treat(),"A guest cannot begin an authoritative treatment")
	guest_medic.abilities.update(1.01)
	check(patient.hp==before and guest_medic.abilities.repair_remaining==60,"Guest ability updates cannot spend medicine or alter ally health")
	arena.network.active=false
	guest_medic.free()
	var line_medic=troop("combat_medic",600+float(EnemyCatalog.PROFILES.combat_medic.reach))
	for role in EnemyCatalog.HUMAN_CLASSES:
		if role=="combat_medic": continue
		var line_ally=troop(role,600+float(EnemyCatalog.PROFILES[role].reach))
		line_ally.hp-=2
		await frames(2)
		ready_medic(line_medic)
		var started: bool=line_medic.abilities.try_treat()
		line_medic.abilities.update(1.01)
		check(started and line_ally.hp==line_ally.max_hp,"Medic can reach a "+role+" at its own real stopping distance")
		line_ally.free()
	line_medic.free()
	medic.free()
	patient.free()
	robot.free()
	var wall=load("res://scenes/wall.tscn").instantiate()
	wall.game=arena
	wall.initial_state=4
	wall.position=Vector2(600,430)
	arena.add_child(wall)
	wall.hp=10000
	wall.max_hp=10000
	var heavy=troop("heavy_gunner",880)
	heavy.attack_clock=0
	await frames(2)
	heavy._physics_process(1.11)
	for unused in 3: heavy._physics_process(.19)
	await settle_shots()
	check(heavy.attack_count==4 and is_equal_approx(wall.hp,10000-4*heavy.attack_damage),"Heavy gunner braces then fires four timed physical rounds into cover")
	check(heavy.burst_remaining==0 and heavy.attack_clock>0,"Heavy gunner ends the bounded salvo and enters its reload pause")
	var marksman=troop("marksman",975)
	marksman.attack_clock=0
	before=wall.hp
	marksman._physics_process(1.60)
	check(marksman.attack_count==0 and marksman.abilities.aim_locked,"Marksman advertises a fixed aim for its long windup")
	marksman._physics_process(.06)
	await settle_shots()
	check(marksman.attack_count==1 and wall.hp==before-marksman.attack_damage,"Marksman single physical round reaches its extended 375-pixel firing line")
	marksman.free()
	var victim=worker(1,Vector2(760,430))
	victim.max_hp=1000
	victim.hp=1000
	await frames(3)
	heavy.attack_clock=100
	heavy.worker_attack_clock=0
	var shots_before: int=heavy.attack_count
	heavy._physics_process(1.11)
	check(heavy.burst_remaining==3 and heavy.abilities.blocks_action(),"Heavy gunner starts a real timed player-directed salvo and stays braced")
	for unused in 3: heavy._physics_process(.19)
	check(heavy.attack_count==shots_before+4 and heavy.burst_remaining==0,"Player-directed suppression emits exactly four independently spawned rounds")
	await settle_shots()
	check(victim.hp<1000,"At least one real burst round physically reaches the exposed player")
	victim.invulnerability=0
	heavy.worker_attack_clock=0
	heavy._physics_process(1.11)
	var cover2=blocker(Rect2(820,330,12,100))
	await frames(2)
	shots_before=heavy.attack_count
	heavy._physics_process(.19)
	check(heavy.attack_count==shots_before and heavy.burst_remaining==0,"New cover cancels the remaining player-directed burst")
	cover2.free()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(arena,self),"Army fixture and physical ordnance clean up")
	print("ARMY DIVERSITY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
