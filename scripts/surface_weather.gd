class_name SurfaceWeather
extends Node2D
## Secondary contacts share actual walkable support with rain. Deposits and
## tracks retain support samples so removed floors never leave floating marks.
const GroundContacts := preload("res://scripts/ground_contact_effects.gd")

const MAX_PARTICLES := 160
const MAX_SPLASHES := 52
const MAX_PATCHES := 120
const MAX_FOOTPRINTS := 48
const PATCH_GRID := 24.0
const WATER := Color("8daeb1")
const WATER_LIGHT := Color("bed0c7")
const WET_STONE := Color("243334")
const WET_EARTH := Color("302c25")
const MUD := Color("63523c")

var weather: Node2D
var patches: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var splashes: Array[Dictionary] = []
var footprints: Array[Dictionary] = []
var elapsed := 0.0
var rain_contact_count := 0
var footstep_count := 0
var ground: RefCounted
var _last_actor_contact: Dictionary = {}
var _support_clock := 0.0
var _support_cursor := 0
var _presentation_frame := -1
var _presentation_delta := 0.0
var _rng := RandomNumberGenerator.new()
var _surface_layer: Node2D
var _spray_layer: Node2D

func _ready() -> void:
	_rng.seed = 194609
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground = GroundContacts.new()
	ground.surfaces = self
	_surface_layer = _make_layer("WetGroundAndFootprints", 12, _draw_surfaces)
	_spray_layer = _make_layer("ContactSpray", 19, _draw_spray)

func _make_layer(title: String, depth: int, paint: Callable) -> Node2D:
	var result := Node2D.new()
	result.name = title
	result.z_as_relative = false
	result.z_index = depth
	result.draw.connect(paint)
	add_child(result)
	return result

func _reduced() -> bool:
	return is_instance_valid(weather) and bool(weather.get("reduced_effects"))

func on_rain_hit(hit: Dictionary, velocity: Vector2, depth: float = 1.0) -> void:
	if hit.is_empty() or not hit.has("position") or _reduced():
		return
	var point: Vector2 = hit.position
	var normal: Vector2 = hit.get("normal", Vector2.UP)
	if normal.length_squared() < 0.25:
		normal = Vector2.UP
	else:
		normal = normal.normalized()
	var surface_material: String = str(hit.get("material", "concrete"))
	var moving := _moving_hit(hit)
	rain_contact_count += 1
	if not moving and not bool(hit.get("weather_prop", false)) and normal.y < -0.60 and surface_material in ["soil", "concrete", "metal"]:
		_deposit(hit, normal, surface_material)
	# Every contact wets its support; only some contacts throw a visible crown.
	# This keeps foreground impacts distinct from distant fine rain.
	var prominence := clampf(depth, 0.3, 1.4)
	var rebound := 1.0
	match surface_material:
		"cloth": rebound = 0.16
		"wood": rebound = 0.48
		"soil": rebound = 0.62
		"actor": rebound = 0.70
		"metal": rebound = 1.15
	if _rng.randf() > (0.45 + prominence * 0.25) * rebound:
		return
	var kind := "glance" if surface_material == "glass" or absf(normal.x) > 0.45 else "crown"
	if surface_material == "cloth":
		kind = "soak"
	_add_splash(point, normal, kind, prominence * rebound, hit.get("collider"), surface_material)
	var tangent := Vector2(-normal.y, normal.x)
	var reflected := velocity.bounce(normal).normalized()
	var count := 2 if prominence > 0.7 else 1
	if surface_material == "cloth":
		count = 0
	elif surface_material in ["wood", "soil"]:
		count = 1
	for index in count:
		var motion := (normal * _rng.randf_range(17, 38) + tangent * _rng.randf_range(-24, 24)) * rebound
		if kind == "glance":
			motion = reflected * _rng.randf_range(28, 53) + tangent * _rng.randf_range(-8, 8)
		_spawn_drop(point + normal * 1.5, motion, "mud" if surface_material == "soil" else "water", _rng.randf_range(0.14, 0.28), prominence * rebound, hit.get("collider") as Node, surface_material)

func _moving_hit(hit: Dictionary) -> bool:
	var collider: Object = hit.get("collider")
	return bool(hit.get("moving", false)) or collider is CharacterBody2D or collider is RigidBody2D or str(hit.get("material", "")) == "actor"

