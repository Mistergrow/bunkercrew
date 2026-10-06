extends SceneTree
## Actual field-gun barrel ray, nearby enemy hitboxes and attributed health loss.
var checks := 0
var failures := 0
var game
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int):
	for i in count: await physics_frame
func machine(x: float,hp: float=100.0):
	var enemy = game.ENEMY.instantiate()
	enemy.kind = "runner"
	enemy.game = game
	# Keep the current physical runner hull centered on the horizontal barrel.
	# Its art/hitbox shrink changed this height since the fixture was authored.
	enemy.position = Vector2(x,430+RoofTurret.PIVOT.y+float(EnemyCatalog.profile("runner").center_y))
	game.add_child(enemy)
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.set_physics_process(false)
	return enemy
func bullets(parent: Node) -> int:
	var amount := 0
	for child in parent.get_children():
		if child is BunkerProjectile: amount += 1
		amount += bullets(child)
	return amount
func run():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.selected_characters.assign(["mara","ivo"])
	game.start(2)
	game.combat_events.persistence_enabled = false
	game.rounds.set_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
		worker.get_node("WorkerWeapon").set_physics_process(false)
	var p1 = game.players[0]
	var p2 = game.players[1]
	p1.progression.skill_points = 1
	p1.progression.purchase_skill("combat")
	var mount := FieldDefense.new()
	mount.game = game
	mount.kind = "sentry_kit"
	mount.position = Vector2(950,430)
	game.add_child(mount)
	var turret: RoofTurret = mount.turret
	turret.set_physics_process(false)
	turret.ammo = 10
	turret.aim_angle = 0
	turret.enter(p1)
	var target = machine(990)
	await frames(3)
	var expected: float = Balance.SHOT_DAMAGE*p1.damage_multiplier()
	var xp_before: float = p1.progression.xp
	var p2_xp_before: float = p2.progression.xp
	check(turret.fire() and is_equal_approx(target.hp,100-expected),"Enemy entirely inside the visible seventy-pixel barrel receives real upgraded damage")
	var expected_share := expected*PlayerProgression.XP_PER_DAMAGE*0.675
	check(is_equal_approx(p1.progression.xp-xp_before,expected_share) and is_equal_approx(p2.progression.xp-p2_xp_before,expected_share),"Close barrel contact shares only actual HP damage with the two participating workers")
	check(turret.ammo==9 and mount.hp==180 and bullets(game)==0,"Close shot consumes exactly one round, leaves its own base intact and spawns no duplicate projectile")
	var hp_after: float = target.hp
	await frames(8)
	check(target.hp==hp_after,"The contact hit cannot strike again on a later projectile tick")
	target.hp = 4
	turret.cooldown = 0
	turret.fire()
	check(p1.progression.kills==1 and p2.progression.kills==0,"A lethal close-range shot supplies exactly one personally credited kill")
	await frames(2)
	target = machine(1000)
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.initial_state = 4
	wall.position = Vector2(973,430)
	game.add_child(wall)
	await frames(3)
	xp_before = p1.progression.xp
	var wall_hp: float = wall.hp
	turret.cooldown = 0
	turret.fire()
	check(target.hp==100 and p1.progression.xp==xp_before and wall.hp==wall_hp and bullets(game)==0,"Intact concrete before the close enemy blocks the barrel without XP or friendly wall damage")
	wall.free()
	var terrain = game.add_terrain(Rect2(963,370,9,55))
	await frames(2)
	turret.cooldown = 0
	turret.fire()
	check(target.hp==100 and p1.progression.xp==xp_before and bullets(game)==0,"Solid terrain inside the barrel also stops the round before the enemy")
	terrain.free()
	target.position.x = 1100
	await frames(2)
	turret.cooldown = 0
	turret.fire()
	check(bullets(game)==1 and target.hp==100,"A clear barrel keeps the existing visible projectile for targets beyond the muzzle")
	await frames(14)
	check(is_equal_approx(target.hp,100-expected) and bullets(game)==0,"The normal outgoing projectile still deals the same personal damage exactly once")
	turret.exit()
	turret.enter(p2)
	target.position.x = 990
	target.hp = 100
	await frames(2)
	turret.cooldown = 0
	xp_before = p1.progression.xp
	p2_xp_before = p2.progression.xp
	var p2_expected: float = Balance.SHOT_DAMAGE*p2.damage_multiplier()
	turret.fire()
	expected_share = p2_expected*PlayerProgression.XP_PER_DAMAGE*0.675
	check(not is_equal_approx(expected,p2_expected) and is_equal_approx(target.hp,100-p2_expected) and is_equal_approx(p1.progression.xp-xp_before,expected_share) and is_equal_approx(p2.progression.xp-p2_xp_before,expected_share),"After a gunner swap the next close hit uses distinct new owner stats and the bounded crew XP share")
	target.hp = 4
	turret.cooldown = 0
	turret.fire()
	check(p1.progression.kills==1 and p2.progression.kills==1,"The second gunner owns the next lethal close hit despite shared crew XP")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Field-gun test scene and playback resources release cleanly")
	print("TURRET CLOSE RANGE: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
