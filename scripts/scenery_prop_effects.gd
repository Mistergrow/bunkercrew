extends Node2D
## Local, bounded foliage and wreck presentation. Damage remains in reactions.
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const SurfaceArt := preload("res://scripts/station_surface_art.gd")
const FALL_SHADER := preload("res://shaders/scenery_fall.gdshader")
const FIRE_LIGHTING := preload("res://scripts/scenery_fire_lighting.gd")
const MAX_PARTICLES := 144
const REDUCED_PARTICLES := 28
const MAX_FIRE_SOURCES := 18
const MAX_FALL_FRAGMENTS := 6
const FALL_SECONDS := 1.05
const FALL_FADE_SECONDS := .28
const GROWTH := ["grass", "frost_grass", "reeds", "brush", "vines"]
const BURN_SECONDS := preload("res://scripts/scenery_damage.gd").BURN_SECONDS
## A standing tree catches from the foot up: each fire anchor lights after
## IGNITE_BASE plus IGNITE_CLIMB times its share of the tree's height, and its
## flames grow in over IGNITE_GROW seconds (presentation of the replicated
## burn state; damage and burn time are untouched).
const IGNITE_BASE := .10
const IGNITE_CLIMB := 1.15
const IGNITE_GROW := .38
var props: Node2D
var particles: Array[Dictionary] = []
var elapsed := 0.0
var emitted := 0
var culled := 0
var burst_count := 0
var _seen: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _draw_clock := 0.0
var _fire_clock := 0.0
var _entry_count := -1
var _reduced := false
var _gust := 0.0
var _bounds := Rect2()
var _origins: Array[Dictionary] = []
var _sound_delay := 0.0
var _fall_fragments: Dictionary = {}
var fire_lighting: Node2D
## Flames and embers are self-lit (unlit grid layer); their glow is additive.
var flame_layer: Node2D
var glow_layer: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Smoke from burning props is drawn as texel-grid cel puffs; flames,
	# debris and particles keep their own drawing (they pass through).
	material = PixelArt.grid_material(PixelArt.GRID_LIT)
	glow_layer = Node2D.new()
	glow_layer.name = "FireGlow"
	glow_layer.material = PixelArt.grid_material(PixelArt.GRID_ADD)
	glow_layer.draw.connect(_draw_glow)
	add_child(glow_layer)
	flame_layer = Node2D.new()
	flame_layer.name = "Flames"
	flame_layer.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
	flame_layer.draw.connect(_draw_flames)
	add_child(flame_layer)
	fire_lighting = FIRE_LIGHTING.new()
	fire_lighting.name = "SceneryFireLighting"
	fire_lighting.effects = self
	add_child(fire_lighting)
	reset()

func reset() -> void:
	_clear_fall_fragments()
	if is_instance_valid(fire_lighting): fire_lighting.reset()
	particles.clear()
	_seen.clear()
	_origins.clear()
	elapsed = 0.0
	emitted = 0
	culled = 0
	burst_count = 0
	_draw_clock = 0.0
	_fire_clock = 0.0
	_sound_delay = 0.0
	_entry_count = -1
	_rng.seed = 217091 + (str(props.get("environment_id")).hash() if is_instance_valid(props) else 0)
	# Smoke takes the tint of this world's sky.
	if is_instance_valid(props): PixelArt.atmosphere_from(props.get("game"))
	_redraw()

func sync_replica(first_snapshot: bool) -> void:
	if not first_snapshot or not is_instance_valid(props) or not is_instance_valid(props.get("reactions")):
		return
	# A joining client receives the current world, not its historical impacts.
	if props.has_method("sync_replica"): props.sync_replica(true)
	particles.clear()
	_clear_fall_fragments()
	_origins.clear()
	_seen.clear()
	_entry_count = props.entries.size()
	for entry: Dictionary in props.entries:
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if not state.is_empty(): _seen[int(entry.index)] = _initial_record(entry, state)
	if is_instance_valid(fire_lighting): fire_lighting.reset()
	_redraw()

func _redraw() -> void:
	queue_redraw()
	if is_instance_valid(flame_layer): flame_layer.queue_redraw()
	if is_instance_valid(glow_layer): glow_layer.queue_redraw()

func _initial_record(entry: Dictionary, state: Dictionary) -> Dictionary:
	return {"serial":int(state.get("serial", 0)), "hp":float(state.get("hp", 1)),
		"broken":bool(state.get("broken", false)), "fall_age":FALL_SECONDS,
		"direction":_fall_direction(state, int(entry.index)), "ambient":_rng.randf_range(0.5, 2.8),
		"charred":bool(state.get("charred", false)) or bool(state.get("burning", false)),
		# A fire already burning when first seen (a joining guest, a world that
		# starts in flames) shows at full height at once.
		"ignite":99.0 if bool(state.get("burning", false)) else 0.0}

