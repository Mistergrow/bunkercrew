extends RefCounted
## Draw-only roadside stories. All action comes from the shared starting clock;
## these paintings never move actors, grant cargo or create combat entities.
const REFERENCE := Vector2(1440,900)
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Parallax := preload("res://scripts/parallax_catalog.gd")
const Trees := preload("res://scripts/scenario_prop_catalog.gd")
const HULL := preload("res://assets/vehicles/convoy_hull_v2.png")
const PARTS := preload("res://assets/vehicles/convoy_parts_v1.png")
const LANDMARKS := preload("res://assets/expedition/roadside_landmarks_v1.png")
const DEPOT := preload("res://assets/expedition/fuel_depot_v1.png")
const METAL := preload("res://assets/machinery/components.png")
const VERGE := preload("res://assets/expedition/road_verge_v2.png")
const DEAD_TREE := preload("res://assets/environments/props/dead_tree.png")
const CHARRED_TREE := preload("res://assets/cinematics/storm_charred_tree_v1.png")
const CONIFER := preload("res://assets/environments/props/conifer_tree.png")
const INK := Color("182122")
const EDGE := Color("a7a58d")
const RUST := Color("806044")
const WHEEL_REGION := Rect2(132,103,451,454)
const HULL_REGION := Rect2(24,131,1751,558)
const SHELTER_REGION := Rect2(886,12,610,498)
const LOCKER_REGION := Rect2(930,571,574,377)
const BARRIER_REGION := Rect2(36,265,775,245)
static var _backgrounds: Dictionary = {}

static func sample(context: Dictionary, elapsed: float, reduced: bool=false) -> Dictionary:
	var supplied_duration:=float(context.get("duration",8.0))
	var duration:=clampf(supplied_duration,.01,12.0) if is_finite(supplied_duration) else 8.0
	var seconds := clampf(elapsed,0,duration) if is_finite(elapsed) else 0.0
	var progress := seconds/duration
	var id := str(context.get("id","signal"))
	if id not in ["signal","storm","supply"]: id="signal"
	var dolly := smoothstep(.05,.92,progress)
	var strike := smoothstep(.119,.125,progress)*(1.0-smoothstep(.132,.17,progress)) if id=="storm" else 0.0
	return {"id":id,"time":seconds,"progress":progress,"duration":duration,
		"camera_zoom":1.0 if reduced else 1.0+dolly*.028,
		"camera_shift":Vector2.ZERO if reduced else Vector2(lerpf(10,-9,dolly),-dolly*2),
		"power":smoothstep(.20,.42,progress) if id=="signal" else smoothstep(.16,.30,progress),
		"lock":smoothstep(.44,.49,progress),"shutter":smoothstep(.27,.53,progress),
		"strike":strike*(.32 if reduced else 1.0),"fire":smoothstep(.13,.22,progress) if id=="storm" else 0.0,
		"rain_count":26 if reduced else 84,"smoke_count":3 if reduced else 7,
		"reduced":reduced}

static func draw(canvas: CanvasItem, context: Dictionary, elapsed: float, reduced: bool) -> void:
	var state := sample(context,elapsed,reduced)
	var environment := str(context.get("environment","ash_foundry"))
	if not Parallax.PROFILES.has(environment): environment="ash_foundry"
	var crew := _crew(context)
	_background(canvas,environment,state)
	_road(canvas,state)
	match str(state.id):
		"storm": _storm(canvas,context,crew,state)
		"supply": _supply(canvas,context,crew,state)
		_: _signal(canvas,context,crew,state)
	_foreground(canvas,state)
	canvas.draw_set_transform(Vector2.ZERO)

static func _crew(context: Dictionary) -> Array[String]:
	var result: Array[String]=[]
	var supplied: Variant=context.get("crew_ids",[])
	if supplied is Array:
		for id: Variant in supplied:
			if result.size()>=4: break
			result.append(str(id) if IdentityArt.HEAD.has(str(id)) else "mara")
	if result.is_empty():
		var selected:=str(context.get("character_id","mara"))
		result.append(selected if IdentityArt.HEAD.has(selected) else "mara")
	else:
		# The actual driver may be P2/P3/P4. Lead poses and the cab aperture
		# belong to that identity, while the rest of the real party—including
		# repeated characters—must remain present exactly once per member.
		var driver_index:=result.find(str(context.get("character_id","")))
		if driver_index>0:
			var driver: String=result.pop_at(driver_index)
			result.push_front(driver)
	return result

