extends SceneTree
## Actual enemy health, attributed projectiles, boss phase and isolated persistence.
var checks := 0
var failures := 0
var game
var seen: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("REWARDS %s: %s" % ["PASS" if value else "FAIL",message])
	if not value:
		failures += 1
		push_error(message)

func machine(at: Vector2, hp: float = 90.0):
	var enemy = game.ENEMY.instantiate()
	enemy.game = game
	enemy.position = at
	game.add_child(enemy)
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	game.combat_events.event.connect(func(kind,data): seen.append([kind,data.duplicate()]))
	game.rounds.set_process(false)
	for p in game.players:
		p.set_physics_process(false)
	var p1 = game.players[0]
	var p2 = game.players[1]
	var target = machine(Vector2(1070,430),40)
	var expected_impact: Vector2 = target.global_position-Vector2(0,target.body_height)
	check(is_equal_approx(game.combat_hit(target,10,p1),10),"Damage dispatcher returns actual enemy health removed")
	check(is_equal_approx(p1.progression.xp,.675) and is_equal_approx(p2.progression.xp,.675),"Actual damage creates one bounded pool shared equally with the active partner")
	check(game.combat_hit(target,-10,p1)==0 and game.combat_hit(target,NAN,p1)==0,"Invalid damage cannot award XP or heal an enemy")
	check(is_equal_approx(game.combat_hit(target,999,p2),30),"Overkill is capped to the thirty remaining HP")
	check(p2.progression.kills==1 and p1.progression.kills==0,"Kill belongs to the finishing shot, both helpers retain hit XP")
	var earned: float = p2.progression.xp
	check(game.combat_hit(target,100,p2)==0 and p2.progression.xp==earned,"Queued dead enemy cannot give a second kill or repeat XP")
	check(game.combat_events.unlocked.has("first_kill"),"A real credited kill unlocks the first achievement")
	check(not game.combat_events.unlock("first_kill"),"Repeated achievements do not replay or grant extra rewards")
	var hit = seen.filter(func(item): return item[0]=="hit")
	check(hit.size()==2 and Vector2(hit[0][1].position).is_equal_approx(expected_impact),"Actual impacts carry their world position from the current sized enemy into visual feedback")
	await physics_frame
	# These are real projectile sweeps through the unchanged arena physics.
	var shot_target = machine(Vector2(1110,430),20)
	await physics_frame
	var shot = load("res://scripts/worker_projectile.gd").new()
	shot.game = game
	shot.credit_worker = p1
	shot.damage = 25
	shot.position = Vector2(1010,400)
	game.add_child(shot)
	for frame in 12:
		await physics_frame
	check(not is_instance_valid(shot_target) and p1.progression.kills==1,"A real handheld projectile supplies the owner and awards one kill")
	var blocked_target = machine(Vector2(1210,430),90)
	var cover = game.add_terrain(Rect2(1160,355,12,74))
	await physics_frame
	var before_xp: float = p1.progression.xp
	var blocked_shot = load("res://scripts/projectile.gd").new()
	blocked_shot.game = game
	blocked_shot.credit_worker = p1
	blocked_shot.position = Vector2(1120,400)
	game.add_child(blocked_shot)
	for frame in 10:
		await physics_frame
	check(blocked_target.hp==90 and p1.progression.xp==before_xp,"Terrain-blocked turret rounds cannot deal damage or create XP")
	cover.queue_free()
	blocked_target.queue_free()
	# Four more genuine kills continue player one's sequence and unlock combo 5.
	for i in 4:
		var combo_target = machine(Vector2(1100+i*2,430),1)
		game.combat_hit(combo_target,1,p1)
	check(p1.progression.combo==5 and game.combat_events.unlocked.has("combo_five"),"Five credited kills inside the window unlock the combo achievement")
	p1.progression._physics_process(5.1)
	check(p1.progression.combo==0,"Combo expires without a new kill")
	var p2_before: float = p2.progression.xp
	var anonymous = machine(Vector2(1130,430),5)
	game.combat_hit(anonymous,5)
	check(p2.progression.xp==p2_before,"Unowned damage is not assigned to the other local player")
	game.spawn_enemy(20,11,12)
	var boss
	for enemy in get_nodes_in_group("enemies"):
		if enemy is BossMachine:
			boss = enemy
	check(is_instance_valid(boss) and boss.get_meta("final_boss",false),"Final wave creates the actual articulated Mother Machine")
	boss.set_physics_process(false)
	check(boss.max_hp>800 and game.combat_events.boss_status().title=="MUTTERMASCHINE","Boss health and identity are available to the persistent status bar")
	check(seen.any(func(item): return item[0]=="boss" and item[1].portrait=="siege"),"Spawn emits a character portrait announcement exactly through the real spawn route")
	game.combat_hit(boss,boss.hp*0.51,p1)
	boss._physics_process(0.01)
	check(boss.overdrive and boss.profile.burst==2 and boss.profile.windup>=1.5,"Damaged boss visibly charges its second-phase double salvo")
	check(int(game.combat_events.boss_status().phase)==2,"Boss status reports phase two")
	var phase_count := seen.filter(func(item): return item[0]=="boss_phase").size()
	boss._physics_process(0.01)
	check(seen.filter(func(item): return item[0]=="boss_phase").size()==phase_count,"Threshold announcement cannot repeat each frame")
	game.combat_hit(boss,boss.hp,p2)
	check(game.combat_events.unlocked.has("boss") and game.combat_events.boss_status().is_empty(),"Actual boss death unlocks its achievement and removes the health bar")
	var temp_path := "user://achievement-test-%d.cfg" % OS.get_process_id()
	var service := CombatEvents.new()
	service.save_path = temp_path
	root.add_child(service)
	service.persistence_enabled = true
	service.unlock("armor")
	var reloaded := CombatEvents.new()
	reloaded.save_path = temp_path
	reloaded.load_records()
	check(reloaded.records().filter(func(row): return row.unlocked).size()==1,"Local achievements survive loading without inheriting XP or falsely unlocking other records")
	check(not reloaded.unlock("missing_id"),"Unknown records cannot enter the persistent profile")
	reloaded.free()
	service.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	game.return_to_menu()
	await process_frame
	await process_frame
	game = current_scene
	check(is_instance_valid(game) and not game.started and game.players.is_empty(),"Return to menu reaches pre-game selection without constructing unused players")
	check(get_nodes_in_group("pickups").is_empty(),"Return to menu in the same frame as a kill safely discards deferred drops from the old scene")
	game.selected_characters[1] = "ivo"
	game.start(1)
	check(game.players[0].progression.level==1 and game.players[0].progression.xp==0 and game.players[0].progression.armor_tier==0,"Fresh start clears personal run XP and equipment")
	game.join_coop()
	check(game.players.size()==2 and game.players[1].character_id=="ivo" and game.players[1].max_hp==90 and game.players[0].max_hp==100,"Drop-in worker receives the selected identity before ready, independently of P1")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Main scene and audio are cleanly released")
	print("REWARDS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
