extends RefCounted
## Authored body keys for the articulated crew rig (pass 6A-2): idle, hit,
## collapse, get-up and tending a running machine. Every key is a held pose in
## whole texels, played stepped at body rates (style bible §5: 8-12 frames per
## second with holds) instead of eased sines, so each frame is a deliberate
## pose. Packs, bags, aerials and hanging hair trail the body one or two frames
## late through the follow-through layers (assets/workers/generate_crew_layers.py):
## `gear` (whole-texel shift of the gear layer), `gear_swing` and `hair_swing`
## (-1 trailing behind, +1 swung forward). Pass 7A-crew adds the walk and run
## body keys, the revive kneel, press and rise, standing bandaging and the
## dance's beat poses (sections below). Pure presentation: timers, input,
## colliders and replicated values are only read for timing, never changed.

# ------------------------------------------------------------------ idle
## A 24-frame weight-and-breath loop at 8 frames per second (3 s). Weight sits
## on the rear foot, transfers to the front foot (frames 10-11), then back
## (22-23); the hips lead, the shoulders answer a frame late and the free heel
## lifts. Each 12-frame half holds one breath: the chest rises two texels
## through an in-between, the head and the hanging hands follow a frame later,
## the pack lags the rise and the fall. The pack, then the hair, trail each
## weight transfer and swing through once. Every third loop the worker glances
## up two turned steps for six frames.
const IDLE_FPS := 8.0
const IDLE_FRAMES := 24
const IDLE_HIP_X := [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,0,1,1,1,1,1,1,1,1,1,1,1,0,-1]
const IDLE_HIP_Y := [0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,1,0]
const IDLE_BREATH := [0,0,-1,-2,-2,-1,0,0,0,0,0,0,0,0,-1,-2,-2,-1,0,0,0,0,0,0]
const IDLE_GEAR_X := [1,0,0,0,0,0,0,0,0,0,0,-1,-1,0,0,0,0,0,0,0,0,0,0,1]
const IDLE_GEAR_SWING := [1,0,-1,0,0,0,0,0,0,0,0,-1,-1,0,1,0,0,0,0,0,0,0,0,1]
const IDLE_HAIR_SWING := [1,1,0,-1,0,0,0,0,0,0,0,0,-1,-1,0,1,0,0,0,0,0,0,0,0]
## Free heel lift (radians, WorkerPoseArt.foot_transform) of [rear, front] foot.
const HEEL := 0.26
const GLANCE_TILT := -0.2618

static func idle_frame(clock: float, seed_value: int) -> int:
	return posmod(floori(clock*IDLE_FPS)+seed_value, IDLE_FRAMES)

## Offsets of idle frame `frame` (loop `loop` of the worker's own clock).
static func idle_key(frame: int, loop: int) -> Dictionary:
	var f := posmod(frame, IDLE_FRAMES)
	var before := posmod(f-1, IDLE_FRAMES)
	var hip := Vector2(IDLE_HIP_X[f], IDLE_HIP_Y[f])
	var chest := Vector2(IDLE_HIP_X[before], IDLE_BREATH[f]+IDLE_HIP_Y[f])
	# Hanging hands follow the chest one more frame later.
	var late := Vector2(IDLE_HIP_X[posmod(f-2, IDLE_FRAMES)], IDLE_BREATH[before]+IDLE_HIP_Y[before])
	var key := {
		"hip":hip, "shoulder":chest,
		# The head answers the chest one frame later (it is carried by the coat).
		"head":Vector2(0, IDLE_BREATH[before]-IDLE_BREATH[f]),
		"hands":[late, late],
		"gear":Vector2(IDLE_GEAR_X[f], signf(IDLE_BREATH[f]-IDLE_BREATH[before])*-1.0),
		"gear_swing":IDLE_GEAR_SWING[f], "hair_swing":IDLE_HAIR_SWING[f],
		"heel":[HEEL if f>=13 and f<=21 else 0.0, HEEL if f>=1 and f<=9 else 0.0],
		"tilt":GLANCE_TILT if posmod(loop,3)==2 and f>=3 and f<=8 else 0.0,
	}
	return key