static func _space(canvas: CanvasItem, state: Dictionary, at: Vector2=Vector2.ZERO, scale: float=1.0, angle: float=0.0, facing: float=1.0) -> void:
	var zoom: float=state.camera_zoom
	var camera: Vector2=state.camera_shift
	canvas.draw_set_transform((at-REFERENCE*.5)*zoom+REFERENCE*.5+camera,angle,Vector2(scale*facing,scale)*zoom)

static func _background(canvas: CanvasItem, environment: String, state: Dictionary) -> void:
	if not _backgrounds.has(environment):
		var loaded_textures: Array[Texture2D]=[]
		for path: String in Parallax.paths(environment): loaded_textures.append(load(path) as Texture2D)
		_backgrounds[environment]=loaded_textures
	var textures: Array=_backgrounds[environment]
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_rect(Rect2(Vector2.ZERO,REFERENCE),Color("182832"))
	for index in 3:
		var texture: Texture2D=textures[index]
		if texture==null: continue
		var width:=1504.0+index*64.0
		var height:=width*texture.get_height()/texture.get_width()
		var at: Vector2=Vector2((REFERENCE.x-width)*.5,620-height)+Vector2(state.camera_shift)*[.12,.32,.58][index]
		canvas.draw_texture_rect(texture,Rect2(at,Vector2(width,height)),false,Color("a7b3b7") if state.id=="storm" else Color("c3c8c1"))
	canvas.draw_rect(Rect2(0,0,1440,625),Color(.02,.055,.07,.22 if state.id=="storm" else .12))
	# Sparse service wires add a separate mid-distance silhouette.
	_space(canvas,state,Vector2(0,590),1)
	for x in [122.0,1345.0]:
		canvas.draw_rect(Rect2(x,-243,6,243),Color("263c3c"))
		canvas.draw_line(Vector2(x-11,-235),Vector2(x+20,-235),Color("7c8676"),3,false)
	for cable in 2:
		var path:=PackedVector2Array()
		for segment in 17:
			var position:=float(segment)/16
			path.append(Vector2(122+1223*position,-234+cable*9+sin(position*PI)*(40+sin(float(state.time)*.8)*1.5)))
		canvas.draw_polyline(path,Color("253939"),1,false)

static func _road(canvas: CanvasItem, state: Dictionary) -> void:
	_space(canvas,state)
	canvas.draw_rect(Rect2(-50,587,1540,313),Color("162425"))
	canvas.draw_rect(Rect2(-50,587,1540,43),Color("424e46"))
	canvas.draw_line(Vector2(-50,588),Vector2(1490,588),Color("879381"),3,false)
	canvas.draw_line(Vector2(-50,595),Vector2(1490,595),Color("262f2d"),2,false)
	for index in 25:
		var x:=float(index)*64-28
		canvas.draw_rect(Rect2(x,594,28,2),Color("697561"))
		canvas.draw_line(Vector2(x+48,587),Vector2(x+53,623),Color("28352f"),1,false)
		canvas.draw_rect(Rect2(x+11,610+index%3*2,19,2),Color("343e37"))
	# Broken white survey paint and a shallow puddle live on the same plane.
	for x in [182,501,846,1202]:
		canvas.draw_rect(Rect2(x,598,38,3),Color("8c8b70"))
		canvas.draw_rect(Rect2(x+27,598,5,3),Color("424e46"))
	if state.id=="storm":
		canvas.draw_rect(Rect2(175,591,620,3),Color(.27,.41,.45,.58))
		canvas.draw_rect(Rect2(1010,591,254,2),Color(.42,.49,.48,.48))

static func _sprite(canvas: CanvasItem, texture: Texture2D, region: Rect2, at: Vector2, width: float, state: Dictionary, tint: Color=Color.WHITE) -> void:
	_space(canvas,state,at)
	var height:=width*region.size.y/region.size.x
	canvas.draw_texture_rect_region(texture,Rect2(-width*.5,-height,width,height),region,tint)

