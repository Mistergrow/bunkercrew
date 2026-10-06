extends SceneTree
## Real player rigs use character XP and the audible drum stream, without
## gallery metadata or disabling the ordinary idle-gesture clocks.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Infantry := preload("res://scripts/ground_infantry.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class MusicStub extends Node:
	var state := {"active":true,"phase":0.0,"beat":0,"bar":0,"audible_seconds":0.0,"last_kick_seconds":-1.0,"last_kick_strength":0.0,"kick_count":0,"beat_pulse":1.0,"accent_pulse":1.0,"motion_gain":1.0,"dance_intensity":1.0,"dance_profiles":{}}
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
	if not "--no-profile-save" in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save for dance gameplay verification")
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _heard(music: MusicStub, time: float, tempo: float = 118.0) -> void:
	var beats := time * tempo / 60.0
	music.state.merge({"active":true,"bar":floori(beats / 4.0),"beat":floori(beats) % 4,"phase":fposmod(beats, 1.0),"audible_seconds":time,"last_kick_seconds":floorf(beats) * 60.0 / tempo,"last_kick_strength":1.0,"kick_count":floori(beats) + 1,"genre":"minimal_techno"}, true)

func _prime(music: MusicStub, visual: WorkerVisual, begin: float) -> void:
	for tick in 90:
		_heard(music, begin + float(tick) / 30.0)
		visual._process(1.0 / 30.0)