func _process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(props) or not is_finite(delta) or delta <= 0:
		return
	if not is_instance_valid(props.get("reactions")):
		return
	var entries: Array = props.entries
	if _entry_count >= 0 and _entry_count != entries.size():
		reset()
	_entry_count = entries.size()
	_reduced = props.reduced() if props.has_method("reduced") else false
	_bounds = props.visible_bounds if props.get("visible_bounds") is Rect2 else get_viewport_rect()
	_gust = _wind_strength()
	elapsed += delta
	_sound_delay = maxf(0.0, _sound_delay - delta)
	_update_particles(delta)
	_update_fall_fragments(delta)
	var fire_due := false
	_fire_clock += delta
	if _fire_clock >= (0.48 if _reduced else 0.16):
		_fire_clock = 0.0
		fire_due = true
	var fire_budget := 3 if _reduced else MAX_FIRE_SOURCES
	for entry: Dictionary in entries:
		var index := int(entry.index)
		var state: Dictionary = props.reactions.state_for(index)
		if state.is_empty():
			continue
		var first := not _seen.has(index)
		if first:
			_seen[index] = _initial_record(entry, state)
		var record: Dictionary = _seen[index]
		record.charred = bool(record.charred) or bool(state.get("charred", false)) or bool(state.get("burning", false))
		if bool(state.get("burning", false)):
			# Time since ignition: the local clock, never behind the replicated
			# burn time already spent (a paused or late-joining view catches up).
			record.ignite = maxf(float(record.get("ignite", 0.0)) + delta, BURN_SECONDS - float(state.get("burn_left", BURN_SECONDS)))
		else: record.ignite = 0.0
		var became_broken: bool = not record.broken and bool(state.get("broken", false))
		var changed: bool = int(record.serial) != int(state.get("serial", 0))
		var visible_entry := _visible(entry)
		if became_broken:
			record.fall_age = 0.0
			record.direction = _fall_direction(state, index)
			if visible_entry and not _reduced and entry.kind == "tree":
				_start_fall_fragment(entry, state, float(record.direction))
		if not first and visible_entry and changed and (became_broken or float(state.get("hp", 0)) < float(record.hp) - 0.01):
			_hit_burst(entry, state, became_broken)
		record.serial = int(state.get("serial", 0))
		record.hp = float(state.get("hp", 0))
		record.broken = bool(state.get("broken", false))
		record.fall_age = minf(FALL_SECONDS, float(record.fall_age) + delta)
		if not visible_entry:
			continue
		if not record.broken and entry.kind == "tree" and not _reduced and not bool(state.get("burning", false)):
			record.ambient -= delta * (0.20 + _gust)
			if float(record.ambient) <= 0 and _gust > 0.28:
				record.ambient = _rng.randf_range(0.75, 3.6)
				_emit_foliage(entry, _canopy_point(entry, _rng.randi()), false)
		if bool(state.get("burning", false)) and fire_due and fire_budget > 0:
			var points := fire_points(entry, state)
			for point: Vector2 in points:
				if fire_budget <= 0:
					break
				if ignition(entry, state, point) < .5: continue
				fire_budget -= 1
				if not _reduced:
					_spawn("smoke", point + Vector2(_rng.randf_range(-3, 3), -16), Vector2(_gust * 8, -16 - _rng.randf() * 7), entry, 1.5 + _rng.randf() * 0.9)
				_spawn("ember", point + Vector2(0, -3), Vector2(_gust * 12 + _rng.randf_range(-5, 5), -26 - _rng.randf() * 19), entry, .5 + _rng.randf() * .55)
	var budget := REDUCED_PARTICLES if _reduced else MAX_PARTICLES
	while particles.size() > budget:
		particles.pop_front()
	fire_lighting.update_lighting(delta)
	_draw_clock += delta
	if _draw_clock >= (1.0 / 12.0 if _reduced else 1.0 / 30.0):
		_draw_clock = 0.0
		_redraw()

func _wind_strength() -> float:
	var game = props.get("game")
	if is_instance_valid(game) and is_instance_valid(game.get("weather")) and game.weather.has_method("wind_strength"):
		return clampf(float(game.weather.wind_strength()), 0.0, 1.5)
	return clampf(float(props.get("_gust_strength")) if props.get("_gust_strength") != null else 0.6, 0.0, 1.5)

func _start_fall_fragment(entry: Dictionary, state: Dictionary, direction: float) -> void:
	if _fall_fragments.size() >= MAX_FALL_FRAGMENTS or _fall_fragments.has(int(entry.index)):
		return
	var source: MeshInstance2D = null
	for tree: MeshInstance2D in props.tree_nodes:
		if int(tree.get_meta("prop_index", -1)) == int(entry.index):
			source = tree
			break
	if source == null or source.mesh == null or source.texture == null:
		return
	var pivot := Node2D.new()
	pivot.name = "FallingCrown%02d" % int(entry.index)
	pivot.position = Vector2(entry.position) + Vector2(0, -18)
	pivot.show_behind_parent = true
	add_child(pivot)
	var crown := MeshInstance2D.new()
	crown.mesh = source.mesh
	crown.texture = source.texture
	crown.scale = source.scale
	crown.position = Vector2(0, 18)
	crown.modulate = source.modulate
	if bool(state.get("charred", false)):
		crown.modulate = Color(entry.tint).darkened(.52)
	var cut_material := ShaderMaterial.new()
	cut_material.shader = FALL_SHADER
	cut_material.set_shader_parameter("cut_local_y", -18.0 / maxf(.001, source.scale.y))
	cut_material.set_shader_parameter("ground_y", props.to_global(entry.position).y)
	cut_material.set_shader_parameter("opacity", 1.0)
	crown.material = cut_material
	pivot.add_child(crown)
	_fall_fragments[int(entry.index)] = {"pivot":pivot, "mesh":crown, "material":cut_material,
		"age":0.0, "direction":direction}

