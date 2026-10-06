extends RefCounted
## Distinct, authored joint paths for the character repertoires. Beats are
## audible sample-derived musical beats, never a separate animation timer.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const IDS := [
	"crew_bounce","crew_two_step","crew_clap",
	"mara_precision_step","mara_cross_turn","mara_box_glide","mara_lockstep","mara_pivot_finish",
	"branko_foundry_stomp","branko_hammer_pop","branko_shoulder_hit","branko_low_bounce","branko_power_freeze",
	"ivo_heel_switch","ivo_backslide","ivo_toe_weave","ivo_tick_tock","ivo_knee_wave",
	"nora_flow_step","nora_ribbon_arms","nora_sway_turn","nora_cross_wave","nora_spiral_roll",
	"levin_toprock","levin_six_step","levin_sweep","levin_cc_kick","levin_air_freeze",
	"selma_skip_step","selma_v_step","selma_double_shuffle","selma_running_switch","selma_kick_turn",
	"oskar_quarry_stride","oskar_brace_step","oskar_heel_press","oskar_pack_pop","oskar_tunnel_turn",
	"rika_signal_step","rika_cable_wave","rika_switch_glide","rika_contact_shuffle","rika_coil_finish",
]
const SHARED_STYLES := ["crew_bounce","crew_two_step","crew_clap"]
static var _owned_styles: Dictionary = {}

static func owns(style: String) -> bool:
	if _owned_styles.is_empty():
		for id: String in IDS: _owned_styles[id] = true
	return _owned_styles.has(style)

static func _snap(beats: float) -> float:
	return beats+sin(fposmod(beats*2.0,1.0)*TAU)*(0.125/TAU)

static func _kick(beats: float) -> float:
	return pow((1.0+cos(beats*TAU))*.5,2.0)

static func _body(pose: Dictionary,hip: Vector2,lean: float) -> void:
	pose.hip = hip
	pose.shoulder = hip+Vector2(sin(lean),-cos(lean))*17.0
	pose.head_tilt = -lean*.62
	pose.head_shift = Vector2.ZERO

static func _arm(pose: Dictionary,index: int,upper: float,forearm: float) -> void:
	var body := PoseArt.torso_transform(pose)
	var local_root := PoseArt.shoulder_local(pose,index)
	var root := body*local_root
	if not pose.has("elbows"): pose.elbows = [Vector2.ZERO,Vector2.ZERO]
	pose.elbows[index] = root+Vector2(cos(upper),sin(upper))*11.0
	pose.hands[index] = pose.elbows[index]+Vector2(cos(forearm),sin(forearm))*11.7

static func _hands(pose: Dictionary,left: Vector2,right: Vector2,side_carriage: bool=true) -> void:
	var body := PoseArt.torso_transform(pose)
	# These standing wrist paths were authored as a frontal pair. In the
	# side-view rig the visible arm needs room in front of the chest to bend.
	pose.hands = [body*left,body*(right+Vector2(8,0) if side_carriage else right)]

static func _steps(pose: Dictionary,phase: float,width: float,travel: float,lift: float,amplitude: float) -> void:
	for index in 2:
		var step := phase+float(index)*PI
		# Smooth takeoff and contact retain the precise musical anchor without
		# snapping vertical boot velocity at the lifted/support phase change.
		var swing := maxf(0.0,sin(step))
		pose.feet[index] = Vector2((-width if index==0 else width)+sin(step)*travel*amplitude,-3.0-swing*swing*lift*amplitude)
		pose.foot_angles[index] = sin(step)*.18

static func _mix(first: Dictionary,second: Dictionary,amount: float) -> Dictionary:
	var result := first.duplicate(true)
	var t := smoothstep(0,1,amount)
	for key: String in ["hip","shoulder","head_shift"]: result[key] = Vector2(first[key]).lerp(second[key],t)
	for key: String in ["hands","feet"]:
		for index in 2: result[key][index] = Vector2(first[key][index]).lerp(second[key][index],t)
	result.head_tilt = lerpf(float(first.head_tilt),float(second.head_tilt),t)
	result.foot_angles = [lerpf(float(first.foot_angles[0]),float(second.foot_angles[0]),t),lerpf(float(first.foot_angles[1]),float(second.foot_angles[1]),t)]
	if first.has("elbows") or second.has("elbows"):
		result.elbows = PoseArt.blend_arm_elbows(first,second,t)
	return result