func _run() -> void:
	InputSetup.install()
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.audio = AudioStub.new()
	fixture.add_child(fixture.audio)
	fixture.audio.live_music = MusicStub.new()
	fixture.audio.add_child(fixture.audio.live_music)
	var music := fixture.audio.live_music
	var melodic_state := music.state.duplicate(true)
	var actor_index := 0
	for character: String in Dance.IDS:
		var actor: Worker = preload("res://scenes/player.tscn").instantiate()
		actor.game = fixture
		actor.character_id = character
		actor.position = Vector2(actor_index * 110.0, 0)
		actor_index += 1
		fixture.add_child(actor)
		_freeze(actor)
		var visual: WorkerVisual = actor.get_node("PixelVisual")
		var collider: CollisionShape2D = actor.get_node("CollisionShape2D")
		var original_transform := actor.transform
		var original_shape := collider.shape
		var original_shape_size: Vector2 = collider.shape.size
		music.state = melodic_state.duplicate(true)
		visual._process(0.0)
		visual.idle_clock.begin("helmet")
		visual._process(0.05)
		check(visual.special_pose == "helmet" and visual.rhythm.weight == 0.0, character + " keeps its normal idle gesture during a melodic introduction")
		_heard(music, 0.08)
		visual._process(0.08)
		check(visual.special_pose.is_empty() and visual.idle_clock.gesture.is_empty() and visual.rhythm._reaction > 0.0, character + " responds to the first heard kick even when an idle gesture was active")
		_prime(music, visual, 0.1)
		check(visual.rhythm._dance_blend > 0.99 and visual.pose_skeleton.get("dance_style", "") in Dance.SHARED_STYLES, character + " actually dances with its level-one shared repertoire")
		var min_foot := Vector2(INF, INF)
		var max_foot := Vector2(-INF, -INF)
		var head_low := INF
		var head_high := -INF
		var interrupted := false
		for tick in 900:
			# Force the real cosmetic clock to be due. A gallery workaround would
			# instead postpone this indefinitely and miss the runtime conflict.
			visual.idle_clock.wait_remaining = 0.0
			_heard(music, 3.1 + float(tick) / 30.0)
			visual._process(1.0 / 30.0)
			interrupted = interrupted or not visual.special_pose.is_empty() or visual.rhythm._dance_blend < 0.99
			var pose: Dictionary = visual.pose_skeleton
			for foot: Vector2 in pose.feet:
				min_foot = Vector2(minf(min_foot.x, foot.x), minf(min_foot.y, foot.y))
				max_foot = Vector2(maxf(max_foot.x, foot.x), maxf(max_foot.y, foot.y))
			head_low = minf(head_low, float(pose.head_tilt))
			head_high = maxf(head_high, float(pose.head_tilt))
		check(not interrupted, character + " keeps thirty seconds of heard choreography without random idle interruptions")
		check(min_foot.distance_to(max_foot) > 10.0 and head_high - head_low > 0.025, character + " has readable leg travel and head movement on the audible beat")
		check(actor.transform == original_transform and actor.velocity == Vector2.ZERO and collider.shape == original_shape and collider.shape.size == original_shape_size, character + " choreography never moves the gameplay body or resizes its hitbox")
		check(not music.state.has("character_level") and not fixture.has_meta("dance_preview"), character + " uses actual progression without mutating the shared mixer frame")
		for index in Dance.UNLOCK_LEVELS.size():
			actor.progression.level = int(Dance.UNLOCK_LEVELS[index])
			var learned: String = Dance.UNIQUE_STYLES[character][index]
			music.state.dance_profiles = {character:{"style":learned,"intensity":1.0}}
			_heard(music, 34.0 + float(index))
			visual._process(0.5)
			check(visual.rhythm._movement == learned, character + " can use its own move at character level %d" % actor.progression.level)
		actor.progression.level = 1
		_heard(music, 40.0)
		visual._process(0.1)
		check(visual.rhythm._movement in Dance.SHARED_STYLES, character + " a saved locked preference cannot bypass character progression")
		music.state.dance_profiles = {}
		for action: String in preload("res://scripts/network_input.gd").ACTIONS:
			_prime(music, visual, 41.0)
			Input.action_press(actor.action(action))
			visual._process(0.0)
			check(visual.rhythm.weight == 0.0 and not visual.pose_skeleton.has("dance_style"), character + " immediately exits the dance on " + action)
			Input.action_release(actor.action(action))
		_prime(music, visual, 45.0)
		music.state.active = false
		visual.idle_clock.wait_remaining = 0.0
		visual._process(0.01)
		check(not visual.special_pose.is_empty() and visual.rhythm.weight == 0.0, character + " muted music releases the rig for ordinary idle gestures")
		_prime(music, visual, 49.0)
		music.state.dance_intensity = 0.0
		visual.idle_clock.wait_remaining = 0.0
		visual._process(0.01)
		check(not visual.special_pose.is_empty() and visual.rhythm.weight == 0.0, character + " disabling dance does not suppress ordinary character personality")
		music.state.dance_intensity = 1.0
		_prime(music, visual, 53.0)
		_heard(music, 58.0)
		music.state.last_kick_seconds = 54.0
		visual.idle_clock.wait_remaining = 0.0
		visual._process(0.01)
		check(not visual.special_pose.is_empty() and visual.rhythm.weight == 0.0, character + " a long drum break releases the idle rig")
		actor.progression.level = 10
		music.state.dance_profiles = {character:{"style":Dance.UNIQUE_STYLES[character][4],"intensity":1.0}}
		_prime(music, visual, 61.0)
		var last_painted: Dictionary = visual.pose_skeleton.duplicate(true)
		actor.velocity.x = 120.0
		visual._process(0.0)
		check(visual.rhythm.weight == 0.0 and not visual.pose_skeleton.has("dance_style") and visual.locomotion._transition.hip == last_painted.hip, character + " moving starts immediately and joins the last painted dance pose smoothly")
		check(visual.pose_skeleton.hip == last_painted.hip and visual.pose_skeleton.feet == last_painted.feet, character + " the first walking frame does not snap its dancing legs or torso")
		_heard(music, 65.0)
		visual._process(0.12)
		check(visual.locomotion.kind in ["walk","run"] and visual.rhythm.weight == 0.0 and visual.pose_skeleton.hip != last_painted.hip, character + " the short visual transition completes without delaying movement")
		actor.velocity = Vector2.ZERO

	var infantry = Infantry.new()
	infantry.game = fixture
	infantry.kind = "rifle_guard"
	infantry.position = Vector2(1800, 0)
	fixture.add_child(infantry)
	_freeze(infantry)
	infantry.gait = 1.4
	infantry.moving = true
	music.state.merge({"active":true,"last_kick_seconds":-1.0,"last_kick_strength":0.0,"accent_pulse":0.0}, true)
	infantry.infantry.update_pose()
	var baseline: Dictionary = infantry.infantry.pose.duplicate(true)
	var original_gun: Transform2D = infantry.infantry.gun
	music.state.accent_pulse = 1.0
	infantry.infantry.update_pose()
	check(infantry.infantry.pose == baseline, "a melodic instrument alone does not make an enemy nod as if a drum sounded")
	_heard(music, 60.02)
	infantry.infantry.update_pose()
	check(infantry.infantry.pose.head_shift.y > baseline.head_shift.y and infantry.infantry.pose.head_tilt < baseline.head_tilt, "hostile infantry reacts to the actual audible kick")
	check(infantry.infantry.pose.feet == baseline.feet and infantry.infantry.gun == original_gun and infantry.gait == 1.4, "enemy kick reactions preserve gun aim, contacts and actual travel")
	infantry.muzzle_flash = 0.1
	infantry.infantry.update_pose()
	check(is_zero_approx(float(infantry.infantry.pose.head_shift.y)), "firing takes priority over an enemy's beat reaction")
	check(await Cleanup.free_scene(fixture, self), "production player and infantry rigs release cleanly")
	print("DANCE GAMEPLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
