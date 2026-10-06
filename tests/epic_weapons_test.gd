extends SceneTree
## Finite stop rewards drive the real handheld ammo and projectile implementations.
class WeaponLab extends Node2D:
	var started := true
	var campaign: CampaignState
	var upgrades: UpgradeSystem
	var requests: Array[String] = []
	func sound(kind): requests.append(str(kind))
	func notify(_message): pass
	func fx(_point, _color, _count): pass
class Fighter extends CharacterBody2D:
	var game
	var character_id := "mara"
	var player_id := 1
	var facing := 1.0
	var climbing := false
	var mining := false
	@warning_ignore("unused_private_class_variable")
	var _interacting := false
	var mounted_turret
	var inventory: Dictionary = {}
	var progression: PlayerProgression
	func action(suffix: String) -> String: return "p1_" + suffix
	func carried_count() -> int: return 0
	func take_item(kind: String, amount: int) -> bool:
		if int(inventory.get(kind, 0)) < amount: return false
		inventory[kind] -= amount
		return true
class Target extends StaticBody2D:
	var hp := 500.0
	var stagger := 0.0
	func take_damage(amount: float) -> void: hp -= amount
	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group("enemies")
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(12, 28)
		collider.shape = shape
		add_child(collider)
var checks := 0
var failures := 0
var game: WeaponLab
var worker: Fighter
var weapon: WorkerWeapon
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func shots() -> Array:
	return game.get_children().filter(func(node): return node is WorkerShot and not node.is_queued_for_deletion())
func clear_shots() -> void:
	for shot in shots(): shot.free()
func ready_weapon(kind: String, amount: int) -> void:
	weapon.cancel_actions()
	weapon.cooldown = 0.0
	weapon.weapon_kind = kind
	weapon.loaded[kind] = amount
	weapon.aim_direction = Vector2.RIGHT
func target_at(x: float) -> Target:
	var target := Target.new()
	target.position = weapon.global_position + Vector2(x, 0)
	game.add_child(target)
	return target
