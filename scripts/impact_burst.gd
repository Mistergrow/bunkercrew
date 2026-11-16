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
const LOBES := 7
const FIRE_HOT := Color("fff3c4")
const FIRE_ORANGE := Color("f59a3e")
const FIRE_RED := Color("a8402a")
const SMOKE_BODY := Color("4b4e51")
const PRESETS := {
	"metal": {"sparks":15, "shards":7, "dust":4, "hot":Color("fff0b1"), "body":Color("5f6866"), "dust_color":Color("6c7677"), "flash":24.0},
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
	# Presentation-only flak airburst (combat_feel.gd fuses shells locally on
	# host and guests alike); never sent as a replicated impact.
	"flak": {"sparks":12, "shards":4, "dust":0, "hot":Color("ffe6a0"), "body":Color("2e2c2a"), "dust_color":Color("2b2a2b"), "flash":14.0},
}
## Explosion families. life: seconds until the last smoke has frayed out (it
## holds solid for the first third); fire: seconds a billow burns; rise: climb of the smoke
## column; skirt: ground dust rolled out by the pressure front; scorch: width
## of the ground mark; chunks/trails/burning: debris, smoking and burning pieces;
## size: the family's scale of fireball, pressure ring and smoke (gameplay
## weight: a grenade pops, a fuel tank or a building goes up).
const BLASTS := {
	"grenade": {"lobes":4, "fire":.20, "smoke":Color("8a8277"), "dust":Color("8c7f6c"), "rise":.80, "life":2.2, "debris":"earth", "chunks":7, "trails":1, "burning":0, "skirt":.80, "scorch":.65, "size":1.0},
	"ground": {"lobes":7, "fire":.34, "smoke":Color("837d74"), "dust":Color("8c7f6c"), "rise":1.0, "life":2.9, "debris":"earth", "chunks":12, "trails":3, "burning":0, "skirt":1.0, "scorch":1.0, "size":1.45},
	"mech": {"lobes":6, "fire":.32, "smoke":Color("6c6c6b"), "dust":Color("7d776c"), "rise":1.0, "life":2.8, "debris":"steel", "chunks":12, "trails":3, "burning":1, "skirt":.80, "scorch":.90, "size":1.40},
	# Fuel burns black: the darkest family, still lobed, lit and dithered.
	"vehicle": {"lobes":7, "fire":.48, "smoke":Color("47423d"), "dust":Color("766f64"), "rise":1.3, "life":3.0, "debris":"wreck", "chunks":12, "trails":4, "burning":2, "skirt":.90, "scorch":1.1, "size":1.60},
	"aircraft": {"lobes":5, "fire":.30, "smoke":Color("5c5c5d"), "dust":Color("5c5c5d"), "rise":.75, "life":2.7, "debris":"airframe", "chunks":11, "trails":5, "burning":3, "skirt":0.0, "scorch":0.0, "size":1.30},
	"structure": {"lobes":7, "fire":.26, "smoke":Color("9a9488"), "dust":Color("a39d8e"), "rise":.80, "life":2.9, "debris":"concrete", "chunks":14, "trails":2, "burning":0, "skirt":1.45, "scorch":.80, "size":1.50},
}
## Flak: a white-yellow flash and a near-black burst (FLAK_BURST) that greys
## into a dark charcoal puff (smoke), holds for about a second while it swells
## and drifts on the wind, then frays out: the classic black flak puff, which a
## pale grey one never read as against cloud. No fireball: that is the
## explosions' look.
const FLAK := {"lobes":4, "fire":.13, "smoke":Color("37332f"), "dust":Color("2c2b2c"), "rise":1.0, "life":2.5, "debris":"steel", "chunks":0, "trails":0, "burning":0, "skirt":0.0, "scorch":0.0}
const FLAK_BURST := Color("1b1816")
const FLAK_REACH := 16.0
const FLAK_LIFETIME := 2.5
## Seconds the flak shrapnel streaks fly out of a burst.
const FLAK_SHRAPNEL := .34
## Body and lit edge of blast debris per family.
const DEBRIS := {
	"earth": [Color("3b2f25"), Color("7a6650")],
	"steel": [Color("394141"), Color("98a39e")],
	"wreck": [Color("242220"), Color("75726a")],
	"airframe": [Color("4e5557"), Color("b2bab5")],
	"concrete": [Color("6a665c"), Color("b4af9e")],
}
const STRUCTURE_GROUPS := ["field_defenses", "flak_turrets", "core", "turrets", "perimeter_sites"]
## Seconds a blast keeps looking for the wreck or building it came from.
const SETTLE_TIME := .07
const TRAIL := 6
const TRAIL_STEP := .04
## Seconds the pressure ring of a blast takes to run out and vanish.
const PRESSURE_LIFE := .22
## Hot palettes, hottest first; sparks and embers step down them as they cool.
const SPARK_RAMP := [Color("fffbe8"), Color("ffe27a"), Color("ffa43a"), Color("e8642a"), Color("a8341c")]
const EMBER_RAMP := [Color("fff3c4"), Color("ffc65a"), Color("f59a3e"), Color("d5602c"), Color("a8402a")]
const COLD_RAMP := [Color("f2fffd"), Color("c4f4ff"), Color("8fd8f0"), Color("6f9fd8"), Color("5a6cb0")]
static var _flak_flash_ms := -100000

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
var glow_layer: Node2D
var hot_layer: Node2D # unlit: sparks, embers and flame keep their own brightness at night
var flash_scale := 1.0 # lowered by combat_feel.gd when blasts follow each other too quickly
var _lobe_offset := PackedVector2Array()
var _lobe_shape := PackedVector2Array() # x: size factor, y: start delay
var _lobe_rise := PackedVector2Array() # x: sideways drift, y: upward speed
var lifetime := MAX_LIFETIME # blasts linger longer than the particle budget
var blast_class := "" # explosion family (BLASTS), settled in the first frames
var _ground := NAN # local y of the ground surface below a blast; NAN: open air
var _settle_frames := 0
var class_hint := "" # a caller that knows what blew up may name the family
var _wind := 0.0 # horizontal wind at the blast (px/s), sampled once
var _size_from := 1.0 # family scale before the family settled
var _size_at := 0.0 # age at which the family settled

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
	# Debris, sparks and smoke share the actor texel grid: whole world units for
	# the burst origin, and grid shaders for every shape (pixel_effect_art.gd).
	global_position = global_position.round()
	material = PixelArt.grid_material(PixelArt.GRID_LIT)
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
	var blast := surface_material in ["explosion","flak"]
	if blast:
		# Fire and smoke linger past the particle budget; debris and the family
		# of the blast follow in the first frames (_settle_class).
		lifetime = FLAK_LIFETIME if surface_material == "flak" else float(BLASTS[_provisional_class()].life)
	var scale_count := (0.34 if reduced else 1.0) * sqrt(power)
	var max_bits := 16 if reduced else MAX_PARTICLES
	if count_override >= 0:
		max_bits = mini(max_bits, int(ceil(count_override * (0.34 if reduced else 1.0))))
	for type in ["dust", "shards", "sparks"]:
		# A blast throws its own debris once it knows what blew up; its dust is
		# the cel-shaded ground skirt and smoke column, not loose puffs.
		if surface_material == "explosion" and type != "sparks": continue
		if surface_material == "flak" and type == "dust": continue
		var number := int(ceil(float(_preset[type]) * scale_count))
		if count_override >= 0:
			number = int(ceil(count_override * (0.7 if type == "sparks" else 0.3))) if type != "dust" else 0
		for index in number:
			if bits.size() >= max_bits: break
			_spawn_bit(type)
	if blast:
		_wind = PixelArt.wind_x(get_parent(),global_position)
		_stage_explosion()
	if int(_preset.sparks) > 0 or blast or float(_preset.flash) > 0.0:
		hot_layer = Node2D.new()
		hot_layer.name = "Hot"
		hot_layer.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
		hot_layer.draw.connect(_draw_hot)
		add_child(hot_layer)
	if not reduced and (float(_preset.flash) > 0.0 or int(_preset.sparks) > 0):
		# Hot cores, spark heads and halos add light on a separate unlit layer;
		# the burst itself keeps opaque debris, dust and smoke.
		glow_layer = Node2D.new()
		glow_layer.name = "Glow"
		glow_layer.material = PixelArt.grid_material(PixelArt.GRID_ADD)
		glow_layer.z_index = 1
		glow_layer.draw.connect(_draw_glow)
		add_child(glow_layer)
	if surface_material == "flak":
		# Airbursts follow each other quickly: only the first in a third of a
		# second gets the full white heart and rays (photosensitivity).
		var now := Time.get_ticks_msec()
		if now - _flak_flash_ms < 330: flash_scale = .45
		else: _flak_flash_ms = now
	var feel := preload("res://scripts/combat_feel.gd").of(self)
	if feel != null: feel.burst_started(self)
	_leave_mark()
	queue_redraw()

