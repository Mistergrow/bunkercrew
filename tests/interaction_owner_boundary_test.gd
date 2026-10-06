extends SceneTree
## Real global groups must not transfer focus, cargo or technology between worlds.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var shared_world := World2D.new()

class Arena extends "res://scripts/game.gd":
	func _ready() -> void:
		upgrades = UpgradeSystem.new()
		add_child(upgrades)
	func fx(_pos: Vector2, _color: Color = Art.AMBER, _count: int = 8) -> void:
		pass
	func notify(_message: String) -> void:
		pass

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func arena(separate := true) -> Arena:
	var view := SubViewport.new()
	if separate:
		view.world_2d = World2D.new()
	else:
		view.world_2d = shared_world
	root.add_child(view)
	var world := Arena.new()
	view.add_child(world)
	return world

func worker(world: Arena) -> Worker:
	var result: Worker = load("res://scenes/player.tscn").instantiate()
	result.game = world
	result.position = Vector2(100, 100)
	world.add_child(result)
	result.set_physics_process(false)
	result.get_node("WorkerWeapon").set_physics_process(false)
	return result

func pile(world: Arena, kind: String) -> ResourcePickup:
	var result := ResourcePickup.new()
	result.game = world
	result.kind = kind
	result.amount = 3
	result.position = Vector2(130, 100)
	world.add_child(result)
	result.set_physics_process(false)
	return result

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	var own := arena()
	var other := arena()
	var own_worker := worker(own)
	var foreign := pile(other, "ore")
	await physics_frame
	await physics_frame
	check(own.get_world_2d() != other.get_world_2d(), "The fixtures use actual independent World2D instances")
	check(not own.valid_focus(own_worker, foreign) and own.get_focus(own_worker) == null, "Foreign group entries cannot become the own worker's focused cargo")
	check(not foreign.can_interact(own_worker), "Direct manual pickup rejects a foreign worker")
	foreign.interact(own_worker, 0.016)
	check(foreign.amount == 3 and own_worker.carried_count() == 0, "Foreign manual pickup conserves the other world's cargo")
	own_worker.inventory.clear()
	foreign.amount = 3
	var other_core := pile(other, "core")
	var old_points: int = other.upgrades.points
	other_core._collect_upgrade_points()
	check(other_core.amount == 3 and other.upgrades.points == old_points, "An own worker cannot remotely collect another world's technology crystals")
	var local := pile(own, "ore")
	check(own.valid_focus(own_worker, local) and own.get_focus(own_worker) == local, "Local material remains the actual selected focus")
	local.interact(own_worker, 0.016)
	check(own_worker.carried_count() == 3 and local.amount == 0, "A local transfer still conserves real carried material")
	var local_core := pile(own, "core")
	var local_points: int = own.upgrades.points
	local_core._collect_upgrade_points()
	check(local_core.amount == 0 and own.upgrades.points == local_points + 3, "A local worker still collects local technology exactly once")
	var live_other_worker := worker(other)
	var queued_core := pile(other, "core")
	live_other_worker.queue_free()
	var before_queued: int = other.upgrades.points
	queued_core._collect_upgrade_points()
	check(queued_core.amount == 3 and other.upgrades.points == before_queued, "A queued worker cannot collect crystals during teardown")
	var shared_a := arena(false)
	var shared_b := arena(false)
	var shared_worker := worker(shared_a)
	var shared_foreign := pile(shared_b, "ore")
	check(shared_a.get_world_2d() == shared_b.get_world_2d(), "The second fixture shares physics but has two distinct game owners")
	check(not shared_a.valid_focus(shared_worker, shared_foreign) and not shared_foreign.can_interact(shared_worker), "Shared physics does not grant interaction with another game's materials")
	var shared_core := pile(shared_b, "core")
	var shared_points: int = shared_b.upgrades.points
	shared_core._collect_upgrade_points()
	check(shared_core.amount == 3 and shared_b.upgrades.points == shared_points, "Shared physics does not grant another game's automatic technology credit")
	for world in [own, other, shared_a, shared_b]:
		check(await Cleanup.free_scene(world.get_parent(), self), "World and physics fixtures retire cleanly")
	print("INTERACTION OWNER BOUNDARIES: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
