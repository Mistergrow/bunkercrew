class_name ImpactBurst
extends Node2D
## Short, bounded CPU particle bursts. Solid fragments sweep against the actual
## terrain/walls; particles never cause damage or alter a collision shape.

const MAX_BURSTS := 36
const MAX_PARTICLES := 48
const MAX_LIFETIME := 1.65
const GROUP := "transient_effects"
const BALLISTIC_FLAVORS := ["rifle", "shotgun", "turret", "dart", "tracer"]
const RICOCHET_MAX_INCIDENCE := 0.70
const PixelArt = preload("res://scripts/pixel_effect_art.gd")
const PRESETS := {
	"metal": {"sparks":15, "shards":7, "dust":4, "hot":Color("fff0b1"), "body":Color("a1b2af"), "dust_color":Color("6c7677"), "flash":24.0},
	"concrete": {"sparks":3, "shards":13, "dust":10, "hot":Color("eacb8b"), "body":Color("a7a58f"), "dust_color":Color("85836c"), "flash":16.0},
	"earth": {"sparks":0, "shards":10, "dust":10, "hot":Color("d6b483"), "body":Color("9a7a52"), "dust_color":Color("82725a"), "flash":0.0},
	"mining_ore": {"sparks":0, "shards":8, "dust":3, "hot":Color("a99570"), "body":Color("82745c"), "dust_color":Color("6c6856"), "flash":0.0},
	"mining_limestone": {"sparks":0, "shards":7, "dust":4, "hot":Color("bab6a0"), "body":Color("aaa68f"), "dust_color":Color("888675"), "flash":0.0},
	"mining_tungsten": {"sparks":0, "shards":9, "dust":2, "hot":Color("aaa99a"), "body":Color("737c7c"), "dust_color":Color("656a62"), "flash":0.0},
	"mining_sand": {"sparks":0, "shards":5, "dust":4, "hot":Color("b9a073"), "body":Color("8a7755"), "dust_color":Color("807052"), "flash":0.0},
	"glass": {"sparks":5, "shards":17, "dust":3, "hot":Color("e6fff4"), "body":Color("a6d8d8"), "dust_color":Color("819c9b"), "flash":20.0},
	"flesh": {"sparks":0, "shards":6, "dust":3, "hot":Color("a25348"), "body":Color("a44e43"), "dust_color":Color("797065"), "flash":0.0},
	"explosion": {"sparks":18, "shards":14, "dust":12, "hot":Color("fff0bc"), "body":Color("7e8b88"), "dust_color":Color("4f5a5a"), "flash":48.0},
	"arc": {"sparks":17, "shards":4, "dust":3, "hot":Color("d3faff"), "body":Color("ab98df"), "dust_color":Color("6f748e"), "flash":28.0},
	"utility": {"sparks":5, "shards":2, "dust":0, "hot":Art.AMBER, "body":Art.AMBER, "dust_color":Art.MUTED, "flash":0.0},
}

var surface_material := "metal"
var direction := Vector2.LEFT
var power := 1.0
var reduced := false
var age := 0.0
var bits: Array[Dictionary] = []
var seed_value := 0
var count_override := -1
var tint_override := Color.TRANSPARENT
var collision_count := 0
var retired := false
var _random := RandomNumberGenerator.new()
var _preset: Dictionary = {}
var _collision_ray := PhysicsRayQueryParameters2D.new()

static func material_for(collider: Object) -> String:
	if collider is Node:
		if collider.has_method("impact_material"): return str(collider.impact_material())
		if collider.is_in_group("dome_segments"): return "glass"
		if collider.is_in_group("players") or collider.is_in_group("human_enemies"): return "flesh"
		if collider.is_in_group("enemies") or collider.is_in_group("core") or collider.is_in_group("field_defenses") or collider.is_in_group("anti_air"): return "metal"
		if collider.is_in_group("mine_blocks"): return "earth"
	return "concrete"

static func sound_for(collider: Object) -> String:
	if collider is Node and collider.has_method("impact_sound"): return str(collider.impact_sound())
	if collider is Node and collider.is_in_group("walls"):
		# DefenseWall's wooden formwork (1) and exposed rebar (2) have distinct contacts.
		match collider.get("state"):
			1: return "impact_wood"
			2: return "impact_metal"
	return {"metal":"impact_metal","concrete":"impact_stone","earth":"impact_stone"}.get(material_for(collider),"hit")

static func ricochet_for(collider: Object, normal: Vector2, incoming: Vector2, flavor: String) -> String:
	# This is contact audio, not projectile deflection. Only an identified bullet
	# approaching a hard face at more than 45.6 degrees from its normal can skid.
	# Inside-shape rays have no normal; unknown and explosive/energy shots opt out.
	if not is_instance_valid(collider) or flavor not in BALLISTIC_FLAVORS or not normal.is_finite() or not incoming.is_finite(): return ""
	if normal.length_squared() < 0.000001 or incoming.length_squared() < 0.000001: return ""
	var incidence := -incoming.normalized().dot(normal.normalized())
	if incidence <= 0.001 or incidence >= RICOCHET_MAX_INCIDENCE: return ""
	var surface := material_for(collider)
	# Wooden formwork shares a wall collider with concrete and cannot ring like it.
	var cue := sound_for(collider)
	if cue == "impact_wood": return ""
	if surface == "metal" or (surface == "concrete" and cue == "impact_metal"):
		return "ricochet_metal"
	return "ricochet_stone" if surface == "concrete" else ""

