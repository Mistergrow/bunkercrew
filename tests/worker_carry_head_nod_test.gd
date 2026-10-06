extends SceneTree
## Actual loaded crew rigs: audible head-only accents preserve every load anchor.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const VisualTest := preload("res://tests/rhythm_visual_test.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const HEAD_KEYS := ["head_tilt", "head_shift", "head_pivot", "continuous"]
const LOADS := ["sand", "ore", "steel", "concrete", "ammo", "scrap"]
var checks := 0
var failures := 0
var max_handoff_pixels := 0.0
var max_handoff_radians := 0.0

func _initialize() -> void:
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

func _prime(music: Node, rig: WorkerVisual) -> void:
	for _index in 5:
		music.state.kick_count += 1
		music.state.last_kick_seconds = float(music.state.kick_count) * 0.55
		music.state.audible_seconds = music.state.last_kick_seconds + 0.12
		music.state.last_kick_strength = 1.0
		rig._process(0.55)

func _sample(music: Node, rig: WorkerVisual, phase: float) -> Dictionary:
	music.state.audible_seconds = float(music.state.last_kick_seconds) + phase * rig.rhythm._beat_period
	rig._process(0.0)
	return rig.pose_skeleton.duplicate(true)

func _non_head(pose: Dictionary) -> Dictionary:
	var result := pose.duplicate(true)
	for key: String in HEAD_KEYS:
		result.erase(key)
	return result

func _head_origin(pose: Dictionary, facing: float) -> Vector2:
	# The painted rig mirrors this transform for a left-facing worker.
	return PoseArt.head_transform(pose).origin * Vector2(facing, 1.0)

func _suppressed(rig: WorkerVisual, label: String) -> void:
	rig._process(0.0)
	check(rig.rhythm.weight == 0.0 and not rig.pose_skeleton.has("head_pivot"), label)

