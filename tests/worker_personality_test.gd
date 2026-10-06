extends SceneTree
## Verify authored motion independently from palette, plus the gameplay anchors
## that must remain exact when a worker changes identity at runtime.

const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const IdleClock := preload("res://scripts/worker_idle_clock.gd")
const WeatherGeometry := preload("res://scripts/actor_weather_geometry.gd")
const IDS := ["mara","branko","ivo"]
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _point(value: Array) -> Vector2:
	return Vector2(value[0],value[1])

func _trajectory(id: String,state: String) -> Array:
	var result: Array = []
	var frames: Array = Personality.frames(id)[state]
	var first: Dictionary = frames[0]
	for pose: Dictionary in frames:
		# Subtract the initial configuration: a wider coat or a different fixed
		# stance cannot pass this check without genuinely different movement.
		result.append(_point(pose.hip)-_point(first.hip))
		result.append(_point(pose.shoulder)-_point(first.shoulder))
		result.append(float(pose.head)-float(first.head))
		for limb in ["hands","feet"]:
			for index in 2:
				result.append(_point(pose[limb][index])-_point(first[limb][index]))
	return result

func _run() -> void:
	InputSetup.install()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/worker_frames.json"))
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_visuals.json"))
	for id in IDS:
		var frames := Personality.frames(id)
		var count := 0
		check(frames.size()==19,"%s preserves 19 gameplay states"%id)
		for state in frames:
			count += frames[state].size()
			check(frames[state].size()==int(metadata.states[state].frames),"%s %s preserves frame count"%[id,state])
			for index in frames[state].size():
				check(_point(frames[state][index].item)==_point(metadata.states[state].item_anchors[index]),"%s %s:%d keeps cargo anchor"%[id,state,index])
		check(count==110,"%s preserves 110 native poses"%id)
		check(is_equal_approx(float(profiles.motion_profiles[id].walk_rate),Personality.playback_rate(id,"walk")),"%s authoring and runtime cadence agree"%id)
		for pose in ["mine","crouch_mine","climb","weapon","turret"]:
			check(Personality.playback_rate(id,pose)==1.0,"%s %s retains functional timing"%[id,pose])
		for frame in 8:
			check(frames.climb[frame].feet==metadata.states.climb.feet[frame] and frames.climb[frame].hands==metadata.states.climb.hands[frame],"%s climbing contacts follow world rungs at frame %d"%[id,frame])
	for state in ["idle","walk","carry_walk","jump_up","fall","land","mine","work","crouch_walk"]:
		for pair in [["mara","branko"],["mara","ivo"],["branko","ivo"]]:
			check(_trajectory(pair[0],state)!=_trajectory(pair[1],state),"%s: %s / %s differ in joint movement after removing initial pose"%[state,pair[0],pair[1]])
	for state in ["mine","crouch_mine"]:
		var contact := Personality.frame("mara",state,3)
		for id in IDS:
			var pose := Personality.frame(id,state,3)
			check(pose.tool==contact.tool and pose.hands==contact.hands,"%s %s retains exact strike endpoint and two-hand grip"%[id,state])
	for state in ["carry_idle","carry_walk","pickup","drop","work","weapon","weapon_up","weapon_down","turret"]:
		for index in Personality.frames("mara")[state].size():
			var hands: Array = Personality.frame("mara",state,index).hands
			check(hands==Personality.frame("branko",state,index).hands and hands==Personality.frame("ivo",state,index).hands,"%s:%d has identical functional cargo/weapon grips"%[state,index])
	var all_gestures: Dictionary = {}
	for id in IDS:
		var kinds := Personality.gestures(id)
		check(kinds.size()==6,"%s has six exclusive idle gestures"%id)
		var clock := IdleClock.new()
		clock.configure(719,id)
		var observed: Array[String] = []
		for cycle in 8:
			clock.wait_remaining = 0
			clock.tick(0.1,true)
			check(kinds.has(clock.gesture),"%s idle bag uses its own gestures"%id)
			check(observed.is_empty() or observed[-1]!=clock.gesture,"%s gestures never repeat immediately"%id)
			observed.append(clock.gesture)
			clock.tick(clock.duration()+0.1,true)
		check(kinds.all(func(kind):return observed.has(kind)),"%s visits every idle gesture"%id)
		for kind in kinds:
			check(not all_gestures.has(kind),"%s belongs to only one character"%kind)
			all_gestures[kind] = true
			var base := Personality.stance(PoseArt.neutral(),id)
			for phase in [0.0,1.0]:
				var pose := PoseArt.sample(kind,phase,0,Vector2(24,-13),id)
				check(pose.hip==base.hip and pose.shoulder==base.shoulder and pose.hands==base.hands and pose.feet==base.feet,"%s returns smoothly to its own standing stance"%kind)
			var center := PoseArt.sample(kind,0.5,0,Vector2(24,-13),id)
			check(center.hands!=base.hands,"%s visibly articulates its hands"%kind)
			check(center.feet==base.feet,"%s keeps both boots planted"%kind)
			for step in 61:
				var pose := PoseArt.sample(kind,step/60.0,0,Vector2(24,-13),id)
				var body := PoseArt.torso_transform(pose)
				check(pose.hands.size()==2 and pose.feet.size()==2 and pose.hands[0].distance_to(body*Vector2(-6,0))<=23.0 and pose.hands[1].distance_to(body*Vector2(3,0))<=23.0,"%s step %d keeps two connected, finite arms"%[kind,step])
		clock.begin(kinds[0])
		clock.tick(0.01,false)
		check(clock.gesture.is_empty(),"%s gesture interrupts immediately when gameplay resumes"%id)
	await _runtime_checks()
	print("WORKER PERSONALITY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _runtime_checks() -> void:
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
	var rates: Dictionary = {}
	for id in IDS:
		worker.configure_character(id)
		worker.velocity = Vector2(160,0)
		var before_hp := worker.hp
		var before_speed := worker.movement_multiplier()
		visual._process(0)
		visual._step = 0
		visual._process(0.4)
		rates[id] = visual._step
		check(visual.idle_clock.character_id==id,"%s runtime switch updates its gesture bag"%id)
		check(visual._equipment_anchors==Personality.frames(id),"%s armor follows its actual animated shoulders"%id)
		check(worker.hp==before_hp and worker.movement_multiplier()==before_speed and worker.velocity==Vector2(160,0),"%s presentation preserves health and movement"%id)
		for frame in 8:
			worker.position.x+=160.0/60.0
			visual._process(1.0/60.0)
			var feet := WeatherGeometry.worker_feet(visual)
			check(feet==[visual.pose_skeleton.feet[0],visual.pose_skeleton.feet[1]],"%s frame %d rain and foot splashes track rendered continuous boots"%[id,frame])
		worker.velocity = Vector2.ZERO
		visual._process(0)
		visual.idle_clock.begin(Personality.gestures(id)[0])
		visual.idle_clock.elapsed = visual.idle_clock.duration()*0.5
		visual._process(0)
		check(visual.special_pose==Personality.gestures(id)[0] and not visual.pose_skeleton.is_empty(),"%s runtime draws its own long gesture"%id)
		worker.velocity.x = 160
		visual._process(0.01)
		check(visual.special_pose.is_empty(),"%s walking interrupts its long gesture immediately"%id)
	check(rates.branko<rates.mara and rates.mara<rates.ivo,"Equal movement speed still gives three deliberate presentation cadences")
	await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
