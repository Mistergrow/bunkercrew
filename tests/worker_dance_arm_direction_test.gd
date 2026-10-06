extends SceneTree
## These compact popping moves present their near wrist in front of the coat.
## Broad waves and floor-support moves deliberately retain their own carriage.
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const VisualFixture := preload("res://tests/rhythm_visual_test.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const COMPACT_MOVES := {
	"ivo_heel_switch":"ivo",
	"ivo_knee_wave":"ivo",
	"mara_lockstep":"mara",
	"branko_shoulder_hit":"branko",
	"rika_contact_shuffle":"rika",
}
const PHRASE_BEATS := 16.0
const SAMPLES_PER_BEAT := 16
var checks := 0
var failures := 0
var _pose_renderer: RefCounted = PoseArt.new()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _front_wrist(pose: Dictionary,facing: float) -> bool:
	var body := PoseArt.torso_transform(pose)
	var mirror := Vector2(facing,1.0)
	var chest: Vector2 = body.origin*mirror
	var wrist: Vector2 = Vector2(pose.hands[1])*mirror
	var forward: Vector2 = body.x*mirror
	# Four native pixels puts the wrist beyond the near shoulder (x=3),
	# rather than accepting a glove drawn across the pack behind the chest.
	return (wrist-chest).dot(forward)>=4.0-.001

func _connected_arms(pose: Dictionary,facing: float) -> bool:
	if not pose.has("elbows") or pose.elbows.size()!=2:
		return false
	var body := PoseArt.torso_transform(pose)
	var mirror := Vector2(facing,1.0)
	for index in 2:
		var shoulder: Vector2 = (body*PoseArt.shoulder_local(pose,index))*mirror
		var elbow: Vector2 = Vector2(pose.elbows[index])*mirror
		var hand: Vector2 = Vector2(pose.hands[index])*mirror
		if not elbow.is_finite() or not hand.is_finite():
			return false
		if absf(shoulder.distance_to(elbow)-11.0)>.351 or absf(elbow.distance_to(hand)-11.7)>.401:
			return false
	return true

func _visual_front_wrist(visual: WorkerVisual,facing: float) -> bool:
	var pose: Dictionary = visual.pose_skeleton
	var body := PoseArt.torso_transform(pose)
	var transform := ActorWeatherGeometry.worker_transform(visual)
	var chest: Vector2 = transform*body.origin
	var wrist: Vector2 = transform*Vector2(pose.hands[1])
	# The intended world direction comes from the actual actor, independently
	# from the mirror selected by its draw path. A wrong sprite-facing branch
	# must therefore fail instead of being mirrored twice by the test.
	var forward: Vector2 = body.x*Vector2(facing,1.0)
	return (wrist-chest).dot(forward)>=4.0-.001

