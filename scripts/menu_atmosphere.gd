extends Node2D
## Menu-only atmosphere. Every sample uses the preview clock, so a paused match
## and different presentation frame rates cannot change wind or particle paths.
const SMOKE := preload("res://shaders/menu_smoke.gdshader")
const LAMP := preload("res://shaders/menu_lamp.gdshader")
const MAX_ASH := 28
var scenery: Node2D
var seconds := 0.0
var reduced_effects := false
var phase := 0.0
var base_wind := 4.0
var ash_enabled := false
var lamp_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	name = "MenuAtmosphere"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	phase = float(posmod(str(scenery.environment_id).hash(), 9))
	base_wind = float(scenery.profile.wind) * .35
	ash_enabled = scenery.environment_id in ["ash_foundry", "sector07", "buried_megafactory", "sulfur_refinery"]
	for index in scenery.smoke_nodes.size():
		var node: MeshInstance2D = scenery.smoke_nodes[index]
		var plume := ShaderMaterial.new()
		plume.shader = SMOKE
		plume.set_shader_parameter("smoke_origin", node.position)
		plume.set_shader_parameter("emitter_index", float(index))
		plume.set_shader_parameter("wind_phase", phase)
		plume.set_shader_parameter("base_wind", base_wind)
		if scenery.environment_id == "sector07":
			# Its closer skyline framing magnifies exhaust. Keep the plume path
			# and wind lag, but leave the central tower readable through the smoke.
			plume.set_shader_parameter("plume_width", .72)
			node.modulate.a = .58
		node.material = plume
		scenery._smoke_materials[index] = plume
		# The gust can carry old smoke to either side of its chimney. The shared
		# mesh belongs to this preview and needs bounds for both wind directions.
		node.mesh.custom_aabb = AABB(Vector3(-760, -290, -1), Vector3(1520, 390, 2))
	for index in scenery.lighting_layer.emission_nodes.size():
		var emitter: Sprite2D = scenery.lighting_layer.emission_nodes[index]
		var previous: ShaderMaterial = emitter.material
		var lamp := ShaderMaterial.new()
		lamp.shader = LAMP
		for parameter in ["source_center", "source_radius", "edge_fade", "allow_white"]:
			lamp.set_shader_parameter(parameter, previous.get_shader_parameter(parameter))
		emitter.material = lamp
		scenery.lighting_layer.emission_materials[index] = lamp
		lamp_materials.append(lamp)
	_prepare_weather()
	for node in scenery.smoke_nodes:
		node.material.set_shader_parameter("gust_strength",float(weather_profile.get("gust",1.0)))
	update_at(float(scenery.elapsed), scenery.reduced())

func update_at(at: float, is_reduced: bool) -> void:
	seconds = at
	reduced_effects = is_reduced
	for index in lamp_materials.size():
		lamp_materials[index].set_shader_parameter("illumination", lamp_level(index, at) if not is_reduced else 1.0)
	if is_instance_valid(storm_layer): storm_layer.queue_redraw()
	if is_instance_valid(water_mist_layer): water_mist_layer.queue_redraw()
	for layer in scenery.cloud_layers:
		if layer.material != null: layer.material.set_shader_parameter("storm_light", storm_strength(at))
	queue_redraw()

func wind_at(at: float) -> float:
	var clock := at + phase
	var cycle := floori(clock / 32.0)
	var within := fposmod(clock, 32.0)
	var gust := smoothstep(3.0, 8.0, within) * (1.0 - smoothstep(12.0, 18.0, within))
	var direction := -1.0 if posmod(cycle, 3) == 2 else 1.0
	return base_wind + sin(clock * .18) * 1.5 + gust * direction * 62.0 * float(weather_profile.get("gust", 1.0))

func wind_displacement(at: float, age: float) -> float:
	# Simpson sampling gives older exhaust a delayed bend instead of rotating
	# the whole plume at once when a gust reaches its source.
	return age * (wind_at(at - age) + 4.0 * wind_at(at - age * .5) + wind_at(at)) / 6.0

func smoke_offset(at: float, age: float, emitter: int = 0) -> Vector2:
	var drift := wind_displacement(at, age)
	var mean_wind := absf(drift) / maxf(age, .001)
	return Vector2(drift * .48 + sin(age * .7 + emitter) * age * .7, -age * 13.0 / (1.0 + mean_wind / 95.0))

func lamp_level(index: int, at: float) -> float:
	var individual_phase := index * 5.27 + phase
	var pulse := fposmod(at + individual_phase, 19.0 + index * 6.7)
	var dip := smoothstep(5.5, 6.1, pulse) * (1.0 - smoothstep(6.5, 7.7, pulse))
	var steady := 1.22 + sin(at * .83 + individual_phase) * .13 + sin(at * 1.37 + individual_phase * 1.7) * .07
	return clampf(steady - dip * .82, .34, 1.45)

func ash_count() -> int:
	return (7 if reduced_effects else MAX_ASH) if ash_enabled else 0

