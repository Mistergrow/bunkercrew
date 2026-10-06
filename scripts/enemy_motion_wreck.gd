extends Node2D
## Detached visual rig: original enemy, collision, rewards and wave membership
## retire immediately. Drawing delegates never enter the tree or run gameplay.
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const MAX_ACTIVE := 20
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

func _build_parts(source: Node2D) -> void:
	var names := ["propulsion_part","body_part","weapon_part"] if airborne else ["legs_part","body_part","weapon_part"]
	for field in names:
		var part := Node2D.new()
		# Copy authored components: decomposing a negative-X Transform2D turns it
		# into PI rotation / negative Y, then later collapse rotation flips it over.
		part.position = source.get(field).position
		part.rotation = source.get(field).rotation
		part.scale = source.get(field).scale
		part.material = source.get(field).material
		artist.set(field,part)
		var method := "_draw_"+str(field).trim_suffix("_part")
		if field=="propulsion_part": method = "_draw_propulsion"
		part.draw.connect(Callable(artist,method))
		add_child(part)
	if is_instance_valid(artist_ability):
		var equipment := GroundVariantVisual.new()
		equipment.machine = artist
		artist.variant_visual = equipment
		artist.body_part.add_child(equipment)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>=duration:
		queue_free()
		return
	var phase := clampf(elapsed/duration,0,1)
	var drop := Pose.smooth(phase/0.64)
	modulate.a = 1.0-Pose.smooth((phase-0.64)/0.36)
	var horizontal_drop := 4.0 if rolling else 12.0
	var vertical_drop := 5.0 if rolling else (40.0 if airborne else standing_height*0.58)
	var displacement := Vector2(mirror*drop*horizontal_drop,drop*vertical_drop)
	artist.body_part.modulate = Color.WHITE.lerp(Color("716959"),Pose.smooth(phase/0.8)*0.55)
	artist.weapon_part.modulate = artist.body_part.modulate
	artist.body_part.position = hull_offset+displacement
	artist.body_part.rotation = hull_angle+(0.06 if rolling else (0.45 if airborne else 0.18))*drop*mirror
	artist.weapon_part.position = weapon_origin+displacement*0.9
	artist.weapon_part.rotation = weapon_angle+0.32*drop*mirror
	artist.age += delta*(1.0-phase)*0.8
	artist_motion.pose = Pose.sample("destroy",phase,identity,airborne)
	if airborne:
		artist.propulsion_part.position = displacement
		artist.propulsion_part.rotation = artist.body_part.rotation
	for part in get_children():
		if part is CanvasItem: part.queue_redraw()
	queue_redraw()

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
	if reduced_effects: return
	for index in 2:
		var side: float=-1.0 if index==0 else 1.0
		if elapsed<.20:
			var t := elapsed/.20
			var point := hull_offset+Vector2(side*(3+t*16),-3-t*(9+index*4))
			draw_line(point.round(),(point-Vector2(side*3,-1)).round(),Color("fff0b9").lerp(Color("d99358"),t),1,false)
		else:
			var t := clampf((elapsed-.20)/maxf(.01,duration-.20),0,1)
			var point := hull_offset+Vector2(side*(3+t*8),-4-t*(14+index*3))
			PixelArt.puff(self,point,2+t*(4 if airborne else 3),Color(.15,.18,.16,(1-t)*.25),index+variation,false)

func _exit_tree() -> void:
	if is_instance_valid(artist): artist.free()
	if is_instance_valid(artist_ability): artist_ability.free()
	if is_instance_valid(artist_motion): artist_motion.free()
