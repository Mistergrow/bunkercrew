extends RefCounted
const Quads := preload("res://scripts/canvas_quads.gd")
## Painted vehicle hulls with independent native-pixel running gear and weapons.
## Rolling phase follows world travel, never a second replicated animation clock.
const Metal := preload("res://scripts/machine_surface_details.gd")
const Limbs := preload("res://scripts/machine_limb_art.gd")
const HULL_PATH := "res://assets/enemies/vehicle_hulls_v1.png"
const REGIONS := {"scout_car":Rect2(265,130,1055,330),"mortar_carrier":Rect2(103,556,1393,361),"battle_tank":Rect2(103,556,1393,361)}
const RECTS := {"scout_car":Rect2(-56,-25,112,35.03),"mortar_carrier":Rect2(-63,-20,126,32.65),"battle_tank":Rect2(-63,-20,126,32.65)}
const INK := Color("171f1c")
const EDGE := Color("aaa58b")
static var _hull_texture: Texture2D

static func is_vehicle(kind: String) -> bool:
	return EnemyCatalog.is_vehicle(kind)

static func hull_texture() -> Texture2D:
	if _hull_texture==null:
		if ResourceLoader.exists(HULL_PATH):
			_hull_texture=load(HULL_PATH)
		elif FileAccess.file_exists(HULL_PATH):
			# A new source asset can be reviewed before the editor imports it.
			_hull_texture=ImageTexture.create_from_image(Image.load_from_file(HULL_PATH))
	return _hull_texture

static func travel(machine: Node2D) -> float:
	return machine.position.x*(-float(machine.attack_direction))/maxf(.1,float(machine.visual_scale))

static func deployment(machine: Node2D) -> float:
	var threshold: float=machine.move_speed*(.30 if machine.moving else 1.0)
	return clampf(1.0-machine.locomotion_speed/maxf(1,threshold),0,1)

static func muzzle(kind: String) -> Vector2:
	return Vector2(-62 if kind=="battle_tank" else (-46 if kind=="mortar_carrier" else -39),0)

static func wheel_centers(kind: String) -> Array[Vector2]:
	if kind=="scout_car": return [Vector2(-26,-12),Vector2(36,-12)]
	return [Vector2(-43,-12),Vector2(-22,-12),Vector2(0,-12),Vector2(22,-12),Vector2(43,-12)]

static func contact(kind: String, index: int) -> Vector2:
	var x: float=[-26.0,36.0][posmod(index,2)] if kind=="scout_car" else [-44.0,44.0][posmod(index,2)]
	return Vector2(x,-3)

static func pose_parts(machine: Node2D) -> void:
	var mirror: float=-machine.attack_direction
	var size: float=machine.visual_scale
	var tracked: bool=machine.kind!="scout_car"
	var roll:=travel(machine)
	var speed:=clampf(machine.locomotion_speed/maxf(1,machine.move_speed),0,1)
	var compression:=sin(roll*.13)*(.70 if tracked else 1.05)*speed
	var settle:=deployment(machine)
	var kick: float=machine.weapon_recoil
	var motion_offset:=Vector2.ZERO
	var motion_roll:=0.0
	if is_instance_valid(machine.motion) and not machine.motion.pose.is_empty():
		motion_offset=Vector2(machine.motion.pose.offset)*.20
		motion_roll=float(machine.motion.pose.roll)*.18
	for part in [machine.body_part,machine.legs_part,machine.weapon_part]:
		part.scale=Vector2(mirror,1)*size
	machine.legs_part.position=Vector2.ZERO
	machine.legs_part.rotation=0
	machine.body_part.position=Vector2((motion_offset.x+kick*.13)*mirror,compression+motion_offset.y+(settle*1.4 if machine.kind=="mortar_carrier" else 0.0))*size-Vector2(0,machine.body_height)
	machine.body_part.rotation=(sin(roll*.08)*.014*speed+motion_roll)*mirror
	var pivot:=Vector2(8,-18) if tracked else Vector2(10,-21)
	var base: Vector2=machine.to_local(machine.body_part.to_global(pivot))
	var aim: Vector2=machine.target_attack_point()
	if machine.worker_windup>0 and is_instance_valid(machine.worker_target): aim=machine.worker_target.global_position-Vector2(0,23)
	if machine.muzzle_flash>0: aim=machine.to_global(machine.tracer_end)
	if is_instance_valid(machine.abilities) and machine.abilities.aim_locked: aim=machine.abilities.aim_point
	var local_aim:=machine.to_local(aim)
	var angle:=.12 if machine.kind=="mortar_carrier" else 0.0
	# Iterate from the visible mouth because its elevation changes the ballistic
	# launch point. The final transform also contains the barrel's single recoil.
	for unused in 7:
		var axis:=Vector2(-cos(angle)*mirror,-sin(angle))
		var origin:=base-axis*kick*size
		var mouth:=origin+axis*absf(muzzle(machine.kind).x)*size
		var direction:=local_aim-mouth
		if machine.kind=="mortar_carrier" and is_instance_valid(machine.abilities):
			var velocity: Vector2=machine.abilities.launch_velocity(machine.to_global(mouth),aim)
			direction=machine.to_local(machine.to_global(mouth)+velocity)-mouth
		var aimed:=wrapf(Vector2(direction.x*mirror,direction.y).angle()-PI,-PI,PI)
		angle=lerpf(.12,clampf(aimed,.20,1.35),settle) if machine.kind=="mortar_carrier" else clampf(aimed,-.40,.95)
	var recoil_axis:=Vector2(-cos(angle)*mirror,-sin(angle))
	machine.weapon_part.position=base-recoil_axis*kick*size
	machine.weapon_part.rotation=angle*mirror

