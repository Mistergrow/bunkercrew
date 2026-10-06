extends RefCounted
## Draw-only choreography for the original wheeled medical assistant. Entry is
## gated by native, audible kick events; shared simulation decides if it is idle.
const Catalog := preload("res://scripts/medic_dance_catalog.gd")
const EquipmentArt := preload("res://scripts/support_equipment_art.gd")
const Presentation := preload("res://scripts/rhythm_presentation.gd")
const SETTLE_SECONDS := 0.32
const ENTER_SECONDS := 0.24
const TRANSITION_BEATS := 0.5
var weight := 0.0
var software_level := 0
var style := ""
var pose: Dictionary = {}
var _idle_seconds := 0.0
var _last_count := -1
var _last_kick := -1.0
var _heard_kicks := 0
var _period := 0.5
var _previous_pose: Dictionary = {}
var _transition_beat := -INF

func clear() -> void:
	weight = 0.0
	style = ""
	pose.clear()
	_idle_seconds = 0.0
	_last_count = -1
	_last_kick = -1.0
	_heard_kicks = 0
	_previous_pose.clear()
	_transition_beat = -INF

func is_active() -> bool:
	return weight > 0.0 and not pose.is_empty()

func state() -> Dictionary:
	return {"active":is_active(), "style":style, "level":software_level, "weight":weight, "heard_kicks":_heard_kicks, "pose":pose.duplicate(true)}

func advance(delta: float, allowed: bool, frame: Dictionary, level: int) -> bool:
	software_level = clampi(level, 0, Catalog.MAX_LEVEL)
	var was_active := is_active()
	var dance_gain := clampf(float(frame.get("dance_intensity", 1.0)), 0.0, 1.5)
	var music_gain := Presentation.gain(frame)
	# Reduced motion leaves the complete normal standby rig in place. A stop,
	# cargo pickup or medical task releases this drawing in the same frame.
	if not allowed or software_level <= 0 or bool(frame.get("reduced_motion", false)) or not is_finite(music_gain) or not is_finite(dance_gain) or music_gain <= 0.0 or dance_gain <= 0.0:
		clear()
		return was_active
	var now := float(frame.get("audible_seconds", -1.0))
	var kick := float(frame.get("last_kick_seconds", -1.0))
	var strength := float(frame.get("last_kick_strength", 0.0))
	var count := int(frame.get("kick_count", 0))
	if not is_finite(now) or not is_finite(kick) or not is_finite(strength) or now < 0.0 or kick < 0.0 or now < kick or count <= 0 or strength < 0.35:
		clear()
		return was_active
	if count < _last_count or kick < _last_kick:
		clear()
	if count != _last_count:
		if _last_kick >= 0.0 and kick > _last_kick:
			_period = clampf(kick - _last_kick, 0.30, 1.0)
		# On entry/rejoin a large historical kick count represents only the
		# latest kick, never a backlog that would immediately start a dance.
		_heard_kicks += 1 if _last_count < 0 else clampi(count - _last_count, 0, 2)
		_last_count = count
		_last_kick = kick
	_period = Presentation.beat_period(frame,_period)
	if now - kick > _period * 1.8:
		clear()
		return was_active
	var dt := maxf(0.0, delta) if is_finite(delta) else 0.0
	_idle_seconds += dt
	if _heard_kicks < 2:
		weight = 0.0
		pose.clear()
		return was_active
	weight = smoothstep(SETTLE_SECONDS, SETTLE_SECONDS + ENTER_SECONDS, _idle_seconds) * music_gain * dance_gain
	var beats := audible_beats(frame)
	var selected := Catalog.style_for(software_level, beats)
	if selected != style:
		_previous_pose = pose.duplicate(true) if is_active() else {}
		_transition_beat = beats
		style = selected
	var age := now - kick
	var target := choreography(style, beats, age, _period, strength, minf(weight, 1.5))
	if not _previous_pose.is_empty():
		var progress := smoothstep(0.0, TRANSITION_BEATS, maxf(0.0, beats - _transition_beat))
		target = mix_pose(_previous_pose, target, progress)
		if progress >= 1.0:
			_previous_pose.clear()
	pose = target if weight > 0.0 else {}
	return was_active or is_active()

static func audible_beats(frame: Dictionary) -> float:
	var beats := float(maxi(0, int(frame.get("bar", 0)))) * 4.0 + float(maxi(0, int(frame.get("beat", 0)))) + float(frame.get("phase", 0.0))
	return maxf(0.0, beats) if is_finite(beats) else 0.0

static func neutral() -> Dictionary:
	return {"body_offset":Vector2.ZERO, "body_angle":0.0, "track_offset":Vector2.ZERO, "track_angle":0.0, "track_phase":0.0, "head_drop":0.0, "look":3.0, "elbow":Vector2(19,-19), "hand":Vector2(19,-11)}

static func kick_nod(age: float, period: float) -> float:
	if age < 0.0 or not is_finite(age) or not is_finite(period):
		return 0.0
	var phase := age / clampf(period, 0.25, 1.5)
	if phase < 0.12:
		return smoothstep(0.0, 0.12, phase)
	return 1.0 - smoothstep(0.12, 0.60, phase)

