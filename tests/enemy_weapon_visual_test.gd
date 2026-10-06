extends SceneTree
## Real articulated scene transforms: wrapped aiming, per-variant muzzle and recoil.
class Target extends Node2D:
	func attack_point() -> Vector2: return global_position
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func run():
	var world := Node2D.new()
	root.add_child(world)
	var target := Target.new()
	world.add_child(target)
	var worker_target := Node2D.new()
	world.add_child(worker_target)
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(kind): continue # Human weapon transforms have their own rig checks.
		var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
		machine.kind=kind
		machine.position=Vector2(650,430)
		world.add_child(machine)
		machine.set_physics_process(false)
		machine.target=target
		machine.gait=0
		for offset in [Vector2(-300,-60),Vector2(-300,0),Vector2(-300,95)]:
			machine._pose_parts()
			target.global_position=machine.weapon_part.global_position+offset
			machine._pose_parts()
			var tip: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
			var target_direction: Vector2=(tip-machine.weapon_part.global_position).normalized()
			var expected: Vector2=machine.abilities.launch_velocity(tip,target.global_position).normalized() if kind=="mortar_carrier" else offset.normalized()
			check(target_direction.dot(expected)>0.9999,"%s points along its actual launch path to the %s target" % [kind,"upper" if offset.y<0 else ("lower" if offset.y>0 else "level")])
		machine.scale=Vector2.ONE*2.0
		machine._pose_parts()
		var offset:=Vector2(-300,-60)
		target.global_position=machine.weapon_part.global_position+offset
		machine._pose_parts()
		var direction: Vector2=(machine.weapon_part.to_global(machine.weapon_muzzle())-machine.weapon_part.global_position).normalized()
		var scaled_expected: Vector2=machine.abilities.launch_velocity(machine.weapon_part.to_global(machine.weapon_muzzle()),target.global_position).normalized() if kind=="mortar_carrier" else offset.normalized()
		check(direction.dot(scaled_expected)>0.9999,"%s retains correct aim under scaled parents" % kind)
		if GroundVariantVisual.has_special_weapon(kind):
			target.global_position=machine.weapon_part.global_position+Vector2(-400,0)
			machine._pose_parts()
			var before: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
			machine.weapon_recoil=5
			machine._pose_parts()
			var displacement: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())-before
			check(displacement.distance_to(Vector2(10,0))<0.01,"%s barrel and shared flash muzzle recoil once, together" % kind)
			machine.weapon_recoil=0
			if kind=="lancer":
				var resting: Vector2=machine.weapon_muzzle()
				machine.abilities.rush_time=1
				check(machine.weapon_muzzle().x<resting.x-9,"Lance tip and strike flash follow real rush extension")
			if kind=="demolisher":
				var resting: Vector2=machine.weapon_muzzle()
				machine.windup=float(machine.profile.windup)
				check(machine.weapon_muzzle().x>resting.x+9,"Hammer retracts during actual windup, sharing its strike anchor")
		if kind=="sniper":
			machine.worker_target=worker_target
			machine.worker_windup=0.7
			machine._pose_parts()
			worker_target.global_position=machine.weapon_part.global_position+Vector2(-300,-40)+Vector2(0,23)
			target.global_position=machine.weapon_part.global_position+Vector2(-300,70)
			machine._pose_parts()
			direction=(machine.weapon_part.to_global(machine.weapon_muzzle())-machine.weapon_part.global_position).normalized()
			check(direction.y<0,"Sniper barrel follows its active worker target instead of the wall")
			machine.tracer_end=machine.to_local(worker_target.global_position-Vector2(0,23))
			machine.worker_windup=0
			machine.muzzle_flash=0.08
			machine._pose_parts()
			direction=(machine.weapon_part.to_global(machine.weapon_muzzle())-machine.weapon_part.global_position).normalized()
			check(direction.y<0,"Finished worker shot keeps its actual impact aim throughout the muzzle flash")
		machine.free()
	world.free()
	await process_frame
	print("ENEMY WEAPON VISUAL: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
