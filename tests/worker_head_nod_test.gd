extends SceneTree
## Actual audible event times, neck attachment, rests and functional rig safety.
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

func audible(clock: MusicBeatClock,seconds: float,events: Array=[]) -> Dictionary:
	clock.advance(roundi((seconds+0.061)*48000.0),48000,0.0,0.061,events)
	var frame := clock.frame()
	frame.motion_gain = 1.0
	frame.dance_intensity = 1.0
	frame.dance_profiles = {}
	return frame

func _run() -> void:
	InputSetup.install()
	for character: String in Dance.IDS:
		for fps: int in [30,60,144]:
			var clock := MusicBeatClock.new()
			clock.configure(130.0)
			var fixture_rhythm := Rhythm.new()
			fixture_rhythm.configure(character)
			var period := 60.0/130.0
			for tick in fps*3:
				var seconds := float(tick)/fps
				var events: Array = []
				var beat := floori(seconds/period)
				var previous := floori((seconds-1.0/fps)/period)
				if beat>previous:
					events.append({"sample":roundi(beat*period*48000),"track":0,"kind":"hit","strength":1.0})
				var frame := audible(clock,seconds,events)
				frame.dance_profiles = {character:{"style":"head_nod","intensity":1.0}}
				fixture_rhythm.advance(1.0/fps,true,frame)
			# An intentionally syncopated kick lies between the quarter-note grid.
			var actual_hit := 3.0+period*0.375
			var start := audible(clock,actual_hit,[{"sample":roundi(actual_hit*48000),"track":0,"kind":"hit","strength":1.0}])
			start.dance_profiles = {character:{"style":"head_nod","intensity":1.0}}
			fixture_rhythm.advance(0.0,true,start)
			var at_hit := PoseArt.neutral()
			fixture_rhythm.apply(at_hit,start)
			var after_hit := audible(clock,actual_hit+fixture_rhythm._beat_period*0.09)
			after_hit.dance_profiles = start.dance_profiles
			fixture_rhythm.advance(0.0,true,after_hit)
			var dip := PoseArt.neutral()
			fixture_rhythm.apply(dip,after_hit)
			check(dip.head_tilt-at_hit.head_tilt>0.17 and dip.head_shift.y-at_hit.head_shift.y>0.6,character+" has a readable smooth chin dip on the actual syncopated kick at %d FPS"%fps)
			var neck := Vector2(0,12)
			var body := PoseArt.torso_transform(dip)
			var attached := body*(Vector2(1,-15)+Vector2(dip.head_shift)+neck)
			check((PoseArt.head_transform(dip)*neck).distance_to(attached)<0.0001,character+" rotates around its attached neck at %d FPS"%fps)
			var rest := audible(clock,actual_hit+fixture_rhythm._beat_period*0.95)
			rest.dance_profiles = start.dance_profiles
			fixture_rhythm.advance(0.0,true,rest)
			var returned := PoseArt.neutral()
			fixture_rhythm.apply(returned,rest)
			check(absf(returned.head_tilt)<0.0001 and absf(returned.head_shift.y)<0.0001,character+" settles the head between real drums at %d FPS"%fps)
			for quiet_beat in 4:
				var empty := audible(clock,actual_hit+1.0+quiet_beat*period)
				empty.dance_profiles = start.dance_profiles
				fixture_rhythm.advance(period,true,empty)
				var quiet := PoseArt.neutral()
				fixture_rhythm.apply(quiet,empty)
				check(absf(quiet.head_tilt)<0.0001,character+" cannot nod on a melodic grid without another heard drum")
	# Optional dance neck pivots preserve every existing functional head pose.
	for kind: String in ["helmet","bandage_self","aid_revive","thoughtful"]:
		var pose := PoseArt.sample(kind,0.5)
		var body := PoseArt.torso_transform(pose)
		var legacy := Transform2D(body.get_rotation()+float(pose.head_tilt),body*(Vector2(1,-15)+Vector2(pose.head_shift)))
		check(PoseArt.head_transform(pose).is_equal_approx(legacy),kind+" retains its original functional head transform")
	var frozen := Rhythm.choreography("breakdance",12.0,"levin",1.0)
	var rhythm := Rhythm.new()
	rhythm.configure("levin")
	rhythm.weight = 1.5
	var preserved := frozen.duplicate(true)
	rhythm._apply_head_nod(frozen,{"audible_seconds":5.04,"last_kick_seconds":5.0,"last_kick_strength":1.0})
	check(frozen==preserved,"an actual loud kick preserves the supported breakdance freeze")

	var fixture := VisualTest.Fixture.new()
	fixture.set_meta("dance_preview",true) # Real lab contract permits quiet styles.
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
	var rig: WorkerVisual = actor.get_node("PixelVisual")
	rig.idle_clock.wait_remaining = 1000.0
	var music := fixture.audio.live_music
	music.state.dance_profiles = {"mara":{"style":"head_nod","intensity":1.0}}
	_prime_kicks(music,rig)
	check(rig.pose_skeleton.has("head_pivot") and rig.rhythm.weight>0.99,"actual idle worker rig paints the new neck-attached nod")
	for action: String in ["right","fire","down","interact"]:
		Input.action_press(actor.action(action))
		rig._process(0.0)
		check(rig.rhythm.weight==0.0 and not rig.pose_skeleton.has("head_pivot"),action+" immediately restores the functional head pose")
		Input.action_release(actor.action(action))
		_prime_kicks(music,rig)
	for style: String in ["head_nod","crew_bounce"]:
		music.state.dance_profiles = {"mara":{"style":style,"intensity":1.0}}
		_prime_kicks(music,rig)
		check(rig.pose_skeleton.has("head_pivot") and rig.pose_skeleton.has("dance_style")==bool(style=="crew_bounce"),style+" handoff fixture exercises its actual quiet/full-body branch")
		var painted_head := PoseArt.head_transform(rig.pose_skeleton)
		actor.velocity.x = 100.0
		rig._process(0.0)
		check(rig.rhythm.weight==0.0 and PoseArt.head_transform(rig.pose_skeleton).is_equal_approx(painted_head),"moving from "+style+" preserves the last painted head transform at the first locomotion frame")
		actor.velocity = Vector2.ZERO
		_prime_kicks(music,rig)
	music.state.active = false
	rig._process(0.0)
	check(rig.rhythm.weight==0.0 and not rig.pose_skeleton.has("head_pivot"),"muting real rig music cancels the neck accent immediately")
	check(await Cleanup.free_scene(fixture,self),"head-nod fixture releases cleanly")
	print("WORKER HEAD NOD: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _prime_kicks(music: Node,rig: WorkerVisual) -> void:
	for index in 5:
		music.state.kick_count += 1
		music.state.last_kick_seconds = float(music.state.kick_count)*0.55
		music.state.audible_seconds = music.state.last_kick_seconds+0.12
		music.state.last_kick_strength = 1.0
		rig._process(0.55)
