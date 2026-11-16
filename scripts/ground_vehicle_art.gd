extends RefCounted
const Quads := preload("res://scripts/canvas_quads.gd")
## Painted vehicle hulls with independent native-pixel running gear and weapons.
## Rolling phase follows world travel, never a second replicated animation clock.
const Metal := preload("res://scripts/machine_surface_details.gd")
const Limbs := preload("res://scripts/machine_limb_art.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
## v2: graded per type for value contrast (tools/grade_enemy_hulls.py); the
## mortar carrier has its own copy of the tank hull in a new row. The game
## draws its offline bakes (assets/enemies/vehicle_hulls_world.png, one texel
## per world unit at every drawn size); the plate is the bake key and only
## loaded as the fallback for a size without a bake.
const HULL_PATH := "res://assets/enemies/vehicle_hulls_v2.png"
const REGIONS := {"scout_car":Rect2(265,130,1055,330),"mortar_carrier":Rect2(103,1024,1393,361),"battle_tank":Rect2(103,556,1393,361)}
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

## Suspension on the texel grid. The hull rides the road in whole texels: the
## heave lifts or sinks it, and the pitch shears its columns (draw_hull draws
## the painted hull in vertical strips), so nose and tail step against each
## other instead of the hull turning as a resampled quad. A pure function of
## replicated state (world travel, speed, the move flag, recoil, hit timer and
## the mechanical performance pose), so every peer shows the same ride.
## Returns x: heave in texels (down +), y: nose offset in texels (down +).
const ROAD_WAVES := [Vector3(29.0,1.10,0.0),Vector3(47.0,.70,1.7)]
const MAX_NOSE := 3

static func _road(at: float) -> float:
	var height := 0.0
	for wave: Vector3 in ROAD_WAVES: height += sin(at*TAU/wave.x+wave.z)*wave.y
	return height

static func suspension(machine: Node2D) -> Vector2i:
	var tracked: bool=machine.kind!="scout_car"
	var roll:=travel(machine)
	var speed:=clampf(machine.locomotion_speed/maxf(1,machine.move_speed),0,1)
	var half:=absf(Rect2(RECTS.get(machine.kind,RECTS.scout_car)).position.x)
	# Front and rear axles meet the same road profile one wheelbase apart.
	var front:=_road(roll-half*.55)
	var rear:=_road(roll+half*.55)
	var heave:=(front+rear)*.5*(1.1 if tracked else 1.25)*speed
	var nose:=(front-rear)*.5*(1.5 if tracked else 1.8)*speed
	# Many road wheels average out the road; the tracks rumble instead.
	if tracked: heave+=sin(roll*TAU/11.0)*.95*speed
	# Squat while pulling away, dive while braking to a halt.
	if machine.moving: nose-=(1.0-speed)*(1.0 if tracked else 1.4)
	else: nose+=speed*(1.2 if tracked else 1.7)
	# The shot rocks the hull back onto its tail; a mortar presses it down.
	var kick: float=machine.weapon_recoil
	if machine.kind=="mortar_carrier": heave+=kick*.20
	else: nose-=kick*(.30 if machine.kind=="battle_tank" else .22)
	# A hit jolts the hull: it rears up on its springs (nose up, the body
	# lifted), drops back past rest and settles (the impact performance).
	if machine.hit_flash>.12 and not WeaponEffectArt.reduced(machine.game): heave-=1.0
	if is_instance_valid(machine.motion) and not machine.motion.pose.is_empty():
		var knock:=Vector2(machine.motion.pose.offset)
		heave+=knock.y*.45
		nose-=knock.x*(.40 if tracked else .50)
		nose+=sin(float(machine.motion.pose.roll)*.18)*half
	return Vector2i(roundi(heave),clampi(roundi(nose),-MAX_NOSE,MAX_NOSE))

## Whole-texel drop of the hull column at local x for a nose offset.
static func shear(nose: int, x: float, half: float) -> int:
	return 0 if nose==0 else roundi(float(nose)*-x/half)

## Global point of a hull-local position, including the column shear.
static func hull_point(machine: Node2D, local: Vector2) -> Vector2:
	var nose:=suspension(machine).y
	var half:=absf(Rect2(RECTS.get(machine.kind,RECTS.scout_car)).position.x)
	return machine.body_part.to_global(local+Vector2(0,shear(nose,local.x,half)/maxf(.1,float(machine.visual_scale))))

## Presentation-only life of the hull in whole world texels, on top of the
## road suspension (which the gun mount follows): driving, the body bounces
## a texel up and down on its springs over the small bumps; standing, the
## engine shudders it a texel at a held 6 Hz idle beat. The weapon node that fires
## stays exact; the drawn gun rides along (draw_weapon).
static func hull_life(machine: Node2D) -> Vector2:
	var clock: float = float(machine.motion.get("clock")) if is_instance_valid(machine.motion) else float(machine.age)
	var speed:=clampf(machine.locomotion_speed/maxf(1,machine.move_speed),0,1)
	if speed>.15: return Vector2(0.0,roundf(sin(travel(machine)*TAU/(14.0 if machine.kind=="scout_car" else 18.0))*1.3*speed))
	# Standing: the idle beat (deployed mortar legs and a stopped tank too).
	return Vector2(0.0,-1.0 if fposmod(clock*6.0,1.0)<.5 else 0.0)

static func pose_parts(machine: Node2D) -> void:
	var mirror: float=-machine.attack_direction
	var size: float=machine.visual_scale
	var tracked: bool=machine.kind!="scout_car"
	var settle:=deployment(machine)
	var kick: float=machine.weapon_recoil
	var motion_offset:=Vector2.ZERO
	if is_instance_valid(machine.motion) and not machine.motion.pose.is_empty():
		motion_offset=Vector2(machine.motion.pose.offset)*Vector2(.70,.20)
	for part in [machine.body_part,machine.legs_part,machine.weapon_part]:
		part.scale=Vector2(mirror,1)*size
	machine.legs_part.position=Vector2.ZERO
	machine.legs_part.rotation=0
	var ride:=suspension(machine)
	# Whole texels only: the painted hull never slides or turns off its grid.
	var offset:=Vector2(roundf(motion_offset.x+kick*.13)*mirror,float(ride.x)+roundf(settle*1.4 if machine.kind=="mortar_carrier" else 0.0))
	machine.body_part.position=(offset*size).round()-Vector2(0,machine.body_height)
	machine.body_part.rotation=0.0
	var pivot:=Vector2(8,-18) if tracked else Vector2(10,-21)
	var base: Vector2=machine.to_local(hull_point(machine,pivot))
	machine.body_part.position+=hull_life(machine)
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

## Wheel discs baked once per size on whole texels (rim and tyre): the round
## silhouette steps like the rest of the pixel art instead of a smooth circle
## at screen resolution. Hub, treads and spokes turn on top with the travel.
static var _discs: Dictionary = {}

static func _disc(radius: int, far: bool) -> Texture2D:
	var key := radius*2+(1 if far else 0)
	if _discs.has(key): return _discs[key]
	var size := radius*2+1
	var pixels := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var tyre := Color("242d27") if far else Color("303a32")
	var hub := Color("414d43").darkened(.25 if far else 0.0)
	for y in size:
		for x in size:
			var offset := Vector2(x-radius,y-radius)
			var distance := offset.length()
			if distance > radius+.35: continue
			var tint := INK
			if distance <= radius-1.65: tint = tyre
			if distance <= radius-3.65: tint = hub
			pixels.set_pixel(x,y,tint)
	var texture := ImageTexture.create_from_image(pixels)
	_discs[key] = texture
	return texture

## A wheel in the running gear's world-texel frame (`frame` maps the part's
## space into it): the disc is baked at the wheel's drawn radius and every
## lug, spoke and hub mark lands on whole world texels. The spin is held in
## keys a quarter of the lug pitch apart (the tread repeats every 60
## degrees), so the turning wheel steps visibly instead of shimmering.
const SPIN_KEYS := 24

static func _wheel(canvas: Node2D, frame: Transform2D, at: Vector2, radius: float, phase: float, far: bool=false) -> void:
	var unit := frame.get_scale().y
	var centre := (frame*at).round()
	var whole := roundi(radius*unit)
	canvas.draw_texture(_disc(whole,far),centre-Vector2(whole,whole))
	var turn := floorf(fposmod(phase,TAU)/TAU*SPIN_KEYS)*TAU/SPIN_KEYS
	for index in 6:
		# Worn tread blocks, lit against the dark tyre, so the spin reads.
		var direction := Vector2.from_angle(turn+index*TAU/6.0)
		var lug := (frame*(at+direction*(radius-1.5))).round()
		Quads.rect(canvas,Rect2(lug-Vector2.ONE,Vector2(2,2)),Color("75776a").darkened(.30 if far else 0.0))
	Metal.disc(canvas,centre,(radius-4)*unit,"dark")
	var grid := PixelArt.supports_grid(canvas)
	for spoke in 3:
		var direction:=Vector2.from_angle(turn+spoke*TAU/3.0)
		var from:=frame*(at+direction*2)
		var to:=frame*(at+direction*(radius-5))
		if grid: PixelArt.grid_line(canvas,from,to,Color("b0ab90"))
		else: canvas.draw_line(from.round(),to.round(),Color("b0ab90"),1,false)
	Quads.rect(canvas,Rect2(centre-Vector2(2,2),Vector2(4,4)),INK)
	Quads.rect(canvas,Rect2(centre-Vector2.ONE,Vector2(2,2)),EDGE)

## Running gear on world texels: drawn in the part's upright frame, every
## point mapped from the part's own (scaled) space and rounded to whole
## texels, so tyres, track links and teeth step with the baked hull.
static func draw_running_gear(machine: Node2D) -> void:
	var canvas: Node2D=machine.legs_part
	var tracked: bool=machine.kind!="scout_car"
	var distance:=travel(machine)
	var frame:=WorldTexels.to_upright(canvas)
	canvas.draw_set_transform_matrix(WorldTexels.upright(canvas))
	if not tracked:
		# The far axle is drawn first; the near tires sit exactly in the painted
		# wheel arches. Their bottom edges stay on the ground under suspension.
		for center in wheel_centers(machine.kind):
			_wheel(canvas,frame,center+Vector2(3,-3),10,distance/12,true)
			var spring: Vector2=canvas.to_local(hull_point(machine,Vector2(center.x,6)))
			Limbs.piston(canvas,(frame*spring).round(),(frame*center).round(),false)
			_wheel(canvas,frame,center,12,distance/12)
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		_road_dust(machine,canvas)
		return
	var belt:=PackedVector2Array()
	for point: Vector2 in [Vector2(-52,-25),Vector2(51,-25),Vector2(61,-17),Vector2(60,-8),Vector2(52,0),Vector2(-53,0),Vector2(-62,-8),Vector2(-62,-17)]: belt.append((frame*point).round())
	canvas.draw_colored_polygon(belt,INK)
	var face:=PackedVector2Array()
	for point: Vector2 in [Vector2(-52,-22),Vector2(51,-22),Vector2(58,-15),Vector2(55,-7),Vector2(50,-3),Vector2(-51,-3),Vector2(-59,-10),Vector2(-59,-15)]: face.append((frame*point).round())
	Metal.polygon(canvas,face,"dark",1)
	for center in wheel_centers(machine.kind): _wheel(canvas,frame,center,9,distance/9)
	# Fixed link count and an absolute travel phase keep a stopped belt still.
	var phase:=fposmod(distance,6.0)
	for index in 18:
		for y in [-24,-2]:
			var x: float=-52+index*6+(phase if y==-24 else -phase)
			var link:=(frame*Vector2(x,y)).round()
			Quads.rect(canvas,Rect2(link,Vector2(4,2)),Color("7f806a"))
			Quads.rect(canvas,Rect2(link+Vector2(0,1),Vector2(3,1)),Color("474e40"))
	for end in [-1,1]:
		for tooth in 5:
			var angle:=(-.5+tooth*.25)*PI
			var point:=Vector2(end*51,-12)+Vector2(cos(angle)*end,sin(angle))*11
			Quads.rect(canvas,Rect2((frame*point).round(),Vector2(2,3)),Color("696f5c"))
	if machine.kind=="mortar_carrier":
		# The stabiliser legs on the same world texels: joints rounded in the
		# upright frame, shaft and pad at their drawn size.
		var deployed:=deployment(machine)
		for side in [-1,1]:
			var anchor: Vector2=(frame*canvas.to_local(hull_point(machine,Vector2(side*43,8)))).round()
			var foot:=(frame*Vector2(side*(45+20*deployed),-12+11*deployed)).round()
			Metal.shaft(canvas,anchor,foot,4,"steel")
			Metal.face(canvas,Rect2(foot-Vector2(4,1),Vector2(9,3)),"dark",2)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_road_dust(machine,canvas)

## World size of a hull drawn at `drawn_scale` (the machine's visual scale):
## its bake key, one texel per world unit.
static func hull_texels(kind: String, drawn_scale: float) -> Vector2i:
	return Vector2i((Rect2(RECTS.get(kind,RECTS.scout_car)).size*drawn_scale).round())

static func draw_hull(machine: Node2D) -> void:
	var canvas: Node2D=machine.body_part
	var rect: Rect2=RECTS[machine.kind]
	var half:=absf(rect.position.x)
	var nose:=suspension(machine).y
	var baked:=WorldTexels.texture(HULL_PATH,REGIONS[machine.kind],hull_texels(machine.kind,float(machine.visual_scale)))
	if baked!=null:
		_draw_baked_hull(machine,canvas,baked,rect,half,nose)
		_exhaust(machine,canvas,nose,half,1.0/maxf(.1,float(machine.visual_scale)))
		return
	var texture:=hull_texture()
	# Shear steps are whole world texels; the part carries the hull's scale.
	var unit:=1.0/maxf(.1,float(machine.visual_scale))
	if texture!=null:
		# The hit shows as the whole machine's flash (SiegeMachine.machine_flash).
		# Pitch: runs of whole texel columns, each dropped by its shear.
		var region: Rect2=REGIONS[machine.kind]
		var texels_per_unit:=region.size.x/rect.size.x
		# Runs between the columns where the drop changes, found directly in
		# ascending order (at most 2*MAX_NOSE cuts; no buffer per frame).
		var start:=rect.position.x
		var span:=absi(nose)
		for step in 2*span:
			var level:=span-1-step if nose>0 else step-span
			var cut:=ceilf(-(float(level)+.5)*half/float(nose)-.5)
			# A column centred exactly on the boundary rounds away from zero.
			if shear(nose,cut+.5,half)==shear(nose,cut-.5,half): cut+=1.0
			cut=clampf(cut,start,rect.end.x)
			if cut>start:
				_hull_run(canvas,texture,rect,region,texels_per_unit,start,cut,shear(nose,start+.5,half)*unit)
				start=cut
		if rect.end.x>start: _hull_run(canvas,texture,rect,region,texels_per_unit,start,rect.end.x,shear(nose,start+.5,half)*unit)
	else:
		var width:=63.0 if machine.kind!="scout_car" else 56.0
		Metal.polygon(canvas,PackedVector2Array([Vector2(-width,-6),Vector2(-width+18,-18),Vector2(width-20,-18),Vector2(width,-7),Vector2(width,10),Vector2(-width,10)]),"dark",4)
	# The mount, receiver and barrel are separate from the source hull. These
	# two understated details follow the existing mechanical performance states.
	var pivot:=Vector2(8,-18) if machine.kind!="scout_car" else Vector2(10,-21)
	Metal.face(canvas,Rect2(pivot+Vector2(-7,-1+shear(nose,pivot.x,half)*unit),Vector2(14,5)),"dark",5)
	if machine.elite:
		for stripe in 3: Quads.rect(canvas,Rect2(19+stripe*4,-3+shear(nose,20+stripe*4,half)*unit,2,5),Color("c3a465"))
	_exhaust(machine,canvas,nose,half,unit)

## The hull's offline bake at its drawn size (one texel per world unit),
## upright on the world grid. Pitch: runs of whole baked columns, each dropped
## by its shear in texels, so nose and tail step against each other. The
## mount plate and elite marks sit on the same texels.
static func _draw_baked_hull(machine: Node2D, canvas: Node2D, baked: AtlasTexture, rect: Rect2, half: float, nose: int) -> void:
	var at:=WorldTexels.upright_point(canvas,rect.position).round()
	var columns:=int(baked.region.size.x)
	var height:=baked.region.size.y
	canvas.draw_set_transform_matrix(WorldTexels.upright_turned(canvas,rect.get_center(),0.0))
	var run_start:=0
	var run_drop:=_column_drop(nose,0,columns,rect,half)
	for column in range(1,columns+1):
		var drop:=_column_drop(nose,column,columns,rect,half) if column<columns else run_drop+1
		if drop==run_drop: continue
		var width:=float(column-run_start)
		canvas.draw_texture_rect_region(baked.atlas,Rect2(at+Vector2(run_start,run_drop),Vector2(width,height)),Rect2(baked.region.position+Vector2(run_start,0),Vector2(width,height)))
		run_start=column
		run_drop=drop
	var pivot:=Vector2(8,-18) if machine.kind!="scout_car" else Vector2(10,-21)
	var mount:=WorldTexels.upright_point(canvas,pivot+Vector2(-7,-1)).round()+Vector2(0,shear(nose,pivot.x,half))
	Metal.face(canvas,Rect2(mount,Vector2(14,5)),"dark",5)
	if machine.elite:
		for stripe in 3:
			var mark:=WorldTexels.upright_point(canvas,Vector2(19+stripe*4,-3)).round()
			Quads.rect(canvas,Rect2(mark+Vector2(0,shear(nose,20+stripe*4,half)),Vector2(2,5)),Color("c3a465"))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## Whole-texel drop of baked column `column` of `columns` spanning `rect`.
static func _column_drop(nose: int, column: int, columns: int, rect: Rect2, half: float) -> int:
	return shear(nose,rect.position.x+(float(column)+.5)*rect.size.x/float(columns),half)

static func _hull_run(canvas: Node2D, texture: Texture2D, rect: Rect2, region: Rect2, texels_per_unit: float, from: float, to: float, drop: float) -> void:
	canvas.draw_texture_rect_region(texture,Rect2(from,rect.position.y+drop,to-from,rect.size.y),Rect2(region.position.x+(from-rect.position.x)*texels_per_unit,region.position.y,(to-from)*texels_per_unit,region.size.y))

## Dust thrown up behind the tyres or the track ends while the hull drives:
## small cel-shaded puffs that roll back off the contact and thin out, more
## of them the faster it goes. Presentation clock; absent with reduced effects.
const DUST_PUFFS := 3

static func _road_dust(machine: Node2D, canvas: Node2D) -> void:
	if not machine.is_inside_tree() or machine.dead or not is_instance_valid(machine.motion) or not PixelArt.supports_grid(canvas): return
	if WeaponEffectArt.reduced(machine.game): return
	var speed:=clampf(machine.locomotion_speed/maxf(1,machine.move_speed),0,1)
	if speed<.2: return
	var clock: float=float(machine.motion.get("clock")) if machine.motion.get("clock")!=null else float(machine.age)
	# The two ground contacts (tyres, or the ends of the track).
	var contacts:=Vector2(-26.0,36.0) if machine.kind=="scout_car" else Vector2(-50.0,52.0)
	var tone:=Color(PixelArt.smoke_tone(Color(.64,.61,.55)),.85)
	for wheel in 2:
		for index in DUST_PUFFS:
			var cycle:=fposmod(clock*(1.6+1.2*speed)+float(index)/float(DUST_PUFFS)+float(wheel)*.37,1.0)
			# Local +x is the rear in every facing (the part carries the mirror).
			var at:=Vector2((contacts.x if wheel==0 else contacts.y)+6.0+cycle*(10.0+8.0*speed),-2.0-cycle*(4.0+3.0*speed))
			PixelArt.grid_cel(canvas,at,(2.6+cycle*5.0)*(.6+.4*speed),tone,index+wheel*5+floori(clock*1.7),clampf(.05+cycle*.90,0.0,1.0),0.0,.75)

## Exhaust from the stack (scout car) or the engine deck grille (tracked
## hulls): puffs leave the mouth, swell and drift back and up, quicker and
## longer behind a moving hull, darker and thicker on a damaged engine. The
## clock is the presentation child's, so guests animate it between snapshots.
const EXHAUST := {"scout_car":Vector2(37,-24),"mortar_carrier":Vector2(45,-17),"battle_tank":Vector2(45,-17)}
const EXHAUST_PUFFS := 4

static func _exhaust(machine: Node2D, canvas: Node2D, nose: int, half: float, unit: float) -> void:
	# The wreck reuses this drawing through an unparented delegate: no engine.
	if not machine.is_inside_tree() or machine.dead or not is_instance_valid(machine.motion): return
	var clock: float=float(machine.motion.get("clock")) if machine.motion.get("clock")!=null else float(machine.age)
	var speed:=clampf(machine.locomotion_speed/maxf(1,machine.move_speed),0,1)
	var damage:=1.0-clampf(float(machine.hp)/maxf(1.0,float(machine.max_hp)*.45),0.0,1.0)
	var socket: Vector2=EXHAUST.get(machine.kind,EXHAUST.scout_car)
	socket.y+=shear(nose,socket.x,half)*unit
	var count:=2 if WeaponEffectArt.reduced(machine.game) else EXHAUST_PUFFS
	# Pulling away the engine works hard: faster, larger, darker puffs.
	var strain:=clampf((1.0-speed)*2.0,0.0,1.0) if machine.moving else 0.0
	var rate:=lerpf(.9,1.6,maxf(speed,strain))
	var tone:=Color(.36,.35,.34,.95).lerp(Color(.20,.19,.18,1.0),maxf(damage,strain*.5))
	for index in count:
		var cycle:=clock*rate+float(index)/float(count)
		var age:=fposmod(cycle,1.0)
		# Local +x is the rear in every facing (the part carries the mirror).
		var drift:=Vector2(age*(3.0+11.0*speed)+sin(cycle*5.1)*age,-age*(12.0-4.0*speed))
		var radius:=3.0+age*(4.0+2.5*strain+3.5*damage)
		if PixelArt.supports_grid(canvas):
			# Dense at the mouth, torn into dithered wisps as it drifts away.
			PixelArt.grid_smoke(canvas,socket+drift,radius,Color(PixelArt.smoke_tone(tone),tone.a),index+floori(cycle)*3,smoothstep(.55,1.0,age)*.85,clampf(1.0-age*4.0,0.0,1.0)*damage*.7)
		else:
			PixelArt.puff(canvas,socket+drift,radius,tone,index,false)

## The guns' own space as tools/capture_vehicle_guns.gd renders it (the
## high-density source of their world-texel aim stances).
const GUN_SOURCE := "res://assets/enemies/vehicle_guns_src.png"
const GUN_ROWS := {"scout_car":0, "mortar_carrier":1, "battle_tank":2}
const GUN_RECTS := {"scout_car":Rect2(-68,-18,96,32), "mortar_carrier":Rect2(-68,-18,96,32), "battle_tank":Rect2(-68,-18,96,32)}
const GUN_SOURCE_SCALE := 8.0

static func gun_region(kind: String) -> Rect2:
	var rect: Rect2 = GUN_RECTS.get(kind,GUN_RECTS.scout_car)
	return Rect2(Vector2(0,float(GUN_ROWS.get(kind,0))*rect.size.y)*GUN_SOURCE_SCALE,rect.size*GUN_SOURCE_SCALE)

## The gun: its baked aim stance at the drawn size, upright on world texels
## (WorldTexels.draw_stance); the procedural drawing is the source render
## (`source`) and the fallback for a size without a bake.
static func draw_weapon(machine: Node2D, source: bool = false) -> void:
	var canvas: Node2D=machine.weapon_part
	var tip:=muzzle(machine.kind)
	var strength:=1.1 if machine.kind=="battle_tank" else (.92 if machine.kind=="mortar_carrier" else .54)
	var rect: Rect2 = GUN_RECTS.get(machine.kind,GUN_RECTS.scout_car)
	if not source and WorldTexels.draw_stance(canvas,GUN_SOURCE,gun_region(machine.kind),rect,Vector2i((rect.size*float(machine.visual_scale)).round()),Color.WHITE,hull_life(machine)):
		WeaponEffectArt.muzzle(canvas,tip,machine.muzzle_flash,.13,-1,strength,machine.attack_count,WeaponEffectArt.reduced(machine.game))
		return
	# The gun rides the hull's presentation life (hull_life), in its own space.
	var lift:=Vector2.ZERO if source else Transform2D(canvas.rotation,canvas.scale,0.0,Vector2.ZERO).affine_inverse().basis_xform(hull_life(machine))
	canvas.draw_set_transform(lift)
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
		# A bright steel barrel keeps the light gun clear of the fence lattice.
		Metal.shaft(canvas,Vector2(-12,0),tip,4,"steel")
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
	if not source: WeaponEffectArt.muzzle(canvas,tip,machine.muzzle_flash,.13,-1,strength,machine.attack_count,WeaponEffectArt.reduced(machine.game))
	canvas.draw_set_transform(Vector2.ZERO)

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
	var points: Array=[Vector2(-53,-1),Vector2(-37,-9),Vector2(-9,-9),Vector2(1,-19),Vector2(19,-19),Vector2(29,-16),Vector2(49,-14)] if machine.kind=="scout_car" else [Vector2(-60,1),Vector2(-34,-11),Vector2(-8,-14),Vector2(2,-18),Vector2(25,-17),Vector2(45,-12),Vector2(59,-7)]
	for index in range(points.size()-1):
		var a: Vector2=hull_point(machine,points[index])
		var b: Vector2=hull_point(machine,points[index+1])
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