## A round that struck a static surface (bunker concrete, a wall, terrain,
## a steel fixture) leaves a mark on it (impact_marks.gd); a burst in open
## air or on a moving actor leaves none.
func _leave_mark() -> void:
	if not surface_material in ["metal","concrete","earth"] or not is_inside_tree(): return
	_collision_ray.collision_mask = 1|2
	_collision_ray.hit_from_inside = false
	_collision_ray.from = global_position+direction*2.0
	_collision_ray.to = global_position-direction*6.0
	var hit := get_world_2d().direct_space_state.intersect_ray(_collision_ray)
	if hit.is_empty() or Vector2(hit.normal).length_squared() < .25: return
	var collider: Object = hit.collider
	if not (collider is StaticBody2D or (collider is Node and (collider as Node).is_in_group("walls"))): return
	var marks: Node2D = preload("res://scripts/impact_marks.gd").of(self)
	if marks != null: marks.mark(Vector2(hit.position),Vector2(hit.normal),surface_material,collider)

func _provisional_class() -> String:
	return "grenade" if power < 1.0 else "ground"

func _stage_explosion() -> void:
	# Fixed lobes on the open side of the surface: flash, fireball and smoke
	# column are functions of age, so they need no further particle budget.
	# The first four start at once; the later billows wait until the family of
	# the blast is known, so a smaller family never pops lobes away.
	var flak := surface_material == "flak"
	var count := (3 if reduced else 4) if flak else (4 if reduced else LOBES)
	var side := direction.orthogonal()
	for index in count:
		var along := _random.randf_range(.10,.85) if index > 0 else .30
		var across := _random.randf_range(-.85,.85) if index > 0 else 0.0
		if flak:
			# An airburst has no surface: a round cluster around the shell.
			var around := Vector2.from_angle(float(index)*TAU/float(count-1)+_random.randf_range(-.4,.4))*_random.randf_range(.75,1.05) if index > 0 else Vector2.ZERO
			_lobe_offset.append(around)
			_lobe_shape.append(Vector2(.80 if index == 0 else _random.randf_range(.52,.70),0.0 if index == 0 else _random.randf_range(.02,.07)))
			_lobe_rise.append(Vector2(_random.randf_range(-5.0,5.0),_random.randf_range(4.0,12.0)))
			continue
		if index > 0:
			# Billows spread over the open side so the fireball reads as a
			# cluster of masses, not one disc.
			along = _random.randf_range(.18,1.0)
			across = _random.randf_range(-.95,.95)
		_lobe_offset.append(direction*along+side*across)
		var delay := 0.0 if index == 0 else (_random.randf_range(.0,.06) if index < 4 else _random.randf_range(.09,.15))
		_lobe_shape.append(Vector2(.86 if index == 0 else _random.randf_range(.55,.84),delay))
		_lobe_rise.append(Vector2(_random.randf_range(-20.0,20.0),42.0 if index == 0 else _random.randf_range(40.0,128.0)))