static func _shared_character(pose: Dictionary,style: String,beats: float,character_id: String) -> void:
	character_id = CharacterCatalog.presentation_id(character_id,"dance")
	# The crew dances share their steps and musical anchors. A character keeps
	# their own relaxed arm carriage and shoulder phrasing even at level one.
	# Neither a new animation timer nor a phase offset may move a boot contact.
	var t := _snap(beats)
	var swing := sin(t*PI)
	var offbeat := sin(t*TAU)
	var pulse := _kick(beats)
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	var lean := 0.0
	match character_id:
		"mara":
			# Controlled, compact counter-swing from the shift leader.
			left = Vector2(-.5+offbeat*.6,-1-swing*.7)
			right = Vector2(-.5-offbeat*.6,1+swing*.7)
			lean = swing*.025
		"branko":
			# Heavy elbows and low fists, with a pronounced shoulder hit.
			left = Vector2(-3,5-pulse*1.8)
			right = Vector2(2,4-pulse*1.8)
			lean = swing*.09
		"ivo":
			# Close, high hands and a quick double-time wrist response.
			left = Vector2(3, -6+sin(t*TAU*2.0)*1.4)
			right = Vector2(0, -4-sin(t*TAU*2.0)*1.4)
			lean = -.055+offbeat*.025
		"nora":
			# A broad, relaxed arm sweep follows the shoulders in a soft wave.
			left = Vector2(-4-sin(t*PI-.5)*1.6,0)
			right = Vector2(4+sin(t*PI-.5)*1.6,1)
			lean = sin(t*PI-.45)*.06
		"levin":
			# Open elbows and alternating high accents echo his toprock.
			left = Vector2(-5,-4-swing*2.2)
			right = Vector2(5,-7+swing*2.2)
			lean = swing*.11
		"selma":
			# One arm drives each light step while the other stays relaxed.
			left = Vector2(1+swing*1.7,-6-offbeat*1.8)
			right = Vector2(2-swing*1.7,3+offbeat*1.8)
			lean = .055+swing*.04
		"oskar":
			# Braced shoulders and compact hands keep the miner's solid stance.
			left = Vector2(4,-.5-pulse*.7)
			right = Vector2(-3,-1.5-pulse*.7)
			lean = -.10+swing*.025
		"rika":
			# Her free signal hand stays higher; the other draws a cable wave.
			left = Vector2(-1, -1+sin(t*TAU-.5)*1.6)
			right = Vector2(-4, -11-offbeat*1.8)
			lean = .07+offbeat*.04
	var body := PoseArt.torso_transform(pose)
	var inverse := body.affine_inverse()
	var left_hand: Vector2 = inverse*Vector2(pose.hands[0])
	var right_hand: Vector2 = inverse*Vector2(pose.hands[1])
	_body(pose,pose.hip,body.get_rotation()+lean)
	# All eight hands still meet on the shared clap's real kick. The distinct
	# arm carriage reappears between claps rather than separating the palms.
	var freedom := 1.0-pulse if style=="crew_clap" else 1.0
	_hands(pose,left_hand+left*freedom,right_hand+right*freedom,false)