static func _wheel(canvas: Node2D, at: Vector2, radius: float, phase: float, far: bool=false) -> void:
	canvas.draw_circle(at,radius,INK)
	canvas.draw_circle(at,radius-2,Color("303a32") if not far else Color("242d27"))
	for index in 12:
		var point:=at+Vector2.from_angle(phase+index*TAU/12.0)*(radius-1)
		Quads.rect(canvas,Rect2(point.round()-Vector2.ONE,Vector2(2,2)),Color("626554") if index%2==0 else Color("474c40"))
	Metal.disc(canvas,at,radius-4,"dark")
	for spoke in 4:
		var direction:=Vector2.from_angle(phase+spoke*PI*.5)
		canvas.draw_line((at+direction*2).round(),(at+direction*(radius-5)).round(),Color("96937c"),1,false)
	Quads.rect(canvas,Rect2(at-Vector2(2,2),Vector2(4,4)),INK)
	Quads.rect(canvas,Rect2(at-Vector2.ONE,Vector2(2,2)),EDGE)

static func draw_running_gear(machine: Node2D) -> void:
	var canvas: Node2D=machine.legs_part
	var tracked: bool=machine.kind!="scout_car"
	var distance:=travel(machine)
	if not tracked:
		# The far axle is drawn first; the near tires sit exactly in the painted
		# wheel arches. Their bottom edges stay on the ground under suspension.
		for center in wheel_centers(machine.kind):
			_wheel(canvas,center+Vector2(3,-3),10,distance/12,true)
			var spring: Vector2=canvas.to_local(machine.body_part.to_global(Vector2(center.x,6)))
			Limbs.piston(canvas,spring,center,false)
			_wheel(canvas,center,12,distance/12)
		return
	var belt:=PackedVector2Array([Vector2(-52,-25),Vector2(51,-25),Vector2(61,-17),Vector2(60,-8),Vector2(52,0),Vector2(-53,0),Vector2(-62,-8),Vector2(-62,-17)])
	canvas.draw_colored_polygon(belt,INK)
	Metal.polygon(canvas,PackedVector2Array([Vector2(-52,-22),Vector2(51,-22),Vector2(58,-15),Vector2(55,-7),Vector2(50,-3),Vector2(-51,-3),Vector2(-59,-10),Vector2(-59,-15)]),"dark",1)
	for center in wheel_centers(machine.kind): _wheel(canvas,center,9,distance/9)
	# Fixed link count and an absolute travel phase keep a stopped belt still.
	var phase:=fposmod(distance,6.0)
	for index in 18:
		for y in [-24,-2]:
			var x: float=-52+index*6+(phase if y==-24 else -phase)
			Quads.rect(canvas,Rect2(Vector2(x,y).round(),Vector2(4,2)),Color("7f806a"))
			Quads.rect(canvas,Rect2(Vector2(x,y+1).round(),Vector2(3,1)),Color("474e40"))
	for end in [-1,1]:
		for tooth in 5:
			var angle:=(-.5+tooth*.25)*PI
			var point:=Vector2(end*51,-12)+Vector2(cos(angle)*end,sin(angle))*11
			Quads.rect(canvas,Rect2(point.round(),Vector2(2,3)),Color("696f5c"))
	if machine.kind=="battle_tank": return
	var deployed:=deployment(machine)
	for side in [-1,1]:
		var anchor: Vector2=canvas.to_local(machine.body_part.to_global(Vector2(side*43,8)))
		var foot:=Vector2(side*(45+20*deployed),-12+11*deployed)
		Metal.shaft(canvas,anchor,foot,4,"steel")
		Metal.face(canvas,Rect2(foot-Vector2(5,1),Vector2(10,3)),"dark",2)

