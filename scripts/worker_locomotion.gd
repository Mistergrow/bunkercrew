extends RefCounted
## Local presentation rig. Gameplay velocity, input, colliders and action clocks
## are never changed. A stance foot travels backwards by the body's actual
## displacement; swing has a smooth toe-off, clearance and heel contact.

const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Keys := preload("res://scripts/worker_motion_keys.gd")
const PROFILES := {
	"mara": {"stride":1.0, "lift":1.0, "arms":0.8, "lean":0.10, "bob":0.8},
	"branko": {"stride":1.08, "lift":0.78, "arms":0.65, "lean":0.04, "bob":1.12},
	"ivo": {"stride":0.88, "lift":1.18, "arms":1.12, "lean":0.17, "bob":0.9},
	"nora": {"stride":1.05, "lift":0.84, "arms":0.62, "lean":0.02, "bob":0.65},
	"levin": {"stride":0.92, "lift":1.25, "arms":1.22, "lean":0.22, "bob":1.0},
	"selma": {"stride":0.98, "lift":0.92, "arms":0.72, "lean":0.07, "bob":0.58},
	"oskar": {"stride":1.02, "lift":0.72, "arms":0.56, "lean":0.035, "bob":0.72},
	"rika": {"stride":0.94, "lift":1.12, "arms":1.05, "lean":0.15, "bob":0.78},
}
const STATES := ["idle", "walk", "carry_idle", "carry_walk", "crouch", "crouch_walk", "jump_up", "fall", "land", "climb", "pickup", "drop", "work", "weapon", "weapon_up", "weapon_down"]

var phase := 0.0
var speed := 0.0
var kind := "idle"
var _activity := 0.0
var _crouch := 0.0
var _crawl := 0.0
var _duck := 0.0
var _torso_step := 0
var _head_step := 0
var _clock := 0.0
var _position := Vector2.ZERO
var _initialized := false
var _facing := 1.0
var _state := ""
var _previous: Dictionary = {}
var _transition: Dictionary = {}
var _transition_time := 1.0
## Hit timing from the replicated hurt timer. WorkerVisual ticks it once per
## frame itself (also while a medical or gesture pose is shown) and sets
## external_hit; a bare rig (convoy escort, tests) ticks it in advance().
var hit := Keys.HitClock.new()
var external_hit := false

func reset() -> void:
	_initialized=false
	_previous={}
	_transition={}
	_state=""
	phase=0.0
	speed=0.0
	_activity=0.0
	_crouch=0.0
	_crawl=0.0
	_duck=0.0

static func supports(state: String) -> bool:
	return state in STATES

static func foot(cycle: float, stride: float, stance: float, lift: float) -> Vector2:
	var t := fposmod(cycle, 1.0)
	var extent := stride*stance*0.5
	if t<stance:
		return Vector2(extent-stride*t, -3.0)
	var swing := (t-stance)/(1.0-stance)
	# Endpoint tangent matches the planted foot. A quintic swing avoids a
	# velocity discontinuity where the sole leaves or reaches the floor.
	var progress := swing*swing*swing*(10.0+swing*(-15.0+swing*6.0))
	var tangent := -stride*(1.0-stance)*swing*(1.0-swing)*(1.0-2.0*swing)
	return Vector2(lerpf(-extent, extent, progress)+tangent, -3.0-lift*pow(sin(PI*swing), 2.0))

