extends RefCounted
## One authored hull; actual wheels, suspension, crew and weapon are articulated.
const HULL := preload("res://assets/vehicles/convoy_hull_v3.png")
const PARTS_PATH := "res://assets/vehicles/convoy_parts_v1.png"
const PART_REGIONS := {"wheel":Rect2(132,103,451,454),"mg":Rect2(652,221,843,295),"armor":Rect2(25,681,812,203),"cargo":Rect2(856,681,661,203)}
const SERVICE_ATLAS := preload("res://assets/vehicles/convoy_service_v3.png")
const SERVICE_REGIONS := {"wheel":Rect2(38,81,568,578),"rupture":Rect2(688,81,573,582),"flat":Rect2(40,740,672,398),"hub":Rect2(841,789,310,311)}
static var _parts_texture: Texture2D
const REGION := Rect2(24,131,1751,558)
const BODY := Rect2(-98,-70,196,62.46)
const WHEELS := [-65.0,-15.0,56.0]
const SERVICE_STUDS := [Vector2(0,-4),Vector2(3,2),Vector2(-3,2)]
const SERVICE_LIFT := 4.0
const FLAT_DROP := 6.0
const JACK_PUMP_RATE := 1.8
const CUTOUT := preload("res://shaders/actor_wet.gdshader")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")

static func parts_texture() -> Texture2D:
	if _parts_texture==null:
		if ResourceLoader.exists(PARTS_PATH): _parts_texture=load(PARTS_PATH)
		else: _parts_texture=ImageTexture.create_from_image(Image.load_from_file(PARTS_PATH))
	return _parts_texture

static func draw_running_gear(node: Node2D, vehicle: Node2D) -> void:
	if node.material==null:
		var cutoff:=ShaderMaterial.new()
		cutoff.shader=CUTOUT
		cutoff.set_shader_parameter("sprite_alpha_cutoff",.5)
		node.material=cutoff
	node.draw_rect(Rect2(-99,0,199,3),Color(0.02,0.03,0.025,0.35))
	node.draw_line(Vector2(-79,-13),Vector2(72,-13),Color("1c2727"),7,false)
	var service := repair_visual_state(vehicle)
	var pose:=body_pose(vehicle)
	for wheel_x in WHEELS:
		var center:=Vector2(wheel_x*vehicle.facing,-11)
		if wheel_x==WHEELS[0] and service.active: center=service.hub_position
		_draw_suspension(node,pose,vehicle.facing,wheel_x,center)
		if wheel_x==WHEELS[0] and service.active:
			if service.loose:
				_draw_service_hub(node,center)
				draw_service_wheel(node,service.wheel_position,service.wheel_rotation,service.flat,float(service.collapse))
			else:
				draw_service_wheel(node,center,0.0,service.flat,float(service.collapse))
			if service.step in ["tighten","lower"]:
				_draw_service_studs(node,center,int(service.bolts),int(service.bolts) if service.step=="tighten" else -1,vehicle.facing)
		else:
			draw_service_wheel(node,center,float(vehicle.wheel_phase),false)
	if service.active and service.step in ["fit","tighten","lower"]:
		# The removed rubber stays on the verge until service finishes. This is
		# a compact flattened tyre, distinct from the upright replacement wheel.
		var discarded := Vector2(WHEELS[0]*vehicle.facing-53*vehicle.facing,0)
		node.draw_set_transform(discarded,0,Vector2(vehicle.facing,1))
		node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(-13,-15.4,26,15.4),SERVICE_REGIONS.flat,Color("929687"))
		node.draw_line(Vector2(-12,0),Vector2(12,0),Color("182020"),1,false)
		node.draw_set_transform(Vector2.ZERO)

