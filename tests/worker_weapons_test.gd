extends SceneTree

class UpgradeStub extends Node:
	var unlocked: Dictionary = {}
	func has_upgrade(kind: String) -> bool: return unlocked.has(kind)
	func weapon_multiplier() -> float: return 1.2 if unlocked.has("weapon_handling") else 1.0

class GameStub extends Node2D:
	var started := true
	var upgrades
	var core
	func fx(_pos,_color,_count): pass
	func sound(_kind): pass
	func spawn_pickup(_kind,_amount,_pos): pass

class WorkerStub extends CharacterBody2D:
	var game
	var player_id := 1
	var facing := 1.0
	var climbing := false
	var mining := false
	# WorkerWeapon reads this production interface through the fixture dynamically.
	@warning_ignore("unused_private_class_variable")
	var _interacting := false
	var mounted_turret
	var inventory: Dictionary = {}
	func action(suffix: String) -> String: return "p%d_%s" % [player_id,suffix]
	func carried_count() -> int:
		var count := 0
		for amount in inventory.values(): count += int(amount)
		return count
	func take_item(kind: String, amount: int) -> bool:
		if int(inventory.get(kind,0)) < amount: return false
		inventory[kind] -= amount
		if inventory[kind] == 0: inventory.erase(kind)
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func clear_shots(game: Node) -> void:
	for child in game.get_children():
		if child is WorkerShot:
			child.queue_free()