static func draw_hull(machine: Node2D) -> void:
	var canvas: Node2D=machine.body_part
	var texture:=hull_texture()
	if texture!=null:
		canvas.draw_texture_rect_region(texture,RECTS[machine.kind],REGIONS[machine.kind],Color(1.30,1.20,1.0) if machine.hit_flash>.13 else Color.WHITE)
	else:
		var width:=63.0 if machine.kind!="scout_car" else 56.0
		Metal.polygon(canvas,PackedVector2Array([Vector2(-width,-6),Vector2(-width+18,-18),Vector2(width-20,-18),Vector2(width,-7),Vector2(width,10),Vector2(-width,10)]),"dark",4)
	# The mount, receiver and barrel are separate from the source hull. These
	# two understated details follow the existing mechanical performance states.
	var pivot:=Vector2(8,-18) if machine.kind!="scout_car" else Vector2(10,-21)
	Metal.face(canvas,Rect2(pivot+Vector2(-7,-1),Vector2(14,5)),"dark",5)
	if machine.elite:
		for stripe in 3: Quads.rect(canvas,Rect2(19+stripe*4,-3,2,5),Color("c3a465"))

static func draw_weapon(machine: Node2D) -> void:
	var canvas: Node2D=machine.weapon_part
	var tip:=muzzle(machine.kind)
	var slide:=0.0
	if is_instance_valid(machine.motion) and not machine.motion.pose.is_empty(): slide=snappedf(float(machine.motion.pose.slide)*.45,1)
	if machine.kind=="battle_tank":
		_breech(canvas,PackedVector2Array([Vector2(-20,7),Vector2(-26,-3),Vector2(-14,-14),Vector2(14,-14),Vector2(24,-5),Vector2(24,8)]))
		Metal.shaft(canvas,Vector2(-21,0),tip,7,"dark")
		canvas.draw_line(Vector2(-60,-2),Vector2(-24,-2),EDGE,1)
		_band(canvas,Rect2(-62,-5,7,10))
		_band(canvas,Rect2(-31,-5,5,10))
		Metal.face(canvas,Rect2(-11,-17,17,4),"steel",3)
		Quads.rect(canvas,Rect2(6,-9,5,3),Color("c19454"))
		for x in [-12,-4,4,12]: Quads.rect(canvas,Rect2(x,4,2,2),EDGE)
	elif machine.kind=="mortar_carrier":
		_breech(canvas,PackedVector2Array([Vector2(6,-8),Vector2(10,-3),Vector2(9,6),Vector2(4,9),Vector2(-7,8),Vector2(-12,2),Vector2(-9,-7)]))
		# Forged tube: a dark underside, thin long highlight and staggered wear.
		Metal.shaft(canvas,Vector2(-7,0),tip+Vector2(2,0),10,"dark")
		canvas.draw_line(Vector2(-42,-3),Vector2(-11,-3),Color("909785"),1)
		canvas.draw_line(Vector2(-42,3),Vector2(-11,3),Color("262e29"),2)
		for x in [-40,-24,-11]:
			_band(canvas,Rect2(x,-6,4,12))
			Quads.rect(canvas,Rect2(x+1,-2,1,3),Color("424d44"))
		_band(canvas,Rect2(tip+Vector2(0,-7),Vector2(4,14)))
		canvas.draw_line(tip+Vector2(0,-5),tip+Vector2(0,5),INK,2)
		Quads.rect(canvas,Rect2(-44,-4,1,3),Color("889185"))
		Quads.rect(canvas,Rect2(-32,-4,4,1),Color("767d6a"))
		Quads.rect(canvas,Rect2(-18,-1,3,1),Color("7f7156"))
		Metal.shaft(canvas,Vector2(1,7),Vector2(-19,10),3,"brass")
		_band(canvas,Rect2(-1+slide,-4,8,8))
		Quads.rect(canvas,Rect2(2+slide,-2,3,4),INK)
		Quads.rect(canvas,Rect2(1,-11,5,5),INK)
		canvas.draw_line(Vector2(2,-10),Vector2(4,-10),EDGE,1)
	else:
		_breech(canvas,PackedVector2Array([Vector2(11,5),Vector2(13,0),Vector2(7,-6),Vector2(-10,-6),Vector2(-16,-2),Vector2(-14,6)]))
		Metal.shaft(canvas,Vector2(-12,0),tip,4,"dark")
		canvas.draw_line(Vector2(-37,-1),Vector2(-16,-1),Color("949a86"),1)
		for x in [-32,-27,-22]: Quads.rect(canvas,Rect2(x,0,2,1),INK)
		_band(canvas,Rect2(-39,-3,4,6))
		_band(canvas,Rect2(-16,-3,3,6))
		Quads.rect(canvas,Rect2(-8+slide,-2,9,3),INK)
		canvas.draw_line(Vector2(-6+slide,-2),Vector2(-1+slide,-2),Color("787f6f"),1)
		Quads.rect(canvas,Rect2(3,-2,2,4),Color("a39b7e"))
		Quads.rect(canvas,Rect2(4,0,3,1),INK)
		_band(canvas,Rect2(-10,-10,10,4))
		Quads.rect(canvas,Rect2(-10,-9,2,2),Color("998254"))
		for y in [3,5]: canvas.draw_line(Vector2(-10,y),Vector2(-3,y),Color("2c352e"),1)
	var strength:=1.1 if machine.kind=="battle_tank" else (.92 if machine.kind=="mortar_carrier" else .54)
	WeaponEffectArt.muzzle(canvas,tip,machine.muzzle_flash,.13,-1,strength,machine.attack_count,WeaponEffectArt.reduced(machine.game))