func _update_fall_fragments(delta: float) -> void:
	for index: int in _fall_fragments.keys():
		var fragment: Dictionary = _fall_fragments[index]
		fragment.age += delta
		if _reduced or float(fragment.age) >= FALL_SECONDS + FALL_FADE_SECONDS or index >= props.entries.size() or not _visible(props.entries[index]):
			fragment.pivot.queue_free()
			_fall_fragments.erase(index)
			continue
		var progress := clampf(float(fragment.age) / FALL_SECONDS, 0.0, 1.0)
		fragment.pivot.rotation = float(fragment.direction) * (progress * progress * .5 + progress * .5) * PI * .5
		fragment.material.set_shader_parameter("opacity", 1.0 - clampf((float(fragment.age) - FALL_SECONDS) / FALL_FADE_SECONDS, 0.0, 1.0))

func _clear_fall_fragments() -> void:
	for fragment: Dictionary in _fall_fragments.values():
		if is_instance_valid(fragment.pivot): fragment.pivot.queue_free()
	_fall_fragments.clear()

func _visible(entry: Dictionary) -> bool:
	return bool(entry.get("displayed", true)) and _bounds.intersects(entry.get("bounds", Rect2(entry.position - entry.size, entry.size * 2)))

func _fall_direction(state: Dictionary, index: int) -> float:
	var impulse: Vector2 = state.get("direction", Vector2.RIGHT)
	if absf(impulse.x) > .05:
		return signf(impulse.x)
	return -1.0 if index % 2 == 0 else 1.0

func _canopy_point(entry: Dictionary, selection: int) -> Vector2:
	var points: PackedVector2Array = entry.get("emit_points", PackedVector2Array())
	if points.is_empty():
		# A missing opaque anchor suppresses ambient shedding, rather than using
		# an arbitrary rectangle point in transparent sprite padding.
		return Vector2(INF, INF)
	if props.has_method("canopy_point"):
		return props.canopy_point(entry, posmod(selection, points.size()))
	return points[posmod(selection, points.size())]

func foliage_kind(entry: Dictionary) -> String:
	match str(entry.get("family", entry.get("tree_family", entry.get("tree", "dead")))):
		"broadleaf", "deciduous": return "leaf"
		"conifer": return "snow" if str(props.get("environment_id")) == "frozen_rail_yard" else "needle"
	return "bark"

func _emit_foliage(entry: Dictionary, point: Vector2, hit: bool) -> void:
	if not point.is_finite():
		return
	var kind := foliage_kind(entry)
	var push := 19.0 if hit else 5.0
	_spawn(kind, point, Vector2(_gust * 17 + _rng.randf_range(-push, push), _rng.randf_range(-18, -4) if hit else _rng.randf_range(2, 9)), entry, _rng.randf_range(1.7, 3.8))

func _hit_burst(entry: Dictionary, state: Dictionary, broken: bool) -> void:
	burst_count += 1
	var root_point: Vector2 = entry.position
	var world_hit: Vector2 = state.get("hit", props.to_global(root_point - Vector2(0, entry.size.y * .4)))
	_hit_sound(entry, world_hit)
	var hit: Vector2 = props.to_local(world_hit)
	var kind := str(entry.kind)
	var count := (3 if broken else 1) if _reduced else (11 if broken else 5)
	var direction: Vector2 = state.get("direction", Vector2.RIGHT)
	if kind == "tree":
		var nearest := _nearest_anchor(entry, hit)
		if nearest.is_finite():
			for index in count:
				var selection := int(entry.index) + floori(float(index) * entry.emit_points.size() / count)
				_emit_foliage(entry, _canopy_point(entry, selection) if broken else nearest, true)
		var trunk: PackedVector2Array = entry.get("trunk_points", PackedVector2Array())
		var bark_point := root_point - Vector2(0, minf(20.0, float(entry.size.y) * .1))
		if not trunk.is_empty():
			bark_point = trunk[0]
			for point: Vector2 in trunk:
				if point.distance_squared_to(hit) < bark_point.distance_squared_to(hit): bark_point = point
		for index in (2 if _reduced else 5):
			_spawn("bark", bark_point, direction * _rng.randf_range(18, 50) + Vector2(_rng.randf_range(-14, 14), -_rng.randf_range(22, 55)), entry, 1.0 + _rng.randf())
	elif kind in GROWTH:
		var point := Vector2(clampf(hit.x, root_point.x - entry.size.x * .4, root_point.x + entry.size.x * .4), clampf(hit.y, root_point.y - entry.size.y * .55, root_point.y - 2))
		for index in count:
			_spawn("leaf" if kind in ["grass", "vines", "reeds"] else "bark", point, direction * 17 + Vector2(_rng.randf_range(-15, 15), -_rng.randf_range(12, 29)), entry, _rng.randf_range(.6, 1.8))
	else:
		var point := Vector2(clampf(hit.x, root_point.x - entry.size.x * .4, root_point.x + entry.size.x * .4), clampf(hit.y, root_point.y - entry.size.y, root_point.y - 2))
		for index in count:
			var particle_kind := "cloth" if kind in ["windsock", "tape"] and index % 2 == 0 else "spark"
			_spawn(particle_kind, point, direction * _rng.randf_range(16, 39) + Vector2(_rng.randf_range(-14, 14), -_rng.randf_range(14, 39)), entry, _rng.randf_range(.35, 1.0))

