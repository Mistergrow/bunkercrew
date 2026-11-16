extends Node2D
## Detached visual rig: original enemy, collision, rewards and wave membership
## retire immediately. Drawing delegates never enter the tree or run gameplay.
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const MAX_ACTIVE := 20
## Body frames per second of a ground hull's held collapse.
const COLLAPSE_FPS := 12.0
const FRAGMENT_SHAPES := [
	[Vector2(-2,-1),Vector2(2,-1),Vector2(2,0),Vector2(0,0),Vector2(0,1),Vector2(-2,1)],
	[Vector2(-1,-2),Vector2(1,-2),Vector2(1,0),Vector2(0,0),Vector2(0,2),Vector2(-1,2)],
	[Vector2(-3,-1),Vector2(1,-1),Vector2(3,0),Vector2(3,1),Vector2(-1,1),Vector2(-1,0)],
]
var identity := "strider"
var airborne := false
var elapsed := 0.0
var duration := 1.5
var hull_offset := Vector2.ZERO
var hull_angle := 0.0
var weapon_origin := Vector2.ZERO
var weapon_angle := 0.0
var standing_height := 43.0
var mirror := 1.0
var rolling := false
var reduced_effects := false
var artist: Node2D
var artist_ability: Node
var artist_motion: Node2D
## Aircraft fall instead of fading in mid-air: the hull keeps the flight
## velocity it had, drops under a gravity chosen so it reaches the arena floor
## inside the unchanged class lifetime, tumbles in authored 22.5 degree steps,
## trails burning smoke, and on contact with terrain or a roof crashes with a
## local (presentation-only) blast before it dissolves where it lies.
const WRECK_SHADER := preload("res://shaders/actor_wreck.gdshader")
const TUMBLE_STEP := PI/8.0
const TRAIL := 24
const TRAIL_LIFE := 0.85
## Puffs overlap along the fall path (spacing below their young radius), so
## the plume is a continuous ribbon instead of a string of beads.
const TRAIL_SPACING := 5.0
static var _wreck_material: ShaderMaterial
var fall_velocity := Vector2.ZERO
var fall_offset := Vector2.ZERO
var gravity := 700.0
var spin := 0.0
var tumble := 0.0
var landed := -1.0
var body_half := 12.0
var mass := 1.0
var flames: Node2D
var _trail := PackedVector3Array()
var _trail_head := 0
var _trail_clock := 0.0
var _dissolve := -1.0
var _ray := PhysicsRayQueryParameters2D.new()

static func spawn(machine: Node2D, kind: String, flying: bool) -> Node2D:
	var old: Array[Node] = []
	for candidate in machine.get_tree().get_nodes_in_group("enemy_motion_wrecks"):
		if not candidate.is_queued_for_deletion(): old.append(candidate)
	if old.size()>=MAX_ACTIVE: old[0].queue_free()
	var wreck = load("res://scripts/enemy_motion_wreck.gd").new()
	wreck.identity = kind
	wreck.airborne = flying
	wreck.duration = Pose.duration("destroy",kind)
	wreck.hull_offset = machine.body_part.position
	wreck.hull_angle = machine.body_part.rotation
	wreck.weapon_origin = machine.weapon_part.position
	wreck.weapon_angle = machine.weapon_part.rotation
	wreck.standing_height = machine.body_height
	wreck.mirror = -machine.attack_direction
	wreck.rolling = machine.has_method("uses_rolling_contacts") and machine.uses_rolling_contacts()
	wreck.reduced_effects = WeaponEffectArt.reduced(machine.game)
	wreck.transform = machine.transform
	wreck.z_index = machine.z_index
	if flying:
		var traits: Vector4 = Pose.PROFILES.get(kind,Pose.PROFILES.strider)
		var flight: Vector2 = machine.get("flight_velocity") if "flight_velocity" in machine else Vector2.ZERO
		wreck.mass = traits.x
		wreck.fall_velocity = flight.limit_length(140.0)+Vector2(0,-35)
		wreck.spin = (signf(flight.x) if absf(flight.x)>4.0 else wreck.mirror)*lerpf(6.0,1.6,clampf((traits.x-0.75)/0.9,0,1))
		var size: Vector2 = machine.profile.get("body_size",Vector2(57,34))
		wreck.body_half = size.y*0.35*float(machine.profile.get("scale",1.0))
		var floor_y: float = float(machine.get("scenario_floor")) if "scenario_floor" in machine else machine.global_position.y+320.0
		var height := maxf(60.0,floor_y-machine.global_position.y-wreck.body_half)
		var fall_time: float = float(wreck.duration)*0.62
		wreck.gravity = clampf(2.0*(height+35.0*fall_time)/(fall_time*fall_time),300.0,1600.0)
	# Reuse the original drawing methods and exact equipment. This unparented
	# delegate has no collision children, group membership, _ready or processing.
	wreck.artist = machine.get_script().new()
	# Absolute chassis travel freezes the original wheel/tread phase on defeat.
	if machine.has_method("uses_rolling_contacts") and machine.uses_rolling_contacts(): wreck.artist.position=machine.position
	for field in ["kind","profile","chassis_atlas","elite","body_height","age","gait","visual_scale","attack_direction","overdrive","weapon_recoil","windup","worker_windup","moving","locomotion_speed"]:
		if field in machine and field in wreck.artist:
			var value = machine.get(field)
			wreck.artist.set(field,value.duplicate(true) if value is Dictionary else value)
	wreck.artist_motion = load("res://scripts/enemy_motion.gd").new()
	wreck.artist_motion.pose = Pose.sample("destroy",0,kind,flying)
	wreck.artist.motion = wreck.artist_motion
	if not flying and is_instance_valid(machine.abilities):
		wreck.artist_ability = machine.abilities.get_script().new()
		for field in ["mode","shield_hp","shield_open","rush_primed","rush_time","rush_warning","heat","vent_time"]:
			wreck.artist_ability.set(field,machine.abilities.get(field))
		wreck.artist_ability.machine = wreck.artist
		wreck.artist.abilities = wreck.artist_ability
	machine.get_parent().add_child(wreck)
	wreck._build_parts(machine)
	return wreck

