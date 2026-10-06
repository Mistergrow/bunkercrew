extends SceneTree
## Paid AA commissioning/upgrades, finite ammunition, owner credit, collision
## and an actual destructible hull. The small world uses genuine physics rays.
class TestPlayer extends Node2D:
	var player_id:=1
	var inventory: Dictionary={}
	var selected_kind:=""
	var mounted_turret: Node2D
	var focus: Node2D
	var facing:=1.0
	var bonus:=1.0
	var down:=false
	func can_act(): return not down
	func is_downed(): return down
	func selected_material(): return selected_kind
	func action(suffix): return "p%d_%s"%[player_id,suffix]
	func damage_multiplier(): return bonus
	func take_item(kind,amount):
		if int(inventory.get(kind,0))<amount: return false
		inventory[kind]-=amount
		return true
class RoundState extends Node:
	var wave:=5
class World extends Node2D:
	var rounds: Node
	var players: Array=[]
	var ladders: Array[Rect2]=[]
	var floor_levels: Array[float]=[245,430,600,800]
	var credits: Array=[]
	func sound(_kind): pass
	func notify(_message): pass
	func impact(_pos,_kind,_direction=Vector2.UP,_power=1.0): pass
	func fx(_pos,_color,_amount): pass
	func combat_hit(enemy,amount,worker):
		credits.append([worker,amount])
		enemy.take_damage(amount)
	func add_terrain(rect: Rect2):
		var body:=StaticBody2D.new()
		body.collision_layer=1
		body.collision_mask=0
		var shape:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=rect.size
		shape.shape=box
		body.position=rect.get_center()
		body.add_child(shape)
		add_child(body)
		return body
class Target extends StaticBody2D:
	var hp:=1000.0
	var dead:=false
	var flying:=true
	var flight_velocity:=Vector2.ZERO
	var hits:=0
	func _ready():
		collision_layer=4
		collision_mask=0
		add_to_group("enemies")
		if flying: add_to_group("air_enemies")
		var shape:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=Vector2(32,28)
		shape.shape=box
		add_child(shape)
	func take_damage(amount):
		hp=maxf(0.0,hp-amount)
		hits+=1
		dead=hp<=0

