extends SceneTree
## Run: godot --headless --path . --script tests/worker_visual_test.gd

class TestTurret:
	extends Node2D
	var recoil := 0.0

class TestWeapon:
	extends Node2D
	var aiming := true
	var flash := 0.0
	var recoil := 4.0
	var aim_direction := Vector2.RIGHT

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func _run() -> void:
	InputSetup.install()
	var world := Node2D.new()
	root.add_child(world)
	var worker := Worker.new()
	world.add_child(worker)
	worker.set_physics_process(false)
	var visual := worker.get_node_or_null("PixelVisual") as WorkerVisual
	if visual == null:
		visual = WorkerVisual.new()
		visual.worker = worker
		worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	await process_frame
	_check(visual._frames.size() == 19, "All 19 animation states loaded")
	var frames := 0
	for descriptor: Dictionary in visual._frames.values():
		frames += int(descriptor.frames)
		_check(descriptor.item_anchors.size() == int(descriptor.frames), "Every pose has a hand/item anchor")
	_check(frames == 110, "110 authored poses per character identity")
	visual._process(0.1)
	_check(visual.pose_name == "idle", "Stationary idle")
	worker.velocity.x = 160.0
	visual._process(0.1)
	_check(visual.pose_name == "walk", "Walking has distinct gait")
	var walk_frame := visual.pose_frame
	visual._process(0.15)
	_check(visual.pose_frame != walk_frame, "Walking frames progress")
	worker.add_item("concrete", 1)
	worker.pickup_animation = 0.0
	visual._process(0.1)
	_check(visual.pose_name == "carry_walk", "Carried load changes walking pose")
	worker.velocity.x = 0.0
	visual._process(0.1)
	_check(visual.pose_name == "carry_idle", "Stationary worker supports held cargo")
	worker.mining = true
	visual._process(0.1)
	_check(visual.pose_name == "mine", "Mining uses pick anticipation and strike poses")
	worker.mining = false
	worker._airborne = true
	worker.velocity.y = -200
	visual._process(0.1)
	_check(visual.pose_name == "jump_up", "Jump rise pose")
	worker.velocity.y = 100
	visual._process(0.1)
	_check(visual.pose_name == "fall", "Falling pose")
	worker._airborne = false
	worker._landing_time = 0.12
	visual._process(0.03)
	_check(visual.pose_name == "land", "Landing recovery pose")
	worker._landing_time = 0.0
	worker.drop_animation = 0.3
	worker.last_transfer_kind = "concrete"
	worker.take_item("concrete", 1)
	visual._process(0.02)
	_check(visual.pose_name == "drop", "Last item keeps a visible drop animation")
	worker.drop_animation = 0.0
	worker.add_item("ore", 1)
	visual._process(0.02)
	_check(visual.pose_name == "pickup", "Accepted pickup bends and reaches")
	worker.pickup_animation = 0.0
	worker.climbing = true
	visual._process(0.1)
	_check(visual.pose_name == "climb", "Climb has a separate full-body pose")
	var held_frame := visual.pose_frame
	Input.action_press("p1_up")
	visual._process(0.5)
	Input.action_release("p1_up")
	_check(visual.pose_frame == held_frame, "Climb frame stays still without actual movement, even with held input")
	worker.global_position.y -= 7.0
	visual._process(0.01)
	_check(visual.pose_frame == (held_frame + 1) % 8, "Ascent advances by one pose per seven world pixels")
	worker.global_position.y += 7.0
	visual._process(0.01)
	_check(visual.pose_frame == held_frame, "Descent retraces the same pose instead of playing ascent forwards")
	worker.facing = -1.0
	_check(visual.sprite_facing() == 1.0, "Back-view ladder sprite ignores previous left-facing walk")
	worker.facing = 1.0
	worker.climbing = false
	worker.inventory.clear()
	var weapon := TestWeapon.new()
	weapon.name = "WorkerWeapon"
	worker.add_child(weapon)
	visual._process(0.01)
	_check(visual.pose_name == "weapon" and visual.pose_frame == 1, "Handheld gun aiming drives the braced firing and recoil pose")
	weapon.aim_direction = Vector2(1, -1).normalized()
	visual._process(0.01)
	_check(visual.pose_name == "weapon_up", "Upward handheld aim raises both arms")
	weapon.aim_direction = Vector2(1, 1).normalized()
	visual._process(0.01)
	_check(visual.pose_name == "weapon_down", "Downward handheld aim lowers both arms")
	worker.velocity.x = 160.0
	visual._process(0.1)
	_check(visual.pose_name == "walk" and visual.weapon_pose() == "weapon_down", "Moving while firing keeps walking legs and braced upper body")
	worker.inventory["ore"] = 1
	visual._process(0.1)
	_check(visual.pose_name == "carry_walk" and visual.weapon_pose().is_empty(), "Carried cargo takes priority over firearm art")
	worker.inventory.clear()
	worker.velocity.x = 0.0
	weapon.aiming = false
	weapon.recoil = 0.0
	visual._process(0.1)
	_check(visual.pose_name == "idle", "Releasing handheld aim restores idle")
	worker.remove_child(weapon)
	weapon.free()
	var turret := TestTurret.new()
	world.add_child(turret)
	worker.mounted_turret = turret
	turret.recoil = 6.0
	visual._process(0.01)
	_check(visual.pose_name == "turret" and visual.pose_frame == 1, "Gun recoil drives worker recoil frame")
	worker.mounted_turret = null
	var ceiling := StaticBody2D.new()
	ceiling.collision_layer = 1
	ceiling.position = Vector2(0, -58)
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(100, 8)
	ceiling.add_child(shape)
	world.add_child(ceiling)
	await physics_frame
	await physics_frame
	visual._physics_process(0.2)
	visual._process(0.1)
	_check(visual.crouched and visual.pose_name == "crouch", "Low mine ceiling selects authored crouch pose")
	worker.mining = true
	visual._process(0.1)
	_check(visual.pose_name == "crouch_mine", "Mining beneath low ceiling stays crouched")
	world.queue_free()
	await process_frame
	print("WORKER VISUAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