func _spawn_bit(type: String) -> void:
	var angle := _random.randf_range(-0.85, 0.85)
	if surface_material in ["explosion","flak"]: angle = _random.randf_range(-PI, PI)
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
		if surface_material == "metal":
			# Ricochet sparks arc down under their own weight and skip once.
			life = _random.randf_range(0.22, 0.62)
			gravity = 520.0
			drag = 1.25
		elif surface_material == "explosion":
			# Embers: slower, long-lived, thrown upward before they fall.
			velocity = velocity * .62 + Vector2(0, -_random.randf_range(40, 150))
			life = _random.randf_range(0.55, 1.35)
			gravity = 300.0
			drag = 1.0
		elif surface_material == "flak":
			# Shrapnel: a fast, even ring of hot fragments that dies quickly.
			velocity = Vector2.from_angle(_random.randf_range(-PI,PI))*_random.randf_range(250,430)
			life = _random.randf_range(0.14, 0.34)
			gravity = 120.0
			drag = 3.2
	elif type == "dust":
		velocity = velocity * (0.30 if surface_material in ["concrete","earth"] else 0.16) + Vector2(0, -_random.randf_range(12, 28))
		life = _random.randf_range(0.55, 1.5)
		size = _random.randf_range(4, 9)
		color = _preset.dust_color
		gravity = -10.0
		drag = 2.0
	else:
		velocity.y -= _random.randf_range(35, 125)
	if surface_material == "flak" and type == "shards":
		# Spent casing fragments: small, dark, falling out of the puff.
		velocity *= .55
		size = _random.randf_range(1.0, 1.8)
		life = _random.randf_range(0.9, 1.5)
	if surface_material == "metal" and type == "shards":
		# Torn plating flakes: small and dark, not pale panes.
		size = _random.randf_range(1.2, 2.6)
	if surface_material == "earth":
		if type == "dust":
			# Soil hangs in the air: a larger cloud that drifts up for longer.
			life = _random.randf_range(0.95, 1.6)
			size = _random.randf_range(5, 11)
		elif bits.size() % 2 == 0:
			# Every other fragment is grit: a single fast grain.
			size = _random.randf_range(1.0, 1.4)
			velocity *= 1.35
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

func _settle_class() -> void:
	## The family of a blast, from what both host and guests can see at its
	## point: the fresh wreck the dying machine leaves (aircraft, wheeled or
	## tracked vehicle, walker), a convoy truck or a defensive structure next
	## to it, otherwise ground (by power) or open air. A guest may receive the
	## replicated blast a moment before the snapshot that leaves the wreck, so
	## the search runs for a few frames; the fireball covers that moment.
	if _settle_frames == 0: _probe_ground()
	_settle_frames += 1
	var found := class_hint if BLASTS.has(class_hint) else _source_class()
	if found.is_empty():
		if age < SETTLE_TIME: return
		found = "aircraft" if is_nan(_ground) else _provisional_class()
	_size_from = _size()
	_size_at = age
	blast_class = found
	var spec: Dictionary = BLASTS[blast_class]
	lifetime = float(spec.life)
	if blast_class == "vehicle":
		# Fuel cooks off a moment later: the late billows become a second blast.
		for index in range(4,_lobe_shape.size()):
			if _lobe_shape[index].y > age: _lobe_shape[index].y = .20+float(index-4)*.06
	_spawn_debris(spec)
	if float(spec.scorch) > 0.0 and not is_nan(_ground):
		var feel := preload("res://scripts/combat_feel.gd").of(self)
		if feel != null and feel.has_method("scorch"): feel.scorch(global_position+Vector2(0,_ground),27.0*sqrt(power)*float(spec.scorch)*float(spec.size)*1.6,seed_value+int(get_instance_id()%997))

