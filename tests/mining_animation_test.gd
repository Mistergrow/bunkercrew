extends SceneTree
## Real worker poses drive presentation on real mine cells; excavation progress
## remains independent of rendering cadence and the number of workers.

class PresentationProbe extends Node2D:
	var contacts: Array[Vector2] = []
	var contact_materials: Array[String] = []
	var mining_sounds := 0
	func impact(at: Vector2, kind: String, _direction: Vector2, strength: float) -> void:
		if is_equal_approx(strength, 0.25):
			contacts.append(at)
			contact_materials.append(kind)
	func sound(kind: String) -> void:
		if kind == "mine": mining_sounds += 1
	func fx(at: Vector2, _color: Color, _count: int) -> void:
		contacts.append(at)

class LivePresentationProbe extends PresentationProbe:
	var started := true
	var world_right := 500.0
	var floor_levels: Array = [320.0]
	var ladders: Array[Rect2] = []
	var upgrades
	func valid_focus(worker, target) -> bool:
		return is_instance_valid(target) and not target.is_queued_for_deletion() and target.can_interact(worker)
	func focus_candidates(worker) -> Array:
		var result: Array = []
		for target in get_tree().get_nodes_in_group("mine_blocks"):
			if valid_focus(worker, target): result.append(target)
		return result
	func get_focus(worker):
		var targets := focus_candidates(worker)
		return null if targets.is_empty() else targets[0]
	func notify(_message: String) -> void: pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _worker(parent: Node, id: int) -> Worker:
	var worker := Worker.new()
	worker.player_id = id
	parent.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	return worker

func _block(parent: PresentationProbe, at: Vector2) -> MineBlock:
	var block := MineBlock.new()
	block.kind = "ore"
	block.position = at
	block.game = parent
	parent.add_child(block)
	return block

func _run() -> void:
	InputSetup.install()
	var world := PresentationProbe.new()
	root.add_child(world)
	var first := _worker(world, 1)
	var second := _worker(world, 2)
	var first_visual := first.get_node("PixelVisual") as WorkerVisual
	var second_visual := second.get_node("PixelVisual") as WorkerVisual
	var right := _block(world, Vector2(58, -22))
	var left := _block(world, Vector2(-58, -22))
	await physics_frame
	await physics_frame
	first.focus = right
	first.mining = true
	right.interact(first, 0.20)
	_check(is_equal_approx(right.mining, 0.20) and world.contacts.is_empty(), "Work advances without an off-pose impact")
	first_visual._process(2.9 / 12.8)
	_check(world.contacts.is_empty(), "Anticipation poses produce no contact burst")
	first_visual._process(0.2 / 12.8)
	_check(first_visual.pose_frame == 3 and world.contacts.size() == 1 and world.mining_sounds == 1, "Forward tool contact emits exactly one synchronized burst and sound")
	_check(world.contact_materials == ["mining_ore"] and is_equal_approx(world.contacts[0].x,34), "Ore strike uses mineral chips at the actual exposed rock face")
	first_visual._process(1.5 / 12.8)
	_check(world.contacts.size() == 1, "Holding and leaving contact pose never repeats a strike")
	first_visual._process(14.6 / 12.8)
	_check(world.contacts.size() == 3 and world.mining_sounds == 3, "A slow render update preserves both crossed strikes exactly once")
	_check(is_equal_approx(right.mining, 0.20) and first.inventory.is_empty(), "Rendering strikes cannot change work progress or yield")
	first.mining = false
	first_visual._process(1.0)
	_check(world.contacts.size() == 3, "Cancelling mining cannot release a delayed strike")
	first.mining = true
	first_visual._process(2.9 / 12.8)
	_check(world.contacts.size() == 3, "Restarting begins with clean anticipation")
	first_visual._process(0.2 / 12.8)
	_check(world.contacts.size() == 4, "Restarted swing produces one fresh contact")
	first_visual.crouched = true
	first_visual._process(3.1 / 12.8)
	_check(first_visual.pose_name == "crouch_mine" and world.contacts.size() == 5, "Crouched mining uses the same authored contact frame")
	second.focus = right
	second.mining = true
	right.interact(second, 0.30)
	second_visual._process(3.1 / 12.8)
	_check(world.contacts.size() == 6 and is_equal_approx(right.mining, 0.50), "Co-op worker has an independent strike while work accumulation is unchanged")
	first.focus = left
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() == 7 and world.contacts[-1].x < 0, "A continuous swing follows the current target without replaying on the old cell")
	first.focus = null
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() == 7, "Losing the focus suppresses further contact effects")
	first.focus = left
	first.mining = false
	first_visual._process(0.0)
	first.mining = true
	var contacts_before := world.contacts.size()
	for _frame in 120:
		first_visual._process(1.0 / 120.0)
	_check(world.contacts.size() - contacts_before == 2, "One second at 120 Hz reaches both expected contacts")
	first.mining = false
	first_visual._process(0.0)
	first.mining = true
	contacts_before = world.contacts.size()
	for _frame in 30:
		first_visual._process(1.0 / 30.0)
	_check(world.contacts.size() - contacts_before == 2, "30 Hz rendering matches the same two contacts")
	left.depleted = true
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() - contacts_before == 2, "A depleted cell ignores later visual contact")
	var shaft = load("res://scripts/excavation_site.gd").new()
	shaft.game = world
	world.add_child(shaft)
	first.focus = shaft
	contacts_before = world.contacts.size()
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() == contacts_before, "An unsupported shaft does not emit excavation strikes")
	shaft.materials = {"steel": 2}
	shaft.interact(first, 0.30)
	_check(is_equal_approx(shaft.work, 0.30) and world.contacts.size() == contacts_before, "Shaft work advances independently of strike presentation")
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() == contacts_before + 1 and is_equal_approx(shaft.work, 0.30), "A supported shaft emits one burst per tool contact without changing work")
	shaft.completed = true
	first_visual._process(8.0 / 12.8)
	_check(world.contacts.size() == contacts_before + 1, "Completed shaft suppresses later contact effects")
	_check(world.contacts.size() == world.mining_sounds, "Every contact burst has exactly one mining sound")
	await preload("res://tests/scene_cleanup.gd").free_scene(world, self)
	# Check real physics/process scheduling and the normal held interaction, in
	# addition to the deterministic skipped-frame and co-op pose checks above.
	var live := LivePresentationProbe.new()
	root.add_child(live)
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var floor_box := RectangleShape2D.new()
	floor_box.size = Vector2(500, 20)
	floor_shape.shape = floor_box
	floor_shape.position = Vector2(250, 330)
	floor_body.add_child(floor_shape)
	live.add_child(floor_body)
	var live_worker = load("res://scenes/player.tscn").instantiate()
	live_worker.game = live
	live_worker.position = Vector2(82, 320)
	live.add_child(live_worker)
	var live_block := _block(live, Vector2(140, 298))
	for _frame in 4: await physics_frame
	live_worker.preferred_focus = live_block
	Input.action_press("p1_interact")
	for _frame in 120:
		await physics_frame
		if not is_instance_valid(live_block) or live_block.depleted: break
	Input.action_release("p1_interact")
	_check(live_worker.inventory.get("ore", 0) == Balance.MINE_YIELD, "Held real input still excavates one cell with its original yield")
	_check(live.contacts.size() == 2 and live.mining_sounds == 2, "Real physics/process scheduling plays both contacts before normal cell depletion")
	for _frame in 3: await physics_frame
	_check(live.contacts.size() == 2, "Releasing held input after depletion adds no trailing strike")
	await preload("res://tests/scene_cleanup.gd").free_scene(live, self)
	print("MINING ANIMATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