static func _draw_suspension(node: Node2D, pose: Transform2D, side: float, wheel_x: float, axle: Vector2) -> void:
	# The leaf ends belong to the sprung hull; the middle follows the actual
	# planted wheel (or raised service hub). Each axle uses one short polygon.
	var rear: Vector2=pose*Vector2((wheel_x-15)*side,-19)
	var front: Vector2=pose*Vector2((wheel_x+15)*side,-19)
	var spring:=PackedVector2Array([rear.round(),(axle+Vector2(-7*side,-6)).round(),(axle+Vector2(7*side,-6)).round(),front.round()])
	node.draw_polyline(spring,Color("182322"),4,false)
	node.draw_polyline(spring,Color("7d8064"),2,false)
	var attachment: Vector2=pose*Vector2((wheel_x-10)*side,-24)
	var end: Vector2=axle+Vector2(8*side,-5)
	node.draw_line(attachment.round(),end.round(),Color("232e2b"),4,false)
	node.draw_line(attachment.round(),end.round(),Color("aba17b"),2,false)
	node.draw_rect(Rect2(attachment.round()-Vector2.ONE,Vector2(2,2)),Color("d0b686"))

static func draw_service_wheel(node: Node2D, at: Vector2, spin: float, flat: bool, collapse: float=1.0) -> void:
	node.draw_set_transform(at,spin)
	if flat:
		# Preserve the authored round rim and upper tread; only the collapsed
		# rubber sidewall folds onto the road. No chassis/collider is displaced.
		collapse=clampf(collapse,0,1)
		var wheel: Rect2 = SERVICE_REGIONS.rupture
		var upper := Rect2(wheel.position,Vector2(wheel.size.x,wheel.size.y*.75))
		var lower := Rect2(wheel.position+Vector2(0,wheel.size.y*.75),Vector2(wheel.size.x,wheel.size.y*.25))
		if collapse<.65:
			node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(-12,-12,24,18),upper)
			node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(-12,6,24,6.0*(1-collapse)),lower)
			if collapse>.1:
				node.draw_colored_polygon(PackedVector2Array([Vector2(-12,5),Vector2(-13,8),Vector2(-13,12-FLAT_DROP*collapse),Vector2(13,12-FLAT_DROP*collapse),Vector2(13,8),Vector2(12,5)]),Color("222825"))
		else:
			var floor_y: float=11.0-FLAT_DROP*collapse
			if floor_y>5.0:
				node.draw_rect(Rect2(-13,4,26,floor_y-4),Color("252b26"))
			node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(-13,-10.4,26,15.4),SERVICE_REGIONS.flat)
	else:
		node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(-12,-12,24,24),SERVICE_REGIONS.wheel)
	node.draw_set_transform(Vector2.ZERO)

static func _draw_service_hub(node: Node2D, at: Vector2) -> void:
	# The exposed axle retains authored oxidised steel and a distinct rim hub.
	node.draw_texture_rect_region(SERVICE_ATLAS,Rect2(at-Vector2(6,6),Vector2(12,12)),SERVICE_REGIONS.hub)
	_draw_service_studs(node,at,0,-1)

static func _draw_service_studs(node: Node2D, at: Vector2, bolts: int, selected: int, facing: float=1.0) -> void:
	for index in SERVICE_STUDS.size():
		var point: Vector2 = at+SERVICE_STUDS[index]*Vector2(facing,1)
		node.draw_rect(Rect2(point-Vector2.ONE,Vector2(2,2)),Color("d0b57c") if index<bolts else Color("37433a"))
		if index==selected:
			node.draw_rect(Rect2(point-Vector2(2,2),Vector2(4,4)),Color("bea26b"),false,1,false)

