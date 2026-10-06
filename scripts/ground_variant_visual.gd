class_name GroundVariantVisual
extends Node2D
const Quads := preload("res://scripts/canvas_quads.gd")
## Native pixel equipment layered over the original industrial chassis artwork.
## Separate shields, tools and gun assemblies follow body recoil and locomotion.
var machine
const INK := Color("171d1c")
const STEEL := Color("686b5e")
const EDGE := Color("a2a28a")
const RUST := Color("8b694b")
const RED := Color("ee7855")
const MechanismArt := preload("res://scripts/machine_surface_details.gd")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2

func plate(rect: Rect2, tint: Color = STEEL) -> void:
	plate_on(self,rect,tint)

func plate_on(part: Node2D, rect: Rect2, tint: Color = STEEL) -> void:
	var a := rect.position.round()
	var b := rect.end.round()
	var light := tint.lerp(EDGE,0.58)
	# Cut corners, a narrow lit bevel and a shaded return give the accessories
	# the same metal thickness as the painted chassis, within their old bounds.
	part.draw_colored_polygon(PackedVector2Array([a+Vector2(2,0),Vector2(b.x-2,a.y),Vector2(b.x,a.y+2),b-Vector2(0,2),b-Vector2(2,0),Vector2(a.x+2,b.y),Vector2(a.x,b.y-2),a+Vector2(0,2)]),INK)
	MechanismArt.face(part,Rect2(a+Vector2(2,2),b-a-Vector2(4,4)),"steel",3)
	Quads.rect(part,Rect2(a+Vector2(2,2),b-a-Vector2(4,4)),Color(tint,0.14))
	Quads.rect(part,Rect2(a+Vector2(3,3),Vector2(b.x-a.x-6,maxf(1,floorf(rect.size.y*0.24)))),tint.lerp(EDGE,0.17))
	part.draw_line(a+Vector2(3,1),Vector2(b.x-3,a.y+1),light,1)
	part.draw_line(a+Vector2(1,3),Vector2(a.x+1,b.y-3),tint.lerp(EDGE,0.30),1)
	part.draw_line(Vector2(b.x-3,a.y+3),b-Vector2(3,3),tint.darkened(0.43),2)
	part.draw_line(Vector2(a.x+3,b.y-2),b-Vector2(3,2),tint.darkened(0.52),1)
	if rect.size.y>=13:
		var seam_y := roundf(a.y+rect.size.y*0.62)
		part.draw_line(Vector2(a.x+4,seam_y),Vector2(b.x-4,seam_y),tint.darkened(0.32),1)
		part.draw_line(Vector2(a.x+4,seam_y+1),Vector2(b.x-6,seam_y+1),tint.lerp(EDGE,0.13),1)
	# Sparse edge chips stay attached to the construction instead of spreading
	# random colored specks across the plate face.
	for index in maxi(1,int(rect.size.x/11)):
		var x := a.x+5+index*9
		Quads.rect(part,Rect2(x,a.y+2,2,1),RUST.darkened(0.12))
		Quads.rect(part,Rect2(x+2,b.y-4,2,1),tint.darkened(0.34))
	for at in [a+Vector2(3,3),Vector2(b.x-5,a.y+3),b-Vector2(5,5),Vector2(a.x+3,b.y-5)]:
		Quads.rect(part,Rect2(at,Vector2(2,2)),INK)
		Quads.rect(part,Rect2(at,Vector2.ONE),light)

func _rod_on(part: Node2D, start: Vector2, end: Vector2, width: float, tint: Color = STEEL) -> void:
	var normal := (end-start).normalized().orthogonal()
	if normal.y>0: normal = -normal
	part.draw_line(start,end,INK,width)
	part.draw_line(start,end,tint.darkened(0.16),width-2)
	part.draw_line(start+normal,end+normal,tint.lerp(EDGE,0.58),1)
	part.draw_line(start-normal,end-normal,tint.darkened(0.46),1)

