extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
class CoreStub extends Node2D:
	var hp = 450.0
	func take_damage(damage): hp -= damage
class GameStub extends Node2D:
	var core
	var drops: Dictionary = {}
	func fx(_p,_c,_n): pass
	func sound(_s): pass
	func notify(_s): pass
	func spawn_pickup(kind,n,_p): drops[kind] = int(drops.get(kind, 0)) + n
class PlayerStub extends Node2D:
	var inventory = {"ammo":1}
	var mounted_turret
	var player_id = 1
	func take_item(kind,n):
		if inventory.get(kind,0) < n: return false
		inventory[kind] -= n
		return true
	func action(s): return "p1_"+s
var checks = 0
func check(value,message):
	if not value:
		push_error("FAILED: "+message)
		quit(1)
		return false
	checks += 1
	print("PASS ",message)
	return true
func _initialize():
	call_deferred("run")
func run():
	InputSetup.install()
	var game = GameStub.new()
	root.add_child(game)
	var core = CoreStub.new()
	core.position = Vector2(-100,200)
	game.core = core
	game.add_child(core)
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.initial_state = 4
	wall.game = game
	wall.position = Vector2(100,200)
	game.add_child(wall)
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.position = Vector2(200,200)
	enemy.game = game
	game.add_child(enemy)
	enemy.set_physics_process(false)
	await physics_frame
	var initial_wall_hp: float = wall.hp
	var initial_enemy_hp: float = enemy.hp
	var bullet = load("res://scenes/projectile.tscn").instantiate()
	bullet.position = Vector2(0,160)
	bullet.game = game
	game.add_child(bullet)
	for i in range(12): await physics_frame
	if not check(wall.hp == initial_wall_hp and enemy.hp == initial_enemy_hp and not is_instance_valid(bullet),"Projectile stops on intact own concrete without friendly damage or damage to the enemy behind"): return
	var bullet2 = load("res://scenes/projectile.tscn").instantiate()
	var projectile_damage: float = bullet2.damage
	bullet2.position = Vector2(140,170)
	bullet2.game = game
	game.add_child(bullet2)
	for i in range(8): await physics_frame
	if not check(is_equal_approx(enemy.hp,initial_enemy_hp-projectile_damage) and not is_instance_valid(bullet2),"Exposed machine takes actual projectile damage once"): return
	enemy.position.x = 163
	enemy.target = enemy.nearest_obstacle()
	if not check(enemy.target == wall and enemy.attack_obstacle(),"Machine targets and damages first intact obstacle"): return
	if not check(core.hp == 450.0,"Core protected by intact wall"): return
	wall.take_damage(999)
	await physics_frame
	enemy.target = enemy.nearest_obstacle()
	if not check(enemy.target == core,"Machine advances toward core after breached wall"): return
	enemy.position.x = -37
	if not check(enemy.attack_obstacle() and is_equal_approx(core.hp,450.0-enemy.attack_damage),"Machine damages exposed core at contact"): return
	var turret = load("res://scenes/turret.tscn").instantiate()
	turret.game = game
	turret.position = Vector2(400,200)
	game.add_child(turret)
	var player = PlayerStub.new()
	game.add_child(player)
	turret.enter(player)
	turret.ammo = 50
	if not check(turret.start_reload(),"Reload accepts carried ammo pack"): return
	turret._physics_process(1.1)
	if not check(turret.ammo == int(Balance.MAGAZINE) and turret.reserve == 0 and AmmoTransfer.remainder(player) == AmmoTransfer.PACK_SIZE-10 and player.inventory.ammo == 0,"Partial reload fills the magazine and preserves unused package rounds with the worker"): return
	turret.ammo = 45
	turret.start_reload()
	turret._physics_process(1.1)
	if not check(turret.ammo == 55 and turret.reserve == 0 and AmmoTransfer.remainder(player) == 0,"Next reload consumes the preserved open package without a new crate"): return
	turret.exit()
	var barrel_blocker = load("res://scenes/wall.tscn").instantiate()
	barrel_blocker.initial_state = 4
	barrel_blocker.game = game
	barrel_blocker.position = Vector2(445,200)
	game.add_child(barrel_blocker)
	await physics_frame
	turret.aim_angle = 0
	turret.cooldown = 0
	turret.fire()
	if not check(game.get_children().filter(func(n): return n is BunkerProjectile).is_empty(),"Obstructed barrel cannot spawn a projectile beyond wall"): return
	barrel_blocker.queue_free()
	await physics_frame
	var roof = StaticBody2D.new()
	roof.collision_layer = 1
	var roof_shape = CollisionShape2D.new()
	var roof_box = RectangleShape2D.new()
	roof_box.size = Vector2(340,18)
	roof_shape.shape = roof_box
	roof_shape.position = Vector2(245,209)
	roof.add_child(roof_shape)
	game.add_child(roof)
	await physics_frame
	turret.aim_angle = deg_to_rad(65)
	turret.cooldown = 0
	turret.fire()
	if not check(game.get_children().filter(func(n): return n is BunkerProjectile).size() == 1,"Roof platform edge leaves steepest legal gun angle unobstructed"): return
	enemy.take_damage(999)
	if not check(game.drops.get("scrap", 0) == int(enemy.profile.scrap) and game.drops.get("core", 0) == int(enemy.profile.cores) and get_nodes_in_group("enemies").is_empty(),"Destroyed machine yields its scrap and upgrade cores and leaves wave enemy group"): return
	if not check(await Cleanup.free_scene(game,self),"Combat fixture and its playback resources release cleanly"): return
	print("COMBAT CHECKS PASSED: ",checks)
	quit(0)