static func _metal(canvas: CanvasItem, rect: Rect2, tint: Color=Color.WHITE) -> void:
	canvas.draw_rect(rect.grow(1),INK)
	# Keep native metal grain on narrow supports instead of crushing the whole
	# machinery strip into a flat averaged colour or stretching it vertically.
	for row in ceili(rect.size.y/44.0):
		var height:=minf(44,rect.size.y-row*44)
		canvas.draw_texture_rect_region(METAL,Rect2(rect.position+Vector2(0,row*44),Vector2(rect.size.x,height)),Rect2(1157,215,minf(rect.size.x,179),height),tint)
	canvas.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),EDGE,1,false)
	canvas.draw_line(rect.position+Vector2(rect.size.x,1),rect.end,Color("202825"),2,false)
	for corner in [rect.position+Vector2(3,3),rect.position+Vector2(rect.size.x-4,3),rect.end-Vector2(4,4)]:
		canvas.draw_rect(Rect2(corner,Vector2.ONE),Color("c0ae89"))

static func _worker(canvas: CanvasItem, id: String, at: Vector2, state: Dictionary, kind: String="guard", phase: float=.5, facing: float=1.0, pose_override: Dictionary={}) -> void:
	_space(canvas,state,at,1.95,0,facing)
	var pose:=PoseArt.sample(kind,clampf(phase,0,1),0.0,Vector2(24,-13),id) if pose_override.is_empty() else pose_override
	pose.continuous=true
	PoseArt.draw_identity_pose(canvas,pose,id)

static func _truck(canvas: CanvasItem, at: Vector2, state: Dictionary, crew: Array[String], occupied: bool=false) -> void:
	var rocking:=sin(float(state.time)*1.7)*.11 if occupied and not state.reduced else 0.0
	_space(canvas,state,at,2.48)
	canvas.draw_rect(Rect2(-102,0,204,2),Color(.025,.04,.04,.5))
	canvas.draw_line(Vector2(-81,-13),Vector2(74,-13),INK,6,false)
	for x in [-65.0,-15.0,56.0]:
		canvas.draw_texture_rect_region(PARTS,Rect2(x-12,-23,24,24),WHEEL_REGION)
		canvas.draw_line(Vector2(x-10,-25),Vector2(x+8,-20),Color("93967d"),2,false)
	if occupied:
		for index in range(1,crew.size()):
			var pose:=PoseArt.neutral()
			pose.hip=Vector2(0,-13)
			pose.shoulder=Vector2(1,-30)
			pose.hands=[Vector2(-8,-22),Vector2(8,-28)]
			pose.feet=[Vector2(-5,-3),Vector2(8,-3)]
			pose.head_shift=Vector2(-1,2)
			pose.head_tilt=-.055*smoothstep(.30,.38,float(state.progress))
			_space(canvas,state,at+Vector2((-72+(index-1)*30)*2.48,-37*2.48),2.0)
			PoseArt.draw_identity_pose(canvas,pose,crew[index])
	_space(canvas,state,at+Vector2(0,rocking),2.48)
	canvas.draw_texture_rect_region(HULL,Rect2(-98,-70,196,62.46),HULL_REGION)
	if occupied:
		canvas.draw_texture_rect_region(IdentityArt.torso(crew[0]),Rect2(49,-42,18,7),Rect2(37,45,30,15))
		canvas.draw_texture_rect_region(IdentityArt.head(crew[0]),Rect2(47,-59,24,24),Rect2(34,24,32,36))
		canvas.draw_line(Vector2(47,-36),Vector2(74,-36),Color("b7aa82"),2,false)
	canvas.draw_rect(Rect2(-96,-28,2,3),Color("a45e3b"))
	canvas.draw_rect(Rect2(89,-36,5,3),Color("d5c88f"))
	canvas.draw_line(Vector2(-91,-4),Vector2(94,-4),Color("292f2a"),2,false)
	if not state.reduced:
		for index in 3:
			var age:=fposmod(float(state.time)*.27+index*.33,1)
			canvas.draw_rect(Rect2(38-age*12,-64-age*18,3+age*4,2+age*2),Color(.37,.41,.39,(1-age)*.20))

