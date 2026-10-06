extends SceneTree
## Real existing machine bodies/worker hitboxes; only positions and timers arranged.
class CoreProbe extends Node2D:
	var hp := 10000.0
	func take_damage(value): hp -= value
class Arena extends Node2D:
	var started := false
	var core
	var upgrades
	var stats := {"kills":0}
	var drops: Dictionary = {}
	var impacts: Array = []
	func sound(_kind): pass
	func notify(_text): pass
	func fx(_at,_color,_count): pass
	func impact(at,impact_material,normal=Vector2.LEFT,power=1.0): impacts.append([at,impact_material,normal,power])
	func spawn_pickup(kind,amount,_at): drops[kind] = int(drops.get(kind,0))+amount
var checks := 0
var failures := 0
var arena
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int):
	for i in count: await physics_frame
func machine(kind: String,x: float):
	var result = load("res://scenes/enemy.tscn").instantiate()
	result.kind = kind
	result.game = arena
	result.position = Vector2(x,430)
	arena.add_child(result)
	result.set_physics_process(false)
	result.worker_attack_clock = 100
	return result
func worker(id: int,point: Vector2):
	var result = load("res://scenes/player.tscn").instantiate()
	result.player_id = id
	result.game = arena
	result.position = point
	arena.add_child(result)
	result.set_physics_process(false)
	result.get_node("WorkerWeapon").set_physics_process(false)
	return result
func blocker(rect: Rect2):
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	arena.add_child(body)
	return body