static func repair_visual_state(vehicle: Node2D) -> Dictionary:
	# One description is shared by the running gear and service props. Every
	# coordinate is local cosmetic geometry; the authoritative rear axle stays
	# at WHEELS[0] and the existing service_point never changes.
	var state := journey_state(vehicle)
	var step := str(state.get("repair_step","none"))
	var active: bool = state.get("phase","")=="repair" and step in ["jack","remove","fit","tighten","lower"]
	var work := clampf(float(state.get("repair_work",0.0)),0,1)
	var side: float = vehicle.facing
	var mounted := Vector2(WHEELS[0]*side,-11)
	var offset: float = work if step=="remove" else 1.0-work if step=="fit" else 0.0
	var loose: bool = active and step in ["remove","fit"]
	var presentation:=vehicle.get_node_or_null("ConvoyPresentation")
	var collapse: float=presentation.tyre_collapse() if is_instance_valid(presentation) else 1.0
	var flat: bool=active and step in ["jack","remove"]
	var lift: float=work if step=="jack" else 1.0-work if step=="lower" else 1.0
	var rear_offset: float=(FLAT_DROP*collapse*(1-lift) if flat else 0.0)-SERVICE_LIFT*lift
	var hub:=mounted+Vector2(0,rear_offset if active else 0.0)
	# Slow near contact, clear the verge while carried, and land on the same
	# road plane at both endpoints. The spare has a full sidewall again.
	var handling: float=offset*offset*(3.0-2.0*offset)
	var station:=Vector2(mounted.x-36*side,-5 if flat else -12)
	var wheel:=hub.lerp(station,handling)-Vector2(0,sin(handling*PI)*2.0)
	var phase_time: float=presentation.service_clock(state) if is_instance_valid(presentation) and presentation.has_method("service_clock") else float(state.get("phase_time",0.0))
	return {"active":active,"step":step,"work":work,"phase_time":phase_time,"lift":lift,"loose":loose,"flat":flat,"collapse":collapse,"hub_position":hub,"station_position":station,"rear_body_offset":rear_offset if active else 0.0,"wheel_position":wheel,"wheel_rotation":offset*.18*side if loose and step=="fit" else 0.0,"bolts":clampi(int(state.get("repair_bolts",0)),0,3),"cursor":clampf(float(state.get("repair_cursor",0)),0,1),"working":int(state.get("repair_operator",0))>0 or bool(state.get("solo_assist",false))}

static func jack_grip(vehicle: Node2D, state: Dictionary) -> Vector2:
	var working: bool=bool(state.get("working",int(state.get("repair_operator",0))>0 or bool(state.get("solo_assist",false))))
	var lowering: bool=str(state.get("step",state.get("repair_step","")))=="lower"
	var pumping: float=sin(float(state.get("phase_time",0))*TAU*JACK_PUMP_RATE) if working and not lowering else 0.0
	return Vector2((WHEELS[0]-5)*vehicle.facing,-4+pumping*2.5)

static func service_tool_point(vehicle: Node2D, state: Dictionary) -> Vector2:
	var service: Dictionary=state if state.has("hub_position") else repair_visual_state(vehicle)
	if service.step in ["jack","lower"]: return jack_grip(vehicle,state)
	if service.step=="tighten":
		var bolt: int=mini(int(service.bolts),SERVICE_STUDS.size()-1)
		return service.hub_position+SERVICE_STUDS[bolt]*Vector2(vehicle.facing,1)
	return service.wheel_position

static func body_pose(vehicle: Node2D) -> Transform2D:
	var presentation:=vehicle.get_node_or_null("ConvoyPresentation")
	var pitch: float=float(presentation.body_pitch) if is_instance_valid(presentation) else 0.0
	var heave: float=float(presentation.body_heave) if is_instance_valid(presentation) else 0.0
	var service:=repair_visual_state(vehicle)
	if service.active:
		# Lift around the undamaged front contact. Gameplay and seat transforms
		# keep their fixed coordinates; only the painted chassis/leafs articulate.
		var service_pitch: float=-atan2(float(service.rear_body_offset),WHEELS[2]-WHEELS[0])
		pitch+=service_pitch
		heave-=sin(service_pitch)*WHEELS[2]
	return Transform2D(pitch*vehicle.facing,Vector2(0,vehicle.suspension+heave))

static func body_point(vehicle: Node2D, point: Vector2) -> Vector2:
	return body_pose(vehicle)*(point*Vector2(vehicle.facing,1))