var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	print("FLAK ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)
func deposit(station,player,count):
	for i in count: station.interact(player,Balance.TRANSFER_TIME)
func target(world,at: Vector2,flying:=true):
	var node:=Target.new()
	node.flying=flying
	node.position=at
	world.add_child(node)
	return node
func shells(world):
	return world.get_children().filter(func(node):return node is FlakProjectile and not node.is_queued_for_deletion())
func advance_shells(world,time:=0.8):
	for shell in shells(world): shell._physics_process(time)
func frames():
	await process_frame
	await physics_frame
	await physics_frame

func run():
	InputSetup.install()
	var world:=World.new()
	root.add_child(world)
	world.rounds=RoundState.new()
	world.add_child(world.rounds)
	var p1:=TestPlayer.new()
	var p2:=TestPlayer.new()
	p2.player_id=2
	world.add_child(p1)
	world.add_child(p2)
	world.players=[p1,p2]
	var station:=FlakStation.new()
	station.game=world
	station.position=Vector2(515,430)
	world.add_child(station)
	p1.inventory={"steel":3,"concrete":2,"ammo":1}
	deposit(station,p1,9)
	check(not station.built and p1.inventory.steel==3,"A locked flak console cannot consume resources")
	station.unlock()
	deposit(station,p1,9)
	check(not station.built and p1.inventory.ammo==1,"Wave-five construction cannot bypass the wave-six gate")
	check(station.prompt(p1).contains("Baupause Welle 6") and not station.prompt(p1).contains("Material einfüllen"),"The newly revealed console explicitly names its pending wave-six construction gate")
	world.rounds.wave=6
	deposit(station,p1,3)
	check(station.materials.steel==3 and not station.built,"Partial steel stays in a shared physical construction buffer")
	deposit(station,p1,3)
	check(not station.built and p1.inventory.ammo==0 and station.materials.ammo==1,"Commissioning ammunition must be paid before assembly")
	station.interact(p1,2.6)
	var gun=station.turret
	gun.set_physics_process(false)
	check(station.built and station.tier==1 and gun.ammo==20 and gun.reserve==0,"Paid initial construction creates exactly twenty rounds")
	check(world.floor_levels[0]==35.0 and world.floor_levels[-1]==800.0 and world.ladders.has(FlakStation.ACCESS),"Paid tower adds its climbable platform and preserves sorted floor bounds")
	check(gun.hull.is_in_group("anti_air") and gun.hull.can_be_targeted() and not gun.hull.is_in_group("walls"),"Air defense hull is targetable without trapping ground navigation")
	var hostile=preload("res://scripts/hostile_air_projectile.gd").new()
	hostile.game=world
	hostile.position=Vector2(1000,85)
	hostile.velocity=(gun.hull.global_position-hostile.position).normalized()*1000
	hostile.damage=17
	world.add_child(hostile)
	await frames()
	hostile._physics_process(0.6)
	check(gun.hp==183,"A real hostile aircraft round reaches and damages the exposed gun hull above its platform")
	p2.inventory={"steel":1}
	p2.selected_kind="steel"
	deposit(station,p2,1)
	check(gun.hp==200 and p2.inventory.steel==0,"Physical AA damage can be repaired at the safe bunker console")
	p2.inventory={"ammo":2}
	p2.selected_kind="ammo"
	deposit(station,p2,2)
	check(gun.reserve==40 and p2.inventory.ammo==0,"Console stores exactly twenty reserve rounds per real ammunition box")
	world.rounds.wave=10
	p1.inventory={"steel":4,"glass":2}
	deposit(station,p1,6)
	check(p1.inventory.steel==4 and station.tier==1,"Second tier cannot accept payment before wave eleven")
	world.rounds.wave=11
	deposit(station,p1,6)
	station.interact(p1,3.1)
	check(station.tier==2 and gun.tier==2 and gun.ammo_capacity()==60,"Paid second tier increases the real magazine capacity")
	check(gun.ammo==20 and gun.reserve==40 and p1.inventory.steel==0 and p1.inventory.glass==0,"Upgrade conserves ammunition and consumes its exact steel/glass costs")
	world.rounds.wave=15
	p2.selected_kind=""
	p2.inventory={"alloy":3,"glass":3}
	deposit(station,p2,6)
	check(p2.inventory.alloy==3 and station.tier==2,"Third tier is gated before wave sixteen")
	world.rounds.wave=16
	gun.hull.take_damage(1000)
	var blocked_cargo: Dictionary=p2.inventory.duplicate()
	deposit(station,p2,6)
	station.interact(p2,9.0)
	check(p2.inventory==blocked_cargo and station.materials.is_empty() and station.construction==0.0 and station.tier==2 and gun.hp==0,"A disabled gun accepts no alloy/glass upgrade payment or construction until explicitly repaired")
	p1.inventory={"steel":1}
	p1.selected_kind="steel"
	deposit(station,p1,1)
	check(gun.hp==80 and p1.inventory.steel==0,"One deliberate paid steel repair re-enables upgrading")
	p1.selected_kind=""
	deposit(station,p2,6)
	gun.hull.take_damage(1000)
	station.interact(p2,3.6)
	check(station.tier==2 and gun.hp==0 and station.construction==0.0 and station.materials.alloy==3 and station.materials.glass==3,"A fully paid upgrade also remains buffered while its gun is disabled")
	p1.inventory={"steel":1}
	p1.selected_kind="steel"
	deposit(station,p1,1)
	p1.selected_kind=""
	station.interact(p2,3.6)
	check(station.tier==3 and gun.ammo_capacity()==80 and gun.max_hp==440,"Shared paid final tier improves weapon and chassis")
	check(gun.ammo==20 and gun.reserve==40 and world.ladders.size()==1,"Final upgrade never adds free ammunition or duplicate access geometry")
	var ground=target(world,Vector2(900,50),false)
	await frames()
	gun._physics_process(1.0)
	check(gun.ammo==20 and gun.tracking_target==null,"Autonomous air watch never spends rounds on ground classes")
	var air=target(world,Vector2(960,60))
	await frames()
	gun._physics_process(1.0)
	check(gun.tracking_target==air and gun.ammo==19,"Automatic watch tracks a visible airborne machine and spends one round")
	advance_shells(world)
	check(air.hits==0 and ground.hits==1,"First-contact collision intercepts an AA shot before its intended aircraft")
	check(is_equal_approx(ground.hp,1000-86*0.45),"Ground interception receives reduced physical flak damage")
	ground.queue_free()
	await frames()
	gun.cooldown=0
	gun._physics_process(1.0)
	advance_shells(world)
	check(air.hits==1 and air.hp==914 and world.credits.back()[0]==p1,"Visible air contact takes full damage credited to the original tower builder")
	var wall=world.add_terrain(Rect2(770,-80,18,260))
	await frames()
	gun.cooldown=0
	var before: int=gun.ammo
	gun._physics_process(1.0)
	check(not gun.target_visible(air) and gun.ammo==before,"Auto watch will not fire through a closed physical obstruction")
	gun.aim_angle=(air.position-(gun.position+RoofTurret.PIVOT)).angle()
	gun.fire()
	advance_shells(world)
	check(air.hits==1 and gun.ammo==before-1,"Manual rounds also stop at the first terrain contact")
	wall.queue_free()
	await frames()
	p2.bonus=1.5
	gun.enter(p2)
	gun.cooldown=0
	gun.aim_angle=(air.position-(gun.position+RoofTurret.PIVOT)).angle()
	gun.fire()
	gun.exit()
	advance_shells(world)
	check(world.credits.back()[0]==p2 and is_equal_approx(world.credits.back()[1],129.0),"An in-flight manual shot retains its firing player and personal damage after exit")
	gun.ammo=0
	gun.reserve=20
	gun.reload_timer=0
	check(gun.start_reload(),"An unattended gun can reload from an existing paid reserve")
	gun._physics_process(1.4)
	check(gun.ammo+gun.reserve==20 or gun.ammo+gun.reserve==19,"Automatic reload moves finite rounds without refilling the larger magazine for free")
	for shell in shells(world): shell.queue_free()
	air.queue_free()
	await frames()
	gun._physics_process(0.2)
	check(gun.tracking_target==null,"A freed aircraft is safely discarded before autonomous retargeting")
	gun.ammo=0
	gun.reserve=0
	gun.cooldown=0
	gun.reload_timer=0
	check(not gun.start_reload() and not gun.fire() and gun.ammo==0,"Empty automatic defense cannot create rounds")
	p2.inventory={"ammo":1}
	gun.enter(p2)
	check(gun.start_reload() and p2.inventory.ammo==0 and gun.reserve==20,"Manual reload consumes exactly one carried box")
	gun._physics_process(1.4)
	check(gun.ammo==20 and gun.reserve==0,"Manual reload respects crate yield at maximum weapon tier")
	gun.hull.take_damage(500)
	check(gun.hp==0 and p2.mounted_turret==null and not gun.hull.can_be_targeted(),"Actual hull damage disables the gun and releases its operator")
	check(not gun.fire() and not gun.start_reload(),"A disabled AA gun cannot shoot or reload")
	p1.inventory={"steel":1}
	p1.selected_kind="steel"
	deposit(station,p1,1)
	check(gun.hp==80 and p1.inventory.steel==0 and gun.ammo==20,"A real steel repair restores only eighty HP and preserves ammunition")
	p2.inventory={"ammo":1}
	p2.selected_kind="ammo"
	gun.reserve=gun.reserve_capacity()
	deposit(station,p2,2)
	check(p2.inventory.ammo==1,"A full reserve never consumes another ammunition box")
	var close_air=target(world,gun.position+RoofTurret.PIVOT+Vector2(35,0))
	await frames()
	gun.exit()
	gun.cooldown=0
	gun.reload_timer=0
	gun.aim_angle=0
	gun.fire()
	check(close_air.hp<1000,"A machine inside the visible barrel is hit instead of bypassed")
	var before_hits: int=close_air.hits
	for shell in world.get_children():
		if shell is FlakProjectile and shell.retired: shell.impact(close_air,close_air.position,Vector2.LEFT)
	check(close_air.hits==before_hits,"A retired shell cannot apply damage or XP twice")
	world.queue_free()
	await process_frame
	print("FLAK TEST: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