func run():
	InputSetup.install()
	arena = Arena.new()
	root.add_child(arena)
	arena.core = CoreProbe.new()
	arena.core.position = Vector2(200,430)
	arena.add_child(arena.core)
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.initial_state = 4
	wall.game = arena
	wall.position = Vector2(600,430)
	arena.add_child(wall)
	wall.hp = 1000
	wall.max_hp = 1000
	var p1 = worker(1,Vector2(100,600))
	var p2 = worker(2,Vector2(140,600))
	var guard = machine("shield_guard",676)
	var lancer = machine("lancer",860)
	var sniper = machine("sniper",845)
	var demolisher = machine("demolisher",682)
	var medic = machine("repair_crawler",1700)
	var bastion = machine("bastion",744)
	var variants := [guard,lancer,sniper,demolisher,medic,bastion]
	for enemy in variants:
		check(is_instance_valid(enemy.abilities) and enemy.body_part.has_node("VariantEquipment") and enemy.BODY_REGIONS.has(enemy.chassis_kind()),"%s has a real ability and separately animated equipment on a valid original chassis" % enemy.kind)
	await frames(3)
	var hp: float = guard.hp
	guard.take_damage(30)
	check(guard.hp==hp and guard.abilities.shield_hp==30,"Closed shield absorbs actual incoming damage into its finite sixty-point charge")
	guard.take_damage(50)
	check(guard.hp==hp-20 and guard.abilities.shield_hp==0,"An overloaded shield passes only excess damage to actual machine health")
	guard.take_damage(10)
	check(guard.hp==hp-30,"Broken shield exposes the machine until the next timed cycle")
	guard.abilities.update(GroundMachineAbilities.SHIELD_CYCLE+0.01)
	check(guard.abilities.shield_closed() and guard.abilities.shield_hp==60,"Shield regenerates its bounded charge at the next visible cycle")
	guard.abilities.update(GroundMachineAbilities.SHIELD_CLOSED_TIME)
	guard.take_damage(12)
	check(guard.hp==hp-42 and not guard.abilities.shield_closed(),"The scheduled open interval takes full damage even with remaining shield charge")
	lancer.attack_clock = 0
	var before_x: float = lancer.position.x
	lancer._physics_process(0.01)
	lancer._physics_process(0.5)
	check(lancer.abilities.rush_warning>0 and lancer.position.x==before_x and lancer.attack_count==0,"Lancer visibly braces for three quarters of a second before advancing or striking")
	lancer._physics_process(0.26)
	check(lancer.abilities.rush_time>0 and lancer.locomotion_speed>lancer.move_speed,"Completed warning produces a real faster ground charge")
	wall.hp = 1000
	for step in 70:
		lancer._physics_process(0.05)
		if lancer.attack_count>0: break
	check(lancer.position.x>=wall.position.x+lancer.attack_reach-0.01,"The accelerated charge stops at the first intact wall without tunnelling")
	check(lancer.attack_count==1 and is_equal_approx(wall.hp,1000-lancer.attack_damage*1.65),"Only the first successful charge strike receives the extra impact damage")
	check(not lancer.abilities.rush_primed and lancer.abilities.rush_cooldown>0,"A charge consumes its bonus and cannot restart before its cooldown")
	wall.hp = 1000
	sniper.attack_clock = 0
	sniper._physics_process(1.0)
	check(sniper.attack_count==0 and wall.hp==1000 and sniper.windup>0,"Long-range cannon visibly charges before any damage")
	sniper._physics_process(0.36)
	check(sniper.attack_count==1 and wall.hp==1000-sniper.attack_damage,"The charged rifle strikes a real wall from its 245-pixel range")
	check(sniper.worker_windup_duration()==1.35 and sniper.profile.worker_range==295,"Player targeting shares the long warning and extended range")
	var cover = blocker(Rect2(710,330,12,100))
	await frames(2)
	sniper.attack_clock = 0
	sniper.windup = 0
	hp = wall.hp
	sniper._physics_process(1.36)
	check(sniper.attack_count==1 and wall.hp==hp,"Charged long-range attacks cannot pass intervening solid terrain")
	cover.free()
	p1.position = Vector2(675,430)
	p2.position = Vector2(560,430)
	await frames(3)
	wall.hp = 1000
	demolisher.attack_clock = 0
	demolisher._physics_process(1.2)
	check(wall.hp==1000 and p1.hp==100 and p2.hp==100,"Demolition hammer has a long visible windup before its impact and shockwave")
	demolisher._physics_process(0.51)
	check(wall.hp==1000-demolisher.attack_damage and demolisher.abilities.shock_flash>0,"Hammer impact applies its heavy real wall damage and visible shockwave")
	check(p1.hp==86 and p2.hp==100,"Shockwave injures the nearby exposed worker while intact concrete protects the worker behind it")
	p1.position = Vector2(100,600)
	p2.position = Vector2(140,600)
	var patient = machine("strider",1770)
	patient.hp = 10
	await frames(3)
	check(medic.abilities.try_repair()==16 and patient.hp==26 and medic.abilities.repair_remaining==48,"Repair crawler transfers a sixteen-HP pulse from finite spare parts into a living ally")
	cover = blocker(Rect2(1735,340,12,90))
	await frames(2)
	check(medic.abilities.try_repair()==0 and patient.hp==26 and medic.abilities.repair_remaining==48,"A concrete obstruction blocks support repairs without wasting spare parts")
	cover.free()
	patient.hp = patient.max_hp-3
	await frames(2)
	check(medic.abilities.try_repair()==3 and patient.hp==patient.max_hp and medic.abilities.repair_remaining==45,"Repairs clamp to missing health and spend only the actual restored amount")
	for i in 8:
		patient.hp = 10
		medic.abilities.try_repair()
	check(medic.abilities.repair_remaining==0 and medic.abilities.repaired_total==64,"All support healing is bounded to sixty-four HP per crawler")
	patient.hp = 0
	patient.dead = true
	medic.abilities.repair_remaining = 16
	check(medic.abilities.try_repair()==0 and patient.hp==0 and medic.abilities.repair_remaining==16,"A destroyed machine cannot be resurrected or consume a repair pulse")
	wall.hp = 1000
	bastion.attack_clock = 0
	hp = bastion.hp
	bastion.take_damage(100)
	check(bastion.hp==hp-65,"Closed Bastion armor reduces actual incoming damage by thirty-five percent")
	bastion._physics_process(0.71)
	for i in 5: bastion._physics_process(0.16)
	check(bastion.attack_count==6 and is_equal_approx(wall.hp,1000-6*bastion.attack_damage),"Bastion fires six independently damaging rounds with individual shot timing")
	check(bastion.abilities.vent_time>0 and bastion.burst_remaining==0,"Completed sustained salvo opens the cooling plates and stops firing")
	hp = bastion.hp
	bastion.take_damage(40)
	check(bastion.hp==hp-40,"Open cooling plates expose full machine health to counterfire")
	var shots: int = bastion.attack_count
	bastion._physics_process(1.0)
	check(bastion.attack_count==shots,"The cooling window cannot emit extra salvo shots")
	bastion._physics_process(1.41)
	hp = bastion.hp
	bastion.take_damage(20)
	check(is_equal_approx(bastion.hp,hp-13) and bastion.abilities.heat==0,"Cooling resets the finite heat cycle and restores armor")
	for enemy in variants:
		enemy.take_damage(10000)
		enemy.die()
	check(arena.stats.kills==6,"Each new ground class dies and awards one kill without ability-driven resurrection")
	arena.free()
	print("GROUND ABILITIES: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