func _deposit(hit: Dictionary, normal: Vector2, surface_material: String) -> void:
	var point: Vector2 = hit.position
	var cell := Vector2i(floori(point.x / PATCH_GRID), floori(point.y / 12.0))
	var collider: Object = hit.get("collider")
	var collider_id := collider.get_instance_id() if is_instance_valid(collider) else 0
	for patch in patches:
		if patch.cell == cell and patch.collider_id == collider_id and patch.material == surface_material:
			patch.wetness = minf(1.0, float(patch.wetness) + 0.075)
			patch.last_rain = elapsed
			return
	if patches.size() >= MAX_PATCHES:
		# Reclaim the least wet patch; storage is independent of session duration.
		var least := 0
		for index in range(1, patches.size()):
			if float(patches[index].wetness) < float(patches[least].wetness):
				least = index
		patches.remove_at(least)
	var half_width := _supported_half_width(point, normal, surface_material, collider_id)
	if half_width < 2.0:
		return
	patches.append({"point": point, "normal": normal, "cell": cell, "collider_id": collider_id,
		"support": weakref(collider) if is_instance_valid(collider) else null,
		"material": surface_material, "wetness": 0.26, "width": half_width,
		"seed": _rng.randi_range(0, 65535), "last_rain": elapsed})

func _supported_half_width(point: Vector2, normal: Vector2, surface_material: String, collider_id: int) -> float:
	if not is_instance_valid(weather) or not weather.has_method("trace_rain"):
		return 0.0
	var tangent := Vector2(-normal.y, normal.x)
	var width := 2.0
	for extent in [4.0, 8.0, 11.0]:
		var both_supported := true
		for side in [-1.0, 1.0]:
			var sample: Vector2 = point + tangent * float(extent) * float(side)
			var hit: Dictionary = weather.trace_rain(sample + normal * 4.0, sample - normal * 5.0, false)
			if not _same_support(hit, sample, surface_material, collider_id, 3.0):
				both_supported = false
				break
		if not both_supported:
			break
		width = extent
	return width

func _same_support(hit: Dictionary, point: Vector2, surface_material: String, collider_id: int, tolerance: float = 5.0) -> bool:
	if hit.is_empty() or not hit.has("position") or str(hit.get("material", "")) != surface_material:
		return false
	if Vector2(hit.position).distance_to(point) > tolerance:
		return false
	var collider: Object = hit.get("collider")
	if collider_id != 0 and (not is_instance_valid(collider) or collider.get_instance_id() != collider_id):
		return false
	return not _moving_hit(hit)

func surface_state_at(feet: Vector2) -> Dictionary:
	var result := {"wetness": 0.0, "mud": 0.0, "material": "dry", "kind": "dry", "distance": INF, "support_y": INF}
	if ground != null:
		var deposited: Dictionary = ground.state_at(feet)
		if not deposited.is_empty():
			result.merge(deposited, true)
	for patch in patches:
		var offset: Vector2 = feet - Vector2(patch.point)
		var normal: Vector2 = patch.normal
		var tangent := Vector2(-normal.y, normal.x)
		# A floor above or below the feet must never wet the wrong actor.
		if absf(offset.dot(normal)) > 7.0 or absf(offset.dot(tangent)) > float(patch.width) + 5.0:
			continue
		if float(patch.wetness) > float(result.wetness):
			result.wetness = float(patch.wetness)
			result.material = str(patch.material)
			result.mud = float(patch.wetness) if patch.material == "soil" else 0.0
			result.distance = offset.dot(normal)
			result.support_y = Vector2(patch.point).y
			result.kind = "water"
	return result

func sample_contact(feet: Vector2) -> Dictionary:
	var missing := {"supported": false, "kind": "dry", "material": "dry", "wetness": 0.0, "mud": 0.0,
		"distance": INF, "support_y": INF, "point": feet, "normal": Vector2.UP}
	if not feet.is_finite():
		return missing
	# Boot support comes from walkable physics, independently of decorative
	# rain silhouettes such as hanging cloth and machinery above the floor.
	var hit: Dictionary = {}
	if is_inside_tree():
		var query := PhysicsRayQueryParameters2D.create(feet+Vector2(0,-8),feet+Vector2(0,9),3)
		hit = get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var collision = weather.get("collision") if is_instance_valid(weather) else null
			hit["material"] = collision.material_for(hit.collider,hit.position) if collision is RainCollision else "concrete"
	if hit.is_empty(): hit = _near_support(feet)
	if hit.is_empty() or _moving_hit(hit) or bool(hit.get("weather_prop", false)):
		return missing
	var point: Vector2 = hit.position
	var normal: Vector2 = hit.get("normal", Vector2.UP)
	if normal.length_squared() < 0.25:
		return missing
	normal = normal.normalized()
	var distance := (feet - point).dot(normal)
	if normal.y >= -0.60 or absf(distance) > 9.0:
		return missing
	if ground != null:
		ground.prepare()
	var state := surface_state_at(feet)
	var surface_material := str(hit.get("material", "concrete"))
	var contact_kind := "water" if float(state.wetness) >= 0.12 else ("metal" if surface_material == "metal" else "dry")
	if state.get("kind", "") == "ice" or (ground != null and ground.environment == "frozen_rail_yard" and ground.is_outside_ground(point, surface_material)):
		contact_kind = "ice"
	var collider: Object = hit.get("collider")
	state.merge({"supported": true, "point": point, "normal": normal, "distance": distance, "support_y": point.y,
		"kind": contact_kind, "material": surface_material, "collider": collider,
		"collider_id": collider.get_instance_id() if is_instance_valid(collider) else 0,
		"support": weakref(collider) if is_instance_valid(collider) else null}, true)
	return state

