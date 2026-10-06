extends Node2D
## Real local fire illumination. A fixed pool shares one small radial texture;
## only foreground world objects receive it, behind actual surface shadows.
const MAX_LIGHTS := 4
const OCCLUDER_MASK := 1 << 14
const MAX_OCCLUDERS := 12
const UPDATE_STEP := 1.0 / 24.0
static var _falloff: GradientTexture2D
var effects: Node2D
var lights: Array[PointLight2D] = []
var occluders: Array[LightOccluder2D] = []
var active_entries: Array[int] = []
var clock := 0.0
var uniform_updates := 0
var effects_enabled := true
var _update_clock := 0.0
var _geometry_clock := 0.0
var _geometry_signature := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false) # The parent advances particles, fall geometry and light together.
	for index in MAX_LIGHTS:
		var lamp := PointLight2D.new()
		lamp.name = "FireLight%02d" % index
		lamp.texture = falloff_texture()
		lamp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		lamp.color = Color(1.0, .56, .25)
		lamp.range_z_min = -8
		lamp.range_z_max = 20
		lamp.range_layer_min = 0
		lamp.range_layer_max = 0
		lamp.range_item_cull_mask = 1
		# Compatibility also checks this mask against receiving CanvasItems;
		# include their ordinary bit, not only the dedicated blocker bit.
		lamp.shadow_item_cull_mask = OCCLUDER_MASK | 1
		lamp.shadow_enabled = true
		lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		lamp.shadow_filter_smooth = 1.0
		lamp.enabled = false
		add_child(lamp)
		lights.append(lamp)

static func falloff_texture() -> GradientTexture2D:
	if _falloff == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, .12, .34, .62, .84, 1])
		gradient.colors = PackedColorArray([Color.WHITE, Color(.94,.94,.94), Color(.63,.63,.63), Color(.24,.24,.24), Color(.045,.045,.045), Color.BLACK])
		_falloff = GradientTexture2D.new()
		_falloff.width = 128
		_falloff.height = 128
		_falloff.fill = GradientTexture2D.FILL_RADIAL
		_falloff.fill_from = Vector2(.5, .5)
		_falloff.fill_to = Vector2(1, .5)
		_falloff.gradient = gradient
	return _falloff

func reset() -> void:
	active_entries.clear()
	clock = 0.0
	_update_clock = UPDATE_STEP
	_geometry_clock = 1.0
	_geometry_signature = ""
	for lamp in lights: lamp.enabled = false
	for blocker in occluders: blocker.queue_free()
	occluders.clear()

func update_lighting(delta: float) -> void:
	if not is_instance_valid(effects) or not is_instance_valid(effects.props) or get_tree().paused:
		return
	var props: Node2D = effects.props
	if not is_instance_valid(props.get("reactions")): return
	clock = effects.elapsed
	# Disabling, extinction and culling take effect immediately, even between
	# the inexpensive light-position/flicker updates.
	if not effects_enabled or effects._reduced or not effects.is_visible_in_tree():
		_disable_all()
		return
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in props.entries:
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if not bool(state.get("burning", false)) or not effects._visible(entry): continue
		var points: PackedVector2Array = effects.fire_points(entry, state)
		if points.is_empty(): continue
		# Follow the low, actual wood fire. A burning fallen branch consequently
		# carries its light away from the standing trunk during its finite fall.
		var at := points[0]
		if points.size() > 1: at = at.lerp(points[1], .4)
		at.y -= 10.0
		candidates.append({"index":int(entry.index), "position":at,
			"broken":bool(state.get("broken", false)), "tree":entry.kind == "tree",
			"tail":smoothstep(0.0, 1.5, float(state.get("burn_left", 8.0))),
			"distance":at.distance_squared_to(effects._bounds.get_center())})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var selected: Array[int] = []
	for index in mini(MAX_LIGHTS, candidates.size()): selected.append(int(candidates[index].index))
	var changed := selected != active_entries
	active_entries = selected
	for index in range(active_entries.size(), lights.size()): lights[index].enabled = false
	if candidates.is_empty(): return
	_geometry_clock += delta
	if changed or _geometry_clock >= .25:
		_geometry_clock = 0.0
		_sync_occluders()
	_update_clock += delta
	if not changed and _update_clock < UPDATE_STEP: return
	_update_clock = 0.0
	for index in active_entries.size():
		var candidate: Dictionary = candidates[index]
		var lamp := lights[index]
		var phase := float(candidate.index) * 2.137
		var flicker := .9 + .065 * sin(clock * 6.7 + phase) + .035 * sin(clock * 11.3 + phase * 2.1)
		var radius := 142.0 if candidate.tree else 102.0
		if candidate.broken: radius *= .88
		radius *= lerpf(.72, 1.0, float(candidate.tail))
		lamp.position = to_local(props.to_global(candidate.position))
		lamp.texture_scale = radius / 64.0
		lamp.energy = (1.02 if candidate.tree else .76) * flicker * float(candidate.tail)
		lamp.enabled = true
		uniform_updates += 3

