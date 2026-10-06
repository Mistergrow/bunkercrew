extends SceneTree
## Global groups must not cross game ownership, even across separate World2D instances.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class Arena extends Node2D:
	var started := false
	var core: Node
	var upgrades: Node
	var campaign: CampaignState
	var stats := {"kills":0}
	func sound(_kind: String) -> void: pass
	func notify(_message: String) -> void: pass
	func fx(_at: Vector2, _color: Color, _count: int) -> void: pass
	func impact(_at: Vector2, _kind: String, _normal: Vector2 = Vector2.LEFT, _power: float = 1.0) -> void: pass

class DamageWorkerProbe extends CharacterBody2D:
	var game: Node
	var hp := 100.0
	func can_be_targeted() -> bool: return hp > 0
	func take_damage(amount: float, _direction: Vector2 = Vector2.ZERO) -> void: hp -= amount

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func arena() -> Arena:
	var view := SubViewport.new()
	view.world_2d = World2D.new()
	root.add_child(view)
	var game := Arena.new()
	view.add_child(game)
	return game

func machine(game: Arena, kind: String, at: Vector2) -> SiegeMachine:
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.game = game
	enemy.kind = kind
	enemy.position = at
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func aircraft(game: Arena, at: Vector2) -> AirMachine:
	var enemy = load("res://scenes/air_enemy.tscn").instantiate()
	enemy.game = game
	game.add_child(enemy)
	enemy.position = at
	enemy.set_physics_process(false)
	return enemy

func worker(game: Arena, at: Vector2) -> Node2D:
	var result = load("res://scenes/player.tscn").instantiate()
	result.game = game
	result.position = at
	game.add_child(result)
	result.set_physics_process(false)
	result.get_node("WorkerWeapon").set_physics_process(false)
	return result

func damage_worker(parent: Arena, owner_game: Arena, at: Vector2) -> DamageWorkerProbe:
	var result := DamageWorkerProbe.new()
	result.game = owner_game
	result.position = at
	result.collision_layer = 8
	result.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 44)
	collision.shape = shape
	collision.position = Vector2(0, -23)
	result.add_child(collision)
	parent.add_child(result)
	result.add_to_group("players")
	return result

