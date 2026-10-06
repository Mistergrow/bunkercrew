extends SceneTree

## Inventory and input regressions for the material handling update.
class TestArena extends Node2D:
	var started := true
	var ladders: Array[Rect2] = []
	var target
	var reject_drop := false
	var drops: Array[ResourcePickup] = []
	func get_focus(_player):
		return target
	func drop_material(player, kind: String, amount: int) -> bool:
		if reject_drop or not player.take_item(kind, amount):
			return false
		var pile: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
		pile.game = self
		pile.kind = kind
		pile.amount = amount
		pile.position = player.position + Vector2(30, -10)
		add_child(pile)
		pile.set_physics_process(false)
		drops.append(pile)
		return true
	func sound(_kind: String) -> void:
		pass

class WorkTarget extends Node2D:
	var calls := 0
	func interaction_point() -> Vector2:
		return global_position - Vector2(0, 20)
	func interact(_player, _delta: float) -> void:
		calls += 1

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
	else:
		print("PASS ", label)

func release_inputs() -> void:
	for id in [1, 2]:
		for suffix in ["drop", "interact", "cycle_material"]:
			Input.action_release("p%d_%s" % [id, suffix])

func run_checks() -> void:
	InputSetup.install()
	release_inputs()
	var arena := TestArena.new()
	root.add_child(arena)
	var scene = load("res://scenes/player.tscn")
	var p1: Worker = scene.instantiate()
	p1.game = arena
	p1.position = Vector2(200, 600)
	arena.add_child(p1)
	p1.set_physics_process(false)
	var p2: Worker = scene.instantiate()
	p2.game = arena
	p2.player_id = 2
	p2.position = Vector2(300, 600)
	arena.add_child(p2)
	p2.set_physics_process(false)

	p1.add_item("ore", 2)
	p1.add_item("sand", 3)
	check(p1.selected_material() == "ore", "Receiving another resource preserves the selected material")
	p1.cycle_material()
	check(p1.selected_material() == "sand", "Cycle selects another carried material explicitly")
	p1.take_item("ore", 1)
	check(p1.selected_material() == "sand", "Transferring a different material preserves the selection")
	p1.take_item("sand", 3)
	check(p1.selected_material() == "ore", "Depleting the selected material selects a remaining material")
	p1.take_item("ore", 1)
	check(p1.selected_material().is_empty(), "Empty inventory clears the material selection")
	p1.add_item("sand", 3)
	p1.add_item("steel", 3)
	p1.cycle_material()
	p2.add_item("ore", 4)
	Input.action_press("p1_drop")
	p1._update_material_controls(0.12)
	p2._update_material_controls(0.12)
	check(p1.carried_count() == 6 and p2.carried_count() == 4, "Press waits for tap versus hold without dropping prematurely")
	Input.action_release("p1_drop")
	p1._update_material_controls(0.016)
	p2._update_material_controls(0.016)
	check(p1.inventory.get("steel", 0) == 2 and p1.inventory.get("sand", 0) == 3, "Tap drops one selected steel and preserves sand")
	check(arena.drops.size() == 1 and arena.drops[0].kind == "steel" and arena.drops[0].amount == 1, "Tap transfers exactly one material unit into a real world pile")
	check(p2.inventory.get("ore", 0) == 4, "Player one drop does not affect player two")
	check(p1.last_transfer_kind == "steel" and p1.drop_animation > 0, "Drop animation remembers the transferred material")
	Input.action_press("p1_drop")
	p1._update_material_controls(0.2)
	check(is_equal_approx(p1.drop_hold_progress(), 0.5), "Hold progress exposes the 0.4 second stack-drop threshold")
	p1._update_material_controls(0.21)
	check(p1.inventory.get("steel", 0) == 0 and p1.inventory.get("sand", 0) == 3 and arena.drops[1].amount == 2, "Holding drops the remaining selected stack only")
	p1._update_material_controls(1.0)
	Input.action_release("p1_drop")
	p1._update_material_controls(0.016)
	check(arena.drops.size() == 2 and p1.carried_count() == 3, "Keeping drop held and releasing never spills another material")
	check(p1.selected_material() == "sand" and p1.last_transfer_kind == "steel", "Selection advances while the final dropped material remains available to animation")
	arena.reject_drop = true
	p1._drop_one()
	check(p1.carried_count() == 3 and arena.drops.size() == 2, "Rejected placement preserves all inventory and world quantities")
	arena.reject_drop = false
	Input.action_press("p2_drop")
	p1._update_material_controls(0.42)
	p2._update_material_controls(0.42)
	Input.action_release("p2_drop")
	p1._update_material_controls(0.016)
	p2._update_material_controls(0.016)
	check(p1.carried_count() == 3 and p2.carried_count() == 0 and arena.drops[2].amount == 4, "Player two independently drops a whole stack without affecting player one")

	var pile: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
	pile.kind = "ore"
	pile.amount = 5
	pile.position = p1.position
	pile.game = arena
	arena.add_child(pile)
	pile.set_physics_process(false)
	arena.target = pile
	Input.action_press("p1_interact")
	p1._update_interaction(0.001)
	check(p1.inventory.get("ore", 0) == 3 and pile.amount == 2 and p1.carried_count() == 6, "A short pickup tap immediately fills free capacity and retains overflow")
	check(p1.selected_material() == "sand" and p1.pickup_animation > 0, "Pickup keeps explicit selection and starts the pickup animation")
	p1.take_item("ore", 1)
	p1._update_interaction(0.6)
	check(pile.amount == 2 and p1.inventory.get("ore", 0) == 2, "A held pickup press does not silently refill space freed later")
	Input.action_release("p1_interact")
	p1._update_interaction(0.016)
	Input.action_press("p1_interact")
	p1._update_interaction(0.001)
	check(pile.amount == 1 and p1.carried_count() == 6, "A fresh pickup tap collects the remaining fitting amount")
	Input.action_release("p1_interact")
	p1._update_interaction(0.016)
	p1.inventory.clear()
	Input.action_press("p1_interact")
	p1._update_interaction(0.001)
	check(p1.inventory.get("ore", 0) == 1 and pile.amount == 0 and pile.is_queued_for_deletion(), "Emptying a world pile removes it without material loss")

	var mining_target := WorkTarget.new()
	mining_target.position = p1.position
	arena.add_child(mining_target)
	mining_target.add_to_group("mine_blocks")
	arena.target = mining_target
	p1._update_interaction(0.5)
	check(mining_target.calls == 0 and not p1.mining, "Deleting a picked-up pile cannot transfer the held action to nearby mining")
	Input.action_release("p1_interact")
	p1._update_interaction(0.016)
	Input.action_press("p1_interact")
	p1._update_interaction(0.1)
	check(mining_target.calls == 1 and p1.mining, "Pressing again explicitly starts work on the new target")
	var station_target := WorkTarget.new()
	station_target.position = p1.position
	arena.add_child(station_target)
	arena.target = station_target
	p1._update_interaction(0.1)
	check(mining_target.calls == 2 and station_target.calls == 0 and p1.focus == mining_target, "Held work stays on its selected object when candidate priority changes")
	p1.position.x += 150
	p1._update_interaction(0.1)
	check(mining_target.calls == 2 and not p1._interacting, "Walking away suspends a held interaction outside its reach")
	p1.position.x -= 150
	mining_target.queue_free()
	p1._update_interaction(0.1)
	check(station_target.calls == 0 and p1.focus == null, "Destroying the held work target never redirects the action to a station")
	Input.action_release("p1_interact")
	p1._update_interaction(0.016)
	Input.action_press("p1_interact")
	p1._update_interaction(0.1)
	check(station_target.calls == 1 and p1.focus == station_target, "Releasing then pressing permits the intended station interaction")
	release_inputs()

	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	var insert := InputEventKey.new()
	insert.physical_keycode = KEY_INSERT
	var shoulder := InputEventJoypadButton.new()
	shoulder.device = 0
	shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
	var pad_drop := InputEventJoypadButton.new()
	pad_drop.device = 0
	pad_drop.button_index = JOY_BUTTON_B
	check(InputMap.event_is_action(tab, "p1_cycle_material") and not InputMap.event_is_action(tab, "p2_cycle_material"), "Tab changes only player one's selected material")
	check(InputMap.event_is_action(insert, "p2_cycle_material") and not InputMap.event_is_action(insert, "p1_cycle_material"), "Insert changes only player two's selected material")
	check(InputMap.event_is_action(shoulder, "p2_cycle_material") and not InputMap.event_is_action(shoulder, "p1_cycle_material"), "Controller LB cycles only player two's materials")
	check(InputMap.event_is_action(pad_drop, "p2_drop") and not InputMap.event_is_action(pad_drop, "p1_drop"), "Controller B maps drop exclusively to player two")

	# A real physics floor verifies swept settling, including a large one-frame fall.
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(900, 18)
	collider.shape = rectangle
	collider.position = Vector2(500, 609)
	floor_body.add_child(collider)
	arena.add_child(floor_body)
	var falling: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
	falling.position = Vector2(550, 510)
	arena.add_child(falling)
	falling.set_physics_process(false)
	await physics_frame
	await physics_frame
	falling._physics_process(0.03)
	check(falling.position.y > 510, "Unsupported material piles fall instead of hovering")
	falling._physics_process(1.0)
	check(absf(falling.position.y - 599.5) < 0.1 and falling.fall_speed == 0, "Swept pickup motion settles on the floor without tunneling at large delta")
	for frame in 15:
		falling._physics_process(0.016)
	check(absf(falling.position.y - 599.5) < 0.1, "Settled piles remain at the floor surface")
	print("MATERIAL CONTROL CHECKS: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
