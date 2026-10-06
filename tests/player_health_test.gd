extends SceneTree
## Real worker physics and enemy hit rays; explicit fixture positions isolate
## cover, interception, KO, recovery and finite cargo/ammunition accounting.

class CoreProbe extends StaticBody2D:
	var hp := 450.0
	func take_damage(amount: float): hp -= amount

class WorkProbe extends Node2D:
	var work := 0.0
	func interaction_point(): return global_position-Vector2(0,20)
	func interact(_worker,delta): work += delta

class HealthGame extends Node2D:
	var started := true
	var core
	var upgrades
	var ladders: Array[Rect2] = []
	var floor_levels: Array = [430.0]
	var world_right := 1900.0
	var chosen
	var impacts: Array = []
	var drops: Array = []
	var stats := {"kills":0}
	func get_focus(_worker): return chosen
	func focus_candidates(_worker) -> Array: return [chosen] if is_instance_valid(chosen) else []
	func valid_focus(worker,target) -> bool:
		return is_instance_valid(target) and worker.global_position.distance_to(target.global_position)<80
	func impact(pos,kind,direction=Vector2.LEFT,power=1.0): impacts.append([pos,kind,direction,power])
	func fx(_pos,_color,_count): pass
	func sound(_kind): pass
	func notify(_message): pass
	func spawn_pickup(kind,amount,pos): drops.append([kind,amount,pos])

var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int):
	for frame in count: await physics_frame
func seconds(duration: float):
	await frames(ceili(duration*Engine.physics_ticks_per_second/Engine.time_scale)+1)
func box(parent,point: Vector2,size: Vector2,layer: int=1):
	var body := StaticBody2D.new()
	body.position = point
	body.collision_layer = layer
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	parent.add_child(body)
	return body
func worker_at(game,point: Vector2,id: int):
	var worker = load("res://scenes/player.tscn").instantiate()
	worker.game = game
	worker.player_id = id
	worker.position = point
	game.add_child(worker)
	return worker
func machine_at(game,point: Vector2):
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.game = game
	enemy.position = point
	game.add_child(enemy)
	return enemy