func _joint_on(part: Node2D, at: Vector2) -> void:
	var center := at.round()
	Quads.rect(part,Rect2(center-Vector2(3,2),Vector2(6,4)),INK)
	Quads.rect(part,Rect2(center-Vector2(2,3),Vector2(4,6)),INK)
	Quads.rect(part,Rect2(center-Vector2(2,2),Vector2(4,4)),RUST.darkened(0.20))
	part.draw_line(center-Vector2(2,2),center+Vector2(1,-2),EDGE,1)
	Quads.rect(part,Rect2(center-Vector2.ONE,Vector2(2,2)),INK)
	Quads.rect(part,Rect2(center-Vector2.ONE,Vector2.ONE),STEEL)

func _slot_on(part: Node2D, rect: Rect2, tint: Color) -> void:
	Quads.rect(part,rect,INK)
	Quads.rect(part,Rect2(rect.position+Vector2(1,1),Vector2(rect.size.x-2,maxf(1,rect.size.y-2))),tint.darkened(0.24))
	part.draw_line(rect.position+Vector2(2,1),Vector2(rect.end.x-2,rect.position.y+1),tint,1)

func piston(start: Vector2, end: Vector2) -> void:
	_rod_on(self,start,end,6)
	_rod_on(self,start,start.lerp(end,0.48),6,RUST)
	_joint_on(self,start)

func armor_face(points: PackedVector2Array) -> void:
	MechanismArt.polygon(self,points,"dark",6)
	var outline:=points.duplicate()
	outline.append(points[0])
	draw_polyline(outline,INK,1,false)
	draw_line(points[0]+Vector2(1,1),points[1]+Vector2(-1,1),EDGE.darkened(.15),1)
	for at in [points[0]+Vector2(3,4),points[-2]+Vector2(-3,-4)]:
		Quads.rect(self,Rect2(at-Vector2.ONE,Vector2(3,3)),INK)
		Quads.rect(self,Rect2(at-Vector2.ONE,Vector2.ONE),EDGE)

