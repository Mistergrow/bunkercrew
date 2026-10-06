extends SceneTree

class CoreStub extends Node2D:
	var hp := 450.0
	func take_damage(value: float) -> void:
		hp -= value

class PointsStub extends Node:
	var points := 0
	func add_points(amount: int) -> void:
		points += amount

class GameStub extends Node2D:
	var core
	var upgrades
	var drops: Dictionary = {}
	var stats := {"kills":0}
	func fx(_pos, _color, _count): pass
	func sound(_kind): pass
	func spawn_pickup(kind: String, amount: int, _pos: Vector2) -> void:
		drops[kind] = int(drops.get(kind,0))+amount

class Collector extends Node2D:
	var inventory := {"sand":6}
	func carried_count() -> int: return 6
	func add_item(_kind, _amount):
		push_error("Upgrade points must never enter carried inventory")
		return 0

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func run_checks() -> void:
	check(EnemyCatalog.CLASS_ORDER.size()==33 and EnemyCatalog.GROUND_CLASSES.size()==21 and EnemyCatalog.VEHICLE_CLASSES.size()==3 and EnemyCatalog.HUMAN_CLASSES.size()==6 and AirEnemyCatalog.CLASS_ORDER.size()==12,"Catalog exposes twelve walkers, three vehicles, six infantry roles and twelve aircraft")
	var seen: Dictionary = {}
	for wave in range(1,21):
		var count := int(Balance.WAVE_COUNTS[wave-1])
		var roster := EnemyCatalog.wave_roster(wave,count)
		check(roster.size() == count and roster == EnemyCatalog.wave_roster(wave,count),"Wave%d preserves count and deterministic composition" % wave)
		for kind: String in roster: seen[kind]=true
		check(roster.filter(func(kind): return AirEnemyCatalog.PROFILES.has(kind)).size()<=EnemyCatalog.air_limit(wave),"Wave%d respects the bounded airborne replacement budget" % wave)
		check(roster.all(func(kind): return int(EnemyCatalog.INTRO_WAVES[kind]) <= wave),"Wave%d never introduces a class prematurely" % wave)
		var elite_count := 0
		for index in count:
			if EnemyCatalog.is_elite(wave,index,count): elite_count += 1
		check(elite_count == (1 if wave in [5,10,15,20] else 0),"Wave%d has exactly the intended milestone elite" % wave)
	check(seen.size()==33,"The real twenty-wave solo roster contains all thirty-three enemy classes")
	for kind in EnemyCatalog.CLASS_ORDER:
		var intro: int = EnemyCatalog.INTRO_WAVES[kind]
		check(EnemyCatalog.wave_roster(intro,12).has(kind),"%s arrives on its specified introduction wave%d" % [kind,intro])
	check(EnemyCatalog.wave_roster(20,0).is_empty(),"Empty roster requests remain empty")
	check(EnemyCatalog.hp_scale(20) == EnemyCatalog.hp_scale(200) and EnemyCatalog.hp_scale(20) <= 1.45,"HP scaling is bounded even beyond the final wave")
	check(EnemyCatalog.speed_scale(20) == EnemyCatalog.speed_scale(200) and EnemyCatalog.speed_scale(20) <= 1.16,"Speed scaling cannot turn heavy machines into sprinters")
	check(EnemyCatalog.damage_scale(20) <= 1.20,"Campaign damage increase remains bounded")
	var game := GameStub.new()
	root.add_child(game)
	game.core = CoreStub.new()
	game.core.position = Vector2(350,200)
	game.add_child(game.core)
	game.upgrades = PointsStub.new()
	game.add_child(game.upgrades)
	var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.position = Vector2(400,200)
	wall.initial_state = 4
	game.add_child(wall)
	var machines: Array[SiegeMachine] = []
	for kind: String in ["runner","strider","breaker","colossus","assault","siege"]:
		var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
		machine.kind = kind
		machine.game = game
		machine.position = Vector2(400+float(EnemyCatalog.profile(kind).reach),200)
		game.add_child(machine)
		machine.set_physics_process(false)
		machines.append(machine)
	var last_wave = load("res://scenes/enemy.tscn").instantiate()
	last_wave.kind = "colossus"
	last_wave.wave = 20
	game.add_child(last_wave)
	last_wave.set_physics_process(false)
	var beyond_campaign = load("res://scenes/enemy.tscn").instantiate()
	beyond_campaign.kind = "colossus"
	beyond_campaign.wave = 200
	game.add_child(beyond_campaign)
	beyond_campaign.set_physics_process(false)
	check(is_equal_approx(last_wave.max_hp,beyond_campaign.max_hp) and last_wave.max_hp <= machines[3].max_hp*1.45,"Actual spawned machines use the bounded HP curve")
	check(is_equal_approx(last_wave.move_speed,beyond_campaign.move_speed) and last_wave.move_speed <= machines[3].move_speed*1.16,"Actual spawned heavy movement uses the bounded speed curve")
	last_wave.free()
	beyond_campaign.free()
	check(machines[1].hp == 90 and machines[1].attack_damage == 12, "Default strider preserves the established combat values")
	check(machines[0].max_hp < machines[1].max_hp and machines[1].max_hp < machines[2].max_hp and machines[2].max_hp < machines[3].max_hp, "Larger classes have genuinely greater durability")
	check(machines[0].move_speed > machines[1].move_speed and machines[2].move_speed > machines[3].move_speed, "Small runners advance faster than heavy walkers")
	check(machines[3].get_node("MachineHitbox").shape.size.y > machines[2].get_node("MachineHitbox").shape.size.y and machines[2].visual_scale > machines[1].visual_scale, "Class size changes actual hitboxes and articulated artwork")
	await physics_frame
	await physics_frame
	check(machines.all(func(machine): return machine.nearest_obstacle()==wall), "Every prepared machine selects the actual wall in its own game")
	for machine in machines:
		wall.hp = wall.max_hp
		machine.attack_clock = 0
		var before := wall.hp
		machine._physics_process(float(machine.profile.windup)*0.8)
		check(wall.hp == before, "%s shows an attack windup before dealing damage" % machine.kind)
		machine._physics_process(float(machine.profile.windup)*0.3)
		check(is_equal_approx(wall.hp,before-machine.attack_damage), "%s applies its own real wall damage" % machine.kind)
	var assault := machines[4]
	wall.hp = wall.max_hp
	assault.windup = 0
	assault.burst_remaining = 0
	assault.attack_clock = 0
	assault._physics_process(float(assault.profile.windup)+0.01)
	var after_first := wall.hp
	assault._physics_process(float(assault.profile.burst_gap)-0.02)
	check(wall.hp == after_first,"Assault burst has a real delay between shots")
	assault._physics_process(0.03)
	assault._physics_process(float(assault.profile.burst_gap))
	check(is_equal_approx(wall.hp,wall.max_hp-3*assault.attack_damage) and assault.burst_remaining == 0,"Assault emits exactly three individually damaging burst shots")
	check(assault.max_hp < machines[1].max_hp and float(machines[5].profile.windup)>1.5 and machines[5].attack_damage>machines[3].attack_damage,"Assault is fragile and siege trades long warning for heavier single damage")
	var heavy := machines[3]
	heavy.position.x = game.core.position.x+heavy.attack_reach
	heavy.target = game.core
	check(not heavy.attack_obstacle() and game.core.hp == 450, "Heavy long-range attack cannot bypass an intact wall to hit the core")
	wall.take_damage(10000)
	await physics_frame
	heavy.target = heavy.nearest_obstacle()
	check(heavy.target == game.core and heavy.attack_obstacle() and game.core.hp == 414, "After a breach the heavy machine reaches and damages the exposed core")
	var dome = load("res://scripts/dome_segment.gd").new()
	dome.game = game
	# A real front spans245..430; the shared constructor places its firing gap
	# at310..404 and the physical lower pane at404..430.
	dome.configure(Vector2(1290,245),Vector2(1290,430),0,true)
	game.add_child(dome)
	dome.set_frame()
	dome.glaze()
	await physics_frame
	await physics_frame
	var glass_ray := PhysicsRayQueryParameters2D.create(Vector2(1380,410),Vector2(1200,410),2)
	var port_ray := PhysicsRayQueryParameters2D.create(Vector2(1380,360),Vector2(1200,360),2)
	var glass_hit: Dictionary = game.get_world_2d().direct_space_state.intersect_ray(glass_ray)
	check(not glass_hit.is_empty() and glass_hit.collider==dome and game.get_world_2d().direct_space_state.intersect_ray(port_ray).is_empty(), "Prepared dome has real lower glass at410 and an open firing window at360")
	for machine in machines:
		machine.position = Vector2(1290+machine.attack_reach,430)
		machine.target = machine.nearest_obstacle()
		var before_glass: float = dome.hp
		check(machine.target == dome and machine.attack_obstacle() and dome.hp < before_glass,"%s hits real dome glass at410 from its articulated weapon" % machine.kind)
	for machine in machines:
		machine.take_damage(10000)
		machine.die()
	check(game.drops.get("core",0) == 13 and game.drops.get("scrap",0) == 12, "Six classes award their specified core and scrap quantities")
	check(game.stats.kills == 6 and get_nodes_in_group("enemies").is_empty(), "Repeated death calls never duplicate rewards or leave a wave blocked")
	var collector := Collector.new()
	collector.position = Vector2(830,600)
	game.add_child(collector)
	collector.add_to_group("players")
	var pickup: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
	pickup.kind = "core"
	pickup.amount = 3
	pickup.position = Vector2(870,600)
	pickup.game = game
	game.add_child(pickup)
	pickup.set_physics_process(false)
	check(not pickup.can_interact(collector), "Glowing upgrade cores do not steal normal interaction focus")
	pickup.interact(collector,1.0)
	check(pickup.amount == 3 and collector.inventory == {"sand":6}, "Upgrade cores cannot enter the carried-material inventory")
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8,60)
	shape.shape = box
	shape.position = Vector2(850,575)
	blocker.add_child(shape)
	game.add_child(blocker)
	await physics_frame
	await physics_frame
	pickup._collect_upgrade_points()
	check(game.upgrades.points == 0 and pickup.amount == 3, "Automatic core collection is blocked by solid geometry")
	blocker.queue_free()
	await physics_frame
	collector.position.y = 550
	pickup._collect_upgrade_points()
	check(game.upgrades.points == 0, "Core absorption cannot cross different bunker floors")
	collector.position.y = 600
	pickup._collect_upgrade_points()
	check(game.upgrades.points == 3 and pickup.amount == 0 and collector.inventory == {"sand":6}, "Nearby cores award shared upgrade points even when the worker carries a full load")
	pickup._collect_upgrade_points()
	check(game.upgrades.points == 3, "Collected core points are awarded exactly once")
	print("ENEMY CLASS CHECKS: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