static func choreography(move: String, beats: float, kick_age: float, period: float, strength: float = 1.0, amount: float = 1.0) -> Dictionary:
	var result := neutral()
	if move not in Catalog.STYLES or not is_finite(beats):
		return result
	amount = clampf(amount, 0.0, 1.5) if is_finite(amount) else 0.0
	var pulse := kick_nod(kick_age, period) * clampf(strength, 0.0, 1.0)
	var swing := sin(beats * PI)
	var eighth := sin(beats * TAU)
	var slow := sin(beats * PI * 0.5)
	result.head_drop = pulse * 2.8
	match move:
		"san_kick_nod":
			result.body_offset = Vector2(0, pulse * 0.75)
			result.elbow = Vector2(19 + pulse * 2, -20 - pulse * 2)
			result.hand = Vector2(21 + pulse, -12 - pulse * 2)
		"san_servo_lock":
			# Short travel and an explicit hold around each beat resemble actual
			# servo stops. Smooth easing retains continuity at every boundary.
			var lock := sin((beats + sin(beats * TAU) * 0.09) * PI)
			result.body_angle = lock * 0.065
			result.body_offset = Vector2(lock * 1.8, pulse)
			result.elbow = Vector2(18 + lock * 4, -30 - pulse * 2)
			result.hand = Vector2(23 + lock * 5, -37 + lock * 4)
			result.look = 3 + lock * 2.0
		"san_track_shuffle":
			# Alternating tread accents are paint-only. Neither the chassis
			# collider nor its authoritative home position rolls away.
			result.track_angle = swing * 0.045
			result.track_offset = Vector2(swing * 1.8, -absf(swing) * 0.5)
			result.track_phase = beats * 3.0 + swing * 2.0
			result.body_offset = Vector2(-swing * 2.4, pulse * 0.9)
			result.body_angle = -swing * 0.065
			result.elbow = Vector2(18 - swing * 4, -25 + eighth * 3)
			result.hand = Vector2(23 - swing * 6, -24 - eighth * 6)
		"san_arm_wave":
			var wave := beats * PI * 0.5
			result.body_angle = slow * 0.075
			result.body_offset = Vector2(slow * 1.0, pulse * 0.55)
			result.elbow = Vector2(15 + cos(wave) * 6, -31 + sin(wave) * 5)
			result.hand = Vector2(22 + cos(wave - 0.7) * 7, -38 + sin(wave - 0.7) * 7)
			result.look = 3 + cos(wave - 0.7) * 2.6
		"san_bunker_freeze":
			# An eight-beat compressor dip, overhead lock and return. The hold
			# occupies two full beats without replaying an unrelated timer.
			var phase := fposmod(beats, 8.0)
			var lock := smoothstep(0.5, 2.0, phase) * (1.0 - smoothstep(4.0, 6.0, phase))
			var dip := smoothstep(5.0, 6.0, phase) * (1.0 - smoothstep(6.0, 7.5, phase))
			result.body_angle = -lock * 0.13
			result.body_offset = Vector2(-lock * 2, dip * 2.5 + pulse * 0.4)
			result.elbow = Vector2(19, -19).lerp(Vector2(16, -35), lock)
			result.hand = Vector2(19, -11).lerp(Vector2(3, -43), lock)
			result.look = 3 - lock * 5
			result.head_drop = pulse * 2.0 + dip
	for key: String in ["body_offset", "track_offset"]:
		result[key] *= amount
	for key: String in ["body_angle", "track_angle", "head_drop", "track_phase"]:
		result[key] *= amount
	result.look = lerpf(3.0, float(result.look), amount)
	result.elbow = Vector2(19, -19).lerp(result.elbow, amount)
	result.hand = Vector2(19, -11).lerp(result.hand, amount)
	# Preserve two believable mechanical link lengths at extreme user gain.
	var shoulder := Vector2(13, -22)
	result.elbow = shoulder + (Vector2(result.elbow) - shoulder).limit_length(17.0)
	result.hand = result.elbow + (Vector2(result.hand) - Vector2(result.elbow)).limit_length(19.0)
	return result

static func mix_pose(from: Dictionary, to: Dictionary, blend: float) -> Dictionary:
	var result := neutral()
	for key: String in result:
		if result[key] is Vector2:
			result[key] = Vector2(from[key]).lerp(Vector2(to[key]), blend)
		else:
			result[key] = lerpf(float(from[key]), float(to[key]), blend)
	return result

func draw(canvas: Node2D, supplies: int, facing: float) -> bool:
	if not is_active():
		return false
	canvas.draw_rect(Rect2(-18, -1, 36, 4), Color(0, 0, 0, 0.32))
	var direction := -1.0 if facing < 0.0 else 1.0
	var track_at: Vector2 = pose.track_offset
	canvas.draw_set_transform(track_at, float(pose.track_angle))
	EquipmentArt.tracks(canvas, float(pose.track_phase))
	var angle := float(pose.body_angle) * direction
	var pivot := Vector2(0, -12)
	var body_at: Vector2 = pose.body_offset
	body_at.x *= direction
	canvas.draw_set_transform(body_at + pivot - pivot.rotated(angle), angle)
	EquipmentArt.medic_body(canvas, 0.0, float(pose.look) * direction, supplies, false, float(pose.head_drop))
	var shoulder := Vector2(13 * direction, -22)
	var elbow: Vector2 = pose.elbow
	var hand: Vector2 = pose.hand
	elbow.x *= direction
	hand.x *= direction
	EquipmentArt.linkage(canvas, shoulder, elbow, 3)
	EquipmentArt.linkage(canvas, elbow, hand, 3)
	EquipmentArt.joint(canvas, elbow)
	EquipmentArt.casing(canvas, Rect2(hand - Vector2(3, 2), Vector2(7, 5)), Color("929980"), 1)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