func _probe_ground() -> void:
	var reach := 27.0*sqrt(power)
	_collision_ray.collision_mask = 1|2
	_collision_ray.hit_from_inside = false
	# From above the point: a blast released at ground level (or a hair inside
	# it) still finds the surface it stands on.
	_collision_ray.from = global_position+Vector2(0,-reach*.5)
	_collision_ray.to = global_position+Vector2(0,reach*1.5+26.0)
	var hit := get_world_2d().direct_space_state.intersect_ray(_collision_ray)
	if not hit.is_empty() and Vector2(hit.normal).y < -.5: _ground = roundf(float(hit.position.y)-global_position.y)

func _source_class() -> String:
	var tree := get_tree()
	var at := global_position
	var nearest := 110.0*110.0
	var found := ""
	for wreck in tree.get_nodes_in_group("enemy_motion_wrecks"):
		if not wreck is Node2D or wreck.is_queued_for_deletion() or float(wreck.get("elapsed")) > .4: continue
		var gap: float = (wreck as Node2D).global_position.distance_squared_to(at)
		if gap < nearest:
			nearest = gap
			found = "aircraft" if wreck.get("airborne") == true else ("vehicle" if wreck.get("rolling") == true else "mech")
	if not found.is_empty(): return found
	for truck in tree.get_nodes_in_group("convoy_vehicles"):
		if truck is Node2D and (truck as Node2D).global_position.distance_squared_to(at) < 100.0*100.0: return "vehicle"
	for group: String in STRUCTURE_GROUPS:
		for building in tree.get_nodes_in_group(group):
			if building is Node2D and (building as Node2D).global_position.distance_squared_to(at) < 52.0*52.0: return "structure"
	return ""

func _spawn_debris(spec: Dictionary) -> void:
	# Chunks of whatever blew up, flung in arcs from the fireball; a few heavy
	# pieces trail smoke, and burning ones carry a flame head.
	var palette: Array = DEBRIS[spec.debris]
	var airborne := is_nan(_ground)
	var count := int(ceil(float(spec.chunks)*(.4 if reduced else 1.0)*sqrt(power)))
	var trails := 0 if reduced else int(spec.trails)
	var burning := 0 if reduced else int(spec.burning)
	var reach := 27.0*sqrt(power)*float(spec.size)
	for index in count:
		if bits.size() >= MAX_PARTICLES: break
		var angle := _random.randf_range(-PI,PI) if airborne else _random.randf_range(-PI*.94,-PI*.06)
		var heavy := index < trails
		var speed := (_random.randf_range(150,270) if heavy else _random.randf_range(90,240))*sqrt(float(spec.size))
		var velocity := Vector2.from_angle(angle)*speed*sqrt(power)*(0.55 if reduced else 1.0)
		var bit := {"type":"shards", "pos":Vector2.from_angle(angle)*reach*.18, "velocity":velocity, "age":0.0,
			"life":_random.randf_range(1.05,1.6) if heavy else _random.randf_range(.75,1.4),
			"size":(_random.randf_range(2.6,3.9) if heavy else _random.randf_range(1.4,3.0))*sqrt(float(spec.size)),
			"color":palette[0], "light":palette[1], "rotation":_random.randf_range(-PI,PI), "spin":_random.randf_range(-9,9),
			"gravity":330.0 if airborne else 430.0, "drag":.45, "bounces":0, "stopped":false}
		if heavy:
			bit["trail"] = PackedVector2Array()
			bit["trail_clock"] = 0.0
			bit["burning"] = index < burning
		bits.append(bit)

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
	if age >= lifetime:
		retire()
		return
	if surface_material == "explosion" and blast_class.is_empty(): _settle_class()
	var space:=get_world_2d().direct_space_state
	_collision_ray.collision_mask=1|2
	_collision_ray.hit_from_inside=true
	for bit in bits:
		bit.age += delta
		if bit.age >= bit.life: continue
		if bit.has("trail"):
			# A smoke trail sampled every few frames, at most TRAIL points.
			bit.trail_clock += delta
			if bit.trail_clock >= TRAIL_STEP:
				bit.trail_clock = 0.0
				var trail: PackedVector2Array = bit.trail
				if trail.size() >= TRAIL: trail.remove_at(0)
				trail.append(Vector2(bit.pos).round())
				bit.trail = trail
		if bit.stopped: continue
		bit.velocity.y += float(bit.gravity) * delta
		bit.velocity *= exp(-float(bit.drag) * delta)
		var destination: Vector2 = bit.pos + bit.velocity * delta
		_collision_ray.from=global_position+bit.pos
		_collision_ray.to=global_position+destination
		var hit := space.intersect_ray(_collision_ray)
		if not hit.is_empty():
			collision_count += 1
			bit.pos = hit.position - global_position + hit.normal * 0.9
			var skips: bool = bit.type == "shards" or (bit.type == "sparks" and surface_material in ["metal","explosion"])
			if skips and bit.bounces == 0 and hit.normal.length_squared() > 0.01:
				bit.velocity = Vector2(bit.velocity).bounce(hit.normal) * (0.28 if bit.type == "shards" else 0.46)
				bit.bounces = 1
				bit.spin *= 0.45
			else:
				bit.stopped = true
				bit.life = minf(bit.life, bit.age + (0.55 if surface_material.begins_with("mining_") and bit.type=="shards" else (0.5 if bit.has("light") else 0.12)))
		else:
			bit.pos = destination
		bit.rotation += float(bit.spin) * delta
	queue_redraw()
	if is_instance_valid(glow_layer): glow_layer.queue_redraw()
	if is_instance_valid(hot_layer): hot_layer.queue_redraw()

