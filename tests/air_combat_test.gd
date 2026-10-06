extends SceneTree
## Actual physics projectiles, real worker/dome/loot scenes, then finite rifle
## ammunition and authoritative XP in the main scene. Positions are fixtures.

class TargetProbe extends StaticBody2D:
	var hp := 10000.0
	func take_damage(amount: float): hp -= amount
	func is_blocking(): return hp>0
	func attack_point(): return global_position
	func can_be_targeted(): return hp>0

class AirWorld extends Node2D:
	var started := true
	var core
	var dome
	var upgrades
	var ladders: Array[Rect2] = []
	var floor_levels: Array = [430.0]
	var world_right := 1840.0
	var stats := {"kills":0}
	var impacts: Array = []
	var drops: Array = []
	func get_focus(_worker): return null
	func focus_candidates(_worker)->Array: return []
	func valid_focus(_worker,_target)->bool: return false
	func sound(_kind): pass
	func notify(_message): pass
	func fx(_pos,_color,_count): pass
	func impact(pos,kind,direction=Vector2.LEFT,power=1.0): impacts.append([pos,kind,direction,power])
	func spawn_pickup(kind,amount,pos):
		var pickup = load("res://scenes/resource_pickup.tscn").instantiate()
		pickup.game = self
		pickup.kind = kind
		pickup.amount = amount
		pickup.position = pos
		add_child(pickup)
		drops.append(pickup)

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(condition: bool,label: String):
	checks += 1
	if condition: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int=2):
	for frame in count: await physics_frame
func seconds(duration: float):
	await frames(ceili(duration*Engine.physics_ticks_per_second/Engine.time_scale)+1)
func box(parent,point: Vector2,size: Vector2,layer: int=1,damageable: bool=false):
	var body = TargetProbe.new() if damageable else StaticBody2D.new()
	body.position = point
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
func world():
	var game := AirWorld.new()
	root.add_child(game)
	box(game,Vector2(980,440),Vector2(1950,20))
	game.core = box(game,Vector2(150,390),Vector2(42,78),2,true)
	return game
func machine(game,kind: String,point: Vector2,wave: int=7):
	var enemy = load("res://scenes/air_enemy.tscn").instantiate()
	enemy.game = game
	enemy.kind = kind
	enemy.wave = wave
	enemy.position = point
	game.add_child(enemy)
	return enemy
func worker(game,point: Vector2,id: int=1):
	var player = load("res://scenes/player.tscn").instantiate()
	player.game = game
	player.player_id = id
	player.position = point
	game.add_child(player)
	player.set_physics_process(false)
	return player
func shot(game,point: Vector2,velocity: Vector2,damage: float=15.0,flavor: String="dart",gravity: float=0):
	var projectile := HostileAirProjectile.new()
	projectile.game = game
	projectile.position = point
	projectile.velocity = velocity
	projectile.damage = damage
	projectile.flavor = flavor
	projectile.gravity = gravity
	game.add_child(projectile)
	return projectile