static func _band(canvas: Node2D, rect: Rect2) -> void:
	Quads.rect(canvas,rect,INK)
	Metal.face(canvas,rect.grow(-1),"steel",5)
	canvas.draw_line(rect.position+Vector2.ONE,Vector2(rect.end.x-2,rect.position.y+1),EDGE,1)
	canvas.draw_line(Vector2(rect.position.x+1,rect.end.y-2),rect.end-Vector2(2,2),Color("303c32"),1)

static func _breech(canvas: Node2D, points: PackedVector2Array) -> void:
	Metal.polygon(canvas,points,"dark",3)
	var outline:=points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline,INK,1,false)
	var top: float=points[0].y
	for point in points: top=minf(top,point.y)
	canvas.draw_line(Vector2(-8,top+1),Vector2(5,top+1),Color("89917d"),1)
	for at in [Vector2(7,2),Vector2(-9,-3)]:
		Quads.rect(canvas,Rect2(at-Vector2.ONE,Vector2(3,3)),INK)
		Quads.rect(canvas,Rect2(at-Vector2.ONE,Vector2.ONE),EDGE)

static func weather_segments(machine: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var hull: Node2D=machine.body_part
	var points: Array=[Vector2(-53,-1),Vector2(-37,-9),Vector2(-9,-9),Vector2(1,-19),Vector2(19,-19),Vector2(29,-16),Vector2(49,-14)] if machine.kind=="scout_car" else [Vector2(-60,1),Vector2(-34,-11),Vector2(-8,-14),Vector2(2,-18),Vector2(25,-17),Vector2(45,-12),Vector2(59,-7)]
	for index in range(points.size()-1):
		var a: Vector2=hull.to_global(points[index])
		var b: Vector2=hull.to_global(points[index+1])
		var normal: Vector2=(b-a).orthogonal().normalized()
		if normal.y>0: normal=-normal
		result.append({"from":a,"to":b,"normal":normal,"material":"metal"})
	var gun: Node2D=machine.weapon_part
	var gun_a:=gun.to_global(muzzle(machine.kind)+Vector2(1,-4))
	var gun_b:=gun.to_global(Vector2(9,-4))
	var gun_normal: Vector2=(gun_b-gun_a).orthogonal().normalized()
	if gun_normal.y>0: gun_normal=-gun_normal
	result.append({"from":gun_a,"to":gun_b,"normal":gun_normal,"material":"metal"})
	return result

static func weather_feet(machine: Node2D) -> Array[Vector2]:
	return [machine.legs_part.to_global(contact(machine.kind,0)),machine.legs_part.to_global(contact(machine.kind,1))]
