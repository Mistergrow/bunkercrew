extends RefCounted
## Cosmetic, beat-clock choreography for the existing articulated crew rig.
## Steps, floor work and freezes move painted joints only; action cancels now.
const Presentation := preload("res://scripts/rhythm_presentation.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Catalog := preload("res://scripts/worker_dance_catalog.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Moves := preload("res://scripts/worker_dance_moves.gd")
const PROFILES := {
	"mara": {"sway": 0.35, "shoulder": 0.65, "bounce": 0.65, "nod": 0.040, "wrist": 0.35, "offset": 0.0},
	"branko": {"sway": 0.75, "shoulder": 1.10, "bounce": 0.38, "nod": 0.020, "wrist": 0.45, "offset": 0.12},
	"ivo": {"sway": 0.42, "shoulder": 0.45, "bounce": 0.80, "nod": 0.035, "wrist": 1.25, "offset": 0.05},
	"nora": {"sway": 0.65, "shoulder": -0.75, "bounce": 0.28, "nod": 0.025, "wrist": 0.60, "offset": 0.18},
	"levin": {"sway": 0.55, "shoulder": 0.95, "bounce": 0.52, "nod": 0.050, "wrist": 0.90, "offset": 0.08},
	"selma": {"sway": 0.82, "shoulder": 0.55, "bounce": 0.22, "nod": 0.024, "wrist": 0.50, "offset": 0.22},
	"oskar": {"sway": 0.48, "shoulder": 0.96, "bounce": 0.42, "nod": 0.032, "wrist": 0.38, "offset": 0.15},
	"rika": {"sway": 0.58, "shoulder": 0.72, "bounce": 0.72, "nod": 0.043, "wrist": 1.06, "offset": 0.07},
}
const SETTLE_SECONDS := 0.16
const ENTER_SECONDS := 0.36
const REACTION_DELAY := {"mara":0.022,"branko":0.041,"ivo":0.030,"nora":0.047,"levin":0.016,"selma":0.037,"oskar":0.044,"rika":0.025}
var character_id := "mara"
var idle_seconds := 0.0
var weight := 0.0
var _profile: Dictionary = PROFILES.mara
var _style := "character_default"
var _movement := "shuffle"
var _last_kick_count := -1
var _last_kick_seconds := -1.0
var _heard_kicks := 0.0
var _dance_blend := 0.0
var _reaction := 0.0
var _beat_period := 0.55
var _transition_pose: Dictionary = {}
var _transition_beat := -INF
const TRANSITION_BEATS := .5

func configure(id: String) -> void:
	character_id = id
	_profile = PROFILES.get(CharacterCatalog.presentation_id(id,"dance"), PROFILES.mara)
	_style = "character_default"
	_movement = Catalog.DEFAULT_STYLES.get(id,"shuffle")
	reset()

func reset() -> void:
	idle_seconds = 0.0
	weight = 0.0
	_last_kick_count = -1
	_last_kick_seconds = -1.0
	_heard_kicks = 0.0
	_dance_blend = 0.0
	_reaction = 0.0
	_transition_pose.clear()
	_transition_beat = -INF

func follows_kicks(frame: Dictionary) -> bool:
	# Idle fidgets must not repeatedly replace a dance that the player is
	# actually hearing. A melodic grid, mute or an old kick does not reserve
	# the rig, so the normal character gestures still play during quiet music.
	var profile: Dictionary = frame.get("dance_profiles", {}).get(character_id, {})
	var dance_gain := float(frame.get("dance_intensity", 1.0)) * float(profile.get("intensity", 1.0))
	if Presentation.gain(frame) <= 0.0 or not is_finite(dance_gain) or dance_gain <= 0.0:
		return false
	var kick_time := float(frame.get("last_kick_seconds", -1.0))
	var age := float(frame.get("audible_seconds", 0.0)) - kick_time
	return kick_time >= 0.0 and age >= 0.0 and age <= Presentation.beat_period(frame,_beat_period) * 2.3 and float(frame.get("last_kick_strength", 0.0)) >= 0.35

func advance(delta: float, allowed: bool, frame: Dictionary) -> float:
	var music_gain := Presentation.gain(frame)
	var profile: Dictionary = frame.get("dance_profiles", {}).get(character_id, {})
	var style := str(profile.get("style", "character_default"))
	if style != _style:
		_style = style
		_profile = Catalog.MOVEMENTS.get(style, PROFILES.get(CharacterCatalog.presentation_id(character_id,"dance"), PROFILES.mara))
	var genre := str(frame.get("genre","minimal_techno"))
	var selected := Catalog.resolve_style(character_id,_style,genre,maxi(1,int(frame.character_level)),floori(maxf(0,float(frame.get("bar",0)))/4.0),bool(frame.get("dance_preview",false))) if frame.has("character_level") else Catalog.character_style(character_id,genre) if _style=="character_default" else _style
	if selected!=_movement:
		if _dance_blend>0 and _movement in Catalog.FULL_BODY_STYLES:
			_transition_beat = _audible_beats(frame)
			_transition_pose = choreography(_movement,_transition_beat,character_id,clampf(weight,1.0,1.5))
		else:
			_transition_pose.clear()
		_movement = selected
	var requested_gain := float(frame.get("dance_intensity", 1.0)) * float(profile.get("intensity", 1.0))
	var dance_gain := clampf(requested_gain, 0.0, 1.5) if is_finite(requested_gain) else 0.0
	if _style=="character_default" and str(frame.get("genre",""))=="schranz":
		dance_gain = minf(dance_gain*1.16,1.5)
	music_gain *= dance_gain
	if not allowed or music_gain <= 0.0:
		reset()
		return 0.0
	idle_seconds += maxf(0.0, delta)
	weight = smoothstep(SETTLE_SECONDS, SETTLE_SECONDS + ENTER_SECONDS, idle_seconds) * music_gain
	var now := float(frame.get("audible_seconds",0.0))
	var kick_time := float(frame.get("last_kick_seconds",-1.0))
	var kick_strength := clampf(float(frame.get("last_kick_strength",0.0)),0.0,1.0)
	var kick_count := int(frame.get("kick_count",0))
	if not is_finite(now) or not is_finite(kick_time) or not is_finite(kick_strength) or now<0.0:
		reset()
		return 0.0
	if kick_count<_last_kick_count or kick_time<_last_kick_seconds:
		# A seek or isolated preview restart begins a new audible kick stream.
		_last_kick_count = -1
		_last_kick_seconds = -1.0
		_heard_kicks = 0.0
		_dance_blend = 0.0
		_transition_pose.clear()
		_transition_beat = -INF
	if kick_count != _last_kick_count:
		var fresh := kick_time>=0.0 and now>=kick_time and now-kick_time<0.6
		var newly_heard := 1 if _last_kick_count<0 else clampi(kick_count-_last_kick_count,0,4)
		if fresh and kick_strength>=0.35:
			_heard_kicks += float(newly_heard)*kick_strength
		if _last_kick_seconds>=0.0 and kick_time>_last_kick_seconds:
			_beat_period = clampf(kick_time-_last_kick_seconds,0.30,1.0)
		_last_kick_count = kick_count
		_last_kick_seconds = kick_time
	_beat_period = Presentation.beat_period(frame,_beat_period)
	var delayed_age := now-kick_time-float(REACTION_DELAY.get(CharacterCatalog.presentation_id(character_id,"dance"),0.06))
	_reaction = exp(-delayed_age/0.14)*kick_strength if kick_time>=0.0 and delayed_age>=0.0 else 0.0
	var readiness := smoothstep(1.7,3.8,_heard_kicks)
	if kick_time<0.0 or now-kick_time>_beat_period*2.3:
		readiness = 0.0
		_heard_kicks = 0.0
	_dance_blend = move_toward(_dance_blend,readiness,maxf(0.0,delta)*2.75)
	return weight

func apply(pose: Dictionary, frame: Dictionary) -> void:
	if weight <= 0.0 or pose.is_empty():
		return
	if _movement in Catalog.FULL_BODY_STYLES:
		if _dance_blend>0.0:
			_apply_choreography(pose,frame)
		else:
			_apply_reaction(pose,frame)
		_apply_head_nod(pose,frame)
		return
	if _dance_blend<=0.0:
		_apply_reaction(pose,frame)
		_apply_head_nod(pose,frame)
		return
	var amount := weight*_dance_blend
	var beats := _audible_beats(frame)
	var articulated_beat := snappy_beats(beats)
	var beat := articulated_beat*TAU
	var offset := float(_profile.offset) * TAU
	var sway := sin(articulated_beat*PI+offset)
	var pulse := kick_accent(beats)
	var delayed := sin(beat - 0.30 + offset)
	var bounce := pulse * float(_profile.bounce) * amount
	pose.hip += Vector2(sway * float(_profile.sway) * amount, bounce)
	pose.shoulder += Vector2(delayed * float(_profile.shoulder) * amount, bounce * 0.80)
	# Secondary sway retains each character's temperament. The head follows
	# actual heard kick events below, including off-grid kicks and drum rests.
	pose.head_shift.x += sway * 0.20 * amount
	# Wrists follow a relaxed forearm; no new props, detached gloves or lifted
	# boots. Half-beat accents give Ivo a recognizable nervous finger rhythm.
	var wrist := float(_profile.wrist) * amount
	var hand_pulse := sin(beat * (2.0 if CharacterCatalog.presentation_id(character_id,"dance") == "ivo" or _style == "hand_tap" else 1.0) + offset)
	pose.hands[0] += Vector2(sway * 0.25, hand_pulse * wrist)
	pose.hands[1] += Vector2(-sway * 0.20, -hand_pulse * wrist * 0.72)
	pose.continuous = true
	var torso := PoseArt.torso_transform(pose)
	for index in 2:
		var root := torso*PoseArt.shoulder_local(pose,index)
		var reach: Vector2 = Vector2(pose.hands[index]) - root
		if reach.length() > 22.9:
			pose.hands[index] = root + reach.normalized() * 22.9
	_apply_head_nod(pose,frame)
	# Quiet styles retain the standing contact anchors.

func _apply_reaction(pose: Dictionary,frame: Dictionary) -> void:
	# The melodic introduction gets a breath and a real kick response, never
	# a fabricated four-on-the-floor signal from the regular music grid.
	var breath := sin(float(frame.get("audible_seconds",0.0))*1.5+float(_profile.offset)*TAU)
	pose.shoulder += Vector2(breath*0.06,_reaction*float(_profile.shoulder)*0.45)*weight
	pose.head_shift.y += breath*0.08*weight
	pose.continuous = true

func apply_carry_nod(pose: Dictionary,frame: Dictionary) -> void:
	# Busy hands keep their exact cargo grips. Only the free head follows the
	# heard kick; body choreography and idle gestures never move the load.
	if weight <= 0.0 or pose.is_empty():
		return
	_apply_head_nod(pose,frame,true)

func _apply_head_nod(pose: Dictionary,frame: Dictionary,head_only: bool = false) -> void:
	var kick_time := float(frame.get("last_kick_seconds",-1.0))
	var strength := clampf(float(frame.get("last_kick_strength",0.0)),0.0,1.0)
	if kick_time<0.0 or strength<0.35:
		return
	# A small, quick chin dip and a slower return read as a human nod. Sampling
	# the heard event age keeps the same pose at 30/60/144 FPS; a missing drum
	# never fabricates another nod from the regular musical grid.
	var age := float(frame.get("audible_seconds",0.0))-kick_time
	var nod := head_nod_envelope(age,_beat_period)*strength
	var body_lean := absf(PoseArt.torso_transform(pose).get_rotation())
	var standing := smoothstep(16.0,21.0,-float(pose.hip.y))*(1.0-smoothstep(0.45,0.95,body_lean))
	var amount := weight*standing
	if amount<=0.0:
		return # Floor work and held freezes keep their authored head/support pose.
	var angle := 0.20 if head_only or _movement=="head_nod" else 0.12+float(PROFILES.get(CharacterCatalog.presentation_id(character_id,"dance"),PROFILES.mara).nod)
	pose.head_tilt += nod*angle*amount
	pose.head_shift += Vector2(nod*0.20,nod*0.80)*amount
	# The clean head textures are anchored at the helmet. Rotate about the
	# neck instead, keeping the face attached to the coat during the accent.
	pose.head_pivot = Vector2(0,12)*standing
	pose.continuous = true

static func head_nod_envelope(age: float,period: float) -> float:
	if age<0.0 or not is_finite(age) or not is_finite(period):
		return 0.0
	var phase := age/clampf(period,0.25,1.5)
	if phase<0.09:
		return smoothstep(0.0,0.09,phase)
	if phase<0.58:
		return 1.0-smoothstep(0.09,0.58,phase)
	if phase<0.82:
		return -0.10*pow(sin((phase-0.58)/0.24*PI),2.0)
	return 0.0

func _apply_choreography(pose: Dictionary,frame: Dictionary) -> void:
	# The individual delay belongs to the first human reaction, not to steps.
	# Once dancing, contacts and freezes use the audible sample-derived grid.
	var beats := _audible_beats(frame)
	# Below full intensity the authored pose is blended once. Scaling its
	# steps as well made a 50% setting only show 25% of the boot travel.
	var target := choreography(_movement,beats,character_id,clampf(weight,1.0,1.5))
	if not _transition_pose.is_empty():
		var progress := clampf((beats-_transition_beat)/TRANSITION_BEATS,0,1)
		if progress>=1.0:
			_transition_pose.clear()
		else:
			# Passing through a planted stance prevents two opposing lifted feet
			# from blending into an unsupported pose at a repertoire change.
			var planted := PoseArt.neutral()
			planted.foot_angles = [0.0,0.0]
			target = _mix(_transition_pose,planted,progress*2.0) if progress<.5 else _mix(planted,target,(progress-.5)*2.0)
			target.dance_stage = "step_change"
			_constrain(target)
	var blend := minf(weight,1.0)*_dance_blend
	var original_elbows: Array[Vector2] = []
	if target.has("elbows") and blend<1.0:
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			original_elbows.append(_elbow(body*PoseArt.shoulder_local(pose,index),pose.hands[index]))
	for key: String in ["hip","shoulder","head_shift"]:
		pose[key] = Vector2(pose[key]).lerp(Vector2(target[key]),blend)
	for key: String in ["feet","hands"]:
		for index in 2:
			pose[key][index] = Vector2(pose[key][index]).lerp(Vector2(target[key][index]),blend)
	pose.head_tilt = lerpf(float(pose.head_tilt),float(target.head_tilt),blend)
	pose.hip_spread = lerpf(float(pose.get("hip_spread",4.0)),float(target.get("hip_spread",4.0)),blend)
	pose.foot_angles = [float(target.foot_angles[0])*blend,float(target.foot_angles[1])*blend]
	if target.has("elbows"):
		pose.elbows = target.elbows if blend>=1.0 else [original_elbows[0].lerp(target.elbows[0],blend),original_elbows[1].lerp(target.elbows[1],blend)]
	pose.dance_style = _movement
	pose.dance_stage = target.get("dance_stage","standing")
	pose.continuous = true
	if blend<1.0:
		_constrain(pose)

static func _audible_beats(frame: Dictionary) -> float:
	return maxf(0.0,float(frame.get("bar",0)))*4.0+maxf(0.0,float(frame.get("beat",0)))+float(frame.get("phase",0.0))

static func snappy_beats(beats: float) -> float:
	# Increase instantaneous movement speed by 25% near each eighth-note
	# anchor, then ease the middle of the swing. Every quarter/eighth anchor
	# remains exact: multiplying the whole timeline would drift off the music.
	var eighth_phase := fposmod(beats*2.0,1.0)
	return beats+sin(eighth_phase*TAU)*(0.125/TAU)

static func kick_accent(beats: float) -> float:
	# Continuous compression has its maximum at the actual kick, rather than
	# half a beat after it. No discontinuous event envelope snaps painted joints.
	return pow((1.0+cos(beats*TAU))*.5,2.0)

static func _body(pose: Dictionary,hip: Vector2,lean: float) -> void:
	pose.hip = hip
	pose.shoulder = hip+Vector2(sin(lean),-cos(lean))*17.0
	pose.head_tilt = -lean*0.62
	pose.head_shift = Vector2.ZERO

static func _elbow(root: Vector2,hand: Vector2) -> Vector2:
	# Entry/exit blends can bring a glove almost onto its shoulder. Share the
	# reachable fold limit while retaining the authored bend and float motion.
	return PoseArt.joint_position(root,hand,11.0,12.0,1.0)

static func _arm(pose: Dictionary,index: int,upper: float,forearm: float) -> void:
	var body := PoseArt.torso_transform(pose)
	var root := body*PoseArt.shoulder_local(pose,index)
	if not pose.has("elbows"):
		pose.elbows = [Vector2.ZERO,Vector2.ZERO]
	pose.elbows[index] = root+Vector2(cos(upper),sin(upper))*11.0
	pose.hands[index] = pose.elbows[index]+Vector2(cos(forearm),sin(forearm))*11.7

static func _circle_entry(point: Vector2,target: Vector2,center: Vector2,radius: float) -> float:
	# The target is inside the circle. Return the first point along this
	# segment that is also inside, so a tiny excess makes a tiny correction.
	var offset := point-center
	var excess := offset.length_squared()-radius*radius
	if excess<=0.0: return 0.0
	var travel := target-point
	var squared := travel.length_squared()
	if squared<.000001: return 1.0
	var along := 2.0*offset.dot(travel)
	return clampf((-along-sqrt(maxf(0.0,along*along-4.0*squared*excess)))/(2.0*squared),0.0,1.0)

static func _bounded_elbow(attachment: Vector2,hand: Vector2,hint: Vector2) -> Vector2:
	var target := _elbow(attachment,hand)
	if not hint.is_finite(): return target
	# Keep valid authored joints. Outside either reach circle, move only as
	# far as necessary toward one stable pole; choosing the nearest pole used
	# to flip a blended elbow across the body while its hand hardly moved.
	var amount := maxf(_circle_entry(hint,target,attachment,11.30),_circle_entry(hint,target,hand,12.05))
	return hint.lerp(target,amount)

static func _constrain(pose: Dictionary) -> void:
	# Existing legs have 12+12 pixels of reach. Shorten a visual step rather
	# than stretching the shin; the physics body never receives these values.
	var spread := float(pose.get("hip_spread",4.0))
	for index in 2:
		var root: Vector2 = pose.hip+Vector2(-spread if index==0 else spread,0)
		var foot: Vector2 = pose.feet[index]
		var offset := foot-root
		if offset.length()>23.8:
			var vertical := clampf(foot.y-root.y,-23.8,23.8)
			var horizontal := sqrt(maxf(0.0,23.8*23.8-vertical*vertical))
			foot.x = root.x+clampf(offset.x,-horizontal,horizontal)
		foot.y = minf(foot.y,-3.0)
		pose.feet[index] = foot
	var torso := PoseArt.torso_transform(pose)
	for index in 2:
		var root := torso*PoseArt.shoulder_local(pose,index)
		var reach: Vector2 = pose.hands[index]-root
		if reach.length()>22.9:
			pose.hands[index] = root+reach.normalized()*22.9
		if pose.has("elbows"):
			pose.elbows[index] = _bounded_elbow(root,pose.hands[index],pose.elbows[index])
	if not pose.has("elbows"):
		# Every dance target includes its rendered elbows. Entering a plain
		# freeze must blend those endpoints too, including at half strength.
		pose.elbows = PoseArt.arm_elbows(pose)

static func _mix(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
	var pose := a.duplicate(true)
	var blend := smoothstep(0.0,1.0,t)
	for key: String in ["hip","shoulder","head_shift"]:
		pose[key] = Vector2(a[key]).lerp(Vector2(b[key]),blend)
	for key: String in ["feet","hands"]:
		for index in 2:
			pose[key][index] = Vector2(a[key][index]).lerp(Vector2(b[key][index]),blend)
	pose.head_tilt = lerpf(float(a.head_tilt),float(b.head_tilt),blend)
	pose.foot_angles = [lerpf(float(a.foot_angles[0]),float(b.foot_angles[0]),blend),lerpf(float(a.foot_angles[1]),float(b.foot_angles[1]),blend)]
	if a.has("elbows") or b.has("elbows"):
		pose.elbows = PoseArt.blend_arm_elbows(a,b,blend)
	return pose

static func choreography(style: String,beats: float,crew_id: String="mara",intensity: float=1.0) -> Dictionary:
	var amplitude := clampf(intensity,0.4,1.5)
	var articulated_beat := snappy_beats(beats)
	var temperament: Dictionary = PROFILES.get(CharacterCatalog.presentation_id(crew_id,"dance"),PROFILES.mara)
	var personality := float(temperament.sway)*0.7+0.65
	if Moves.owns(style):
		# The repertoire helper already owns the only neutral pose allocation.
		# Skip the legacy pose, joint arrays, and unused legacy wave evaluation.
		var authored := Moves.choreography(style,beats,crew_id,amplitude)
		authored.head_tilt += sin(articulated_beat*TAU+float(temperament.offset)*TAU)*.016*personality
		_constrain(authored)
		return authored
	var pose := PoseArt.neutral()
	pose.continuous = true
	pose.foot_angles = [0.0,0.0]
	var cycle := articulated_beat*PI
	var sway := sin(cycle)
	var pulse := kick_accent(beats)
	var eighth := sin(articulated_beat*TAU*2.0)
	match style:
		"moonwalk":
			# Raised heel bears the weight while the flat opposite sole glides
			# backwards. Roles exchange every beat; the painted root returns on
			# a four-beat phrase, with no accumulating gameplay displacement.
			var stride := 7.5*amplitude
			var drift := -4.0*sin(beats*PI*0.5)*amplitude
			_body(pose,Vector2(drift,-24.0+pulse*0.75),-0.08)
			for index in 2:
				var phase := fposmod(articulated_beat*0.5+float(index)*0.5,1.0)
				var travel := cos(phase*TAU)*stride
				pose.feet[index] = Vector2(drift+(-5.0 if index==0 else 5.0)+travel,-3.0)
				pose.foot_angles[index] = -0.32*pow(maxf(0.0,sin(phase*TAU)),1.5)+eighth*0.045
			var torso := PoseArt.torso_transform(pose)
			pose.hands = [torso*Vector2(-10+sway*2.0,11),torso*Vector2(18-sway*2.0,13)]
			pose.head_tilt += sin(cycle)*0.07
		"shuffle":
			# Side-to-side weight transfer, alternating lifted toe and heel
			# pivots. Every lifted foot has an opposite foot on the floor.
			_body(pose,Vector2(sway*3.5*amplitude,-22.0+pulse*1.6),sway*0.13)
			for index in 2:
				var step := cycle+float(index)*PI
				var lift := maxf(0.0,sin(step))*6.0*amplitude
				pose.feet[index] = Vector2((-7.0 if index==0 else 7.0)+sin(step)*8.5*amplitude,-3.0-lift)
				pose.foot_angles[index] = sin(step+0.45)*0.20+eighth*0.045
			var torso := PoseArt.torso_transform(pose)
			pose.hands = [torso*Vector2(-10+sin(cycle+0.3)*4,7+cos(cycle)*3),torso*Vector2(19-sin(cycle+0.3)*4,9-cos(cycle)*3)]
			pose.head_tilt += sin(cycle+0.5)*0.08
		"running_man":
			# Each beat lifts a knee, then plants it as the supported boot slides
			# back. Arms oppose the lifted leg rather than following a walk clock.
			var switch_weight := sin(cycle)
			_body(pose,Vector2(switch_weight*1.8,-23.0+pulse*2.4),0.13)
			for index in 2:
				var step := fposmod(articulated_beat+float(index),2.0)
				if step<1.0:
					var lift := pow(sin(step*PI),1.15)
					pose.feet[index] = Vector2((-4.0 if index==0 else 4.0)+lift*10.0*amplitude,-3.0-lift*11.0*amplitude)
					pose.foot_angles[index] = lift*0.28
				else:
					pose.feet[index] = Vector2((-4.0 if index==0 else 4.0)-sin((step-1.0)*PI)*9.0*amplitude,-3.0)
			var torso := PoseArt.torso_transform(pose)
			var hand_bob := sin(articulated_beat*TAU)*1.2+eighth*.55
			pose.hands = [torso*Vector2(-8+switch_weight*7,7-hand_bob),torso*Vector2(18-switch_weight*7,8+hand_bob)]
			pose.head_tilt -= pulse*0.06
		"robot":
			# Eased mechanical locks, with a short elastic pop at the kick.
			# There is no frame quantization: even a hold joins continuously.
			var quadrant := floori(fposmod(beats,4.0))
			var lock_phase := fposmod(beats,1.0)
			var transition := smoothstep(0.04,0.20,lock_phase)
			var previous: float = [0.0,1.0,0.0,-1.0][(quadrant+3)%4]
			var next: float = [0.0,1.0,0.0,-1.0][quadrant]
			var lock := lerpf(previous,next,transition)
			var pop := exp(-lock_phase*12.0)*sin(lock_phase*PI*6.0)
			_body(pose,Vector2(lock*2.8*amplitude,-22.0+absf(lock)*0.8+pop*0.8),lock*0.16)
			pose.feet = [Vector2(-8+lock*8*amplitude,-3),Vector2(8+lock*8*amplitude,-3)]
			pose.foot_angles = [maxf(lock,0.0)*0.20,minf(lock,0.0)*0.20]
			_arm(pose,0,0.45+lock*0.42,-PI*0.5+lock*0.45)
			_arm(pose,1,PI*0.35-lock*0.40,-PI*0.5-lock*0.45)
			pose.head_tilt = -lock*0.25+pop*0.10
		"arm_wave":
			# Wave travels wrist → elbow → shoulder → torso → opposite arm.
			# Explicit two-bone elbows make the ripple visible, not just hands.
			var wave := articulated_beat*PI*0.5
			_body(pose,Vector2(sin(wave-1.1)*2.1*amplitude,-23.0+sin(wave-1.6)*1.0),sin(wave-0.8)*0.14)
			for index in 2:
				var step := wave+float(index)*PI
				pose.feet[index] = Vector2((-8.0 if index==0 else 8.0)+sin(step)*9.0*amplitude,-3.0-maxf(0.0,sin(step))*6.0*amplitude)
			pose.foot_angles = [maxf(0.0,sin(wave-1.1))*0.14,-maxf(0.0,-sin(wave-1.1))*0.14]
			_arm(pose,0,PI+sin(wave-0.45)*0.56,PI+sin(wave)*0.78)
			_arm(pose,1,sin(wave-1.35)*0.56,sin(wave-1.8)*0.78)
			pose.head_tilt = sin(wave-0.9)*0.12
		"body_roll":
			# Knees initiate; the pelvis, chest and head follow a quarter beat
			# later. Arms frame the travelling body wave and soles bear weight.
			var roll := articulated_beat*PI
			_body(pose,Vector2(sin(roll)*3.0*amplitude,-22.0+(sin(roll)+1.0)*1.6),sin(roll-0.65)*0.28*amplitude)
			for index in 2:
				var step := roll+float(index)*PI
				pose.feet[index] = Vector2((-8.0 if index==0 else 8.0)+sin(step)*9.0*amplitude,-3.0-maxf(0.0,sin(step))*4.0*amplitude)
			pose.foot_angles = [maxf(0.0,sin(roll))*0.17,-maxf(0.0,-sin(roll))*0.17]
			_arm(pose,0,0.95+sin(roll-0.9)*0.22,0.30+sin(roll-1.3)*0.50)
			_arm(pose,1,PI-(PI*0.72+sin(roll-1.1)*0.22),PI-(PI*0.90+sin(roll-1.5)*0.50))
			pose.head_tilt += sin(roll-1.3)*0.18
		"breakdance":
			pose = _breakdance(beats,amplitude)
	# Small character-specific head/shoulder accents remain visible when two
	# characters select the same dance, without disturbing the contact path.
	pose.head_tilt += sin(articulated_beat*TAU+float(temperament.offset)*TAU)*0.020*personality+(pulse-.5)*float(temperament.nod)*.75
	pose.dance_style = style
	_constrain(pose)
	return pose

static func _toprock(beats: float,amplitude: float) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.foot_angles = [0.0,0.0]
	var beat := snappy_beats(beats)*PI
	var pulse := kick_accent(beats)
	_body(pose,Vector2(sin(beat)*3.0*amplitude,-22.0+pulse*1.6),sin(beat)*0.18)
	for index in 2:
		var step := beat+float(index)*PI
		pose.feet[index] = Vector2((-7.0 if index==0 else 7.0)+sin(step)*8.0*amplitude,-3.0-maxf(0.0,sin(step))*4.0)
		pose.foot_angles[index] = sin(step)*0.18
	var torso := PoseArt.torso_transform(pose)
	pose.hands = [torso*Vector2(-12+sin(beat)*5,5),torso*Vector2(20-sin(beat)*5,6)]
	return pose

static func _floorwork(beats: float,amplitude: float) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.foot_angles = [0.0,0.0]
	var circle := snappy_beats(beats)*PI
	_body(pose,Vector2(-5.0+sin(circle)*2.5*amplitude,-15.0+cos(circle)*1.0),0.92+sin(circle)*0.15)
	pose.hands = [Vector2(9,-3),Vector2(20,-3)]
	for index in 2:
		var step := circle+float(index)*PI
		pose.feet[index] = Vector2(-8.0+cos(step)*14.0*amplitude,-3.0-maxf(0.0,sin(step))*9.0*amplitude)
		pose.foot_angles[index] = sin(step)*0.35
	pose.dance_stage = "floorwork"
	return pose

static func _freeze(_beats: float) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.foot_angles = [0.08,-0.38]
	_body(pose,Vector2(-6,-15),1.35)
	pose.feet = [Vector2(-23,-3),Vector2(-7,-34)]
	pose.hands = [Vector2(8,-24),Vector2(17,-3)]
	pose.head_tilt = -0.38
	pose.dance_stage = "freeze"
	return pose

static func _breakdance(beats: float,amplitude: float) -> Dictionary:
	var t := fposmod(beats,16.0)
	var pose: Dictionary
	if t<4.0:
		pose = _toprock(t,amplitude)
		pose.dance_stage = "toprock"
	elif t<5.0:
		pose = _mix(_toprock(4.0,amplitude),_floorwork(0.0,amplitude),t-4.0)
		pose.dance_stage = "drop"
	elif t<10.0:
		pose = _floorwork(t-5.0,amplitude)
	elif t<11.0:
		pose = _mix(_floorwork(5.0,amplitude),_freeze(t),t-10.0)
		pose.dance_stage = "freeze_entry"
	elif t<13.0:
		pose = _freeze(t)
	elif t<15.0:
		pose = _mix(_freeze(t),_toprock(15.0,amplitude),(t-13.0)/2.0)
		pose.dance_stage = "rise"
	else:
		pose = _toprock(t,amplitude)
		pose.dance_stage = "toprock"
	return pose