static func emit(game, point: Vector2, surface: String, normal: Vector2 = Vector2.LEFT, strength: float = 1.0) -> void:
	if not is_instance_valid(game): return
	if game.has_method("impact"):
		game.impact(point, surface, normal, strength)
	elif game.has_method("fx"):
		game.fx(point, PRESETS.get(surface, PRESETS.metal).hot, mini(16, int(8 * strength)))

static func contact(game, collider: Object, point: Vector2, normal: Vector2, incoming: Vector2, strength: float = 1.0, flavor: String = "") -> void:
	# The projectile owns its precise contact; receivers suppress a second
	# generic body-centre puff on this frame. Destruction remains independent.
	if collider is Node:
		collider.set_meta("impact_contact_frame", Engine.get_physics_frames())
		preload("res://scripts/combat_gore.gd").capture_contact(collider,point,incoming,strength,flavor)
	var surface := "arc" if flavor == "arcgun" else material_for(collider)
	if is_instance_valid(game):
		var sound := preload("res://scripts/spatial_sound.gd")
		sound.emit(game,sound_for(collider),point)
		var ricochet := ricochet_for(collider,normal,incoming,flavor)
		if not ricochet.is_empty(): sound.emit(game,ricochet,point)
	# Only accepted damage creates blood. Invulnerable contacts retain audio.
	if material_for(collider)!="flesh" or not is_instance_valid(game) or not is_instance_valid(game.get("combat_gore")):
		emit(game, point, surface, normal if normal.length_squared() > 0.01 else -incoming, strength)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 24
	var owner_game=get_parent()
	var gore=owner_game.get("combat_gore") if is_instance_valid(owner_game) else null
	if surface_material=="flesh" and is_instance_valid(gore) and gore.level==0:
		retire()
		return
	if not PRESETS.has(surface_material): surface_material = "metal"
	power = clampf(power, 0.25, 2.0)
	direction = direction.normalized() if direction.length_squared() > 0.01 else Vector2.LEFT
	_preset = PRESETS[surface_material]
	_random.seed = seed_value if seed_value != 0 else int(get_instance_id()) * 7919
	# Hiding retired nodes immediately also caps one-frame shotgun salvos.
	var active := get_tree().get_nodes_in_group(GROUP)
	var limit := 16 if reduced else MAX_BURSTS
	while active.size() >= limit:
		var oldest = active.pop_front()
		oldest.retire()
	add_to_group(GROUP)
	var scale_count := (0.34 if reduced else 1.0) * sqrt(power)
	var max_bits := 16 if reduced else MAX_PARTICLES
	if count_override >= 0:
		max_bits = mini(max_bits, int(ceil(count_override * (0.34 if reduced else 1.0))))
	for type in ["dust", "shards", "sparks"]:
		var number := int(ceil(float(_preset[type]) * scale_count))
		if count_override >= 0:
			number = int(ceil(count_override * (0.7 if type == "sparks" else 0.3))) if type != "dust" else 0
		for index in number:
			if bits.size() >= max_bits: break
			_spawn_bit(type)
	queue_redraw()

func _spawn_bit(type: String) -> void:
	var angle := _random.randf_range(-0.85, 0.85)
	if surface_material == "explosion": angle = _random.randf_range(-PI, PI)
	var velocity := direction.rotated(angle) * _random.randf_range(80, 190)
	var life := _random.randf_range(0.5, 1.2)
	var size := _random.randf_range(2, 4)
	var color: Color = _preset.body
	var gravity := 420.0
	var drag := 0.7
	if type == "sparks":
		velocity *= 2.4
		life = _random.randf_range(0.12, 0.46)
		size = 1.0
		color = _preset.hot
		gravity = 150.0
		drag = 1.9
	elif type == "dust":
		velocity = velocity * 0.16 + Vector2(0, -_random.randf_range(12, 28))
		life = _random.randf_range(0.55, 1.5)
		size = _random.randf_range(4, 9)
		color = _preset.dust_color
		gravity = -10.0
		drag = 2.0
	else:
		velocity.y -= _random.randf_range(35, 125)
	if surface_material == "flesh":
		velocity *= 0.34
		size = 1.0 if type == "shards" else 3.0
		life = minf(life, 0.4)
		gravity = 250.0
	if surface_material == "glass" and type == "shards": size *= 0.85
	if surface_material == "utility":
		velocity *= 0.48
		life = minf(life, 0.6)
	if surface_material.begins_with("mining_"):
		# A pick releases small local chips. The final cell break uses the same
		# material at greater strength; neither event resembles an explosion.
		velocity *= 0.42
		if type == "shards":
			size = _random.randf_range(1.0,2.6)*sqrt(power)
			life = _random.randf_range(.65,1.25)
		else:
			size = _random.randf_range(2.0,4.0)
			life = _random.randf_range(.30,.65)
	if tint_override.a > 0: color = tint_override
	velocity *= sqrt(power) * (0.55 if reduced else 1.0)
	bits.append({"type":type, "pos":direction * 2.0, "velocity":velocity, "age":0.0, "life":minf(life, MAX_LIFETIME), "size":size, "color":color, "rotation":_random.randf_range(-PI,PI), "spin":_random.randf_range(-12,12), "gravity":gravity, "drag":drag, "bounces":0, "stopped":false})

