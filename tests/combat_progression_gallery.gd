extends SceneTree
## Prepared positions/wave, normal worker rifle ammo and actual projectile kills.
## No XP, kill events, skill points or enemy HP are injected for the showcase.
var game
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/combat-progression-%s.png" % label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	game.rounds.running = false
	game.rounds.phase = "attack"
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	var worker = game.players[0]
	worker.position = Vector2(925,430)
	worker.set_physics_process(false)
	worker.focus = null
	game.players[1].position = Vector2(420,430)
	game.players[1].set_physics_process(false)
	game.players[1].focus = null
	var weapon = worker.get_node("WorkerWeapon")
	game.notify("PRÜFAUFBAU · vorbereitete Positionen · echte Gewehrtreffer / normale Munition")
	game.notice_time = 30
	await create_timer(1.5).timeout
	for index in 5:
		var enemy = game.ENEMY.instantiate()
		enemy.game = game
		enemy.kind = "runner"
		enemy.position = Vector2(1140,430)
		game.add_child(enemy)
		var deadline := Time.get_ticks_msec()+8000
		while is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and Time.get_ticks_msec()<deadline:
			weapon.aim_direction = (enemy.global_position-Vector2(0,enemy.body_height)-weapon.global_position).normalized()
			weapon.fire()
			await create_timer(0.22).timeout
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			push_error("Showcase rifle failed to defeat a normal runner within its ammo/time budget")
			failures += 1
			break
		if index==1:
			await capture("hits")
	await capture("combo")
	if worker.progression.kills!=5 or worker.progression.level<2:
		push_error("Showcase expected five real projectile kills and an earned level")
		failures += 1
	print("SHOWCASE actual_kills=%d level=%d hp=%.0f ammo_remaining=%d combo=%d" % [worker.progression.kills,worker.progression.level,worker.max_hp,weapon.total_ammunition(),worker.progression.combo])
	await create_timer(1.5).timeout
	game.rounds.wave = 20
	game.spawn_enemy(20,11,12)
	for enemy in get_nodes_in_group("enemies"):
		if enemy is BossMachine:
			enemy.position.x = 1300
	await create_timer(0.6).timeout
	await capture("boss")
	await create_timer(5.2).timeout
	if not await preload("res://tests/scene_cleanup.gd").free_scene(game,self):
		failures += 1
	print("SHOWCASE finished; failures=%d; automated aim, arranged positions/wave, actual projectile health and finite ammunition" % failures)
	quit(1 if failures else 0)