func footstep(feet: Vector2, strength: float = 1.0, actor: Node = null) -> Dictionary:
	return contact_event(feet, strength, actor)

func contact_event(feet: Vector2, strength: float = 1.0, actor: Node = null, state: Dictionary = {}) -> Dictionary:
	if state.is_empty():
		state = sample_contact(feet)
	if not bool(state.get("supported", false)) or absf(float(state.get("distance", INF))) > 2.5 or not is_finite(strength):
		return state
	if state.get("support") != null and state.support.get_ref() == null:
		state.supported = false
		return state
	# The contact description remains available to audio while F3 suppresses VFX.
	if _reduced() or get_tree().paused:
		return state
	if is_instance_valid(actor):
		var actor_id := actor.get_instance_id()
		if elapsed - float(_last_actor_contact.get(actor_id, -1.0)) < 0.12:
			return state
		_last_actor_contact[actor_id] = elapsed
		if _last_actor_contact.size() > 96:
			for key in _last_actor_contact.keys():
				if elapsed - float(_last_actor_contact[key]) > 1.0:
					_last_actor_contact.erase(key)
			while _last_actor_contact.size() > 96:
				_last_actor_contact.erase(_last_actor_contact.keys()[0])
	footstep_count += 1
	if state.kind != "water":
		ground.emit_contact(state, strength)
		return state
	var point: Vector2 = state.point
	var normal: Vector2 = state.normal
	var wetness := float(state.wetness)
	var muddy := float(state.mud) > 0.15
	var kind := "mud" if muddy else "water"
	var weight := clampf(strength, 0.2, 2.2)
	var count := clampi(roundi(2.0 + wetness * weight * 3.0), 2, 7)
	for index in count:
		var motion := Vector2(_rng.randf_range(-34, 34), -_rng.randf_range(18, 48)) * sqrt(weight)
		_spawn_drop(point + normal * 2.0, motion, kind, _rng.randf_range(0.16, 0.35), wetness, actor, str(state.material))
	_add_splash(point, normal, "ripple", wetness, null)
	var spray_material := "soil" if muddy else ("metal" if state.material == "metal" else "concrete")
	_add_splash(point, normal, "foot_fan", wetness * minf(weight, 1.5), state.get("collider"), spray_material)
	if muddy:
		if footprints.size() >= MAX_FOOTPRINTS:
			footprints.pop_front()
		footprints.append({"point": point, "normal": normal, "age": 0.0, "life": 9.0,
			"size": clampf(3.0 * sqrt(weight), 2.0, 5.0), "wetness": wetness,
			"support": state.get("support"), "collider_id": int(state.get("collider_id", 0)), "material": str(state.material)})
	return state

func emit_drip(point: Vector2, velocity: Vector2 = Vector2(0, 20), wetness: float = 1.0, actor: Node = null) -> void:
	if _reduced() or wetness < 0.1:
		return
	_spawn_drop(point, velocity, "water", 0.42, clampf(wetness, 0.0, 1.0), actor)

func _near_support(point: Vector2) -> Dictionary:
	if not is_instance_valid(weather) or not weather.has_method("trace_rain"):
		return {}
	return weather.trace_rain(point + Vector2(0, -8), point + Vector2(0, 9), false)

func _spawn_drop(point: Vector2, velocity: Vector2, kind: String, lifetime: float, strength: float, actor: Node = null, surface_material: String = "concrete") -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	particles.append({"point": point, "last": point, "velocity": velocity, "kind": kind,
		"age": 0.0, "life": lifetime, "strength": strength, "material": surface_material,
		"owner": weakref(actor) if is_instance_valid(actor) else null})

