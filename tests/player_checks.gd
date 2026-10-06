extends SceneTree

class TestGame extends Node2D:
	var started = true
	var ladders: Array[Rect2] = [Rect2(218, 205, 44, 400), Rect2(320, 560, 44, 240)]
	var drops: Array = []
	func get_focus(player):
		var closest = null
		var closest_distance := 83.0
		for target in get_tree().get_nodes_in_group("interactables"):
			if not is_instance_valid(target) or target.is_queued_for_deletion():
				continue
			if target.has_method("can_interact") and not target.can_interact(player):
				continue
			var point: Vector2 = target.interaction_point()
			var center: Vector2 = player.global_position - Vector2(0, 20)
			var distance := center.distance_to(point)
			if absf(center.y - point.y) <= 68 and distance < closest_distance:
				closest = target
				closest_distance = distance
		return closest
	func spawn_pickup(kind, amount, pos):
		drops.append([kind, amount, pos])
	func sound(_kind):
		pass
	func fx(_pos, _color = Color.WHITE, _count = 8):
		pass
	func notify(_message):
		pass

var fails := 0
func check(value: bool, label: String) -> void:
	if not value:
		fails += 1
		push_error(label)
	else:
		print("PASS ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	InputSetup.install()
	var game := TestGame.new()
	root.add_child(game)
	# Match the actual floor topology, including the open roof edge.
	for rect in [Rect2(75,245,675,18), Rect2(75,430,1365,22), Rect2(75,600,700,22), Rect2(75,800,1120,26), Rect2(58,245,16,580), Rect2(1195,622,24,204)]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.size
		shape.shape = rectangle
		shape.position = rect.get_center()
		body.add_child(shape)
		game.add_child(body)
	var scene = load("res://scenes/player.tscn")
	var p1 = scene.instantiate()
	p1.game = game
	p1.position = Vector2(240, 430)
	game.add_child(p1)
	var p2 = scene.instantiate()
	p2.player_id = 2
	p2.game = game
	p2.position = Vector2(380, 430)
	game.add_child(p2)
	check(p1.add_item("ore", 8) == 6 and p1.carried_count() == 6, "carry capacity clips safely")
	check(not p1.take_item("ore", 7) and p1.carried_count() == 6, "failed take preserves inventory")
	check(p1.take_item("ore", 2) and p1.add_item("sand", 4) == 2, "different materials share capacity")
	p1._drop_one()
	check(p1.carried_count() == 5 and game.drops.size() == 1, "drop transfers exactly one unit")
	p1.inventory.clear()
	for _i in 4:
		await physics_frame
	Input.action_press("p1_right")
	for _i in 15:
		await physics_frame
	Input.action_release("p1_right")
	check(p1.position.x > 280 and absf(p2.position.x - 380) < 1, "p1 input cannot move p2")
	Input.action_press("p2_left")
	var p1_x = p1.position.x
	for _i in 15:
		await physics_frame
	Input.action_release("p2_left")
	check(p2.position.x < 340 and absf(p1.position.x - p1_x) < 4, "p2 input cannot move p1")
	p1.position = Vector2(240, 430)
	p1.velocity = Vector2.ZERO
	Input.action_press("p1_up")
	for _i in 90:
		await physics_frame
	Input.action_release("p1_up")
	for _i in 5:
		await physics_frame
	check(absf(p1.position.y - 245) < 1 and p1.collision_mask == 1, "ladder reaches roof and restores collisions")
	Input.action_press("p1_down")
	for _i in 160:
		await physics_frame
	Input.action_release("p1_down")
	for _i in 5:
		await physics_frame
	check(absf(p1.position.y - 600) < 1 and p1.collision_mask == 1, "ladder reaches lower floor without trapping")
	p1.position = Vector2(342, 600)
	p1.velocity = Vector2.ZERO
	Input.action_press("p1_down")
	for _i in 95:
		await physics_frame
	Input.action_release("p1_down")
	for _i in 5:
		await physics_frame
	check(absf(p1.position.y - 800) < 1, "mine ladder reaches mine")
	var isolated := true
	for suffix in ["left", "right", "up", "down", "jump", "interact", "drop", "reload", "fire"]:
		for event in InputMap.action_get_events("p1_" + suffix):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				isolated = false
	check(isolated, "controller events assigned exclusively to p2")
	check(InputMap.action_get_events("p2_jump")[0].location == KEY_LOCATION_RIGHT, "second keyboard uses right shift")
	var stick := InputEventJoypadMotion.new()
	stick.device = 0
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	check(InputMap.event_is_action(stick, "p2_right") and not InputMap.event_is_action(stick, "p1_right"), "controller motion mapping belongs exclusively to p2")
	# Real player processing drives held mining, walking transport and production.
	var ore = load("res://scenes/mine_block.tscn").instantiate()
	ore.kind = "ore"
	ore.game = game
	ore.position = Vector2(410, 776)
	game.add_child(ore)
	for _i in 3:
		await physics_frame
	Input.action_press("p1_interact")
	for _i in 100:
		await physics_frame
	Input.action_release("p1_interact")
	check(p1.inventory.get("ore", 0) == 3 and not is_instance_valid(ore), "held input mines reachable ore into worker inventory")
	check(p2.carried_count() == 0, "p1 interaction does not give materials to p2")
	var furnace = load("res://scenes/station.tscn").instantiate()
	furnace.kind = "furnace"
	furnace.game = game
	furnace.position = Vector2(660, 800)
	game.add_child(furnace)
	Input.action_press("p1_right")
	for _i in 92:
		await physics_frame
	Input.action_release("p1_right")
	for _i in 3:
		await physics_frame
	check(p1.position.x > 595 and p1.position.x < 680 and p1.focus == furnace, "loaded worker walks to and selects furnace")
	Input.action_press("p1_interact")
	for _i in 55:
		await physics_frame
	Input.action_release("p1_interact")
	check(furnace.working and p1.inventory.get("ore", 0) == 1, "held interaction deposits exactly one recipe")
	for _i in 370:
		await physics_frame
	check(furnace.output_amount == 2 and not furnace.working, "furnace finishes autonomously")
	Input.action_press("p1_interact")
	for _i in 45:
		await physics_frame
	Input.action_release("p1_interact")
	check(p1.inventory.get("steel", 0) == 2 and furnace.output_amount == 0, "worker collects finished steel using same interaction")
	# An occupied turret must not bounce between mounted/unmounted while held.
	var turret = load("res://scenes/turret.tscn").instantiate()
	turret.game = game
	turret.position = Vector2(735, 245)
	game.add_child(turret)
	# The real level creates its turret before its workers. Preserve this order:
	# one interact press must not exit in turret code, then reenter in worker code.
	game.move_child(turret, 0)
	p2.position = Vector2(700, 245)
	p2.velocity = Vector2.ZERO
	for _i in 3:
		await physics_frame
	Input.action_press("p2_interact")
	for _i in 10:
		await physics_frame
	check(turret.occupant == p2 and p2.mounted_turret == turret, "p2 mounts turret and holding does not instantly dismount")
	Input.action_release("p2_interact")
	var old_angle = turret.aim_angle
	Input.action_press("p2_aim_down")
	for _i in 10:
		await physics_frame
	Input.action_release("p2_aim_down")
	check(turret.aim_angle > old_angle, "p2 keyboard aim moves mounted turret")
	var old_ammo = turret.ammo
	Input.action_press("p2_fire")
	for _i in 3:
		await physics_frame
	Input.action_release("p2_fire")
	check(turret.ammo == old_ammo - 1, "p2 fire action shoots exactly once within cooldown")
	p2.add_item("ammo", 1)
	var reload_rounds: int = turret.ammo+turret.reserve+AmmoTransfer.remainder(p2)+AmmoTransfer.PACK_SIZE*int(p2.inventory.get("ammo",0))
	Input.action_press("p2_reload")
	for _i in 3:
		await physics_frame
	Input.action_release("p2_reload")
	check(turret.reload_timer > 0 and p2.inventory.get("ammo", 0) == 0, "p2 reload consumes carried ammo crate")
	for _i in 70:
		await physics_frame
	check(turret.ammo == Balance.MAGAZINE and turret.reserve == 0 and AmmoTransfer.remainder(p2) == 19, "reload preserves remaining crate rounds with the worker")
	check(turret.ammo+turret.reserve+AmmoTransfer.remainder(p2)==reload_rounds,"roof reload conserves every carried ammunition round")
	Input.action_press("p2_interact")
	for _i in 3:
		await physics_frame
	Input.action_release("p2_interact")
	check(p2.mounted_turret == null and turret.occupant == null, "second interact press exits turret")
	print("PLAYER CHECKS: ", "PASS" if fails == 0 else "FAIL", " (", fails, " failures)")
	quit(fails)