func run():
	InputSetup.install()
	Engine.time_scale = 3.0
	var game := HealthGame.new()
	root.add_child(game)
	box(game,Vector2(950,440),Vector2(2000,20))
	game.core = CoreProbe.new()
	game.core.position = Vector2(150,430)
	game.core.collision_layer = 2
	var core_shape := CollisionShape2D.new()
	var core_rect := RectangleShape2D.new()
	core_rect.size = Vector2(38,78)
	core_shape.shape = core_rect
	core_shape.position.y = -39
	game.core.add_child(core_shape)
	game.add_child(game.core)
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.position = Vector2(600,430)
	wall.initial_state = 4
	game.add_child(wall)
	var p1 = worker_at(game,Vector2(634,430),1)
	var p2 = worker_at(game,Vector2(560,430),2)
	var enemy = machine_at(game,Vector2(674,430))
	enemy.set_physics_process(false)
	await frames(4)
	check(p1.hp==100 and p2.hp==100,"Both real workers start with 100 independent HP")
	enemy.target = wall
	var wall_hp: float = wall.hp
	check(enemy.attack_obstacle() and p1.hp==88 and wall.hp==wall_hp,"First worker on an actual enemy ray intercepts the shot before the wall")
	check(p2.hp==100 and game.impacts[-1][1]=="flesh","Only the struck worker is injured; real impact uses flesh preset")
	check(p1.hurt_stun>0 and p1.hurt_flash>0 and p1.knockback<0,"Damage produces brief stun, flash and directional knockback")
	check(enemy.attack_obstacle() and p1.hp==88,"Repeated hit during 0.65-second invulnerability cannot multiply damage")
	await seconds(0.72)
	p1.position = Vector2(634,430)
	p1.knockback = 0
	await frames(2)
	check(enemy.attack_obstacle() and p1.hp==76,"A new enemy hit damages the worker after invulnerability expires")
	p1.position = Vector2(560,430)
	p2.position = Vector2(490,430)
	await frames(3)
	var health_before: float = p1.hp
	wall_hp = wall.hp
	check(not enemy._visible_worker(p1) and enemy.attack_obstacle() and wall.hp<wall_hp and p1.hp==health_before,"Intact concrete cover protects the worker while the wall receives real damage")
	p1.position = Vector2(625,430)
	var rock = box(game,Vector2(642,385),Vector2(10,90))
	await frames(3)
	check(not enemy._visible_worker(p1) and not enemy.attack_obstacle() and p1.hp==health_before,"Solid terrain blocks both deliberate targeting and obstacle-ray interception")
	rock.free()
	var pane := DomeSegment.new()
	pane.configure(Vector2(648,350),Vector2(648,430),0)
	pane.game = game
	game.add_child(pane)
	pane.set_frame()
	pane.glaze()
	await frames(3)
	check(not enemy._visible_worker(p1) and not enemy.attack_obstacle(),"Real glazed dome geometry also blocks enemy shots toward workers")
	pane.free()
	# A worker away from the exact obstacle firing line still gets an explicit,
	# visible 0.48-second warning before a nearby machine can attack them.
	p1.position = Vector2(628,430)
	p1.invulnerability = 0
	p1.hp = 100
	enemy.attack_clock = 100
	enemy.worker_attack_clock = 0
	enemy.set_physics_process(true)
	await seconds(0.24)
	check(enemy.worker_windup>0 and p1.hp==100,"Deliberate attack visibly winds up before applying any worker damage")
	await seconds(0.40)
	check(p1.hp<100 and enemy.worker_attack_count==1,"Normal enemy physics completes a real, line-of-sight worker attack")
	enemy.set_physics_process(false)
	var health_after: float = p1.hp
	p1.invulnerability = 0
	p1.position = Vector2(560,430)
	enemy.worker_attack_clock = 0
	enemy.worker_windup = 0
	enemy.set_physics_process(true)
	await seconds(0.70)
	check(p1.hp==health_after and enemy.worker_attack_count==1,"The separate worker-attack cooldown never bypasses newly entered cover")
	enemy.set_physics_process(false)
	wall.free()
	enemy.free()
	# Both friendly projectile implementations physically cross worker hitboxes.
	p1.position = Vector2(520,430)
	p2.position = Vector2(550,430)
	p1.invulnerability = 0
	p2.invulnerability = 0
	var hp1: float = p1.hp
	var hp2: float = p2.hp
	var target = machine_at(game,Vector2(650,430))
	target.set_physics_process(false)
	await frames(3)
	var hand_round := WorkerShot.new()
	hand_round.game = game
	hand_round.position = Vector2(480,410)
	hand_round.direction = Vector2.RIGHT
	game.add_child(hand_round)
	await seconds(0.25)
	check(p1.hp==hp1 and p2.hp==hp2 and target.hp<target.max_hp,"Handheld projectiles ignore both workers and damage the actual enemy beyond")
	var gun_round = load("res://scenes/projectile.tscn").instantiate()
	gun_round.game = game
	gun_round.position = Vector2(480,410)
	gun_round.direction = Vector2.RIGHT
	game.add_child(gun_round)
	var target_before: float = target.hp
	await seconds(0.25)
	check(p1.hp==hp1 and p2.hp==hp2 and target.hp<target_before,"Roof-gun projectiles also pass teammates without friendly fire")
	target.free()
	# KO halfway through an ammunition transfer keeps every physical round.
	p1.position = Vector2(750,430)
	p2.position = Vector2(450,430)
	p1.hp = 100
	p1.invulnerability = 0
	p1.inventory = {"ore":2,"ammo":2}
	var weapon = p1.get_node("WorkerWeapon")
	weapon.loaded = {"rifle":5,"shotgun":0,"arcgun":0}
	weapon.reserve = 0
	weapon.open_pack = 0
	weapon.weapon_kind = "rifle"
	var rounds_before_reload: int = weapon.total_ammunition()+int(p1.inventory.ammo)*AmmoTransfer.PACK_SIZE
	# Filling the remaining 25 rifle slots opens two twenty-round packs. The
	# unused fifteen rounds remain in the carried open pack through KO/revival.
	check(weapon.start_reload() and weapon.reserve==25 and weapon.open_pack==15 and int(p1.inventory.get("ammo",0))==0 and weapon.total_ammunition()==rounds_before_reload and rounds_before_reload==45,"Reload transfers exactly 25 rounds and preserves the remaining 15 before KO")
	var inventory_before: Dictionary = p1.inventory.duplicate(true)
	var loaded_before: Dictionary = weapon.loaded.duplicate(true)
	var reserve_before: int = weapon.reserve
	var open_pack_before: int = weapon.open_pack
	var turret = load("res://scenes/turret.tscn").instantiate()
	turret.game = game
	turret.position = Vector2(779,430)
	game.add_child(turret)
	turret.enter(p1)
	var turret_total: int = turret.ammo+turret.reserve
	p1.take_damage(200,Vector2.LEFT)
	check(p1.is_downed() and p1.hp==0 and is_equal_approx(p1.down_time,MedicalCatalog.CRITICAL_DELAY),"Lethal injury starts a recoverable 45-second incapacitation")
	check(p1.mounted_turret==null and turret.occupant==null and p1.collision_layer==0,"KO leaves the turret and removes the corpse from projectile blocking")
	check(p1.inventory==inventory_before and weapon.loaded==loaded_before and weapon.reserve==reserve_before and weapon.open_pack==open_pack_before and weapon.total_ammunition()==rounds_before_reload,"KO preserves cargo and all loaded/reserve/open-pack ammunition even during reload")
	check(weapon.reload_timer==0 and not weapon.fire() and not weapon.start_reload(),"Incapacitated worker cannot fire or restart a cancelled reload")
	turret.enter(p1)
	check(turret.occupant==null and turret.ammo+turret.reserve==turret_total,"A downed worker cannot re-enter or duplicate the turret's finite rounds")
	var station := WorkProbe.new()
	station.position = p1.position
	game.add_child(station)
	game.chosen = station
	Input.action_press("p1_interact")
	Input.action_press("p1_fire")
	Input.action_press("p1_drop")
	Input.action_press("p1_right")
	Input.action_press("p2_right")
	var p1_x: float = p1.position.x
	var p2_x: float = p2.position.x
	await seconds(0.65)
	check(absf(p1.position.x-p1_x)<17 and station.work==0 and game.drops.is_empty(),"Held move/interact/fire/drop inputs cannot act during KO")
	check(p2.position.x>p2_x+70 and p2.hp==100,"The healthy local-coop worker keeps moving independently")
	for action_name in ["p1_interact","p1_fire","p1_drop","p1_right","p2_right"]: Input.action_release(action_name)
	await seconds(5.50)
	check(p1.is_downed() and p1.hp==0,"An untreated worker remains down instead of automatically returning after six seconds")
	p2.position = p1.position+Vector2(-36,0)
	p2.velocity = Vector2.ZERO
	game.chosen = p1.get_node("MedicalAidTarget")
	await frames(3)
	Input.action_press("p2_interact")
	await seconds(5.15)
	Input.action_release("p2_interact")
	check(not p1.is_downed() and p1.hp==35 and p1.position.distance_to(game.core.position)>100 and p2.medical.charges==1,"A real held coop interaction revives in place using exactly one helper charge")
	check(p1.invulnerability>1.5 and p1.take_damage(50)==0 and p1.hp==35,"Successful aid grants two seconds of real damage protection")
	check(p1.inventory==inventory_before and weapon.loaded==loaded_before and weapon.reserve==reserve_before and weapon.open_pack==open_pack_before and weapon.total_ammunition()==rounds_before_reload and turret.ammo+turret.reserve==turret_total,"Recovery never duplicates or loses carried materials, opened packs or either weapon's ammunition")
	# Regeneration is local to the core and obeys the hit-free delay.
	p1.invulnerability = 0
	p1.hp = 100
	p1.take_damage(12)
	p1.position = Vector2(205,430)
	p1.knockback = 0
	await seconds(3.7)
	check(p1.hp==88,"Core proximity does not heal before four seconds without injury")
	await seconds(1.3)
	check(p1.hp>94 and p1.hp<98.5,"After the delay, the core regenerates approximately eight HP per second")
	p1.position = Vector2(500,430)
	var away_hp: float = p1.hp
	await seconds(1.0)
	check(p1.hp==away_hp,"Regeneration stops outside the core's small safe area")
	game.free()
	Engine.time_scale = 1.0
	print("PLAYER HEALTH: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