static func _signal(canvas: CanvasItem, _context: Dictionary, crew: Array[String], state: Dictionary) -> void:
	_tree(canvas,CONIFER,"conifer",Vector2(1348,588),248,state,Color("66817b"),.007)
	_sprite(canvas,LANDMARKS,SHELTER_REGION,Vector2(1080,590),235,state)
	_space(canvas,state,Vector2(1070,421),1.55)
	_metal(canvas,Rect2(-3,-119,6,116),Color("72827a"))
	for index in 7:
		canvas.draw_rect(Rect2(-2,-111+index*15,2,3),RUST.darkened(.2))
	for y in [-102,-72,-42]:
		canvas.draw_line(Vector2(-3,y),Vector2(-24,y+22),Color("364d48"),2,false)
	var angle:=lerpf(-.22,.13,smoothstep(.16,.43,float(state.progress)))
	_space(canvas,state,Vector2(1070,250),1.55,angle)
	_metal(canvas,Rect2(-44,-3,88,7),Color("929783"))
	for x in [-34,-17,0,17,34]: canvas.draw_line(Vector2(x,-16),Vector2(x,16),Color("8b9689"),3,false)
	_space(canvas,state,Vector2(1070,421),1.55)
	var active: float=state.power
	var locked: float=state.lock
	canvas.draw_rect(Rect2(-22,-15,37,12),INK)
	for index in 4:
		var intensity:=active*(.55+.45*sin(float(state.time)*11+index*2)) if locked<.9 else .78
		canvas.draw_rect(Rect2(-18+index*8,-11,4,4),Color(.40+locked*.2,.34+locked*.28,.13+locked*.19,intensity))
	if not state.reduced and active>.1:
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-11,-4),Vector2(-77,107),Vector2(42,107)]),Color(.9,.75,.38,active*.033))
	_truck(canvas,Vector2(385,587),state,crew)
	var tuning:=1.0-smoothstep(.43,.55,float(state.progress))
	var pose:=PoseArt.neutral()
	pose.shoulder=Vector2(3,-41)
	pose.hands=[Vector2(-8,-29),Vector2(17,-31+sin(float(state.time)*5)*tuning*1.4)]
	pose.head_shift=Vector2(1,2)
	pose.head_tilt=.08*tuning
	if tuning<.5: pose=PoseArt.sample("radio_check",lerpf(.20,.75,smoothstep(.46,.94,float(state.progress))),0,Vector2(24,-13),crew[0])
	_worker(canvas,crew[0],Vector2(965,588),state,"guard",.5,1,pose)
	_space(canvas,state,Vector2(985,537))
	_metal(canvas,Rect2(0,-36,15,61),Color("69796b"))
	canvas.draw_line(Vector2(7,-9),Vector2(30,-7+sin(float(state.time)*5)*tuning*2),Color("c0aa76"),3,false)
	canvas.draw_line(Vector2(8,23),Vector2(65,40),Color("283e37"),3,false)
	for index in range(1,crew.size()):
		_worker(canvas,crew[index],Vector2(660+(index-1)*69,588),state,"horizon_scan" if index==1 else "strap_check",clampf(float(state.progress)*.74+.12,0,1),-1 if index==1 else 1)
	_sprite(canvas,LANDMARKS,BARRIER_REGION,Vector2(160,612),191,state,Color("9ca492"))

static func _tree(canvas: CanvasItem, texture: Texture2D, kind: String, root: Vector2, height: float, state: Dictionary, tint: Color, sway: float=0.0) -> void:
	var anchor: Vector2=Trees.TREE_ROOTS[kind]
	var crop: Rect2=Rect2(Trees.TREE_REGIONS[kind])
	crop.size.y=anchor.y-crop.position.y
	var ratio:=height/crop.size.y
	var angle:=sin(float(state.time)*.85)*sway if not state.reduced else 0.0
	_space(canvas,state,root,ratio,angle)
	canvas.draw_texture_rect_region(texture,Rect2(crop.position-anchor,crop.size),crop,tint)

static func _storm(canvas: CanvasItem, _context: Dictionary, crew: Array[String], state: Dictionary) -> void:
	var flame: float=state.fire
	# The first scorch is concealed by the authored lightning flash. Both
	# sprites share the original root/crop and stay on the roadside plane.
	var scorch := smoothstep(0.0,.22,flame)
	if scorch<1.0:
		var bark := Color("899585").darkened(flame*.24)
		bark.a=1.0-scorch
		_tree(canvas,DEAD_TREE,"dead",Vector2(1185,587),330,state,bark,.010)
	if scorch>0.0:
		var charred := Color("899585")
		charred.a=scorch
		_tree(canvas,CHARRED_TREE,"dead",Vector2(1185,587),330,state,charred,.010)
	# The shelter is actual weathered service metal, with posts behind the car.
	_space(canvas,state,Vector2(0,587))
	for x in [208.0,787.0]:
		_metal(canvas,Rect2(x,-260,10,260),Color("626e64"))
		canvas.draw_line(Vector2(x,-260),Vector2(x+58 if x<500 else x-58,-212),INK,6,false)
	_space(canvas,state)
	canvas.draw_texture_rect_region(DEPOT,Rect2(185,296,646,83),Rect2(830,12,1070,137),Color("a1b0a5"))
	_truck(canvas,Vector2(476,587),state,crew,true)
	if float(state.strike)>.001:
		_space(canvas,state)
		var bolt:=PackedVector2Array([Vector2(1178,45),Vector2(1167,151),Vector2(1184,195),Vector2(1146,285),Vector2(1161,319),Vector2(1148,417)])
		canvas.draw_polyline(bolt,Color(.48,.70,.77,float(state.strike)*.28),9,false)
		canvas.draw_polyline(bolt,Color(.88,.93,.86,float(state.strike)*.92),3,false)
		canvas.draw_polyline(PackedVector2Array([bolt[3],Vector2(1221,313),Vector2(1235,362)]),Color(.78,.88,.87,float(state.strike)*.55),2,false)
		canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_rect(Rect2(Vector2.ZERO,REFERENCE),Color(.42,.56,.58,float(state.strike)*(.05 if state.reduced else .17)))
	_fire(canvas,Vector2(1152,491),flame,state)
	_rain(canvas,state)
	_sprite(canvas,LANDMARKS,BARRIER_REGION,Vector2(92,610),171,state,Color("839b91"))