func frames() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	InputSetup.install()
	var own := arena()
	var other := arena()
	check(own.get_world_2d() != other.get_world_2d(), "Fixtures use two actual independent physics worlds")
	var crawler := machine(own, "repair_crawler", Vector2(200, 430))
	var foreign_patient := machine(other, "strider", Vector2(260, 430))
	foreign_patient.hp = 10
	await frames()
	check(crawler.abilities.try_repair() == 0 and foreign_patient.hp == 10 and crawler.abilities.repair_remaining == 64, "Repair cannot heal another game's machine or consume spare parts")
	var patient := machine(own, "strider", Vector2(240, 430))
	patient.hp = patient.max_hp - 3
	await frames()
	check(crawler.abilities.try_repair() == 3 and patient.hp == patient.max_hp and crawler.abilities.repair_remaining == 61, "A local repair still spends exactly the local patient's missing health")
	patient.hp = 10
	patient.queue_free()
	check(crawler.abilities.try_repair() == 0 and crawler.abilities.repair_remaining == 61, "A queued local machine cannot receive or waste a repair pulse")
	var gun := FlakTurret.new()
	gun.game = own
	gun.position = Vector2(500, 200)
	own.add_child(gun)
	gun.set_physics_process(false)
	var foreign_air := aircraft(other, Vector2(800, 0))
	await frames()
	check(not gun.target_visible(foreign_air), "Flak cannot track aircraft in another actual World2D")
	gun.ammo = 8
	gun.cooldown = 100
	gun._watch_sky(0.01)
	check(not is_instance_valid(gun.tracking_target) and gun.ammo == 8, "Foreign aircraft cannot steer automatic flak or consume ammunition")
	var local_air := aircraft(own, Vector2(800, 0))
	await frames()
	check(gun.target_visible(local_air), "Local visible aircraft remain valid targets")
	gun.scan_clock = 0
	gun._watch_sky(0.01)
	check(gun.tracking_target == local_air, "Automatic tracking selects a local aircraft despite foreign group entries")
	local_air.queue_free()
	check(not gun.target_visible(local_air), "Queued aircraft cannot retain targeting permission")
	foreign_air.free()
	check(not gun.target_visible(foreign_air), "A freed aircraft is rejected safely")
	own.campaign = CampaignState.new("user://unused-owner-test.json", false)
	check(own.campaign.begin_new({}, ["mara"], 1) and not own.campaign.mission_start().is_empty(), "A real temporary campaign enters its first mission")
	check(own.campaign.reserve_drop("wave_03", 1), "Campaign issues one genuine bounded salvage envelope")
	var salvage := CampaignSalvage.new()
	salvage.game = own
	salvage.claim_id = own.campaign.mission_id
	salvage.drop_id = "wave_03"
	salvage.position = Vector2(100, 100)
	own.add_child(salvage)
	salvage.set_physics_process(false)
	worker(other, Vector2(100, 100))
	salvage._physics_process(0.0)
	check(not salvage.collected and own.campaign.mission_salvage == 0, "A foreign actual worker at the same coordinates cannot claim salvage")
	var queued_worker := worker(own, Vector2(100, 100))
	queued_worker.queue_free()
	salvage._physics_process(0.0)
	check(not salvage.collected and own.campaign.mission_salvage == 0, "A queued own worker cannot claim salvage during teardown")
	worker(own, Vector2(100, 100))
	salvage._physics_process(0.0)
	check(salvage.collected and own.campaign.mission_salvage == 1, "A living own worker collects the genuine campaign drop exactly once")
	check(not salvage.collect(false) and own.campaign.mission_salvage == 1, "Ownership checks preserve one-time salvage credit")
	var demolition := machine(own, "demolisher", Vector2(900, 430))
	var foreign_shared := damage_worker(own, other, Vector2(840, 383))
	await frames()
	demolition.abilities.after_strike(null, Vector2(800, 360), Vector2.RIGHT)
	check(foreign_shared.hp == 100, "A demolition shockwave cannot damage a foreign-owned worker even in the shared physical world")
	foreign_shared.free()
	var local_worker := damage_worker(own, own, Vector2(840, 383))
	await frames()
	demolition.abilities.after_strike(null, Vector2(800, 360), Vector2.RIGHT)
	check(local_worker.hp == 86, "An exposed local worker still receives the real demolition shockwave")
	local_worker.hp = 100
	local_worker.queue_free()
	demolition.abilities.after_strike(null, Vector2(800, 360), Vector2.RIGHT)
	check(local_worker.hp == 100, "A queued local worker is ignored by the demolition shockwave")
	var shooter := machine(own, "strider", Vector2(1700,430))
	var aircraft_shooter := aircraft(own, Vector2(1800,150))
	var foreign_target := damage_worker(own,other,Vector2(1650,430))
	await frames()
	check(not shooter._visible_worker(foreign_target) and not aircraft_shooter.visible_worker(foreign_target), "Actual ground and air targeting reject a foreign worker in the shared physical world")
	check(aircraft_shooter.choose_target() != foreign_target, "Aircraft cannot select the visible foreign group entry")
	foreign_target.free()
	var own_target := damage_worker(own,own,Vector2(1650,430))
	await frames()
	check(shooter._visible_worker(own_target) and aircraft_shooter.visible_worker(own_target), "Ground and air targeting still recognize the actual local collision hull")
	check(aircraft_shooter.choose_target() == own_target, "Aircraft still prioritize the visible local worker")
	own_target.queue_free()
	check(not shooter._visible_worker(own_target) and not aircraft_shooter.visible_worker(own_target), "Queued own workers lose ground and air targeting permission")
	await frames()
	check(not shooter._visible_worker(own_target) and not aircraft_shooter.visible_worker(own_target), "Freed workers cannot cause either target selector to throw")
	for _index in HostileAirProjectile.MAX_ACTIVE:
		var foreign_shot := HostileAirProjectile.new()
		foreign_shot.game = other
		other.add_child(foreign_shot)
		foreign_shot.set_physics_process(false)
	check(aircraft_shooter._fire_at(Vector2(1500,407)), "The full foreign projectile pool cannot silence an own aircraft")
	var own_shots: Array[HostileAirProjectile] = []
	for candidate in own.get_children():
		if candidate is HostileAirProjectile:
			candidate.set_physics_process(false)
			own_shots.append(candidate)
	while own_shots.size() < HostileAirProjectile.MAX_ACTIVE:
		var shot := HostileAirProjectile.new()
		shot.game = own
		own.add_child(shot)
		shot.set_physics_process(false)
		own_shots.append(shot)
	check(not aircraft_shooter._fire_at(Vector2(1500,407)), "The full live own projectile pool retains its original 42-round cap")
	own_shots[0].queue_free()
	check(aircraft_shooter._fire_at(Vector2(1500,407)), "A queued own projectile immediately releases exactly one firing slot")
	for candidate in own.get_children():
		if candidate is HostileAirProjectile: candidate.set_physics_process(false)
	check(not aircraft_shooter._fire_at(Vector2(1500,407)), "Filling the released slot restores the actual own pool cap")
	own_shots[1].spent = true
	check(aircraft_shooter._fire_at(Vector2(1500,407)), "A spent own projectile cannot waste a firing slot before its deferred deletion")
	await Cleanup.free_scene(own.get_parent(), self)
	await Cleanup.free_scene(other.get_parent(), self)
	print("GAMEPLAY OWNER BOUNDARIES: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