func advance(worker: Node2D, state: String, delta: float, armed: bool=false, visual_node: Node2D=null) -> Dictionary:
	var dt := maxf(0.0, delta)
	_clock+=dt
	var point := worker.global_position
	var displacement := point-_position if _initialized else Vector2.ZERO
	_position=point
	var facing: float = worker.facing
	var turned := _initialized and facing!=_facing and state!="climb"
	# A landing or take-off crouch at speed keeps striding: the soles stay
	# planted in world space instead of skating under a fixed squat.
	var striding: bool = state.ends_with("walk") or (state=="land" and absf(worker.velocity.x)>15.0)
	var target_speed: float = absf(worker.velocity.x) if striding else 0.0
	var smoothing := 1.0-exp(-dt*18.0)
	speed=lerpf(speed, target_speed, smoothing)
	_activity=lerpf(_activity, 1.0 if target_speed>15.0 else 0.0, 1.0-exp(-dt*22.0))
	_crouch=lerpf(_crouch, 1.0 if state.begins_with("crouch") else 0.0, 1.0-exp(-dt*26.0))
	var visual := visual_node if visual_node!=null else worker.get_node_or_null("PixelVisual")
	var low: bool = state.begins_with("crouch") and visual!=null and visual.ceiling_height<49.0 and not armed
	# Under a low lintel or through a dug adit a moving worker ducks and keeps
	# running bent double, head up; only a slow or resting one goes down on
	# hands and knees. Same probe and collider; presentation only.
	var dashing: bool = absf(worker.velocity.x)>70.0
	var crawl_allowed: bool = low and worker.carried_count()==0 and not dashing
	_crawl=lerpf(_crawl, 1.0 if crawl_allowed else 0.0, 1.0-exp(-dt*20.0))
	_duck=lerpf(_duck, 1.0 if low and not crawl_allowed else 0.0, 1.0-exp(-dt*24.0))
	var profile: Dictionary = PROFILES.get(CharacterCatalog.presentation_id(str(worker.character_id),"motion"), PROFILES.mara)
	var running := smoothstep(95.0, 180.0, speed)*(1.0-_crouch)
	var stride: float = lerpf(40.0, 54.0, running)*float(profile.stride)
	stride=lerpf(stride, 38.0*float(profile.stride), _crouch)
	var stance := lerpf(0.62, 0.52, running)
	stance=lerpf(stance, 0.64, _crouch)
	if displacement.length()>70.0:
		# Teleports/spawns are not a stride. Clear interpolation across the map.
		_transition={}
		_previous={}
	elif target_speed>15.0:
		# Velocity fallback supports stationary presentation fixtures. A blocked
		# CharacterBody reports zero velocity after move_and_slide, so it stops.
		var travel := absf(displacement.x) if absf(displacement.x)>0.001 else target_speed*dt
		phase+=travel/stride
	var pose := Personality.stance(PoseArt.neutral(), str(worker.character_id))
	pose.continuous=true
	pose.hip_spread=2.0
	# Standing life comes from authored idle keys (WorkerMotionKeys, applied
	# below once the arms hang): weight shifts, a breath, late hands and a
	# trailing pack and braid. A blink every few seconds on an uneven,
	# per-worker rhythm.
	var rest := (1.0-_activity)*(1.0-_crouch)
	pose.blink=blinking(_clock, worker)
	if state=="climb":
		pose=_climb(worker)
		kind="climb"
	else:
		var lift: float = lerpf(7.0, 9.0, running)*float(profile.lift)
		lift=lerpf(lift, 3.8, _crouch)
		var gait_feet := [foot(phase+0.5, stride, stance, lift), foot(phase, stride, stance, lift)]
		for index in 2:
			pose.feet[index]=Vector2(pose.feet[index]).lerp(gait_feet[index], _activity)
		# A load makes every contact heavier.
		var loaded := 1.0 if worker.carried_count()>0 else 0.0
		var weight := sin(phase*TAU*2.0-0.6)*float(profile.bob)*(1.0+0.8*loaded)*_activity
		# Upright strides bob on the held contact/down/passing/up keys
		# (WorkerMotionKeys.WALK_KEYS); crouched gaits keep the smooth sway.
		var stride_key := Keys.walk_key(phase)
		var gait := _activity*(1.0-_crouch)
		var bob := float(stride_key.bob)*float(profile.bob)*(1.0+0.4*loaded)*_activity
		pose.hip.x-=running*0.5
		pose.hip.y=lerpf(pose.hip.y, lerpf(-22.0, -19.0, running)+lerpf(bob, weight, _crouch), _activity)
		pose.hip=Vector2(pose.hip).lerp(Vector2(-3, -13.0+weight*0.35), _crouch)
		# Keep the real two-bone leg length even at long stride contacts. This
		# produces weight transfer instead of stretching the shin to a target.
		for index in 2:
			var dx: float = pose.feet[index].x-(pose.hip.x+(-2.0 if index==0 else 2.0))
			var reach := sqrt(maxf(1.0, 23.7*23.7-dx*dx))
			pose.hip.y=maxf(pose.hip.y, pose.feet[index].y-reach)
		var lean: float = (lerpf(float(profile.lean), float(profile.lean)+0.13, running)-0.12*loaded)*_activity
		lean=lerpf(lean, 0.42, _crouch)
		pose.shoulder=Vector2(pose.shoulder).lerp(pose.hip+Vector2(sin(lean), -cos(lean))*17.0, maxf(_activity,_crouch))
		pose.shoulder.x+=float(stride_key.lean)*gait
		# Under a load the chest rocks back over each planted step.
		# (Small enough to stay inside one drawn coat attitude: the load and the
		# hips carry the visible weight; see _cargo's bounce.)
		pose.shoulder.x+=sin(phase*TAU*2.0-0.2)*0.45*loaded*_activity
		pose.head_tilt=-lean*0.68
		pose.head_shift+=Vector2(0, _crouch*2.0+float(stride_key.head)*gait)
		var swing := sin(phase*TAU)*lerpf(7.0, 10.0, running)*float(profile.arms)*_activity
		var tx := PoseArt.torso_transform(pose)
		# Arcs: the hand swinging forward rises towards the chest, the one
		# swinging back lifts a little behind the hip.
		var rise := [maxf(0.0, swing)*0.75+maxf(0.0, -swing)*0.3, maxf(0.0, -swing)*0.75+maxf(0.0, swing)*0.3]
		pose.hands=[tx*Vector2(-8+swing, 15.0-running*5.0-float(rise[0])*(1.0-_crouch)), tx*Vector2(7-swing, 14.0-running*5.0-float(rise[1])*(1.0-_crouch))]
		if striding and gait>0.5:
			pose.gear=stride_key.gear
			pose.gear_swing=int(stride_key.gear_swing)
			pose.hair_swing=int(stride_key.hair_swing)
		if striding and gait>0.05:
			pose.foot_angles=[Keys.walk_foot_angle(phase+0.5, stance)*gait, Keys.walk_foot_angle(phase, stance)*gait]
		if _crouch>0.001:
			pose.hands[0]=Vector2(pose.hands[0]).lerp(tx*Vector2(0+swing*0.25, 14), _crouch)
			pose.hands[1]=Vector2(pose.hands[1]).lerp(tx*Vector2(13-swing*0.25, 14), _crouch)
		if _activity<0.99 and _crouch<0.001:
			var resting := Personality.stance(PoseArt.neutral(), str(worker.character_id))
			for index in 2:
				pose.hands[index]=Vector2(resting.hands[index]).lerp(pose.hands[index], _activity)
		if rest>0.001:
			Keys.apply_idle(pose, idle_key(worker), rest, worker.carried_count()==0)
		kind="crouch" if _crouch>0.5 else ("run" if running>0.5 else ("walk" if _activity>0.1 else "idle"))
		if _crawl>0.001:
			var crawling := pose.duplicate(true)
			crawling.hip=Vector2(-11,-14+weight*0.18)
			crawling.shoulder=Vector2(6,-19+weight*0.15)
			crawling.head_tilt=-PoseArt.torso_transform(crawling).get_rotation()*0.92
			for index in 2:
				crawling.feet[index]=Vector2(pose.feet[index])+Vector2(-12,0)
				var hand := foot(phase+(0.25 if index==0 else 0.75),stride,0.36 if index==0 else 0.56,2.5)*_activity+Vector2(4 if index==0 else 12,-3*(1.0-_activity))
				crawling.hands[index]=hand
			pose=_blend(pose,crawling,_crawl)
			pose.crawling=_crawl>0.5
			if _crawl>0.5: kind="crawl"
		if _duck>0.001:
			pose=_blend(pose,_duck_pose(pose,phase,weight,_activity),_duck)
			if _duck>0.5: kind="duck"
		_actions(pose, worker, state, _clock, _activity)
		_hurt(pose, worker, dt)
	if (state!=_state or turned) and not _previous.is_empty():
		_transition=_previous.duplicate(true)
		if turned: _mirror(_transition)
		_transition_time=0.0
	_transition_time+=dt
	if not _transition.is_empty() and _transition_time<0.12 and state!="climb" and _state!="climb":
		pose=_blend(_transition, pose, smoothstep(0.0, 0.12, _transition_time))
	if state=="land" and _activity<0.5:
		# The body absorbs the impact while the painted soles immediately meet
		# the actual floor. Do not delay supported sound/dust behind a pose blend.
		for index in 2: pose.feet[index].y=-3.0
	# Keep carrying and aiming anchors exact after blending. Hands follow a
	# rigid load/weapon rather than independently interpolating through it.
	if state!="climb":
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var shoulder := body*Vector2(-6 if index==0 else 3,0)
			var reach: Vector2=pose.hands[index]-shoulder
			if reach.length()>22.8: pose.hands[index]=shoulder+reach.normalized()*22.8
		if worker.carried_count()>0 or (state=="drop" and worker.drop_animation>0.12):
			# The load swings a beat behind the hips' weight drop and rides
			# the breath at rest, instead of being bolted to the torso.
			# Pass 3: a texel more travel and a slight fore-aft lag, so the load
			# visibly rides each step rather than following the hands rigidly.
			var bounce := sin(phase*TAU*2.0-1.5)*3.6*_activity+sin(_clock*2.6-0.8)*1.4*(1.0-_activity)
			var lag := sin(phase*TAU*2.0-2.4)*0.6*_activity
			_cargo(pose, Vector2(lag, bounce))
		if armed: _weapon(pose, worker, visual)
	pose.continuous=true
	# Hysteresis for the drawn coat/head attitudes (WorkerPoseArt.held_step).
	# The ladder stays a pure function of height (it retraces exactly).
	if state!="climb":
		var body_turn := PoseArt.torso_transform(pose).get_rotation()
		_torso_step=PoseArt.held_step(body_turn, _torso_step)
		_head_step=PoseArt.held_step(body_turn+float(pose.head_tilt), _head_step)
		pose.torso_step=_torso_step
		pose.head_step=_head_step
	_previous=pose.duplicate(true)
	_state=state
	_facing=facing
	_initialized=true
	return pose