func _ready() -> void:
	add_to_group("enemy_motion_wrecks")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Its smoke wisps step in world texels like the blast around it.
	material = PixelArt.grid_material(PixelArt.GRID_LIT)

static func wreck_material() -> ShaderMaterial:
	if _wreck_material==null:
		_wreck_material = ShaderMaterial.new()
		_wreck_material.shader = WRECK_SHADER
	return _wreck_material

func _build_parts(source: Node2D) -> void:
	var names := ["propulsion_part","body_part","weapon_part"] if airborne else ["legs_part","body_part","weapon_part"]
	for field in names:
		var part := Node2D.new()
		# Copy authored components: decomposing a negative-X Transform2D turns it
		# into PI rotation / negative Y, then later collapse rotation flips it over.
		part.position = source.get(field).position
		part.rotation = source.get(field).rotation
		part.scale = source.get(field).scale
		# A dead hull drops the weather/team read and steps on the texel grid.
		part.material = wreck_material()
		part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		artist.set(field,part)
		var method := "_draw_"+str(field).trim_suffix("_part")
		if field=="propulsion_part": method = "_draw_propulsion"
		part.draw.connect(Callable(artist,method))
		add_child(part)
	if is_instance_valid(artist_ability):
		var equipment := GroundVariantVisual.new()
		equipment.machine = artist
		equipment.material = wreck_material()
		artist.variant_visual = equipment
		artist.body_part.add_child(equipment)
	# Engine and fuel fire on its own unlit grid layer above the hull: falling
	# aircraft trail it, and a wrecked machine on the ground burns down.
	flames = Node2D.new()
	flames.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
	flames.draw.connect(_draw_flames)
	add_child(flames)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>=duration:
		queue_free()
		return
	var phase := clampf(elapsed/duration,0,1)
	var drop := Pose.smooth(phase/0.64)
	# The wreck leaves in an ordered texel dither instead of an alpha fade.
	_set_dissolve(Pose.smooth((elapsed-(duration-0.45))/0.45) if airborne else Pose.smooth((phase-0.64)/0.36))
	artist.body_part.modulate = Color.WHITE.lerp(Color("716959"),Pose.smooth(phase/0.8)*0.55)
	if airborne and landed<0.0:
		# A falling hull is lit by its own fire (held flicker at 12 fps)
		# instead of charring against a dark sky; it chars once down.
		var flicker := 0.85+0.15*float(posmod(floori(elapsed*12.0)*7+3,5))/4.0
		artist.body_part.modulate = Color(1.0,1.0,1.0).lerp(Color(1.42,1.08,.80),flicker)
	artist.weapon_part.modulate = artist.body_part.modulate
	artist.age += delta*(1.0-phase)*0.8
	if airborne:
		artist_motion.pose = Pose.sample("destroy",phase,identity,airborne)
		_fall(delta)
	else:
		# A ground hull collapses in held body frames (style bible 5); the
		# dissolve and the flames keep their own continuous timing.
		var frame := clampf(floorf(elapsed*COLLAPSE_FPS+0.0001)/COLLAPSE_FPS/duration,0,1)
		drop = Pose.smooth(frame/0.64)
		artist_motion.pose = Pose.sample("destroy",frame,identity,airborne)
		var horizontal_drop := 4.0 if rolling else 12.0
		var vertical_drop := 5.0 if rolling else standing_height*0.58
		var displacement := Vector2(mirror*drop*horizontal_drop,drop*vertical_drop)
		artist.body_part.position = hull_offset+displacement
		artist.body_part.rotation = hull_angle+(0.06 if rolling else 0.18)*drop*mirror
		artist.weapon_part.position = weapon_origin+displacement*0.9
		artist.weapon_part.rotation = weapon_angle+0.32*drop*mirror
	for part in get_children():
		if part is CanvasItem: part.queue_redraw()
	queue_redraw()

