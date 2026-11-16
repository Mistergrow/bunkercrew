extends Node2D
## Hostile human anatomy: the articulated rig of the crew (bones, contacts,
## held performances) drawn as the hand-pixelled field kit at its drawn size.
## Helmets, webbing, scarves, weapons and limbs are separate parts of the
## world-texel kit (InfantryArtAtlas, tools/bake_infantry_world.py), drawn
## 1:1 on whole world texels in an art frame whose unit is one rig unit
## times the human factor 0.82 (style bible §1). The rig node keeps that
## scale, so muzzles, weather, gore and hitboxes read the same bones.
const RoleArt := preload("res://scripts/infantry_role_art.gd")
const Atlas := preload("res://scripts/infantry_art_atlas.gd")
const Rhythm := preload("res://scripts/rhythm_presentation.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const Quads := preload("res://scripts/canvas_quads.gd")
var soldier: Node2D
var pose: Dictionary = WorkerPoseArt.neutral()
var gun := Transform2D.IDENTITY
var troop_kind := "rifle_guard"
var squad_slot := 0
var corpse := false
var corpse_age := 0.0
var fall_start: Dictionary = {}
var fall_gun := Transform2D.IDENTITY
var calm := false
var reload_phase := 0.0
var treating := false
var cloth_sway := 0.0
var gore_mask:=0
var effects: Node
## Drawn pose and gun: the combat-coupled `pose`/`gun` (muzzle, body height,
## weather, gore and test anchors) plus presentation layers only, namely
## stride weight, anticipation, recoil, reload handling and hit knockback.
var shown: Dictionary = {}
var shown_gun := Transform2D.IDENTITY
var _seen_shots := -1
var _shot_age := 10.0
var _charge := 0.0
var _dissolve := 0.0
var _rest := 1.0
## Whole-texel lag of the pack behind the torso (follow-through).
var _pack := Vector2.ZERO
## Keys the drawn weapon climbs for the first frames of a shot's kick.
var _recoil_keys := 0
static var remains_material: ShaderMaterial

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if corpse:
		add_to_group("infantry_remains")
		if remains_material==null:
			remains_material=ShaderMaterial.new()
			remains_material.shader=preload("res://shaders/ground_infantry_remains.gdshader")
		material=remains_material
		set_instance_shader_parameter("ground_level",global_position.y)

func _process(delta: float) -> void:
	if corpse:
		corpse_age+=delta
		if corpse_age>3.0:
			queue_free()
			return
		# Held body frames (style bible 5): the staged fall is sampled at
		# BODY_FPS, so kneel, topple and rebound read as drawn poses.
		var frame_age := held(corpse_age,BODY_FPS)
		pose=fall_pose(fall_start,frame_age,calm,squad_slot)
		gun=fall_gun_transform(fall_gun,frame_age,calm)
		shown=pose
		shown_gun=gun
		cloth_sway=0.0
		treating=false
		reload_phase=0.0
		# The body leaves texel by texel in an ordered dither (shader), not as a
		# translucent ghost; the timing and the 3 s lifetime are unchanged.
		var dissolve := snappedf(smoothstep(2.25,3.0,corpse_age),1.0/16.0)
		if dissolve!=_dissolve:
			_dissolve=dissolve
			set_instance_shader_parameter(&"dissolve",dissolve)
	else:
		if not is_instance_valid(soldier): return
		update_pose()
		compose(delta)
		var alpha := modulate.a
		WeaponEffectArt.strike(self,soldier.hit_flash,WeaponEffectArt.reduced(soldier.game))
		modulate.a = alpha
	queue_redraw()

## Staged defeat, a pure function of corpse age (hosts and guests match): the
## hit throws the shoulders back, the knees give way into a slumped kneel with
## the head dropping and the weapon slipping out of the hands, the body then
## topples backwards under gravity, strikes the floor with a damped rebound,
## and the arms flop down last (overlapping action). At BODY_FPS the topple
## spans four drawn frames.
const FALL_RECOIL := 0.10
const FALL_KNEEL := 0.36
const FALL_CONTACT := 0.66
const FALL_ARMS := 0.80
const GUN_RELEASE := 0.12
const GUN_GRAVITY := 900.0
## The lying body (rig units, facing right, ground at y = 0): on its back,
## shoulders propped on the pack so the chest slopes down to the belt, the
## head rolled back, toes up. Odd squad slots lie with one knee raised and
## the rear arm flung past the helmet, even slots with the legs out straight,
## one arm across the chest and the other on the ground at the side, so a
## squad's fallen do not repeat one silhouette.
const LYING := [
	{"hip":Vector2(-3,-8),"shoulder":Vector2(-19,-13),"feet":[Vector2(17,-4),Vector2(20,-4)],
		"hands":[Vector2(-27,-3),Vector2(-6,-16)],"foot_angles":[-PI*0.5,-PI*0.5],"head_tilt":0.05,"head_shift":Vector2(0,2)},
	{"hip":Vector2(-3,-8),"shoulder":Vector2(-19,-13),"feet":[Vector2(9,-4),Vector2(19,-4)],
		"hands":[Vector2(-38,-5),Vector2(-8,-17)],"foot_angles":[0.0,-PI*0.5],"head_tilt":0.0,"head_shift":Vector2(0,2)},
]

static func lying_pose(slot: int) -> Dictionary:
	return LYING[posmod(slot+1,LYING.size())]

## Topple from the kneel to the floor: accelerating like a falling body.
static func fall_progress(age: float) -> float:
	var drop := clampf((age-FALL_KNEEL)/(FALL_CONTACT-FALL_KNEEL),0,1)
	return drop*drop

static func fall_settle(age: float) -> float:
	var since := age-FALL_CONTACT
	return -sin(since*26.0)*exp(-since*10.0)*2.0 if since>0 else 0.0

static func fall_kneel(start: Dictionary) -> Dictionary:
	var result := start.duplicate(true)
	result.hip = Vector2(-5,-13)
	result.shoulder = Vector2(-9,-29)
	result.feet = [Vector2(-15,-3),Vector2(maxf(4.0,Vector2(start.feet[1]).x),-3)]
	result.hands = [Vector2(-8,-15),Vector2(1,-13)]
	result.head_tilt = 0.32
	result.head_shift = Vector2(1,1)
	return result

static func fall_pose(start: Dictionary, age: float, quiet: bool = false, slot: int = 0) -> Dictionary:
	var lying := lying_pose(slot)
	var kneel := fall_kneel(start)
	var result := start.duplicate(true)
	# Reduced effects keep the same timing without the snap back and rebounds.
	var jolt := 0.0 if quiet else sin(clampf(age/(FALL_RECOIL*2.0),0,1)*PI)
	var buckle := smoothstep(FALL_RECOIL*0.5,FALL_KNEEL,age)
	buckle *= buckle*(2.0-buckle)
	var drop := fall_progress(age)
	var settle := 0.0 if quiet else fall_settle(age)
	var spines: Array[Vector2] = [Vector2(start.shoulder)-Vector2(start.hip),Vector2(kneel.shoulder)-Vector2(kneel.hip),Vector2(lying.shoulder)-Vector2(lying.hip)]
	# The spine rotates about the hip at its real length, so the shoulders
	# travel on an arc instead of the torso shortening through a straight blend.
	var angle := lerp_angle(lerp_angle(spines[0].angle()-0.25*jolt,spines[1].angle(),buckle),spines[2].angle(),drop)
	var length := lerpf(lerpf(spines[0].length(),spines[1].length(),buckle),spines[2].length(),drop)
	result.hip = (Vector2(start.hip)+Vector2(-2.5*jolt,0)).lerp(kneel.hip,buckle).lerp(lying.hip,drop)+Vector2(0,settle*0.5)
	result.shoulder = Vector2(result.hip)+Vector2.from_angle(angle)*length+Vector2(0,settle*0.5)
	var legs := smoothstep(0.0,1.0,minf(1.0,drop*1.4))
	var arms := clampf((age-FALL_KNEEL)/(FALL_ARMS-FALL_KNEEL),0,1)
	arms *= arms
	var limp := smoothstep(GUN_RELEASE,FALL_KNEEL,age)
	var flop := 0.0 if quiet or age<FALL_ARMS else -sin((age-FALL_ARMS)*22.0)*exp(-(age-FALL_ARMS)*9.0)*2.5
	var rolls: Array = start.get("foot_angles",[0.0,0.0])
	var roll_to: Array = lying.foot_angles
	for index in 2:
		result.feet[index] = Vector2(start.feet[index]).lerp(kneel.feet[index],buckle).lerp(lying.feet[index],legs)
		var flung: Vector2 = Vector2(start.hands[index])+Vector2(-4,-7 if index==0 else -4)*jolt
		result.hands[index] = flung.lerp(kneel.hands[index],limp).lerp(lying.hands[index],arms)+Vector2(0,flop)
	result.foot_angles = [lerpf(float(rolls[0])*(1.0-buckle),float(roll_to[0]),legs),lerpf(float(rolls[1])*(1.0-buckle),float(roll_to[1]),legs)]
	result.head_tilt = lerpf(lerpf(float(start.head_tilt)-0.35*jolt,float(kneel.head_tilt),buckle),float(lying.head_tilt),drop)-settle*0.05
	result.head_shift = Vector2(start.head_shift).lerp(kneel.head_shift,buckle).lerp(lying.head_shift,drop)
	return result

## The weapon slips from the hands as the knees give way, drops under gravity
## while its muzzle dips, lands in front of the body and kicks once.
static func fall_gun_transform(start: Transform2D, age: float, quiet: bool = false) -> Transform2D:
	var since := maxf(0.0,age-GUN_RELEASE)
	var ground := -7.0
	var height := maxf(0.0,ground-start.origin.y)
	var landing := maxf(0.05,sqrt(2.0*height/GUN_GRAVITY))
	var flight := clampf(since/landing,0,1)
	var origin := Vector2(start.origin.x+24.0*flight,minf(ground,start.origin.y+GUN_GRAVITY*since*since*0.5))
	var turn := lerp_angle(start.get_rotation(),0.06,smoothstep(0.0,1.0,flight))+0.35*sin(flight*PI)
	var after := since-landing
	if after>0.0 and after<0.16 and not quiet:
		origin.y -= 3.0*sin(after/0.16*PI)
		turn -= 0.10*sin(after/0.16*PI)
	return Transform2D(turn,origin)

## Walk per role (style bible 5: held body keys, planted soles): `keys` per
## cycle (8-12 drawn frames a second at the role's gait rate), `stride`
## lengthens each step against the gait clock (the planted boot still moves
## back by exactly the ground travel), `crouch` lowers and `lean` pitches the
## body, `bob` is the drop at each heel strike, `lift` the swinging boot,
## `pitch` the chest's rock per step, `sway` the carried weapon's swing.
## Rifle guard and medic march, the grenadier crouch-walks behind the
## launcher, the scout trots, the heavy gunner plods, the marksman stalks.
const WALK := {
	"rifle_guard": {"keys":8, "stride":1.25, "crouch":0.0, "lean":2.0, "bob":3.2, "lift":6.5, "pitch":1.8, "sway":0.12},
	"grenadier": {"keys":8, "stride":1.15, "crouch":4.0, "lean":5.0, "bob":3.6, "lift":6.0, "pitch":2.4, "sway":0.14},
	"scout": {"keys":6, "stride":1.0, "crouch":1.0, "lean":4.5, "bob":2.8, "lift":8.0, "pitch":1.6, "sway":0.18},
	"heavy_gunner": {"keys":8, "stride":1.15, "crouch":1.5, "lean":2.5, "bob":4.2, "lift":5.0, "pitch":1.2, "sway":0.08},
	"marksman": {"keys":8, "stride":1.30, "crouch":3.0, "lean":3.0, "bob":2.4, "lift":5.5, "pitch":1.2, "sway":0.08},
	"combat_medic": {"keys":8, "stride":1.25, "crouch":0.5, "lean":2.5, "bob":3.0, "lift":6.0, "pitch":1.6, "sway":0.12},
}

func walk_style() -> Dictionary:
	return WALK.get(troop_kind,WALK.rifle_guard)

## The walk phase (gait clock over the stride factor) and its held key.
func walk_phase() -> float:
	return gait_phase()/float(walk_style().stride)

func walk_key() -> float:
	var step := TAU/float(walk_style().keys)
	return floorf(walk_phase()/step+0.0001)*step

func update_pose() -> void:
	if not is_instance_valid(soldier): return
	troop_kind=soldier.kind
	squad_slot=soldier.squad_slot
	scale=Vector2(soldier.attack_direction,1)*soldier.visual_scale
	var role := RoleArt.spec(troop_kind)
	var walk := walk_style()
	var kneel: float=soldier.stance
	var phase := walk_phase()
	var keyed := walk_key()
	var bob: float=absf(sin(keyed))*float(role.bob) if soldier.moving else sin(soldier.age*2.1+squad_slot)*.25
	cloth_sway=snappedf(sin(keyed*.75+squad_slot)*1.3+(2.0 if soldier.moving else 0.0),1.0)
	treating=troop_kind=="combat_medic" and is_instance_valid(soldier.abilities) and soldier.abilities.repair_flash>0
	pose=WorkerPoseArt.neutral()
	pose.hip=Vector2(-1,float(role.hip_y)+bob).lerp(Vector2(-5,float(role.kneel_y)),kneel)
	pose.shoulder=Vector2(float(role.lean),float(role.hip_y)-17+bob).lerp(Vector2(float(role.kneel_lean),float(role.kneel_y)-17),kneel)
	pose.shoulder+=Vector2(-3,1)*sin(clampf(soldier.hit_flash/.2,0,1)*PI)
	# Boots: the planted sole travels back by exactly the body's ground travel
	# (replicated speed), so it never slides; the role's stride lengthens the
	# step against the gait clock. Step height fades with speed so halting sets
	# the raised boot down instead of snapping it. These are the continuous
	# contacts (weather, footsteps); compose() holds the swing in walk keys.
	var travel: float=soldier.stride_per_radian()*float(walk.stride)
	var step_height: float=float(walk.lift)*soldier.stride_amount()
	for index in 2:
		var leg := phase+(0.0 if index==0 else PI)
		pose.feet[index]=Vector2((-6.0 if index==0 else 6.0)-SiegeMachine.stride_offset(leg,travel),-4-maxf(0,cos(leg))*step_height)
	pose.feet[0]=Vector2(pose.feet[0]).lerp(Vector2(-float(role.spread)-3,-4),kneel)
	pose.feet[1]=Vector2(pose.feet[1]).lerp(Vector2(float(role.spread),-4),kneel)
	var aim: Vector2=soldier.target_attack_point()
	if is_instance_valid(soldier.abilities) and soldier.abilities.aim_locked: aim=soldier.abilities.aim_point
	elif soldier.muzzle_flash>0: aim=soldier.to_global(soldier.tracer_end)
	var anchor: Vector2=Vector2(pose.shoulder)+Vector2(4-soldier.weapon_recoil*.5,float(role.gun_y))
	var origin: Vector2=soldier.to_global(Vector2(anchor.x*soldier.attack_direction,anchor.y)*soldier.visual_scale)
	var direction: Vector2=aim-origin
	if troop_kind=="grenadier" and is_instance_valid(soldier.abilities): direction=soldier.abilities.launch_velocity(origin,aim)
	var angle:=clampf(Vector2(direction.x*soldier.attack_direction,direction.y).angle(),-.9,.65)
	if soldier.moving: angle=lerpf(angle,float(role.carry),.65)
	if treating: angle=.85
	gun=Transform2D(angle,anchor)
	pose.hands=[gun*Vector2(13,4),gun*Vector2(-1,5)]
	pose.head_tilt=angle*.20
	# Audible kicks touch the upper body only; world-distance gait, gun aim,
	# planted soles, shot timing and treatment gestures retain their own phases.
	var rhythm_frame := Rhythm.frame_for(soldier)
	var rhythm_gain := Rhythm.gain(rhythm_frame)
	if rhythm_gain > 0.0 and soldier.hit_flash <= 0.0 and soldier.muzzle_flash <= 0.0 and not treating:
		var kick_time := float(rhythm_frame.get("last_kick_seconds", -1.0))
		var kick_age := float(rhythm_frame.get("audible_seconds", 0.0)) - kick_time
		var kick := exp(-kick_age / 0.18) * clampf(float(rhythm_frame.get("last_kick_strength", 0.0)), 0.0, 1.0) if kick_time >= 0.0 and kick_age >= 0.0 else 0.0
		var accent := kick * rhythm_gain
		pose.head_tilt -= accent * (0.028 if troop_kind == "heavy_gunner" else 0.040)
		pose.head_shift.y += accent * 0.45
	# Each role has a different service gesture. It stays inside the existing
	# cooldown and never invents a reload delay or consumes gameplay ammunition.
	reload_phase=0.0
	var cooldown: float=soldier.worker_attack_clock if soldier.worker_attack_count>0 and is_instance_valid(soldier.worker_target) else soldier.attack_clock
	var duration: float=float(soldier.profile.cooldown)
	if soldier.worker_attack_count>0 and is_instance_valid(soldier.worker_target): duration=float(soldier.profile.get("worker_interval",SiegeMachine.WORKER_ATTACK_INTERVAL))
	var window:=minf(float(role.reload_time),duration*.72)
	var shots:=maxi(soldier.attack_count,soldier.worker_attack_count)
	var since_shot:=duration-cooldown
	if shots>0 and shots%int(role.magazine)==0 and not soldier.moving and soldier.burst_remaining==0 and soldier.muzzle_flash<=0 and since_shot>.12 and since_shot<window+.12:
		reload_phase=clampf((since_shot-.12)/window,0,1)
		var reach:=sin(reload_phase*PI)
		match troop_kind:
			"marksman": pose.hands[1]=Vector2(pose.hands[1]).lerp(gun*Vector2(3,-5),reach)
			"heavy_gunner": pose.hands[0]=Vector2(pose.hands[0]).lerp(gun*Vector2(7,-8),reach)
			"scout": pose.hands[0]=Vector2(pose.hands[0]).lerp(gun*Vector2(3,12),reach)
			_: pose.hands[0]=Vector2(pose.hands[0]).lerp(Vector2(pose.hip)+Vector2(-7,-1),reach)
	if treating:
		var progress:=clampf(1.0-soldier.abilities.repair_flash,0,1)
		pose.hands[0]=(Vector2(pose.hip)+Vector2(-7,-2)).lerp(Vector2(pose.shoulder)+Vector2(14,7),smoothstep(0,.6,progress))
		var patient: Vector2=soldier.abilities.repair_endpoint-soldier.global_position
		pose.head_tilt=clampf(atan2(patient.y,absf(patient.x))*.18,-.25,.25)
	# The draw routine uses these exact endpoints; keep all reloading/treatment
	# gloves inside the two-segment arm reach used by weather and combat effects.
	for hand in 2:
		var root: Vector2=Vector2(pose.shoulder)+Vector2(-3,1) if hand==0 else Vector2(pose.shoulder)+Vector2(3,2)
		var reach: Vector2=Vector2(pose.hands[hand])-root
		if reach.length()>22.8: pose.hands[hand]=root+reach.normalized()*22.8

## Recoil strength per role: the launcher kicks hard, the belt-fed gun only
## shivers per round, rifles sit in between.
const KICK := {"grenadier":1.0, "marksman":0.75, "rifle_guard":0.55, "scout":0.45, "combat_medic":0.45, "heavy_gunner":0.32}
## How far the muzzle rests below the aim between attacks (radians).
const REST_DROP := {"grenadier":0.42, "heavy_gunner":0.16, "marksman":0.22}
const NO_ROLL := [0.0,0.0]

## Body frames per second of the held performances (fall, wind-up raise) and
## of the hit, whose 0.2 s replicated timer holds one impact pose and three
## recovery frames (style bible 5).
const BODY_FPS := 12.0
const HIT_FPS := 20.0
const HIT_FRAMES := [1.0,0.65,0.35,0.12]

static func held(age: float, fps: float) -> float:
	return floorf(maxf(0.0,age)*fps+0.0001)/fps

## Hit reaction as held frames: the impact pose at once, then recovery.
static func hit_frame(since: float) -> float:
	if since < 0.0: return 0.0
	var frame := floori(since*HIT_FPS+0.0001)
	return float(HIT_FRAMES[frame]) if frame < HIT_FRAMES.size() else 0.0

## Flinch envelope over the 0.2 s hit timer: a two-frame snap, a short hold
## and an eased recovery (the continuous curve the held frames replace).
static func flinch(since: float) -> float:
	if since < 0.0: return 0.0
	if since < 0.035: return smoothstep(0.0,0.035,since)
	if since < 0.09: return 1.0
	return 1.0-smoothstep(0.09,0.2,since)

static func _ease_pulse(value: float, rise: float, fall: float) -> float:
	return smoothstep(0.0,rise,value)*(1.0-smoothstep(rise,fall,value))

## Toe and heel roll of one boot over its gait phase (stride_offset's
## convention): heel strike, flat stance, heel lift, toe-off, swing.
static func foot_roll(phase: float) -> float:
	var theta := fposmod(phase-PI*0.5,TAU)
	if theta<PI:
		if theta<0.45: return -0.24*(1.0-theta/0.45)
		return 0.30*smoothstep(PI-0.75,PI,theta)
	return lerpf(0.30,-0.24,smoothstep(0.08,0.92,(theta-PI)/PI))

## Builds `shown`/`shown_gun` from the combat pose. Every layer is driven by
## replicated state (gait, stride amount, windup clocks, attack counters,
## cooldown clock, hit timer), so hosts and guests see the same performance.
## The drawn gun returns exactly onto the combat gun for the last part of a
## wind-up, so a round always leaves the barrel that is on screen.
func compose(delta: float) -> void:
	shown = pose.duplicate(true)
	shown_gun = gun
	if not is_instance_valid(soldier): return
	var shots: int = int(soldier.attack_count)+int(soldier.worker_attack_count)
	if _seen_shots>=0 and shots>_seen_shots: _shot_age = 0.0
	else: _shot_age += maxf(0.0,delta)
	_seen_shots = shots
	var quiet := WeaponEffectArt.reduced(soldier.game)
	var gain := 0.5 if quiet else 1.0
	var gun_turn := 0.0
	var gun_shift := Vector2.ZERO
	var hips := Vector2.ZERO
	var lean := Vector2.ZERO
	var head := 0.0
	var stride: float = soldier.stride_amount() if soldier.moving or soldier.locomotion_speed>1.0 else 0.0
	stride *= 1.0-float(soldier.stance)
	_pack = Vector2.ZERO
	if stride>0.0:
		# Held walk keys: each heel strike drops the hips (lowest with both
		# boots down, highest as the legs pass), the chest rocks over the
		# stride, the helmet nods a beat later, the carried weapon swings and
		# bobs behind the shoulders and the pack lands after the body.
		var walk := walk_style()
		var keyed := walk_key()
		var phase := walk_phase()
		var angles: Array = [0.0,0.0]
		var travel: float = soldier.stride_per_radian()*float(walk.stride)
		var step_height: float = float(walk.lift)*soldier.stride_amount()
		for index in 2:
			var offset := 0.0 if index==0 else PI
			angles[index] = foot_roll(keyed+offset)*stride
			# The swinging boot is drawn in held walk keys, starting from where
			# the planted sole left the ground; a planted sole stays exact.
			var theta := fposmod(phase+offset-PI*0.5,TAU)
			if theta >= PI:
				var swing_phase := maxf(PI,theta-(phase-keyed))+PI*0.5
				var swing := Vector2((-6.0 if index==0 else 6.0)-SiegeMachine.stride_offset(swing_phase,travel),-4.0-maxf(0,cos(swing_phase))*step_height)
				var rest := Vector2(-float(RoleArt.spec(troop_kind).spread)-3.0,-4.0) if index==0 else Vector2(float(RoleArt.spec(troop_kind).spread),-4.0)
				shown.feet[index] = swing.lerp(rest,float(soldier.stance))
		shown.foot_angles = angles
		hips.y += (float(walk.crouch)+absf(sin(keyed))*float(walk.bob))*stride
		_pack.y += (absf(sin(keyed-0.8))-absf(sin(keyed)))*(1.0+float(walk.bob)*.5)*stride
		lean.x += (float(walk.lean)+sin(keyed)*float(walk.pitch))*stride
		lean.y += absf(sin(keyed-0.8))*1.2*stride
		head += sin(keyed*2.0-0.8)*0.07*stride
		shown.head_shift = Vector2(shown.head_shift)+Vector2(0,absf(sin(keyed-0.8))*1.2*stride)
		gun_turn += sin(keyed*2.0-1.6)*float(walk.sway)*stride
		gun_shift.y += absf(sin(keyed-0.8))*2.6*stride
	var charge := 0.0
	if soldier.windup>0.0: charge = clampf(held(soldier.windup,BODY_FPS)/maxf(0.01,float(soldier.profile.windup)),0,1)
	if soldier.worker_windup>0.0: charge = maxf(charge,clampf(held(soldier.worker_windup,BODY_FPS)/soldier.worker_windup_duration(),0,1))
	# The raise and its overshoot are held frames; the final lock onto the
	# combat gun follows the exact clocks so a round leaves the drawn barrel.
	if charge>=0.7:
		charge = 0.0
		if soldier.windup>0.0: charge = clampf(soldier.windup/maxf(0.01,float(soldier.profile.windup)),0,1)
		if soldier.worker_windup>0.0: charge = maxf(charge,clampf(soldier.worker_windup/soldier.worker_windup_duration(),0,1))
	_charge = charge
	var settled := 1.0-stride
	var raise := smoothstep(0.0,0.30,charge)
	var lock := smoothstep(0.70,0.92,charge)
	# Between attacks the weapon rests low; the wind-up raises it with a small
	# overshoot (anticipation), leans into the stock and braces the knees.
	# The rest blend follows the wind-up exactly and otherwise eases, so a
	# finished reload or dressing lowers the weapon instead of snapping it.
	if charge>0.0: _rest = minf(_rest,1.0-raise)
	else: _rest = move_toward(_rest,0.0 if reload_phase>0.0 or treating or _shot_age<0.35 else 1.0,maxf(0.0,delta)*2.2)
	gun_turn += float(REST_DROP.get(troop_kind,0.12))*_rest*settled
	gun_turn -= 0.10*_ease_pulse(charge,0.30,0.50)
	lean += Vector2(1.5*raise*(1.0-lock*0.4),0.0)
	head += 0.07*raise
	hips.y += 1.5*lock
	lean.y += 1.5*lock
	if troop_kind=="grenadier":
		# A heavy launcher is hefted: the rear boot steps back and the torso
		# rocks back against the weight before settling into the aim.
		shown.feet[0].x -= 2.0*raise*settled
		lean.x -= 3.0*_ease_pulse(charge,0.22,0.55)
	# Standing life between and during actions, in whole drawn texels: the
	# chest rises one texel on each held breath (also behind a raised
	# weapon), the weight shifts between the boots between attacks, and an
	# aimed weapon rides the breath until it locks for the shot.
	var age := float(soldier.age)
	var breath := 1.0 if sin(age*5.0+squad_slot*1.3) > 0.0 else 0.0
	lean.y -= breath*1.3*settled
	var shift := sin(age*0.9+squad_slot*1.7)
	hips.x += (1.3 if shift > 0.45 else (-1.3 if shift < -0.45 else 0.0))*(1.0-raise)*settled
	gun_shift.y -= breath*1.3*raise*(1.0-lock)*settled
	# Recoil: a two-frame kick, then a slower recovery with one rebound. The
	# shoulders and weapon travel at least a texel and the muzzle climbs one
	# drawn key, so even the belt-fed gun's light rounds read shot by shot.
	_recoil_keys = 0
	if _shot_age<0.8:
		var strength: float = float(KICK.get(troop_kind,0.5))*gain
		var envelope := smoothstep(0.0,0.035,_shot_age) if _shot_age<0.035 else exp(-(_shot_age-0.035)*11.0)
		envelope -= sin(maxf(0.0,_shot_age-0.035)*14.0)*exp(-maxf(0.0,_shot_age-0.035)*6.0)*0.18
		var kick := envelope*strength
		gun_turn -= 0.32*kick
		gun_shift.x -= (1.6+2.0*strength)*envelope
		lean.x -= (1.4+3.5*strength)*envelope
		hips.x -= 1.0*kick
		head -= 0.18*kick
		if _shot_age<0.09 and not quiet: _recoil_keys = 1
	# Hit flinch (the replicated hit timer): within two frames the torso is
	# thrown back a key or two, the head snaps back, the muzzle flips up and
	# the rear boot steps back to catch the weight; held for a beat, then the
	# soldier recovers into the stance. Reduced effects halve it.
	if soldier.hit_flash>0.0:
		var knock := hit_frame(0.2-float(soldier.hit_flash))*gain
		hips.x -= 3.0*knock
		hips.y += 1.0*knock
		lean.x -= 5.0*knock
		lean.y += 1.0*knock
		head -= 0.42*knock
		gun_turn -= 0.30*knock
		shown.feet[0].x -= 3.0*knock
		shown.feet[1].x -= 1.0*knock
		shown.head_shift = Vector2(shown.head_shift)+Vector2(-1.0,0.0)*knock
		# The pack keeps going a moment as the body is thrown back.
		_pack.x += 2.0*knock
	if reload_phase>0.0:
		var handling := _ease_pulse(reload_phase,0.18,0.85)
		match troop_kind:
			"grenadier": gun_turn += 0.55*handling
			"rifle_guard", "combat_medic": gun_turn -= 0.22*handling
			"scout": gun_turn += 0.18*handling
			"marksman": gun_turn -= 0.10*handling
			"heavy_gunner": gun_turn -= 0.08*handling
		head += 0.10*handling
	shown.hip = Vector2(shown.hip)+hips
	shown.shoulder = Vector2(shown.shoulder)+hips+lean
	shown.head_tilt = float(shown.head_tilt)+head
	var carry := Vector2(shown.shoulder)-Vector2(pose.shoulder)
	shown_gun = Transform2D(gun.get_rotation()+gun_turn,gun.origin+carry+gun_shift.rotated(gun.get_rotation()))
	if lock>0.0: shown_gun = shown_gun.interpolate_with(gun,lock)
	# Gloves that held the combat gun hold the drawn one; a hand away on a
	# reload or dressing moves with the body.
	var grips: Array[Vector2] = [Vector2(13,4),Vector2(-1,5)]
	for index in 2:
		if Vector2(pose.hands[index]).distance_to(gun*grips[index])<0.05:
			shown.hands[index] = shown_gun*grips[index]
		else:
			shown.hands[index] = Vector2(pose.hands[index])+hips+lean
	if troop_kind=="grenadier" and reload_phase>0.0:
		# Fore hand: off the launcher, into the rear pouch, round to the tipped
		# breech, push it home, back onto the fore-end.
		var grip := shown_gun*grips[0]
		var pouch := Vector2(shown.hip)+Vector2(-8,-1)
		var breech := shown_gun*Vector2(9,-7)
		var r := reload_phase
		var hand := grip
		if r<0.30: hand = grip.lerp(pouch,smoothstep(0.0,0.30,r))
		elif r<0.62: hand = pouch.lerp(breech,smoothstep(0.30,0.62,r))
		elif r<0.80: hand = breech+(shown_gun.basis_xform(Vector2(3,2)))*smoothstep(0.62,0.74,r)
		else: hand = (breech+shown_gun.basis_xform(Vector2(3,2))).lerp(grip,smoothstep(0.80,1.0,r))
		shown.hands[0] = hand
	for index in 2:
		var root: Vector2 = Vector2(shown.shoulder)+(Vector2(-3,1) if index==0 else Vector2(3,2))
		var reach: Vector2 = Vector2(shown.hands[index])-root
		if reach.length()>22.8: shown.hands[index] = root+reach.normalized()*22.8

## The drawn walk cycle: the replicated gait clock, each squad slot offset.
func gait_phase() -> float:
	if not is_instance_valid(soldier): return 0.0
	return float(soldier.gait)+float(squad_slot)*.7

func _drawn() -> Dictionary:
	return shown if not shown.is_empty() else pose

func head_transform() -> Transform2D:
	var drawn := _drawn()
	var body:=WorkerPoseArt.torso_transform(drawn)
	return Transform2D(body.get_rotation()*.55+float(drawn.head_tilt),body*Vector2(1,-14)+Vector2(drawn.head_shift))

## A falling body is drawn in authored key attitudes, 22.5 degrees apart
## (infantry_turns_world.png): torso, pack, head and dropped weapon are
## upright texels on whole world texels instead of rotated quads.
const TURN_STEPS := 16
const TURN_BODY := Vector2i(-4,1)
const TURN_GUN := Vector2i(-2,2)
const TURN_HEADS := 7
const TURN_HEAD_CELL := 40

static func turn_step(angle: float, span: Vector2i) -> int:
	return clampi(roundi(angle/TAU*TURN_STEPS),span.x,span.y)

## A living soldier is drawn in authored attitudes too, 7.5 degrees apart
## (infantry_living_turns_world.png): torso, pack and head are upright texels
## on whole world texels; the upright key is the reduced tile with its cloth
## sway. A remembered step (hysteresis, as WorkerPoseArt.held_step) keeps a
## breathing or marching body from popping across a key boundary.
const LIVING_PER_TURN := 48
const LIVING_STEPS := [-2,-1,1,2,3,4]
const LIVING_HEADS_PER_ROW := 21
const LIVING_HEAD_ROWS := 2
var _torso_step := 0
var _head_step := 0
## The living weapon in authored 7.5 degree keys as well
## (infantry_gun_turns_world.png), held on whole texels; the gloves keep the
## exact grips, which stay within a texel of the drawn key.
const GUN_KEY_STEPS := Vector2i(-10,10)
var _gun_step := 0

static func living_texture() -> Texture2D:
	return Atlas.sheet(Atlas.LIVING_WORLD_PATH)

static func living_step(angle: float, hint: int) -> int:
	var exact := angle/TAU*LIVING_PER_TURN
	var low: int = LIVING_STEPS[0]
	var high: int = LIVING_STEPS[-1]
	if absf(exact-float(hint))<=0.9: return clampi(hint,low,high)
	return clampi(roundi(exact),low,high)

func keyed_gun(tx: Transform2D) -> Transform2D:
	var exact := tx.get_rotation()/TAU*LIVING_PER_TURN
	if absf(exact-float(_gun_step))>0.9 or _gun_step<GUN_KEY_STEPS.x or _gun_step>GUN_KEY_STEPS.y:
		_gun_step = clampi(roundi(exact),GUN_KEY_STEPS.x,GUN_KEY_STEPS.y)
	var step := clampi(_gun_step-_recoil_keys,GUN_KEY_STEPS.x,GUN_KEY_STEPS.y)
	return Transform2D(float(step)*TAU/LIVING_PER_TURN,tx.origin)

## The art frame: one unit is one rig unit times the human factor, its
## origin on a whole world texel, so baked parts land 1:1 on the world grid.
func art_frame() -> Transform2D:
	return WorldTexels.on_grid(self,Transform2D(0.0,Vector2.ONE/Atlas.ART_SCALE,0.0,Vector2.ZERO))

func _living_part(at: Vector2, step: int, part: String, slot: int = 0, sway: float = 0.0) -> void:
	if step==0:
		Atlas.draw_world_part(self,at,part,troop_kind,slot,sway)
		return
	var role := maxi(0,Atlas.ROLES.find(troop_kind))
	var index := LIVING_STEPS.find(step)
	var band := Atlas.LIVING_BODY_CELL+LIVING_HEAD_ROWS*Atlas.LIVING_HEAD_CELL
	var region: Rect2
	if part=="head":
		var cell := float(Atlas.LIVING_HEAD_CELL)
		var at_index := posmod(slot+1,TURN_HEADS)*LIVING_STEPS.size()+index
		region = Rect2(float(at_index%LIVING_HEADS_PER_ROW)*cell,float(role*band+Atlas.LIVING_BODY_CELL)+float(floori(float(at_index)/LIVING_HEADS_PER_ROW))*cell,cell,cell)
	else:
		var column := 0 if part=="torso" else 1
		region = Rect2(float((column*LIVING_STEPS.size()+index)*Atlas.LIVING_BODY_CELL),float(role*band),Atlas.LIVING_BODY_CELL,Atlas.LIVING_BODY_CELL)
	draw_texture_rect_region(living_texture(),Rect2(at-region.size*0.5,region.size),region)

func _living_gun(at: Vector2, step: int) -> void:
	var role := maxi(0,Atlas.ROLES.find(troop_kind))
	var cell := float(Atlas.GUN_CELL)
	var region := Rect2(float(step-GUN_KEY_STEPS.x)*cell,float(role)*cell,cell,cell)
	draw_texture_rect_region(Atlas.sheet(Atlas.GUN_WORLD_PATH),Rect2(at-Vector2.ONE*cell*0.5,region.size),region)

func _turned_part(at: Vector2, step: int, part: String, slot: int = 0) -> void:
	var role := maxi(0,Atlas.ROLES.find(troop_kind))
	var count := TURN_BODY.y-TURN_BODY.x+1
	var region: Rect2
	if part=="gun":
		var gun_count := TURN_GUN.y-TURN_GUN.x+1
		region = Rect2(float(role*gun_count+step-TURN_GUN.x)*Atlas.GUN_CELL,6.0*Atlas.TURN_BODY_CELL,Atlas.GUN_CELL,Atlas.GUN_CELL)
	elif part=="head":
		var column := posmod(slot+1,TURN_HEADS)*count+step-TURN_BODY.x
		region = Rect2(float(2*count*Atlas.TURN_BODY_CELL+column*TURN_HEAD_CELL),float(role*Atlas.TURN_BODY_CELL),TURN_HEAD_CELL,TURN_HEAD_CELL)
	else:
		var column := (0 if part=="torso" else count)+step-TURN_BODY.x
		region = Rect2(float(column*Atlas.TURN_BODY_CELL),float(role*Atlas.TURN_BODY_CELL),Atlas.TURN_BODY_CELL,Atlas.TURN_BODY_CELL)
	draw_texture_rect_region(Atlas.sheet(Atlas.TURNS_WORLD_PATH),Rect2(at-region.size*0.5,region.size),region)

## Leg: thigh from the hip, shin from the boot (a stretched stride shows at
## the knee cap), knee cap, boot in its roll. Points are rig units.
func _leg(art: Transform2D, hip: Vector2, foot: Vector2, front: bool, roll: float) -> void:
	var knee := WorkerPoseArt.joint_position(hip,foot,12,12,-1)
	var h := art*hip
	var k := art*knee
	var f := art*foot
	Atlas.draw_limb(self,"thigh",troop_kind,front,h,k)
	Atlas.draw_limb(self,"shin_long" if hip.distance_to(foot)>24.5 else "shin",troop_kind,front,f,k)
	Atlas.draw_single(self,"knee",troop_kind,front,k)
	Atlas.draw_boot(self,troop_kind,front,f,roll)

func _arm(art: Transform2D, shoulder: Vector2, hand: Vector2, front: bool) -> void:
	if shoulder.distance_to(hand)>22.9: hand = shoulder+(hand-shoulder).normalized()*22.9
	var elbow := WorkerPoseArt.joint_position(shoulder,hand,11,12,1)
	var s := art*shoulder
	var e := art*elbow
	var g := art*hand
	Atlas.draw_limb(self,"upper",troop_kind,front,s,e)
	Atlas.draw_limb(self,"fore",troop_kind,front,g,e)
	Atlas.draw_single(self,"elbow",troop_kind,front,e)
	Atlas.draw_single(self,"glove",troop_kind,front,g)

func _draw() -> void:
	if pose.is_empty(): return
	var drawn: Dictionary = _drawn()
	var drawn_gun: Transform2D = shown_gun if not shown.is_empty() else gun
	var limb_mask:=preload("res://scripts/combat_gore.gd").visible_mask(soldier) if not corpse else 0
	if corpse and is_instance_valid(effects) and effects.level==2:
		limb_mask=gore_mask|effects.mask_for_id(str(get_meta("combat_actor_id","")))
	var frame := art_frame()
	var art := frame.affine_inverse()
	var hip: Vector2=drawn.hip
	var shoulder: Vector2=drawn.shoulder
	var body:=WorkerPoseArt.torso_transform(drawn)
	var head:=head_transform()
	var body_step := 0
	var head_step := 0
	var gun_step := 0
	if corpse:
		# The head follows the falling spine; both land on authored attitudes.
		body_step = turn_step(body.get_rotation(),TURN_BODY)
		var lying := Transform2D(float(body_step)*TAU/TURN_STEPS,body.origin)
		head = Transform2D(body.get_rotation()+float(drawn.head_tilt),lying*Vector2(1,-14)+Vector2(drawn.head_shift))
		head_step = turn_step(head.get_rotation(),TURN_BODY)
		gun_step = turn_step(drawn_gun.get_rotation(),TURN_GUN)
	else:
		# Authored attitudes on whole texels; contacts keep the exact pose.
		_torso_step = living_step(body.get_rotation(),_torso_step)
		_head_step = living_step(head.get_rotation(),_head_step)
		body_step = _torso_step
		head_step = _head_step
		var stepped := Transform2D(float(_torso_step)*TAU/LIVING_PER_TURN,body.origin)
		head = Transform2D(head.get_rotation(),stepped*Vector2(1,-14)+Vector2(drawn.head_shift))
		drawn_gun = keyed_gun(drawn_gun)
		gun_step = roundi(drawn_gun.get_rotation()/TAU*LIVING_PER_TURN)
	var body_at := (art*body.origin).round()
	var head_at := (art*head.origin).round()
	var gun_at := (art*drawn_gun.origin).round()
	var roll: Array=drawn.get("foot_angles",NO_ROLL)
	draw_set_transform_matrix(frame)
	# The dropped weapon lies behind the body, so the legs stay readable over
	# it; lying on the back, the pack is pressed under the body (as the crew's
	# supine coat).
	if corpse:
		_turned_part(gun_at,gun_step,"gun")
		if body_step>TURN_BODY.x+1: _turned_part(body_at,body_step,"rear")
	else: _living_part(body_at+_pack.round(),_torso_step,"rear",0,cloth_sway)
	if corpse:
		# Once down, the legs come out of the coat skirt over it, so a raised
		# knee and the upturned boots break the body's outline.
		var down := body_step<=TURN_BODY.x+1
		if not limb_mask&4 and not down: _leg(art,hip+Vector2(-3,0),drawn.feet[0],false,float(roll[0]))
		if not limb_mask&1: _arm(art,shoulder+Vector2(-3,1),drawn.hands[0],false)
		if not limb_mask&8 and not down: _leg(art,hip+Vector2(2,0),drawn.feet[1],true,float(roll[1]))
		_turned_part(body_at,body_step,"torso")
		if not limb_mask&4 and down: _leg(art,hip+Vector2(-3,0),drawn.feet[0],false,float(roll[0]))
		if not limb_mask&8 and down: _leg(art,hip+Vector2(2,0),drawn.feet[1],true,float(roll[1]))
		_turned_part(head_at,head_step,"head",squad_slot)
	else:
		if not limb_mask&4: _leg(art,hip+Vector2(-3,0),drawn.feet[0],false,float(roll[0]))
		if not limb_mask&1: _arm(art,shoulder+Vector2(-3,1),drawn.hands[0],false)
		if not limb_mask&8: _leg(art,hip+Vector2(2,0),drawn.feet[1],true,float(roll[1]))
		_living_part(body_at,_torso_step,"torso")
		_living_part(head_at,_head_step,"head",squad_slot,cloth_sway)
		_living_gun(gun_at,gun_step)
	var deployed := float(soldier.stance) if not corpse and is_instance_valid(soldier) else 0.0
	RoleArt.gun_details(self,art,drawn_gun,troop_kind,deployed,reload_phase)
	if not limb_mask&2: _arm(art,shoulder+Vector2(3,2),drawn.hands[1],true)
	if not corpse: RoleArt.front_kit(self,art,drawn,body,drawn_gun,troop_kind,treating,reload_phase,limb_mask)
	for wound in [[1,shoulder+Vector2(-3,1)],[2,shoulder+Vector2(3,2)],[4,hip+Vector2(-3,0)],[8,hip+Vector2(2,0)]]:
		if limb_mask&int(wound[0]): Quads.rect(self,Rect2((art*Vector2(wound[1])).round()-Vector2(2,1),Vector2(4,2)),Color("702c29"))
	if not corpse and is_instance_valid(soldier): _draw_aim_glint(art,drawn_gun)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_effects(drawn_gun)

## Launch smoke per role: puffs, life (s), size. The launcher thumps out a
## lingering cloud; rifles leave a short wisp.
const LAUNCH_SMOKE := {"grenadier":Vector3(5,1.0,1.6),"marksman":Vector3(2,.45,.6),"heavy_gunner":Vector3(1,.30,.45)}

## Wind-up telegraph: an ember at the muzzle once the weapon is up, and a
## brighter cross of texels in the last part before the shot, on world texels
## (art frame). It steps, never blinks; the replicated wind-up clocks drive it.
func _draw_aim_glint(art: Transform2D, tx: Transform2D) -> void:
	if _charge < .35: return
	var at: Vector2 = (art*(tx*(Vector2(RoleArt.spec(troop_kind).muzzle)+Vector2(1,0)))).floor()
	if _charge < .75:
		Quads.rect(self,Rect2(at,Vector2(2,2)),Color("d9692c"))
		return
	for arm: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		Quads.rect(self,Rect2(at+arm,Vector2.ONE),Color(1.0,.62,.30,.85))
		Quads.rect(self,Rect2(at+arm*2.0,Vector2.ONE),Color(1.0,.48,.22,.55))
	Quads.rect(self,Rect2(at,Vector2.ONE),Color("fff0c4"))

## Smoke left at the muzzle by the last shot (local age of the replicated shot
## counter), drifting out along the barrel and up, torn on the texel grid.
func _draw_launch_smoke(tx: Transform2D) -> void:
	var spec: Vector3 = LAUNCH_SMOKE.get(troop_kind,Vector3(1,.25,.35))
	if _shot_age >= spec.y or not PixelArt.supports_grid(self): return
	var count := int(spec.x) if not WeaponEffectArt.reduced(soldier.game) else 1
	var mouth: Vector2 = tx*Vector2(RoleArt.spec(troop_kind).muzzle)
	var forward := tx.basis_xform(Vector2.RIGHT).normalized()
	var life := _shot_age/spec.y
	for index in count:
		var lag := float(index)/float(maxi(1,count))
		var age := clampf(life*(1.0+lag*.6),0.0,1.0)
		var at := mouth+forward*(2.0+age*(5.0+6.0*lag)*spec.z*2.0)+Vector2(sin(float(index)*2.1)*age*3.0,-age*(6.0+4.0*lag))
		PixelArt.grid_smoke(self,at,(2.0+age*5.0*spec.z)*(1.0-lag*.25),Color(PixelArt.smoke_tone(Color(.66,.64,.60)),.9),index+int(soldier.attack_count)*3,smoothstep(.35,1.0,age)*.9,clampf(1.0-age*5.0,0.0,1.0)*.6)

## Effects in rig space (shared effect grid, layered flash), after the art.
func _draw_effects(tx: Transform2D) -> void:
	if corpse or not is_instance_valid(soldier): return
	_draw_launch_smoke(tx)
	if soldier.muzzle_flash<=0: return
	# The shared layered flash replaces the role kit's flat single polygon;
	# the launcher's thump is the biggest of the field kits.
	draw_set_transform_matrix(tx)
	WeaponEffectArt.muzzle(self,RoleArt.spec(troop_kind).muzzle,soldier.muzzle_flash,0.09 if troop_kind!="grenadier" else 0.13,1,1.1 if troop_kind=="grenadier" else (0.8 if troop_kind in ["heavy_gunner","marksman"] else 0.6),soldier.attack_count,WeaponEffectArt.reduced(soldier.game),false,tx)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# The round itself: one self-lit hostile streak per replicated shot.
	if int(get_meta(&"traced_shot",-1)) != int(soldier.attack_count) and soldier.tracer_end != Vector2.ZERO:
		set_meta(&"traced_shot",int(soldier.attack_count))
		var feel: Node2D = preload("res://scripts/combat_feel.gd").of(self)
		if feel != null: feel.trace(get_global_transform()*(tx*Vector2(RoleArt.spec(troop_kind).muzzle)),soldier.to_global(soldier.tracer_end),1.0)
