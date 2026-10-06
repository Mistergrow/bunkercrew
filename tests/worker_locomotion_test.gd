extends SceneTree
## Exercise actual rig integration, continuous contacts, world rung grips,
## carrying, recoil and variable render rates without saving player progress.

const Rig := preload("res://scripts/worker_locomotion.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Geometry := preload("res://scripts/actor_weather_geometry.gd")
const IDS := ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func _anatomy(pose: Dictionary, label: String) -> void:
	check(pose.feet.size()==2 and pose.hands.size()==2, label+" has exactly four limbs")
	var body := PoseArt.torso_transform(pose)
	for index in 2:
		var hand: Vector2 = pose.hands[index]
		var foot: Vector2 = pose.feet[index]
		check(hand.is_finite() and foot.is_finite(), label+" has finite anchors")
		if not bool(pose.get("back", false)):
			check(hand.distance_to(body*Vector2(-6 if index==0 else 3, 0))<=23.0, label+" keeps arm connected")
			var spread := float(pose.get("hip_spread",4.0))
			check(foot.distance_to(Vector2(pose.hip)+Vector2(-spread if index==0 else spread, 0))<=24.05, label+" keeps leg connected")

func _run() -> void:
	InputSetup.install()
	var world := Node2D.new()
	root.add_child(world)
	var actor := Worker.new()
	world.add_child(actor)
	actor.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name="PixelVisual"
	actor.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual.idle_clock.wait_remaining=1000
	var signatures: Array = []
	for id in IDS:
		actor.configure_character(id)
		actor.inventory.clear()
		actor.velocity=Vector2.ZERO
		actor._airborne=false
		actor._landing_time=0
		actor.climbing=false
		visual.crouched=false
		visual._process(1.0/60.0)
		var signature: Array = []
		for action in ["walk", "run", "crouch", "carry", "stop"]:
			actor.velocity.x=80 if action=="walk" else (190 if action=="run" else (95 if action=="crouch" else (105 if action=="carry" else 0)))
			visual.crouched=action=="crouch"
			actor.inventory={"ore":1} if action=="carry" else {}
			actor.selected_kind="ore" if action=="carry" else ""
			var previous: Dictionary = visual.pose_skeleton.duplicate(true)
			var previous_world := Vector2.INF
			var subframes: Array[float] = []
			var had_contact := false
			for frame in 120:
				actor.position.x+=actor.velocity.x/60.0
				visual._process(1.0/60.0)
				var pose: Dictionary = visual.pose_skeleton
				check(visual.has_articulated_pose() and not visual.locomotion_pose.is_empty(), id+" "+action+" renders continuous rig")
				_anatomy(pose, id+" "+action)
				check(Geometry.worker_feet(visual)==[pose.feet[0], pose.feet[1]], id+" effects use the drawn boots")
				if frame>12:
					check(pose.hip.distance_to(previous.hip)<3.0 and pose.shoulder.distance_to(previous.shoulder)<3.0, id+" "+action+" torso has no pose jump (frame %d, hip %.3f px, shoulder %.3f px)"%[frame,pose.hip.distance_to(previous.hip),pose.shoulder.distance_to(previous.shoulder)])
					for index in 2: check(pose.feet[index].distance_to(previous.feet[index])<8.0, id+" "+action+" feet move continuously")
				if action in ["walk", "run", "crouch"]:
					var sole: Vector2 = pose.feet[1]
					var world_foot: Vector2 = actor.position+sole
					if frame>80 and is_equal_approx(sole.y, -3.0) and is_equal_approx(float(previous.feet[1].y), -3.0) and previous_world!=Vector2.INF:
						check(absf(world_foot.x-previous_world.x)<0.02, id+" "+action+" planted boot stays in world space")
						had_contact=true
					previous_world=world_foot
					if frame in range(60, 90): subframes.append(sole.x)
				if action=="carry":
					check(pose.has("cargo") and pose.hands[0]==pose.cargo+Vector2(-7, 0) and pose.hands[1]==pose.cargo+Vector2(5, 3), id+" cargo has two exact grips")
				previous=pose.duplicate(true)
			if action in ["walk", "run", "crouch"]:
				check(had_contact, id+" "+action+" has a planted phase")
				var unique: Dictionary = {}
				for x in subframes: unique[x]=true
				check(unique.size()>24, id+" "+action+" advances on render subframes instead of holding eight atlas frames")
				signature.append([previous.hip, previous.hands, visual.locomotion.phase])
			if action=="run": check(visual.locomotion.kind=="run", id+" high speed uses a run gait")
			if action=="crouch": check(previous.shoulder.y>-35.0, id+" bends under low ceilings")
			if action=="stop": check(previous.feet[0].y<-2.99 and previous.feet[0].y>-3.01 and visual.locomotion.kind=="idle", id+" stop settles without skating")
		visual.crouched=true
		visual.ceiling_height=43
		actor.velocity.x=95
		for frame in 60:
			actor.position.x+=95.0/60.0
			visual._process(1.0/60.0)
			_anatomy(visual.pose_skeleton, id+" crawl")
		check(visual.locomotion.kind=="crawl" and visual.pose_skeleton.shoulder.y>-22 and visual.pose_skeleton.shoulder.x>visual.pose_skeleton.hip.x+12, id+" very low tunnels use actual hands-and-knees crawl")
		visual.crouched=false
		visual.ceiling_height=128
		signatures.append(signature)
		actor._airborne=true
		actor.velocity=Vector2(130, -390)
		visual._process(0.2)
		var rising: Dictionary = visual.pose_skeleton.duplicate(true)
		actor.velocity.y=200
		visual._process(0.2)
		check(visual.pose_name=="fall" and rising.feet!=visual.pose_skeleton.feet, id+" jump evolves from tuck to fall")
		actor._airborne=false
		actor.velocity=Vector2.ZERO
		actor._landing_time=0.15
		visual._process(0.13)
		check(visual.pose_skeleton.hip.y>-20 and visual.pose_skeleton.feet[0].y==-3, id+" landing absorbs weight on planted soles")
		actor._landing_time=0
		actor.climbing=true
		actor._ladder=Rect2(0, 0, 40, 200)
		actor.position.y=15.0
		visual._process(0.2)
		var held: Dictionary = visual.pose_skeleton.duplicate(true)
		visual._process(0.5)
		check(visual.pose_skeleton==held, id+" stationary ladder freezes its continuous pose")
		var grip: Vector2 = actor.position+Vector2(held.hands[0])
		for frame in 28:
			actor.position.y-=0.75
			visual._process(1.0/120.0)
			check((actor.position+Vector2(visual.pose_skeleton.hands[0])).is_equal_approx(grip), id+" ascending hand remains on its actual rung")
		actor.position.y=15.0
		visual._process(0.01)
		check(visual.pose_skeleton==held and visual.sprite_facing()==1.0, id+" descending retraces the back-view pose")
		actor.climbing=false
	for first in signatures.size():
		for second in range(first+1, signatures.size()): check(signatures[first]!=signatures[second], "Crew identities have distinct locomotion")
	_rate_checks(actor)
	_weapon_checks(actor, visual)
	await _clearance_checks(actor,visual,world)
	visual.set_process(true)
	actor.velocity=Vector2(190,0)
	for frame in 3: await process_frame
	paused=true
	var held_phase: float=visual.locomotion.phase
	for frame in 4: await process_frame
	check(visual.locomotion.phase==held_phase,"Actual SceneTree pause freezes the locomotion clock")
	paused=false
	for frame in 3: await process_frame
	check(visual.locomotion.phase>held_phase,"Locomotion resumes after actual SceneTree pause")
	visual.set_process(false)
	await CLEANUP.free_scene(world, self)
	print("WORKER LOCOMOTION: %d checks, %d failures"%[checks, failures])
	quit(1 if failures else 0)

func _rate_checks(actor: Worker) -> void:
	actor.character_id="mara"
	actor.climbing=false
	actor.inventory.clear()
	actor.velocity=Vector2(160, 0)
	var end_phases: Array[float] = []
	for rate in [30, 60, 144]:
		var rig := Rig.new()
		actor.position=Vector2.ZERO
		rig.advance(actor, "walk", 0)
		for frame in rate*3:
			actor.position.x+=160.0/rate
			rig.advance(actor, "walk", 1.0/rate)
		end_phases.append(rig.phase)
	check(absf(end_phases[0]-end_phases[2])<0.10 and absf(end_phases[1]-end_phases[2])<0.05, "Distance gait remains consistent at 30, 60 and 144 render frames/s")
	var stopped_rig := Rig.new()
	stopped_rig.advance(actor, "walk", 0.3)
	var before := stopped_rig.phase
	actor.velocity=Vector2.ZERO
	for frame in 60: stopped_rig.advance(actor, "idle", 1.0/60.0)
	check(stopped_rig.phase==before, "Blocked or stationary movement never advances the gait")

func _weapon_checks(actor: Worker, visual: WorkerVisual) -> void:
	var weapon := WorkerWeapon.new()
	weapon.name="WorkerWeapon"
	actor.add_child(weapon)
	weapon.set_physics_process(false)
	weapon.aiming=true
	actor.velocity=Vector2(160, 0)
	for id in IDS:
		actor.character_id=id
		for crouched in [false, true]:
			visual.crouched=crouched
			for facing in [-1.0, 1.0]:
				actor.facing=facing
				for angle in [-0.9, 0.0, 0.8]:
					weapon.aim_direction=Vector2(cos(angle)*facing, sin(angle))
					weapon._update_origin()
					for recoil in [0.0, 4.0]:
						weapon.recoil=recoil
						actor.hurt_flash=0.11 if recoil>0 else 0.0
						visual._process(0.2)
						var pose: Dictionary = visual.pose_skeleton
						_anatomy(pose, id+" armed")
						var gun := Transform2D(weapon.aim_direction.angle(), weapon.global_position).scaled_local(Vector2(1, 1 if weapon.aim_direction.x>=0 else -1))
						var tx := Geometry.worker_transform(visual)
						for index in 2:
							var expected := gun*Vector2((-1 if index==0 else 15)-recoil, 1 if index==0 else -1)
							var actual := visual.to_global(tx*Vector2(pose.hands[index]))
							check(actual.distance_to(expected)<0.001, id+" running/low/aim/recoil hands stay on gun during damage flinch")
	actor.hurt_flash=0

func _clearance_checks(actor: Worker, visual: WorkerVisual, world: Node2D) -> void:
	actor.position=Vector2.ZERO
	actor.facing=1
	actor.velocity=Vector2(190,0)
	var ceiling := StaticBody2D.new()
	ceiling.collision_layer=1
	ceiling.position=Vector2(75,-47)
	var shape := CollisionShape2D.new()
	shape.shape=RectangleShape2D.new()
	shape.shape.size=Vector2(60,10)
	ceiling.add_child(shape)
	world.add_child(ceiling)
	for frame in 2: await physics_frame
	visual._clearance_time=0
	visual._physics_process(0.1)
	check(visual.crouched and visual.ceiling_height<49,"Actual forward roof probe prepares a low posture before entering the tunnel")
	actor.inventory.clear()
	actor.get_node("WorkerWeapon").aiming=false
	actor.get_node("WorkerWeapon").recoil=0
	for frame in 30: visual._process(1.0/60.0)
	check(visual.locomotion.kind=="crawl","Actual roof clearance selects crawl in the integrated visual")
	actor.position.x=150
	visual._clearance_time=0
	visual._physics_process(0.1)
	check(not visual.crouched,"Actual roof probe releases the low posture beyond the tunnel")
	ceiling.queue_free()
	await process_frame