func _run() -> void:
	InputSetup.install()
	var fixture := VisualTest.Fixture.new()
	fixture.set_meta("dance_preview", true)
	root.add_child(fixture)
	fixture.audio = VisualTest.AudioStub.new()
	fixture.add_child(fixture.audio)
	fixture.audio.live_music = VisualTest.MusicStub.new()
	fixture.audio.add_child(fixture.audio.live_music)
	var music := fixture.audio.live_music
	var target := Node2D.new()
	fixture.add_child(target)
	for character: String in Dance.IDS:
		var actor: Worker = PlayerScene.instantiate()
		actor.game = fixture
		actor.character_id = character
		fixture.add_child(actor)
		_freeze(actor)
		var rig: WorkerVisual = actor.get_node("PixelVisual")
		rig.idle_clock.wait_remaining = 1000.0
		# A selected full-body move must become a head-only response with cargo.
		music.state.dance_profiles = {character: {"style": "crew_bounce", "intensity": 1.0}}
		for material: String in LOADS:
			actor.inventory = {material: actor.capacity()}
			actor.selected_kind = material
			for facing: float in [1.0, -1.0]:
				actor.facing = facing
				_prime(music, rig)
				check(actor.carried_count() == actor.capacity() and rig.pose_name == "carry_idle" and rig.rhythm.weight > 0.99, character + " waits with full " + material + " load facing " + str(facing))
				var fixture_neutral := _sample(music, rig, 0.0)
				var dip := _sample(music, rig, 0.09)
				check(float(dip.head_tilt) - float(fixture_neutral.head_tilt) > 0.17 and Vector2(dip.head_shift).y - Vector2(fixture_neutral.head_shift).y > 0.60, character + " visibly dips its head while holding " + material)
				check(_head_origin(dip, facing).distance_to(_head_origin(fixture_neutral, facing)) > 1.7, character + " moves the painted helmet more than a pixel in either facing direction")
				check(_non_head(dip) == _non_head(fixture_neutral), character + " preserves the exact torso, hands, feet, cargo and equipment on the kick")
				check(Vector2(dip.hands[0]) == Vector2(dip.cargo) + Vector2(-7, 0) and Vector2(dip.hands[1]) == Vector2(dip.cargo) + Vector2(5, 3), character + " keeps both gloves attached to the held " + material)
				check(rig.special_pose.is_empty() and not dip.has("dance_style") and not dip.has("elbows") and not dip.has("foot_angles"), character + " holds its load without a gesture, step or full-body dance")
				var neck := Vector2(0, 12)
				var neck_anchor := PoseArt.torso_transform(dip) * (Vector2(1, -15) + Vector2(dip.head_shift) + neck)
				check((PoseArt.head_transform(dip) * neck).distance_to(neck_anchor) < 0.0001, character + " keeps its nod attached at the neck")
				# Repeated render frames must not feed the visible nod back into gait.
				for phase in 41:
					var current := _sample(music, rig, float(phase) / 40.0)
					check(_non_head(current) == _non_head(fixture_neutral), character + " changes only head joints through the complete heard kick envelope")
				var returned := _sample(music, rig, 0.95)
				check(absf(float(returned.head_tilt) - float(fixture_neutral.head_tilt)) < 0.0001 and Vector2(returned.head_shift).is_equal_approx(fixture_neutral.head_shift), character + " returns between heard drums without accumulating a head offset")
				music.state.audible_seconds = float(music.state.last_kick_seconds) + 3.0
				rig._process(0.0)
				check(absf(float(rig.pose_skeleton.head_tilt) - float(fixture_neutral.head_tilt)) < 0.0001, character + " does not invent nods during a melodic drum rest")
		_prime(music, rig)
		rig.idle_clock.begin("helmet")
		rig._process(0.0)
		check(rig.special_pose.is_empty() and rig.idle_clock.gesture.is_empty() and rig.pose_skeleton.has("cargo"), character + " cancels an ordinary idle gesture when its arms hold cargo")
		var neutral := _sample(music, rig, 0.0)
		var normal := _sample(music, rig, 0.09)
		music.state.motion_gain = 0.22
		rig._process(2.0)
		var reduced := _sample(music, rig, 0.09)
		var full_angle := float(normal.head_tilt) - float(neutral.head_tilt)
		check(rig.rhythm.weight <= 0.22001 and float(reduced.head_tilt) > 0.0 and float(reduced.head_tilt) <= full_angle * 0.22001, character + " respects the existing reduced-motion amplitude")
		music.state.motion_gain = 0.0
		_suppressed(rig, character + " stops nodding when cosmetic motion is disabled")
		music.state.motion_gain = 1.0
		_prime(music, rig)
		music.state.active = false
		_suppressed(rig, character + " stops its load-bearing nod when music is muted")
		music.state.active = true
		music.state.dance_intensity = 0.0
		_suppressed(rig, character + " respects the dance intensity control with full arms")
		music.state.dance_intensity = 1.0
		music.state.dance_profiles[character].intensity = 0.0
		_suppressed(rig, character + " respects the individual character intensity control with full arms")
		music.state.dance_profiles[character].intensity = 1.0
		_prime(music, rig)
		for action: String in preload("res://scripts/network_input.gd").ACTIONS:
			Input.action_press(actor.action(action))
			_suppressed(rig, character + " preserves functional input priority for " + action)
			Input.action_release(actor.action(action))
			_prime(music, rig)
		actor.hurt_flash = 0.10
		_suppressed(rig, character + " damage suppresses the carry accent")
		actor.hurt_flash = 0.0
		actor.medical.bleeding = 1
		_suppressed(rig, character + " bleeding suppresses the carry accent")
		actor.medical.bleeding = 0
		actor.medical.fractured = true
		_suppressed(rig, character + " fracture suppresses the carry accent")
		actor.medical.fractured = false
		actor.hp = actor.max_hp * 0.50
		_suppressed(rig, character + " low health suppresses the carry accent")
		actor.hp = actor.max_hp
		_prime(music, rig)
		target.add_to_group("enemies")
		target.position = actor.position + Vector2(200, 0)
		_suppressed(rig, character + " a close enemy interrupts loaded waiting")
		target.remove_from_group("enemies")
		target.add_to_group("air_projectiles")
		_suppressed(rig, character + " nearby ordnance interrupts loaded waiting")
		target.remove_from_group("air_projectiles")
		_prime(music, rig)
		actor.focus = target
		actor._interacting = true
		_suppressed(rig, character + " actual work retains priority over music")
		check(rig.pose_name == "work", character + " work gate exercises the real work pose")
		actor._interacting = false
		actor.focus = null
		actor.pickup_animation = 0.25
		_suppressed(rig, character + " pickup retains its load-transfer animation")
		actor.pickup_animation = 0.0
		actor.drop_animation = 0.25
		_suppressed(rig, character + " dropping retains its load-transfer animation")
		actor.drop_animation = 0.0
		rig.crouched = true
		_suppressed(rig, character + " a low ceiling retains the crouched pose")
		rig.crouched = false
		actor._airborne = true
		actor.velocity.y = -100.0
		_suppressed(rig, character + " jumping retains the airborne pose")
		actor._airborne = false
		actor.velocity = Vector2.ZERO
		_prime(music, rig)
		_sample(music, rig, 0.09)
		var painted_head := PoseArt.head_transform(rig.pose_skeleton)
		var saved_inventory := actor.inventory.duplicate(true)
		actor.velocity.x = 100.0
		rig._process(0.0)
		check(rig.pose_name == "carry_walk" and rig.rhythm.weight == 0.0 and not rig.pose_skeleton.has("head_pivot"), character + " immediately changes from waiting nod to functional loaded walking")
		var after_move := PoseArt.head_transform(rig.pose_skeleton)
		max_handoff_pixels = maxf(max_handoff_pixels, after_move.origin.distance_to(painted_head.origin))
		max_handoff_radians = maxf(max_handoff_radians, absf(after_move.get_rotation() - painted_head.get_rotation()))
		# Loaded locomotion reapplies its rigid grip after the stance blend. Its
		# tiny shoulder rebrace stays below a third of a native pixel; the head
		# must retain its visible nod rather than jump upright on the first frame.
		check(after_move.origin.distance_to(painted_head.origin) < 0.30 and absf(after_move.get_rotation() - painted_head.get_rotation()) < 0.008, character + " preserves the visible head through the existing subpixel load rebrace")
		var phase := rig.locomotion.phase
		music.state.phase = 0.73
		rig._process(0.0)
		check(rig.locomotion.phase == phase and actor.inventory == saved_inventory and actor.velocity == Vector2(100, 0), character + " beat changes never retime gait or alter carried resources and movement")
		rig._process(0.14)
		check(rig.rhythm.weight == 0.0 and Vector2(rig.pose_skeleton.hands[0]) == Vector2(rig.pose_skeleton.cargo) + Vector2(-7, 0) and Vector2(rig.pose_skeleton.hands[1]) == Vector2(rig.pose_skeleton.cargo) + Vector2(5, 3), character + " keeps its functional load grip after the walking transition")
		actor.velocity = Vector2.ZERO
		actor.inventory.clear()
		_prime(music, rig)
		check(rig.pose_name == "idle" and rig.rhythm.weight > 0.99 and rig.pose_skeleton.has("dance_style") and not rig.pose_skeleton.has("cargo") and not rig.pose_skeleton.has("cargo_kind"), character + " cleanly returns to its unlocked full dance when its arms become free")
		actor.queue_free()
	check(await Cleanup.free_scene(fixture, self), "loaded head-nod fixture releases cleanly")
	print("CARRY HEAD HANDOFF MAX: %f native pixels, %f radians" % [max_handoff_pixels, max_handoff_radians])
	print("WORKER CARRY HEAD NOD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