func run():
	InputSetup.install()
	Engine.time_scale = 5.0
	check(AirEnemyCatalog.CLASS_ORDER.size()==12 and AirEnemyCatalog.INTRO_WAVES.values()==[7,9,11,13,16,18,8,10,12,14,15,19],"Twelve canonical aircraft retain the original six waves and add six staggered introductions")
	var game = world()
	var p1 = worker(game,Vector2(900,430))
	var p2 = worker(game,Vector2(600,430),2)
	var enemy = machine(game,"scout_drone",Vector2(1100,125))
	enemy.set_physics_process(false)
	await frames(3)
	check(enemy.visible_worker(p1),"Aircraft can identify an exposed actual worker through a clear ray")
	var hp: float = p1.hp
	enemy._fire_at(p1.global_position-Vector2(0,23))
	check(p1.hp==hp,"Firing does not remotely apply damage before the projectile travels")
	await seconds(1.5)
	check(p1.hp<hp and p2.hp==100,"A real moving hostile projectile damages only the first worker struck")
	check(game.impacts.any(func(event):return event[1]=="flesh"),"Air hit emits the real flesh impact preset")
	var roof = box(game,Vector2(412,245),Vector2(675,18))
	p1.position = Vector2(440,430)
	p1.hp = 100
	p1.invulnerability = 0
	enemy.position = Vector2(1000,100)
	await frames(3)
	check(not enemy.visible_worker(p1),"Roof geometry prevents selecting a covered worker")
	enemy._fire_at(p1.global_position-Vector2(0,23))
	await seconds(2.5)
	check(p1.hp==100,"Roof slab physically stops air ammunition before the covered worker")
	roof.free()
	var pane := DomeSegment.new()
	pane.game = game
	pane.configure(Vector2(700,40),Vector2(700,440),0)
	game.add_child(pane)
	pane.set_frame()
	pane.glaze()
	p1.position = Vector2(660,230)
	enemy.position = Vector2(940,125)
	await frames(3)
	var glass_hp := pane.hp
	var rocket = shot(game,Vector2(900,200),Vector2(-500,0),38,"rocket")
	await seconds(0.7)
	check(not is_instance_valid(rocket) and pane.hp==glass_hp-38 and p1.hp==100,"Intact real dome pane intercepts the heavy shell; blast cannot leak into covered workers")
	check(not enemy.visible_worker(p1),"Aircraft target visibility respects real glazed dome collision")
	pane.take_damage(pane.hp)
	await frames(3)
	shot(game,Vector2(900,207),Vector2(-700,0))
	await seconds(0.6)
	check(p1.hp==85,"After actual glass destruction a new physical shot passes through the breach")
	var thin = box(game,Vector2(820,140),Vector2(2,80),2,true)
	var protected = box(game,Vector2(770,140),Vector2(10,60),2,true)
	await frames(3)
	shot(game,Vector2(900,140),Vector2(-7000,0),17)
	await frames(3)
	check(thin.hp==9983 and protected.hp==10000,"Swept projectile cannot tunnel through a two-pixel obstacle at high speed")
	thin.free()
	protected.free()
	var ally = machine(game,"gunship",Vector2(830,140),9)
	ally.set_physics_process(false)
	var target = box(game,Vector2(720,140),Vector2(12,50),2,true)
	await frames(3)
	var ally_hp: float = ally.hp
	shot(game,Vector2(950,140),Vector2(-800,0),19)
	await seconds(0.6)
	check(ally.hp==ally_hp and target.hp==9981,"Hostile ammunition excludes enemy layer4 and cannot damage allied machines")
	var bomb = shot(game,Vector2(1700,30),Vector2(-15,10),20,"bomb",180)
	var first_velocity: float = bomb.velocity.y
	await seconds(0.4)
	check(is_instance_valid(bomb) and bomb.velocity.y>first_velocity+60 and bomb.position.y>45,"Gravity bomb actually accelerates and follows a curved physical trajectory")
	var stale = shot(game,Vector2(1500,-200),Vector2.ZERO)
	stale.lifetime = 0.25
	await seconds(0.5)
	check(not is_instance_valid(stale),"A missed hostile projectile expires after its finite lifetime")
	game.queue_free()
	await frames(3)

	game = world()
	var wall = box(game,Vector2(845,385),Vector2(28,90),2,true)
	wall.add_to_group("walls")
	var aircraft: Array = []
	for kind in AirEnemyCatalog.CLASS_ORDER:
		var air = machine(game,kind,Vector2(1660,AirEnemyCatalog.PROFILES[kind].lane),int(AirEnemyCatalog.INTRO_WAVES[kind]))
		aircraft.append(air)
	await seconds(7.6)
	check(aircraft.all(func(air):return air.attack_count==0),"Every aircraft gives at least eight seconds of grace after entering the arena")
	var minimum_y := 1000.0
	var maximum_y := -1000.0
	var traced_gravity := false
	for index in 105:
		await frames()
		for air in aircraft:
			if air.kind=="interceptor":
				minimum_y = minf(minimum_y,air.position.y)
				maximum_y = maxf(maximum_y,air.position.y)
		for projectile in get_nodes_in_group("air_projectiles"):
			traced_gravity = traced_gravity or projectile.gravity>0
	for air in aircraft:
		check(air.attack_count>0 and air.position.y>=62 and air.position.y<=178 and air.position.x<=game.world_right-70,"%s moves in visible bounded lanes and fires its real attack" % air.kind)
	check(aircraft[1].attack_count>=3 and aircraft[3].attack_count>=2,"Gunship burst and diving interceptor release their distinct multi-shot patterns")
	check(maximum_y-minimum_y>38 and traced_gravity,"Interceptor makes an actual dive while bomber emits real gravity ordnance")
	check(aircraft[4].position.x>=1390 and aircraft[5].position.x>=1390,"Late aircraft stay outside the dome rather than spawning shots inside its cover")
	var shield = aircraft[4]
	shield.set_physics_process(false)
	shield.windup = 0
	shield.burst_remaining = 0
	shield.age = 1
	var original: float = shield.hp
	shield.take_damage(20)
	check(is_equal_approx(shield.hp,original-10),"Active airship shield reduces actual damage by half without immunity")
	shield.age = 5
	shield.take_damage(20)
	check(is_equal_approx(shield.hp,original-30),"Airship has a real periodic vulnerability window at full damage")
	var doomed = aircraft[5]
	doomed.take_damage(doomed.hp+1)
	await seconds(1.6)
	check(game.stats.kills==1 and game.drops.size()==2,"Destroyed aircraft increments wave kill accounting and creates exactly one scrap/core reward pair")
	check(game.drops.all(func(pile):return pile.global_position.x<game.world_right and pile.global_position.x>1290 and absf(pile.global_position.y-429.5)<2),"Actual salvage physics settles both finite reward piles on reachable outside ground")
	for air in aircraft:
		if is_instance_valid(air): air.set_physics_process(false)
	for index in HostileAirProjectile.MAX_ACTIVE:
		shot(game,Vector2(1800,-200),Vector2.ZERO)
	check(not aircraft[0]._fire_at(Vector2(845,385)),"Global hostile-projectile cap prevents unbounded spawning")
	game.queue_free()
	await frames(3)

	# Actual finite personal weapon and authoritative hit/kill XP integration.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.combat_events.persistence_enabled = false
	main.start(1)
	main.rounds.running = false
	var gunner = main.players[0]
	gunner.position = Vector2(725,245)
	gunner.inventory.clear()
	gunner.facing = 1
	var victim = machine(main,"scout_drone",Vector2(980,105))
	var expected_hp: float = victim.hp
	var rifle = gunner.get_node("WorkerWeapon")
	var ammo_before: int = rifle.total_ammunition()
	var fired := 0
	await frames(3)
	for index in 18:
		if not is_instance_valid(victim): break
		rifle.aim_direction = (victim.global_position+victim.velocity*0.20-rifle.global_position).normalized()
		if rifle.fire(): fired += 1
		await seconds(0.24)
	await seconds(0.7)
	check(not is_instance_valid(victim) and gunner.progression.kills==1,"Actual rifle projectiles can destroy the flying collision hull and credit one personal kill")
	check(rifle.total_ammunition()==ammo_before-fired and fired>0,"Every real shot consumes finite personal ammunition exactly once")
	check(is_equal_approx(gunner.progression.xp,expected_hp*PlayerProgression.XP_PER_DAMAGE+PlayerProgression.XP_PER_KILL),"Authoritative air-hit XP equals real removed HP plus exactly one kill bonus")
	check(main.stats.kills==1,"Air kill leaves no hidden enemy keeping the round alive")
	Engine.time_scale = 1
	var cleanup: bool = await preload("res://tests/scene_cleanup.gd").free_scene(main,self)
	check(cleanup,"Main-scene audio and gameplay resources release cleanly")
	print("AIR COMBAT: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