static func choreography(style: String,beats: float,character_id: String="mara",intensity: float=1.0) -> Dictionary:
	var pose := PoseArt.neutral()
	pose.foot_angles = [0.0,0.0]
	pose.continuous = true
	pose.dance_stage = "standing"
	var a := clampf(intensity,.4,1.5)
	var t := _snap(beats)
	var s := sin(t*PI)
	var c := cos(t*PI)
	var p := _kick(beats)
	var e := sin(t*TAU)
	var eighth := sin(t*TAU*2.0)
	match style:
		"crew_bounce":
			_body(pose,Vector2(s*1.4,-22+p*2.0),s*.07)
			_steps(pose,t*PI,6,4.8,3.0,a)
			_hands(pose,Vector2(-11+e*1.5,9-p*3),Vector2(11-e*1.5,9-p*3))
		"crew_two_step":
			var side := sin(t*PI*.5)
			_body(pose,Vector2(side*4*a,-22+p),side*.12)
			_steps(pose,t*PI,7,6,4.0,a)
			pose.feet[0].x += side*3
			pose.feet[1].x += side*3
			_hands(pose,Vector2(-10+side*3,12+c*2),Vector2(11+side*3,12-c*2))
		"crew_clap":
			_body(pose,Vector2(s*1.8,-22+p*1.2),s*.05)
			_steps(pose,t*PI,7,4.5,3.2,a)
			_hands(pose,Vector2(lerpf(-13,14,p),9),Vector2(lerpf(22,14,p),9),false)
		"mara_precision_step":
			# A small cross-back step alternates with a straight toe placement.
			_body(pose,Vector2(s*2.5,-23+p*1.3),s*.08)
			_steps(pose,t*PI,6,7.8,4.8,a)
			pose.feet[0].x += maxf(0,c)*2
			pose.feet[1].x -= maxf(0,-c)*2
			_hands(pose,Vector2(-9+e*3,10-c*2),Vector2(10-e*2,11+c*3))
		"mara_cross_turn":
			var turn := sin(t*PI*.5)
			_body(pose,Vector2(turn*2.8,-22+p*1.4),turn*.19)
			_steps(pose,t*PI,4.5,9,4.2,a)
			pose.foot_angles = [s*.28,-s*.28]
			_arm(pose,0,PI*.9+turn*.3,PI*.7-turn*.5)
			_arm(pose,1,.12-turn*.3,.55+turn*.5)
		"mara_box_glide":
			var box := sin(t*PI*.5)
			_body(pose,Vector2(box*3.2,-24+p*.8),-.10)
			pose.feet = [Vector2(-7+box*4+cos(t*PI)*6*a,-3),Vector2(7+box*4-cos(t*PI)*6*a,-3)]
			pose.foot_angles = [-maxf(0,s)*.24,-maxf(0,-s)*.24]
			_hands(pose,Vector2(-10+e*2,12),Vector2(11-e*2,9))
		"mara_lockstep":
			_body(pose,Vector2(e*1.6,-22+p*1.8),e*.10)
			_steps(pose,t*TAU,6,7.4,4.1,a)
			pose.foot_angles = [eighth*.16,-eighth*.16]
			_arm(pose,0,.85+e*.22,-.85-e*.25)
			_arm(pose,1,PI-(2.2-e*.22),PI-(-2.15+e*.25))
		"mara_pivot_finish":
			var turn := sin(t*PI*.25)
			var pivot := sin(t*PI*.5)
			_body(pose,Vector2(pivot*3,-23+p),pivot*.24)
			_steps(pose,t*PI,7,7.4,4.2,a)
			pose.foot_angles = [pivot*.31,-pivot*.26]
			_arm(pose,0,2.5+turn*.5,2.0-turn*.9)
			_arm(pose,1,.7-turn*.5,1.15+turn*.9)
		"branko_foundry_stomp":
			# A stationary drill step. The raised leg stays almost straight while
			# the other boot bears weight; each heard kick plants the marching boot.
			_body(pose,Vector2(0,-26.65+p*.35),0.0)
			pose.hip_spread = 4.0
			for index in 2:
				var phase := fposmod(t+float(index),2.0)
				var lift := pow(sin(phase*PI),2.0) if phase<1.0 else 0.0
				var angle := lift*1.10*minf(a,1.15)
				var attachment: Vector2 = pose.hip+Vector2(-4 if index==0 else 4,0)
				pose.feet[index] = attachment+Vector2(sin(angle),cos(angle))*23.65
				if lift<.00001: pose.feet[index].y = -3.0
				pose.foot_angles[index] = -angle*.10
			_hands(pose,Vector2(-10-e*2,13-p*2),Vector2(10+e*2,12-p*2))
			pose.head_shift.y = p*.65
			pose.dance_stage = "drill_step"
		"branko_hammer_pop":
			_body(pose,Vector2(e*1.3,-21+p*1.5),.16+p*.12)
			pose.feet = [Vector2(-9-eighth*6.2,-3),Vector2(9+eighth*6.2,-3)]
			pose.foot_angles = [p*.18,-p*.18]
			_hands(pose,Vector2(-10,6+p*11),Vector2(12,7+p*9))
			pose.head_tilt += p*.09
		"branko_shoulder_hit":
			_body(pose,Vector2(s*3,-22+p*1.0),s*.26)
			_steps(pose,t*PI,8,7.3,3.8,a)
			_arm(pose,0,1.0+s*.30,-.6-s*.8)
			_arm(pose,1,PI-(2.2+s*.35),PI-(-2.5+s*.8))
			pose.head_shift.x = -s*.6
		"branko_low_bounce":
			_body(pose,Vector2(e*1.0,-18+p*2.8),e*.06)
			pose.feet = [Vector2(-10-e*6.2*a,-3),Vector2(10+e*6.2*a,-3)]
			pose.foot_angles = [e*.20,-e*.20]
			_hands(pose,Vector2(-12+p*4,13-p*7),Vector2(13-p*4,13-p*7))
		"branko_power_freeze":
			var q := fposmod(beats,8.0)
			var hold := smoothstep(2.0,3.0,q)*(1.0-smoothstep(6.0,8.0,q))
			_body(pose,Vector2(hold*3+s*(1-hold)*2,-22+p*(1-hold)),hold*.28)
			_steps(pose,t*PI,9,7.5*(1-hold),4*(1-hold),a)
			_arm(pose,0,lerpf(1.0,.5,hold),lerpf(-.8,-1.25,hold))
			_arm(pose,1,PI-lerpf(2.0,2.8,hold),PI-lerpf(-2.2,3.4,hold))
			pose.dance_stage = "power_lock" if hold>.99 else "standing"
		"ivo_heel_switch":
			_body(pose,Vector2(e*2,-24+p*.7),-.07+e*.05)
			pose.feet = [Vector2(-7+e*6.4*a,-3),Vector2(7-e*6.4*a,-3)]
			pose.foot_angles = [-maxf(0,e)*.34,-maxf(0,-e)*.34]
			_arm(pose,0,.8+eighth*.12,-.3+eighth*.5)
			_arm(pose,1,PI-(2.1-eighth*.12),PI-(2.8-eighth*.5))
		"ivo_backslide":
			var drift := -sin(t*PI*.5)*5*a
			_body(pose,Vector2(drift,-23+p*.7),-.14)
			pose.feet = [Vector2(drift-6+c*6*a,-3),Vector2(drift+6-c*6*a,-3)]
			pose.foot_angles = [-maxf(0,s)*.29,-maxf(0,-s)*.29]
			_hands(pose,Vector2(-10-s*5,8+s*2),Vector2(11+s*5,11-s*2))
		"ivo_toe_weave":
			_body(pose,Vector2(s*1.4,-23+p),s*.15)
			_steps(pose,t*PI,4.3,8.5,3.5,a)
			pose.feet[0].x += sin(t*TAU)*2.2
			pose.feet[1].x -= sin(t*TAU)*2.2
			pose.foot_angles = [c*.25,-c*.25]
			_hands(pose,Vector2(-12+eighth*3,10+e*2),Vector2(12-eighth*3,10-e*2))
		"ivo_tick_tock":
			var fraction := fposmod(beats,1.0)
			var quadrant := floori(fposmod(beats,4))
			var values := [0.0,1.0,0.0,-1.0]
			var lock := lerpf(values[(quadrant+3)%4],values[quadrant],smoothstep(.04,.20,fraction))
			_body(pose,Vector2(lock*2.8,-22+p*.7),lock*.19)
			pose.feet = [Vector2(-7+lock*8,-3),Vector2(7-lock*4,-3)]
			pose.foot_angles = [lock*.2,-lock*.2]
			_arm(pose,0,PI*.83+lock*.35,-PI*.3-lock*.7)
			_arm(pose,1,PI*.14+lock*.35,PI*.9-lock*.7)
			pose.head_tilt = lock*.18
		"ivo_knee_wave":
			_body(pose,Vector2(s*1.7,-23+p*1.3),s*.10)
			_steps(pose,t*PI,5.5,7.0,8.0,a)
			_arm(pose,0,1.4+sin(t*PI-.5)*.4,-.4+sin(t*PI)*.65)
			_arm(pose,1,PI-(1.8-sin(t*PI-1)*.4),PI-(3.5-sin(t*PI-.5)*.65))
			pose.head_shift.y = -e*.35
		"nora_flow_step":
			var flow := t*PI*.5
			_body(pose,Vector2(sin(flow)*3.1,-22+p*.65),sin(flow)*.11)
			_steps(pose,t*PI,6,6.8,3.7,a)
			_arm(pose,0,2.8+sin(flow)*.38,2.0+sin(flow-.8)*.65)
			_arm(pose,1,.4-sin(flow)*.38,1.1-sin(flow-.8)*.65)
		"nora_ribbon_arms":
			var ribbon := t*PI
			_body(pose,Vector2(sin(ribbon-.7)*2.4,-22+p*.7),sin(ribbon-.5)*.12)
			pose.feet = [Vector2(-9+sin(ribbon)*6.8*a,-3),Vector2(9-sin(ribbon)*6.8*a,-3)]
			pose.foot_angles = [sin(ribbon)*.19,-sin(ribbon)*.19]
			_arm(pose,0,PI+sin(ribbon-.4)*.52,PI+sin(ribbon)*.72)
			_arm(pose,1,sin(ribbon-1.3)*.52,sin(ribbon-1.8)*.72)
		"nora_sway_turn":
			var turn := sin(t*PI*.25)
			_body(pose,Vector2(sin(t*PI*.5)*3.3,-23+p),sin(t*PI*.5)*.18)
			_steps(pose,t*PI,5,8.2,4.6,a)
			_arm(pose,0,2.8+turn*.5,1.7-turn*.6)
			_arm(pose,1,.35-turn*.5,1.45+turn*.6)
		"nora_cross_wave":
			_body(pose,Vector2(s*2.2,-22+p),sin(t*PI-.5)*.17)
			_steps(pose,t*PI,4.8,9.0,4.0,a)
			_arm(pose,0,2.4+sin(t*PI)*.5,1.3+sin(t*PI-.7)*.8)
			_arm(pose,1,.55+sin(t*PI-PI)*.5,1.9+sin(t*PI-.7-PI)*.8)
			pose.head_tilt += sin(t*PI-1.1)*.1
		"nora_spiral_roll":
			var roll := t*PI
			_body(pose,Vector2(sin(roll)*3.0,-22+cos(roll)*1.2),sin(roll-.7)*.22)
			_steps(pose,roll,8,7.4,4.4,a)
			_arm(pose,0,2.6+sin(roll-1)*.38,2.0+cos(roll-1.4)*.66)
			_arm(pose,1,.5+sin(roll-.6)*.38,1.2+cos(roll-1.0)*.66)
			pose.head_shift = Vector2(sin(roll-1.5)*.4,cos(roll-1.5)*.3)
		"levin_toprock":
			_body(pose,Vector2(s*3.1,-21+p*1.6),s*.21)
			_steps(pose,t*PI,6.5,9.5,5.8,a)
			pose.feet[0].x += e*1.4
			pose.feet[1].x -= e*1.4
			_arm(pose,0,2.1+s*.55,2.0-s*.65)
			_arm(pose,1,.9+s*.55,1.1-s*.65)
		"levin_six_step":
			_body(pose,Vector2(-4+sin(t*PI)*2,-14+cos(t*PI)),.91+sin(t*PI)*.13)
			pose.hands = [Vector2(11,-3),Vector2(21,-3)]
			for index in 2:
				var circle := t*PI+float(index)*PI
				pose.feet[index] = Vector2(-8+cos(circle)*13*a,-3-maxf(0,sin(circle))*9*a)
				pose.foot_angles[index] = sin(circle)*.3
			pose.dance_stage = "floorwork"
		"levin_sweep":
			_body(pose,Vector2(-5+e*1.2,-15+e*.7),1.03+e*.10)
			pose.hands = [Vector2(12,-3),Vector2(22,-3)]
			pose.feet = [Vector2(-10,-3),Vector2(-5+e*16*a,-3-maxf(0,s)*7*a)]
			pose.foot_angles = [.12,e*.38]
			pose.dance_stage = "floorwork"
		"levin_cc_kick":
			_body(pose,Vector2(-3+s*2.2,-15+p*1.2),.63+s*.19)
			pose.hands = [Vector2(9+maxf(0,s)*5,-3),Vector2(20,-3)]
			for index in 2:
				var kick := sin(t*PI+float(index)*PI)
				pose.feet[index] = Vector2((-7 if index==0 else 5)+maxf(0,kick)*12*a,-3-maxf(0,kick)*9*a)
				pose.foot_angles[index] = maxf(0,kick)*.34
			pose.dance_stage = "floorwork"
		"levin_air_freeze":
			pose = _air_freeze(beats,a)
		"selma_skip_step":
			_body(pose,Vector2(s*1.8,-23+p*1.6),.10+s*.07)
			_steps(pose,t*PI,5.8,7.2,8.0,a)
			_hands(pose,Vector2(-9+s*5,7-e*3),Vector2(10-s*5,9+e*3))
			pose.head_shift.y = -maxf(0,e)*.4
		"selma_v_step":
			var open := (1.0-cos(t*PI))*.5
			_body(pose,Vector2(s*2,-22+p*1.4),s*.06)
			for index in 2:
				var side := -1.0 if index==0 else 1.0
				var step := sin(t*PI+float(index)*PI)
				pose.feet[index] = Vector2(side*(5+open*11*a),-3-maxf(0,step)*5*a)
				pose.foot_angles[index] = side*open*.28
			_hands(pose,Vector2(-9-open*5,10-p*2),Vector2(10+open*5,10-p*2))
		"selma_double_shuffle":
			_body(pose,Vector2(e*2.1,-22+p*1.1),e*.12)
			_steps(pose,t*TAU,7.2,7.4,5.0,a)
			pose.foot_angles = [eighth*.23,-eighth*.23]
			_hands(pose,Vector2(-11+e*4,8+eighth*1.8),Vector2(12-e*4,9-eighth*1.8))
		"selma_running_switch":
			_body(pose,Vector2(s*2,-22+p*2),.16)
			for index in 2:
				var leg := sin(t*PI+float(index)*PI)
				pose.feet[index] = Vector2((-4.8 if index==0 else 4.8)+leg*9*a,-3-maxf(0,leg)*10*a)
				pose.foot_angles[index] = maxf(0,leg)*.28
			_arm(pose,0,1.2+s*.35,-.8-s*.5)
			_arm(pose,1,PI-(2.0+s*.35),PI-(-2.3-s*.5))
		"selma_kick_turn":
			var turn := sin(t*PI*.25)
			_body(pose,Vector2(s*2.8,-21+p*1.1),-s*.14)
			for index in 2:
				var leg := sin(t*PI+float(index)*PI)
				pose.feet[index] = Vector2((-7 if index==0 else 7)+maxf(0,leg)*14*a,-3-maxf(0,leg)*6.5*a)
				pose.foot_angles[index] = leg*.3
			_arm(pose,0,1.05+turn*.35,-1.0-turn*.55)
			_arm(pose,1,PI-(2.0-turn*.35),PI-(-2.2+turn*.55))
		"oskar_quarry_stride":
			_body(pose,Vector2(s*1.2,-22+p*1.9),-.10+s*.04)
			_steps(pose,t*PI,9.5,6.2,8.3,a)
			_hands(pose,Vector2(-13+c*2,14-e*2),Vector2(11-c*2,12+e*2))
			pose.head_shift.y=p*.8
		"oskar_brace_step":
			var weight := sin(t*PI*.5)
			_body(pose,Vector2(weight*3.5,-23+p*.9),-.12+weight*.14)
			_steps(pose,t*PI,8,7.3,4.3,a)
			pose.feet[0].x+=weight*4
			pose.feet[1].x+=weight*2
			_arm(pose,0,2.5+weight*.2,1.5-weight*.3)
			_arm(pose,1,.8-weight*.3,.35+weight*.4)
		"oskar_heel_press":
			# Knee compression leaves room for a readable alternating heel glide.
			# The opposite flat boot keeps contact at every musical anchor.
			_body(pose,Vector2(e*2.1,-23+p*1.3),-.04+e*.08)
			pose.feet=[Vector2(-9+e*7.2*a,-3),Vector2(9-e*7.2*a,-3)]
			pose.foot_angles=[maxf(0,e)*.30,maxf(0,-e)*.30]
			_hands(pose,Vector2(-12-e*2,13),Vector2(12+e*2,14-p*2))
		"oskar_pack_pop":
			_body(pose,Vector2(eighth*1.4,-23+p*1.1),eighth*.13)
			_steps(pose,t*TAU,8.5,6.6,4.6,a)
			pose.foot_angles=[eighth*.22,-eighth*.19]
			_hands(pose,Vector2(-8,3+p*3),Vector2(7,4-p*3))
			pose.head_tilt-=eighth*.10
		"oskar_tunnel_turn":
			var pivot := sin(t*PI*.25)
			_body(pose,Vector2(s*2.1,-22+p*1.2),pivot*.18)
			_steps(pose,t*PI,8.5,6.5,5.5,a)
			pose.foot_angles=[pivot*.29,pivot*.24]
			_arm(pose,0,1.8+pivot*.6,1.1-pivot*.4)
			_arm(pose,1,.8+pivot*.3,1.8-pivot*.6)
		"rika_signal_step":
			_body(pose,Vector2(s*2.0,-24+p*.9),.07+s*.10)
			_steps(pose,t*PI,5.5,8.1,6.2,a)
			pose.foot_angles=[e*.22,-e*.18]
			_arm(pose,0,2.2+s*.4,-2.0-s*.55)
			_arm(pose,1,-.7+e*.20,-1.2-e*.15)
			pose.head_shift.x=-e*.5
		"rika_cable_wave":
			var ribbon := sin(t*PI*.5)
			_body(pose,Vector2(ribbon*3,-23+p*.8),ribbon*.16)
			_steps(pose,t*PI,6.2,5.8,4.1,a)
			_arm(pose,0,2.8+e*.35,1.0+sin(t*TAU-.8)*.8)
			_arm(pose,1,.25+e*.35,2.1+sin(t*TAU+.8)*.8)
		"rika_switch_glide":
			var glide := sin(t*PI*.5)*3.5*a
			_body(pose,Vector2(glide,-24+p*.6),s*.09)
			pose.feet=[Vector2(-6+glide+c*7*a,-3),Vector2(6+glide-c*7*a,-3)]
			pose.foot_angles=[maxf(0,s)*.26,maxf(0,-s)*.26]
			_hands(pose,Vector2(-10+e*5,8-e*2),Vector2(11-e*5,12+e*2))
		"rika_contact_shuffle":
			_body(pose,Vector2(e*2.8,-23+p*1.4),-.08+e*.10)
			_steps(pose,t*TAU,5.5,8.7,5.8,a)
			pose.foot_angles=[eighth*.27,-eighth*.27]
			_arm(pose,0,1.3+e*.35,-.7-e*.5)
			_arm(pose,1,PI-(2.1+e*.35),PI-(-2.1+e*.5))
		"rika_coil_finish":
			var phrase := fposmod(beats,8.0)
			var coil := sin(t*PI*.25)
			var finish := smoothstep(5.5,6.0,phrase)*(1.0-smoothstep(7.25,8.0,phrase))
			_body(pose,Vector2(coil*2.8,-23+p*(1-finish)),coil*.18)
			_steps(pose,t*PI,6.5,7.0*(1-finish),4.3*(1-finish),a)
			pose.foot_angles=[coil*.18,-coil*.18]
			_arm(pose,0,2.3+coil*.45,1.1+finish*.7)
			_arm(pose,1,.9-coil*.4,2.0-finish*.8)
			pose.dance_stage="signal_lock" if finish>.99 else "standing"
	if style in SHARED_STYLES:
		_shared_character(pose,style,beats,character_id)
	pose.head_tilt += (_kick(beats)-.5)*.026
	pose.dance_style = style
	return pose

static func _air_freeze(beats: float,amplitude: float) -> Dictionary:
	var q := fposmod(beats,8.0)
	var standing := choreography("levin_toprock",beats,"levin",amplitude)
	var held := PoseArt.neutral()
	_body(held,Vector2(-6,-15),1.35)
	held.foot_angles = [.1,-.38]
	held.feet = [Vector2(-23,-3),Vector2(-7,-34)]
	held.hands = [Vector2(8,-24),Vector2(17,-3)]
	held.head_tilt = -.38
	if q<2:
		standing.dance_stage = "toprock"
		return standing
	if q<3:
		var entry := _mix(choreography("levin_toprock",2.0,"levin",amplitude),held,q-2.0)
		entry.dance_stage = "drop"
		return entry
	if q<5:
		held.dance_stage = "freeze"
		return held
	if q<7:
		var exit := _mix(held,choreography("levin_toprock",7.0,"levin",amplitude),(q-5)/2.0)
		exit.dance_stage = "rise"
		return exit
	standing.dance_stage = "toprock"
	return standing