func run() -> void:
	InputSetup.install()
	game = WeaponLab.new()
	root.add_child(game)
	game.upgrades = UpgradeSystem.new()
	game.upgrades.game = game
	game.add_child(game.upgrades)
	game.campaign = CampaignState.new("user://epic-weapons-test.json", false)
	worker = Fighter.new()
	worker.game = game
	worker.position = Vector2(200, 200)
	game.add_child(worker)
	worker.progression = PlayerProgression.new()
	worker.add_child(worker.progression)
	weapon = WorkerWeapon.new()
	weapon.name = "WorkerWeapon"
	worker.add_child(weapon)
	weapon.set_physics_process(false)
	check(weapon.available_weapons() == ["rifle"] and weapon.total_ammunition() == 120, "Epic definitions create neither unlocks nor free ammunition")
	for id: String in WorkerWeapon.EPIC_WEAPONS:
		ready_weapon(id, 0)
		check(not weapon.start_reload() and not weapon.fire() and weapon.reserve == 90, "Locked epic cannot be reloaded or fired: " + id)
		weapon.cycle_weapon()
		check(weapon.weapon_kind == "rifle", "Cycling skips unearned epic weapons")
	check(game.campaign.begin_new({"environment":"ash_foundry", "position":"left", "build_type":"bastion"}, ["mara"], 1), "Start isolated campaign")
	var mission := game.campaign.mission_start()
	check(not game.campaign.complete_mission(mission.id, 20, [worker], game.upgrades).is_empty(), "Prepared first wave20 victory unlocks actual expedition state")
	for destination: String in ["harbor", "quarry", "steelworks"]:
		check(game.campaign.select_destination(destination) and game.campaign.select_stop(destination + ":weapon"), "Select real weapon depot route " + destination)
		check(not game.campaign.begin_journey(destination).is_empty() and game.campaign.reach_stop(), "Reach guarded stop through route transitions")
		var total_before := weapon.total_ammunition()
		var reward := game.campaign.secure_stop()
		var id: String = str(reward.get("weapon", ""))
		check(WorkerWeapon.EPIC_WEAPONS.has(id) and weapon.available_weapons().has(id), "Secured depot unlocks its actual usable weapon")
		check(weapon.total_ammunition() == total_before and weapon.loaded[id] == 0, "Depot unlock keeps new magazine empty and conserves ammunition")
		check(game.campaign.secure_stop().is_empty(), "Secured depot cannot be looted twice")
		check(game.campaign.arrive_at_destination() and game.campaign.secure_destination(), "Next bunker occupation returns to defense")
		mission = game.campaign.mission_start()
		check(not game.campaign.complete_mission(mission.id, 20, [worker], game.upgrades).is_empty(), "Prepared next bunker victory preserves earned weapons")
	check(weapon.available_weapons().size() == 4, "All three earned epics coexist without granting normal research weapons")
	for id: String in WorkerWeapon.EPIC_WEAPONS:
		ready_weapon(id, 0)
		var total_before := weapon.total_ammunition()
		game.requests.clear()
		check(weapon.start_reload(), "Earned empty epic reloads from finite reserve")
		weapon._physics_process(float(WorkerWeapon.WEAPONS[id].reload) + .01)
		check(weapon.current_ammo() == weapon.magazine_size() and weapon.total_ammunition() == total_before, "Epic reload conserves rounds: " + id)
		var sound_family := WorkerWeapon.family_for(id)
		if sound_family == "arcgun": sound_family = "arc"
		check(game.requests.has("reload_" + sound_family + "_open") and game.requests.has("reload_" + sound_family + "_close"), "Epic handling uses existing correct family sounds")
		weapon.cooldown = 0.0
		var rounds_before := weapon.current_ammo()
		check(weapon.fire() and weapon.current_ammo() == rounds_before - int(WorkerWeapon.WEAPONS[id].cost), "Actual epic shot consumes correct ammunition")
		check(shots().size() == int(WorkerWeapon.WEAPONS[id].pellets) and shots()[0].flavor == WorkerWeapon.family_for(id), "Finite pellet count and wire-compatible family flavor")
		clear_shots()
	ready_weapon("veteran_rifle", 20)
	var dummy := target_at(100)
	await physics_frame
	check(weapon.fire(), "Precision rifle fires")
	for shot in shots(): shot._physics_process(.10)
	check(is_equal_approx(dummy.hp, 476.0), "Precision projectile actually delivers24 damage")
	dummy.free()
	clear_shots()
	ready_weapon("breacher_shotgun", 4)
	dummy = target_at(80)
	await physics_frame
	weapon.fire()
	for shot in shots(): shot._physics_process(.10)
	check(is_equal_approx(dummy.hp, 416.0) and is_equal_approx(dummy.stagger, .40), "Six breacher pellets actually deliver84damage and0.4s suppression")
	dummy.free()
	clear_shots()
	ready_weapon("storm_arcgun", 9)
	var targets: Array[Target] = [target_at(55), target_at(90), target_at(125), target_at(165)]
	await physics_frame
	weapon.fire()
	for shot in shots(): shot._physics_process(.20)
	check(targets[0].hp == 455 and targets[1].hp == 455 and targets[2].hp == 455 and targets[3].hp == 500, "Storm arc penetrates exactly three actual targets")
	clear_shots()
	for target in targets: target.free()
	weapon.weapon_kind = "storm_arcgun"
	var snapshot := CampaignBonus.snapshot_player(worker)
	check(CampaignBonus.valid_snapshot(snapshot) and snapshot.weapon_kind == "storm_arcgun", "Earned epic survives player snapshot format")
	var checkpoint := game.campaign.checkpoint()
	checkpoint.snapshots["1"] = snapshot
	check(CampaignState.valid_checkpoint(checkpoint), "Checkpoint accepts equipped earned epic")
	checkpoint.expedition.epic_weapons.erase("storm_arcgun")
	check(not CampaignState.valid_checkpoint(checkpoint), "Checkpoint rejects equipped epic without its reward")
	for id in weapon.loaded: weapon.loaded[id] = 0
	weapon.reserve = 0
	worker.inventory.clear()
	weapon.cooldown = 0
	check(not weapon.start_reload() and not weapon.fire() and shots().is_empty(), "Empty reserve and cargo cannot create epic rounds")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "Epic fixture releases all nodes")
	print("EPIC WEAPONS: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
