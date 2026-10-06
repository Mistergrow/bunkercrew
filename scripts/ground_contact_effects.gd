extends RefCounted
## Bounded ground deposits and short contact debris, all attached to real support.
const Catalog := preload("res://scripts/ground_surface_catalog.gd")
const MAX_FIELDS := 28
const MAX_CHIPS := 88
const MAX_PLUMES := 24
const MAX_TRACKS := 48
var surfaces: Node2D
var fields: Array[Dictionary] = []
var chips: Array[Dictionary] = []
var plumes: Array[Dictionary] = []
var tracks: Array[Dictionary] = []
var environment := ""
var _configured := false
var _validation_clock := 0.0
var _field_cursor := 0
var _track_cursor := 0
var _created_physics_frame := Engine.get_physics_frames()
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 194621

func _game():
	var sky = surfaces.weather
	return sky.get("game") if is_instance_valid(sky) and "game" in sky else null

func _environment() -> String:
	var game = _game()
	if not is_instance_valid(game):
		return ""
	var options: Dictionary = game.get("scenario_options") if "scenario_options" in game else {}
	return str(options.get("environment", "sector07"))

func _ground_y() -> float:
	var game = _game()
	var bunker = game.get("scenario_bunker") if is_instance_valid(game) and "scenario_bunker" in game else null
	return float(bunker.ground_y) if is_instance_valid(bunker) else 430.0

func is_outside_ground(point: Vector2, surface_material: String) -> bool:
	if environment.is_empty() or surface_material != "soil" or absf(point.y - _ground_y()) > 3.0:
		return false
	var game = _game()
	var bunker = game.get("scenario_bunker") if is_instance_valid(game) and "scenario_bunker" in game else null
	if is_instance_valid(bunker):
		if point.x >= float(bunker.room_left) - 12.0 and point.x <= float(bunker.room_right) + 12.0:
			return false
	elif point.x < 885.0:
		return false
	var sky = surfaces.weather
	return sky.has_method("exposure_at") and float(sky.exposure_at(point + Vector2(0, -2))) > 0.5

func prepare() -> void:
	var selected := _environment()
	if _configured and selected == environment:
		return
	# A selected bunker creates its colliders after weather._ready(). Never
	# permanently cache an empty query made before the first physics sync.
	if not selected.is_empty() and Engine.get_physics_frames() <= _created_physics_frame:
		return
	environment = selected
	_configured = true
	fields.clear()
	if environment.is_empty():
		return
	var game = _game()
	var has_bunker: bool = is_instance_valid(game) and "scenario_bunker" in game and is_instance_valid(game.scenario_bunker)
	var first_x := -240.0 if has_bunker else 890.0
	var last_x := 1680.0 if has_bunker else 1430.0
	for cell in range(floori(first_x / Catalog.CELL_WIDTH), ceili(last_x / Catalog.CELL_WIDTH)):
		if fields.size() >= MAX_FIELDS:
			break
		var spec := Catalog.deposit(environment, cell)
		if spec.is_empty() or float(spec.x) < first_x or float(spec.x) > last_x:
			continue
		var hit: Dictionary = surfaces._near_support(Vector2(float(spec.x), _ground_y()))
		if hit.is_empty() or not is_instance_valid(hit.get("collider")) or bool(hit.get("weather_prop", false)) or surfaces._moving_hit(hit):
			continue
		var point: Vector2 = hit.position
		var normal: Vector2 = hit.get("normal", Vector2.UP)
		var surface_material := str(hit.get("material", "concrete"))
		if normal.y >= -0.60 or not is_outside_ground(point, surface_material):
			continue
		var collider: Object = hit.collider
		var width := 2.0
		for extent in [5.0, 10.0, 16.0, 22.0]:
			if extent > float(spec.width):
				break
			var supported := true
			for side in [-1.0, 1.0]:
				var sample := point + Vector2(extent * side, 0)
				if not surfaces._same_support(surfaces._near_support(sample), sample, surface_material, collider.get_instance_id(), 2.0) or not is_outside_ground(sample, surface_material):
					supported = false
					break
			if not supported:
				break
			width = extent
		if width < 5.0:
			continue
		fields.append({"point": point, "normal": normal, "width": width, "kind": spec.kind, "seed": spec.seed,
			"material": surface_material, "collider_id": collider.get_instance_id(), "support": weakref(collider)})

