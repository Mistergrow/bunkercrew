extends SceneTree
## Paid orders, personal ownership, grounded placement and actual combat devices.
const Workshop = preload("res://scripts/field_workshop.gd")
const Defense = preload("res://scripts/field_defense.gd")

class PersonalEquipment extends Node:
	var armor_tier := 0
	func equip_armor(tier: int) -> bool:
		if tier != armor_tier+1 or tier>2:
			return false
		armor_tier = tier
		return true

class TestPlayer extends Node2D:
	var game: Node
	var player_id := 1
	var inventory := {}
	var selected_kind := ""
	var progression: Node
	var mounted_turret: Node2D
	var focus: Node2D
	var facing := 1.0
	var down := false
	func _ready():
		add_to_group("players")
		progression = PersonalEquipment.new()
		add_child(progression)
	func action(suffix): return "p%d_%s"%[player_id,suffix]
	func can_act(): return not down
	func is_downed(): return down
	func carried_count():
		var total := 0
		for value in inventory.values(): total += int(value)
		return total
	func add_item(kind,amount):
		var accepted := mini(amount,6-carried_count())
		if accepted>0:
			inventory[kind] = int(inventory.get(kind,0))+accepted
		return accepted
	func take_item(kind,amount):
		if int(inventory.get(kind,0))<amount: return false
		inventory[kind] -= amount
		return true
	func selected_material(): return selected_kind

class TestWorld extends Node2D:
	var players: Array = []
	var world_right := 1400.0
	var ladders: Array[Rect2] = []
	var core: Node2D
	var stats := {"kills":0}
	var credits: Array = []
	var drops: Array = []
	func sound(_kind): pass
	func notify(_message): pass
	func fx(_pos,_color,_count): pass
	func impact(_pos,_kind,_dir=Vector2.UP,_power=1.0): pass
	func spawn_pickup(kind,amount,pos): drops.append([kind,amount,pos])
	func combat_hit(enemy,damage,player):
		var before: float = enemy.hp
		enemy.take_damage(damage)
		credits.append([player,minf(before,damage)])

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func box(world,rect: Rect2,layer:=1):
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var geometry := RectangleShape2D.new()
	geometry.size = rect.size
	shape.shape = geometry
	body.position = rect.get_center()
	body.add_child(shape)
	world.add_child(body)
	return body
func deposit(bench,worker,count: int):
	for i in count: bench.interact(worker,Balance.TRANSFER_TIME)
func machine(world,at: Vector2,health:=500.0):
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.game = world
	enemy.position = at
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.max_hp = health
	enemy.hp = health
	return enemy
func clear_devices():
	for node in get_nodes_in_group("field_defenses"): node.queue_free()
	for node in get_nodes_in_group("enemies"): node.queue_free()
	await process_frame
	await physics_frame