func ash_sample(index: int, at: float, bounds: Rect2) -> Dictionary:
	var seed_value := float(index) * 137.50776
	var depth := .35 + fposmod(seed_value * .017, .65)
	var life := 17.0 + float(index % 5)
	var age := fposmod(at + seed_value * .11, life)
	var drift := wind_displacement(at, age) * (.36 + depth * .30)
	var point := Vector2(bounds.position.x + fposmod(seed_value * 13.0 + drift, bounds.size.x), bounds.position.y + fposmod(seed_value * 7.0 + age * (8.0 + depth * 8.0), bounds.size.y))
	point.x += sin(at * .42 + seed_value) * 3.0 * depth
	var fade := smoothstep(0.0, 1.3, age) * (1.0 - smoothstep(life - 2.0, life, age))
	fade *= smoothstep(bounds.position.y, bounds.position.y + 28, point.y) * (1.0 - smoothstep(bounds.end.y - 28, bounds.end.y, point.y))
	var tint := Color("b8b7a9") if index % 6 else Color("bc8551")
	tint.a = (.20 + depth * .29) * fade * (.45 if reduced_effects else 1.0)
	return {"position":point.round(), "color":tint, "size":1 if index % 4 else 2}

func _draw() -> void:
	var bounds: Rect2 = scenery._visible_rect.intersection(Rect2(-3200, -2400, 7840, 2828))
	if not bounds.has_area(): return
	for index in ash_count():
		var sample := ash_sample(index, seconds, bounds)
		if is_instance_valid(scenery.get("distant_sky_lights")) and scenery.distant_sky_lights.visible:
			# Far airborne glints now sit behind the cloud bank. Preserve ash
			# around the industry/floor, with a soft altitude handover.
			var transition: float=scenery.panorama_rect.position.y+scenery.panorama_rect.size.y*.43
			sample.color.a*=smoothstep(transition,transition+60.0,sample.position.y)
		if sample.color.a >= .01:
			draw_rect(Rect2(sample.position, Vector2(sample.size, 1)), sample.color)
	for index in precipitation_count():
		var sample := precipitation_sample(index, seconds, bounds)
		if sample.color.a < .01: continue
		if sample.tail == Vector2.ZERO:
			draw_rect(Rect2(sample.position, Vector2.ONE * float(sample.size)), sample.color)
		else:
			draw_line(sample.position, sample.position + sample.tail, sample.color, 1.0)

# Precipitation is presentation-only: no physics bodies, audio events or world
# damage are created by a paused menu. Counts remain fixed at every resolution.
const PRECIPITATION_LIMIT := 156
const MENU_PROFILES := {
	"sector07": {"fall":"none", "count":0, "gust":1.0},
	"ash_foundry": {"fall":"none", "count":0, "gust":1.0},
	"abandoned_harbor": {"fall":"spray", "count":26, "gust":.86},
	"basalt_quarry": {"fall":"dust", "count":30, "gust":.65},
	"overgrown_steelworks": {"fall":"leaves", "count":22, "gust":.55},
	"frozen_rail_yard": {"fall":"snow", "count":92, "gust":.68},
	"iron_canyon": {"fall":"dust", "count":46, "gust":1.15},
	"flooded_power_station": {"fall":"rain", "count":92, "gust":.65},
	"mountain_pass": {"fall":"rain", "count":156, "gust":1.25},
	"storm_dam": {"fall":"rain", "count":144, "gust":1.15},
	"sulfur_refinery": {"fall":"dust", "count":32, "gust":.82},
	"radar_highlands": {"fall":"snow", "count":108, "gust":1.02},
	"buried_megafactory": {"fall":"dust", "count":28, "gust":.75},
}
var weather_profile: Dictionary = {}
var storm_layer: Node2D
var water_mist: Texture2D
var water_mist_layer: Node2D

func _prepare_weather() -> void:
	weather_profile = MENU_PROFILES.get(scenery.environment_id, MENU_PROFILES.ash_foundry)
	storm_layer = Node2D.new()
	storm_layer.name = "DistantMenuLightning"
	storm_layer.draw.connect(_draw_storm)
	scenery.add_child(storm_layer)
	# The painted buildings occlude the distant lightning. This cannot light
	# the menu controls or flash the full screen.
	scenery.move_child(storm_layer, scenery.panorama.get_index())
	var mist_path := "res://assets/atmosphere/menu_water_mist_v1.png"
	if ResourceLoader.exists(mist_path):
		water_mist = load(mist_path)
		water_mist_layer = Node2D.new()
		water_mist_layer.name = "WaterSprayBanks"
		var mist_material := ShaderMaterial.new()
		mist_material.shader = preload("res://shaders/menu_water_mist.gdshader")
		mist_material.set_shader_parameter("mist_tint", Color("96b7c3") if scenery.environment_id == "abandoned_harbor" else Color("a6bdb5"))
		water_mist_layer.material = mist_material
		water_mist_layer.draw.connect(_draw_water_mist)
		add_child(water_mist_layer)
		move_child(water_mist_layer, 0)