static func draw_hull(node: Node2D, vehicle: Node2D) -> void:
	if node.material==null:
		var cutout_material:=ShaderMaterial.new()
		cutout_material.shader=CUTOUT
		cutout_material.set_shader_parameter("sprite_alpha_cutoff",0.5)
		node.material=cutout_material
	var pose:=body_pose(vehicle)
	node.draw_set_transform(pose.origin,pose.get_rotation(),Vector2(vehicle.facing,1))
	var tint:=Color("a6aaa0") if vehicle.destroyed else Color.WHITE
	if vehicle.hit_flash>0: tint=Color(1.3,1.1,0.9)
	node.draw_texture_rect_region(HULL,BODY,REGION,tint)
	var presentation=vehicle.get_node_or_null("ConvoyPresentation")
	# Window-facing seated driver is painted with the same character rig. Body
	# rendering masks boots/legs naturally behind the door, never behind glass.
	var driver=vehicle.driver_seat.occupant
	if is_instance_valid(driver):
		# Only the visible upper body belongs in the cab aperture.
		var head_texture:=preload("res://scripts/worker_identity_art.gd").head(str(driver.character_id))
		var torso_texture:=preload("res://scripts/worker_identity_art.gd").torso(str(driver.character_id))
		node.draw_texture_rect_region(torso_texture,Rect2(49,-42,18,7),Rect2(37,45,30,15))
		node.draw_texture_rect_region(head_texture,Rect2(47,-59,24,24),Rect2(34,24,32,36))
		node.draw_arc(Vector2(69,-39),3,-PI*.65,PI*.65,8,Color("1b2426"),1,false)
		# Cab sill covers lower portion of the occupant, respecting hull silhouette.
		node.draw_line(Vector2(47,-36),Vector2(74,-36),Color("b7aa82"),2,false)
	if is_instance_valid(presentation) and presentation.door_open>.015:
		_draw_door(node,float(presentation.door_open),tint)
	if vehicle.max_hp>vehicle.BASE_HP:
		node.draw_texture_rect_region(parts_texture(),Rect2(-91,-33,109,27.25),PART_REGIONS.armor)
	if vehicle.cargo_capacity>vehicle.BASE_CARGO:
		node.draw_texture_rect_region(parts_texture(),Rect2(-91,-56,53,16.28),PART_REGIONS.cargo)
	if vehicle.has_mg:
		var mount:=Vector2(-7,-76)
		if vehicle.has_method("gun_origin"):
			mount=(pose.affine_inverse()*node.to_local(vehicle.gun_origin()))*Vector2(vehicle.facing,1)
		# The sprung floor moves under the stabilized weapon/seat anchor. Its
		# visible support must reach the actual breech during a jack or blowout.
		node.draw_line(Vector2(-7,-33),mount,Color("1b2728"),7,false)
		node.draw_line(Vector2(-6,-33),mount+Vector2(1,0),Color("7d8a77"),3,false)
		node.draw_rect(Rect2(-38,-41,35,5),Color("38453d"))
		node.draw_line(Vector2(-38,-42),Vector2(-3,-42),Color("a19973"),2,false)
	var reduced: bool=WeaponEffectArt.reduced(vehicle.game)
	if absf(vehicle.velocity.x)>3 and not vehicle.destroyed and not reduced:
		for index in 5:
			var phase:=fposmod(vehicle.animation_time*0.8+float(index)*0.2,1.0)
			var smoke:=Vector2(39-phase*18,-63-phase*22)
			PixelArt.puff(node,smoke,2+phase*4,Color(0.25,0.28,0.26,(1-phase)*0.26),index,false)
	if vehicle.hp<vehicle.max_hp*0.35 and not reduced:
		for index in 7:
			var phase:=fposmod(vehicle.animation_time*0.55+float(index)/7,1)
			PixelArt.puff(node,Vector2(77-phase*15,-35-phase*42),2+phase*7,Color(0.11,0.13,0.12,(1-phase)*0.55),index,false)
	node.draw_set_transform(Vector2.ZERO)
	if is_instance_valid(driver):
		var marker:=body_point(vehicle,Vector2(60,-84))
		node.draw_rect(Rect2(marker+Vector2(-10,-12),Vector2(22,14)),Color("132126"))
		Art.text(node,marker+Vector2(-8,-1),"P%d"%driver.player_id,11,PartyConfig.player_color(driver.player_id))
		node.draw_colored_polygon(PackedVector2Array([marker+Vector2(-3,4),marker+Vector2(3,4),marker+Vector2(0,8)]),PartyConfig.player_color(driver.player_id))