static func _ramp(ramp: Array, cooled: float) -> Color:
	# Banded, not blended: a spark or ember steps down its palette.
	return ramp[clampi(int(cooled*float(ramp.size())),0,ramp.size()-1)]

func _draw() -> void:
	if retired or _preset.is_empty(): return
	if surface_material in ["explosion","flak"]: _draw_explosion()
	for bit in bits:
		if bit.age >= bit.life: continue
		var opacity: float = 1.0 - float(bit.age) / float(bit.life)
		var color: Color = bit.color
		color.a = minf(1, opacity * 1.7)
		var point: Vector2 = Vector2(bit.pos).round()
		var size: float = bit.size
		if bit.type == "dust":
			# Half of the fade is translucency, the other half an ordered-dither
			# dissolve on the texel grid, so old dust breaks up instead of ghosting.
			if surface_material.begins_with("mining_"):
				color.a = (0.45 + 0.55 * opacity) * 0.10
				PixelArt.grid_puff(self,point,roundf(size * (1.0 + float(bit.age) * 1.5)),color,int(float(bit.life)*100.0),smoothstep(0.45,1.0,1.0 - opacity) * 0.9)
				continue
			# Kicked-up dust: a small cel-shaded cloud that tears apart in
			# clusters as it rises, instead of a soft translucent smudge.
			color.a = (0.30 if reduced else 0.58) if surface_material in ["concrete","earth"] else (0.22 if reduced else 0.34)
			var radius := roundf(size * (0.55 + float(bit.age) * 0.95))
			var variant := int(float(bit.life)*100.0)
			var thin := clampf(.12 + smoothstep(0.2,1.0,1.0 - opacity) * 0.9,0.0,1.0)
			# Two offset lumps per mote: a ragged cluster, not a ball.
			PixelArt.grid_cel(self,point,radius,color,variant,thin)
			PixelArt.grid_cel(self,point+Vector2(float(bit.rotation)*.25*radius,-.45*radius).round(),radius*.62,color,variant+1,thin)
		elif bit.type == "sparks":
			continue # self-lit: drawn by _draw_hot on the unlit layer
		elif bit.has("light"):
			# Blast debris: an opaque chunk with one lit edge, then its smoke trail.
			if bit.has("trail"): _draw_trail(bit)
			color.a = 1.0 if opacity > .18 else 0.0
			var axis := Vector2.from_angle(float(bit.rotation)) * size
			PixelArt.grid_shard(self, point, axis, size * .62, color)
			draw_rect(Rect2(point-Vector2(0,ceilf(size*.4)),Vector2.ONE),Color(bit.light,color.a))
		else:
			var axis := Vector2.from_angle(float(bit.rotation)) * size
			if surface_material == "flesh":
				draw_rect(Rect2(point, Vector2(2,2)), color)
			else:
				var side := size * (0.4 if surface_material == "glass" else 0.65)
				PixelArt.grid_shard(self, point, axis, side, color)
				if surface_material == "glass":
					PixelArt.grid_line(self, point-axis, point+axis.orthogonal().normalized()*side, Color(color.lightened(0.28),color.a))
				else:
					# One lit texel on the upper edge instead of a pale outline.
					draw_rect(Rect2(point-Vector2(0,ceilf(side)),Vector2.ONE),Color(color.lightened(0.34),color.a))

func _draw_trail(bit: Dictionary) -> void:
	var trail: PackedVector2Array = bit.trail
	var count := trail.size()
	var smoke: Color = PixelArt.smoke_tone(_blast_spec().smoke)
	var burning: bool = bit.get("burning",false)
	for index in count:
		# Oldest first: larger, paler and further broken up.
		var old := float(count-index)/float(TRAIL)
		var fade := smoothstep(.55,1.0,float(bit.age)/float(bit.life))
		# Overlapping puffs that widen with age: a ribbon of smoke, not beads.
		PixelArt.grid_smoke(self,trail[index],2.0+old*3.5,Color(smoke.lightened(.10*old),.95),index*7+int(float(bit.life)*50.0),clampf(old*.50+fade,0.0,1.0),.6 if burning and index == count-1 else 0.0,clampf(_wind*.004,-.3,.3)*old)

func _blast_spec() -> Dictionary:
	if surface_material == "flak": return FLAK
	return BLASTS[blast_class if not blast_class.is_empty() else _provisional_class()]

func _reach() -> float:
	return (FLAK_REACH if surface_material == "flak" else 27.0)*sqrt(power)*_size()

## The family's scale; it eases over from the provisional family once the
## blast knows what blew up, so the fireball never pops to a new size.
func _size() -> float:
	if surface_material != "explosion": return 1.0
	var target := float(_blast_spec().get("size",1.0))
	if blast_class.is_empty(): return target
	return lerpf(_size_from,target,smoothstep(0.0,.14,age-_size_at))