func _add_splash(point: Vector2, normal: Vector2, kind: String, strength: float, collider: Object, surface_material: String = "concrete") -> void:
	if splashes.size() >= MAX_SPLASHES:
		return
	var attached := collider is Node2D
	splashes.append({"point": point, "normal": normal, "kind": kind, "strength": strength, "material": surface_material,
		"age": 0.0, "life": 0.34 if kind == "ripple" else 0.19,
		"attachment": weakref(collider) if attached else null,
		"local": (collider as Node2D).to_local(point) if attached else Vector2.ZERO})

func _physics_process(delta: float) -> void:
	_presentation_delta += delta
	var frame := Engine.get_process_frames()
	if _presentation_frame == frame: return
	_presentation_frame = frame
	advance(_presentation_delta)
	_presentation_delta = 0.0

func advance(delta: float) -> void:
	if get_tree().paused:
		return
	elapsed += delta
	ground.advance(delta, _reduced())
	if _reduced():
		particles.clear()
		splashes.clear()
	else:
		_step_particles(delta)
	for index in range(splashes.size() - 1, -1, -1):
		var splash := splashes[index]
		splash.age += delta
		if splash.attachment != null:
			var attached: Object = splash.attachment.get_ref()
			if is_instance_valid(attached) and attached is Node2D:
				splash.point = attached.to_global(splash.local)
			else:
				splash.age = splash.life
		if splash.age >= splash.life:
			splashes.remove_at(index)
	for index in range(footprints.size() - 1, -1, -1):
		footprints[index].age += delta
		if footprints[index].age >= footprints[index].life or (footprints[index].get("support") != null and footprints[index].support.get_ref() == null):
			footprints.remove_at(index)
	for index in range(patches.size() - 1, -1, -1):
		var patch := patches[index]
		patch.wetness = maxf(0.0, float(patch.wetness) - delta * 0.009)
		if patch.wetness <= 0.02 or (patch.support != null and not is_instance_valid(patch.support.get_ref())):
			patches.remove_at(index)
	_support_clock += delta
	if _support_clock >= 0.1:
		_support_clock = 0.0
		_validate_supports()
	_redraw()

func _step_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle := particles[index]
		particle.age += delta
		if particle.age >= particle.life:
			particles.remove_at(index)
			continue
		var old: Vector2 = particle.point
		particle.last = old
		particle.velocity += Vector2(4.0, 260.0) * delta
		var next: Vector2 = old + Vector2(particle.velocity) * delta
		var hit: Dictionary = {}
		if is_instance_valid(weather) and weather.has_method("trace_rain"):
			var owner_actor: Node = null
			if particle.owner != null and float(particle.age) < 0.06:
				owner_actor = particle.owner.get_ref() as Node
			hit = weather.trace_rain(old, next, true, owner_actor)
		if not hit.is_empty():
			if particle.kind == "water":
				_add_splash(hit.position, hit.get("normal", Vector2.UP), "ripple", float(particle.strength) * 0.55, hit.get("collider"), str(hit.get("material", "concrete")))
			particles.remove_at(index)
		else:
			particle.point = next

func _validate_supports() -> void:
	# Four support probes per tenth of a second, irrespective of rain density.
	for unused in 4:
		if patches.is_empty():
			break
		_support_cursor %= patches.size()
		var patch := patches[_support_cursor]
		var normal: Vector2 = patch.normal
		var point: Vector2 = patch.point
		var hit: Dictionary = {}
		if is_instance_valid(weather) and weather.has_method("trace_rain"):
			hit = weather.trace_rain(point + normal * 4.0, point - normal * 6.0, false)
		if not _same_support(hit, point, patch.material, int(patch.collider_id)):
			patches.remove_at(_support_cursor)
		else:
			_support_cursor += 1
	# Footprints are short-lived, but must also disappear with their support.
	for index in range(footprints.size() - 1, -1, -1):
		var mark := footprints[index]
		if not _same_support(_near_support(mark.point), mark.point, str(mark.get("material", "soil")), int(mark.get("collider_id", 0)), 2.0):
			footprints.remove_at(index)

func _redraw() -> void:
	if is_instance_valid(_surface_layer):
		_surface_layer.queue_redraw()
	if is_instance_valid(_spray_layer):
		_spray_layer.queue_redraw()