static func _fire(canvas: CanvasItem, at: Vector2, strength: float, state: Dictionary) -> void:
	if strength<=0: return
	_space(canvas,state,at)
	var clock:=float(state.time)
	for index in (4 if state.reduced else 8):
		var cluster:=floori(index/3.0)
		var x:=index%3*5-8+cluster*4
		var y:=index%3*2-cluster*13
		var height: float=(9+sin(clock*5+index*2.1)*4+index%3*3)*strength
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(x-3,y+2),Vector2(x-2,y-height*.4),Vector2(x+2+sin(clock*4+index)*2,y-height),Vector2(x+4,y-height*.35),Vector2(x+5,y+2)]),Color(.62,.36,.16,strength))
		canvas.draw_rect(Rect2(x,y-height*.31,2,height*.31+2),Color(.86,.64,.34,strength))
	for index in int(state.smoke_count):
		var age:=fposmod(clock*.23+index/float(state.smoke_count),1)
		var drift:=age*46+sin(age*4+index)*3
		canvas.draw_circle(Vector2(drift,-10-age*118),5+age*14,Color(.16,.21,.20,(1-age)*strength*.38),true,-1,false)
	if not state.reduced:
		for index in 6:
			var age:=fposmod(clock*.51+index*.17,1)
			canvas.draw_rect(Rect2(5+age*32,-age*64,2,2),Color(.84,.52,.23,(1-age)*strength*.65))

static func _rain(canvas: CanvasItem, state: Dictionary) -> void:
	_space(canvas,state)
	for index in int(state.rain_count):
		var depth:=.3+(index%7)/10.0
		var x:=fposmod(index*173.19+float(state.time)*128*depth,1550)-55
		var y:=fposmod(index*97.03+float(state.time)*510*depth,545)+68
		# Near drops stop on the metal roof rather than crossing the shelter.
		if x>190 and x<835 and y>310 and y<588: continue
		canvas.draw_line(Vector2(x,y),Vector2(x-4-depth*5,y-9-depth*9),Color(.57,.69,.70,.12+depth*.14),1,false)
	for index in (5 if state.reduced else 13):
		var age:=fposmod(float(state.time)*1.5+index*.37,1)
		var x:=fposmod(index*217.7,1400)
		if x>185 and x<835: continue
		canvas.draw_line(Vector2(x-3*age,591),Vector2(x+3*age,591),Color(.61,.74,.73,(1-age)*.32),1,false)