func _frame(beats: float,id: String,style: String) -> Dictionary:
	return {"active":true,"phase":fposmod(beats,1.0),"bar":floori(beats/4.0),"beat":floori(beats)%4,"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"bpm":120.0,"beat_period_seconds":.5,"motion_gain":1.0,"dance_intensity":1.5,"dance_profiles":{id:{"style":style,"intensity":1.0}},"genre":"minimal_techno"}

func _stomp_support(pose: Dictionary) -> bool:
	var supported := false
	for index in 2:
		var foot: Vector2 = pose.feet[index]
		if foot.y>-2.999:
			return false
		var boot := PoseArt.foot_transform(foot,float(pose.foot_angles[index]))
		var lowest := maxf((boot*Vector2(-5,3)).y,(boot*Vector2(8,3)).y)
		if absf(lowest)<.001:
			supported = true
	return supported

func _drawn_leg_reach(pose: Dictionary) -> bool:
	var spread := float(pose.get("hip_spread",4.0))
	for index in 2:
		var leg_attachment: Vector2 = pose.hip+Vector2(-spread if index==0 else spread,0)
		if leg_attachment.distance_to(pose.feet[index])>23.801:
			return false
	return true

func _drawn_elbows(pose: Dictionary) -> Array:
	if _pose_renderer.has_method("arm_elbows"):
		var resolved: Array = _pose_renderer.call("arm_elbows",pose)
		return resolved
	# The saved baseline predates the renderer's pure elbow accessor. Read
	# its authored hints, or use its actual shared solver for an unhinted arm.
	# This compatibility path keeps the same regression runnable before/after.
	var body := PoseArt.torso_transform(pose)
	var result: Array[Vector2] = []
	for index in 2:
		if pose.has("elbows"):
			result.append(pose.elbows[index])
		else:
			result.append(PoseArt.joint_position(body*PoseArt.shoulder_local(pose,index),pose.hands[index],11,12))
	return result

func _freeze_elbow_contract(world: VisualFixture.Fixture,actor: Worker,visual: WorkerVisual) -> void:
	actor.configure_character("levin")
	for intensity: float in [.5,1.0]:
		for facing: float in [-1.0,1.0]:
			actor.facing = facing
			visual.rhythm.reset()
			visual.idle_clock.wait_remaining = 1000.0
			for beat in 8:
				var frame := _frame(float(beat),"levin","levin_air_freeze")
				frame.dance_intensity = intensity
				world.audio.live_music.state = frame
				visual._process(.5)
			var previous_elbows: Array = []
			var previous_hands: Array = []
			var largest_elbow_step := 0.0
			var largest_hand_step := 0.0
			var connected := true
			for sample in 142:
				# Drop through the authored-to-unhinted handoff at beat3.0, using
				# exactly1/128 beat steps and the actual blended WorkerVisual rig.
				var frame := _frame(10.0+float(sample)/128.0,"levin","levin_air_freeze")
				frame.dance_intensity = intensity
				world.audio.live_music.state = frame
				visual._process(1.0/256.0)
				var pose: Dictionary = visual.pose_skeleton
				var elbows := _drawn_elbows(pose)
				var body := PoseArt.torso_transform(pose)
				var transform := ActorWeatherGeometry.worker_transform(visual)
				var hands: Array[Vector2] = []
				for index in 2:
					var attachment := body*PoseArt.shoulder_local(pose,index)
					var elbow: Vector2 = elbows[index]
					connected = connected and elbow.is_finite() and attachment.distance_to(elbow)<=11.3501 and elbow.distance_to(pose.hands[index])<=12.1001
					elbows[index] = transform*elbow
					hands.append(transform*Vector2(pose.hands[index]))
					if not previous_elbows.is_empty():
						largest_elbow_step = maxf(largest_elbow_step,Vector2(elbows[index]).distance_to(previous_elbows[index]))
						largest_hand_step = maxf(largest_hand_step,hands[index].distance_to(previous_hands[index]))
				previous_elbows = elbows
				previous_hands = hands
			check(largest_elbow_step<2.0,"Levin freeze strength%.1f facing%.0f: actual drawn elbows stay continuous through the authored/default handoff (largest%.3fpx per1/128 beat)"%[intensity,facing,largest_elbow_step])
			check(largest_hand_step<1.0,"Levin freeze strength%.1f facing%.0f: the real grips remain continuous while the rig enters floor support"%[intensity,facing])
			check(connected,"Levin freeze strength%.1f facing%.0f: authored and default elbow paths keep both real arm segments bounded"%[intensity,facing])

func _stomp_contract() -> void:
	for intensity: float in [.5,1.0,1.5]:
		for facing: float in [-1.0,1.0]:
			var steady := true
			var supported := true
			for sample in int(PHRASE_BEATS*SAMPLES_PER_BEAT)+1:
				var pose := Rhythm.choreography("branko_foundry_stomp",float(sample)/SAMPLES_PER_BEAT,"branko",intensity)
				steady = steady and absf(float(pose.hip.x))<.001 and absf(PoseArt.torso_transform(pose).get_rotation())<.001
				steady = steady and float(pose.hip.y)>=-26.651 and float(pose.hip.y)<=-26.299
				supported = supported and _stomp_support(pose)
			check(steady,"Branko stomp strength%.1f facing%.0f: planted pelvis and upright body retain the nearly straight marching stance"%[intensity,facing])
			check(supported,"Branko stomp strength%.1f facing%.0f: an actual painted sole supports every moment and neither boot passes through the floor"%[intensity,facing])
			var planted := true
			var alternate := true
			var extended := true
			for beat in int(PHRASE_BEATS)+1:
				var pose := Rhythm.choreography("branko_foundry_stomp",float(beat),"branko",intensity)
				planted = planted and is_equal_approx(pose.feet[0].y,-3.0) and is_equal_approx(pose.feet[1].y,-3.0)
				if beat==int(PHRASE_BEATS):
					continue
				pose = Rhythm.choreography("branko_foundry_stomp",float(beat)+.5,"branko",intensity)
				var lifted := beat%2
				alternate = alternate and float(pose.feet[lifted].y)<-3.5 and is_equal_approx(pose.feet[1-lifted].y,-3.0)
				if intensity>=1.0:
					var hip: Vector2 = pose.hip+Vector2(-4.0 if lifted==0 else 4.0,0)
					var mirror := Vector2(facing,1.0)
					var reach := (Vector2(pose.feet[lifted])-hip)*mirror
					extended = extended and reach.length()>=23.6 and reach.length()<=23.801 and reach.x*facing>10.0
			check(planted,"Branko stomp strength%.1f facing%.0f: both boots plant precisely on each heard beat"%[intensity,facing])
			check(alternate,"Branko stomp strength%.1f facing%.0f: the forward raised leg alternates while the opposite sole carries weight"%[intensity,facing])
			if intensity>=1.0:
				check(extended,"Branko stomp strength%.1f facing%.0f: the raised marching leg reaches forward nearly straight instead of folding underneath the coat"%[intensity,facing])

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	for style: String in COMPACT_MOVES:
		var id: String = COMPACT_MOVES[style]
		for intensity: float in [.5,1.0,1.5]:
			for facing: float in [-1.0,1.0]:
				var front := true
				var connected := true
				for sample in int(PHRASE_BEATS*SAMPLES_PER_BEAT)+1:
					var beats := float(sample)/SAMPLES_PER_BEAT
					var pose := Rhythm.choreography(style,beats,id,intensity)
					front = front and _front_wrist(pose,facing)
					connected = connected and _connected_arms(pose,facing)
				check(front,"%s strength%.1f facing%.0f: compact near wrist remains in front of the chest throughout sixteen heard beats"%[style,intensity,facing])
				check(connected,"%s strength%.1f facing%.0f: both authored upper arms and forearms remain attached to their real endpoints"%[style,intensity,facing])
	_stomp_contract()
	var world := VisualFixture.Fixture.new()
	world.set_meta("dance_preview",true)
	root.add_child(world)
	world.audio = VisualFixture.AudioStub.new()
	world.add_child(world.audio)
	world.audio.live_music = VisualFixture.MusicStub.new()
	world.audio.add_child(world.audio.live_music)
	var actor := Worker.new()
	actor.game = world
	world.add_child(actor)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	actor.add_child(visual)
	_freeze(actor)
	for style: String in COMPACT_MOVES:
		var id: String = COMPACT_MOVES[style]
		actor.configure_character(id)
		for facing: float in [-1.0,1.0]:
			actor.position = Vector2(124,230)
			actor.facing = facing
			actor.velocity = Vector2.ZERO
			actor.inventory.clear()
			visual.rhythm.reset()
			visual.idle_clock.wait_remaining = 1000.0
			for beat in 8:
				world.audio.live_music.state = _frame(float(beat),id,style)
				visual._process(.5)
			check(visual.rhythm._dance_blend==1.0 and visual.pose_skeleton.get("dance_style","")==style,id+": actual WorkerVisual reaches its requested compact move after real fixture kick events")
			check(visual.sprite_facing()==facing,id+": real dance drawing faces the actor's world direction")
			var before := [actor.position,actor.velocity,actor.facing,actor.inventory.duplicate(true),actor.hp]
			var front := true
			var connected := true
			for sample in int(PHRASE_BEATS*SAMPLES_PER_BEAT)+1:
				world.audio.live_music.state = _frame(8.0+float(sample)/SAMPLES_PER_BEAT,id,style)
				visual._process(1.0/(SAMPLES_PER_BEAT*2.0))
				front = front and _visual_front_wrist(visual,facing)
				connected = connected and _connected_arms(visual.pose_skeleton,visual.sprite_facing())
			check(front,id+": actual rendered pose keeps its compact near hand ahead of the chest in either world facing")
			check(connected,id+": actual rendered pose retains both elbow/grip connections")
			check(before==[actor.position,actor.velocity,actor.facing,actor.inventory,actor.hp],id+": dance presentation changes no position, facing, velocity, cargo or health")
	actor.configure_character("branko")
	for facing: float in [-1.0,1.0]:
		actor.position = Vector2(230,324)
		actor.facing = facing
		actor.velocity = Vector2.ZERO
		visual.rhythm.reset()
		visual.idle_clock.wait_remaining = 1000.0
		for beat in 8:
			world.audio.live_music.state = _frame(float(beat),"branko","branko_foundry_stomp")
			visual._process(.5)
		check(visual.rhythm._dance_blend==1.0 and visual.pose_skeleton.get("dance_style","")=="branko_foundry_stomp","Branko: actual WorkerVisual enters the existing unlocked foundry move")
		var before := [actor.position,actor.velocity,actor.facing,actor.inventory.duplicate(true),actor.hp]
		var supported := true
		var steady := true
		var connected := true
		for sample in int(PHRASE_BEATS*SAMPLES_PER_BEAT)+1:
			world.audio.live_music.state = _frame(8.0+float(sample)/SAMPLES_PER_BEAT,"branko","branko_foundry_stomp")
			visual._process(1.0/(SAMPLES_PER_BEAT*2.0))
			supported = supported and _stomp_support(visual.pose_skeleton)
			steady = steady and absf(float(visual.pose_skeleton.hip.x))<.001 and visual.sprite_facing()==facing
			connected = connected and _drawn_leg_reach(visual.pose_skeleton) and is_equal_approx(float(visual.pose_skeleton.get("hip_spread",4.0)),4.0)
		check(supported and steady,"Branko: actual dance rig keeps the marching pelvis still and a painted sole supported in either facing")
		check(connected,"Branko: actual rendered hip attachments follow the marching stance and keep each boot within both bone lengths")
		check(before==[actor.position,actor.velocity,actor.facing,actor.inventory,actor.hp],"Branko: high forward kicks never displace the actual actor or alter movement, cargo or health")
	_freeze_elbow_contract(world,actor,visual)
	check(await Cleanup.free_scene(world,self),"Compact dance fixtures release all owning nodes")
	print("WORKER DANCE ARM DIRECTION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)