## Adds an idle key to a standing pose, scaled by `weight` (1 at rest; the
## locomotion rig fades it out as a stride begins). Under a load both boots
## stay flat (`heels` false): the free heel only lifts empty-handed.
static func apply_idle(pose: Dictionary, key: Dictionary, weight: float, heels: bool=true) -> void:
	pose.hip = Vector2(pose.hip)+Vector2(key.hip)*weight
	pose.shoulder = Vector2(pose.shoulder)+Vector2(key.shoulder)*weight
	pose.head_shift = Vector2(pose.head_shift)+Vector2(key.head)*weight
	pose.head_tilt = float(pose.head_tilt)+float(key.tilt)*weight
	for index in 2:
		pose.hands[index] = Vector2(pose.hands[index])+Vector2(key.hands[index])*weight
	if weight>0.5:
		pose.gear = Vector2(key.gear)
		pose.gear_swing = int(key.gear_swing)
		pose.hair_swing = int(key.hair_swing)
		if heels and (float(key.heel[0])>0.0 or float(key.heel[1])>0.0):
			pose.foot_angles = [float(key.heel[0]), float(key.heel[1])]

# ------------------------------------------------------------------ hit
## Hit reaction at 12 frames per second: one impact pose, a held peak, then
## three recovery keys (style bible §5). Offsets in texels for a push towards
## the drawn facing (side +1); a push from the front mirrors them (side -1).
## The body is thrown 6 texels at the shoulders and 3 at the hips, the head
## snaps two turned steps, the arms fly up, the boot on the pushed side steps
## 3 texels to catch the weight and comes back, the pack trails and
## overshoots. The gameplay knockback, stun and hitbox are untouched.
const HIT_FPS := 12.0
const HIT_KEYS := [
	{"hold":1, "hip":Vector2(2,1), "shoulder":Vector2(5,2), "head":Vector2(1,0), "tilt":0.26, "hands":Vector2(-3,-6), "step":Vector2(1,-2), "gear":Vector2(-1,-1), "gear_swing":-1, "hair_swing":-1},
	{"hold":1, "hip":Vector2(3,2), "shoulder":Vector2(6,3), "head":Vector2(1,1), "tilt":0.26, "hands":Vector2(-2,-4), "step":Vector2(3,0), "gear":Vector2(0,0), "gear_swing":-1, "hair_swing":-1},
	{"hold":2, "hip":Vector2(2,1), "shoulder":Vector2(3,1), "head":Vector2(0,0), "tilt":0.13, "hands":Vector2(-1,-2), "step":Vector2(3,0), "gear":Vector2(1,0), "gear_swing":1, "hair_swing":0},
	{"hold":2, "hip":Vector2(1,0), "shoulder":Vector2(1,0), "head":Vector2(0,0), "tilt":0.0, "hands":Vector2(0,-1), "step":Vector2(2,-1), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":1},
	{"hold":1, "hip":Vector2(0,0), "shoulder":Vector2(-1,0), "head":Vector2(0,0), "tilt":0.0, "hands":Vector2(0,0), "step":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":0},
]

static func hit_frames() -> int:
	var total := 0
	for key: Dictionary in HIT_KEYS: total += int(key.hold)
	return total

static func hit_seconds() -> float:
	return float(hit_frames())/HIT_FPS

## The held key at `age` seconds after the hit, or {} once it has played.
static func hit_key(age: float) -> Dictionary:
	if age<0.0: return {}
	var frame := floori(age*HIT_FPS)
	for key: Dictionary in HIT_KEYS:
		frame -= int(key.hold)
		if frame<0: return key
	return {}

## Applies a hit key for a push to `side` (+1 the drawn facing, -1 behind).
## `reduced` halves every offset (reduced effects). Planted boots keep the
## real two-bone leg length; the stepping boot is the one on the pushed side.
static func apply_hit(pose: Dictionary, key: Dictionary, side: float, reduced: bool=false) -> void:
	if key.is_empty(): return
	var amount := 0.5 if reduced else 1.0
	var flip := Vector2(side, 1.0)
	var foot := 1 if side>0.0 else 0
	pose.feet[foot] = Vector2(pose.feet[foot])+(Vector2(key.step)*flip*amount).round()
	var hip: Vector2 = Vector2(pose.hip)+(Vector2(key.hip)*flip*amount).round()
	var spread := float(pose.get("hip_spread", 2.0))
	for index in 2:
		var dx: float = pose.feet[index].x-(hip.x+(-spread if index==0 else spread))
		hip.y = maxf(hip.y, pose.feet[index].y-sqrt(maxf(1.0, 23.7*23.7-dx*dx)))
	pose.shoulder = Vector2(pose.shoulder)+(Vector2(key.shoulder)*flip*amount).round()+(hip-Vector2(pose.hip))
	pose.hip = hip
	pose.head_shift = Vector2(pose.head_shift)+(Vector2(key.head)*flip*amount).round()
	pose.head_tilt = float(pose.head_tilt)+float(key.tilt)*side*amount
	for index in 2:
		pose.hands[index] = Vector2(pose.hands[index])+(Vector2(key.hands)*flip*amount).round()
	pose.gear = (Vector2(key.gear)*flip).round() if not reduced else Vector2.ZERO
	pose.gear_swing = int(key.gear_swing)*int(side)
	pose.hair_swing = int(key.hair_swing)*int(side)

## Tracks fresh hits from the replicated hurt timer and knockback.
class HitClock extends RefCounted:
	var age := 10.0
	var side := -1.0
	var _last_hurt := 0.0
	func tick(worker: Node, dt: float) -> void:
		var hurt: float = float(worker.get("hurt_flash")) if "hurt_flash" in worker else 0.0
		if hurt>_last_hurt+0.05:
			age = 0.0
			var push: float = float(worker.get("knockback")) if "knockback" in worker else 0.0
			side = signf(push)*float(worker.get("facing")) if absf(push)>0.01 else -1.0
		_last_hurt = hurt
		age += maxf(0.0, dt)

# ------------------------------------------------------------------ collapse
## Knockout at 12 frames per second: the knees buckle and the head drops, one
## knee hits the floor with a hand reaching down, the body topples back about
## the hip, falls, strikes the floor (limbs and head bounce a texel or two)
## and settles flat on the back. Absolute joints (texels from the feet
## anchor); spines stay 16.5-17 texels so the drawn coat meets the hips.
const COLLAPSE_FPS := 12.0
const COLLAPSE_KEYS := [
	{"hold":2, "hip":Vector2(-1,-21), "shoulder":Vector2(3,-37), "feet":[Vector2(-7,-3),Vector2(7,-3)], "hands":[Vector2(-5,-24),Vector2(11,-22)], "tilt":0.26, "head":Vector2(1,1), "gear":Vector2(0,-1), "gear_swing":0, "hair_swing":-1, "blink":false},
	{"hold":2, "hip":Vector2(-3,-14), "shoulder":Vector2(2,-30), "feet":[Vector2(-14,-3),Vector2(8,-3)], "hands":[Vector2(-3,-15),Vector2(15,-5)], "tilt":0.35, "head":Vector2(1,2), "gear":Vector2(0,0), "gear_swing":1, "hair_swing":1, "blink":true},
	{"hold":1, "hip":Vector2(-4,-12), "shoulder":Vector2(-15,-25), "feet":[Vector2(-12,-3),Vector2(12,-6)], "hands":[Vector2(-16,-31),Vector2(5,-27)], "tilt":-0.13, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":-1, "hair_swing":-1, "blink":true},
	{"hold":1, "hip":Vector2(-2,-12), "shoulder":Vector2(-18,-16), "feet":[Vector2(14,-5),Vector2(21,-7)], "hands":[Vector2(-26,-12),Vector2(-8,-24)], "tilt":0.05, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":-1, "blink":true},
	{"hold":1, "hip":Vector2(0,-12), "shoulder":Vector2(-17,-12), "feet":[Vector2(18,-5),Vector2(25,-6)], "hands":[Vector2(-25,-5),Vector2(-9,-20)], "tilt":0.16, "head":Vector2(0,-1), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":1, "blink":true},
	{"hold":2, "hip":Vector2(0,-13), "shoulder":Vector2(-17,-13), "feet":[Vector2(18,-3),Vector2(25,-4)], "hands":[Vector2(-25,-3),Vector2(-9,-17)], "tilt":0.10, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":0, "blink":true},
]

## Get-up after a revival over the rise progress 0..1 (MedicalCatalog
## RECOVERY_TIME, 1.1 s: about 10 frames per second): eyes open, roll onto an
## elbow, sit up and draw a knee, kneel, push up off the knee, stand with the
## pack settling, then the plain stance. `until` is the progress at which a
## key ends.
const RISE_KEYS := [
	{"until":0.12, "hip":Vector2(0,-13), "shoulder":Vector2(-17,-13), "feet":[Vector2(18,-3),Vector2(25,-4)], "hands":[Vector2(-25,-3),Vector2(-9,-17)], "tilt":0.0, "head":Vector2(0,-1), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":0, "blink":false},
	{"until":0.24, "hip":Vector2(0,-13), "shoulder":Vector2(-15,-21), "feet":[Vector2(17,-3),Vector2(24,-4)], "hands":[Vector2(-21,-3),Vector2(-3,-15)], "tilt":0.05, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":-1, "blink":false},
	{"until":0.36, "hip":Vector2(-1,-13), "shoulder":Vector2(-13,-25), "feet":[Vector2(15,-3),Vector2(22,-3)], "hands":[Vector2(-20,-3),Vector2(0,-14)], "tilt":0.10, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":0, "hair_swing":-1, "blink":false},
	{"until":0.48, "hip":Vector2(-2,-12), "shoulder":Vector2(-6,-28), "feet":[Vector2(9,-3),Vector2(18,-3)], "hands":[Vector2(-14,-3),Vector2(8,-12)], "tilt":0.15, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":1, "hair_swing":0, "blink":false},
	{"until":0.62, "hip":Vector2(-5,-13), "shoulder":Vector2(3,-28), "feet":[Vector2(-17,-3),Vector2(11,-3)], "hands":[Vector2(-9,-17),Vector2(17,-6)], "tilt":0.22, "head":Vector2(0,0), "gear":Vector2(0,0), "gear_swing":1, "hair_swing":1, "blink":false},
	{"until":0.76, "hip":Vector2(-3,-19), "shoulder":Vector2(4,-35), "feet":[Vector2(-12,-3),Vector2(10,-3)], "hands":[Vector2(-4,-22),Vector2(13,-18)], "tilt":0.15, "head":Vector2(0,0), "gear":Vector2(0,1), "gear_swing":0, "hair_swing":1, "blink":false},
	{"until":0.90, "hip":Vector2(-1,-24), "shoulder":Vector2(1,-41), "feet":[Vector2(-8,-3),Vector2(7,-3)], "hands":[Vector2(-10,-27),Vector2(10,-26)], "tilt":0.05, "head":Vector2(0,0), "gear":Vector2(0,1), "gear_swing":-1, "hair_swing":0, "blink":false},
]

## Collapse progress 0..1 to its key; the last key holds.
static func collapse_seconds() -> float:
	var total := 0
	for key: Dictionary in COLLAPSE_KEYS: total += int(key.hold)
	return float(total)/COLLAPSE_FPS

static func collapse_key(elapsed: float) -> Dictionary:
	var frame := floori(maxf(0.0, elapsed)*COLLAPSE_FPS)
	for key: Dictionary in COLLAPSE_KEYS:
		frame -= int(key.hold)
		if frame<0: return key
	return COLLAPSE_KEYS[-1]

## Rise progress 0..1 to its key; {} after the last key (the plain stance).
static func rise_key(progress: float) -> Dictionary:
	for key: Dictionary in RISE_KEYS:
		if progress<float(key.until): return key
	return {}

## A collapse or rise key as a full rig pose over `base` (its stance values).
static func body_pose(base: Dictionary, key: Dictionary) -> Dictionary:
	var pose := base.duplicate(true)
	if key.is_empty(): return pose
	pose.hip = key.hip
	pose.shoulder = key.shoulder
	pose.feet = [key.feet[0], key.feet[1]]
	pose.hands = [key.hands[0], key.hands[1]]
	pose.head_tilt = float(key.tilt)
	pose.head_shift = key.head
	pose.gear = key.gear
	pose.gear_swing = int(key.gear_swing)
	pose.hair_swing = int(key.hair_swing)
	pose.blink = bool(key.blink)
	return pose

# ------------------------------------------------------------------ tending
## Tending a running machine at 8 frames per second (12 frames, 1.5 s): the
## worker knocks the turning drum twice with a mallet to free the mix (wind-up,
## swing, contact, rebound; a smaller second blow), then lowers the mallet and
## watches the drum mouth, head raised. The torso rocks into each blow; pack
## and hair answer it. A load stays held on the near hip by the rear hand.
## Hand targets and tool angles are local to the drawn facing. The two contact
## keys carry `hit`: WorkerVisual knocks the drum (MixerAnimation.knock) on the
## frame each one begins.
const TEND_FPS := 8.0
const TEND_KEYS := [
	{"hold":2, "hand":Vector2(12,-51), "angle":-1.1, "shoulder":Vector2(-1,0), "tilt":-0.13, "gear_swing":0, "hair_swing":0},
	{"hold":1, "hand":Vector2(17,-46), "angle":-0.4, "shoulder":Vector2(1,0), "tilt":-0.13, "gear_swing":0, "hair_swing":0},
	{"hold":1, "hand":Vector2(19,-42), "angle":0.15, "shoulder":Vector2(2,1), "tilt":0.0, "gear_swing":1, "hair_swing":0, "hit":true},
	{"hold":1, "hand":Vector2(16,-45), "angle":-0.35, "shoulder":Vector2(1,0), "tilt":0.0, "gear_swing":0, "hair_swing":1},
	{"hold":1, "hand":Vector2(13,-49), "angle":-0.9, "shoulder":Vector2(0,0), "tilt":-0.13, "gear_swing":-1, "hair_swing":0},
	{"hold":1, "hand":Vector2(19,-42), "angle":0.15, "shoulder":Vector2(2,1), "tilt":0.0, "gear_swing":1, "hair_swing":-1, "hit":true},
	{"hold":2, "hand":Vector2(14,-40), "angle":-0.25, "shoulder":Vector2(1,0), "tilt":0.0, "gear_swing":0, "hair_swing":1},
	{"hold":3, "hand":Vector2(10,-32), "angle":0.6, "shoulder":Vector2(0,0), "tilt":-0.26, "gear_swing":0, "hair_swing":0},
]
## Lean of the tending torso towards the machine (radians).
const TEND_LEAN := 0.2
## The struck face of the mallet head in the tool's frame (WorkerPoseArt).
const MALLET_FACE := Vector2(13, -3)

static func tend_frames() -> int:
	var total := 0
	for key: Dictionary in TEND_KEYS: total += int(key.hold)
	return total

static func tend_key(clock: float) -> Dictionary:
	var frame := posmod(floori(maxf(0.0, clock)*TEND_FPS), tend_frames())
	for key: Dictionary in TEND_KEYS:
		frame -= int(key.hold)
		if frame<0: return key
	return TEND_KEYS[-1]

## The tending pose on a standing `base` (planted boots and hips kept), with a
## held load moved to the near hip when `cargo_kind` is set.
static func tend_pose(base: Dictionary, clock: float, cargo_kind: String="") -> Dictionary:
	var key := tend_key(clock)
	var pose := base.duplicate(true)
	pose.shoulder = Vector2(pose.hip)+(Vector2(sin(TEND_LEAN), -cos(TEND_LEAN))*17.0).round()+Vector2(key.shoulder)
	pose.head_tilt = -TEND_LEAN*0.65+float(key.tilt)
	pose.head_shift = Vector2(1, 1)
	pose.hands = [Vector2(pose.hip)+Vector2(-4, 3), key.hand]
	pose.prop = "work_hammer"
	pose.work_tool_angle = float(key.angle)
	pose.work_action = "tend"
	pose.gear = Vector2.ZERO
	pose.gear_swing = int(key.gear_swing)
	pose.hair_swing = int(key.hair_swing)
	pose.erase("foot_angles")
	if not cargo_kind.is_empty():
		pose.cargo = Vector2(pose.hip)+Vector2(-1, 1)
		pose.cargo_kind = cargo_kind
		pose.cargo_pour = false
		pose.hands[0] = Vector2(pose.cargo)+Vector2(-5, 1)
	else:
		pose.erase("cargo")
	# Hands are the grips: bring the chest towards them rather than letting a
	# glove float off the mallet (same rule as WorkerWorkPose; the shoulder
	# sockets of WorkerPoseArt.shoulder_local on its torso_transform).
	for unused in 6:
		var up: Vector2 = (Vector2(pose.shoulder)-Vector2(pose.hip)).normalized()
		var body := Transform2D(up.angle()+PI*0.5, pose.shoulder)
		for index in 2:
			var offset: Vector2 = pose.hands[index]-body*Vector2(-6 if index==0 else 3, 0)
			if offset.length()>22.65:
				pose.shoulder = Vector2(pose.shoulder)+offset.normalized()*(offset.length()-22.65)
	return pose

# ------------------------------------------------------------------ walk
## Walk and run (pass 7A-crew): four held keys per step on the stride phase
## of WorkerLocomotion (contact, down, passing, up) carry the body bob in
## texels, the chest's lean and the follow-through: the head lags the bob a
## key, the pack lifts late and lands late, pack and hair swing against each
## change of direction. The legs stay on the continuous world-planted gait
## (no foot slides) and roll heel to toe (walk_foot_angle); the arms swing on
## arcs (the forward hand rises towards the chest).
const WALK_KEYS := [
	{"bob":0.0, "lean":0.0, "head":0.0, "gear":Vector2(0,-1), "gear_swing":1, "hair_swing":0},
	{"bob":1.5, "lean":-1.0, "head":-1.0, "gear":Vector2(0,0), "gear_swing":0, "hair_swing":1},
	{"bob":0.5, "lean":0.0, "head":0.0, "gear":Vector2(0,1), "gear_swing":-1, "hair_swing":0},
	{"bob":-1.0, "lean":1.0, "head":1.0, "gear":Vector2(0,0), "gear_swing":-1, "hair_swing":-1},
]
## Heel strike (toe up), toe-off (heel up) and the hanging toe of the swing,
## in radians of WorkerPoseArt.foot_transform (+ lifts the heel).
const WALK_TOE_UP := -0.25
const WALK_HEEL_UP := 0.4

## The body key at stride `phase` (one cycle is two steps; a boot touches
## down at every half cycle).
static func walk_key(phase: float) -> Dictionary:
	return WALK_KEYS[posmod(floori(phase*8.0), WALK_KEYS.size())]

## Roll of a boot over its own gait cycle `cycle` (WorkerLocomotion.foot) with
## the stance share `stance`: toe up at the heel strike, flat, heel rising to
## the toe-off, toe hanging early in the swing and lifting before contact.
static func walk_foot_angle(cycle: float, stance: float) -> float:
	var t := fposmod(cycle, 1.0)
	if t < stance:
		if t < 0.1: return WALK_TOE_UP*(1.0-t/0.1)
		return WALK_HEEL_UP*smoothstep(stance-0.16, stance, t)
	var swing := (t-stance)/(1.0-stance)
	return WALK_HEEL_UP*(1.0-smoothstep(0.0, 0.4, swing))+WALK_TOE_UP*smoothstep(0.6, 1.0, swing)

# ------------------------------------------------------------------ revive
## Reviving a downed crew mate (pass 7A-crew). The reviver kneels beside the
## body instead of leaning over its legs as one rotated block: the drawn rig
## slides along the body by `aid_offset` (presentation only; the collider,
## position and aid range stay where they are) so the hands land on the chest
## from a kneel, and WorkerVisual draws the reviver behind the patient, whose
## body then covers the far knee and shins. It steps in through two keys
## (12 fps): a step towards the chest, a lunge down; kneels and presses at
## 8 fps (press, hold, release, hold; the shoulders over straight arms, the
## head down; quicker for a critical patient), and after the revival pushes
## up off the front knee, rises and steps back to its own place through four
## keys at 10 fps with the pack settling. Moving or acting ends the rise at
## once. Joints are local to the drawn facing, in texels from the boots.
const AID_FPS := 12.0
## Where the kneeling hands rest naturally, in front of the kneel.
const AID_HANDS := Vector2(12, -19)
const AID_MAX_OFFSET := 32.0
const AID_KNEEL := {"hip":Vector2(0,-16), "shoulder":Vector2(6,-32), "feet":[Vector2(-14,-3), Vector2(10,-3)]}
const AID_ENTRY := [
	{"hip":Vector2(1,-24), "shoulder":Vector2(5,-40), "feet":[Vector2(-6,-3), Vector2(9,-7)], "hands":[Vector2(-2,-26), Vector2(10,-29)], "offset":0.35, "tilt":0.1, "gear_swing":-1, "hair_swing":-1},
	{"hip":Vector2(0,-18), "shoulder":Vector2(6,-34), "feet":[Vector2(-11,-4), Vector2(11,-3)], "hands":[Vector2(7,-19), Vector2(12,-20)], "offset":0.75, "tilt":0.2, "gear_swing":1, "hair_swing":0},
]
## Press loop: shoulder and hand offsets over the kneel, held frames.
const AID_PRESS := [
	{"hold":1, "shoulder":Vector2(1,2), "hands":Vector2(0,1), "tilt":0.26},
	{"hold":1, "shoulder":Vector2(1,2), "hands":Vector2(0,1), "tilt":0.26},
	{"hold":1, "shoulder":Vector2(0,0), "hands":Vector2(0,0), "tilt":0.2},
	{"hold":1, "shoulder":Vector2(-1,-1), "hands":Vector2(0,0), "tilt":0.13},
]
const AID_PRESS_FPS := {"aid_revive":8.0, "aid_resuscitate":10.0}
const AID_RISE_FPS := 10.0
const AID_RISE := [
	{"hip":Vector2(0,-15), "shoulder":Vector2(7,-30), "feet":[Vector2(-14,-3), Vector2(10,-3)], "hands":[Vector2(9,-18), Vector2(11,-17)], "offset":1.0, "tilt":0.2, "gear_swing":0, "hair_swing":0},
	{"hip":Vector2(-1,-20), "shoulder":Vector2(3,-36), "feet":[Vector2(-9,-3), Vector2(9,-3)], "hands":[Vector2(6,-23), Vector2(9,-22)], "offset":0.65, "tilt":0.1, "gear_swing":-1, "hair_swing":-1},
	{"hip":Vector2(-1,-24), "shoulder":Vector2(1,-41), "feet":[Vector2(-5,-6), Vector2(5,-3)], "hands":[Vector2(-4,-25), Vector2(6,-26)], "offset":0.3, "tilt":0.0, "gear_swing":1, "hair_swing":0},
	{"offset":0.0, "gear_swing":-1, "hair_swing":1},
]

## The drawn rig's slide towards the patient's chest (texels along the drawn
## facing) for a hand target `reach` in the same frame.
static func aid_offset(reach: Vector2) -> float:
	return clampf(roundf(reach.x-AID_HANDS.x), 0.0, AID_MAX_OFFSET)

static func aid_rise_seconds() -> float:
	return float(AID_RISE.size())/AID_RISE_FPS

static func _shift(pose: Dictionary, offset: float) -> void:
	var by := Vector2(offset, 0.0)
	pose.hip = Vector2(pose.hip)+by
	pose.shoulder = Vector2(pose.shoulder)+by
	for key in ["feet", "hands"]:
		pose[key] = [Vector2(pose[key][0])+by, Vector2(pose[key][1])+by]

static func _key_pose(pose: Dictionary, key: Dictionary) -> void:
	for name in ["hip", "shoulder"]:
		if key.has(name): pose[name] = key[name]
	for name in ["feet", "hands"]:
		if key.has(name): pose[name] = [key[name][0], key[name][1]]
	if key.has("tilt"): pose.head_tilt = float(key.tilt)
	pose.gear_swing = int(key.get("gear_swing", 0))
	pose.hair_swing = int(key.get("hair_swing", 0))

## The reviver at `elapsed` seconds into the aid on a `base` stance, for a
## chest target `reach`: the entry keys, then the kneel and its press loop.
static func aid_pose(base: Dictionary, reach: Vector2, elapsed: float, kind: String) -> Dictionary:
	var pose := base.duplicate(true)
	pose.erase("foot_angles")
	pose.hip_spread = 2.0
	pose.aid = true
	pose.head_shift = Vector2(1, 2)
	var offset := aid_offset(reach)
	var entry := floori(maxf(0.0, elapsed)*AID_FPS)
	if entry < AID_ENTRY.size():
		var key: Dictionary = AID_ENTRY[entry]
		_key_pose(pose, key)
		_shift(pose, roundf(offset*float(key.offset)))
		return pose
	pose.hip = AID_KNEEL.hip
	pose.shoulder = AID_KNEEL.shoulder
	pose.feet = [AID_KNEEL.feet[0], AID_KNEEL.feet[1]]
	var fps: float = AID_PRESS_FPS.get(kind, 8.0)
	var press: Dictionary = AID_PRESS[posmod(floori((elapsed-float(AID_ENTRY.size())/AID_FPS)*fps), AID_PRESS.size())]
	pose.shoulder = Vector2(pose.shoulder)+Vector2(press.shoulder)
	pose.head_tilt = float(press.tilt)
	pose.gear_swing = 1 if press.shoulder.y > 0 else 0
	pose.hair_swing = -1 if press.shoulder.y > 0 else 0
	_shift(pose, offset)
	# Both hands on the chest, the near one over the far one.
	var hand := reach+Vector2(press.hands)
	pose.hands = [hand+Vector2(-2,-1), hand+Vector2(1,0)]
	_shoulders_to_hands(pose)
	return pose

## Arms straight to their grips: bring the shoulders towards the hands rather
## than stretching a glove off its arm (same rule as tend_pose).
static func _shoulders_to_hands(pose: Dictionary) -> void:
	for unused in 6:
		var up: Vector2 = (Vector2(pose.shoulder)-Vector2(pose.hip)).normalized()
		var body := Transform2D(up.angle()+PI*0.5, pose.shoulder)
		for index in 2:
			var to_hand: Vector2 = pose.hands[index]-body*Vector2(-6 if index==0 else 3, 0)
			if to_hand.length()>22.65:
				pose.shoulder = Vector2(pose.shoulder)+to_hand.normalized()*(to_hand.length()-22.65)

## Bandaging a crew mate on their feet (also straight after a revival, once
## the reviver has risen): standing a step closer (treat_offset, presentation
## only like the kneel's slide), both hands at the wound wrapping at 8 fps,
## the head down to the work. The earlier pose knelt and reached up to a
## standing chest.
const TREAT_FPS := 8.0
const TREAT_WRAP := [Vector2(0,0), Vector2(1,-1), Vector2(1,-2), Vector2(0,-1)]
## Where standing hands work naturally, in front of the boots.
const TREAT_HANDS := 13.0
const TREAT_MAX_OFFSET := 24.0

static func treat_offset(reach: Vector2) -> float:
	return clampf(roundf(reach.x-TREAT_HANDS), 0.0, TREAT_MAX_OFFSET)

static func treat_pose(base: Dictionary, reach: Vector2, elapsed: float) -> Dictionary:
	var pose := base.duplicate(true)
	pose.erase("foot_angles")
	pose.aid = true
	pose.bandage = true
	_shift(pose, treat_offset(reach))
	var turn: Vector2 = TREAT_WRAP[posmod(floori(maxf(0.0, elapsed)*TREAT_FPS), TREAT_WRAP.size())]
	pose.hands = [reach+Vector2(-2,0)+turn*Vector2(-1,1), reach+Vector2(2,1)+turn]
	pose.head_tilt = 0.2
	pose.head_shift = Vector2(1, 1)
	pose.gear_swing = 0
	pose.hair_swing = 1 if turn.y < -1.5 else 0
	_shoulders_to_hands(pose)
	return pose

## The reviver getting up at `elapsed` seconds after the revival, from a kneel
## slid by `offset` back to the standing `stance` (returned unchanged at the
## end), which itself stands `rest_offset` along (a standing treatment).
static func aid_rise_pose(stance: Dictionary, elapsed: float, offset: float, rest_offset: float = 0.0) -> Dictionary:
	var index := floori(maxf(0.0, elapsed)*AID_RISE_FPS)
	if index >= AID_RISE.size(): return stance
	var pose := stance.duplicate(true)
	var key: Dictionary = AID_RISE[index]
	if not key.has("hip"):
		_key_pose(pose, key)
		return pose
	_key_pose(pose, key)
	pose.erase("foot_angles")
	_shift(pose, roundf(lerpf(rest_offset, offset, float(key.offset))))
	return pose

# ------------------------------------------------------------------ dance
## A one-bar groove of rhythm poses laid over every standing dance (pass
## 7A-crew), on the heard beat grid of WorkerRhythmPose: each pose lands on its
## kick and holds, then eases into the next one through the rest of the beat.
## Beat 1 punches both arms forward, beat 2 pumps them down, beat 3 throws
## both up (the near one up and forward, clear of the face; the far one up and
## back over the pack), beat 4 points the near arm high; the weight steps
## from foot to foot on every beat (hips two texels to the side, the free heel
## lifting, the shoulders answering) and the head looks up with the raised
## arms and down with the pump. `hands` moves each glove in screen texels
## ([far, near]) before the arm is held to its reach about its own shoulder:
## a plain translation, so each dance keeps its own arm carriage underneath
## and no arm can whip faster than its dance and the key move together.
const DANCE_HOLD := 0.25
const DANCE_KEYS := [
	{"hands":[Vector2(10,-8), Vector2(14,-6)], "hip":Vector2(-2, 1), "lean":1.0, "look":0.05, "heels":[0.0, 0.3]},
	{"hands":[Vector2(-6,8), Vector2(-4,8)], "hip":Vector2(2, 2), "lean":1.0, "look":0.10, "heels":[0.3, 0.0]},
	{"hands":[Vector2(-7,-26), Vector2(6,-32)], "hip":Vector2(-2, 1), "lean":-1.0, "look":-0.13, "heels":[0.0, 0.3]},
	{"hands":[Vector2(-2,-2), Vector2(10,-32)], "hip":Vector2(2, 2), "lean":0.0, "look":-0.18, "heels":[0.3, 0.0]},
]
## The groove key at `beats` (audible beats; beat 0 of a bar is the downbeat).
static func dance_key(beats: float) -> Dictionary:
	var count := DANCE_KEYS.size()
	var index := posmod(floori(beats), count)
	var here: Dictionary = DANCE_KEYS[index]
	var next: Dictionary = DANCE_KEYS[(index+1)%count]
	var t := smoothstep(DANCE_HOLD, 1.0, fposmod(beats, 1.0))
	return {
		"hands":[Vector2(here.hands[0]).lerp(next.hands[0], t), Vector2(here.hands[1]).lerp(next.hands[1], t)],
		"hip":Vector2(here.hip).lerp(Vector2(next.hip), t),
		"lean":lerpf(float(here.lean), float(next.lean), t),
		"look":lerpf(float(here.look), float(next.look), t),
		"heels":[lerpf(float(here.heels[0]), float(next.heels[0]), t), lerpf(float(here.heels[1]), float(next.heels[1]), t)],
	}
