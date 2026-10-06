extends SceneTree
## Real crew rigs and enemy parts, plus bounded artistic preference validation.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Presentation := preload("res://scripts/rhythm_presentation.gd")
const Infantry := preload("res://scripts/ground_infantry.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class MusicStub extends Node:
	var state := {"active":true,"phase":0.25,"beat":0,"bar":0,"audible_seconds":0.0,"last_kick_seconds":-1.0,"last_kick_strength":0.0,"kick_count":0,"beat_pulse":1.0,"accent_pulse":1.0,"motion_gain":1.0,"dance_intensity":1.0,"dance_profiles":{}}
	func rhythm_frame() -> Dictionary:
		return state

class AudioStub extends Node:
	var live_music: MusicStub

class Fixture extends Node2D:
	var audio: AudioStub
	var player_count := 4

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func prime_kicks(music: MusicStub,visual: WorkerVisual) -> void:
	for index in 5:
		music.state.kick_count += 1
		music.state.last_kick_seconds = float(music.state.kick_count)*0.55
		music.state.audible_seconds = music.state.last_kick_seconds+0.12
		music.state.last_kick_strength = 1.0
		visual._process(0.55)

func _run() -> void:
	InputSetup.install()
	check(Dance.valid_profiles(Dance.defaults()), "All six defaults validate")
	for invalid in [{"unknown":{"style":"head_nod","intensity":1.0}}, {"mara":{"style":"invalid","intensity":1.0}}, {"mara":{"style":"head_nod","intensity":2.0}}, {"mara":{"style":"head_nod","intensity":NAN}}, {"mara":{"style":"head_nod"}}, []]:
		check(not Dance.valid_profiles(invalid), "Malformed feedback is rejected")
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.audio = AudioStub.new()
	fixture.add_child(fixture.audio)
	fixture.audio.live_music = MusicStub.new()
	fixture.audio.add_child(fixture.audio.live_music)
	var music := fixture.audio.live_music
	var signatures: Array = []
	var actors: Array[Worker] = []
	for id: String in Dance.IDS:
		var actor := Worker.new()
		actor.game = fixture
		actor.character_id = id
		fixture.add_child(actor)
		var fixture_visual := WorkerVisual.new()
		fixture_visual.name = "PixelVisual"
		actor.add_child(fixture_visual)
		_freeze(actor)
		actors.append(actor)
		fixture_visual.idle_clock.wait_remaining = 1000
		fixture_visual._process(0.0)
		fixture_visual._process(2.0)
		prime_kicks(music,fixture_visual)
		check(fixture_visual.rhythm.weight > 0.99, id + " rests into audible rhythm")
		var baseline := fixture_visual.locomotion_pose.duplicate(true)
		var trace: Array = []
		for phase in 61:
			music.state.phase = float(phase) / 60.0
			fixture_visual._process(0.0)
			var pose: Dictionary = fixture_visual.pose_skeleton
			check(pose.feet.all(func(foot): return foot.is_finite() and foot.y <= -2.999 and absf(foot.x) <= 36.0) and (is_equal_approx(pose.feet[0].y,-3.0) or is_equal_approx(pose.feet[1].y,-3.0)), id + " keeps visual steps finite, bounded and supported by the floor")
			check(pose.hip.is_finite() and pose.shoulder.is_finite() and pose.head_shift.is_finite(), id + " uses finite continuous torso anchors")
			trace.append([pose.hip-baseline.hip, pose.shoulder-baseline.shoulder, pose.head_tilt])
		signatures.append(trace)
		for action: String in preload("res://scripts/network_input.gd").ACTIONS:
			Input.action_press(actor.action(action))
			fixture_visual._process(0.0)
			check(fixture_visual.rhythm.weight == 0.0, id + " cancels immediately on " + action)
			Input.action_release(actor.action(action))
			fixture_visual._process(2.0)
		actor.hurt_flash = 0.10
		fixture_visual._process(0.0)
		check(fixture_visual.rhythm.weight == 0.0, id + " damage cancels motion immediately")
		actor.hurt_flash = 0.0
		actor.medical.bleeding = 1
		fixture_visual._process(2.0)
		check(fixture_visual.rhythm.weight == 0.0, id + " injury prevents rhythm motion")
		actor.medical.bleeding = 0
		actor.inventory = {"ore":1}
		fixture_visual._process(2.0)
		check(fixture_visual.rhythm.weight > 0.99 and fixture_visual.pose_skeleton.has("head_pivot") and not fixture_visual.pose_skeleton.has("dance_style") and fixture_visual.pose_skeleton.hands == [fixture_visual.pose_skeleton.cargo+Vector2(-7,0),fixture_visual.pose_skeleton.cargo+Vector2(5,3)], id + " carrying follows the kick with its head while preserving both cargo grips")
		actor.inventory.clear()
		actor.velocity.x = 100.0
		fixture_visual._process(0.1)
		var phase_before := fixture_visual.locomotion.phase
		music.state.phase = 0.73
		fixture_visual._process(0.0)
		check(fixture_visual.rhythm.weight == 0.0 and fixture_visual.locomotion.phase == phase_before, id + " audible beat never retimes locomotion")
		actor.velocity = Vector2.ZERO
		fixture_visual._process(2.0)
		music.state.active = false
		fixture_visual._process(0.0)
		check(fixture_visual.rhythm.weight == 0.0, id + " mute/fallback ends rhythm immediately")
		music.state.active = true
		music.state.motion_gain = 0.22
		fixture_visual._process(2.0)
		check(fixture_visual.rhythm.weight <= 0.22001, id + " reduced setting limits amplitude")
		music.state.motion_gain = 1.0
		for style: String in Dance.STYLES:
			if not Dance.owner(style).is_empty() and Dance.owner(style)!=id: continue
			music.state.dance_profiles = {id:{"style":style,"intensity":1.5}}
			music.state.dance_intensity = 1.5
			fixture_visual._process(2.0)
			prime_kicks(music,fixture_visual)
			for phase in 17:
				music.state.phase = float(phase) / 16.0
				fixture_visual._process(0.0)
				var pose: Dictionary = fixture_visual.pose_skeleton
				var torso := WorkerPoseArt.torso_transform(pose)
				check(pose.feet[0].y <= -2.999 and pose.feet[1].y <= -2.999 and (is_equal_approx(pose.feet[0].y,-3.0) or is_equal_approx(pose.feet[1].y,-3.0)), id + " " + style + " strongest dance stays in contact with the floor")
				check(pose.hands[0].distance_to(torso*WorkerPoseArt.shoulder_local(pose,0))<=23.0 and pose.hands[1].distance_to(torso*WorkerPoseArt.shoulder_local(pose,1))<=23.0,id+" "+style+" remains connected at maximum intensity")
		music.state.dance_profiles = {}
		music.state.dance_intensity = 1.0
	for first in signatures.size():
		for second in range(first+1, signatures.size()):
			check(signatures[first] != signatures[second], "Each character has a distinct default rhythm movement")
	var threat := Node2D.new()
	fixture.add_child(threat)
	threat.add_to_group("enemies")
	var visual: WorkerVisual = actors[0].get_node("PixelVisual")
	threat.position = actors[0].position + Vector2(200,0)
	visual._process(2.0)
	check(visual.rhythm.weight == 0.0, "Close enemies end safe waiting")
	threat.remove_from_group("enemies")
	threat.add_to_group("air_projectiles")
	visual._process(2.0)
	check(visual.rhythm.weight == 0.0, "Nearby ordnance ends safe waiting")
	threat.queue_free()
	var infantry = Infantry.new()
	infantry.kind = "rifle_guard"
	infantry.game = fixture
	infantry.position = Vector2(1600,0)
	fixture.add_child(infantry)
	_freeze(infantry)
	infantry.moving = true
	infantry.gait = 1.4
	infantry.infantry.update_pose()
	var feet_before: Array = infantry.infantry.pose.feet.duplicate()
	var gun_before: Transform2D = infantry.infantry.gun
	var health_before: float = infantry.hp
	music.state.accent_pulse = 0.0
	infantry.infantry.update_pose()
	check(infantry.infantry.pose.feet == feet_before and infantry.infantry.gun == gun_before and infantry.gait == 1.4 and infantry.hp == health_before, "Hostile accents preserve travel, gun aim, health and contact anchors")
	var machine := SiegeMachine.new()
	machine.kind = "battle_tank"
	machine.game = fixture
	machine.position = Vector2(1800,0)
	fixture.add_child(machine)
	_freeze(machine)
	var part_transform: Transform2D = machine.body_part.transform
	var leg_transform: Transform2D = machine.legs_part.transform
	music.state.accent_pulse = 1.0
	Presentation.machine_accent(machine)
	check(machine.body_part.self_modulate.r > 1.0 and machine.body_part.transform == part_transform and machine.legs_part.transform == leg_transform, "Tank accent changes existing vertex color only")
	music.state.active = false
	Presentation.machine_accent(machine)
	check(machine.body_part.self_modulate == Color.WHITE, "Tank original palette returns with music disabled")
	check(await Cleanup.free_scene(fixture,self), "Rhythm fixture releases cleanly")
	print("RHYTHM VISUALS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