static func journey_state(vehicle: Node2D) -> Dictionary:
	var state: Variant=vehicle.get("journey_state")
	return state if state is Dictionary else {}

static func _draw_door(node: Node2D, openness: float, tint: Color) -> void:
	var door:=Rect2(43,-55,25,30)
	var source:=Rect2(REGION.position+(door.position-BODY.position)*REGION.size/BODY.size,door.size*REGION.size/BODY.size)
	# Cover the closed painting with a recessed aperture; swing the original
	# immutable door pixels around its front hinge. Boots stay below the sill.
	node.draw_rect(door,Color("172220"))
	node.draw_rect(Rect2(door.position+Vector2(2,2),door.size-Vector2(4,4)),Color("29382e"))
	var swing: float=openness*openness*(3.0-2.0*openness)
	var width: float=door.size.x*lerpf(1.0,.22,sin(swing*PI*.5))
	var edge: float=door.end.x-width
	node.draw_texture_rect_region(HULL,Rect2(edge,door.position.y-2*swing,width,door.size.y),source,tint)
	# A visible hinge, handrail and folding foothold make boarding readable
	# without painting an extra whole truck or moving a collision/seat anchor.
	node.draw_rect(Rect2(door.end.x-1,door.position.y+3,2,4),Color("837f5e"))
	node.draw_rect(Rect2(door.end.x-1,door.end.y-7,2,4),Color("837f5e"))
	node.draw_line(Vector2(46,-30),Vector2(46,-21),Color("c0ad7d"),2,false)
	var step:=Rect2(44,-18,17,2+swing*3)
	node.draw_rect(step,Color("1b2727"))
	node.draw_line(step.position+Vector2(0,1),step.position+Vector2(step.size.x,1),Color("9d987b"),1,false)
	for index in 5:
		node.draw_rect(Rect2(step.position+Vector2(2+index*3,2),Vector2(1,1)),Color("4e594b"))
	node.draw_line(Vector2(door.end.x,door.position.y),Vector2(door.end.x,door.end.y),Color("ba995d"),1,false)
	node.draw_line(Vector2(edge,door.end.y),Vector2(edge+width,door.end.y),Color("111c21"),2,false)

static func draw_weapon(node: Node2D, vehicle: Node2D) -> void:
	if not vehicle.has_mg or vehicle.destroyed: return
	var origin:=node.to_local(vehicle.gun_origin())
	var side:=-1.0 if cos(vehicle.aim_angle)<0 else 1.0
	node.draw_set_transform(origin,vehicle.aim_angle,Vector2(1,side))
	node.draw_texture_rect_region(parts_texture(),Rect2(-17-vehicle.recoil,-6,64,22.4),PART_REGIONS.mg)
	var feed: float=vehicle.flash_tick%3
	for index in 4:
		var at:=Vector2(-12+index*3-feed,-1+index%2)
		node.draw_rect(Rect2(at.round(),Vector2(2,3)),Color("b69960"))
		node.draw_rect(Rect2((at+Vector2(0,2)).round(),Vector2(2,1)),Color("5e5944"))
	WeaponEffectArt.muzzle(node,Vector2(47-vehicle.recoil,0),vehicle.flash,0.075,1,0.7,vehicle.flash_tick,WeaponEffectArt.reduced(vehicle.game))
	node.draw_set_transform(Vector2.ZERO)
	var presentation:=vehicle.get_node_or_null("ConvoyPresentation")
	if is_instance_valid(presentation): presentation.draw_weapon_debris(node)