func _set_dissolve(value: float) -> void:
	value = snappedf(clampf(value,0,1),1.0/16.0)
	if value==_dissolve: return
	_dissolve = value
	for part in get_children():
		if part is CanvasItem and part!=flames:
			part.set_instance_shader_parameter(&"dissolve",value)
			for detail in part.get_children():
				if detail is CanvasItem: detail.set_instance_shader_parameter(&"dissolve",value)

func _fall(delta: float) -> void:
	if landed<0.0:
		var before := hull_offset+fall_offset
		fall_velocity.y += gravity*delta
		fall_velocity.x *= exp(-delta*0.6)
		fall_offset += fall_velocity*delta
		tumble += spin*delta
		var after := hull_offset+fall_offset
		if is_inside_tree():
			_ray.from = to_global(before)
			_ray.to = to_global(after+Vector2(0,body_half))
			_ray.collision_mask = 1|2
			var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
			if not hit.is_empty():
				landed = elapsed
				fall_offset = to_local(hit.position)-hull_offset-Vector2(0,body_half)
				# It comes to rest on its belly or its back, never on a corner.
				tumble = roundf(tumble/PI)*PI
				_crash(hit.position)
		# One puff per few texels of fall, so the plume stays continuous at speed.
		_trail_clock += before.distance_to(after)
		if _trail_clock>=TRAIL_SPACING or _trail.is_empty():
			_trail_clock = 0.0
			_add_trail(after)
	else:
		# A short skid along the ground after the impact.
		fall_offset.x += fall_velocity.x*delta*0.3*exp(-(elapsed-landed)*7.0)
	var shown := roundf(tumble/TUMBLE_STEP)*TUMBLE_STEP
	var at := hull_offset+fall_offset
	artist.body_part.position = at
	artist.body_part.rotation = hull_angle+shown
	artist.propulsion_part.position = at
	artist.propulsion_part.rotation = artist.body_part.rotation
	artist.weapon_part.position = at+(weapon_origin-hull_offset).rotated(shown)
	artist.weapon_part.rotation = weapon_angle+shown

func _add_trail(point: Vector2) -> void:
	var size := 7 if reduced_effects else TRAIL
	if _trail.size()<size: _trail.append(Vector3(point.x,point.y,elapsed))
	else:
		_trail[_trail_head] = Vector3(point.x,point.y,elapsed)
		_trail_head = (_trail_head+1)%size

func _crash(point: Vector2) -> void:
	var host := get_parent()
	if not is_instance_valid(host): return
	# Local presentation only: no scenery damage, sound or network event (the
	# kill already played those); every peer crashes its own wreck.
	var burst := ImpactBurst.new()
	burst.position = host.to_local(point)
	burst.surface_material = "explosion"
	burst.direction = Vector2.UP
	burst.power = clampf(0.55*mass,0.45,1.1)
	burst.class_hint = "vehicle"
	burst.reduced = reduced_effects
	host.add_child(burst)

func _draw_flames() -> void:
	var phase := clampf(elapsed/duration,0,1)
	var seed_value := posmod(identity.hash()+roundi(global_position.x),997)
	var frame := PixelArt.flame_frame(elapsed,seed_value)
	if airborne:
		# Flames stream from the hull against its fall, then the crashed
		# wreck burns down before it dissolves.
		var at := hull_offset+fall_offset
		var heat := 0.95-phase*0.55
		var lean := clampf(-fall_velocity.x*.05,-9.0,9.0) if landed<0.0 else 0.0
		# Big enough to follow at the combat camera against a night sky.
		var tall := (14.0+mass*6.0)*(1.0 if landed<0.0 else clampf(1.0-(elapsed-landed)/maxf(.2,duration-landed),.3,1.0))
		PixelArt.grid_flame(flames,at+Vector2(-mirror*4.0,-1.0),9.0+mass*3.0,tall,heat,frame,seed_value,lean)
		if not reduced_effects:
			PixelArt.grid_flame(flames,at+Vector2(mirror*5.0,-3.0),6.0+mass*2.0,tall*.75,heat*.9,frame+7,seed_value+3,lean*.8)
			PixelArt.grid_flame(flames,at+Vector2(-mirror*12.0,1.0),5.0+mass*1.5,tall*.55,heat*.8,frame+13,seed_value+6,lean*1.1)
		return
	# A ground wreck: fuel and wiring burn on the hull, flaring up as it
	# collapses and dying back as it dissolves.
	var burn := smoothstep(0.0,.18,phase)*(1.0-smoothstep(.55,.92,phase))
	if burn <= 0.02: return
	var span := 11.0 if rolling else 8.0
	for index in (1 if reduced_effects else 2):
		var side := -1.0 if index==0 else 1.0
		var base: Vector2 = artist.body_part.position+Vector2(side*span*mirror,-standing_height*(.12 if rolling else .18))
		PixelArt.grid_flame(flames,base,(8.0 if index==0 else 6.0)*(.6+.4*burn),(15.0 if index==0 else 10.0)*burn,.35+.6*burn,frame+index*9,seed_value+index*5,float(index)*1.5-.5)