## Ducking run: hips dropped, the back bent forward to about 60 degrees, the
## head lifted about the neck to look ahead under the lintel (helmet crown
## near 39 texels) and the forearms pumping low in front of the knees.
const DUCK_LEAN := 1.05
const DUCK_LOOK := -0.55
const NECK := Vector2(0, 11)
static func _duck_pose(pose: Dictionary, cycle: float, weight: float, activity: float) -> Dictionary:
	var ducking := pose.duplicate(true)
	ducking.hip=Vector2(-2.0, -10.0+weight*0.3)
	ducking.shoulder=Vector2(ducking.hip)+Vector2(sin(DUCK_LEAN), -cos(DUCK_LEAN))*17.0+Vector2(0, absf(sin(cycle*TAU))*activity)
	# The head turns about the base of the neck, so the jaw stays on the collar.
	ducking.head_tilt=DUCK_LOOK
	ducking.head_shift=NECK-NECK.rotated(DUCK_LOOK)
	var pump := sin(cycle*TAU)*4.0*activity
	ducking.hands=[Vector2(13.0-pump, -10.0+absf(pump)*0.4), Vector2(23.0+pump, -12.0+absf(pump)*0.3)]
	return ducking

## A short blink every 3.4-4.6 s, now and then a double blink. Per worker
## (identity and slot), so a crew never blinks in unison.
static func blinking(clock: float, worker: Node) -> bool:
	var seed_value := absi((str(worker.get("character_id"))+str(worker.get("player_id"))).hash())
	var period := 3.4+float(seed_value%13)*0.09
	var cycle := clock+float(seed_value%97)*0.37
	var at := fposmod(cycle, period)
	if at<0.12: return true
	return posmod(floori(cycle/period)+seed_value, 3)==0 and at>0.28 and at<0.38