func machine(game: Node, x: float) -> SiegeMachine:
	var enemy: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
	enemy.position = Vector2(x,200)
	enemy.game = game
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run_checks() -> void:
	InputSetup.install()
	var game := GameStub.new()
	root.add_child(game)
	game.upgrades = UpgradeStub.new()
	game.add_child(game.upgrades)
	var worker := WorkerStub.new()
	worker.game = game
	worker.position = Vector2(200,200)
	game.add_child(worker)
	var weapon := WorkerWeapon.new()
	worker.add_child(weapon)
	weapon.set_physics_process(false)
	var worker2 := WorkerStub.new()
	worker2.game = game
	worker2.player_id = 2
	worker2.position = Vector2(140,200)
	game.add_child(worker2)
	var weapon2 := WorkerWeapon.new()
	worker2.add_child(weapon2)
	weapon2.set_physics_process(false)
	check(weapon.current_ammo()==30 and weapon.reserve==90 and weapon.total_ammunition()==120, "Each worker starts with a finite thirty-round rifle and ninety reserve rounds")
	check(weapon.available_weapons()==["rifle"], "Advanced handheld weapons remain locked before the upgrade")
	weapon.cycle_weapon()
	check(weapon.weapon_kind=="rifle" and weapon.total_ammunition()==120, "Cycling a locked arsenal cannot create ammunition")
	Input.action_press("p1_fire")
	weapon._physics_process(0.02)
	weapon2._physics_process(0.02)
	Input.action_release("p1_fire")
	check(weapon.current_ammo()==29 and weapon2.current_ammo()==30, "Player one's fire action cannot fire player two's weapon")
	clear_shots(game)
	weapon.cooldown = 0
	worker.facing = 1
	weapon._update_origin()
	weapon.aim_direction = Vector2.RIGHT
	var enemy := machine(game,450)
	await physics_frame
	await physics_frame
	check(weapon.fire() and weapon.current_ammo()==28, "Firing a handheld round consumes exactly one loaded cartridge")
	for frame in 16: await physics_frame
	check(enemy.hp==74, "A real handheld projectile damages the exposed machine")
	var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
	wall.initial_state = 4
	wall.position = Vector2(330,200)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	weapon.cooldown = 0
	weapon.fire()
	for frame in 16: await physics_frame
	check(enemy.hp==74 and wall.hp==wall.max_hp, "Friendly bunker walls block handheld rounds without receiving friendly damage")
	wall.position.x = 220
	await physics_frame
	await physics_frame
	weapon.cooldown = 0
	weapon.fire()
	for frame in 16: await physics_frame
	check(enemy.hp==74 and wall.hp==wall.max_hp, "A barrel overlapping a wall cannot spawn shots on its far side")
	wall.queue_free()
	enemy.queue_free()
	await physics_frame
	var ammo_before := weapon.total_ammunition()
	check(weapon.start_reload(), "Rifle reload uses its finite reserve")
	weapon._physics_process(1.2)
	check(weapon.current_ammo()==30 and weapon.total_ammunition()==ammo_before, "Reload transfers ammunition without creating or discarding rounds")
	weapon.loaded={"rifle":0,"shotgun":0,"arcgun":0}
	weapon.reserve=0
	worker.inventory={"ammo":1}
	check(weapon.start_reload() and worker.inventory.is_empty(), "A carried ammunition crate is consumed only when reserve is needed")
	weapon._physics_process(1.2)
	check(weapon.current_ammo()==20 and weapon.reserve==0, "One crate supplies exactly twenty usable handheld rounds")
	game.upgrades.unlocked["shotgun"]=true
	game.upgrades.unlocked["arcgun"]=true
	check(weapon.available_weapons()==["rifle","shotgun","arcgun"], "Weapon upgrades unlock distinct shotgun and arcgun choices")
	weapon.reserve=20
	ammo_before=weapon.total_ammunition()
	weapon.cycle_weapon()
	check(weapon.weapon_kind=="shotgun" and weapon.reload_timer>0, "Switching to an unlocked empty shotgun starts a real reload")
	weapon._physics_process(1.4)
	check(weapon.current_ammo()==6 and weapon.total_ammunition()==ammo_before, "Switching weapons preserves shared ammunition while filling its own magazine")
	weapon.cooldown=0
	weapon.aim_direction=Vector2.RIGHT
	check(weapon.fire(), "Unlocked shotgun can fire")
	var pellets := game.get_children().filter(func(node): return node is WorkerShot)
	check(pellets.size()==8 and weapon.current_ammo()==5, "Shotgun emits eight distinct spread pellets for one cartridge")
	check(pellets[0].direction != pellets[-1].direction and pellets[0].life<=0.27, "Shotgun pellets have real spread and a short maximum range")
	clear_shots(game)
	await physics_frame
	weapon.cycle_weapon()
	weapon._physics_process(1.4)
	weapon.cooldown=0
	weapon.aim_direction=Vector2.RIGHT
	var first := machine(game,330)
	var second := machine(game,430)
	var third := machine(game,540)
	await physics_frame
	await physics_frame
	var arc_ammo := weapon.current_ammo()
	weapon.fire()
	for frame in 24: await physics_frame
	check(first.hp==56 and second.hp==56 and third.hp==90, "Arcgun pierces two actual machines and stops before a third")
	check(weapon.current_ammo()==arc_ammo-2 and first.stagger>=0.6, "Arc discharge uses two rounds and briefly staggers its target")
	first.hp=first.max_hp
	second.hp=second.max_hp
	wall=load("res://scenes/wall.tscn").instantiate()
	wall.initial_state=4
	wall.position=Vector2(375,200)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	weapon.cooldown=0
	weapon.fire()
	for frame in 24: await physics_frame
	check(first.hp==56 and second.hp==90 and wall.hp==wall.max_hp, "Arc piercing stops on an intervening wall without damaging friendly construction")
	wall.queue_free()
	first.hp=first.max_hp
	game.upgrades.unlocked["weapon_handling"]=true
	weapon.weapon_kind="rifle"
	weapon.loaded["rifle"]=30
	weapon.cooldown=0
	await physics_frame
	weapon.fire()
	for frame in 16: await physics_frame
	check(is_equal_approx(first.hp,70.8), "Weapon-handling upgrade increases actual projectile damage by twenty percent")
	worker.inventory={"sand":1}
	weapon.cooldown=0
	ammo_before=weapon.current_ammo()
	check(not weapon.fire() and weapon.current_ammo()==ammo_before, "Carrying material blocks firing without consuming ammunition")
	worker.inventory.clear()
	worker.climbing=true
	check(not weapon.fire(), "Workers cannot fire while using a ladder")
	worker.climbing=false
	worker.mounted_turret=Node2D.new()
	game.add_child(worker.mounted_turret)
	check(not weapon.fire() and not weapon.start_reload(), "Mounted turret controls cannot simultaneously fire or reload the handheld weapon")
	print("WORKER WEAPON CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
