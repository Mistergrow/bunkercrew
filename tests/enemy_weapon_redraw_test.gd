extends SceneTree
## Actual Canvas draw notifications distinguish retained commands from stale
## shots/charges. Aim and recoil still use the real articulated scene nodes.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const MotionPose := preload("res://scripts/enemy_motion_pose.gd")
var checks := 0
var failures := 0
var draw_counts: Dictionary = {}

class Target extends Node2D:
	func attack_point() -> Vector2: return global_position

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func observe(part: CanvasItem) -> void:
	var id := part.get_instance_id()
	draw_counts[id] = 0
	part.draw.connect(func(): draw_counts[id] = int(draw_counts[id]) + 1)

func draws(part: CanvasItem) -> int: return int(draw_counts.get(part.get_instance_id(), 0))

func flush_canvas() -> void:
	# process_frame precedes Canvas redraw; two turns observe the completed draw
	# on both the headless backend and the Compatibility renderer.
	await process_frame
	await process_frame

func make_machine(world: Node2D, kind: String, target: Node2D) -> SiegeMachine:
	var machine: SiegeMachine = load("res://scenes/boss_enemy.tscn" if kind == "boss" else "res://scenes/enemy.tscn").instantiate()
	machine.kind = "siege" if kind == "boss" else kind
	machine.position = Vector2(500, 430)
	world.add_child(machine)
	machine.target = target
	freeze(machine)
	machine.motion.automatic = false
	observe(machine.weapon_part)
	return machine

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var target := Target.new()
	world.add_child(target)
	target.position = Vector2(200, 370)
	for kind: String in ["runner", "strider", "breaker", "assault", "colossus", "siege", "shield_guard", "repair_crawler", "boss"]:
		var machine := make_machine(world, kind, target)
		var hitbox: RectangleShape2D = machine.get_node("MachineHitbox").shape
		var hitbox_size := hitbox.size
		var hp := machine.hp
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 1, kind + " draws its initial actual gun")
		var initial := machine.weapon_part.transform
		for step in 12:
			machine.age += 1.0 / 60.0
			machine.gait += .31
			machine.moving = true
			machine.weapon_recoil = float(step % 4)
			target.position = Vector2(170, 340 + step * 5)
			machine.motion.play("scan", true)
			machine.motion._process(1.0 / 60.0)
			machine.request_weapon_redraw()
			await flush_canvas()
		check(draws(machine.weapon_part) == 1, kind + " retains commands through physics-style and presentation requests")
		check(machine.weapon_part.transform != initial, kind + " still animates aim, gait, recoil and mechanical pose")
		check(hitbox.size == hitbox_size and machine.hp == hp, kind + " preserves hitbox and health")
		machine.muzzle_flash = .06
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 2, kind + " draws the shot flash immediately")
		machine.muzzle_flash = .02
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 2, kind + " retains identical flash geometry while its timer decreases")
		machine.muzzle_flash = 0.0
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 3, kind + " clears expired shot geometry")
		if machine.chassis_kind() == "siege":
			machine.windup = float(machine.profile.windup) * .25
			machine.request_weapon_redraw()
			await flush_canvas()
			check(draws(machine.weapon_part) == 4, kind + " refreshes the actual charge colour")
			machine.profile.windup = float(machine.profile.windup) * .5
			machine.request_weapon_redraw()
			await flush_canvas()
			check(draws(machine.weapon_part) == 5, kind + " invalidates charge when its duration changes")
			machine.windup = float(machine.profile.windup) * 2.0
			machine.request_weapon_redraw()
			await flush_canvas()
			machine.windup *= 2.0
			machine.request_weapon_redraw()
			await flush_canvas()
			check(draws(machine.weapon_part) == 6, kind + " retains an unchanged saturated charge")
		var before := draws(machine.weapon_part)
		machine.profile.chassis = "runner" if machine.chassis_kind() == "siege" else "siege"
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == before + 1, kind + " invalidates changed chassis geometry")
		before = draws(machine.weapon_part)
		machine.weapon_part.hide()
		machine.muzzle_flash = .06
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == before, kind + " does not mark hidden commands as rendered")
		machine.weapon_part.show()
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == before + 1, kind + " refreshes a shot queued while hidden")
		machine.weapon_part.free()
		machine.weapon_part = machine._create_part("ReplacementWeapon", machine._draw_weapon)
		observe(machine.weapon_part)
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 1, kind + " draws replacement CanvasItems even for unchanged geometry")
		machine.request_weapon_redraw()
		await flush_canvas()
		check(draws(machine.weapon_part) == 1, kind + " retains the replacement after its actual initial draw")
		machine.free()
	for kind: String in ["scout_car", "mortar_carrier", "battle_tank", "lancer", "sniper", "demolisher", "bastion"]:
		var machine := make_machine(world, kind, target)
		machine.request_weapon_redraw()
		await flush_canvas()
		var before := draws(machine.weapon_part)
		for step in 4:
			machine.age += .031
			machine.motion.pose = MotionPose.sample("service", float(step) / 5.0, kind, false)
			machine.request_weapon_redraw()
			await flush_canvas()
		check(draws(machine.weapon_part) == before + 4, kind + " preserves every dynamic weapon refresh")
		machine.free()
	check(await Cleanup.free_scene(world, self), "Drawing delegates, materials and observers free cleanly")
	print("ENEMY WEAPON REDRAW: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
