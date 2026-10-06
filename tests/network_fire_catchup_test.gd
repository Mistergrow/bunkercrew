extends SceneTree
## A complete reliable trigger tap arriving in one poll must still launch one
## actual finite round from handheld, roof and convoy weapons.
const Protocol := preload("res://scripts/network_protocol.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var network
var worker
var sequence := 0
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func rounds() -> int:
	var count := 0
	for child in game.get_children():
		if child is WorkerShot or child is BunkerProjectile: count += 1
	return count

func tap() -> void:
	for press: bool in [true, false]:
		sequence += 1
		network._packet(Protocol.encode({"kind": "input", "generation": 23, "seq": sequence,
			"input": {"held": {"fire": 1.0} if press else {}, "pressed": ["fire"] if press else [],
				"released": [] if press else ["fire"], "aim": [2500, 100], "mouse": true}}))
	network._physics_process(1.0 / 60)
	check(NetInput.just_pressed(worker, "fire") and not NetInput.is_pressed(worker, "fire"), "Queued trigger edge survives its already received released held state")

func drain() -> void:
	for tick in 2: network._physics_process(1.0 / 60)

func verify_weapon(target: Node, label: String, handheld: bool = false) -> void:
	var before := rounds()
	target.cooldown = 0.0
	if handheld: target.loaded.rifle = 3
	else: target.ammo = 3
	tap()
	target._physics_process(1.0 / 60)
	var ammunition: int = target.current_ammo() if handheld else target.ammo
	check(ammunition == 2 and rounds() == before + 1, label + ": catch-up tap spends exactly one original round and creates its actual projectile")
	network._physics_process(1.0 / 60)
	target._physics_process(1.0 / 60)
	network._physics_process(1.0 / 60)
	target._physics_process(1.0 / 60)
	check((target.current_ammo() if handheld else target.ammo) == ammunition and rounds() == before + 1, label + ": release and drained FIFO do not repeat the shot")
	tap()
	target._physics_process(1.0 / 60)
	check((target.current_ammo() if handheld else target.ammo) == ammunition and rounds() == before + 1, label + ": a second immediate tap still respects the real firing cooldown")
	drain()
	target.cooldown = 0.0
	target.reserve = 0
	if handheld: target.loaded.rifle = 0
	else: target.ammo = 0
	tap()
	target._physics_process(1.0 / 60)
	check((target.current_ammo() if handheld else target.ammo) == 0 and rounds() == before + 1, label + ": an empty trigger cannot create ammunition or another projectile")
	drain()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(2, {"environment": "ash_foundry", "build_type": "bastion", "position": "left"})
	game.rounds.running = false
	freeze(game)
	network = game.network
	network.leave()
	network.active = true
	network.is_host = true
	network.state = "playing"
	network._authenticated = true
	network._generation = 23
	network._clock = 10
	network._loading = false
	network.match_paused = false
	worker = game.players[1]
	worker.inventory.clear()
	worker.global_position = Vector2(1800, 200)
	var weapon: WorkerWeapon = worker.get_node("WorkerWeapon")
	weapon.weapon_kind = "rifle"
	verify_weapon(weapon, "Actual remote handheld rifle", true)
	var turret := RoofTurret.new()
	turret.game = game
	game.add_child(turret)
	turret.set_physics_process(false)
	turret.global_position = Vector2(1800, 200)
	turret.enter(worker)
	check(turret.occupant == worker and worker.mounted_turret == turret, "Actual remote worker occupies the real roof gun")
	verify_weapon(turret, "Actual occupied roof gun")
	turret.exit()
	var truck := Vehicle.new()
	truck.game = game
	game.add_child(truck)
	freeze(truck)
	truck.configure_trip(Vector2(1800, 200), Vector2(1500, 3000), {"hp": 600.0, "fuel": 12.0, "ammo": 3, "reserve": 0})
	truck.has_mg = true
	truck.driving_enabled = false
	worker.global_position = truck.global_position
	check(truck.board(worker, "gunner") and worker.mounted_turret == truck.gunner_seat, "Actual remote worker boards the real convoy MG seat")
	verify_weapon(truck, "Actual occupied convoy MG")
	network.leave()
	await Cleanup.free_scene(game, self)
	print("NETWORK FIRE CATCHUP: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
