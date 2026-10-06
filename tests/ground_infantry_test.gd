extends "res://tests/ground_abilities_test.gd"
## Actual human bodies and swept grenades; no synthetic damage dispatcher.
class SessionProbe extends Node:
	var active:=true
	var is_host:=false
class InfantryArena extends Arena:
	var network: Node
	var story: Node
class StoryProbe extends Node:
	var warnings: Array[String]=[]
	func once(id: String,_cooldown: float): warnings.append(id)
const SCHEMA=preload("res://scripts/network_replication_schema.gd")

func troop(kind: String,x: float,slot: int=0):
	var result=preload("res://scenes/ground_infantry.tscn").instantiate()
	result.kind=kind
	result.squad_slot=slot
	result.game=arena
	result.position=Vector2(x,430)
	arena.add_child(result)
	result.set_physics_process(false)
	result.worker_attack_clock=100
	result.stance=1.0
	result._pose_parts()
	return result

func settle_shots():
	for index in 190:
		if get_nodes_in_group("air_projectiles").is_empty(): return
		await physics_frame

func run():
	InputSetup.install()
	arena=InfantryArena.new()
	root.add_child(arena)
	arena.core=CoreProbe.new()
	arena.core.position=Vector2(200,430)
	arena.add_child(arena.core)
	arena.story=StoryProbe.new()
	arena.add_child(arena.story)
	var floor_body=blocker(Rect2(0,430,1500,30))
	var wall=preload("res://scenes/wall.tscn").instantiate()
	wall.initial_state=4
	wall.game=arena
	wall.position=Vector2(600,430)
	arena.add_child(wall)
	wall.hp=1000
	wall.max_hp=1000
	var grenadier=troop("grenadier",920)
	var guard=troop("rifle_guard",820,1)
	var guard2=troop("rifle_guard",850,2)
	await frames(3)
	for unit in [grenadier,guard,guard2]:
		check(unit.is_in_group("human_enemies") and unit.infantry.visible and not unit.body_part.visible and not unit.legs_part.visible,"Human anatomy replaces every mechanical body/leg on "+unit.kind)
		check(ImpactBurst.material_for(unit)=="flesh","Human impacts use the existing cloth/flesh feedback")
		check(unit.weather_feet().size()==2 and unit.weather_segments().size()==3,"Animated human feet and helmet expose real weather anchors")
		check(is_equal_approx(unit.get_node("MachineHitbox").shape.size.y,55*unit.visual_scale),"Kneeling lowers the actual collision silhouette")
		var state: Dictionary={}
		for field in SCHEMA.fields("ground_infantry"): state[field]=unit.get(field)
		check(SCHEMA.valid_state("ground_infantry",state),"Complete human state is accepted by the strict wire schema")
		state.stance=2.0
		check(not SCHEMA.valid_state("ground_infantry",state),"Out-of-range remote kneeling state is rejected")
	check(is_equal_approx(grenadier.wetness.stride_weight(),.82),"Human footsteps keep ordinary boot weight instead of heavy machine impacts")
	check(guard.attack_reach!=guard2.attack_reach,"Covering riflemen settle at distinct distances instead of stacking")
	guard.hp-=20
	var repairer=machine("repair_crawler",870)
	check(repairer.abilities.try_repair()==0 and guard.hp==guard.max_hp-20,"Repair crawler cannot weld health into a human soldier")
	repairer.free()
	var hp: float=wall.hp
	grenadier.target=wall
	grenadier.attack_clock=0
	grenadier._physics_process(.1)
	check(grenadier.windup>0 and grenadier.attack_count==0 and get_nodes_in_group("air_projectiles").is_empty(),"Grenadier gives a full preparation window before spawning ordnance")
	check(arena.story.warnings.has("warning_grenadier") and grenadier.abilities.aim_locked,"Preparation routes the localized voiced cover warning and locks its aim")
	var warning: Vector2=grenadier.abilities.warning_point
	check(warning.distance_to(wall.global_position)<85,"Warning brackets are anchored to actual target geometry")
	grenadier._physics_process(1.41)
	check(grenadier.attack_count==1 and wall.hp==hp,"Release launches one real grenade and cannot damage the wall instantly")
	var shot=get_nodes_in_group("air_projectiles")[0]
	check(shot.flavor=="grenade" and shot.gravity==380 and shot.velocity.y<0,"The small grenade has a real rising ballistic arc")
	await settle_shots()
	check(wall.hp==hp-grenadier.attack_damage,"Unobstructed physical grenade applies exactly one wall hit")
	var cover=blocker(Rect2(725,120,22,310))
	await frames(2)
	hp=wall.hp
	grenadier.abilities.prepare_attack((wall.global_position-Vector2(0,40)))
	check(grenadier.abilities.warning_point.x>720,"Telegraph stops at the first intervening solid cover")
	check(grenadier.abilities.fire_projectiles((wall.global_position-Vector2(0,40)),20),"Grenade can be released toward intervening terrain")
	await settle_shots()
	check(wall.hp==hp,"A real barrier catches the grenade without blast damage passing through")
	check(guard.abilities.fire_projectiles((wall.global_position-Vector2(0,40)),7),"Covering rifleman creates a bounded physical bullet")
	await settle_shots()
	check(wall.hp==hp,"Rifle rounds also stop at the first solid cover")
	cover.free()
	await frames(2)
	var prior_shots: int=guard.attack_count
	guard.target=wall
	guard.attack_clock=0
	guard._physics_process(.76)
	guard._physics_process(.25)
	await settle_shots()
	check(guard.attack_count==prior_shots+2 and wall.hp==hp-guard.attack_damage*2,"Covering rifleman fires its two-round burst with exactly two physical impacts")
	var mirrored=troop("grenadier",280)
	mirrored.attack_direction=1.0
	mirrored.target=wall
	mirrored._pose_parts()
	hp=wall.hp
	mirrored.abilities.prepare_attack(wall.global_position-Vector2(0,40))
	mirrored.abilities.fire_projectiles(wall.global_position-Vector2(0,40),20)
	await settle_shots()
	check(wall.hp==hp-20,"A mirrored human fires the same real ballistic trajectory from the opposite approach")
	mirrored.free()
	var worker_target=worker(1,Vector2(745,430))
	await frames(2)
	worker_target.position=Vector2(800,430)
	await frames(2)
	var muzzle_hp: float=worker_target.hp
	guard.abilities.fire_projectiles(wall.global_position-Vector2(0,40),7)
	await frames(2)
	check(worker_target.hp==muzzle_hp-7,"A player intersecting the visible barrel receives the first hit instead of being skipped")
	worker_target.position=Vector2(745,430)
	worker_target.invulnerability=0
	await frames(2)
	var player_hp: float=worker_target.hp
	grenadier.abilities.prepare_attack(worker_target.global_position-Vector2(0,23))
	var locked: Vector2=grenadier.abilities.aim_point
	worker_target.position=Vector2(1100,430)
	await frames(2)
	grenadier.abilities.fire_projectiles(worker_target.global_position-Vector2(0,23),18)
	check(grenadier.tracer_end==grenadier.to_local(locked),"A released grenade keeps its advertised aim instead of tracking an escaping player")
	await settle_shots()
	check(worker_target.hp==player_hp,"A player who leaves the marked position avoids the real grenade")
	arena.network=SessionProbe.new()
	arena.add_child(arena.network)
	var fired: int=grenadier.attack_count
	check(not grenadier.abilities.fire_projectiles((wall.global_position-Vector2(0,40)),20) and grenadier.attack_count==fired,"A guest cannot create authoritative grenades or damage")
	arena.network.active=false
	var obstruction=blocker(Rect2(grenadier.weapon_part.global_position-Vector2(3,8),Vector2(35,16)))
	await frames(2)
	check(not grenadier.abilities.fire_projectiles((wall.global_position-Vector2(0,40)),20),"A blocked muzzle cannot launch through nearby solid geometry")
	obstruction.free()
	for index in 18: guard.abilities.fire_projectiles(wall.global_position-Vector2(0,40),7)
	var capped_count: int=guard.attack_count
	check(get_nodes_in_group("ground_ordnance").size()==18 and not guard.abilities.fire_projectiles(wall.global_position-Vector2(0,40),7) and guard.attack_count==capped_count,"Eighteen in-flight ground rounds form a hard per-game limit")
	for item in get_nodes_in_group("ground_ordnance"): item.free()
	arena.impacts.clear()
	var corpse_before:=get_nodes_in_group("infantry_remains").size()
	var kills_before: int=arena.stats.kills
	grenadier.take_damage(10000)
	grenadier.take_damage(10000)
	check(arena.stats.kills==kills_before+1 and arena.drops.scrap==1 and arena.drops.core==2,"Defeat awards finite loot and one kill despite repeated damage")
	check(get_nodes_in_group("infantry_remains").size()==corpse_before+1,"Human defeat leaves one finite animated collapse")
	check(arena.impacts.all(func(item):return item[1]!="explosion"),"Human bodies do not explode into mechanical wreckage")
	await frames(2)
	check(not is_instance_valid(grenadier),"Defeated soldiers release combat nodes immediately")
	var remain=get_nodes_in_group("infantry_remains")[0]
	var age_before: float=remain.corpse_age
	paused=true
	for index in 3: await process_frame
	check(remain.corpse_age==age_before,"Pause freezes the human collapse")
	paused=false
	remain._process(3.1)
	await process_frame
	check(get_nodes_in_group("infantry_remains").is_empty(),"Finite corpse lifetime releases the visual without persistent scene clutter")
	for index in 20:
		var casualty=troop("rifle_guard",1000,1)
		casualty.die()
	check(get_nodes_in_group("infantry_remains").filter(func(node):return not node.is_queued_for_deletion()).size()==16,"Twenty simultaneous defeats respect the hard sixteen-remains budget")
	floor_body.free()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(arena,self),"Human test scene releases cleanly")
	print("GROUND INFANTRY: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
