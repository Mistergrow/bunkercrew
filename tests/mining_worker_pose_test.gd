extends SceneTree
const Pose := preload("res://scripts/mining_worker_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
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
	# Exercise the actual rig endpoints, including the outer side reach and the
	# top and bottom rows of a three-cell seam. A hidden hand clamp would detach
	# the glove from its shaft even though the tool still reached the rock.
	for identity in IDS:
		for crouched in [false, true]:
			for contact in [Vector2(34,-22),Vector2(72,-22),Vector2(34,-58),Vector2(0,-88),Vector2(34,14),Vector2(88,-22),Vector2(10,-96)]:
				var feet: Array = []
				var ready_tip := Vector2.ZERO
				for frame in 8:
					var pose := Pose._sample_local(contact, frame, crouched, identity)
					var tx := PoseArt.torso_transform(pose)
					if frame == 0:
						feet = pose.feet.duplicate()
						ready_tip = pose.tool_tip
					_check(pose.feet == feet, "Mining keeps both boots planted throughout the swing")
					_check(absf(Vector2(pose.tool_head).distance_to(pose.tool_butt) - Pose.HANDLE_LENGTH) < 0.001, "Pick shaft stays rigid across all targets and swing phases")
					for hand in 2:
						var shoulder := tx * Vector2(-6 if hand == 0 else 3, 0)
						_check(shoulder.distance_to(pose.hands[hand]) < 22.9, "Both visible gloves remain on their actual grips")
						_check(absf((Vector2(pose.hands[hand])-Vector2(pose.tool_head)).cross(pose.tool_axis)) < 0.001, "Both hands lie on the shaft")
					if frame == 3:
						_check(Vector2(pose.tool_tip).distance_to(contact) < 0.001, "The pick point reaches the exact surface on contact frame 3")
						_check(ready_tip.distance_to(contact) > 10, "Anticipation lifts the tool visibly clear of the target")
	# New render subframes retain a rigid tool and connected arms, including
	# the additional identities, mirrored/low stance and the held impact pose.
	for identity in IDS:
		for crouched in [false,true]:
			for contact in [Vector2(34,-22),Vector2(88,-22),Vector2(10,-96),Vector2(34,14)]:
				for frame in 8:
					for fraction in [0.0,0.25,0.5,0.75,0.99]:
						var pose := Pose._sample_local(contact,frame,crouched,identity,fraction)
						var tx := PoseArt.torso_transform(pose)
						_check(absf(Vector2(pose.tool_head).distance_to(pose.tool_butt)-Pose.HANDLE_LENGTH)<0.001,"Continuous pick subframes retain the rigid shaft")
						for hand in 2:
							_check(Vector2(pose.hands[hand]).distance_to(tx*Vector2(-6 if hand==0 else 3,0))<22.9,"Continuous pick subframes keep both arms connected")
						if frame==3: _check(Vector2(pose.tool_tip).distance_to(contact)<0.001,"The entire continuous contact frame remains on the exact surface")
	var world := Node2D.new()
	root.add_child(world)
	var worker := Worker.new()
	world.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	worker.mining = true
	var block := MineBlock.new()
	world.add_child(block)
	worker.focus = block
	for target in [Vector2(58,-22), Vector2(-58,-22), Vector2(58,-76), Vector2(-58,24)]:
		block.position = target
		await physics_frame
		for crouched in [false,true]:
			visual.crouched = crouched
			visual._process(0.0)
			visual._step = 3.0
			visual._process(0.0)
			var pose: Dictionary = visual.mining_pose
			_check(not pose.is_empty() and visual.has_articulated_pose(), "A live mine cell selects the target-relative rig")
			var actual := visual.to_global(ActorWeatherGeometry.worker_transform(visual) * Vector2(pose.tool_tip))
			_check(actual.distance_to(block._contact_from(worker.global_position+Vector2(0,-22))) < 0.001, "Live surface, mirrored drawing and impact share one contact position")
			_check(ActorWeatherGeometry.worker_feet(visual) == pose.feet, "Weather and footsteps follow the planted mining boots")
			var segments := ActorWeatherGeometry.segments(worker)
			_check(segments[-1].to.distance_to(actual) < 0.001, "Rain follows the new pick point instead of the baked atlas tool")
			worker.hurt_flash = 0.11
			_check((ActorWeatherGeometry.worker_transform(visual)*Vector2(pose.tool_tip)).is_equal_approx(Vector2(pose.tool_tip)*Vector2(pose.facing,1)), "Contact-bound hands stay on their tool during damage tint")
			worker.hurt_flash = 0.0
	# Depletion can free the target between physics and the visual process.
	# A stale reference must not be passed into the typed pose sampler.
	block.free()
	visual._process(0.0)
	_check(visual.mining_pose.is_empty(), "A freed mining target safely clears the pose in the same render frame")
	worker.focus = null
	visual._process(0.0)
	_check(visual.mining_pose.is_empty(), "Losing the target clears the previous surface pose")
	worker.mining = false
	visual._process(0.0)
	_check(visual.mining_pose.is_empty() and not visual.locomotion_pose.is_empty(), "Finishing mining restores continuous worker locomotion")
	await Cleanup.free_scene(world,self)
	print("MINING WORKER POSE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
