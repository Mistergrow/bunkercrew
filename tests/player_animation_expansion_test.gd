extends SceneTree
## Additional performances are exercised through real WorkerVisual state changes.
const Library := preload("res://scripts/worker_gesture_library.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Portraits := preload("res://scripts/character_select_panel.gd")
const IdleClock := preload("res://scripts/worker_idle_clock.gd")
const IDS := ["mara","branko","ivo"]

class RoundProbe extends Node:
	var phase := "build"
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class WorldProbe extends Node2D:
	var rounds := RoundProbe.new()
	var weather := WeatherProbe.new()
	func _ready() -> void:
		add_child(rounds)
class WeaponProbe extends Node2D:
	var aiming := false
	var flash := 0.0
	var recoil := 0.0
	var aim_direction := Vector2.RIGHT

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _reset(actor: Worker,visual: WorkerVisual,world: WorldProbe) -> void:
	actor.velocity = Vector2.ZERO
	actor.mining = false
	actor._interacting = false
	actor.focus = null
	actor.inventory.clear()
	actor.selected_kind = ""
	actor.climbing = false
	actor._airborne = false
	actor.hurt_flash = 0.0
	actor.hurt_stun = 0.0
	actor.hp = actor.max_hp
	actor.medical.state = "healthy"
	actor.medical.bleeding = 0
	actor.medical.fractured = false
	actor.medical.aid_target = null
	actor.medical.recovery_time = 0.0
	visual.crouched = false
	visual.idle_clock.cancel()
	visual.idle_clock.wait_remaining = 1000
	visual.expression_clock.reset()
	world.rounds.phase = "build"
	visual._process(0)

func _run() -> void:
	InputSetup.install()
	# Python's native rig uses (-dy, dx); verify anatomy against that contract.
	var elbow := PoseArt._joint(Vector2(3,-42),Vector2(9,-31),11,12,1)
	var knee := PoseArt._joint(Vector2(4,-25),Vector2(7,-3),12,12,-1)
	check(elbow.x<3 and elbow.y>-42,"Articulated elbow bends down/back like the authored native atlas")
	check(knee.x>7 and knee.y>-25,"Articulated knee bends forward like the authored native atlas")
	var totals := 0
	for id in IDS:
		var names := Library.names(id)
		totals += names.size()
		check(names.size()==6,"%s has six additional named performances"%id)
		check(Library.names(id,"idle").size()==4 and Library.names(id,"work_finished").size()==1 and Library.names(id,"wave_clear").size()==1,"%s has four idle and two contextual additions"%id)
		var base := Personality.stance(PoseArt.neutral(),id)
		for kind in names:
			check(not Personality.DURATIONS.has(kind),"%s is additional to all prior gestures"%kind)
			var previous := PoseArt.sample(kind,0,0,Vector2(24,-13),id)
			var differs := false
			for frame in 121:
				var phase := frame/120.0
				var pose := PoseArt.sample(kind,phase,0,Vector2(24,-13),id)
				var body := PoseArt.torso_transform(pose)
				check(pose.feet==base.feet,"%s:%d keeps both soles at their exact world contacts"%[kind,frame])
				check(pose.hands.size()==2 and pose.feet.size()==2,"%s:%d has exactly four limbs"%[kind,frame])
				for side in 2:
					check(pose.hands[side].distance_to(body*Vector2(-6 if side==0 else 3,0))<=23.0,"%s:%d arm %d remains connected"%[kind,frame,side])
					check(pose.hands[side].distance_to(previous.hands[side])<5.0,"%s:%d hand %d has no frame jump"%[kind,frame,side])
				check(pose.hip.distance_to(previous.hip)<3 and pose.shoulder.distance_to(previous.shoulder)<3,"%s:%d weight transfer is continuous"%[kind,frame])
				differs = differs or pose.hands!=base.hands or pose.shoulder!=base.shoulder
				if frame==0 or frame==120:
					check(pose.hands==base.hands and pose.hip==base.hip and pose.shoulder==base.shoulder and pose.prop=="","%s recovers its neutral stance and stows props"%kind)
				previous = pose
			check(differs,"%s actually moves"%kind)
	check(totals==18,"18 new performances across the three selectable characters")
	var clock := IdleClock.new()
	clock.configure(53,"mara")
	clock.tick(0.1,true)
	clock.configure(53,"mara")
	var expected_wait := clock.wait_remaining
	clock.tick(0.1,false)
	check(clock.wait_remaining==expected_wait,"Reconfiguring an allowed idle clock clears old eligibility instead of rerolling its new seed")
	_portrait_checks()
	var world := WorldProbe.new()
	root.add_child(world)
	var actor := Worker.new()
	actor.game = world
	world.add_child(actor)
	actor.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	actor.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	for id in IDS:
		actor.configure_character(id)
		visual._process(0)
		for kind in Library.names(id):
			_reset(actor,visual,world)
			visual.idle_clock.begin(kind)
			visual._process(0.3)
			check(visual.special_pose==kind and not visual.pose_skeleton.is_empty(),"%s renders through the actual worker"%kind)
			var original_hp := actor.hp
			var original_speed := actor.movement_multiplier()
			visual._process(0.1)
			check(actor.hp==original_hp and actor.movement_multiplier()==original_speed,"%s does not modify health or speed"%kind)
			actor.velocity.x = 100
			visual._process(0.01)
			check(visual.special_pose.is_empty() and visual.pose_name=="walk","%s yields to locomotion in the same frame"%kind)
			_reset(actor,visual,world)
			var enemy := Node2D.new()
			enemy.position = actor.position+Vector2(120,0)
			world.add_child(enemy)
			enemy.add_to_group("enemies")
			visual.idle_clock.begin(kind)
			visual._process(0.01)
			check(visual.special_pose.is_empty(),"%s cancels around actual enemy-group nodes"%kind)
			enemy.free()
		_reset(actor,visual,world)
		var idle_names := Library.names(id,"idle")
		var observed: Array[String] = []
		for cycle in 6:
			visual.idle_clock.wait_remaining = 0
			visual._process(0.01)
			observed.append(visual.special_pose)
			visual._process(visual.idle_clock.duration()+0.01)
		check(idle_names.all(func(kind):return kind in observed),"%s reaches every new idle through the natural shuffled bag"%id)
		for action in ["mining","station"]:
			_reset(actor,visual,world)
			var focus := Node2D.new()
			world.add_child(focus)
			actor.focus = focus
			actor.mining = action=="mining"
			actor._interacting = action=="station"
			for frame in 8:
				visual._process(0.1)
			actor.mining = false
			actor._interacting = false
			for frame in 3:
				visual._process(0.1)
			check(visual.special_pose==Personality.reaction(id,"work_finished"),"%s recovers naturally after sustained %s"%[id,action])
			focus.free()
		_reset(actor,visual,world)
		actor.mining = true
		visual._process(0.8)
		actor.mining = false
		actor.velocity.x = 100
		visual._process(0.1)
		actor.velocity.x = 0
		visual._process(0.4)
		check(visual.special_pose.is_empty(),"%s drops a work reaction when movement intervenes"%id)
		_reset(actor,visual,world)
		world.rounds.phase = "attack"
		visual._process(0.01)
		world.rounds.phase = "salvage"
		for frame in 3:
			visual._process(0.1)
		check(visual.special_pose==Personality.reaction(id,"wave_clear"),"%s acknowledges an actual attack-to-salvage transition"%id)
		visual._process(visual.idle_clock.duration()+0.1)
		visual._process(0.5)
		check(visual.special_pose.is_empty(),"%s does not repeat wave-clear reaction every frame"%id)
		for condition in ["jump","cargo","crouch","hit","bleeding","aim","input","projectile"]:
			_reset(actor,visual,world)
			visual.idle_clock.begin(idle_names[0])
			var probe: Node2D
			match condition:
				"jump": actor._airborne = true
				"cargo": actor.inventory = {"ore":1}
				"crouch": visual.crouched = true
				"hit": actor.hurt_flash = 0.2
				"bleeding": actor.medical.bleeding = 1
				"aim":
					probe = WeaponProbe.new()
					probe.name = "WorkerWeapon"
					probe.aiming = true
					actor.add_child(probe)
				"input": Input.action_press(actor.action("interact"))
				"projectile":
					probe = Node2D.new()
					world.add_child(probe)
					probe.position = actor.position+Vector2(80,-20)
					probe.add_to_group("air_projectiles")
			visual._process(0.01)
			check(visual.idle_clock.gesture.is_empty(),"%s %s takes precedence over idle performance"%[id,condition])
			Input.action_release(actor.action("interact"))
			if is_instance_valid(probe): probe.free()
		_reset(actor,visual,world)
		var elapsed_at_quality: Array[float] = []
		for reduced in [false,true]:
			world.weather.reduced_effects = reduced
			visual.idle_clock.begin(idle_names[0])
			visual._process(0.4)
			elapsed_at_quality.append(visual.special_progress)
		check(is_equal_approx(elapsed_at_quality[0],elapsed_at_quality[1]),"%s reduced effects preserve readable character motion timing"%id)
		visual.set_process(true)
		paused = true
		var paused_progress := visual.special_progress
		for frame in 4:
			await process_frame
		check(visual.special_progress==paused_progress,"%s actual scene pause freezes the animation clock"%id)
		paused = false
		visual.set_process(false)
	await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	print("PLAYER ANIMATION EXPANSION: %d checks, %d failures; 6 new per character, 18 total"%[checks,failures])
	quit(1 if failures else 0)

func _portrait_checks() -> void:
	# Sample the public menu portrait clock, measuring each complete visible run
	# instead of reproducing its scheduling algorithm in the test.
	for id in IDS:
		var observed: Dictionary = {}
		var previous_kind := ""
		var run_length := 0.0
		var bounded_progress := true
		var monotonic_progress := true
		var previous_progress := 0.0
		for frame in 3900:
			var performance := Portraits.portrait_performance(id,float(frame)/60.0)
			var kind := str(performance.gesture)
			var progress := float(performance.progress)
			bounded_progress = bounded_progress and progress>=0.0 and progress<1.0
			if kind==previous_kind and not kind.is_empty():
				monotonic_progress = monotonic_progress and progress>=previous_progress
			if kind!=previous_kind:
				if not previous_kind.is_empty():
					observed[previous_kind] = run_length
				run_length = 0.0
			previous_kind = kind
			previous_progress = progress
			run_length += 1.0/60.0
		check(observed.size()==6,"%s menu portrait reaches all six idle performances"%id)
		check(bounded_progress and monotonic_progress,"%s menu portrait phases advance continuously from zero to one"%id)
		for kind in Personality.gestures(id):
			check(observed.has(kind) and absf(float(observed.get(kind,0))-Personality.duration(kind))<0.02,"%s menu portrait uses the complete authored duration for %s"%[id,kind])
		for kind in Library.names(id):
			if Library.CATALOG[kind].trigger!="idle":
				check(not observed.has(kind),"%s stays tied to its gameplay event instead of looping in the menu"%kind)