func _hit_sound(entry: Dictionary, point: Vector2) -> void:
	if _sound_delay > 0.0 or not point.is_finite(): return
	var game = props.get("game")
	var audio = game.get("audio") if is_instance_valid(game) else null
	if not is_instance_valid(audio) or not audio.has_method("play_sound_at"): return
	var organic: bool = entry.kind == "tree" or entry.kind in GROWTH or entry.kind in ["windsock", "tape"]
	# Reactions are already mirrored to guests; play the local contact once at
	# its copied world point instead of echoing a second network sound event.
	if audio.play_sound_at("impact_wood" if organic else "impact_metal", point):
		_sound_delay = .1

func _nearest_anchor(entry: Dictionary, point: Vector2) -> Vector2:
	var anchors: PackedVector2Array = entry.get("emit_points", PackedVector2Array())
	var selected := Vector2(INF, INF)
	var distance := INF
	for index in anchors.size():
		var anchor := _canopy_point(entry, index)
		var candidate := anchor.distance_squared_to(point)
		if candidate < distance:
			selected = anchor
			distance = candidate
	return selected

func _spawn(kind: String, point: Vector2, velocity: Vector2, entry: Dictionary, lifetime: float) -> void:
	var budget := REDUCED_PARTICLES if _reduced else MAX_PARTICLES
	if particles.size() >= budget or not point.is_finite() or not _bounds.grow(16).has_point(point):
		return
	var ground_y: float = entry.position.y
	point.y = minf(point.y, ground_y - 2)
	particles.append({"kind":kind, "position":point, "origin":point, "velocity":velocity,
		"ground":ground_y, "age":0.0, "life":lifetime, "phase":_rng.randf() * TAU,
		"size":_rng.randf_range(1.0, 2.8), "entry":int(entry.index),
		"color":_particle_color(kind, entry), "landed":false})
	emitted += 1
	if _origins.size() >= 64: _origins.pop_front()
	_origins.append({"kind":kind, "entry":int(entry.index), "point":point})

func _particle_color(kind: String, entry: Dictionary) -> Color:
	match kind:
		"leaf": return Color(entry.get("foliage", Color("839b60"))).darkened(_rng.randf_range(0.0, .22))
		"needle": return Color("62765a")
		"snow": return Color("c4d8df")
		"bark": return Color("766049").lerp(Color(entry.tint), .12)
		"cloth": return Color(entry.get("accent", Color("b99755")))
		"spark": return Color("ddb774")
		"ember": return Color("d18438")
	return Color("444a40")

func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var item: Dictionary = particles[index]
		item.age += delta
		if float(item.age) >= float(item.life) or not _bounds.grow(40).has_point(item.position):
			particles.remove_at(index)
			culled += 1
			continue
		if item.landed: continue
		var kind := str(item.kind)
		var velocity: Vector2 = item.velocity
		var gravity := 145.0 if kind in ["bark", "spark"] else 38.0 if kind == "cloth" else 14.0
		if kind in ["smoke", "ember"]: gravity = -2.0
		velocity.y += gravity * delta
		velocity.x = move_toward(velocity.x, _gust * (19 if kind == "smoke" else 26), delta * 9)
		var flutter := sin(elapsed * (4.0 if kind == "leaf" else 2.2) + float(item.phase)) * (5.0 if kind in ["leaf", "cloth"] else 1.5)
		item.position += (velocity + Vector2(flutter, 0)) * delta
		item.velocity = velocity
		if float(item.position.y) >= float(item.ground) - 2:
			item.position.y = float(item.ground) - 2
			item.landed = true
			item.life = minf(float(item.life), float(item.age) + (.12 if kind in ["spark", "ember"] else .8))

