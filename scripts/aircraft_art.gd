extends RefCounted
## Immutable painted hulls with native propulsion, moving bays and weapons.
const Quads := preload("res://scripts/canvas_quads.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const Surface := preload("res://scripts/station_surface_art.gd")
const STEEL := Color("737564")
const DARK := Color("182523")
const RUST := Color("ae8359")

static func reduced(machine: Node2D) -> bool:
	if not is_instance_valid(machine.game): return false
	var weather = machine.game.get("weather")
	return is_instance_valid(weather) and bool(weather.get("reduced_effects"))

static func local_socket(machine: Node2D, source: Vector2) -> Vector2:
	var region: Rect2 = AircraftArtCatalog.REGIONS[machine.kind]
	return (source-region.get_center())*float(machine.profile.body_size.x)/region.size.x

static func body(machine: Node2D, node: Node2D) -> void:
	var size: Vector2 = machine.profile.body_size
	var clock: float = machine.visual_age()
	if machine.chassis_atlas != null:
		node.draw_texture_rect_region(machine.chassis_atlas,Rect2(-size*0.5,size),AircraftArtCatalog.REGIONS[machine.kind])
	else:
		# Missing optional art remains a readable aircraft, never a ground chassis.
		node.draw_colored_polygon(PackedVector2Array([Vector2(-size.x*.5,0),Vector2(-size.x*.28,-size.y*.27),Vector2(size.x*.4,-size.y*.27),Vector2(size.x*.5,-size.y*.5),Vector2(size.x*.48,size.y*.24),Vector2(-size.x*.26,size.y*.28)]),STEEL)
	var lamp := Vector2(-size.x*.30,-size.y*.05)
	Quads.rect(node,Rect2(lamp,Vector2(2,1)),Color("f6bd76") if fposmod(clock+machine.formation_phase,1.6)<.18 else Color("7d4e34"))
	if machine.kind in ["bomber","dive_bomber"]:
		var opening := clampf(machine.windup/float(machine.profile.windup),0,1) if machine.windup>0 else (1.0 if machine.burst_remaining>0 else 0.0)
		var bay := Vector2(-size.x*.08,size.y*.34)
		Quads.rect(node,Rect2(bay-Vector2(10,2),Vector2(20,5)),DARK)
		for side in [-1.0,1.0]:
			var hinge := bay+Vector2(side*10,0)
			node.draw_line(hinge,hinge+Vector2(-side*9*(1-opening),opening*8),STEEL,2)
		if opening>.15:
			node.draw_line(bay-Vector2(0,1),bay+Vector2(0,5),RUST,4)
	if machine.kind=="pulse_fighter":
		var charge := clampf(machine.windup/float(machine.profile.windup),0,1)
		for coil in 4:
			Quads.rect(node,Rect2(size.x*.22+coil*3,-4,2,6),RUST.lightened(charge*.35) if charge>.1 else RUST.darkened(.45))
	if machine.elite:
		for stripe in 3: Quads.rect(node,Rect2(stripe*4-6,-size.y*.20,2,5),Art.AMBER)
	if machine.hp<machine.max_hp*.45 and not reduced(machine):
		for index in 3:
			var cycle := fposmod(clock*1.5+index*.31,1.0)
			PixelArt.puff(node,Vector2(size.x*.23+cycle*18,-size.y*.08-cycle*12),1+cycle*4,Color(.23,.25,.23,(1-cycle)*.6),index,false)

static func propulsion(machine: Node2D, node: Node2D) -> void:
	var size: Vector2 = machine.profile.body_size
	var clock: float = machine.visual_age()
	var family: String = machine.profile.propulsion
	var points := AircraftArtCatalog.engine_points(machine.kind,size.x)
	for index in points.size():
		var point: Vector2 = points[index]
		var phase := clock*(37.0 if family=="propeller" else 44.0)+index*1.7
		if family in ["rotor","tiltrotor","vtol"]:
			var span := clampf(size.x*(.30 if machine.kind=="gunship" else .23),11,29)
			if machine.kind=="sky_fortress": span=15
			var tilt := clampf(-machine.flight_velocity.x*.0014,-.15,.15) if family=="tiltrotor" else clampf(-machine.flight_velocity.x*.00045,-.06,.06)
			var axis := Vector2(cos(tilt),sin(tilt))
			var rim := PackedVector2Array()
			if not reduced(machine):
				for step in 17:
					var angle := TAU*step/16.0
					rim.append(point+axis*cos(angle)*span+Vector2(0,sin(angle)*1.6))
				node.draw_polyline(rim,Color(.70,.69,.56,.19),1)
			var blade := axis*cos(phase)*span+Vector2(0,sin(phase)*1.8)
			node.draw_line(point-blade,point+blade,DARK,3)
			node.draw_line(point-blade+Vector2(0,-1),point+blade+Vector2(0,-1),STEEL,1)
			node.draw_line(point+Vector2(0,1),point+Vector2(0,3),RUST,2)
		elif family in ["propeller","airship"]:
			var span := clampf(size.y*.44,9,21) if family=="propeller" else 9.0
			var blade := Vector2(sin(phase)*2.0,cos(phase)*span)
			if not reduced(machine):
				var disc := PackedVector2Array()
				for step in 17:
					var angle := TAU*step/16.0
					disc.append(point+Vector2(cos(angle)*2.2,sin(angle)*span))
				node.draw_polyline(disc,Color(.68,.69,.60,.17),1)
			node.draw_line(point-blade,point+blade,DARK,3)
			node.draw_line(point-blade,point+blade,STEEL,1)
			node.draw_circle(point,2,RUST)
		else:
			var thrust := clampf(machine.flight_velocity.length()/float(machine.profile.speed),.18,1.0)
			var length := 5+thrust*8+sin(clock*41+index)*1.5
			node.draw_colored_polygon(PackedVector2Array([point+Vector2(0,-2),point+Vector2(length,0),point+Vector2(0,2)]),Color("d78e50"))
			node.draw_line(point,point+Vector2(length*.60,0),Color("f5d7a0"),1)
	if machine.kind=="gunship":
		var tail := local_socket(machine,Vector2(721,211))
		var blade := Vector2.from_angle(clock*41)*7
		node.draw_line(tail-blade,tail+blade,DARK,3)
		node.draw_line(tail-blade,tail+blade,STEEL,1)

static func weapon(machine: Node2D, node: Node2D) -> void:
	var flavor: String = machine.profile.flavor
	var recoil: float = machine.weapon_recoil
	if flavor=="bomb":
		Quads.rect(node,Rect2(-10,-3,20,5),DARK)
		if machine.windup>0 or machine.burst_remaining>0:
			node.draw_texture_rect(Surface._texture(Vector2i(8,12),STEEL,3),Rect2(-3,1,6,9),false)
			Quads.rect(node,Rect2(-3,7,6,2),RUST)
	else:
		var heavy: bool = machine.kind in ["sky_fortress","heavy_zeppelin"]
		var width := 10.0 if heavy else 6.0
		Quads.rect(node,Rect2(-21+recoil,-width*.5,24,width),DARK)
		node.draw_texture_rect(Surface._texture(Vector2i(28,10),STEEL,3),Rect2(-20+recoil,-width*.5+1,20,width-2),false)
		node.draw_line(Vector2(-19+recoil,-width*.5+1),Vector2(-2+recoil,-width*.5+1),Color("b0a585"),1)
		if flavor in ["rocket","arc"]:
			for band in 3: Quads.rect(node,Rect2(-17+band*5+recoil,-width*.5,2,width),RUST)
		node.draw_circle(Vector2(3,0),5,DARK)
		node.draw_texture_rect(Surface._texture(Vector2i(8,8),Color("615e50"),2),Rect2(0,-3,6,6),false)
		Quads.rect(node,Rect2(1,-2,2,1),Color("bb9b68"))
	if machine.windup>0:
		var charge := clampf(machine.windup/float(machine.profile.windup),0,1)
		var tip := Vector2(0,7) if flavor=="bomb" else Vector2(-24,0)
		node.draw_arc(tip,5+charge*3,-PI*.5,-PI*.5+TAU*charge,12,Color("f5aa67"),1)
		node.draw_circle(tip,1+charge,Color("ffd09a"))
	if flavor!="bomb":
		var heavy: bool=machine.kind in ["sky_fortress","heavy_zeppelin"]
		# The recoil-adjusted mouth is also AirMachine.muzzle_global()'s actual
		# launch point. Keep bomb release unflashed and the arc family cold.
		WeaponEffectArt.muzzle(node,Vector2(-24+recoil,0),machine.muzzle_flash,.22 if heavy else .10,-1,.72 if heavy else .50,machine.attack_count,reduced(machine),flavor=="arc")