static func _supply(canvas: CanvasItem, _context: Dictionary, crew: Array[String], state: Dictionary) -> void:
	_sprite(canvas,DEPOT,Rect2(65,12,2008,650),Vector2(1011,587),492,state)
	_tree(canvas,CONIFER,"conifer",Vector2(1320,589),242,state,Color("8b9980"),.004)
	_sprite(canvas,LANDMARKS,LOCKER_REGION,Vector2(1093,587),122,state)
	# An old roll shutter reveals the existing storage art, slat by slat.
	_space(canvas,state,Vector2(1093,587))
	var opening: float=state.shutter
	var shutter_height: float=123*(1-opening)
	if shutter_height>.3:
		_metal(canvas,Rect2(-44,-127,95,shutter_height),Color("616d61"))
		for index in ceili(shutter_height/7):
			canvas.draw_line(Vector2(-44,-126+index*7),Vector2(51,-126+index*7),Color("283b33"),1,false)
		canvas.draw_line(Vector2(-44,-127+shutter_height),Vector2(51,-127+shutter_height),EDGE,3,false)
	_metal(canvas,Rect2(-50,-135,108,8),Color("8c927b"))
	_generator(canvas,Vector2(783,587),state)
	_truck(canvas,Vector2(376,587),state,crew)
	var work:=1.0-smoothstep(.52,.75,float(state.progress))
	var pose:=PoseArt.neutral()
	pose.hip=Vector2(-4,-17)
	pose.shoulder=Vector2(5,-33)
	pose.feet=[Vector2(-13,-3),Vector2(13,-3)]
	pose.hands=[Vector2(14,-20),Vector2(20,-18+sin(float(state.time)*6.3)*work*2)]
	pose.head_shift=Vector2(1,2)
	pose.head_tilt=.08
	pose.prop="wrench"
	if work<.4: pose=PoseArt.sample("shoulder_roll",smoothstep(.68,.98,float(state.progress)),0,Vector2(24,-13),crew[0])
	_worker(canvas,crew[0],Vector2(720,587),state,"guard",.5,1,pose)
	for index in range(1,crew.size()):
		var kind: String="canteen_drink" if index==1 else "route_note" if index==2 else "strap_check"
		_worker(canvas,crew[index],Vector2(908+(index-1)*76,587),state,kind,clampf(float(state.progress)*.83+.03,0,1),-1 if index==1 else 1)
	_space(canvas,state,Vector2(876,587))
	canvas.draw_rect(Rect2(-8,-37,18,37),Color("25332b"))
	_metal(canvas,Rect2(-14,-39,26,3),Color("8b907a"))
	for index in 3: canvas.draw_line(Vector2(-8,-30+index*9),Vector2(10,-30+index*9),Color("5f6d56"),1,false)
	_sprite(canvas,LANDMARKS,BARRIER_REGION,Vector2(160,611),176,state,Color("a5ab92"))

static func _generator(canvas: CanvasItem, at: Vector2, state: Dictionary) -> void:
	_space(canvas,state,at,1.5)
	var power: float=state.power
	_metal(canvas,Rect2(-37,-45,73,41),Color("727f66"))
	_metal(canvas,Rect2(22,-60,5,14),Color("68715e"))
	_metal(canvas,Rect2(-41,-5,85,5),Color("747c62"))
	for x in [-30,-24,-18,-12,-6]:
		canvas.draw_rect(Rect2(x,-35,3,20),INK)
		canvas.draw_line(Vector2(x,-15),Vector2(x+2,-15),EDGE,1,false)
	canvas.draw_rect(Rect2(3,-31,25,17),Color("1d3028"))
	var rotation: float=float(state.time)*5.5*power
	_space(canvas,state,at+Vector2(21,-33),1.5,rotation)
	for index in 4:
		var direction:=Vector2.from_angle(index*PI*.5)
		canvas.draw_line(direction*2,direction*7,Color("a3a88b"),2,false)
	_space(canvas,state,at,1.5)
	canvas.draw_circle(Vector2(14,-22),2,Color("687058"),true,-1,false)
	canvas.draw_rect(Rect2(29,-38,3,3),Color(.84,.65,.25,.15+power*.8))
	canvas.draw_line(Vector2(32,-7),Vector2(55,-2),Color("182e26"),3,false)
	if power>.1 and not state.reduced:
		for index in 3:
			var age:=fposmod(float(state.time)*.46+index*.33,1)
			canvas.draw_rect(Rect2(24+age*9,-62-age*18,3+age*3,2+age*2),Color(.41,.45,.38,(1-age)*power*.24))

static func _foreground(canvas: CanvasItem, state: Dictionary) -> void:
	_space(canvas,state,Vector2(0,0))
	canvas.draw_texture_rect_region(VERGE,Rect2(-120,620,1700,321),Rect2(0,497,1672,316),Color("505e52"))
	canvas.draw_rect(Rect2(-50,680,1540,220),Color(.01,.025,.025,.36))
	# A small near post crosses the lower corner; no scenery obscures subtitles.
	canvas.draw_rect(Rect2(1308,550,8,103),Color("263b35"))
	canvas.draw_rect(Rect2(1306,546,12,8),Color("7d8873"))
	canvas.draw_line(Vector2(1309,551),Vector2(1309,647),Color("7b8067"),1,false)