func _lobe_count() -> int:
	# Before the family is known only the first four billows may start.
	if surface_material == "flak": return _lobe_offset.size()
	if blast_class.is_empty(): return mini(4,_lobe_offset.size())
	return mini(int(_blast_spec().lobes) if not reduced else 4,_lobe_offset.size())

func _lobe_center(index: int, time: float, reach: float) -> Vector2:
	var grow := 1.0-exp(-time*9.0)
	# The smoke leaves the fireball: every lobe climbs at its own pace and the
	# column leans and spreads a little as it rises, and drifts downwind.
	var climb := time*time/(time+.35)
	var center: Vector2 = _lobe_offset[index]*reach*grow+Vector2(_lobe_rise[index].x*climb,-_lobe_rise[index].y*climb)*sqrt(power)*float(_blast_spec().rise)
	center.x += _wind*.30*climb
	if not is_nan(_ground):
		# Billows rest on the ground they rose from instead of sinking into it.
		center.y = minf(center.y,_ground-_lobe_radius(index,time,reach)*.62)
	return center

func _lobe_radius(index: int, time: float, reach: float) -> float:
	var grow := 1.0-exp(-time*9.0)
	return reach*_lobe_shape[index].x*(.34+.66*grow)*(1.0+time*.22)

func _fire_time(index: int) -> float:
	# Each billow burns for its own share of the family's fire time.
	return float(_blast_spec().fire)*(1.0 if index == 0 else .72+.06*float(index%5))

func _draw_explosion() -> void:
	# Smoke billows under the flame (drawn unlit by _draw_hot): they appear as
	# each billow cools, keep the fire's glow underneath for a while, climb,
	# drift and shear downwind, and dissipate into dithered wisps.
	var spec := _blast_spec()
	var reach := _reach()
	var flak := surface_material == "flak"
	# Thinning starts early and gently, so the column never hangs as a solid
	# mass: rims first, then the billows open into wisps.
	var gone := smoothstep(.40 if flak else .30,1.0,age/lifetime)
	var swell := .70 if flak else .42
	var smoke: Color = spec.smoke
	if flak:
		# The airburst's charge leaves a dark-brown puff that greys within a
		# few tenths of a second.
		smoke = FLAK_BURST.lerp(smoke,smoothstep(.03,.45,age))
	for index in range(_lobe_count()-1,-1,-1):
		var time := age-_lobe_shape[index].y
		var start := _fire_time(index)*.30
		if time <= start: continue
		var since := time-start
		var center := _lobe_center(index,time,reach)
		var radius := _lobe_radius(index,time,reach)*(.80+swell*(1.0-exp(-since*(1.4 if flak else 2.4))))*(1.0 if flak else .86)
		var warmth := clampf(1.0-since/(_fire_time(index)+.45),0.0,1.0)
		var tone := smoke.lightened(.07) if index%3 == 1 else (smoke.darkened(.08) if index%3 == 2 else smoke)
		var fade := clampf(gone*(1.0+float(index%3)*.07),0.0,1.0)
		var shear := clampf(_wind*.0035*time,-.4,.4)
		PixelArt.grid_smoke(self,center,radius,Color(PixelArt.smoke_tone(tone),1.0),index+seed_value,fade,warmth*warmth,shear)
	if flak and not reduced and age < FLAK_SHRAPNEL:
		# Shrapnel: dark fragments flung out of the burst as short streaks,
		# so an airburst reads as a detonation and not as a passing cloud.
		var travel := age/FLAK_SHRAPNEL
		for index in 8:
			var toward := Vector2.from_angle(float(index)*TAU/8.0+float(seed_value%11)*.17+float(index%2)*.2)
			var near := reach*(.55+2.9*(1.0-pow(1.0-travel,2.0)))*(.85+.06*float(index%3))
			var tail := reach*(.25+.45*(1.0-travel))
			PixelArt.grid_line(self,toward*(near-tail),toward*near,Color(.11,.095,.085,.95*(1.0-travel*travel)),2.0 if index%3 == 0 else 1.0)
	if surface_material == "explosion" and not is_nan(_ground) and float(spec.skirt) > 0.0:
		_draw_skirt(spec,reach)
		if not reduced and age < .42:
			# Dust snapped off the ground by the pressure front: low cel puffs
			# racing out along the surface ahead of the rolling skirt (a flat
			# ring here read as a thin pale ellipse on the ground).
			var front := age/.42
			var run := reach*(.6+3.4*(1.0-pow(1.0-front,2.0)))
			var dust := Color(PixelArt.smoke_tone(spec.dust).lightened(.08),.85)
			for side in 2:
				var sign_x := -1.0 if side == 0 else 1.0
				PixelArt.grid_cel(self,Vector2(sign_x*run,_ground-2.0-front*3.0),maxf(2.0,reach*.16*(1.0-front*.4)),dust,seed_value+5+side,clampf(front*1.1,0.0,.95),0.0,.55)

