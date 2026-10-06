extends SceneTree
class Target extends StaticBody2D:
	var hp := 100.0
	func _ready():
		collision_layer = 2
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(20,80)
		shape.shape = box
		add_child(shape)
	func take_damage(value): hp -= value
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run():
	var world := Node2D.new()
	root.add_child(world)
	for group in ["walls","dome_segments","anti_air","field_defenses","vehicles","enemies"]:
		var target := Target.new()
		target.position = Vector2(500,500)
		world.add_child(target)
		target.add_to_group(group)
		var behind := Target.new()
		behind.position = Vector2(550,500)
		world.add_child(behind)
		behind.add_to_group("enemies")
		await physics_frame
		await physics_frame
		var shot := BunkerProjectile.new()
		shot.position = Vector2(450,500)
		world.add_child(shot)
		shot.set_physics_process(false)
		shot._physics_process(.1)
		check(target.hp==68 if group=="enemies" else target.hp==100,"Swept shot damages enemies and preserves "+group)
		check(behind.hp==100,"First solid contact blocks the target behind "+group)
		check(shot.is_queued_for_deletion(),"Blocked round retires exactly once")
		target.free()
		behind.free()
		await process_frame
	world.queue_free()
	await process_frame
	print("PROJECTILE FRIENDLY FIRE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