func _draw() -> void:
	if not is_instance_valid(machine) or not is_instance_valid(machine.abilities):
		return
	var ability: GroundMachineAbilities = machine.abilities
	match machine.kind:
		"shield_guard":
			var open := snappedf(ability.shield_open,0.2)
			var recoil := sin(clampf(ability.shield_flash/0.18,0,1)*PI)*3
			var left := Vector2(-43-recoil,-25-open*11)
			var right := Vector2(-43-recoil,2+open*12)
			piston(Vector2(-22,-7),left+Vector2(11,16))
			piston(Vector2(-21,11),right+Vector2(11,7))
			# Split angled mantlets make this chassis read as a shield carrier.
			for panel in [left,right]:
				armor_face(PackedVector2Array([panel+Vector2(-3,0),panel+Vector2(14,0),panel+Vector2(16,5),panel+Vector2(15,22),panel+Vector2(-4,24),panel+Vector2(-7,18),panel+Vector2(-7,7)]))
				_rod_on(self,panel+Vector2(-4,5),panel+Vector2(-4,18),3,STEEL)
				if ability.shield_flash>0: draw_line(panel+Vector2(-6,7),panel+Vector2(-6,18),Color("dcb977"),2)
			for y in [-18,-8,9,19]:
				_slot_on(self,Rect2(-41-recoil,y+(open*(-11 if y<0 else 12)),10,2),RUST)
			_rod_on(self,Vector2(-30,-19),Vector2(-18,-10),5,RUST)
			_slot_on(self,Rect2(-29,-17,8,5),Color("d6b967") if ability.shield_closed() else Color("914939"))
			if ability.shield_closed():
				for y in range(-20,24,7): Quads.rect(self,Rect2(-51-recoil,y,1,2),Color(1.0,0.51,0.23,0.35+ability.shield_flash*2))
		"lancer":
			var repair_ready := 1.0-ability.rush_warning/GroundMachineAbilities.RUSH_WARNING if ability.rush_warning>0 else 0.0
			plate(Rect2(15,-24,17,15),Color("534e3e"))
			_slot_on(self,Rect2(18,-20,10,3),RED if ability.rush_warning>0 or ability.rush_time>0 else Color("8d5942"))
			if ability.rush_warning>0: Art.bar(self,Rect2(-24,-32,46,3),repair_ready,RED)
		"sniper":
			_rod_on(self,Vector2(15,-17),Vector2(18,-43),4,STEEL.darkened(0.2))
			draw_line(Vector2(18,-43),Vector2(30,-43),STEEL,2)
			draw_line(Vector2(18,-44),Vector2(26,-44),EDGE,1)
			Quads.rect(self,Rect2(28,-45,4,4),RED)
			Quads.rect(self,Rect2(28,-45,2,1),Color("ffbd8c"))
		"demolisher":
			plate(Rect2(13,-28,22,24),Color("414947"))
			for y in [-23,-17,-11]: _slot_on(self,Rect2(17,y,13,3),RED.darkened(0.4))
		"repair_crawler":
			var reach := sin(machine.age*2.0)*3.0
			var elbow := Vector2(29,-28+reach)
			var tip := Vector2(46,-7+reach)
			_rod_on(self,Vector2(10,-14),elbow,7)
			_rod_on(self,elbow,tip,6)
			_joint_on(self,elbow)
			# Exposed cable spool and folded supports replace the generic bare back.
			MechanismArt.wheel(self,Vector2(-23,-15),9,machine.gait*.12)
			draw_polyline(PackedVector2Array([Vector2(-24,-8),Vector2(-18,-3),Vector2(5,-4),Vector2(12,-13),elbow+Vector2(0,3),tip]),INK,3,false)
			draw_polyline(PackedVector2Array([Vector2(-24,-8),Vector2(-18,-3),Vector2(5,-4),Vector2(12,-13),elbow+Vector2(0,3),tip]),Color("716b50"),1,false)
			plate(Rect2(-12,-31,25,16),Color("566057"))
			_rod_on(self,Vector2(-8,-32),Vector2(-8,-36),3)
			_rod_on(self,Vector2(-8,-36),Vector2(7,-36),3)
			_rod_on(self,Vector2(7,-36),Vector2(7,-32),3)
			for x in [-8,-1,6]: _slot_on(self,Rect2(x,-27,3,7),Color("d0b573") if ability.repair_remaining>0 else Color("434a43"))
			Quads.rect(self,Rect2(tip-Vector2(2,4),Vector2(7,9)),INK)
			Quads.rect(self,Rect2(tip+Vector2(-1,-3),Vector2(5,2)),STEEL)
			Quads.rect(self,Rect2(tip,Vector2(5,3)),Color("8cc0b1"))
			Quads.rect(self,Rect2(tip+Vector2(1,1),Vector2(3,1)),Color("c6d7b2"))
			if ability.repair_flash>0:
				var endpoint := to_local(ability.repair_endpoint)
				var middle := tip.lerp(endpoint,0.5)+Vector2(0,sin(machine.age*70)*3)
				draw_polyline(PackedVector2Array([tip,middle,endpoint]),Color(0.64,0.84,0.72,ability.repair_flash*2.8),2)
				Quads.rect(self,Rect2(endpoint-Vector2(3,3),Vector2(6,6)),Color("e1d9a0"))
		"bastion":
			var vent := 9.0 if ability.vent_time>0 else 0.0
			for side in [-1,1]:
				armor_face(PackedVector2Array([Vector2(side*28,-9),Vector2(side*44,-4),Vector2(side*46,16),Vector2(side*37,25),Vector2(side*27,20)]))
				_rod_on(self,Vector2(side*32,0),Vector2(side*37,16),5,STEEL)
			piston(Vector2(-23,-13),Vector2(-23,-25-vent))
			piston(Vector2(22,-12),Vector2(22,-23-vent))
			plate(Rect2(-39,-30-vent,28,14),Color("5c6660"))
			plate(Rect2(8,-27-vent,29,13),Color("5c6660"))
			plate(Rect2(20,-7,21,31),Color("4b524e"))
			for y in [0,7,14]: _slot_on(self,Rect2(23,y,15,3),Color("d79854"))
			for i in 5: Quads.rect(self,Rect2(-6+i*4,-20,2,10),RED if ability.vent_time>0 else Color("263330"))
			if ability.vent_time>0:
				for i in 4:
					var rise := fposmod(machine.age*18+i*7,25)
					Quads.rect(self,Rect2(-9+i*6,-28-rise,4,5),Color(0.58,0.59,0.49,(1-rise/25)*0.30))