## 0..1: how far the flames at `point` have grown in. Standing trees catch from
## the foot up; everything else burns at once.
func ignition(entry: Dictionary, state: Dictionary, point: Vector2) -> float:
	if entry.kind != "tree" or bool(state.get("broken", false)): return 1.0
	var record: Dictionary = _seen.get(int(entry.index), {})
	var since := float(record.get("ignite", 99.0))
	return smoothstep(0.0, IGNITE_GROW, since - _ignite_delay(entry, point.y))

func _ignite_delay(entry: Dictionary, y: float) -> float:
	var height := maxf(1.0, float(entry.size.y))
	return IGNITE_BASE + IGNITE_CLIMB * clampf((float(entry.position.y) - y) / height, 0.0, 1.0)

func fire_points(entry: Dictionary, state: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var root_point: Vector2 = entry.position
	var broken := bool(state.get("broken", false))
	if entry.kind == "tree" and not broken:
		var trunk: PackedVector2Array = entry.get("trunk_points", PackedVector2Array())
		if not trunk.is_empty():
			for index in range(0, trunk.size(), maxi(1, floori(trunk.size() / 3.0))):
				points.append(trunk[index])
				if points.size() >= (2 if _reduced else 3): break
		var crown := _canopy_point(entry, int(entry.index) + 2)
		if crown.is_finite() and not _reduced: points.append(crown)
	elif entry.kind == "tree":
		var fallen := fallen_geometry(entry)
		points.append(Vector2(fallen.base).lerp(fallen.tip, .18))
		if not _reduced: points.append(Vector2(fallen.base).lerp(fallen.tip, .68))
	else:
		points.append(root_point + Vector2(-5, -4.0 if broken else -minf(16, entry.size.y * .25)))
		if not _reduced: points.append(root_point + Vector2(9, -5))
	# Missing tree anchors never invent a canopy fire in transparent padding.
	return points

func _draw() -> void:
	if not is_instance_valid(props) or not is_instance_valid(props.get("reactions")): return
	for entry: Dictionary in props.entries:
		if not _visible(entry): continue
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if state.is_empty(): continue
		if entry.kind == "tree" and foliage_kind(entry) == "snow" and not bool(state.get("broken", false)) and (bool(state.get("burning", false)) or not bool(state.get("charred", false))):
			_draw_snowcaps(entry, state)
		if bool(state.get("broken", false)):
			if entry.kind == "tree": _draw_broken_tree(entry, state)
			else: _draw_wreck(entry, state)
	for item: Dictionary in particles:
		if str(item.kind) != "ember": _draw_particle(item)

## Burning entries within the fire budget, as (point, phase, heat) calls.
func _each_fire(callback: Callable) -> void:
	if not is_instance_valid(props) or not is_instance_valid(props.get("reactions")): return
	var fire_budget := 5 if _reduced else MAX_FIRE_SOURCES
	for entry: Dictionary in props.entries:
		if not _visible(entry): continue
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if state.is_empty() or not bool(state.get("burning", false)): continue
		# A fire about to go out shrinks and reddens over its last seconds.
		var heat := lerpf(.30, 1.0, smoothstep(0.0, 2.0, float(state.get("burn_left", 8.0))))
		var points := fire_points(entry, state)
		for index in points.size():
			if fire_budget <= 0: return
			var grown := ignition(entry, state, points[index])
			if grown <= .02: continue
			fire_budget -= 1
			callback.call(points[index], int(entry.index) * 5 + index, heat, grown)

func _draw_flames() -> void:
	_each_fire(_draw_fire)
	for item: Dictionary in particles:
		if str(item.kind) == "ember": _draw_particle(item, flame_layer)

func _draw_glow() -> void:
	if _reduced: return
	_each_fire(_draw_fire_glow)

func _draw_fire_glow(point: Vector2, phase: int, heat: float, grown: float = 1.0) -> void:
	# The warm air around the flames, in dithered additive bands; daylight
	# would wash a strong glow out, so it grows with the dark.
	var flicker := .90 + .10 * float(posmod(PixelArt.flame_frame(elapsed, phase) * 7, 5)) / 4.0
	PixelArt.grid_halo(glow_layer, point + Vector2(0, -12), 30.0 * (.7 + .3 * heat) * (.5 + .5 * grown), Color(1.0, .55, .22, (.08 + .22 * PixelArt.night()) * heat * flicker * grown), phase)

func _draw_snowcaps(entry: Dictionary, state: Dictionary) -> void:
	var points: PackedVector2Array = entry.get("emit_points", PackedVector2Array())
	var count := mini(points.size(), clampi(ceili(float(state.get("hp", 0)) / 16.0), 1, 5))
	if _reduced: count = mini(count, 2)
	var burning := bool(state.get("burning", false))
	for index in count:
		var point := _canopy_point(entry, floori(float(index) * points.size() / count))
		# Snow above the climbing fire front stays until the flames reach it.
		if burning and ignition(entry, state, point) > 0.0: continue
		_rect(point + Vector2(-2, -1), Vector2(4 + index % 2, 1), Color("b8ced6"))
		_rect(point + Vector2(-1, -2), Vector2(2, 1), Color("d7e3df"))
		if index % 2 == 0: _rect(point + Vector2(1, 0), Vector2(2, 1), Color("8eaab7"))

func _draw_fire(point: Vector2, phase: int, heat: float = 1.0, grown: float = 1.0) -> void:
	# A procedural flipbook of pixel flames on the texel grid: one main tongue
	# and two lower side tongues over a bed of glowing coals, leaning with the
	# wind; separate anchors never share an animation phase.
	var frame := PixelArt.flame_frame(elapsed, phase)
	var seed_value := posmod(phase * 31 + roundi(point.x) * 13 + roundi(point.y) * 7, 997)
	var lean := _gust * 5.0 + float(seed_value % 5 - 2) * .6
	var tall := (20.0 + float(seed_value % 9)) * (.55 + .45 * heat) * grown
	var width := (11.0 + float(seed_value % 4)) * (.45 + .55 * grown)
	for tongue in (2 if _reduced else 3):
		# The side tongues are lower and sit a little further down the wood,
		# so the cluster forms a mound around the main tongue.
		var offset := 0.0 if tongue == 0 else (-1.0 if tongue == 1 else 1.0) * (width * .42 + float((seed_value + tongue) % 3))
		var share := 1.0 if tongue == 0 else .42 + .07 * float((seed_value + tongue * 5) % 4)
		PixelArt.grid_flame(flame_layer, point + Vector2(offset, 1.0 if tongue == 0 else 2.0), width * (1.0 if tongue == 0 else .70), tall * share, heat * (1.0 if tongue == 0 else .80), frame + tongue * 9, seed_value + tongue * 17, lean * share)
	# Glowing coals along the burning wood, stepping with the flames.
	var bed := width * .9
	for coal in (2 if _reduced else 4):
		var x := -bed * .5 + float(coal) * bed / 3.0 + float((seed_value + coal) % 3) - 1.0
		var lit := posmod(frame + coal * 3, 5) > 1
		flame_layer.draw_rect(Rect2((point + Vector2(x, -1 - float((seed_value + coal) % 2))).round(), Vector2(2 if coal % 2 else 1, 1)), Color("ffd27a") if lit else Color("d5602c"))

func _draw_particle(item: Dictionary, layer: CanvasItem = self) -> void:
	var point: Vector2 = item.position
	var progress: float = float(item.age) / float(item.life)
	var color: Color = item.color
	color.a = clampf((1.0 - progress) * 3.0, 0, 1)
	var kind := str(item.kind)
	if kind == "smoke":
		# Wood smoke: a dark warm puff over the fire that rises, swells, leans
		# downwind and tears into dithered wisps.
		PixelArt.smoke_puff(self, point, 3.0 + progress * 9.0, Color(.25, .24, .22, .50), int(item.entry) * 3 + int(float(item.life) * 10.0), progress, clampf(1.0 - progress * 3.5, 0.0, 1.0) * .7, clampf(_gust * .35 * progress, 0.0, .4))
	elif kind == "leaf":
		var flip := sin(elapsed * 7.0 + float(item.phase))
		var width := 1.0 if absf(flip) < .32 else 3.0
		_poly([point + Vector2(-width, 0), point + Vector2(0, -1), point + Vector2(width, 1), point + Vector2(0, 2)], color)
		_line(point, point + Vector2(width - 1, 1), Color(color.lightened(.16), color.a))
	elif kind == "snow":
		draw_rect(Rect2(point.round(), Vector2(2, 1)), color)
		draw_rect(Rect2((point + Vector2(1, 1)).round(), Vector2.ONE), Color("8baab7") * Color(1, 1, 1, color.a * .7))
	elif kind in ["bark", "cloth"]:
		var size := Vector2(2, 4) if kind == "bark" else Vector2(4, 2)
		draw_rect(Rect2(point.round() - size * .5, size), color.darkened(.24))
		draw_rect(Rect2(point.round(), Vector2(1, 2)), color)
	elif kind == "needle":
		_line(point, point + Vector2(3, 1), color)
	else:
		layer.draw_rect(Rect2(point.round(), Vector2(1, 2)), color)
		if kind == "ember" and progress < .5: layer.draw_rect(Rect2(point.round(), Vector2.ONE), Color("ffe7a9"))

func fallen_geometry(entry: Dictionary) -> Dictionary:
	var record: Dictionary = _seen.get(int(entry.index), {})
	var progress := clampf(float(record.get("fall_age", FALL_SECONDS)) / FALL_SECONDS, 0, 1)
	var direction := float(record.get("direction", 1.0))
	var angle := direction * (progress * progress * .5 + progress * .5) * PI * .5
	var ground_y: float = entry.position.y
	var base: Vector2 = entry.position + Vector2(direction * 4, -8)
	var tip := base + Vector2(0, -float(entry.size.y) * .58).rotated(angle)
	tip.y = minf(tip.y, ground_y - 7)
	return {"base":base, "tip":tip, "progress":progress, "direction":direction, "ground":ground_y}

func _draw_broken_tree(entry: Dictionary, state: Dictionary) -> void:
	var root_point: Vector2 = entry.position
	var record: Dictionary = _seen.get(int(entry.index), {})
	var charred: bool = bool(state.get("charred", false)) or bool(record.get("charred", false))
	var bark := Color("65543e").lerp(Color(entry.tint), .10).darkened(.55 if charred else 0.0)
	var cut := Color("a99063").darkened(.65 if charred else .08)
	var stump_width := clampf(entry.size.y * .035, 5, 9)
	_poly([root_point + Vector2(-stump_width - 6, -1), root_point + Vector2(-stump_width, -8), root_point + Vector2(-stump_width + 1, -21), root_point + Vector2(-2, -15), root_point + Vector2(2, -24), root_point + Vector2(stump_width - 1, -17), root_point + Vector2(stump_width + 2, -6), root_point + Vector2(stump_width + 6, -1)], bark.darkened(.3))
	_poly([root_point + Vector2(-stump_width + 1, -18), root_point + Vector2(-2, -14), root_point + Vector2(2, -22), root_point + Vector2(stump_width - 2, -16), root_point + Vector2(stump_width - 1, -10), root_point + Vector2(-stump_width + 1, -10)], cut)
	for index in 3:
		_line(root_point + Vector2(-stump_width + 2 + index * 4, -10), root_point + Vector2(-stump_width + 1 + index * 5, -1), bark.lightened(.11), 2)
	var shape := fallen_geometry(entry)
	var base: Vector2 = shape.base
	var tip: Vector2 = shape.tip
	var width := clampf(entry.size.y * .035, 5, 9)
	_wood_segment(base, tip, width, bark)
	var axis := (tip - base).normalized()
	var side := Vector2(-axis.y, axis.x)
	for index in 4:
		var at := base.lerp(tip, .28 + index * .16)
		var reach := (13 + index * 4) * (-1 if index % 2 else 1)
		var branch_end := at + side * reach + axis * (12 + index * 4)
		branch_end.y = minf(branch_end.y, float(shape.ground) - 2)
		_wood_segment(at, branch_end, 2.0 if index % 2 else 3.0, bark)
		if foliage_kind(entry) == "leaf" and not charred and index % 2 == 0:
			var leaf: Color = entry.get("foliage", Color("74865b"))
			_poly([branch_end + Vector2(-5, -2), branch_end + Vector2(0, -5), branch_end + Vector2(5, -2), branch_end + Vector2(3, 0), branch_end + Vector2(-4, 0)], leaf.darkened(.2))
	_line(base - side * 2, base + side * 2, cut, 2)

func _wood_segment(start: Vector2, end: Vector2, width: float, tint: Color) -> void:
	var delta := (end - start).normalized()
	var normal := Vector2(-delta.y, delta.x) * width * .5
	_poly([start - normal, end - normal * .58, end + normal * .58, start + normal], tint.darkened(.32))
	_line(start - normal * .45, end - normal * .28, tint.lightened(.12), maxf(1, width * .38))
	_line(start + normal * .25, end + normal * .15, tint.darkened(.16))

func _draw_wreck(entry: Dictionary, state: Dictionary) -> void:
	var at: Vector2 = entry.position
	var tint: Color = Color(entry.tint).darkened(.18)
	var accent: Color = Color(entry.get("accent", Color("b39358"))).darkened(.24)
	var dark := tint.darkened(.58)
	var kind := str(entry.kind)
	if kind in GROWTH:
		var charred := bool(state.get("charred", false)) or bool(_seen.get(int(entry.index), {}).get("charred", false))
		var stem: Color = Color("302c22") if charred else Color(entry.get("foliage", tint)).darkened(.38)
		for index in 9:
			var x := -25 + index * 6
			_line(at + Vector2(x, -1), at + Vector2(x + (6 if index % 2 else -4), -3 - index % 4 * 2), stem, 2)
		return
	match kind:
		"fan":
			_poly([at + Vector2(-31, -5), at + Vector2(-26, -32), at + Vector2(27, -27), at + Vector2(32, -4)], dark)
			SurfaceArt.face(self, Rect2(at + Vector2(-24, -25), Vector2(48, 20)), tint, 3)
			_disc(at + Vector2(0, -16), 13, dark)
			for index in 3:
				var direction := Vector2.from_angle(index * TAU / 3 + .4)
				_line(at + Vector2(0, -16), at + Vector2(0, -16) + direction * 10, tint.lightened(.1), 4)
			_line(at + Vector2(-15, -18), at + Vector2(15, -12), tint.lightened(.22))
			_line(at + Vector2(-8, -26), at + Vector2(-5, -6), tint.lightened(.15))
			_rect(at + Vector2(30, -5), Vector2(9, 3), dark)
		"signal":
			_rect(at + Vector2(-3, -24), Vector2(6, 24), tint)
			_line(at + Vector2(-2, -24), at + Vector2(7, -29), dark, 3)
			SurfaceArt.face(self, Rect2(at + Vector2(9, -17), Vector2(49, 16)), tint, 2)
			for index in 3:
				_disc(at + Vector2(17 + index * 15, -9), 5, dark)
				_rect(at + Vector2(16 + index * 15, -10), Vector2(2, 2), [Color("56352b"), accent.darkened(.55), Color("334338")][index])
		"windsock":
			_rect(at + Vector2(-3, -19), Vector2(6, 19), tint)
			_line(at + Vector2(3, -4), at + Vector2(84, -8), tint, 4)
			for index in 7:
				_rect(at + Vector2(22 + index * 5, -12 - index % 2 * 2), Vector2(6, 4 + index % 3), accent if index % 2 else Color("848678"))
		"tape":
			for x in [-39, 39]: _rect(at + Vector2(x - 2, -18 if x < 0 else -12), Vector2(4, 18 if x < 0 else 12), tint)
			for index in 13:
				_line(at + Vector2(-32 + index * 5, -4 - index % 2 * 4), at + Vector2(-27 + index * 5, -8 + index % 2 * 4), accent if index % 2 else dark, 3)
		"cable":
			for x in [-35, 35]:
				_rect(at + Vector2(x - 3, -24 if x < 0 else -14), Vector2(6, 24 if x < 0 else 14), tint)
				_rect(at + Vector2(x - 8, -5), Vector2(4, 3), Color("94a59a"))
			_polyline([at + Vector2(-35, -23), at + Vector2(-20, -8), at + Vector2(0, -2), at + Vector2(19, -6), at + Vector2(35, -14)], dark, 2)
			_polyline([at + Vector2(-32, -20), at + Vector2(-9, -3), at + Vector2(16, -2), at + Vector2(24, -4)], accent.darkened(.6))
		"ore_cart":
			_poly([at + Vector2(-33, -8), at + Vector2(-28, -30), at + Vector2(20, -21), at + Vector2(27, -4)], dark)
			_poly([at + Vector2(-28, -10), at + Vector2(-25, -26), at + Vector2(15, -19), at + Vector2(22, -5)], tint)
			_disc(at + Vector2(-21, -7), 6, dark)
			_disc(at + Vector2(38, -5), 5, dark)
			for index in 7:
				_rect(at + Vector2(10 + index * 6, -2 - index % 3 * 3), Vector2(5, 3), tint.darkened(.25 + (index % 2) * .2))
		"pipe":
			SurfaceArt.face(self, Rect2(at + Vector2(-29, -18), Vector2(12, 18)), tint, 2)
			SurfaceArt.face(self, Rect2(at + Vector2(-11, -11), Vector2(42, 10)), tint, 4)
			_rect(at + Vector2(-14, -12), Vector2(6, 12), dark)
			_disc(at + Vector2(-22, -11), 5, accent.darkened(.2))
			_line(at + Vector2(-22, -16), at + Vector2(-22, -7), dark)
		"bollard":
			_rect(at + Vector2(-41, -20), Vector2(14, 20), tint)
			_rect(at + Vector2(-46, -20), Vector2(24, 4), tint.lightened(.1))
			_poly([at + Vector2(22, -3), at + Vector2(26, -14), at + Vector2(43, -9), at + Vector2(41, -2)], tint)
			_polyline([at + Vector2(-33, -18), at + Vector2(-17, -3), at + Vector2(-4, -2), at + Vector2(4, -5)], accent, 2)
			_polyline([at + Vector2(29, -9), at + Vector2(21, -2), at + Vector2(9, -2)], accent.darkened(.15), 2)
		_:
			for index in 6: _rect(at + Vector2(-20 + index * 7, -3 - index % 3), Vector2(5, 3), dark)

func _rect(point: Vector2, size: Vector2, tint: Color) -> void:
	draw_rect(Rect2(point.round(), size.round()), tint)

func _line(first: Vector2, second: Vector2, tint: Color, width := 1.0) -> void:
	draw_line(first.round(), second.round(), tint, width, false)

func _poly(vertices: Array, tint: Color) -> void:
	var points := PackedVector2Array()
	for vertex: Vector2 in vertices: points.append(vertex.round())
	draw_colored_polygon(points, tint)

func _polyline(vertices: Array, tint: Color, width := 1.0) -> void:
	var points := PackedVector2Array()
	for vertex: Vector2 in vertices: points.append(vertex.round())
	draw_polyline(points, tint, width, false)

func _disc(center: Vector2, radius: float, tint: Color) -> void:
	var points: Array[Vector2] = []
	for index in 8: points.append(center + Vector2.from_angle(index * TAU / 8) * radius)
	_poly(points, tint)

func diagnostics() -> Dictionary:
	return {"particles":particles.size(), "budget":REDUCED_PARTICLES if _reduced else MAX_PARTICLES,
		"emitted":emitted, "culled":culled, "bursts":burst_count, "entries":_seen.size(),
		"elapsed":elapsed, "reduced":_reduced, "fall_fragments":_fall_fragments.size(), "origins":_origins.duplicate(true)}
