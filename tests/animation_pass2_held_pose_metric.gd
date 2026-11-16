extends SceneTree
## Measurement, not a regression: samples the drawn joints of the named
## sequences at 30 Hz and reports the longest stretch in which every joint
## stayed within 0.75 px of where the stretch began (a held pose), and the
## mean joint travel per sample.
## "old" uses the presentation the pass replaced (the HEAD rig for workers,
## the combat pose and the pass-1 collapse for infantry); "new" the current.
## Usage: godot --headless --path . --script tests/animation_pass2_held_pose_metric.gd -- --no-profile-save --no-upnp [--old=res://tests/_tmp_old_worker_locomotion.gd]
const NewRig := preload("res://scripts/worker_locomotion.gd")
const Infantry := preload("res://scripts/ground_infantry_art.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const STEP := 1.0/30.0
const HELD := 0.75
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class Stage extends Node2D:
	var weather := WeatherProbe.new()
	var stats := {}
	func fx(_at: Vector2, _color: Color, _count: int = 0) -> void: pass
	func spawn_pickup(_kind: String, _amount: int, _at: Vector2) -> void: pass
	func sound(_name: String, _at: Variant = null, _gain: Variant = null) -> void: pass
var results: Array[String] = []

func _initialize() -> void: call_deferred("run")

static func joints(pose: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array([pose.hip,pose.shoulder,pose.feet[0],pose.feet[1],pose.hands[0],pose.hands[1]])
	result.append(Vector2(float(pose.head_tilt)*15.0,0))
	if pose.has("cargo"): result.append(pose.cargo)
	return result

static func measure(samples: Array) -> Dictionary:
	# A held stretch: every joint stays within HELD px of where the stretch
	# began, so slow continuous motion (breathing) does not count as held.
	var best := 0
	var anchor := 0
	var total := 0.0
	for index in range(1,samples.size()):
		var a: PackedVector2Array = samples[index-1]
		var b: PackedVector2Array = samples[index]
		var moved := 0.0
		for joint in mini(a.size(),b.size()): moved = maxf(moved,a[joint].distance_to(b[joint]))
		total += moved
		var first: PackedVector2Array = samples[anchor]
		var drift := 0.0
		for joint in mini(first.size(),b.size()): drift = maxf(drift,first[joint].distance_to(b[joint]))
		if drift>=HELD: anchor = index
		best = maxi(best,index-anchor)
	return {"held":best,"mean":total/maxf(1,samples.size()-1)}

func report(label: String, old: Array, new: Array, extra: String = "") -> void:
	var a := measure(old)
	var b := measure(new)
	var line := "%-30s old: longest held %2d samples (%.2fs), mean joint travel %.2f px | new: longest held %2d (%.2fs), mean %.2f px %s" % [label,a.held,a.held*STEP,a.mean,b.held,b.held*STEP,b.mean,extra]
	results.append(line)
	print(line)

func run() -> void:
	var old_path := "res://tests/_tmp_old_worker_locomotion.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--old="): old_path = argument.trim_prefix("--old=")
	var OldRig: GDScript = load(old_path) if ResourceLoader.exists(old_path) else null
	var world := Node2D.new()
	root.add_child(world)
	var actor := Worker.new()
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.configure_character("mara")
	if OldRig != null: _workers(actor,OldRig)
	_dance()
	await _infantry()
	print("HELD POSE METRIC: %d sequences" % results.size())
	world.queue_free()
	await process_frame
	quit(0)

func _rigs(OldRig: GDScript) -> Array:
	return [OldRig.new(),NewRig.new()]

func _workers(actor: Worker, OldRig: GDScript) -> void:
	# Idle stance, 3 s.
	var rigs := _rigs(OldRig)
	var tracks: Array = [[],[]]
	actor.velocity = Vector2.ZERO
	for frame in 90:
		for index in 2: tracks[index].append(joints(rigs[index].advance(actor,"idle",STEP)))
	report("worker idle 3 s",tracks[0],tracks[1])
	# Ladder: 1 s at full climbing speed; leg extension range shows the squat.
	rigs = _rigs(OldRig)
	tracks = [[],[]]
	var reach: Array = [Vector2(INF,-INF),Vector2(INF,-INF)]
	actor.climbing = true
	actor._ladder = Rect2(0,0,40,400)
	actor.position = Vector2(0,300)
	for frame in 30:
		actor.position.y -= Balance.CLIMB_SPEED*STEP
		for index in 2:
			var pose: Dictionary = rigs[index].advance(actor,"climb",STEP)
			tracks[index].append(joints(pose))
			for foot in 2:
				var drop: float = Vector2(pose.feet[foot]).y-Vector2(pose.hip).y
				reach[index] = Vector2(minf(reach[index].x,drop),maxf(reach[index].y,drop))
	actor.climbing = false
	report("worker ladder 1 s",tracks[0],tracks[1],"(hip-to-boot drop old %.0f..%.0f px, new %.0f..%.0f px; leg length 24)" % [reach[0].x,reach[0].y,reach[1].x,reach[1].y])
	# Running jump: take-off to touchdown (0.71 s).
	rigs = _rigs(OldRig)
	tracks = [[],[]]
	actor._airborne = true
	for frame in 22:
		actor.velocity = Vector2(190,-390.0+1100.0*frame*STEP)
		for index in 2: tracks[index].append(joints(rigs[index].advance(actor,"jump_up" if actor.velocity.y<0 else "fall",STEP)))
	actor._airborne = false
	actor.velocity = Vector2.ZERO
	report("worker running jump 0.7 s",tracks[0],tracks[1])
	# Carrying a full load at walking speed, 2 s: the load's vertical travel.
	rigs = _rigs(OldRig)
	tracks = [[],[]]
	var load_range: Array = [Vector2(INF,-INF),Vector2(INF,-INF)]
	actor.inventory = {"steel":4}
	actor.selected_kind = "steel"
	actor.velocity = Vector2(105,0)
	for frame in 60:
		actor.position.x += 105.0*STEP
		for index in 2:
			var pose: Dictionary = rigs[index].advance(actor,"carry_walk",STEP)
			tracks[index].append(joints(pose))
			var shoulder_relative: float = Vector2(pose.cargo).y
			load_range[index] = Vector2(minf(load_range[index].x,shoulder_relative),maxf(load_range[index].y,shoulder_relative))
	actor.inventory.clear()
	actor.selected_kind = ""
	actor.velocity = Vector2.ZERO
	report("worker carry walk 2 s",tracks[0],tracks[1],"(load bob old %.1f px, new %.1f px)" % [load_range[0].y-load_range[0].x,load_range[1].y-load_range[1].x])
	# A hit while standing: hurt timer and knockback as Worker.take_damage sets them.
	rigs = _rigs(OldRig)
	tracks = [[],[]]
	for frame in 18:
		actor.hurt_flash = maxf(0.0,0.22-frame*STEP)
		actor.knockback = move_toward(105.0,0.0,frame*STEP*470.0)
		for index in 2: tracks[index].append(joints(rigs[index].advance(actor,"idle",STEP)))
	actor.hurt_flash = 0.0
	actor.knockback = 0.0
	report("worker hit while standing 0.6 s",tracks[0],tracks[1],"(old rig had no hit pose; the sprite tilted rigidly)")

func _dance() -> void:
	# A standing repertoire step over four beats: authored path alone versus
	# with the whole-body groove layered on.
	var old: Array = []
	var new: Array = []
	for frame in 60:
		var beats := 8.0+frame*STEP*2.0
		var authored := Rhythm.choreography("mara_box_glide",beats,"mara",1.0)
		old.append(joints(authored))
		var grooved: Dictionary = authored.duplicate(true)
		Rhythm._apply_groove(grooved,beats,1.0,"mara_box_glide")
		new.append(joints(grooved))
	report("dance mara_box_glide 2 s",old,new)

func _infantry() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var soldier = load("res://scenes/ground_infantry.tscn").instantiate()
	soldier.kind = "grenadier"
	soldier.game = stage
	soldier.show_status_labels = false
	soldier.attack_direction = -1.0
	soldier.position = Vector2(600,400)
	stage.add_child(soldier)
	soldier.set_physics_process(false)
	soldier.set_process(false)
	soldier.motion.set_process(false)
	soldier.infantry.set_process(false)
	var aim := Node2D.new()
	aim.position = soldier.position+Vector2(-300,0)
	stage.add_child(aim)
	soldier.target = aim
	soldier.moving = false
	soldier.stance = 1.0
	var profile: Dictionary = soldier.profile
	var old: Array = []
	var new: Array = []
	var walk_old: Array = []
	var walk_new: Array = []
	var fired := false
	# Wind-up, release, reload and wait: 4.5 s of one attack cycle.
	for tick in int(4.5/STEP):
		soldier.age += STEP
		soldier.muzzle_flash = maxf(0,soldier.muzzle_flash-STEP)
		soldier.attack_clock = maxf(0,soldier.attack_clock-STEP)
		soldier.weapon_recoil = move_toward(soldier.weapon_recoil,0,STEP*24)
		if not fired:
			soldier.windup += STEP
			if soldier.windup>=float(profile.windup):
				fired = true
				soldier.windup = 0
				soldier.attack_count += 1
				soldier.attack_clock = float(profile.cooldown)
				soldier.weapon_recoil = 5.0
				soldier.muzzle_flash = 0.13
		soldier._pose_parts()
		soldier.infantry.compose(STEP)
		old.append(joints(soldier.infantry.pose)+PackedVector2Array([soldier.infantry.gun*Vector2(30,0)]))
		new.append(joints(soldier.infantry.shown)+PackedVector2Array([soldier.infantry.shown_gun*Vector2(30,0)]))
	report("grenadier attack cycle 4.5 s",old,new,"(includes the launcher muzzle)")
	if OS.get_cmdline_user_args().has("--trace"):
		for index in range(1,new.size()):
			var a: PackedVector2Array = new[index-1]
			var b: PackedVector2Array = new[index]
			var moved := 0.0
			for joint in a.size(): moved = maxf(moved,a[joint].distance_to(b[joint]))
			print("trace %d %.3f" % [index,moved])
	# Marching 2 s.
	soldier.moving = true
	soldier.stance = 0.0
	soldier.locomotion_speed = soldier.move_speed
	for tick in 60:
		soldier.gait += STEP*float(profile.gait)
		soldier._pose_parts()
		soldier.infantry.compose(STEP)
		walk_old.append(joints(soldier.infantry.pose))
		walk_new.append(joints(soldier.infantry.shown))
	report("grenadier march 2 s",walk_old,walk_new)
	# Defeat: the pass-1 single rotation versus the staged collapse.
	var start: Dictionary = soldier.infantry.shown.duplicate(true)
	old = []
	new = []
	for tick in 30:
		var age := tick*STEP
		old.append(joints(_pass1_fall(start,age)))
		new.append(joints(Infantry.fall_pose(start,age)))
	report("infantry collapse 1 s",old,new)
	stage.queue_free()
	await process_frame

static func _pass1_fall(start: Dictionary, age: float) -> Dictionary:
	# The pass-1 collapse (one spine rotation about the hip), kept here for comparison.
	var lying := WorkerPoseArt.sample("downed",1.0)
	var result := start.duplicate(true)
	var jolt := 1.0-pow(1.0-clampf(age/0.13,0,1),2.0)
	var drop := clampf((age-0.13)/(0.58-0.13),0,1)
	drop *= drop
	var since := age-0.58
	var settle := -sin(since*24.0)*exp(-since*11.0)*1.8 if since>0 else 0.0
	var start_spine: Vector2 = Vector2(start.shoulder)-Vector2(start.hip)
	var lying_spine: Vector2 = Vector2(lying.shoulder)-Vector2(lying.hip)
	var angle := lerp_angle(start_spine.angle()-0.22*jolt,lying_spine.angle(),drop)
	var length := lerpf(start_spine.length(),lying_spine.length(),drop)
	result.hip = (Vector2(start.hip)+Vector2(-2.0*jolt,0)).lerp(lying.hip,drop)+Vector2(0,settle*0.5)
	result.shoulder = Vector2(result.hip)+Vector2.from_angle(angle)*length+Vector2(0,settle*0.5)
	var legs := clampf(drop*1.5,0,1)
	var arms := drop*drop
	for index in 2:
		result.feet[index] = Vector2(start.feet[index]).lerp(lying.feet[index],legs)
		var flung: Vector2 = Vector2(start.hands[index])+Vector2(-4,-7 if index==0 else -4)*jolt
		result.hands[index] = flung.lerp(lying.hands[index],arms)+Vector2(0,settle)
	result.head_tilt = lerpf(float(start.head_tilt)-0.30*jolt,float(lying.head_tilt),drop)
	return result