static func has_special_weapon(kind: String) -> bool:
	return kind in ["lancer","sniper","demolisher","bastion"]

static func weapon_tip(owner_machine: SiegeMachine) -> Vector2:
	match owner_machine.kind:
		"lancer":
			var extension := 10.0 if is_instance_valid(owner_machine.abilities) and owner_machine.abilities.rush_time>0 else 0.0
			return Vector2(-61-extension,0)
		"sniper": return Vector2(-75,0)
		"bastion": return Vector2(-61,0)
		"demolisher":
			var charge := clampf(owner_machine.windup/float(owner_machine.profile.windup),0,1)
			return Vector2(-61+roundf(charge*10),0)
	return Vector2(-35,0)

func draw_weapon(part: Node2D) -> void:
	# All weapon geometry is authored in the actual aiming/recoil node. The same
	# muzzle is used by the laser, charge light, flash and world-space tracer.
	# Chassis-only shields, antennae and vent doors stay in the body draw above.
	var tip: Vector2 = machine.weapon_muzzle()
	match machine.kind:
		"lancer":
			_rod_on(part,Vector2(5,0),tip+Vector2(13,0),10)
			plate_on(part,Rect2(-29,-8,30,17),RUST)
			for x in [-25,-19,-13]:
				Quads.rect(part,Rect2(x,-6,2,12),RUST.darkened(0.5))
				Quads.rect(part,Rect2(x,-6,1,11),Color("b89b6b"))
			part.draw_colored_polygon(PackedVector2Array([tip+Vector2(20,-9),tip,tip+Vector2(20,9)]),INK)
			part.draw_colored_polygon(PackedVector2Array([tip+Vector2(18,-5),tip+Vector2(4,0),tip+Vector2(18,5)]),EDGE)
			part.draw_colored_polygon(PackedVector2Array([tip+Vector2(18,0),tip+Vector2(4,0),tip+Vector2(18,5)]),STEEL.darkened(0.16))
			part.draw_line(tip+Vector2(8,-1),tip+Vector2(17,-4),Color("c4b999"),1)
			for x in [-45,-39,-33]: Quads.rect(part,Rect2(x,-3,2,2),RUST)
		"sniper":
			plate_on(part,Rect2(-21,-9,34,19),Color("48534c"))
			_rod_on(part,Vector2(-19,0),tip,8)
			for x in [-66,-58,-50,-42]:
				Quads.rect(part,Rect2(x,-4,3,8),INK)
				Quads.rect(part,Rect2(x,-3,2,5),RUST.darkened(0.1))
				Quads.rect(part,Rect2(x,-3,2,1),EDGE)
			plate_on(part,Rect2(-23,-17,21,9),Color("444f4e"))
			_slot_on(part,Rect2(-23,-15,3,4),RED)
			Quads.rect(part,Rect2(tip+Vector2(-1,-5),Vector2(5,10)),INK)
			Quads.rect(part,Rect2(tip+Vector2(0,-2),Vector2(2,4)),RED.darkened(0.35))
			_draw_target_laser(part,tip)
		"demolisher":
			_rod_on(part,Vector2(8,0),tip+Vector2(17,0),12)
			plate_on(part,Rect2(-17,-9,22,18),RUST)
			plate_on(part,Rect2(tip+Vector2(9,-16),Vector2(23,32)),Color("716956"))
			for y in [-11,-3,5]: _slot_on(part,Rect2(tip+Vector2(11,y),Vector2(6,4)),RUST)
			part.draw_colored_polygon(PackedVector2Array([tip+Vector2(10,-8),tip,tip+Vector2(10,8)]),EDGE)
			part.draw_colored_polygon(PackedVector2Array([tip+Vector2(10,0),tip,tip+Vector2(10,8)]),STEEL.darkened(0.20))
			part.draw_line(tip+Vector2(2,-1),tip+Vector2(9,-6),Color("c4b999"),1)
			if is_instance_valid(machine.abilities) and machine.abilities.shock_flash>0:
				var flash: float = machine.abilities.shock_flash
				part.draw_arc(tip,12+(0.45-flash)*45,PI*0.5,PI*1.5,12,Color(0.91,0.62,0.30,flash),2)
		"bastion":
			plate_on(part,Rect2(-23,-14,34,28),Color("555e53"))
			var spin: float = machine.age*35.0
			for index in 3:
				var y := roundf(sin(spin+index*TAU/3.0)*6.0)
				_rod_on(part,Vector2(-19,y),tip+Vector2(1,y),6,STEEL.darkened(0.08))
				for x in [-46,-29]:
					Quads.rect(part,Rect2(x,y-2,2,4),RUST.darkened(0.14))
					Quads.rect(part,Rect2(x,y-2,2,1),EDGE)
			Quads.rect(part,Rect2(tip+Vector2(-2,-10),Vector2(6,21)),INK)
			Quads.rect(part,Rect2(tip+Vector2(-1,-8),Vector2(3,17)),STEEL.darkened(0.2))
			Quads.rect(part,Rect2(tip+Vector2(-1,-8),Vector2(3,1)),EDGE)
			Quads.rect(part,Rect2(tip+Vector2(1,-7),Vector2(1,15)),RUST.darkened(0.2))
			Quads.rect(part,Rect2(tip+Vector2(-2,-2),Vector2(3,4)),Color("e38b56"))
	_draw_weapon_flash(part,tip)