func _draw_skirt(spec: Dictionary, reach: float) -> void:
	# The pressure front rolls a dust skirt along the ground to both sides.
	var dust: Color = PixelArt.smoke_tone(spec.dust)
	var spread: float = spec.skirt
	for side in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		for wave in 2:
			var time := age-.04-.04*float(wave)
			if time <= 0.0: continue
			var travel := reach*(.40+.20*float(wave))+reach*1.7*spread*(1.0-exp(-time*4.0))*(1.0-.28*float(wave))
			var radius := reach*(.30-.07*float(wave))*sqrt(spread)*(.18+.92*(1.0-exp(-time*4.5)))
			var fade := clampf(smoothstep(.10,1.15,time)*.95+smoothstep(.5,1.0,age/lifetime),0.0,1.0)
			# A low, wide roll of dust that thins out quickly into dithered
			# wisps: it must not read as a boulder resting on the ground.
			PixelArt.grid_smoke(self,Vector2(sign_x*travel+_wind*.2*time,_ground-radius*.30-time*9.0),radius*1.25,Color(dust.lightened(.06),.85),seed_value+side*3+wave,clampf(fade+.12,0.0,1.0),0.0,0.0,.44)

func _draw_hot() -> void:
	if retired or _preset.is_empty(): return
	if surface_material in ["explosion","flak"]: _draw_fire()
	elif float(_preset.flash) > 0.0 and age < .06 and surface_material not in ["glass","arc"]:
		# Contact flash: a small white-hot cel star at the struck point (the
		# cold glass and arc hits keep their pale star on the glow layer).
		PixelArt.grid_fire(hot_layer,direction*2.0,float(_preset.flash)*.22*sqrt(power)*(1.0-age/.12),1.0-age/.10,1.0,seed_value)
	var cold := surface_material in ["glass","arc"]
	for bit in bits:
		if bit.age >= bit.life: continue
		if bit.get("burning",false):
			# A burning chunk: flames streaming back from its flight, cooling.
			var burnt: float = float(bit.age)/float(bit.life)
			var flight: Vector2 = bit.velocity
			PixelArt.grid_flame(hot_layer,Vector2(bit.pos).round()+Vector2(0,1),3.0+float(bit.size)*.8,5.0+float(bit.size)*2.2*(1.0-burnt*.5),.95-.65*burnt,PixelArt.flame_frame(age,int(float(bit.life)*40.0)),int(float(bit.life)*40.0),clampf(-flight.x*.025,-6.0,6.0))
		if bit.type != "sparks": continue
		var cooled: float = float(bit.age) / float(bit.life)
		if cooled > .92: continue
		var point: Vector2 = Vector2(bit.pos).round()
		var velocity: Vector2 = bit.velocity
		var ramp: Array = COLD_RAMP if cold else (EMBER_RAMP if surface_material == "explosion" else SPARK_RAMP)
		var head := _ramp(ramp,cooled)
		var tail := _ramp(ramp,cooled+.26)
		if surface_material == "explosion":
			# Embers cool from yellow to dull red as they fall.
			var drift := (velocity.normalized()*minf(4.0,velocity.length()*.02)).round()
			if drift != Vector2.ZERO: PixelArt.grid_line(hot_layer,point-drift,point,tail)
			hot_layer.draw_rect(Rect2(point,Vector2(2,2) if cooled < .35 else Vector2.ONE),head)
			continue
		# A hot head with a short streak in the next cooler band, one texel wide.
		var streak := (velocity.normalized()*minf(9.0 if surface_material == "flak" else 7.0,velocity.length()*.024)).round()
		if streak != Vector2.ZERO: PixelArt.grid_line(hot_layer,point-streak,point,tail)
		hot_layer.draw_rect(Rect2(point,Vector2(2,1) if cooled < .30 and absf(velocity.x) >= absf(velocity.y) else (Vector2(1,2) if cooled < .30 else Vector2.ONE)),head)