func _disable_all() -> void:
	active_entries.clear()
	_update_clock = UPDATE_STEP
	for lamp in lights: lamp.enabled = false

func _sync_occluders() -> void:
	var props: Node2D = effects.props
	var game = props.get("game")
	var ground := 430.0
	var left := -410.0
	var right := 1850.0
	if is_instance_valid(game):
		if game.get("world_left") != null: left = float(game.world_left) - 160.0
		if game.get("world_right") != null: right = float(game.world_right) + 160.0
		if is_instance_valid(game.get("scenario_bunker")): ground = float(game.scenario_bunker.ground_y)
	var shapes: Array[PackedVector2Array] = []
	# Soil receives a 3px warm surface edge. A closed shadow volume supplies
	# stable spatial bounds without drawing any additional ground overlay.
	shapes.append(PackedVector2Array([to_local(Vector2(left, ground + 3)), to_local(Vector2(right, ground + 3)),
		to_local(Vector2(right, ground + 320)), to_local(Vector2(left, ground + 320))]))
	for group in ["scenario_terrain", "walls"]:
		for body: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(game) or not game.is_ancestor_of(body): continue
			for child in body.get_children():
				if not child is CollisionShape2D or child.disabled or not child.shape is RectangleShape2D: continue
				var half: Vector2 = child.shape.size * .5
				var top_left: Vector2 = child.to_global(-half)
				var bottom_right: Vector2 = child.to_global(half)
				if top_left.y >= ground or bottom_right.y < ground - 210: continue
				if shapes.size() >= MAX_OCCLUDERS: break
				shapes.append(PackedVector2Array([to_local(top_left), to_local(Vector2(bottom_right.x, top_left.y)), to_local(bottom_right), to_local(Vector2(top_left.x, bottom_right.y))]))
	var signature := var_to_str(shapes)
	if signature == _geometry_signature: return
	_geometry_signature = signature
	for blocker in occluders: blocker.queue_free()
	occluders.clear()
	for index in shapes.size():
		var polygon := OccluderPolygon2D.new()
		polygon.polygon = shapes[index]
		polygon.closed = true
		polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
		var blocker := LightOccluder2D.new()
		blocker.name = "SoilLightBarrier" if index == 0 else "SolidBunkerLightBarrier%02d" % index
		blocker.occluder = polygon
		blocker.light_mask = OCCLUDER_MASK
		blocker.occluder_light_mask = OCCLUDER_MASK
		blocker.sdf_collision = false
		add_child(blocker)
		occluders.append(blocker)

func diagnostics() -> Dictionary:
	return {"active":active_entries.size(), "pool":lights.size(), "occluders":occluders.size(),
		"entries":active_entries.duplicate(), "clock":clock, "updates":uniform_updates}
