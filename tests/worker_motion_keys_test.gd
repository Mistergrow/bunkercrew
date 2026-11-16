extends SceneTree
## Pass 6A-2 body keys (scripts/worker_motion_keys.gd) on real Worker and
## WorkerVisual state: the idle reads as held poses with weight, breath and
## follow-through; a hit plays impact, peak and recovery with knockback in
## texels and never touches gameplay; a knockout falls through at least three
## frames before lying; a revival gets up through a kneel; a worker idling at
## a running mixer tends it and stops the moment they act.
## Pass 7A-crew: the idle stands (boots under the hips, one leg under the
## weight), the walk rolls heel to toe on held body keys, the dance throws its
## arms on held beat poses, a reviver kneels beside the body behind it and
## gets up through in-betweens, the mixer rumbles and takes mallet knocks, and
## a gate panel ahead is no lintel to duck under.
const Keys := preload("res://scripts/worker_motion_keys.gd")
const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const IDS := ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func make_worker(parent: Node, point: Vector2, id: int) -> Worker:
	var worker := Worker.new()
	worker.game = parent
	worker.player_id = id
	worker.position = point
	parent.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	return worker

static func whole(value: Vector2) -> bool:
	return value == value.round()

static func signature(pose: Dictionary) -> String:
	return var_to_str([Vector2(pose.hip).round(), Vector2(pose.shoulder).round(), Vector2(pose.hands[0]).round(), Vector2(pose.hands[1]).round(), Vector2(pose.head_shift).round(), snappedf(float(pose.head_tilt), 0.01), pose.get("gear", Vector2.ZERO), pose.get("gear_swing", 0), pose.get("hair_swing", 0)])