func _draw_fire() -> void:
	var reach := _reach()
	var flak := surface_material == "flak"
	# Ignition: a white-hot heart with short rays for two frames, then a
	# yellow-hot core that swells into the fireball; smaller when blasts follow
	# each other quickly or with reduced effects.
	var flash_life := .075 if flak else .11
	if age < flash_life:
		var swell := 1.0-age/flash_life
		var core := reach*(.70 if flak else .62)*(.75+.25*flash_scale)*(.85+.3*(1.0-swell))
		# A throttled or reduced flash never reaches the white heart.
		var full := flash_scale > .9 and not reduced
		var origin := direction*reach*(0.0 if flak else .22)
		if age < (.05 if flak else .05) and full:
			# Stubby flame tongues, not needle rays: a pixel-art starburst.
			var rays := 5 if flak else 7
			for index in rays:
				var toward := Vector2.from_angle(float(index)*TAU/float(rays)+float(seed_value%7)*.21-PI*.5)
				var length := core*(1.45+.25*float((index*5+seed_value)%3))
				PixelArt.grid_petal(hot_layer,origin+toward*core*.35,origin+toward*length,core*(.30 if flak else .36),Color("ffe9a8") if flak else Color("ffd27a"))
				PixelArt.grid_petal(hot_layer,origin+toward*core*.35,origin+toward*length*.82,core*.18,FIRE_HOT)
		if flak:
			# A flak shell's charge: a hard white-yellow flash, no fireball.
			PixelArt.grid_blob(hot_layer,origin,core,Color("ffe9a8") if full else Color("f2d48a"),seed_value)
			if full: PixelArt.grid_blob(hot_layer,origin,core*.58,Color("fffbe8"),seed_value+1)
		else:
			PixelArt.grid_fire(hot_layer,origin,core,(1.0 if full else .78)*(1.0 if age < .05 else .86),1.0,seed_value)
	# No outline ring here or anywhere: a thin pale circle read as an
	# interface overlay. Flak never burns on: its flash leaves the black puff.
	if flak: return
	for index in range(_lobe_count()-1,-1,-1):
		var time := age-_lobe_shape[index].y
		if time <= 0.0: continue
		# Outer billows burn cooler: one hot heart for the whole cluster
		# instead of a bright core in every billow.
		var heat := (1.0-time/_fire_time(index))*(1.0-.40*clampf(_lobe_offset[index].length(),0.0,1.0))
		if heat <= 0.02: continue
		var center := _lobe_center(index,time,reach)
		var radius := _lobe_radius(index,time,reach)*(.60+.42*heat)*(1.06 if index == 0 else .94)
		if not reduced and index < (2 if flak else 3) and heat > .22:
			# Tongues licking up from the top of the fireball, so it reads as
			# burning gas instead of a disc. Drawn first: the ball covers
			# their roots and only the licks above its rim show.
			for tongue in 2:
				var across := (float(tongue)-.5)*radius*.80+float((seed_value+index*3)%5-2)
				var tall := radius*(1.20+.30*float((seed_value+index+tongue)%3))*smoothstep(.22,.75,heat)
				PixelArt.grid_flame(hot_layer,center+Vector2(across,-radius*.42),radius*.62,tall,heat,PixelArt.flame_frame(age,seed_value+index*2+tongue),seed_value+index*5+tongue,_wind*.02*tall/maxf(radius,1.0))
		# The fire breaks up into the smoke beneath it as it cools.
		PixelArt.grid_fire(hot_layer,center,radius,heat,1.0,index+seed_value,smoothstep(.40,.0,heat)*.85)

func _draw_glow() -> void:
	# Additive layer: everything here adds light and is absent in reduced mode.
	if retired or _preset.is_empty() or reduced: return
	var hot: Color = _preset.hot
	if surface_material in ["explosion","flak"]:
		# No pressure ring of any kind: an outline circle running out of the
		# blast read as a vector overlay, not as heat. The pressure front is
		# carried by the heated air (the glow below), the shrapnel and debris
		# thrown out, and on the ground by the rolling dust skirt.
		var glow_time := _fire_time(0)*1.8
		if surface_material == "flak": glow_time = .16
		if age < glow_time:
			var heat := 1.0-age/glow_time
			var reach := _reach()
			var origin := _lobe_center(0,maxf(age-_lobe_shape[0].y,.001),reach)
			# Flak lights the air white-yellow for a moment; fire glows amber.
			var tint := Color(1.0,.92,.62) if surface_material == "flak" else Color(1.0,.56,.24)
			PixelArt.grid_halo(glow_layer,origin,reach*(1.45+.45*(1.0-heat)),Color(tint,(.12+.24*PixelArt.night())*heat*flash_scale),seed_value)
	else:
		var radius: float = float(_preset.flash)*sqrt(power)
		var fade := maxf(0.0,1.0-age/.12)
		if radius > 0.0 and fade > 0.0:
			PixelArt.grid_blob(glow_layer,Vector2.ZERO,radius*.55,Color(hot,.16*fade),seed_value,1.0-fade)
			# A two-frame contact star along the surface makes the hit point read.
			var strike := maxf(0.0,1.0-age/.05)
			if strike > 0.0:
				var side := direction.orthogonal()
				for ray in 3:
					var toward := direction*.50 if ray == 0 else ((direction+side*1.5).normalized()*.42 if ray == 1 else (direction-side*1.5).normalized()*.42)
					PixelArt.grid_line(glow_layer,(toward*radius*.18).round(),(toward*radius).round(),Color(hot,strike*.9),2 if power > 1.0 else 1)
			if surface_material == "arc":
				PixelArt.grid_shockwave(glow_layer,Vector2.ZERO,5+age*170*sqrt(power),Color(hot,fade*.32),seed_value)
				for index in 3:
					var axis := direction.rotated(index*TAU/3) * radius
					var bend := (axis*0.35+axis.orthogonal()*0.18).round()
					var kink := (axis*0.62-axis.orthogonal()*0.15).round()
					PixelArt.grid_line(glow_layer, Vector2.ZERO, bend, Color(hot,fade*0.85))
					PixelArt.grid_line(glow_layer, bend, kink, Color(hot,fade*0.85))
					PixelArt.grid_line(glow_layer, kink, axis.round(), Color(hot,fade*0.85))
	for bit in bits:
		if bit.type != "sparks" or bit.age >= bit.life: continue
		var left: float = 1.0-float(bit.age)/float(bit.life)
		if left < .5: continue
		var tone: Color = FIRE_ORANGE if surface_material in ["explosion","flak"] else hot
		glow_layer.draw_rect(Rect2(Vector2(bit.pos).round()-Vector2.ONE,Vector2(3,3)),Color(tone,.26*(left-.5)*2.0))