func follow(pose: Dictionary, worker: Node2D) -> void:
	# Medical, mounted and target-relative work/mining remain authoritative poses.
	# Remember them so their exit joins locomotion without a one-frame snap.
	_previous=pose.duplicate(true)
	if pose.has("head_pivot"):
		# Locomotion uses the original head anchor. Convert the painted dance
		# pivot to an equivalent shift before blending, so the first moving
		# frame retains the exact visible head position and neck rotation.
		var body := PoseArt.torso_transform(pose)
		_previous.head_shift = body.affine_inverse()*PoseArt.head_transform(pose).origin-Vector2(1,-15)
		_previous.erase("head_pivot")
	if float(pose.get("facing",worker.facing))!=float(worker.facing):
		# Target-relative rigs may face behind a moving worker. Convert the
		# remembered joints into the next locomotion rig's drawing direction
		# before its existing state/turn blend; preserve their painted world pose.
		_mirror(_previous)
	_previous.erase("facing")
	_position=worker.global_position
	_facing=worker.facing
	_state="special"
	_initialized=true

static func _blend(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var result := to.duplicate(true)
	for key in ["hip", "shoulder", "head_shift"]:
		result[key]=Vector2(from[key]).lerp(to[key], t)
	for key in ["feet", "hands"]:
		for index in 2: result[key][index]=Vector2(from[key][index]).lerp(to[key][index], t)
	result.head_tilt=lerpf(float(from.head_tilt), float(to.head_tilt), t)
	return result

static func _mirror(pose: Dictionary) -> void:
	for key in ["hip", "shoulder", "head_shift"]: pose[key].x=-pose[key].x
	# Follow-through is local to the drawn facing: behind becomes ahead.
	if pose.has("gear"): pose.gear=Vector2(-Vector2(pose.gear).x, Vector2(pose.gear).y)
	for key in ["gear_swing", "hair_swing"]:
		if pose.has(key): pose[key]=-int(pose[key])
	for key in ["feet", "hands"]:
		for index in 2: pose[key][index].x=-pose[key][index].x
	if pose.has("elbows"):
		for index in 2:
			if pose.elbows[index] is Vector2: pose.elbows[index].x=-pose.elbows[index].x
	if pose.has("hip_spread"): pose.hip_spread=-float(pose.hip_spread)
	pose.head_tilt=-pose.head_tilt

## Airborne keys over the replicated vertical speed (take-off stretch, tuck at
## the apex, legs reaching for the floor on the way down); a running jump is
## a split leap. Every key is a full pose, so no single tuck is held in flight.
const AIR_KEYS := [
	{"u":0.0, "feet":[Vector2(-9,-4),Vector2(8,-14)], "hands":[Vector2(-12,-29),Vector2(12,-47)], "hip":-26.0, "lean":2.0, "tilt":-0.10},
	{"u":0.32, "feet":[Vector2(-8,-12),Vector2(9,-16)], "hands":[Vector2(-12,-41),Vector2(14,-42)], "hip":-25.0, "lean":2.0, "tilt":-0.04},
	{"u":0.52, "feet":[Vector2(-7,-15),Vector2(8,-17)], "hands":[Vector2(-13,-44),Vector2(15,-41)], "hip":-24.0, "lean":1.0, "tilt":0.03},
	{"u":0.76, "feet":[Vector2(-9,-9),Vector2(9,-11)], "hands":[Vector2(-16,-41),Vector2(16,-39)], "hip":-24.0, "lean":0.0, "tilt":0.06},
	{"u":1.0, "feet":[Vector2(-8,-5),Vector2(10,-6)], "hands":[Vector2(-15,-36),Vector2(15,-35)], "hip":-24.0, "lean":0.5, "tilt":0.09},
]
const LEAP_FEET := [[Vector2(-14,-7),Vector2(11,-12)], [Vector2(-13,-12),Vector2(11,-14)], [Vector2(-12,-14),Vector2(10,-15)], [Vector2(-11,-10),Vector2(11,-9)], [Vector2(-10,-8),Vector2(12,-5)]]

static func _air_pose(pose: Dictionary, vertical: float, horizontal: float) -> void:
	var u := clampf((vertical+390.0)/780.0, 0, 1)
	var leap := smoothstep(80.0, 170.0, absf(horizontal))
	var index := 0
	while index<AIR_KEYS.size()-2 and u>float(AIR_KEYS[index+1].u): index+=1
	var a: Dictionary = AIR_KEYS[index]
	var b: Dictionary = AIR_KEYS[index+1]
	var t := smoothstep(float(a.u), float(b.u), u)
	pose.hip=Vector2(-1.0, lerpf(float(a.hip), float(b.hip), t))
	pose.shoulder=pose.hip+Vector2(lerpf(float(a.lean), float(b.lean), t)+leap*1.5, -17)
	for limb in 2:
		var tuck: Vector2 = Vector2(a.feet[limb]).lerp(b.feet[limb], t)
		var split: Vector2 = Vector2(LEAP_FEET[index][limb]).lerp(LEAP_FEET[index+1][limb], t)
		pose.feet[limb]=tuck.lerp(split, leap)
		pose.hands[limb]=Vector2(a.hands[limb]).lerp(b.hands[limb], t)
	pose.head_tilt=lerpf(float(a.tilt), float(b.tilt), t)

static func _actions(pose: Dictionary, worker: Node2D, state: String, clock: float, activity: float=0.0) -> void:
	if state in ["jump_up", "fall"]:
		_air_pose(pose, float(worker.velocity.y), float(worker.velocity.x))
	elif state=="land":
		var compression := 1.0 if worker._jump_windup>0.0 else pow(clampf(worker._landing_time/0.15, 0, 1), 1.5)
		if activity>0.5:
			# Landing at speed: the stride carries on, hips and chest absorb it.
			pose.hip.y+=compression*5.0
			pose.shoulder+=Vector2(compression*3.0, compression*6.0)
			pose.head_tilt+=compression*0.08
			return
		pose.feet=[Vector2(-9, -3), Vector2(8, -3)]
		pose.hip=Vector2(-1, -25+compression*7.0)
		pose.shoulder=pose.hip+Vector2(1+compression*4.0, -17)
		pose.hands=[pose.shoulder+Vector2(-11, 15), pose.shoulder+Vector2(12, 15)]
		pose.head_tilt=-compression*0.10
	elif state in ["pickup", "drop"]:
		var remaining: float = worker.pickup_animation if state=="pickup" else worker.drop_animation
		var t := clampf(1.0-remaining/0.36, 0, 1)
		var bend := pow(sin(t*PI), 2.0)
		pose.hip=Vector2(-2, -25+bend*6)
		pose.shoulder=pose.hip+Vector2(1+bend*9, -17+bend*2)
		pose.feet=[Vector2(-8, -3), Vector2(8, -3)]
		pose.hands=[Vector2(11+bend*4, -28+bend*13), Vector2(17+bend*3, -26+bend*14)]
		pose.cargo_target=Vector2(17+bend*3, -29+bend*14.5)
		pose.head_tilt=bend*0.08
	elif state=="work":
		var work := sin(clock*TAU*1.5)
		pose.shoulder+=Vector2(4, 0)
		pose.hands=[pose.shoulder+Vector2(12, 6), pose.shoulder+Vector2(20+work*1.3, 9)]
		pose.head_tilt=0.10

## The worker's current idle key: their own phase in the loop (a crew never
## breathes in unison) at a tempo from their idle pace.
func idle_key(worker: Node) -> Dictionary:
	var seed_value := absi((str(worker.get("character_id"))+str(worker.get("player_id"))).hash())
	var tempo := clampf(Personality.playback_rate(str(worker.get("character_id")), "idle"), 1.0, 1.25)
	var frames := _clock*Keys.IDLE_FPS*tempo+float(seed_value%Keys.IDLE_FRAMES)
	return Keys.idle_key(floori(frames), floori(frames/Keys.IDLE_FRAMES))

## Hit reaction on the rig (the hurt timer and knockback are replicated): the
## authored impact, peak and recovery keys (WorkerMotionKeys.HIT_KEYS) throw
## hips and shoulders away from the hit, snap the head, fling the arms, step
## a boot and bring the body back with the pack trailing.
func _hurt(pose: Dictionary, worker: Node2D, dt: float) -> void:
	if not external_hit: hit.tick(worker, dt)
	if bool(worker.has_method("is_downed") and worker.is_downed()): return
	Keys.apply_hit(pose, Keys.hit_key(hit.age), hit.side, WeaponEffectArt.reduced(worker.get("game")))

static func _cargo(pose: Dictionary, bounce: Vector2=Vector2.ZERO) -> void:
	var tx := PoseArt.torso_transform(pose)
	pose.cargo=pose.get("cargo_target",tx*Vector2(15, 8))+bounce
	pose.hands=[pose.cargo+Vector2(-7, 0), pose.cargo+Vector2(5, 3)]
	# Slight counterbalance and braced forearms leave the feet free to stride.
	var body := PoseArt.torso_transform(pose)
	for unused in 3:
		for index in 2:
			var at := body*Vector2(-6 if index==0 else 3, 0)
			var reach: Vector2 = pose.hands[index]-at
			if reach.length()>22.7: pose.shoulder+=reach.normalized()*(reach.length()-22.7)
		body=PoseArt.torso_transform(pose)

static func _weapon(pose: Dictionary, worker: Node2D, visual: Node2D=null) -> void:
	var weapon := worker.get_node_or_null("WorkerWeapon")
	if weapon==null: return
	var direction: Vector2 = weapon.aim_direction*Vector2(float(worker.facing), 1)
	var crouched: bool = visual!=null and visual.crouched
	var tx := Transform2D(direction.angle(), Vector2(10, -21 if crouched else -38))
	var recoil := float(weapon.recoil)
	pose.hands=[tx*(WorkerWeapon.GRIP_POINTS[0]-Vector2(recoil,0)),tx*(WorkerWeapon.GRIP_POINTS[1]-Vector2(recoil,0))]
	if weapon is WorkerWeapon and visual!=null:
		var grips: PackedVector2Array = weapon.grip_positions_for(visual)
		pose.hands=[grips[0],grips[1]]
	# The shot kicks the shoulders back along the stock and the head snaps a
	# little; the grips stay on the gun (halved with reduced effects).
	var kick := recoil*(0.5 if WeaponEffectArt.reduced(worker.get("game")) else 1.0)
	pose.shoulder=Vector2(pose.shoulder)+Vector2(-kick*0.55, -kick*0.10)
	pose.head_shift=Vector2(pose.head_shift)+Vector2(-kick*0.22, 0)
	for unused in 5:
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var at := body*Vector2(-6 if index==0 else 3, 0)
			var reach: Vector2 = pose.hands[index]-at
			if reach.length()>22.7: pose.shoulder+=reach.normalized()*(reach.length()-22.7)
	pose.head_tilt=-PoseArt.torso_transform(pose).get_rotation()*0.65-kick*0.03

## Ladder gait (back view), a pure function of the height on the ladder: a
## stationary climber holds, a descending one retraces. Each glove grips a
## real rung and stays on it while the body rises past, then reaches four
## rungs higher; each boot steps two rungs at a time. Opposite hand and foot
## move together, shoulders sway toward the pulling arm, elbows and knees
## bend outwards and never cross the body.
const CLIMB_RUNG := 14.0
const CLIMB_HAND_CYCLE := 56.0
const CLIMB_FOOT_CYCLE := 28.0
const CLIMB_HAND_GRIP := 0.5
const CLIMB_FOOT_GRIP := 0.5

static func _climb_limb(cycle: float, top: float, span: float, grip: float, reach_out: float, side: float) -> Vector2:
	var t := fposmod(cycle, 1.0)
	if t<grip:
		return Vector2(0.0, top+span*t)
	# The free limb lets go below, swings out around the rails and closes on
	# the next rung above with a quintic ease (no velocity step at either end).
	var swing := (t-grip)/(1.0-grip)
	var eased := swing*swing*swing*(10.0+swing*(-15.0+swing*6.0))
	return Vector2(side*reach_out*sin(swing*PI), lerpf(top+span*grip, top, eased))

static func _climb(worker: Node2D) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.back=true
	pose.continuous=true
	var origin: float = worker._ladder.position.y+15.0
	var height: float = origin-worker.global_position.y
	var hand_phase := height/CLIMB_HAND_CYCLE
	var foot_phase := height/CLIMB_FOOT_CYCLE
	for limb in 2:
		var side := -1.0 if limb==0 else 1.0
		# Grips start on rungs above the helmet: the phase offset of an eighth
		# cycle (7 px) puts the 63 px reach exactly on the 14 px rung pitch.
		var hand := _climb_limb(hand_phase+0.125+0.5*limb, -63.0, CLIMB_HAND_CYCLE, CLIMB_HAND_GRIP, 3.0, side)
		pose.hands[limb]=Vector2(side*8.0, 0)+hand
		var step := _climb_limb(foot_phase+0.5*(1-limb), -14.0, CLIMB_FOOT_CYCLE, CLIMB_FOOT_GRIP, 2.0, side)
		pose.feet[limb]=Vector2(side*5.0, 0)+step
	# Shoulders lean toward the arm that is pulling, hips counter it.
	var sway := sin((hand_phase+0.125)*TAU)
	pose.hip=Vector2(-sway*0.8, -23.5)
	pose.shoulder=Vector2(sway*1.5, -40.5)
	pose.head_tilt=sway*0.05
	pose.head_shift=Vector2(sway*0.5, 0)
	var body := PoseArt.torso_transform(pose)
	var elbows: Array = [null, null]
	var knees: Array = [null, null]
	for limb in 2:
		var side := -1.0 if limb==0 else 1.0
		var shoulder := body*PoseArt.shoulder_local(pose, limb)
		var hand: Vector2 = pose.hands[limb]
		if hand.distance_to(shoulder)>22.9: hand=shoulder+(hand-shoulder).normalized()*22.9
		pose.hands[limb]=hand
		var bend_a := PoseArt.joint_position(shoulder, hand, 11, 12, 1)
		var bend_b := PoseArt.joint_position(shoulder, hand, 11, 12, -1)
		elbows[limb]=bend_a if (bend_a.x-bend_b.x)*side>0.0 else bend_b
		# Seen from behind, a raised knee points into the ladder: a short,
		# foreshortened thigh with only a small outward bulge.
		var hip := Vector2(pose.hip)+Vector2(side*5.0, 0)
		var boot: Vector2 = pose.feet[limb]
		var rise := clampf((24.0-(boot.y-hip.y))/14.0, 0, 1)
		knees[limb]=Vector2(lerpf(hip.x, boot.x, 0.5)+side*(0.5+rise*1.5), lerpf(hip.y, boot.y, lerpf(0.5, 0.42, rise)))
	pose.elbows=elbows
	pose.knees=knees
	return pose