func _draw_target_laser(part: Node2D,tip: Vector2) -> void:
	var charge := maxf(machine.windup/float(machine.profile.windup),machine.worker_windup/machine.worker_windup_duration())
	if charge<=0 or not is_instance_valid(machine.target): return
	var destination: Vector2 = machine.worker_target.global_position-Vector2(0,23) if machine.worker_windup>0 and is_instance_valid(machine.worker_target) else machine.target_attack_point()
	var origin := part.to_global(tip)
	var query := PhysicsRayQueryParameters2D.create(origin,destination,1|2|8)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): destination = hit.position
	var end := part.to_local(destination)
	part.draw_line(tip,end,Color(0.96,0.24,0.12,0.2+clampf(charge,0,1)*0.45),1)
	Quads.rect(part,Rect2(end-Vector2(2,2),Vector2(4,4)),RED)

func _draw_weapon_flash(part: Node2D,tip: Vector2) -> void:
	if machine.muzzle_flash<=0: return
	if machine.kind in ["lancer","demolisher"]:
		for index in 5:
			var end := tip+Vector2(-11-3*(index%2),-9+index*4)
			part.draw_line(tip,end,Color("f4bd75"),2 if index==2 else 1)
		Quads.rect(part,Rect2(tip-Vector2(2,2),Vector2(4,4)),Color("ffead0"))
	else:
		part.draw_colored_polygon(PackedVector2Array([tip+Vector2(1,-4),tip+Vector2(-12,-9),tip+Vector2(-9,-2),tip+Vector2(-25,0),tip+Vector2(-10,3),tip+Vector2(-14,8),tip+Vector2(1,4)]),Color("fb8745"))
		part.draw_line(tip,tip+Vector2(-18,0),Color("ffe8b0"),3)