func state_at(feet: Vector2) -> Dictionary:
	for field in fields:
		if field.support.get_ref() == null:
			continue
		var difference: Vector2 = feet - Vector2(field.point)
		if absf(difference.y) <= 7.0 and absf(difference.x) <= float(field.width):
			return {"kind": field.kind, "wetness": 0.78 if field.kind == "water" else 0.0,
				"mud": 0.06 if field.kind == "water" else 0.0, "material": field.material,
				"distance": difference.dot(field.normal), "support_y": Vector2(field.point).y}
	return {}

func emit_contact(state: Dictionary, strength: float) -> void:
	var point: Vector2 = state.point
	var normal: Vector2 = state.normal
	var kind := str(state.kind)
	if kind == "water":
		return
	var weight := clampf(strength, 0.2, 2.6)
	var ice := kind == "ice"
	var steel := kind == "metal"
	var dust_scale := 0.22 if steel else (0.55 if str(state.material) == "concrete" else 1.0)
	var support = state.get("support")
	var spec := Catalog.profile(environment)
	var grit: Color = Color("d5e1df") if ice else Color(spec.grit)
	var count := clampi(roundi((2.0 + weight * 2.3) * (0.4 if steel else 1.0)), 1, 8)
	for index in count:
		if chips.size() >= MAX_CHIPS:
			break
		chips.append({"point": point + normal * 1.5, "velocity": Vector2(_rng.randf_range(-29, 29), -_rng.randf_range(15, 42)) * sqrt(weight),
			"origin": point, "normal": normal, "age": 0.0, "life": _rng.randf_range(0.18, 0.40), "ice": ice,
			"tint": grit, "size": 2 if weight > 1.4 and index % 3 == 0 else 1, "support": support})
	if plumes.size() < MAX_PLUMES and (not steel or weight > 1.5):
		plumes.append({"point": point, "normal": normal, "age": 0.0, "life": 0.38 + weight * 0.05,
			"spread": 3.0 + weight * 3.5, "strength": dust_scale * minf(weight, 1.8),
			"tint": Color("b6c9ca") if ice else Color(spec.dust), "seed": _rng.randi_range(0, 999), "support": support})
	if ice:
		if tracks.size() >= MAX_TRACKS:
			tracks.pop_front()
		tracks.append({"point": point, "normal": normal, "age": 0.0, "life": 4.0 + weight * 0.6,
			"width": clampf(3.0 * sqrt(weight), 2.0, 5.0), "support": support,
			"collider_id": int(state.get("collider_id", 0)), "material": str(state.material)})

func _support_gone(entry: Dictionary) -> bool:
	return entry.get("support") != null and entry.support.get_ref() == null

func advance(delta: float, reduced: bool) -> void:
	prepare()
	if reduced:
		chips.clear()
		plumes.clear()
	for index in range(chips.size() - 1, -1, -1):
		var chip := chips[index]
		chip.age += delta
		chip.velocity += Vector2(3, 245) * delta
		chip.point += Vector2(chip.velocity) * delta
		if chip.age >= chip.life or _support_gone(chip) or (float(chip.age) > 0.06 and (Vector2(chip.point) - Vector2(chip.origin)).dot(chip.normal) < 0.0):
			chips.remove_at(index)
	for index in range(plumes.size() - 1, -1, -1):
		plumes[index].age += delta
		if plumes[index].age >= plumes[index].life or _support_gone(plumes[index]):
			plumes.remove_at(index)
	for index in range(tracks.size() - 1, -1, -1):
		tracks[index].age += delta
		if tracks[index].age >= tracks[index].life or _support_gone(tracks[index]):
			tracks.remove_at(index)
	_validation_clock += delta
	if _validation_clock >= 0.1:
		_validation_clock = 0.0
		_validate_supports()