func run() -> void:
	InputSetup.install()
	_key_tables()
	var world := Node2D.new()
	root.add_child(world)
	_idle(world)
	_hit(world)
	_collapse(world)
	await _tending(world)
	_standing_idle(world)
	_walk_keys(world)
	_dance_keys()
	_revive(world)
	await _mixer(world)
	await _gate_probe(world)
	print("WORKER MOTION KEYS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _key_tables() -> void:
	var distinct := {}
	var hip_x := []
	for frame in Keys.IDLE_FRAMES:
		var key := Keys.idle_key(frame, 0)
		check(whole(key.hip) and whole(key.shoulder) and whole(key.head) and whole(key.gear) and whole(key.hands[0]), "Idle frame %d is whole-texel offsets" % frame)
		distinct[var_to_str([key.hip, key.shoulder, key.head, key.hands, key.gear, key.gear_swing, key.hair_swing])] = true
		hip_x.append(float(key.hip.x))
	check(distinct.size() >= 12, "The idle loop holds at least twelve distinct poses (%d)" % distinct.size())
	check(hip_x.max() - hip_x.min() >= 2.0, "The idle weight shift carries the hips at least two texels")
	var follow := 0
	for frame in range(10, 16):
		var key := Keys.idle_key(frame, 0)
		if int(key.gear_swing) != 0 or int(key.hair_swing) != 0: follow += 1
	check(follow >= 3, "Pack and hair trail the weight transfer for several frames")
	check(not is_zero_approx(float(Keys.idle_key(5, 2).tilt)) and is_zero_approx(float(Keys.idle_key(5, 0).tilt)), "Every third loop holds a glance")
	check(Keys.IDLE_FPS >= 8.0 and Keys.HIT_FPS <= 12.0 and Keys.COLLAPSE_FPS <= 12.0 and Keys.TEND_FPS >= 8.0, "Body keys play at 8-12 frames per second")
	check(Keys.HIT_KEYS.size() >= 4 and Keys.hit_seconds() <= 0.6, "A hit is one impact, a peak and at least two recovery keys inside 0.6 s")
	check(Vector2(Keys.HIT_KEYS[1].shoulder).length() >= 5.0 and absf(Vector2(Keys.HIT_KEYS[1].step).x) >= 3.0, "The hit peak throws the shoulders five texels and steps a boot three")
	check(Keys.hit_key(Keys.hit_seconds() + 0.01).is_empty(), "The hit ends")
	var lying := Keys.COLLAPSE_KEYS[-1]
	var falling := 0
	for key: Dictionary in Keys.COLLAPSE_KEYS:
		var spine: float = Vector2(key.shoulder).distance_to(key.hip)
		check(spine >= 16.0 and spine <= 17.6, "Collapse spines keep the coat on the hips (%.1f)" % spine)
		if key != lying and Vector2(key.shoulder).y < float(lying.shoulder.y)-1.0: falling += 1
	check(falling >= 3, "The collapse has at least three fall frames before it lies (%d)" % falling)
	check(absf(Vector2(lying.shoulder).x - Vector2(lying.hip).x) > 16.0, "The collapse settles flat on the back")
	check(Keys.rise_key(1.0).is_empty() and not Keys.rise_key(0.55).is_empty() and Vector2(Keys.rise_key(0.55).hip).y > -16.0, "The rise passes through a kneel and ends in the plain stance")
	for step in range(-IdentityArt.LAYER_STEPS, IdentityArt.LAYER_STEPS + 1):
		for layer in ["coat", "gear", "head", "hair"]:
			for swing in [-1, 0, 1]:
				var region := IdentityArt.layer_region(layer, step, swing)
				check(region.has_area() and Rect2(Vector2.ZERO, IdentityArt.layers("mara").get_size()).encloses(region), "Layer %s step %d swing %d is in the sheet" % [layer, step, swing])
	check(not IdentityArt.layer_region("coat", IdentityArt.LAYER_STEPS + 1).has_area(), "Beyond the layered steps the single turned piece is drawn")

func _idle(world: Node2D) -> void:
	for id in ["mara", "branko", "levin", "rika"]:
		var worker := make_worker(world, Vector2(200, 300), 1)
		worker.character_id = id
		var visual: WorkerVisual = worker.get_node("PixelVisual")
		visual._ready()
		visual.idle_clock.wait_remaining = 1000
		var seen := {}
		var runs: Array[int] = []
		var last := ""
		var run_length := 0
		for frame in 78:
			visual._process(1.0/60.0)
			var current := signature(visual.pose_skeleton)
			seen[current] = true
			if current == last: run_length += 1
			else:
				if run_length > 0: runs.append(run_length)
				run_length = 1
			last = current
		check(seen.size() >= 6, "%s: a 1.3 s idle shows at least six distinct held poses (%d)" % [id, seen.size()])
		var held := runs.filter(func(length: int) -> bool: return length >= 4)
		check(held.size() * 2 >= runs.size(), "%s: idle poses are held frames, not continuous drift" % id)
		worker.free()

func _hit(world: Node2D) -> void:
	var worker := make_worker(world, Vector2(400, 300), 1)
	worker.character_id = "mara"
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	visual._ready()
	visual.idle_clock.wait_remaining = 1000
	for frame in 30: visual._process(1.0/60.0)
	var rest: Dictionary = visual.pose_skeleton.duplicate(true)
	var before_position := worker.position
	worker.invulnerability = 0
	worker.take_damage(5.0, Vector2.LEFT)
	var stun := float(worker.hurt_stun)
	var knock := float(worker.knockback)
	var peak := 0.0
	var stepped := false
	for frame in 8:
		visual._process(1.0/60.0)
		peak = maxf(peak, Vector2(visual.pose_skeleton.shoulder).distance_to(rest.shoulder))
		stepped = stepped or Vector2(visual.pose_skeleton.feet[0]).distance_to(rest.feet[0]) >= 2.0 or Vector2(visual.pose_skeleton.feet[1]).distance_to(rest.feet[1]) >= 2.0
	check(peak >= 4.0, "A real hit throws the shoulders at least four texels (%.1f)" % peak)
	check(stepped, "A real hit steps a boot to catch the knockback")
	check(worker.position == before_position and float(worker.hurt_stun) == stun and float(worker.knockback) == knock, "The hit presentation never moves the actor or changes its stun or knockback")
	for frame in 40: visual._process(1.0/60.0)
	check(Keys.hit_key(visual.locomotion.hit.age).is_empty(), "The reaction has played out within its keys")
	worker.free()

func _collapse(world: Node2D) -> void:
	var worker := make_worker(world, Vector2(600, 300), 1)
	worker.character_id = "selma"
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	visual._ready()
	worker.invulnerability = 0
	worker.take_damage(500.0)
	var shoulders: Array[float] = []
	var poses := {}
	for step in 10:
		worker.medical.down_elapsed = step/12.0
		visual._process(0.0)
		check(visual.special_pose == "downed", "A knockout shows the collapse")
		shoulders.append(float(visual.pose_skeleton.shoulder.y))
		poses[signature(visual.pose_skeleton)] = true
	check(poses.size() >= 5, "The collapse is at least five distinct keys (%d)" % poses.size())
	check(shoulders[0] < -30.0 and shoulders[3] > shoulders[0] and shoulders[-1] > -16.0, "The shoulders fall from standing height through a kneel to the floor")
	worker.free()

func _tending(world: Node2D) -> void:
	var station := ProductionStation.new()
	station.position = Vector2(900, 300)
	world.add_child(station)
	station.set_process(false)
	var worker := make_worker(world, Vector2(905, 300), 1)
	worker.character_id = "oskar"
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	visual._ready()
	visual.idle_clock.wait_remaining = 1000
	station.working = true
	worker.focus = station
	var swings := {}
	for frame in 100:
		visual._process(1.0/60.0)
		check(str(visual.pose_skeleton.get("prop", "")) == "work_hammer", "A worker idling at the running mixer tends it with the mallet")
		swings[snappedf(float(visual.pose_skeleton.get("work_tool_angle", 0.0)), 0.05)] = true
		for index in 2:
			var socket: Vector2 = WorkerPoseArt.torso_transform(visual.pose_skeleton)*WorkerPoseArt.shoulder_local(visual.pose_skeleton, index)
			check(socket.distance_to(visual.pose_skeleton.hands[index]) <= 22.9, "Tending hands stay within arm reach")
	check(swings.size() >= 4, "The tending mallet moves through its wind-up, blows and rest")
	worker.velocity.x = 90
	visual._process(1.0/60.0)
	check(str(visual.pose_skeleton.get("prop", "")) != "work_hammer", "Walking ends tending at once")
	worker.velocity.x = 0
	station.working = false
	for frame in 10: visual._process(1.0/60.0)
	check(str(visual.pose_skeleton.get("prop", "")) != "work_hammer", "A stopped machine is not tended")
	worker.free()
	station.free()
	await process_frame

# ------------------------------------------------------------- pass 7A-crew
func _standing_idle(world: Node2D) -> void:
	for id: String in IDS:
		var base := Personality.stance(WorkerPoseArt.neutral(), id)
		var gap := absf(Vector2(base.feet[1]).x-Vector2(base.feet[0]).x)
		check(gap <= 9.0, "%s stands with the boots under the hips, not a stride (%d texels apart)" % [id, int(gap)])
		check(float(base.hip.x) > Vector2(base.feet[0]).x and float(base.hip.x) < Vector2(base.feet[1]).x and float(base.hip.y) <= -25.0, "%s keeps the hips over the boots on nearly straight legs" % id)
		var worker := make_worker(world, Vector2(200, 300), 1)
		worker.character_id = id
		var visual: WorkerVisual = worker.get_node("PixelVisual")
		visual.idle_clock.wait_remaining = 1000
		var under := 0
		var widest := 0.0
		for frame in 200:
			visual._process(1.0/60.0)
			var pose: Dictionary = visual.pose_skeleton
			widest = maxf(widest, absf(Vector2(pose.feet[1]).x-Vector2(pose.feet[0]).x))
			var spread := float(pose.get("hip_spread", 4.0))
			for index in 2:
				if absf(Vector2(pose.feet[index]).x-(float(pose.hip.x)+(-spread if index == 0 else spread))) <= 1.01: under += 1
		check(widest <= 9.0, "%s: the live idle never opens into a stride (%.1f)" % [id, widest])
		check(under >= 150, "%s: one leg stands under the weight through the idle (%d of 200 frames)" % [id, under])
		worker.free()

func _walk_keys(world: Node2D) -> void:
	var bobs: Array[float] = []
	for key: Dictionary in Keys.WALK_KEYS: bobs.append(float(key.bob))
	check(Keys.WALK_KEYS.size() == 4 and bobs.max()-bobs.min() >= 2.0, "A step holds contact, down, passing and up keys with at least two texels of bob")
	var previous := Keys.walk_foot_angle(0.0, 0.55)
	var smooth := true
	for step in range(1, 2001):
		var angle := Keys.walk_foot_angle(float(step)/1000.0, 0.55)
		smooth = smooth and absf(angle-previous) < 0.03
		previous = angle
	check(smooth, "The boot rolls heel to toe without a snap over two cycles")
	check(Keys.walk_foot_angle(0.0, 0.55) < -0.2 and Keys.walk_foot_angle(0.549, 0.55) > 0.3, "Heel strike lifts the toe, toe-off lifts the heel")
	var worker := make_worker(world, Vector2(300, 300), 1)
	worker.character_id = "mara"
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	var swings := {}
	var rolled := false
	var heights := {}
	for frame in 90:
		worker.velocity.x = 190.0
		worker.position.x += 190.0/60.0
		visual._process(1.0/60.0)
		var pose: Dictionary = visual.pose_skeleton
		if frame < 30: continue
		swings[[int(pose.get("gear_swing", 0)), int(pose.get("hair_swing", 0))]] = true
		heights[roundi(float(pose.shoulder.y))] = true
		var angles: Array = pose.get("foot_angles", [0.0, 0.0])
		rolled = rolled or absf(float(angles[0])) > 0.2 or absf(float(angles[1])) > 0.2
	check(swings.size() >= 3, "Pack and hair follow through the stride (%d states)" % swings.size())
	check(heights.size() >= 3, "The chest bobs over at least three held heights (%d)" % heights.size())
	check(rolled, "The running boots roll at contact and toe-off")
	worker.free()

func _dance_keys() -> void:
	for beat in 8:
		var key := Keys.dance_key(float(beat))
		check(key.hands[0] == Keys.DANCE_KEYS[beat % 4].hands[0] and key.hands[1] == Keys.DANCE_KEYS[beat % 4].hands[1], "Dance key %d lands on its kick" % beat)
		check(Keys.dance_key(float(beat)+Keys.DANCE_HOLD*0.9).hands[1] == key.hands[1], "Dance key %d holds into the beat" % beat)
	var pose := WorkerPoseArt.neutral()
	pose.foot_angles = [0.0, 0.0]
	var raised := pose.duplicate(true)
	Rhythm._apply_groove(raised, 2.0, 1.0, "crew_bounce")
	var body := WorkerPoseArt.torso_transform(raised)
	var socket := body*WorkerPoseArt.shoulder_local(raised, 1)
	check(Vector2(raised.hands[1]).y < float(raised.shoulder.y)-12.0 and Vector2(raised.hands[1]).x > socket.x+4.0, "Beat three throws the near arm up and forward, clear of the face")
	check(socket.distance_to(raised.hands[1]) <= 22.91, "A thrown arm stays within its reach")
	var pumped := pose.duplicate(true)
	Rhythm._apply_groove(pumped, 1.0, 1.0, "crew_bounce")
	check(Vector2(pumped.hands[1]).y > Vector2(raised.hands[1]).y+12.0, "Beat two pumps the arms down again")
	var quiet := pose.duplicate(true)
	Rhythm._apply_groove(quiet, 2.0, 1.0, "crew_bounce", 0.0)
	var held := WorkerPoseArt.torso_transform(quiet)*WorkerPoseArt.shoulder_local(quiet, 1)
	var rest := WorkerPoseArt.torso_transform(pose)*WorkerPoseArt.shoulder_local(pose, 1)
	check((Vector2(quiet.hands[1])-held).distance_to(Vector2(pose.hands[1])-rest) < 0.01, "With the arm keys at rest the dance keeps its own arm carriage")

func _revive(world: Node2D) -> void:
	var patient := make_worker(world, Vector2(1200, 300), 1)
	patient.character_id = "mara"
	var helper := make_worker(world, Vector2(1234, 300), 2)
	helper.character_id = "branko"
	helper.facing = -1
	var helper_visual: WorkerVisual = helper.get_node("PixelVisual")
	helper_visual.idle_clock.wait_remaining = 1000
	patient.invulnerability = 0
	patient.take_damage(patient.hp+500.0)
	var origin := helper.position
	var kneel: Dictionary = {}
	var entry := {}
	for frame in 40:
		patient.medical.begin_or_continue_aid(helper, 1.0/60.0)
		helper_visual._process(1.0/60.0)
		if frame < 12: entry[roundi(float(helper_visual.pose_skeleton.hip.y))] = true
		kneel = helper_visual.pose_skeleton
	check(helper_visual.special_pose == "aid_revive" and helper_visual.z_index == -1, "The reviver kneels drawn behind the patient's body")
	check(entry.size() >= 3, "The reviver steps in through in-between keys (%d heights)" % entry.size())
	check(float(kneel.hip.y) > -18.0 and float(kneel.hip.x) > 12.0, "The kneel sits beside the chest, slid along the body (hips at %s)" % str(kneel.hip))
	check(helper.position == origin, "The kneel never moves the reviver's collider")
	var chest := patient.to_global(Vector2(-9, -19))
	for hand: Vector2 in kneel.hands:
		check(helper.to_global(hand*Vector2(helper.facing, 1)).distance_to(chest) < 6.0, "Both hands press on the chest")
	patient.medical.begin_or_continue_aid(helper, MedicalCatalog.REVIVE_TIME)
	var rise := {}
	for frame in 30:
		helper_visual._process(1.0/60.0)
		rise[roundi(float(helper_visual.pose_skeleton.hip.y))] = true
	check(rise.size() >= 4, "The reviver gets up through in-betweens (%d heights)" % rise.size())
	check(helper_visual.z_index == 0 and helper_visual._aid_rise < 0.0, "Standing again, the reviver returns to the crew's draw order")
	check(Vector2(helper_visual.pose_skeleton.feet[1]).x < 8.0, "The reviver has stepped back to its own place")
	# A second revival, cut short by walking off: the rise gives way at once.
	patient.invulnerability = 0
	patient.medical.recovery_time = 0
	patient.hp = 1.0
	patient.take_damage(500.0)
	for frame in 20:
		patient.medical.begin_or_continue_aid(helper, 1.0/60.0)
		helper_visual._process(1.0/60.0)
	patient.medical.begin_or_continue_aid(helper, MedicalCatalog.REVIVE_TIME)
	helper.velocity.x = 90
	helper_visual._process(1.0/60.0)
	check(helper_visual._aid_rise < 0.0 and helper_visual.pose_name == "walk", "Walking away ends the rise immediately")
	patient.free()
	helper.free()

func _mixer(world: Node2D) -> void:
	var station := ProductionStation.new()
	station.position = Vector2(1600, 300)
	world.add_child(station)
	station.set_process(false)
	var animation = station.get_node("MixerAnimation")
	animation.set_process(false)
	var center: Vector2 = animation.DRUM_RECT.get_center()
	for step in 30:
		station.elapsed += 1.0/60.0
		animation.advance_visual(1.0/60.0)
	check(animation.rumble_offset == Vector2.ZERO, "An idle mixer does not rumble")
	station.working = true
	var bumps := 0
	for step in 240:
		station.elapsed += 1.0/60.0
		animation.advance_visual(1.0/60.0)
		var offset: Vector2 = animation.rumble_offset
		check(offset == offset.round() and absf(offset.x) <= 1.0 and absf(offset.y) <= 1.0, "The rumble is a whole-texel step of at most one texel")
		check(animation.drum.position == center+animation.rhythm_offset, "The rumble leaves the drum's position to the beat bob")
		if offset != Vector2.ZERO: bumps += 1
	check(bumps >= 30 and bumps <= 150, "A working drum bumps on its seams (%d of 240 frames)" % bumps)
	animation.knock(station.to_global(Vector2(28, -45)), 1.0)
	check(animation.rumble_offset == Vector2(1, 0), "A mallet knock jolts the drum a texel along the blow")
	await process_frame
	station.queue_free()
	await process_frame

func _gate_probe(world: Node2D) -> void:
	var worker := make_worker(world, Vector2(2400, 300), 1)
	worker.character_id = "mara"
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	worker.velocity.x = 150
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	(shape.shape as RectangleShape2D).size = Vector2(34, 64)
	wall.add_child(shape)
	wall.position = Vector2(2448, 268)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	visual._clearance_time = 0.0
	visual._physics_process(1.0/60.0)
	check(visual.crouched and visual._wall_ahead and not visual.body_crouched(), "A gate panel standing on the floor ahead is no lintel: the body stays upright")
	wall.position = Vector2(2448, 244)
	(shape.shape as RectangleShape2D).size = Vector2(34, 24)
	await physics_frame
	await physics_frame
	visual._clearance_time = 0.0
	visual._physics_process(1.0/60.0)
	check(visual.crouched and visual.body_crouched(), "A real lintel ahead still makes the worker duck")
	wall.queue_free()
	worker.free()

