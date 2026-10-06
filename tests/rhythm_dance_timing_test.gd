extends SceneTree
## Heard output samples, quarter/eighth anchors, and functional weapon poses.
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const VisualTest := preload("res://tests/rhythm_visual_test.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func heard_at(clock: MusicBeatClock,beat: float,rate: int,latency: float,calibration: float,events: Array=[]) -> Dictionary:
	var audible_sample := roundi(beat*float(rate)*60.0/clock.bpm)
	# A fractional latency must put the event on the audible side of its
	# integer sample boundary; rounding down would correctly keep it pending.
	var mixed := audible_sample+ceili((latency+calibration)*rate)
	clock.advance(mixed,rate,0,latency,events)
	var frame := clock.frame()
	frame.motion_gain = 1.0
	frame.dance_intensity = 1.0
	frame.dance_profiles = {}
	return frame

func _run() -> void:
	InputSetup.install()
	for tempo in [92.0,118.0,132.0,146.0]:
		for rate in [44100,48000]:
			var clock := MusicBeatClock.new()
			clock.configure(tempo)
			var latency := .060
			var calibration := .073
			clock.set_calibration(calibration)
			var rhythm := Rhythm.new()
			rhythm.configure("mara")
			for beat in 9:
				var event := {"sample":roundi(float(beat)*rate*60.0/tempo),"kind":"hit","track":0,"strength":1.0}
				var frame := heard_at(clock,float(beat),rate,latency,calibration,[event])
				frame.dance_profiles = {"mara":{"style":"head_nod","intensity":1.0}}
				rhythm.advance(60.0/tempo,true,frame)
			check(rhythm._dance_blend==1.0,"%d BPM/%d Hz heard kicks establish the dance"%[tempo,rate])
			var kick_frame := heard_at(clock,9.0,rate,latency,calibration,[{"sample":roundi(9.0*rate*60.0/tempo),"kind":"hit","track":0,"strength":1.0}])
			kick_frame.dance_profiles = {"mara":{"style":"head_nod","intensity":1.0}}
			rhythm.advance(0.0,true,kick_frame)
			var kick_pose := PoseArt.neutral()
			rhythm.apply(kick_pose,kick_frame)
			var nod_frame := heard_at(clock,9.09,rate,latency,calibration)
			nod_frame.dance_profiles = kick_frame.dance_profiles
			rhythm.advance(0.0,true,nod_frame)
			var nod_pose := PoseArt.neutral()
			rhythm.apply(nod_pose,nod_frame)
			var offbeat_frame := heard_at(clock,9.5,rate,latency,calibration)
			offbeat_frame.dance_profiles = kick_frame.dance_profiles
			rhythm.advance(0.0,true,offbeat_frame)
			var offbeat_pose := PoseArt.neutral()
			rhythm.apply(offbeat_pose,offbeat_frame)
			check(kick_pose.hip.y>offbeat_pose.hip.y+.3,"%d BPM body compression lands on the heard kick"%tempo)
			check(nod_pose.head_shift.y>offbeat_pose.head_shift.y+.5 and nod_pose.head_tilt>offbeat_pose.head_tilt+.16,"%d BPM chin visibly dips within 60 ms of the heard kick and returns before the offbeat"%tempo)
			for boundary in range(20,61):
				var beat := float(boundary)*.5
				var frame := heard_at(clock,beat,rate,latency,calibration)
				var sampled := float(frame.bar)*4.0+float(frame.beat)+float(frame.phase)
				check(absf(sampled-beat)<.0001,"%d BPM audible quarter/eighth grid survives latency/calibration"%tempo)
				check(absf(Rhythm.snappy_beats(sampled)-beat)<.00013,"%d BPM faster articulation preserves the same audible anchor"%tempo)
				for style: String in Dance.FULL_BODY_STYLES:
					var pose := Rhythm.choreography(style,sampled,"mara",1.0)
					var exact := Rhythm.choreography(style,beat,"mara",1.0)
					# A fractional native beat interval and device latency can place
					# the nearest integer half-beat within two output samples. Even
					# the fastest sweep must remain within 1/50 of a game pixel.
					check(Vector2(pose.feet[0]).distance_to(exact.feet[0])<.02 and Vector2(pose.feet[1]).distance_to(exact.feet[1])<.02,"%s boots follow the sample-derived grid at%d BPM"%[style,tempo])
	for boundary in range(400):
		var beat := float(boundary)*.5
		check(is_equal_approx(Rhythm.snappy_beats(beat),beat),"faster motion never drifts at an eighth-note anchor")
		check(is_equal_approx(Rhythm.kick_accent(float(boundary)),1.0) and Rhythm.kick_accent(float(boundary)+.5)<.000001,"the continuous nod envelope peaks on every quarter-note kick")
	var epsilon := .00001
	var speed_gain := (Rhythm.snappy_beats(20.0+epsilon)-Rhythm.snappy_beats(20.0-epsilon))/(2.0*epsilon)
	check(speed_gain>1.249 and speed_gain<1.251,"articulation is 25 percent quicker at musical anchors without changing song tempo")
	check(Rhythm.choreography("breakdance",5.0).dance_stage=="floorwork" and Rhythm.choreography("breakdance",15.0).dance_stage=="toprock","breakdance drop and return finish sooner on complete beats")

	var fixture := VisualTest.Fixture.new()
	root.add_child(fixture)
	fixture.audio = VisualTest.AudioStub.new()
	fixture.add_child(fixture.audio)
	fixture.audio.live_music = VisualTest.MusicStub.new()
	fixture.audio.add_child(fixture.audio.live_music)
	var actor: Worker = preload("res://scenes/player.tscn").instantiate()
	actor.game = fixture
	actor.character_id = "mara"
	fixture.add_child(actor)
	_freeze(actor)
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	visual.idle_clock.wait_remaining = 1000
	var weapon: WorkerWeapon = actor.get_node("WorkerWeapon")
	weapon.aiming = true
	weapon.aim_direction = Vector2(1,-.3).normalized()
	var first_pose: Dictionary = {}
	for phase in 121:
		fixture.audio.live_music.state.phase = float(phase)/120.0
		fixture.audio.live_music.state.kick_count = phase+10
		fixture.audio.live_music.state.last_kick_seconds = float(phase)*.5
		fixture.audio.live_music.state.audible_seconds = float(phase)*.5
		fixture.audio.live_music.state.last_kick_strength = 1.0
		visual._process(.1)
		if first_pose.is_empty(): first_pose = visual.pose_skeleton.duplicate(true)
		check(visual.rhythm.weight==0.0 and not visual.pose_skeleton.has("dance_style"),"armed aiming refuses faster dance articulation")
		check(visual.pose_skeleton.hands==first_pose.hands and visual.pose_skeleton.feet==first_pose.feet,"changing the musical beat does not drift the armed pose")
	check(await Cleanup.free_scene(fixture,self),"beat-precision fixture releases cleanly")
	print("DANCE TIMING: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)
