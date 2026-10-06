extends SceneTree
## Held deposits conserve real cargo, keep withdrawal explicit and route guest input.
const NetWorld = preload("res://scripts/network_world.gd")
const Schema = preload("res://scripts/network_replication_schema.gd")
const Cleanup = preload("res://tests/scene_cleanup.gd")

class Session extends Node:
	var active := false
	var local_player_id := 1
	var is_host := true
	var remote_input := {}

class World extends Node2D:
	var started := true
	var players: Array[Worker] = []
	var network: Node
	func sound(_kind): pass

class RefusingWorker extends Worker:
	func take_item(_kind: String, _amount: int = 1) -> bool:
		return false

var checks := 0
var failures := 0
var world: World
var crate: Supply

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)

func worker(id: int) -> Worker:
	var result: Worker = load("res://scenes/player.tscn").instantiate()
	result.player_id = id
	result.game = world
	result.position = Vector2(120+(id-1)*10,200)
	world.add_child(result)
	result.set_physics_process(false)
	result.focus = crate
	world.players.append(result)
	return result

func release_inputs() -> void:
	for key in ["p1_craft_next","p2_craft_next","p1_interact","p2_interact"]:
		Input.action_release(key)

func run() -> void:
	InputSetup.install()
	world = World.new()
	root.add_child(world)
	world.network = Session.new()
	world.add_child(world.network)
	crate = Supply.new()
	crate.game = world
	crate.kind = "steel"
	crate.amount = 0
	crate.position = Vector2(150,200)
	world.add_child(crate)
	crate.set_physics_process(false)
	var p1 := worker(1)
	var p2 := worker(2)
	await physics_frame
	await physics_frame
	p1.inventory = {"steel":3,"sand":2}
	p1.selected_kind = "steel"
	check(crate.can_interact(p1), "An empty nearby crate remains selectable for return deliveries")
	check(crate.has_method("deposit"), "Supply exposes a validated deposit transaction")
	if not crate.has_method("deposit"):
		release_inputs()
		await Cleanup.free_scene(world,self)
		print("SUPPLY STORAGE CHECKS: %d passed, %d failed" % [checks-failures,failures])
		quit(1)
		return
	Input.action_press("p1_craft_next")
	crate._physics_process(0.15)
	check(crate.amount == 0 and p1.inventory.steel == 3, "A short G press starts a deposit without taking cargo early")
	crate._physics_process(0.16)
	check(crate.amount == 1 and p1.inventory.steel == 2, "Holding G deposits exactly one selected matching resource")
	check(p1.last_transfer_kind == "steel" and p1.drop_animation > 0, "Successful deposits use the material hand-off animation")
	crate._physics_process(0.31)
	crate._physics_process(0.31)
	crate._physics_process(2.0)
	check(crate.amount == 3 and p1.inventory == {"sand":2}, "Repeated holding stores the steel stack without changing another material")
	p1.inventory.steel = 1
	p1.selected_kind = "steel"
	check(crate.controls_hint(p1).contains("G") and crate.controls_hint(p1).contains("einlagern"), "The crate explains its separate storage control")
	p2.inventory = {"steel":1}
	p2.selected_kind = "steel"
	check(crate.controls_hint(p2).contains("Num*") and crate.controls_hint(p2).contains("L3"), "Local second-player storage hints match keyboard and gamepad mappings")
	p2.inventory = {"sand":p2.capacity()}
	check(crate.controls_hint(p2) == "Inventarplatz freimachen", "Full unrelated cargo gets a useful space hint instead of another delivery request")
	p1.inventory.erase("steel")
	p2.inventory.clear()
	release_inputs()
	crate.interact(p1,0.31)
	check(crate.amount == 2 and p1.inventory.get("steel",0) == 1, "Primary interaction still withdraws even while carrying another material")
	p1.selected_kind = "steel"
	crate.interact(p1,0.31)
	check(crate.amount == 1 and p1.inventory.steel == 2, "Carrying matching material never silently reverses withdrawal into deposit")
	var before := p1.inventory.duplicate()
	p1.selected_kind = "sand"
	crate.deposit(p1,1.0)
	check(p1.inventory == before and crate.amount == 1, "A different selected material cannot enter this crate")
	p1.selected_kind = "steel"
	crate.deposit(p1,0.15)
	check(crate.interaction_progress(p1) > 0 and crate.interaction_progress(p1) < 1, "Deposit progress is visible before a committed unit")
	Input.action_press("p1_interact")
	Input.action_press("p1_craft_next")
	crate._physics_process(0.3)
	check(crate.amount == 1 and p1.inventory == before, "Primary interaction wins when both controls are held")
	release_inputs()
	crate._physics_process(0.01)
	check(is_zero_approx(crate.deposit_transfer.get(1,0.0)), "Releasing storage clears its partial hold")
	for invalid in [0.0,-1.0,NAN,INF]:
		crate.deposit(p1,invalid)
	check(crate.amount == 1 and p1.inventory == before, "Invalid deposit durations cannot alter inventories")
	p1.position.x += 200
	crate.deposit(p1,1.0)
	check(crate.amount == 1 and p1.inventory == before, "Out-of-reach deposit attempts preserve both inventories")
	crate.interact(p1,1.0)
	check(not crate.can_interact(p1) and crate.amount == 1 and p1.inventory == before, "Out-of-reach withdrawal cannot bypass normal interaction range")
	p1.position.x -= 200
	p1.hurt_stun = 1.0
	crate.deposit(p1,1.0)
	check(crate.amount == 1 and p1.inventory == before, "An incapacitated worker cannot deposit")
	p1.hurt_stun = 0.0
	var barrier := StaticBody2D.new()
	barrier.collision_layer = 1|2
	barrier.position = Vector2(138,170)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8,80)
	shape.shape = box
	barrier.add_child(shape)
	world.add_child(barrier)
	await physics_frame
	await physics_frame
	crate.deposit(p1,1.0)
	check(crate.amount == 1 and p1.inventory == before, "Terrain and walls block deposits without consuming cargo")
	crate.interact(p1,1.0)
	check(not crate.can_interact(p1) and crate.amount == 1 and p1.inventory == before, "The same solid barrier also blocks withdrawal and focus selection")
	barrier.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	p1.inventory = {"steel":6}
	p1.selected_kind = "steel"
	crate.deposit(p1,0.31)
	check(p1.carried_count() == 5 and crate.amount == 2, "A full inventory can free space by depositing into an existing crate")
	p2.inventory = {"steel":2}
	p2.selected_kind = "steel"
	Input.action_press("p2_craft_next")
	crate._physics_process(0.31)
	check(p2.inventory.steel == 1 and p1.inventory.steel == 5 and crate.amount == 3, "Local P2 storage affects only its own cargo")
	release_inputs()
	world.network.active = true
	world.network.remote_input = {"held":{"craft_next":1.0}}
	crate._physics_process(0.31)
	check(p2.carried_count() == 0 and p1.inventory.steel == 5 and crate.amount == 4, "Host applies the guest's existing validated storage input")
	world.network.remote_input = {}
	world.network.is_host = false
	world.network.local_player_id = 2
	p2.inventory = {"steel":1}
	p2.selected_kind = "steel"
	check(crate.controls_hint(p2).contains("G") and not crate.controls_hint(p2).contains("Num*"), "Online guest receives its actual primary keyboard bindings")
	world.network.active = false
	crate.deposit(p1,0.15)
	var snapshotter = NetWorld.new()
	snapshotter.game = world
	var wire: Dictionary = snapshotter._capture_fields(crate,Schema.fields("supply"))
	check(wire.has("deposit_transfer") and is_equal_approx(wire.deposit_transfer.get(1,0.0),0.15), "Supply snapshots carry storage progress under stable player IDs")
	var mirror := Supply.new()
	world.add_child(mirror)
	mirror.set_physics_process(false)
	snapshotter._apply_fields(mirror,wire)
	check(mirror.amount == 4 and is_equal_approx(mirror.deposit_transfer.get(1,0.0),0.15), "Guest presentation receives the real quantity and progress without a second transaction")
	crate.interact(p1,0.15)
	var withdrawal: Dictionary = snapshotter._capture_fields(crate,Schema.fields("supply"))
	snapshotter._apply_fields(mirror,withdrawal)
	var guest_worker := Worker.new()
	guest_worker.player_id = p1.player_id
	world.add_child(guest_worker)
	guest_worker.set_physics_process(false)
	check(guest_worker.get_instance_id()!=p1.get_instance_id() and is_equal_approx(mirror.interaction_progress(guest_worker),0.5), "Withdrawal progress also reaches a guest with a different local worker instance")
	var refusing := RefusingWorker.new()
	refusing.game = world
	refusing.player_id = 3
	refusing.position = p1.position
	world.add_child(refusing)
	refusing.set_physics_process(false)
	refusing.inventory = {"steel":1}
	refusing.selected_kind = "steel"
	crate.deposit(refusing,0.31)
	check(crate.amount == 4 and refusing.inventory.steel == 1, "A rejected inventory debit never creates stored material")
	crate.queue_free()
	crate.deposit(p1,1.0)
	check(p1.inventory.steel == 5, "A crate queued for removal cannot consume the last delivery")
	release_inputs()
	check(await Cleanup.free_scene(world,self), "Storage fixtures release without persistent profile changes")
	print("SUPPLY STORAGE CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures == 0 else 1)