func _draw_surfaces() -> void:
	ground.draw_ground(_surface_layer, elapsed, _reduced())
	for patch in patches:
		var at := _surface_layer.to_local(patch.point).round()
		var normal: Vector2 = patch.normal
		var tangent := Vector2(-normal.y, normal.x)
		var width := float(patch.width)
		var wetness := float(patch.wetness)
		var muddy: bool = patch.material == "soil"
		var tint := WET_EARTH if muddy else WET_STONE
		tint.a = wetness * (0.67 if muddy else 0.43)
		# An irregular two-pixel surface strip respects the actual support tangent.
		var points := PackedVector2Array([at - tangent * width, at - tangent * width * 0.35 - normal,
			at + tangent * width * 0.55, at + tangent * width, at + tangent * (width - 2) - normal * 2,
			at - tangent * (width - 2) - normal * 2])
		_surface_layer.draw_colored_polygon(points, tint)
		if wetness > 0.45:
			var phase := float(int(patch.seed) % 23) * 0.21
			var shimmer := 0.5 if _reduced() else 0.5 + sin(elapsed * 1.4 + phase) * 0.5
			var shine := WATER
			shine.a = (wetness - 0.28) * (0.18 + shimmer * 0.15) * (0.55 if muddy else 1.0)
			var shine_center := at + tangent * sin(phase) * width * 0.2
			_surface_layer.draw_line((shine_center - tangent * width * 0.52).round(), (shine_center + tangent * width * 0.36).round(), shine, 1.0)
	for mark in footprints:
		var at := _surface_layer.to_local(mark.point).round()
		var normal: Vector2 = mark.normal
		var tangent := Vector2(-normal.y, normal.x)
		var alpha := (1.0 - float(mark.age) / float(mark.life)) * float(mark.wetness) * 0.6
		var tint := Color(0.10, 0.12, 0.10, alpha)
		_surface_layer.draw_line(at - tangent * float(mark.size), at + tangent * float(mark.size), tint, 2.0)
		_surface_layer.draw_line(at - normal * 2, at + tangent * 2 - normal * 2, tint, 1.0)

func _draw_spray() -> void:
	if _reduced():
		return
	ground.draw_contacts(_spray_layer)
	for splash in splashes:
		var at := _spray_layer.to_local(splash.point).round()
		var normal: Vector2 = splash.normal
		var tangent := Vector2(-normal.y, normal.x)
		var phase := float(splash.age) / float(splash.life)
		var width := (1.0 + phase * 4.0) * clampf(float(splash.strength), 0.5, 1.2)
		var tint := WATER_LIGHT if splash.material == "metal" else (MUD if splash.material == "soil" else WATER)
		tint.a = (1.0 - phase) * 0.52 * minf(float(splash.strength), 1.0)
		if splash.kind == "soak":
			_spray_layer.draw_rect(Rect2(at, Vector2(2, 1)), Color(0.12, 0.19, 0.19, tint.a))
		elif splash.kind == "ripple":
			_spray_layer.draw_line((at - tangent * width).round(), (at - tangent * width * 0.50).round(), tint, 1.0)
			_spray_layer.draw_line((at + tangent * width * 0.50).round(), (at + tangent * width).round(), tint, 1.0)
		elif splash.kind == "foot_fan":
			var height := sin(phase * PI) * 6.0 * minf(float(splash.strength), 1.3)
			for side in [-1.0, 1.0]:
				for finger in 2:
					var tip := at + tangent * (width + 1.0 + finger * 2.0) * float(side) + normal * height * (1.0 - finger * 0.3)
					_spray_layer.draw_line((at + tangent * float(side) * 2.0).round(), tip.round(), tint, 1.0)
		else:
			var height := sin(phase * PI) * 3.5 * minf(float(splash.strength), 1.3)
			for side in [-1.0, 1.0]:
				var root_point: Vector2 = at + tangent * float(side)
				var tip: Vector2 = at + tangent * width * float(side) + normal * height
				_spray_layer.draw_line(root_point.round(), tip.round(), tint, 1.0)
	for particle in particles:
		var at := _spray_layer.to_local(particle.point).round()
		var fade := 1.0 - pow(float(particle.age) / float(particle.life), 3.0)
		if particle.kind == "mud":
			var tint := MUD
			tint.a = fade * 0.82
			var size := Vector2.ONE if float(particle.strength) < 0.7 else Vector2(2, 2)
			_spray_layer.draw_rect(Rect2(at, size), tint)
			if size.y > 1:
				_spray_layer.draw_rect(Rect2(at + Vector2(0, 1), Vector2.ONE), Color(0.18, 0.18, 0.14, fade))
		else:
			var tint := WATER_LIGHT if particle.material == "metal" else WATER
			tint.a = fade * (0.32 + float(particle.strength) * 0.24)
			var tail := (Vector2(particle.velocity).normalized() * 1.7).round()
			_spray_layer.draw_line(at - tail, at, tint, 1.0)