func gust_at(point: Vector2) -> float:
	return clampf(absf(wind_at(seconds - point.x * .0018)) / 72.0, .02, 1.0)

func wind_strength() -> float:
	return gust_at(Vector2.ZERO)

func precipitation_count() -> int:
	var count := mini(PRECIPITATION_LIMIT, int(weather_profile.get("count", 0)))
	return ceili(count / 4.0) if reduced_effects else count

func precipitation_sample(index: int, at: float, bounds: Rect2) -> Dictionary:
	var kind := str(weather_profile.get("fall", "none"))
	var seed_value := index * 137.50776 + phase * 17.0
	var depth := .30 + fposmod(seed_value * .017, .70)
	var speed := (310.0 + depth * 180.0) if kind == "rain" else (12.0 + depth * 16.0)
	var life := bounds.size.y / speed
	var age := fposmod(at + seed_value * .11, life)
	var drift := wind_displacement(at, minf(age, 12.0)) * (.28 + depth * .45)
	var point := Vector2(bounds.position.x + fposmod(seed_value * 13.0 + drift, bounds.size.x), bounds.position.y + age * speed)
	var tint := Color("b8d2dc")
	var tail := Vector2(-wind_at(at) * .025 * depth, -4.0 - depth * 8.0)
	var size := 1.0 if depth < .78 else 2.0
	match kind:
		"snow":
			point.x += sin(at * (.63 + depth * .47) + seed_value) * (4.0 + depth * 6.0)
			tint = Color("d6e3e8")
			tail = Vector2.ZERO
		"dust", "spray", "leaves":
			point.y = maxf(bounds.position.y, 130.0) + fposmod(seed_value * 7.0 + at * 7.0, maxf(1.0, bounds.end.y - maxf(bounds.position.y, 130.0)))
			point.y += sin(at * .7 + seed_value) * 4.0
			tint = Color("b7a089") if kind == "dust" else Color("92b5ba")
			if kind == "leaves": tint = Color("a5ac77") if index % 2 else Color("82986b")
			tail = Vector2(1.0 + absf(sin(at * 1.1 + seed_value)) * 2.0, 1.0) if kind == "leaves" else Vector2.ZERO
	var edge := smoothstep(0.0, 20.0, point.y - bounds.position.y) * (1.0 - smoothstep(0.0, 20.0, point.y - bounds.end.y + 20.0))
	tint.a = (.13 + depth * .33) * edge * (.58 if reduced_effects else 1.0)
	return {"position":point.round(), "tail":tail.round(), "color":tint, "size":size, "kind":kind}

func storm_strength(at: float) -> float:
	if reduced_effects or not bool(scenery.data.get("lightning", false)): return 0.0
	var within := fposmod(at + phase, 29.0)
	# One restrained, distant pulse with a soft rise/decay, separated by quiet.
	return smoothstep(20.0, 20.14, within) * (1.0 - smoothstep(20.20, 20.85, within)) * .72

func _draw_storm() -> void:
	var strength := storm_strength(seconds)
	if strength < .005: return
	var bounds: Rect2 = scenery._visible_rect
	var cycle := floori((seconds + phase) / 29.0)
	var at := Vector2(720 + sin(cycle * 2.31 + phase) * 480, maxf(bounds.position.y + 75, -380))
	var points := PackedVector2Array([at])
	for index in range(1, 9):
		points.append((at + Vector2(sin(index * 3.4 + cycle) * 16.0 + index * 5.0, index * 18.0)).round())
	for index in range(points.size() - 1):
		storm_layer.draw_line(points[index], points[index + 1], Color(.48, .64, .73, strength * .15), 5.0)
		storm_layer.draw_line(points[index], points[index + 1], Color(.76, .86, .90, strength * .55), 1.0)
	var branch := PackedVector2Array([points[3], points[3] + Vector2(-16, 18), points[3] + Vector2(-11, 28), points[3] + Vector2(-30, 43)])
	storm_layer.draw_polyline(branch, Color(.65, .79, .84, strength * .30), 1.0)

func _draw_water_mist() -> void:
	if water_mist == null: return
	var row := 0 if scenery.environment_id == "abandoned_harbor" else 1
	var source := Rect2(0, row * water_mist.get_height() * .5, water_mist.get_width(), water_mist.get_height() * .5)
	for region: Array in scenery.data.get("water_regions", []):
		var surface: Rect2 = scenery.region_rect(region)
		var width := minf(940.0, surface.size.x * 1.2)
		var height := clampf(surface.size.y * .60, 32, 90)
		var period := width * .72
		var drift := fposmod(seconds * 4.5 + wind_displacement(seconds, 8.0) * .08, period)
		for tile in range(-1, ceili(surface.size.x / period) + 1):
			var rect := Rect2(surface.position.x + tile * period + drift - width * .25, surface.position.y - height * .55, width, height)
			if not rect.intersects(scenery._visible_rect): continue
			water_mist_layer.draw_texture_rect_region(water_mist, rect, source, Color(1, 1, 1, .08 if reduced_effects else .18))
