extends SceneTree
## Real damage, paid repair, destruction and authoritative snapshots drive the
## same body condition. Cosmetic staging adds no resources or gameplay state.
const DamageArt := preload("res://scripts/structure_damage_art.gd")
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class GameStub extends Node2D:
	var sound_calls := 0
	var effect_calls := 0
	var destroyed := 0
	func sound(_kind: String) -> void: sound_calls += 1
	func fx(_point: Vector2, _color: Color, _count: int) -> void: effect_calls += 1
	func on_core_destroyed() -> void: destroyed += 1

class WorkerStub extends Node:
	var inventory: Dictionary = {}
	func take_item(kind: String, count: int = 1) -> bool:
		if int(inventory.get(kind, 0)) < count: return false
		inventory[kind] = int(inventory[kind]) - count
		return true

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var game := GameStub.new()
	root.add_child(game)
	var worker := WorkerStub.new()
	game.add_child(worker)
	for tier in range(1, 5):
		var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
		wall.game = game
		wall.initial_state = DefenseWall.State.HARD
		wall.initial_tier = tier
		game.add_child(wall)
		wall.set_process(false)
		var original_hp := wall.max_hp
		var children := wall.get_child_count()
		for ratio in [0.80, 0.49, 0.10]:
			wall.hp = wall.max_hp
			wall.take_damage(wall.max_hp * (1.0 - ratio))
			var expected := DamageArt.Stage.WORN if ratio == 0.80 else DamageArt.Stage.DAMAGED if ratio == 0.49 else DamageArt.Stage.CRITICAL
			check(DamageArt.stage(wall.hp, wall.max_hp) == expected, "Tier %d real damage exposes distinct %.0f%% body condition" % [tier, ratio * 100.0])
			check(wall.max_hp == original_hp and wall.tier == tier and wall.collider.shape.size == Vector2(30, 90) and wall.is_blocking(), "Damage presentation preserves tier, durability and physical blocking")
			worker.inventory = {"concrete": 64}
			var needed := ceili((wall.max_hp - wall.hp) / Balance.WALL_REPAIR)
			for _repair in needed:
				wall.interact(worker, Balance.WALL_WORK_TIME + 0.01)
			check(wall.hp == wall.max_hp and DamageArt.stage(wall.hp, wall.max_hp) == DamageArt.Stage.INTACT, "Paid repair removes cosmetic damage without leaving a stale damage stage")
			check(worker.inventory.concrete == 64 - needed and wall.get_child_count() == children, "Body damage adds no nodes and consumes only the existing repair recipe")
		wall.take_damage(wall.max_hp + 1.0)
		check(wall.state == DefenseWall.State.EMPTY and wall.hp == 0.0 and wall.max_hp == 0.0 and wall.tier == 1, "Destruction returns to the existing empty construction site")
		check(DamageArt.stage(wall.hp, wall.max_hp) == DamageArt.Stage.INTACT, "Empty zero-maximum site cannot retain armor damage")
	var core: BunkerCore = load("res://scenes/core.tscn").instantiate()
	core.game = game
	game.add_child(core)
	core.set_process(false)
	for maximum in [Balance.CORE_HP, Balance.CORE_HP + 180.0]:
		core.max_hp = maximum
		for ratio in [0.80, 0.49, 0.10]:
			core.hp = maximum
			core.take_damage(maximum * (1.0 - ratio))
			var expected := DamageArt.Stage.WORN if ratio == 0.80 else DamageArt.Stage.DAMAGED if ratio == 0.49 else DamageArt.Stage.CRITICAL
			check(DamageArt.stage(core.hp, core.max_hp) == expected, "Real core damage follows health fraction, including campaign durability bonus")
			worker.inventory = {"steel": 64, "scrap": 3}
			var needed := ceili((core.max_hp - core.hp) / core.repair_amount())
			for _repair in needed:
				core.interact(worker, Balance.CORE_REPAIR_TIME + 0.01)
			check(core.hp == core.max_hp and DamageArt.stage(core.hp, core.max_hp) == DamageArt.Stage.INTACT, "Actual core repair restores intact casing presentation")
			check(worker.inventory.steel == 64 - needed and worker.inventory.scrap == 3, "Core repair retains resource priority and exact established cost")
	var sound_count := game.sound_calls
	var effect_count := game.effect_calls
	for frame in 360:
		var scan_y := DamageArt.monitor_scan_y(frame / 120.0)
		check(scan_y == roundf(scan_y) and scan_y >= -59.0 and scan_y <= -49.0, "Core monitor scan remains on whole local pixels inside its original display")
	check(game.sound_calls == sound_count and game.effect_calls == effect_count, "Cosmetic pixel clock creates no additional audio or effect events")
	core.take_damage(core.max_hp + 1.0)
	check(core.hp == 0.0 and game.destroyed == 1, "Core destruction retains the existing one-shot loss callback")
	core.take_damage(1.0)
	check(game.destroyed == 1, "A destroyed core cannot replay the loss callback")
	check(DamageArt.stage(NAN, 100.0) == DamageArt.Stage.INTACT and DamageArt.stage(10.0, INF) == DamageArt.Stage.INTACT, "Invalid cosmetic inputs produce no invented damage state")
	check(await Cleanup.free_scene(game, self), "Real standalone structure fixtures release cleanly")
	await replicas()
	print("STRUCTURE DAMAGE PRESENTATION: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func replicas() -> void:
	var host = load("res://scenes/main.tscn").instantiate()
	root.add_child(host)
	current_scene = host
	host.combat_events.persistence_enabled = false
	host.start_scenario(2, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	host.set_process(false)
	var authoritative := World.new()
	authoritative.bind(host)
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	current_scene = guest
	guest.combat_events.persistence_enabled = false
	guest.start_scenario(2, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	var replica := World.new()
	replica.bind(guest)
	for ratio in [1.0, 0.80, 0.49, 0.10]:
		for node: Node in authoritative.entities.values():
			if node is DefenseWall:
				node.tier = 4
				node.max_hp = node.completed_max_hp()
				node.hp = node.max_hp * ratio
				node.hit_flash = 0.0
		host.core.hp = host.core.max_hp * ratio
		host.core.hit_flash = 0.0
		var packet := authoritative.capture()
		check(authoritative._validate(packet), "Original network schema accepts the prepared existing structure state")
		check(replica.apply(packet), "Unmodified snapshot application transfers current structure damage")
		check(DamageArt.stage(guest.core.hp, guest.core.max_hp) == DamageArt.stage(host.core.hp, host.core.max_hp), "Replica core derives exactly the host's body condition without a new visual field")
		for id in authoritative.entities:
			var source: Node = authoritative.entities[id]
			if not source is DefenseWall: continue
			var target: DefenseWall = replica.entities[id]
			check(target.tier == source.tier and target.hp == source.hp and target.max_hp == source.max_hp, "Armored wall replica preserves exact existing tier and durability")
			check(DamageArt.stage(target.hp, target.max_hp) == DamageArt.stage(source.hp, source.max_hp), "Replica wall derives the host's visible condition including critical state")
	check(await Cleanup.free_scene(guest, self), "Structure replica scene releases cleanly")
	check(await Cleanup.free_scene(host, self), "Authoritative structure scene releases cleanly")