func retire() -> void:
	if retired: return
	retired = true
	remove_from_group(GROUP)
	hide()
	set_physics_process(false)
	queue_free()

func _physics_process(delta: float) -> void:
	if retired: return
	age += delta
	if age >= MAX_LIFETIME:
		retire()
		return
	var space:=get_world_2d().direct_space_state
	_collision_ray.collision_mask=1|2
	_collision_ray.hit_from_inside=true
	for bit in bits:
		bit.age += delta
		if bit.age >= bit.life or bit.stopped: continue
		bit.velocity.y += float(bit.gravity) * delta
		bit.velocity *= exp(-float(bit.drag) * delta)
		var destination: Vector2 = bit.pos + bit.velocity * delta
		_collision_ray.from=global_position+bit.pos
		_collision_ray.to=global_position+destination
		var hit := space.intersect_ray(_collision_ray)
		if not hit.is_empty():
			collision_count += 1
			bit.pos = hit.position - global_position + hit.normal * 0.9
			if bit.type == "shards" and bit.bounces == 0 and hit.normal.length_squared() > 0.01:
				bit.velocity = Vector2(bit.velocity).bounce(hit.normal) * 0.28
				bit.bounces = 1
				bit.spin *= 0.45
			else:
				bit.stopped = true
				bit.life = minf(bit.life, bit.age + (0.55 if surface_material.begins_with("mining_") and bit.type=="shards" else 0.12))
		else:
			bit.pos = destination
		bit.rotation += float(bit.spin) * delta
	queue_redraw()

func _draw() -> void:
	if retired or _preset.is_empty(): return
	_draw_flash()
	for bit in bits:
		if bit.age >= bit.life: continue
		var opacity: float = 1.0 - float(bit.age) / float(bit.life)
		var color: Color = bit.color
		color.a = minf(1, opacity * 1.7)
		var point: Vector2 = Vector2(bit.pos).round()
		var size: float = bit.size
		if bit.type == "dust":
			color.a = opacity * (0.10 if surface_material.begins_with("mining_") else (0.14 if reduced else 0.23))
			var radius := roundf(size * (1.0 + float(bit.age) * 1.5))
			PixelArt.puff(self,point,radius,color,int(float(bit.life)*100.0),not reduced)
		elif bit.type == "sparks":
			var trail: Vector2 = Vector2(bit.velocity).normalized() * minf(14, Vector2(bit.velocity).length() * 0.035)
			draw_line(point - trail.round(), point, Color(color, color.a * 0.36), 3)
			draw_line(point - (trail * 0.65).round(), point, color, 1)
			draw_rect(Rect2(point, Vector2(2,2)), Color("fff3d3") if surface_material not in ["glass","arc"] else Color("dffcff"))
		else:
			var axis := Vector2.from_angle(float(bit.rotation)) * size
			if surface_material == "flesh":
				draw_rect(Rect2(point, Vector2(2,2)), color)
			else:
				var side := axis.orthogonal() * (0.4 if surface_material == "glass" else 0.65)
				var shape := PackedVector2Array([(point-axis).round(), (point+side).round(), (point+axis).round(), (point-side*0.8).round()])
				draw_colored_polygon(shape, color)
				draw_line((point-axis).round(), (point+side).round(), Color(color.lightened(0.28),color.a), 1)

func _draw_flash() -> void:
	if reduced: return
	var radius: float = _preset.flash * sqrt(power)
	var fade := maxf(0, 1.0 - age / 0.15)
	if radius <= 0 or fade <= 0: return
	var color: Color = _preset.hot
	PixelArt.glow(self,Vector2.ZERO,radius,Color(color,0.07*fade),seed_value)
	draw_rect(Rect2(-3,-3,6,6), Color(color,fade*0.8))
	if surface_material in ["explosion","arc"]:
		PixelArt.shockwave(self,Vector2.ZERO,5+age*170*sqrt(power),Color(color,fade*.32),seed_value)
	if surface_material == "arc":
		for index in 3:
			var axis := direction.rotated(index*TAU/3) * radius
			draw_polyline(PackedVector2Array([Vector2.ZERO, (axis*0.35+axis.orthogonal()*0.18).round(), (axis*0.62-axis.orthogonal()*0.15).round(), axis.round()]), Color(color,fade*0.85), 1)
