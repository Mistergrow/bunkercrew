extends RefCounted
## Local presentation rig. Gameplay velocity, input, colliders and action clocks
## are never changed. A stance foot travels backwards by the body's actual
## displacement; swing has a smooth toe-off, clearance and heel contact.

const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
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
var _clock := 0.0
var _position := Vector2.ZERO
var _initialized := false
var _facing := 1.0
var _state := ""
var _previous: Dictionary = {}
var _transition: Dictionary = {}
var _transition_time := 1.0

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
	var target_speed: float = absf(worker.velocity.x) if state.ends_with("walk") else 0.0
	var smoothing := 1.0-exp(-dt*18.0)
	speed=lerpf(speed, target_speed, smoothing)
	_activity=lerpf(_activity, 1.0 if target_speed>15.0 else 0.0, 1.0-exp(-dt*22.0))
	_crouch=lerpf(_crouch, 1.0 if state.begins_with("crouch") else 0.0, 1.0-exp(-dt*26.0))
	var visual := visual_node if visual_node!=null else worker.get_node_or_null("PixelVisual")
	var crawl_allowed: bool = state.begins_with("crouch") and visual!=null and visual.ceiling_height<49.0 and worker.carried_count()==0 and not armed
	_crawl=lerpf(_crawl, 1.0 if crawl_allowed else 0.0, 1.0-exp(-dt*20.0))
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
	var breath := sin(_clock*2.2)*0.45*(1.0-_activity)
	pose.hip.y+=breath*0.3
	pose.shoulder.y+=breath
	pose.head_tilt=-breath*0.018
	if state=="climb":
		pose=_climb(worker)
		kind="climb"
	else:
		var lift: float = lerpf(7.0, 9.0, running)*float(profile.lift)
		lift=lerpf(lift, 3.8, _crouch)
		var gait_feet := [foot(phase+0.5, stride, stance, lift), foot(phase, stride, stance, lift)]
		for index in 2:
			pose.feet[index]=Vector2(pose.feet[index]).lerp(gait_feet[index], _activity)
		var weight := sin(phase*TAU*2.0-0.6)*float(profile.bob)*_activity
		pose.hip.x-=running*0.5
		pose.hip.y=lerpf(pose.hip.y, lerpf(-22.0, -19.0, running)+weight, _activity)
		pose.hip=Vector2(pose.hip).lerp(Vector2(-3, -13.0+weight*0.35), _crouch)
		# Keep the real two-bone leg length even at long stride contacts. This
		# produces weight transfer instead of stretching the shin to a target.
		for index in 2:
			var dx: float = pose.feet[index].x-(pose.hip.x+(-2.0 if index==0 else 2.0))
			var reach := sqrt(maxf(1.0, 23.7*23.7-dx*dx))
			pose.hip.y=maxf(pose.hip.y, pose.feet[index].y-reach)
		var lean: float = lerpf(float(profile.lean), float(profile.lean)+0.13, running)*_activity
		lean=lerpf(lean, 0.42, _crouch)
		pose.shoulder=Vector2(pose.shoulder).lerp(pose.hip+Vector2(sin(lean), -cos(lean))*17.0, maxf(_activity,_crouch))
		pose.head_tilt=-lean*0.68
		pose.head_shift+=Vector2(0, _crouch*2.0)
		var swing := sin(phase*TAU)*lerpf(7.0, 10.0, running)*float(profile.arms)*_activity
		var tx := PoseArt.torso_transform(pose)
		pose.hands=[tx*Vector2(-8+swing, 15.0-running*5.0), tx*Vector2(7-swing, 14.0-running*5.0)]
		if _crouch>0.001:
			pose.hands[0]=Vector2(pose.hands[0]).lerp(tx*Vector2(0+swing*0.25, 14), _crouch)
			pose.hands[1]=Vector2(pose.hands[1]).lerp(tx*Vector2(13-swing*0.25, 14), _crouch)
		if _activity<0.99 and _crouch<0.001:
			var rest := Personality.stance(PoseArt.neutral(), str(worker.character_id))
			for index in 2:
				pose.hands[index]=Vector2(rest.hands[index]).lerp(pose.hands[index], _activity)
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
		_actions(pose, worker, state, _clock)
	if (state!=_state or turned) and not _previous.is_empty():
		_transition=_previous.duplicate(true)
		if turned: _mirror(_transition)
		_transition_time=0.0
	_transition_time+=dt
	if not _transition.is_empty() and _transition_time<0.12 and state!="climb" and _state!="climb":
		pose=_blend(_transition, pose, smoothstep(0.0, 0.12, _transition_time))
	if state=="land":
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
		if worker.carried_count()>0 or (state=="drop" and worker.drop_animation>0.12): _cargo(pose)
		if armed: _weapon(pose, worker, visual)
	pose.continuous=true
	_previous=pose.duplicate(true)
	_state=state
	_facing=facing
	_initialized=true
	return pose

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
	for key in ["feet", "hands"]:
		for index in 2: pose[key][index].x=-pose[key][index].x
	if pose.has("elbows"):
		for index in 2:
			if pose.elbows[index] is Vector2: pose.elbows[index].x=-pose.elbows[index].x
	if pose.has("hip_spread"): pose.hip_spread=-float(pose.hip_spread)
	pose.head_tilt=-pose.head_tilt

static func _actions(pose: Dictionary, worker: Node2D, state: String, clock: float) -> void:
	if state in ["jump_up", "fall"]:
		var fall := smoothstep(-100.0, 160.0, float(worker.velocity.y))
		pose.feet=[Vector2(-10, lerpf(-12, -4, fall)), Vector2(9, lerpf(-15, -6, fall))]
		pose.hip.y=-24.0
		pose.shoulder=pose.hip+Vector2(2.0*(1.0-fall), -17)
		pose.hands=[Vector2(-12, lerpf(-44, -35, fall)), Vector2(15, lerpf(-43, -33, fall))]
		pose.head_tilt=lerpf(-0.08, 0.06, fall)
	elif state=="land":
		var compression := 1.0 if worker._jump_windup>0.0 else pow(clampf(worker._landing_time/0.15, 0, 1), 1.5)
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

static func _cargo(pose: Dictionary) -> void:
	var tx := PoseArt.torso_transform(pose)
	pose.cargo=pose.get("cargo_target",tx*Vector2(16, 11))
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
	for unused in 5:
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var at := body*Vector2(-6 if index==0 else 3, 0)
			var reach: Vector2 = pose.hands[index]-at
			if reach.length()>22.7: pose.shoulder+=reach.normalized()*(reach.length()-22.7)
	pose.head_tilt=-PoseArt.torso_transform(pose).get_rotation()*0.65

static func _climb(worker: Node2D) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.back=true
	pose.continuous=true
	var origin: float = worker._ladder.position.y+15.0
	var phase_on_ladder := fposmod((origin-worker.global_position.y)/7.0, 8.0)
	var index := floori(phase_on_ladder)
	var t := phase_on_ladder-index
	var a := Personality.frame(str(worker.character_id), "climb", index)
	var b := Personality.frame(str(worker.character_id), "climb", (index+1)%8)
	for key in ["feet", "hands"]:
		for limb in 2:
			var from := Vector2(a[key][limb][0], a[key][limb][1])
			var to := Vector2(b[key][limb][0], b[key][limb][1])
			pose[key][limb]=from.lerp(to, t)
	return pose
