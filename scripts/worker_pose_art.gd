class_name WorkerPoseArt
extends RefCounted

const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Additional := preload("res://scripts/worker_gesture_library.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Quads := preload("res://scripts/canvas_quads.gd")
## Articulated idle and medical poses share each character's actual outfit,
## face and palette. Clean torso/head pieces contain no baked arms or legs.

const C := {"ink":Color("151b1e"),"deep":Color("25302c"),"shadow":Color("354231"),"olive":Color("566044"),"cloth":Color("727a50"),"light":Color("929b67"),"edge":Color("b2b989"),"trouser":Color("44543c"),"trouser_light":Color("65744e"),"skin_shadow":Color("83583d"),"skin":Color("b88957"),"skin_light":Color("dfba7c"),"leather":Color("674a31"),"leather_light":Color("987047"),"strap":Color("43382c"),"boot":Color("352e27"),"boot_light":Color("5b5141"),"sole":Color("141b1c"),"steel":Color("89998e"),"steel_light":Color("c1cbbb"),"red":Color("9a4535")}
static var colors: Dictionary = C.duplicate()
static var _continuous := false

static func neutral() -> Dictionary:
	return {"hip":Vector2(0,-25),"shoulder":Vector2(0,-42),"feet":[Vector2(-6,-3),Vector2(5,-3)],"hands":[Vector2(-9,-26),Vector2(9,-25)],"head_shift":Vector2.ZERO,"head_tilt":0.0,"blink":false,"mouth":false,"watch":false,"bandage":false,"splint":false,"splint_tool":false,"aid":false,"prop":""}

static func _blend(a: Dictionary,b: Dictionary,weight: float) -> Dictionary:
	var result := a.duplicate(true)
	var t := smoothstep(0.0,1.0,clampf(weight,0,1))
	for key in ["hip","shoulder","head_shift"]:
		result[key] = Vector2(a[key]).lerp(Vector2(b[key]),t)
	for key in ["feet","hands"]:
		for index in 2:
			result[key][index] = Vector2(a[key][index]).lerp(Vector2(b[key][index]),t)
	result.head_tilt = lerpf(float(a.head_tilt),float(b.head_tilt),t)
	return result

static func sample(kind: String,phase: float,gait: float=0.0,reach: Vector2=Vector2(24,-13),character_id: String="") -> Dictionary:
	var base := neutral()
	if Personality.has_animation(kind):
		base = Personality.stance(base,character_id)
	var pose := base.duplicate(true)
	var envelope := smoothstep(0.0,0.24,phase)*(1.0-smoothstep(0.78,1.0,phase))
	match kind:
		"radio_check":
			pose.shoulder = Vector2(0,-43)
			pose.hands = [Vector2(-8,-36),Vector2(10,-53)]
			pose.head_shift = Vector2(2,1+sin(phase*TAU*3)*0.6)
			pose.head_tilt = 0.06
			pose = _blend(base,pose,envelope)
			pose.prop = "radio" if envelope>0.2 else ""
			pose.mouth = envelope>0.8 and sin(phase*TAU*7)>0.4
		"strap_check":
			var tug := maxf(0.0,sin(phase*TAU*3))*2.0
			pose.shoulder = Vector2(-1,-43+tug*0.35)
			pose.hands = [Vector2(-9,-40+tug),Vector2(3,-31)]
			pose.head_shift = Vector2(-1,2)
			pose.head_tilt = -0.07
			pose = _blend(base,pose,envelope)
		"shoulder_roll":
			var roll := phase*TAU*1.5
			pose.shoulder = Vector2(-1+cos(roll)*2,-44+sin(roll)*2)
			pose.hands = [Vector2(-13,-39+sin(roll)*2),Vector2(7,-45+cos(roll)*2)]
			pose.head_shift = Vector2(-1,1)
			pose.head_tilt = -0.10
			pose = _blend(base,pose,envelope)
			pose.blink = envelope>0.85
		"beard_check":
			pose.shoulder = Vector2(-1,-41)
			pose.hands = [Vector2(-10,-32),Vector2(9,-47+sin(phase*TAU*3)*2)]
			pose.head_shift = Vector2(1,-1)
			pose.head_tilt = -0.04
			pose = _blend(base,pose,envelope)
		"goggles_check":
			pose.shoulder = Vector2(2,-43)
			pose.hands = [Vector2(-5,-55),Vector2(11,-55+maxf(0.0,sin(phase*TAU*4))*2)]
			pose.head_shift = Vector2(0,1)
			pose.head_tilt = sin(phase*TAU*2)*0.07
			pose = _blend(base,pose,envelope)
		"tool_check":
			pose.shoulder = Vector2(4,-42)
			pose.hands = [Vector2(9,-35),Vector2(20,-36+sin(phase*TAU*4)*1.4)]
			pose.head_shift = Vector2(2,3)
			pose.head_tilt = 0.09
			pose = _blend(base,pose,envelope)
			pose.prop = "wrench" if envelope>0.35 else ""
		"helmet":
			pose.hands = [Vector2(-10,-28),Vector2(8+roundf(sin(phase*TAU*4)*smoothstep(0.18,0.30,phase)*(1.0-smoothstep(0.64,0.78,phase))*1.5),-59)]
			pose.head_shift = Vector2(0,1)
			pose.shoulder = Vector2(-1,-42)
			pose = _blend(base,pose,envelope)
		"boot":
			pose.hip = Vector2(-3,-25)
			pose.shoulder = Vector2(-5,-42)
			pose.feet = [Vector2(-6,-3),Vector2(16+roundf(sin(phase*42)*2),-11+roundf(sin(phase*32)))]
			pose.hands = [Vector2(-14,-35),Vector2(14,-34)]
			pose.head_shift = Vector2(1,3)
			pose = _blend(base,pose,envelope)
		"thoughtful":
			pose.shoulder = Vector2(1,-42)
			pose.hands = [Vector2(9,-38),Vector2(11,lerpf(-45,-48,smoothstep(0.48,0.62,phase)))]
			pose.head_shift = Vector2(2,2)
			pose.head_tilt = 0.07
			pose = _blend(base,pose,envelope)
			pose.watch = envelope>0.70 and phase<0.66
		"stretch":
			pose.shoulder = Vector2(0,-44)
			pose.hands = [Vector2(-11,-61),Vector2(12,lerpf(-49,-61,smoothstep(0.38,0.61,phase)))]
			pose.head_tilt = -0.06
			pose = _blend(base,pose,envelope)
			pose.mouth = envelope>0.85 and phase<0.61
			pose.blink = envelope>0.70
		"guard", "limp":
			pose.shoulder = Vector2(2,-41)
			pose.hands = [Vector2(-10,-29),Vector2(-2,-32)]
			pose.head_shift = Vector2(1,1)
			if kind=="limp":
				var cycle := fposmod(gait,TAU)
				var stride := sin(cycle)
				pose.feet = [Vector2(stride*9,-3-maxf(0,cos(cycle))*6),Vector2(-stride*4,-3-maxf(0,-cos(cycle))*2)]
				pose.hip.y += maxf(0,sin(cycle))*2
				pose.shoulder.y += maxf(0,sin(cycle))*2
		"downed", "rise":
			var lying := neutral()
			lying.hip = Vector2(0,-10)
			lying.shoulder = Vector2(-17,-12)
			lying.feet = [Vector2(13,-4),Vector2(23,-3)]
			lying.hands = [Vector2(-24,-3),Vector2(-7,-6)]
			lying.blink = true
			var kneeling := neutral()
			kneeling.hip = Vector2(-5,-13)
			kneeling.shoulder = Vector2(3,-28)
			kneeling.feet = [Vector2(-17,-3),Vector2(11,-3)]
			kneeling.hands = [Vector2(-9,-17),Vector2(17,-6)]
			var elbow := lying.duplicate(true)
			elbow.shoulder = Vector2(-10,-23)
			elbow.hands = [Vector2(-23,-3),Vector2(5,-15)]
			if kind=="downed":
				pose = _blend(base,kneeling,phase/0.44) if phase<0.44 else _blend(kneeling,lying,(phase-0.44)/0.56)
				pose.blink = phase>0.4
			else:
				if phase<0.30: pose = _blend(lying,elbow,phase/0.30)
				elif phase<0.65: pose = _blend(elbow,kneeling,(phase-0.30)/0.35)
				else: pose = _blend(kneeling,base,(phase-0.65)/0.35)
		"bandage_self", "splint_self":
			pose.hip = Vector2(-3,-15 if kind=="splint_self" else -25)
			pose.shoulder = pose.hip+Vector2(5,-17)
			pose.head_shift = Vector2(2,3)
			var anchor := Vector2(9,-12) if kind=="splint_self" else Vector2(2,-34)
			pose.hands = [anchor+Vector2(-3,-2),anchor+Vector2(4,sin(phase*TAU*4)*2)]
			pose.feet = [Vector2(-8,-3),Vector2(8,-3)]
			pose.bandage = true
			pose.splint = kind=="splint_self"
		"aid_bandage", "aid_splint", "aid_revive", "aid_resuscitate":
			pose.hip = Vector2(-4,-14)
			pose.shoulder = Vector2(9,-29)
			pose.feet = [Vector2(-18,-3),Vector2(12,-3)]
			pose.head_shift = Vector2(2,3)
			var compress := kind in ["aid_revive","aid_resuscitate"]
			var pulse := pow(maxf(0.0,sin(phase*TAU*(10 if kind=="aid_resuscitate" else 7))),2.0)
			var hand := Vector2(clampf(reach.x,12,53),clampf(reach.y,-38,-9))
			var lean := clampf((hand.x-27.0)/24.0,0.0,1.0)
			pose.hip.x += lean*16.0
			pose.shoulder.x += lean*18.0
			pose.shoulder.y += lean*4.0
			pose.feet[0].x = -18.0+lean*8.0
			pose.shoulder.y += pulse*2 if compress else 0.0
			pose.hands = [hand+Vector2(-3,-2),hand+Vector2(2,pulse*2 if compress else sin(phase*TAU*5)*2)]
			pose.bandage = not compress
			pose.aid = true
			pose.splint_tool = kind=="aid_splint"
	if Additional.CATALOG.has(kind):
		pose = Additional.sample(kind,phase,base)
	# Hand anchors used by dressings/tests are the same endpoints actually drawn.
	# Keep both forearms finite even at the outer edge of the care reach.
	var body := torso_transform(pose)
	for index in 2:
		var shoulder := body*Vector2(-6 if index==0 else 3,0)
		var hand: Vector2 = pose.hands[index]
		if shoulder.distance_to(hand)>22.9:
			pose.hands[index] = shoulder+(hand-shoulder).normalized()*22.9
	return pose

static func _joint(a: Vector2,b: Vector2,la: float,lb: float,side: float=1.0) -> Vector2:
	var point := joint_position(a,b,la,lb,side)
	return point if _continuous else point.round()

static func joint_position(a: Vector2,b: Vector2,la: float,lb: float,side: float=1.0) -> Vector2:
	# A folded unequal-length chain has a minimum reachable distance. Below
	# that distance the old cosine term put elbows far beyond the shoulder.
	# Keep the actual grip and bound the solve to the two-bone reach envelope.
	var offset := b-a
	var distance := clampf(offset.length(),maxf(0.1,absf(la-lb)+0.01),la+lb-0.01)
	var along := (la*la-lb*lb+distance*distance)/(2*distance)
	var height := sqrt(maxf(0,la*la-along*along))
	var axis := offset.normalized() if offset.length()>0.01 else Vector2.DOWN
	# Godot orthogonal() rotates clockwise; the native atlas authoring rig
	# uses (-dy, dx). Match its bend side so knees/elbows do not flip at
	# atlas/articulated transitions.
	return a+axis*along-axis.orthogonal()*side*height

static func arm_elbows(pose: Dictionary) -> Array[Vector2]:
	# Joint hints are part of a pose, including transitions to an unhinted rig.
	# Resolve the same endpoints/bend as the renderer before blending them.
	var body := torso_transform(pose)
	var result: Array[Vector2] = []
	for index in 2:
		if pose.has("elbows") and pose.elbows[index] is Vector2:
			result.append(pose.elbows[index])
			continue
		var attachment := body*shoulder_local(pose,index)
		var hand: Vector2 = pose.hands[index]
		var offset := hand-attachment
		if offset.length()>22.9: hand=attachment+offset.normalized()*22.9
		var bend := -1.0 if bool(pose.get("back",false)) else 1.0
		var elbow := joint_position(attachment,hand,11,12,bend)
		if bool(pose.get("crawling",false)):
			var other := joint_position(attachment,hand,11,12,-1)
			if other.y<elbow.y: elbow=other
		result.append(elbow)
	return result

static func blend_arm_elbows(a: Dictionary,b: Dictionary,weight: float) -> Array[Vector2]:
	var first := arm_elbows(a)
	var second := arm_elbows(b)
	return [first[0].lerp(second[0],weight),first[1].lerp(second[1],weight)]

static func _line(node: CanvasItem,a: Vector2,b: Vector2,color: Color,width: float=1.0) -> void:
	node.draw_line(a if _continuous else a.round(),b if _continuous else b.round(),color,width,false)

static func _poly(node: CanvasItem,points: Array,color: Color,outline: bool=false) -> void:
	var vertices := PackedVector2Array()
	for point: Vector2 in points: vertices.append(point if _continuous else point.round())
	node.draw_colored_polygon(vertices,color)
	if outline:
		vertices.append(vertices[0])
		node.draw_polyline(vertices,colors.ink,1,false)

static func _box(node: CanvasItem,at: Vector2,size: Vector2,color: Color) -> void:
	Quads.rect(node,Rect2(at if _continuous else at.round(),size.round()),color)

static func _leg(node: CanvasItem,hip: Vector2,foot: Vector2,front: bool,crawling: bool=false,foot_angle: float=0.0) -> Vector2:
	var knee := _joint(hip,foot,12,12,-1)
	if crawling:
		var other := _joint(hip,foot,12,12,1)
		if other.y>knee.y: knee=other
		knee.y=minf(knee.y,minf(-5.0,foot.y-2.0))
	var high: Color = colors.trouser_light if front else colors.shadow
	var mid: Color = colors.trouser if front else colors.deep
	for segment in [[hip,knee,9],[knee,foot,8]]:
		_line(node,segment[0],segment[1],colors.ink,segment[2])
		_line(node,segment[0]+Vector2(0,-1),segment[1]+Vector2(0,-1),mid,segment[2]-2)
		_line(node,segment[0]+Vector2(-1,-1),segment[1]+Vector2(-1,-2),high,2)
	_box(node,knee+Vector2(-2,-1),Vector2(5,4),colors.shadow)
	_box(node,knee+Vector2(-1,-1),Vector2(4,1),high)
	# Optional dance heel/toe articulation uses the existing boot polygons. The
	# pivot is corrected to keep the lowest painted sole on its contact plane.
	var boot := foot_transform(foot,foot_angle)
	_panel(node,boot,[Vector2(-4,-4),Vector2(2,-4),Vector2(3,-1),Vector2(7,0),Vector2(7,3),Vector2(-5,3),Vector2(-5,0)],colors.boot,true)
	_patch(node,boot,Vector2(-3,-2),Vector2(5,3),colors.boot_light if front else colors.strap)
	_patch(node,boot,Vector2(-4,2),Vector2(12,2),colors.sole)
	_patch(node,boot,Vector2(3,0),Vector2(3,1),colors.leather_light if front else colors.boot_light)
	return knee

static func foot_transform(foot: Vector2,angle: float=0.0) -> Transform2D:
	if is_zero_approx(angle):
		return Transform2D(0.0,foot)
	var rotation := Transform2D(angle,Vector2.ZERO)
	var lowest := maxf((rotation*Vector2(-5,3)).y,(rotation*Vector2(8,3)).y)
	return Transform2D(angle,foot+Vector2(0,3.0-lowest))

static func _ladder_leg(node: CanvasItem,hip: Vector2,foot: Vector2,side: float) -> void:
	var a := _joint(hip,foot,12,12,-1)
	var b := _joint(hip,foot,12,12,1)
	var knee := a if (a.x<b.x if side<0 else a.x>b.x) else b
	for segment in [[hip,knee],[knee,foot]]:
		_line(node,segment[0],segment[1],colors.ink,9)
		_line(node,segment[0],segment[1],colors.trouser,7)
		_line(node,segment[0]+Vector2(-1,0),segment[1]+Vector2(-1,0),colors.trouser_light,2)
	_box(node,foot+Vector2(-5,-4),Vector2(10,7),colors.ink)
	_box(node,foot+Vector2(-3,-3),Vector2(6,5),colors.boot_light)
	_box(node,foot+Vector2(-5,2),Vector2(10,2),colors.sole)

static func _draw_cargo(node: CanvasItem,anchor: Vector2,kind: String,pouring: bool=false,clock: float=0.0,flow_end: Vector2=Vector2.INF,flow_gain: float=1.0) -> void:
	if kind in ["limestone","glass","tungsten","alloy","jaw_trap","blast_trap","sentry_kit"]:
		MaterialArt.draw_material(node,kind,anchor)
	elif ItemCatalog.contains(kind):
		ItemCatalog.draw_carried(node,kind,anchor,1.0,pouring and kind=="concrete")
		if pouring and kind=="concrete":
			var lip := anchor+Vector2(8,3)
			var end := flow_end if flow_end.is_finite() else lip+Vector2(3,18)
			var gain := clampf(flow_gain,0.0,1.0)
			var tangent := end-lip
			# A narrow continuous strand connects the real bucket lip and target.
			# Only three travelling clusters vary; no emitters or random speckle.
			_line(node,lip,end,Color("777e6c"),2)
			for index in 3:
				var fall := fposmod(clock*3.5+float(index)/3.0,1.0)
				var at := lip+tangent*fall
				_box(node,at.round(),Vector2(2,3 if index==0 else 2),Color("bdbea0") if index==0 else Color("a6ab91"))
			_box(node,(end-Vector2(2,0)).round(),Vector2(4+roundf(gain*2),2),Color("969e84"))

static func _arm(node: CanvasItem,shoulder: Vector2,hand: Vector2,front: bool,back: bool=false,crawling: bool=false,elbow_hint: Variant=null) -> void:
	if shoulder.distance_to(hand)>22.9:
		hand = shoulder+(hand-shoulder).normalized()*22.9
	var elbow := _joint(shoulder,hand,11,12,-1 if back else 1)
	if crawling:
		var other := _joint(shoulder,hand,11,12,-1)
		if other.y<elbow.y: elbow=other
	if elbow_hint is Vector2:
		elbow = elbow_hint
	_line(node,shoulder,elbow,colors.ink,9)
	_line(node,shoulder,elbow,colors.olive if front else colors.shadow,7)
	_line(node,shoulder+Vector2(-2,0),elbow+Vector2(-2,0),colors.light if front else colors.olive,2)
	_line(node,elbow,hand,colors.ink,7)
	_line(node,elbow,hand,colors.cloth if front else colors.olive,5)
	_line(node,elbow+Vector2(0,-1),hand+Vector2(0,-1),colors.light if front else colors.cloth,2)
	_box(node,elbow+Vector2(-2,-1),Vector2(4,3),colors.shadow)
	_box(node,hand+Vector2(-3,-2),Vector2(7,6),colors.ink)
	_box(node,hand+Vector2(-2,-1),Vector2(5,4),colors.leather_light if front else colors.leather)
	_box(node,hand+Vector2(1,-1),Vector2(2,2),colors.skin_light if front else colors.skin)
	_box(node,hand+Vector2(-2,2),Vector2(4,1),colors.leather)

static func torso_transform(pose: Dictionary) -> Transform2D:
	var up: Vector2 = (pose.shoulder-pose.hip).normalized()
	return Transform2D(up.angle()+PI*0.5,pose.shoulder)

static func shoulder_local(pose: Dictionary,index: int) -> Vector2:
	if bool(pose.get("back",false)):
		return Vector2(-8 if index==0 else 8,0)
	return Vector2(-6 if index==0 else 3,0)

static func _panel(node: CanvasItem,tx: Transform2D,points: Array,color: Color,outline: bool=false) -> void:
	var mapped: Array = []
	for point: Vector2 in points: mapped.append(tx*point)
	_poly(node,mapped,color,outline)

static func _patch(node: CanvasItem,tx: Transform2D,at: Vector2,size: Vector2,color: Color) -> void:
	Quads.patch(node,tx,at,size,color,not _continuous)

static func _atlas_piece(node: CanvasItem,tx: Transform2D,points: Array,uv_points: Array,texture: Texture2D,origin: Vector2) -> void:
	var mapped := PackedVector2Array()
	var uv := PackedVector2Array()
	for index in points.size():
		var point := tx*Vector2(points[index])
		mapped.append(point if _continuous else point.round())
		uv.append((origin+Vector2(uv_points[index]))/texture.get_size())
	node.draw_polygon(mapped,PackedColorArray([Color.WHITE]),uv,texture)

static func _textured_torso(node: CanvasItem,pose: Dictionary,id: String) -> void:
	var tx := torso_transform(pose)
	# The standalone texture includes the character's complete coat and pack;
	# unlike an atlas crop it cannot bring a third arm into articulated poses.
	var points := [Vector2(-48,-48),Vector2(64,-48),Vector2(64,64),Vector2(-48,64)]
	_atlas_piece(node,tx,points,points,IdentityArt.torso(id,bool(pose.get("back",false))),Vector2(48,48))

static func head_transform(pose: Dictionary) -> Transform2D:
	var body := torso_transform(pose)
	var pivot: Vector2 = pose.get("head_pivot",Vector2.ZERO)
	var tx := Transform2D(body.get_rotation()+float(pose.head_tilt),Vector2.ZERO)
	tx.origin = body*(Vector2(1,-15)+Vector2(pose.head_shift)+pivot)-tx.basis_xform(pivot)
	return tx

static func _head(node: CanvasItem,pose: Dictionary,id: String) -> void:
	var tx := head_transform(pose)
	var points := [Vector2(-49,-33),Vector2(63,-33),Vector2(63,79),Vector2(-49,79)]
	_atlas_piece(node,tx,points,points,IdentityArt.head(id,bool(pose.get("back",false))),Vector2(49,33))
	if pose.blink and CharacterCatalog.presentation_id(id,"visual")!="ivo":
		_patch(node,tx,Vector2(5,4),Vector2.ONE,colors.skin_shadow)
	if pose.mouth and CharacterCatalog.presentation_id(id,"visual")!="branko":
		_patch(node,tx,Vector2(3,10),Vector2(3,3),colors.deep)

static func equipment(node: CanvasItem,pose: Dictionary,worker: Node) -> void:
	var tier: int = worker.progression.armor_tier if "progression" in worker and is_instance_valid(worker.progression) else 0
	_identity_equipment(node,pose,str(worker.character_id),tier)

static func _identity_equipment(node: CanvasItem,pose: Dictionary,character_id: String,tier: int) -> void:
	var tx := torso_transform(pose)
	var length: float = Vector2(pose.shoulder).distance_to(pose.hip)
	if bool(pose.get("back",false)):
		if tier>0:
			for side in [-1,1]:
				_patch(node,tx,Vector2(side*9-2,-2),Vector2(4,17),Color("222b2d"))
				_patch(node,tx,Vector2(side*9-1,-1),Vector2(2,14),Color("77817a"))
		return
	if tier>0:
		_panel(node,tx,[Vector2(-8,0),Vector2(4,0),Vector2(7,5),Vector2(6,length-3),Vector2(-7,length-3)],Color("242d2e"))
		_panel(node,tx,[Vector2(-6,1),Vector2(2,1),Vector2(4,5),Vector2(3,length-5),Vector2(-5,length-5)],Color("727f79") if tier==1 else Color("88958b"))
		_line(node,tx*Vector2(-6,1),tx*Vector2(2,1),Color("bec0a4"))
		_line(node,tx*Vector2(-5,8),tx*Vector2(3,8),Color("485554"),2)
		if tier==2:
			_patch(node,tx,Vector2(-10,-3),Vector2(7,5),Color("293235"))
			_patch(node,tx,Vector2(-9,-2),Vector2(5,2),Color("a4ab98"))
	var spec := CharacterCatalog.data(character_id)
	_patch(node,tx,Vector2(-7,3),Vector2(5,5),Color("26312f"))
	_patch(node,tx,Vector2(-6,4),Vector2(3,2),Color(spec.accent))
	if CharacterCatalog.presentation_id(character_id,"visual") == "branko":
		_patch(node,tx,Vector2(-6,7),Vector2(3,1),Color(spec.accent).darkened(0.2))
	elif CharacterCatalog.presentation_id(character_id,"visual") in ["ivo", "nora", "levin"]:
		_patch(node,tx,Vector2(-5,3),Vector2(1,5),Color(spec.accent).lightened(0.12))

	elif CharacterCatalog.presentation_id(character_id,"visual") == "selma":
		_patch(node,tx,Vector2(-6,3),Vector2(1,5),Color("e4e4ce"))
		_patch(node,tx,Vector2(-8,5),Vector2(5,1),Color("e4e4ce"))

static func draw_legs(node: CanvasItem,pose: Dictionary,id: String="mara") -> void:
	colors = IdentityArt.palette(id,C)
	var previous_continuous := _continuous
	_continuous=bool(pose.get("continuous",false))
	_leg(node,pose.hip+Vector2(-4,0),pose.feet[0],false)
	_leg(node,pose.hip+Vector2(4,0),pose.feet[1],true)
	if pose.splint:
		draw_splint(node,pose.hip+Vector2(4,0),pose.feet[1])
	_continuous=previous_continuous

static func draw_splint(node: CanvasItem,hip: Vector2,foot: Vector2) -> void:
	var knee := _joint(hip,foot,12,12,-1)
	var start := knee+Vector2(4,-1)
	var end := foot+Vector2(3,-3)
	_line(node,start,end,colors.ink,4)
	_line(node,start,end,Color("aa946c"),2)
	for portion in [0.22,0.75]:
		var at := start.lerp(end,portion)
		_line(node,at+Vector2(-5,0),at+Vector2(1,0),Color("d8d5b8"),2)

static func draw_pose(node: CanvasItem,pose: Dictionary,worker: Node) -> void:
	var tier: int = worker.progression.armor_tier if "progression" in worker and is_instance_valid(worker.progression) else 0
	draw_identity_pose(node,pose,str(worker.character_id),tier)

static func draw_identity_pose(node: CanvasItem,pose: Dictionary,id: String,armor_tier: int=0) -> void:
	colors = IdentityArt.palette(id,C)
	var previous_continuous := _continuous
	_continuous=bool(pose.get("continuous",false))
	var hidden:=int(pose.get("hidden_limbs",0))
	var tx := torso_transform(pose)
	var back := bool(pose.get("back",false))
	var crawling := bool(pose.get("crawling",false))
	var hip_spread := float(pose.get("hip_spread",4.0))
	var foot_angles: Array = pose.get("foot_angles",[0.0,0.0])
	var elbows: Array = pose.get("elbows",[null,null])
	var rear_shoulder := tx*shoulder_local(pose,0)
	var front_shoulder := tx*shoulder_local(pose,1)
	if not hidden&4:
		if back: _ladder_leg(node,pose.hip+Vector2(-5,0),pose.feet[0],-1)
		else: _leg(node,pose.hip+Vector2(-hip_spread,0),pose.feet[0],false,crawling,float(foot_angles[0]))
	if not hidden&1: _arm(node,rear_shoulder,pose.hands[0],false,back,crawling,elbows[0])
	if not hidden&8:
		if back: _ladder_leg(node,pose.hip+Vector2(5,0),pose.feet[1],1)
		else: _leg(node,pose.hip+Vector2(hip_spread,0),pose.feet[1],true,crawling,float(foot_angles[1]))
	_textured_torso(node,pose,id)
	_head(node,pose,id)
	_identity_equipment(node,pose,id,armor_tier)
	if pose.has("cargo") and not str(pose.get("cargo_kind","")).is_empty():
		_draw_cargo(node,pose.cargo,str(pose.cargo_kind),bool(pose.get("cargo_pour",false)),float(pose.get("cargo_clock",0.0)),pose.get("cargo_flow_end",Vector2.INF),float(pose.get("cargo_flow",1.0)))
	if pose.get("prop","")=="radio":
		var at: Vector2 = pose.hands[1]+Vector2(-2,-3)
		_box(node,at,Vector2(6,9),colors.ink)
		_box(node,at+Vector2(1,1),Vector2(4,6),colors.deep)
		_line(node,at+Vector2(1,0),at+Vector2(1,-5),colors.steel,1)
		_box(node,at+Vector2(3,1),Vector2.ONE,Color("edbf6e"))
	elif pose.get("prop","")=="wrench":
		var at: Vector2 = pose.hands[1]
		_line(node,at+Vector2(-1,3),at+Vector2(2,-9),colors.ink,4)
		_line(node,at+Vector2(-1,3),at+Vector2(2,-9),colors.steel,2)
		_line(node,at+Vector2(-1,-8),at+Vector2(4,-8),colors.steel_light,2)
		_box(node,at+Vector2(-1,-11),Vector2(2,3),colors.steel)
		_box(node,at+Vector2(4,-11),Vector2(2,3),colors.steel)
	var held_prop := str(pose.get("prop",""))
	var left_hand: Vector2 = pose.hands[0]
	var right_hand: Vector2 = pose.hands[1]
	match held_prop:
		"work_hammer","work_wrench","work_trowel":
			var tool := Transform2D(float(pose.get("work_tool_angle",0.0)),right_hand)
			_line(node,tool*Vector2(-2,4),tool*Vector2(10,-2),colors.ink,4)
			_line(node,tool*Vector2(-2,4),tool*Vector2(10,-2),colors.leather_light if held_prop=="work_hammer" else colors.steel,2)
			if held_prop=="work_hammer":
				_panel(node,tool,[Vector2(6,-6),Vector2(13,-6),Vector2(14,-2),Vector2(7,0)],colors.steel,true)
				_line(node,tool*Vector2(7,-5),tool*Vector2(12,-5),colors.steel_light)
			elif held_prop=="work_wrench":
				_panel(node,tool,[Vector2(7,-5),Vector2(12,-6),Vector2(15,-3),Vector2(12,-3),Vector2(10,-1),Vector2(12,1),Vector2(8,1)],colors.steel,true)
			else:
				_panel(node,tool,[Vector2(8,-5),Vector2(17,-2),Vector2(8,2)],colors.steel,true)
				_line(node,tool*Vector2(9,-4),tool*Vector2(15,-2),colors.steel_light)
		"rifle_magazine":
			# Box magazine for the convoy escort's real personal rifle reload;
			# it is separate from the linked feed used by the mounted weapon.
			var magazine := Transform2D(-0.12,right_hand+Vector2(-3,1))
			_panel(node,magazine,[Vector2(0,-3),Vector2(6,-3),Vector2(7,7),Vector2(5,9),Vector2(0,8)],Color("263236"),true)
			_patch(node,magazine,Vector2(1,-2),Vector2(4,9),Color("748376"))
			_patch(node,magazine,Vector2(1,-2),Vector2(1,9),Color("a8ad91"))
			for rib in 3: _patch(node,magazine,Vector2(2,1+rib*2),Vector2(3,1),Color("485750"))
			_patch(node,magazine,Vector2(2,-3),Vector2(3,2),Color("b99c67"))
		"mounted_rounds":
			# A small linked brass feed, held by the reloading hand.
			for cartridge in 3:
				var at := right_hand+Vector2(-6+cartridge*4,-4)
				_box(node,at,Vector2(3,9),colors.ink)
				_box(node,at+Vector2(1,1),Vector2(1,6),Color("c1a46a"))
			_line(node,right_hand+Vector2(-5,3),right_hand+Vector2(4,3),colors.steel,2)
		"notebook":
			_box(node,left_hand+Vector2(-5,-2),Vector2(15,10),colors.ink)
			_box(node,left_hand+Vector2(-4,-1),Vector2(13,8),Color("c3bb94"))
			_line(node,left_hand+Vector2(-2,1),left_hand+Vector2(6,1),Color("797c69"))
			_line(node,left_hand+Vector2(-2,4),left_hand+Vector2(4,4),Color("797c69"))
			_line(node,right_hand+Vector2(-2,3),right_hand+Vector2(2,-4),colors.ink,2)
		"canteen":
			_box(node,right_hand+Vector2(-4,-3),Vector2(8,11),colors.ink)
			_box(node,right_hand+Vector2(-3,-2),Vector2(6,8),Color("727964"))
			_box(node,right_hand+Vector2(-2,-6),Vector2(4,4),colors.steel)
			_box(node,right_hand+Vector2(-2,0),Vector2(1,5),Color("a2aa8e"))
		"spring":
			var coil := PackedVector2Array()
			for index in 9:
				coil.append(left_hand.lerp(right_hand,float(index)/8.0)+Vector2(0,-2 if index%2==0 else 2))
			node.draw_polyline(coil,colors.ink,3,false)
			node.draw_polyline(coil,colors.steel_light,1,false)
		"cloth":
			_poly(node,[right_hand+Vector2(-4,-3),right_hand+Vector2(4,-4),right_hand+Vector2(5,4),right_hand+Vector2(0,7),right_hand+Vector2(-4,3)],Color("abb09a"),true)
			_line(node,right_hand+Vector2(1,2),right_hand+Vector2(2,5),Color("6d806e"))
		"meter":
			_box(node,left_hand+Vector2(-3,-7),Vector2(11,12),colors.ink)
			_box(node,left_hand+Vector2(-2,-6),Vector2(9,10),Color("687a6b"))
			_box(node,left_hand+Vector2(0,-4),Vector2(5,3),Color("b6c7a1"))
			_line(node,left_hand+Vector2(1,-6),left_hand+Vector2(1,-14),colors.steel)
			_box(node,left_hand+Vector2(3,1),Vector2(2,2),Color("d8a166"))
	if not hidden&2: _arm(node,front_shoulder,pose.hands[1],true,back,crawling,elbows[1])
	for wound in [[1,rear_shoulder],[2,front_shoulder],[4,pose.hip+Vector2(-hip_spread,0)],[8,pose.hip+Vector2(hip_spread,0)]]:
		if hidden&int(wound[0]): _box(node,Vector2(wound[1])-Vector2(2,1),Vector2(5,3),Color("702c29"))
	if pose.watch:
		_box(node,pose.hands[0]+Vector2(-3,-3),Vector2(5,4),colors.ink)
		_box(node,pose.hands[0]+Vector2(-2,-3),Vector2(3,2),colors.steel_light)
	if pose.bandage:
		var center: Vector2 = (Vector2(pose.hands[0])+Vector2(pose.hands[1]))*0.5
		_box(node,center+Vector2(-4,-2),Vector2(9,4),Color("d8d5b8"))
		_box(node,center+Vector2(-2,-1),Vector2(5,1),Color("949d89"))
	if pose.splint_tool:
		var center: Vector2 = (Vector2(pose.hands[0])+Vector2(pose.hands[1]))*0.5
		_line(node,center+Vector2(-4,-7),center+Vector2(2,8),colors.ink,4)
		_line(node,center+Vector2(-4,-7),center+Vector2(2,8),Color("aa946c"),2)
	if pose.splint and not hidden&8:
		draw_splint(node,pose.hip+Vector2(hip_spread,0),pose.feet[1])
	_continuous=previous_continuous
