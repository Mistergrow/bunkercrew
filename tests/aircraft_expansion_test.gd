extends "res://tests/air_combat_test.gd"
## Profile/firing/replica boundaries use real aircraft and swept projectiles.
## Positions, attack clocks and very durable target panels are prepared fixtures.
const Schema := preload("res://scripts/network_replication_schema.gd")

class SessionProbe extends Node:
	var active := false
	var is_host := true

class WeatherProbe extends Node:
	var reduced_effects := false

class ExpandedWorld extends AirWorld:
	var network: SessionProbe
	var weather: WeatherProbe

func world():
	var game := ExpandedWorld.new()
	game.network = SessionProbe.new()
	game.add_child(game.network)
	game.weather = WeatherProbe.new()
	game.add_child(game.weather)
	root.add_child(game)
	box(game,Vector2(980,440),Vector2(1950,20))
	game.core = box(game,Vector2(845,375),Vector2(120,120),2,true)
	return game

func state(air: Node) -> Dictionary:
	var data := {}
	for field in Schema.fields("air_machine"): data[field]=air.get(field)
	return data

func run():
	InputSetup.install()
	check(AirEnemyCatalog.CLASS_ORDER.size()==12 and AirEnemyCatalog.MAX_ACTIVE==5,"Twelve stable aircraft classes have a finite five-aircraft live budget")
	var seen := {}
	var total_air := 0
	for wave in range(1,21):
		var count: int = Balance.WAVE_COUNTS[wave-1]
		var roster := EnemyCatalog.wave_roster(wave,count)
		var aircraft := roster.filter(func(kind): return AirEnemyCatalog.is_air(kind))
		total_air += aircraft.size()
		for kind in aircraft: seen[kind]=true
		check(aircraft.size()==EnemyCatalog.air_limit(wave),"Wave%d fills its new bounded airborne budget without changing the wave population"%wave)
		check(roster.size()==count and roster==EnemyCatalog.wave_roster(wave,count),"Wave%d preserves deterministic total population"%wave)
		var introduction := AirEnemyCatalog.introduction(wave)
		if not introduction.is_empty(): check(introduction in roster,"%s has a protected introduction in wave%d"%[introduction,wave])
		check(EnemyCatalog.wave_roster(wave,count,false).all(func(kind):return not AirEnemyCatalog.is_air(kind)),"Wave%d remains ground-only without a ready AA defense"%wave)
	check(seen.size()==12 and total_air==40,"All twelve classes appear in 40 finite campaign air slots, versus the former 29")
	for count in range(0,13):
		var small := EnemyCatalog.wave_roster(20,count)
		check(small.size()==count,"Synthetic population%d neither duplicates an air replacement slot nor grows"%count)
	var game = world()
	await frames(3)
	for kind in AirEnemyCatalog.CLASS_ORDER:
		var air = machine(game,kind,Vector2(1600,110),int(AirEnemyCatalog.INTRO_WAVES[kind]))
		air.set_physics_process(false)
		air.flight_presentation.set_process(false)
		air.motion.set_process(false)
		check(air.chassis_atlas!=null and air.chassis_atlas.resource_path==AircraftArtCatalog.TEXTURE_PATH,kind+" uses its independent aircraft alpha crop")
		var region: Rect2 = AircraftArtCatalog.REGIONS[kind]
		check(is_equal_approx(air.profile.body_size.y/air.profile.body_size.x,region.size.y/region.size.x),kind+" preserves the original painted aspect ratio")
		check(air.get_node("AircraftHull").shape.size==AirEnemyCatalog.PROFILES[kind].hitbox*.85,kind+" retains its catalog hull hitbox at the established scale")
		check(Schema.valid_state("air_machine",state(air)),kind+" produces a canonical valid network state")
		air.attack_clock=0
		air._update_attack(float(air.profile.windup)*.60)
		check(air.attack_count==0 and air.windup>0,kind+" warns before launching any physical ordnance")
		air._update_attack(float(air.profile.windup)*.41)
		for index in int(air.profile.burst)-1: air._update_attack(float(air.profile.burst_gap)+.001)
		check(air.attack_count==int(air.profile.burst),kind+" releases exactly its advertised actual projectile burst")
		var shots: Array = get_nodes_in_group("air_projectiles")
		check(shots.size()==int(air.profile.burst) and shots.all(func(projectile):return projectile.game==game and projectile.flavor==air.profile.flavor and projectile.damage>0),kind+" ordnance has its actual owner, flavor and finite positive damage")
		air._physics_process(NAN)
		check(air.age==0 and not air._fire_at(Vector2(INF,0)),kind+" rejects invalid delta and nonfinite aim without mutation")
		game.network.active=true
		game.network.is_host=false
		var hp_before: float = air.hp
		var attacks_before: int = air.attack_count
		var position_before: Vector2 = air.position
		air.take_damage(15)
		air.die()
		air._physics_process(1.0)
		check(not air.dead and air.hp==hp_before and air.position==position_before and not air._fire_at(game.core.position) and air.attack_count==attacks_before,kind+" guest cannot move, fire, damage, die or award loot")
		var panel_hp: float = game.core.hp
		shots[0]._impact(game.core,game.core.position,Vector2.UP)
		check(game.core.hp==panel_hp and not shots[0].spent,kind+" guest cannot force a projectile impact")
		air.age=10
		air.flight_presentation._process(.02)
		var first_clock: float = air.flight_presentation.clock
		air.flight_presentation._process(.04)
		check(air.flight_presentation.clock>first_clock and air.age==10,kind+" frozen replica parent retains cosmetic rotor time without changing authoritative age")
		air.flight_presentation._process(.8)
		check(is_equal_approx(air.flight_presentation.clock,10.12),kind+" cosmetic extrapolation stops at the bounded 120ms window")
		paused=true
		var paused_clock: float = air.flight_presentation.clock
		air.flight_presentation._process(.2)
		check(air.flight_presentation.clock==paused_clock,kind+" paused presentation has no independent animation drift")
		paused=false
		game.weather.reduced_effects=true
		air.flight_presentation._redraw_clock=0
		var rotation_before: float=air.body_part.rotation
		air.flight_velocity=Vector2(60,40)
		air.flight_presentation._process(.01)
		check(air.body_part.rotation==rotation_before,kind+" reduced effects defer cosmetic repaint instead of running at full refresh")
		air.flight_presentation._process(.05)
		check(not is_equal_approx(air.body_part.rotation,rotation_before),kind+" reduced effects still advance the actual bank and propulsion transform")
		game.weather.reduced_effects=false
		game.network.active=false
		if kind in ["interceptor","patrol_plane","dive_bomber","pulse_fighter"]:
			air.entered=true
			air.flight_velocity=Vector2(80,0)
			air._pose_parts()
			var direction: float = air.attack_direction
			check(air.body_part.scale.x<0 and air.weapon_part.scale.x>0,kind+" returning pass faces travel while independent weapon retains the threat side")
			air.flight_velocity=Vector2(-80,0)
			air._pose_parts()
			check(air.body_part.scale.x>0 and air.attack_direction==direction,kind+" forward pass faces travel without changing attack-side semantics")
		for projectile in shots: projectile.free()
		air.free()
	# A translated parent proves shots are placed at the true global muzzle.
	game.position=Vector2(120,10)
	var translated = machine(game,"scout_drone",Vector2(1400,110))
	translated.set_physics_process(false)
	translated._pose_parts(game.core.global_position)
	var expected_origin: Vector2 = translated.muzzle_global()
	translated._fire_at(game.core.global_position)
	var actual = get_nodes_in_group("air_projectiles")[0]
	check(actual.global_position.distance_to(expected_origin)<.1,"Aircraft under a translated world launches from the actual global muzzle")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	check(get_nodes_in_group("air_enemies").is_empty() and get_nodes_in_group("air_projectiles").is_empty(),"Expanded aircraft, cosmetic timers and ordnance release during teardown")
	print("AIRCRAFT EXPANSION: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