func _validate_supports() -> void:
	for group_index in 2:
		var entries: Array[Dictionary] = fields if group_index == 0 else tracks
		for probe in 4:
			if entries.is_empty():
				break
			var cursor := _field_cursor if group_index == 0 else _track_cursor
			cursor %= entries.size()
			var entry: Dictionary = entries[cursor]
			var hit: Dictionary = surfaces._near_support(entry.point)
			if not surfaces._same_support(hit, entry.point, str(entry.material), int(entry.collider_id), 2.0) or (group_index == 0 and not is_outside_ground(entry.point, str(entry.material))):
				entries.remove_at(cursor)
			else:
				cursor += 1
			if group_index == 0:
				_field_cursor = cursor
			else:
				_track_cursor = cursor

static func field_polygon(at: Vector2,width: float) -> PackedVector2Array:
	# Short support patches beside a gate may be only5px wide. Keep the upper
	# contour monotonic; -width+4 previously folded back over -width*.3.
	return PackedVector2Array([at+Vector2(-width,0),at+Vector2(minf(-width+4,-width*.65),-1),at+Vector2(-width*.3,-1),
		at+Vector2(width*.25,0),at+Vector2(width-3,-1),at+Vector2(width,0),
		at+Vector2(width-2,2),at+Vector2(-width+2,2)])

func draw_ground(canvas: Node2D, elapsed: float, reduced: bool) -> void:
	for field in fields:
		var at := canvas.to_local(field.point).round()
		var width := float(field.width)
		var ice: bool = field.kind == "ice"
		var edge := Color("5d777c") if ice else Color("243d3d")
		var body := Color("a4bdbe") if ice else Color("526f6e")
		body.a = 0.68 if ice else 0.67
		var points := field_polygon(at,width)
		canvas.draw_polyline(points, edge, 1.0)
		canvas.draw_colored_polygon(points, body)
		var shimmer := 0.6 if reduced else 0.55 + sin(elapsed * 1.35 + float(int(field.seed) % 17)) * 0.15
		var highlight := Color("d1deda") if ice else Color("99b8b6")
		highlight.a = shimmer
		canvas.draw_line(at + Vector2(-width * 0.55, -1), at + Vector2(width * 0.25, -1), highlight, 1.0)
		if ice:
			canvas.draw_line(at + Vector2(2, -1), at + Vector2(5, 2), Color("5e818a"), 1.0)
			canvas.draw_rect(Rect2(at + Vector2(-width + 3, -2), Vector2(3, 1)), Color("d7e1d9"))
	for track in tracks:
		var at := canvas.to_local(track.point).round()
		var opacity := (1.0 - float(track.age) / float(track.life)) * 0.78
		canvas.draw_line(at - Vector2(float(track.width), 0), at + Vector2(float(track.width), 0), Color(0.22, 0.34, 0.37, opacity), 2.0)
		for groove in 3:
			canvas.draw_rect(Rect2(at + Vector2(-3 + groove * 2, -1), Vector2(1, 1)), Color(0.74, 0.83, 0.81, opacity * 0.8))

func draw_contacts(canvas: Node2D) -> void:
	for plume in plumes:
		var progress := float(plume.age) / float(plume.life)
		var at := canvas.to_local(plume.point).round()
		var tint: Color = plume.tint
		tint.a = sin(progress * PI) * (1.0 - progress) * 0.24 * float(plume.strength)
		for puff in 3:
			var spread := float(plume.spread) * (0.5 + progress)
			var x := (puff - 1) * spread * 0.70
			var y := -1.0 - progress * (5.0 + puff * 2.0)
			var size := Vector2(3.0 + spread * (0.5 if puff == 1 else 0.3), 2.0 + progress * 3.0).round()
			var origin := (at + Vector2(x, y) - size * 0.5).round()
			canvas.draw_rect(Rect2(origin + Vector2(1, 0), size - Vector2(2, 0)), tint)
			canvas.draw_rect(Rect2(origin + Vector2(0, 1), size - Vector2(0, 2)), tint)
	for chip in chips:
		var at := canvas.to_local(chip.point).round()
		var tint: Color = chip.tint
		tint.a = (1.0 - float(chip.age) / float(chip.life)) * 0.9
		canvas.draw_rect(Rect2(at, Vector2.ONE * int(chip.size)), tint)
		if chip.ice and int(chip.size) > 1:
			canvas.draw_rect(Rect2(at, Vector2.ONE), Color("eef1df"))