func run():
	InputSetup.install()
	var world := TestWorld.new()
	root.add_child(world)
	world.core = Node2D.new()
	world.add_child(world.core)
	var bench := Workshop.new()
	bench.game = world
	world.add_child(bench)
	bench.set_process(false)
	var p1 := TestPlayer.new()
	var p2 := TestPlayer.new()
	p1.game = world
	p2.game = world
	p2.player_id = 2
	world.add_child(p1)
	world.add_child(p2)
	world.players = [p1,p2]
	check(not bench.is_in_group("stations"),"Field bench cannot enter production-only focus APIs")
	p1.inventory = {"steel":2}
	deposit(bench,p1,1)
	check(p1.inventory.steel==1 and bench.order_for(p1).materials.steel==1,"One held transfer consumes exactly one actual steel")
	bench.cycle_recipe(p1)
	check(bench.recipe_index(p1)==1 and bench.recipe_index(p2)==0,"Blueprint selection belongs to the individual player")
	check(bench.order_for(p1,0).materials.steel==1,"Switching blueprints retains deposited materials")
	bench.selection[1]=0
	deposit(bench,p1,1)
	check(bench.order_for(p1).working and p1.inventory.steel==0,"Only a fully paid order starts manufacturing")
	bench._process(2.1)
	p1.inventory = {"sand":6}
	bench.interact(p1,1)
	check(bench.order_for(p1).ready and not p1.inventory.has("jaw_trap"),"Full hands retain the finished kit at the bench")
	bench.interact(p2,1)
	check(not p2.inventory.has("jaw_trap") and bench.order_for(p1).ready,"P2 cannot claim P1's completed order")
	p1.inventory.clear()
	bench.interact(p1,1)
	check(p1.inventory.jaw_trap==1 and not bench.order_for(p1).ready,"Owner collects exactly one paid kit")
	bench.interact(p1,10)
	check(p1.inventory.jaw_trap==1,"Holding interact cannot duplicate a completed kit")
	bench.selection[1]=3
	p1.inventory={"alloy":3,"steel":2}
	deposit(bench,p1,8)
	check(p1.carried_count()==5 and bench.order_for(p1).materials.is_empty(),"Armor II is blocked before armor I without consuming ingredients")
	bench.selection[1]=2
	p1.inventory={"steel":3}
	deposit(bench,p1,3)
	bench._process(3.1)
	bench.selection[2]=2
	bench.interact(p2,1)
	check(p2.progression.armor_tier==0,"Another worker cannot equip a personal armor order")
	bench.interact(p1,1)
	check(p1.progression.armor_tier==1 and p1.carried_count()==0,"Paid armor I equips its actual owner")
	p1.inventory={"steel":3}
	deposit(bench,p1,3)
	check(p1.inventory.steel==3,"Already equipped armor does not consume duplicate payment")
	bench.selection[1]=3
	p1.inventory={"alloy":3,"steel":2}
	deposit(bench,p1,5)
	bench._process(4.1)
	bench.interact(p1,1)
	check(p1.progression.armor_tier==2 and p1.carried_count()==0,"Armor II consumes exactly its alloy and steel cost")
	bench.selection[1]=4
	p1.inventory={"steel":4}
	deposit(bench,p1,4)
	check(not bench.order_for(p1).working and bench.order_for(p1).materials.steel==4,"Gun fabrication retains a partial delivery across material trips")
	p1.inventory={"concrete":2}
	deposit(bench,p1,2)
	bench._process(4.1)
	bench.interact(p1,1)
	check(p1.inventory.sentry_kit==1 and p1.carried_count()==1,"Four steel plus two concrete produce one gun kit")
	box(world,Rect2(0,430,1440,22))
	p1.position=Vector2(980,430)
	p1.selected_kind="sentry_kit"
	await physics_frame
	await physics_frame
	check(bench.placement_point(p1,"sentry_kit")==Vector2(1028,430),"Placement requires continuous supported exterior ground")
	p1.position.y=600
	check(not bench.deploy(p1) and p1.inventory.sentry_kit==1,"Underground deployment is rejected before consuming the kit")
	p1.position=Vector2(700,430)
	check(not bench.deploy(p1) and p1.inventory.sentry_kit==1,"Interior deployment cannot seal bunker routes")
	p1.position=Vector2(980,430)
	var obstruction=box(world,Rect2(998,350,8,80),2)
	await physics_frame
	await physics_frame
	check(not bench.deploy(p1) and p1.inventory.sentry_kit==1,"No gun kit can be placed through an intact wall")
	obstruction.queue_free()
	await process_frame
	await physics_frame
	world.ladders=[Rect2(1020,350,30,85)]
	check(not bench.deploy(p1),"Placement protects a ladder access footprint")
	world.ladders.clear()
	var front_enemy=machine(world,Vector2(1028,430))
	await physics_frame
	await physics_frame
	check(not bench.deploy(p1),"Placement cannot build inside an enemy")
	front_enemy.queue_free()
	await process_frame
	await physics_frame
	check(bench.deploy(p1) and p1.inventory.sentry_kit==0,"Valid grounded construction consumes the kit once")
	var gun: Node=get_nodes_in_group("field_defenses")[0]
	gun.set_physics_process(false)
	gun.turret.set_physics_process(false)
	check(gun.is_blocking() and gun.turret.ammo==0 and gun.turret.reserve==0,"Crafted gun is a real destructible obstacle without free ammunition")
	p1.inventory={"jaw_trap":1}
	p1.selected_kind="jaw_trap"
	check(not bench.deploy(p1) and p1.inventory.jaw_trap==1,"Device spacing prevents overlapping field constructions")
	p1.inventory={"ammo":1}
	gun.turret.enter(p1)
	check(gun.turret.occupant==p1 and p1.mounted_turret==gun.turret,"Crafted field gun uses the real enter/occupy flow")
	check(gun.turret.start_reload() and p1.inventory.ammo==0,"Reload consumes one real carried ammunition box")
	gun.turret._physics_process(1.2)
	check(gun.turret.ammo==20 and gun.turret.reserve==0,"Crafted gun reload produces exactly twenty rounds")
	await physics_frame
	await physics_frame
	check(gun.turret.fire() and gun.turret.ammo==19,"Actual mounted gun can shoot above its grounded base collider")
	var attacker=machine(world,gun.position+Vector2(55,0))
	await physics_frame
	await physics_frame
	attacker.target=attacker.nearest_obstacle()
	check(attacker.target==gun and attacker.attack_obstacle() and gun.hp<gun.max_hp,"Real enemy collision shot damages the crafted gun before advancing to the bunker")
	gun.take_damage(180)
	check(gun.spent and not gun.is_blocking() and p1.mounted_turret==null,"Destroyed field gun opens the route and releases its operator")
	await process_frame
	await clear_devices()
	var jaw:=Defense.new()
	jaw.game=world
	jaw.builder=p1
	jaw.position=Vector2(1080,430)
	world.add_child(jaw)
	jaw.set_physics_process(false)
	var target=machine(world,Vector2(1086,430))
	check(not jaw.trigger(target),"A newly deployed trap cannot trigger before its arming delay")
	jaw.arming=0
	check(jaw.trigger(target) and target.hp==430 and jaw.charges==2,"Armed jaws deal actual paid device damage and consume one charge")
	check(target.stagger>=1.8 and world.credits.back()[0]==p1,"Jaw slow and real damage are attributed to their builder")
	jaw.cooldown=0
	check(not jaw.trigger(target) and target.hp==430,"One trapped machine cannot farm repeated damage and XP charges")
	for i in 2:
		var another=machine(world,Vector2(1082+i,430))
		jaw.cooldown=0
		check(jaw.trigger(another),"Jaw charge %d works on a new machine"%[i+2])
	check(jaw.spent and jaw.charges==0,"Three triggers exhaust the jaw trap permanently")
	await clear_devices()
	var mine:=Defense.new()
	mine.game=world
	mine.builder=p2
	mine.kind="blast_trap"
	mine.position=Vector2(1080,430)
	world.add_child(mine)
	mine.set_physics_process(false)
	mine.arming=0
	var exposed=machine(world,Vector2(1084,430))
	var splash=machine(world,Vector2(1020,430))
	var protected=machine(world,Vector2(1140,430))
	var distant=machine(world,Vector2(1250,430))
	obstruction=box(world,Rect2(1110,350,10,80),2)
	await physics_frame
	await physics_frame
	check(mine.trigger(exposed),"Mine triggers when a machine crosses its actual trigger radius")
	check(exposed.hp==260 and splash.hp==260,"Mine explosion damages nearby exposed machines")
	check(protected.hp==500 and distant.hp==500,"Blast respects intact walls and its finite radius")
	check(world.credits.back()[0]==p2,"Explosion combat credit belongs to the player who deployed it")
	check(mine.spent and not mine.trigger(exposed),"Explosion is single-use without repeated damage")
	check(p1.progression.armor_tier==2 and not p1.down and not p2.down,"Traps leave friendly workers and their equipment unchanged")
	obstruction.queue_free()
	await clear_devices()
	p1.inventory={"jaw_trap":1}
	p1.selected_kind="jaw_trap"
	p1.position=Vector2(1260,430)
	check(not bench.deploy(p1) and p1.inventory.jaw_trap==1,"Placement obeys current stage boundary")
	world.world_right=1840
	p1.position=Vector2(1500,430)
	check(not bench.deploy(p1),"Unlocked bounds alone cannot place a device over unsupported air")
	p1.down=true
	p1.position=Vector2(980,430)
	check(not bench.deploy(p1) and p1.inventory.jaw_trap==1,"Downed workers cannot build or lose cargo")
	world.queue_free()
	await process_frame
	print("FIELD CRAFTING: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