func _draw() -> void:
	var phase := clampf(elapsed/duration,0,1)
	# Three bent components distinguish a tread/hull plate from an actuator or
	# an aircraft skin strip. Two further slots change from short hot sparks to
	# charcoal wisps; the aftermath never exceeds the original five elements.
	var shape_index := 2 if airborne else (0 if rolling else 1)
	var variation := posmod(identity.hash(),3)
	for index in 3:
		var t := clampf(phase*1.5-float(index)*0.035,0,1)
		var spread := (11.0 if rolling else (19.0 if airborne else 15.0))+variation*2
		var point := hull_offset+Vector2(mirror*(index-1)*spread*t,-sin(t*PI)*(14.0+index*4)+t*8)
		var points := PackedVector2Array()
		for corner: Vector2 in FRAGMENT_SHAPES[shape_index]:
			points.append(point.round()+corner*Vector2(mirror,1))
		var cooling := smoothstep(0.0,.14,elapsed)
		var tint := Color("e6b47c").lerp(Color("777767") if rolling else Color("596762"),cooling)
		draw_colored_polygon(points,Color(tint,1.0-t))
	if airborne:
		# Burning smoke trail: puffs left along the fall path swell, drift up
		# and tear apart on the texel grid.
		for index in _trail.size():
			var entry: Vector3 = _trail[index]
			var age := (elapsed-entry.z)/TRAIL_LIFE
			if age<0.0 or age>=1.0: continue
			# Uneven sizes and a lazy sideways drift keep the plume from reading
			# as a chain of equal beads.
			var sway := sin(float(index)*2.3+entry.z*7.0)
			var point := Vector2(entry.x,entry.y)+Vector2(sway*age*5.0,-age*12.0)
			# Black fuel smoke, warm while it leaves the fire.
			var tone := Color(.36,.30,.26,.80).lerp(Color(.30,.30,.30,.70),clampf(age*2.0,0,1))
			PixelArt.smoke_puff(self,point,4.5+absf(sway)*1.5+age*(7.0+mass*3.0),tone,index,age,clampf(1.0-age*3.0,0.0,1.0)*.8)
		if landed>=0.0:
			var since := elapsed-landed
			for index in 2:
				var rise := fposmod(since*0.9+index*0.5,1.0)
				var point := hull_offset+fall_offset+Vector2((index-0.5)*8.0,-6.0-rise*22.0)
				PixelArt.smoke_puff(self,point,3.0+rise*6.0,Color(.28,.28,.28,.70),index+3,rise,clampf(1.0-rise*2.5,0.0,1.0)*.6)
	if reduced_effects: return
	for index in 2:
		var side: float=-1.0 if index==0 else 1.0
		if elapsed<.20:
			var t := elapsed/.20
			var point := hull_offset+Vector2(side*(3+t*16),-3-t*(9+index*4))
			draw_line(point.round(),(point-Vector2(side*3,-1)).round(),Color("fff0b9").lerp(Color("d99358"),t),1,false)
		else:
			var t := clampf((elapsed-.20)/maxf(.01,duration-.20),0,1)
			var point := hull_offset+Vector2(side*(3+t*8),-4-t*(18+index*5))
			# Black smoke over the burning hull.
			PixelArt.smoke_puff(self,point,2.5+t*(5 if airborne else 7),Color(.28,.27,.26,.5),index+variation,t,clampf(1.0-t*2.0,0.0,1.0)*.7)

func _exit_tree() -> void:
	if is_instance_valid(artist): artist.free()
	if is_instance_valid(artist_ability): artist_ability.free()
	if is_instance_valid(artist_motion): artist_motion.free()
