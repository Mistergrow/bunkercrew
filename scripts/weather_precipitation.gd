extends Node2D
## Falling weather a player can actually see at 1:1: rain streaks, snow, ash
## with embers, drifting dust or mist droplets, in three depth layers. Two far
## layers sit behind the foreground (the bunker, rock and props hide them for
## free); the near layer falls in front of the actors and is clipped to the
## open sky above the real roof and ground line. Every particle lives in a
## MultiMesh and is animated by shaders/weather_precipitation.gdshader from
## the weather's presentation clock: no per-particle script work, fixed pools,
## nothing replicated. Absent with reduced effects and outside a running match.
const SHADER := preload("res://shaders/weather_precipitation.gdshader")
const SHELTER_STEP := 8.0
const SHELTER_COLUMNS := 384
const TILE_STEP := 256.0
const MARGIN := 24.0
const CLOCK_PERIOD := 1024.0
const FAR_Z := -9
const NEAR_Z := 20
## Per weather kind: far, middle and near layer. count: instances in the view
## tile; fall: world px/s; streak: length of a rain streak; sway: drift px;
## parallax: share of the camera motion (positive = farther away); wind: share
## of the weather's gust speed; alpha: base opacity.
const KINDS := {
	"rain": [
		{"count":520, "fall":260.0, "streak":8.0, "alpha":.46, "parallax":.40, "wind":.55},
		{"count":320, "fall":380.0, "streak":12.0, "alpha":.60, "parallax":.16, "wind":.80},
		{"count":90, "fall":580.0, "streak":18.0, "alpha":.70, "parallax":-.10, "wind":1.10},
	],
	"snow": [
		{"count":760, "fall":20.0, "sway":4.0, "alpha":.86, "parallax":.40, "wind":.35, "spread":[.80, 1.06]},
		{"count":480, "fall":32.0, "sway":7.0, "alpha":1.0, "parallax":.16, "wind":.55, "spread":[1.0, 1.42]},
		{"count":110, "fall":52.0, "sway":11.0, "alpha":1.0, "parallax":-.10, "wind":.80, "spread":[1.16, 1.45]},
	],
	# Ash is not snow: grey and charcoal flakes (ASH_TONES) that sink slowly
	# and tumble wide on the air, a dense far veil, and glowing embers that
	# rise on the heat instead of falling (weather_precipitation.gdshader);
	# a warm-grey haze hangs over the backdrop (HAZE).
	"ash": [
		{"count":900, "fall":8.0, "sway":9.0, "alpha":.80, "parallax":.40, "wind":.30, "tumble":.35, "embers":.09, "spread":[.85, 1.10]},
		{"count":520, "fall":12.0, "sway":13.0, "alpha":.94, "parallax":.16, "wind":.45, "tumble":.50, "embers":.11, "spread":[1.0, 1.36]},
		{"count":130, "fall":17.0, "sway":18.0, "alpha":1.0, "parallax":-.10, "wind":.65, "tumble":.70, "embers":.14, "spread":[1.14, 1.42]},
	],
	"dust": [
		{"count":160, "fall":3.0, "sway":6.0, "alpha":.52, "parallax":.40, "wind":.75},
		{"count":90, "fall":5.0, "sway":9.0, "alpha":.64, "parallax":.16, "wind":1.0},
		{"count":22, "fall":7.0, "sway":13.0, "alpha":.70, "parallax":-.10, "wind":1.25, "spread":[1.15, 1.35]},
	],
	"mist": [
		{"count":160, "fall":7.0, "sway":6.0, "alpha":.40, "parallax":.40, "wind":.50},
		{"count":90, "fall":11.0, "sway":8.0, "alpha":.50, "parallax":.16, "wind":.70},
	],
}
## Flake tones of ash by share: pale ash, grey, charcoal (value, share). Kept
## well below snow's near-white so ash never reads as snow.
const ASH_TONES := [[.62, .25], [.45, .40], [.28, .35]]
## The same tones under a night sky, where charcoal would vanish: lifted
## only to a warm mid grey (lit by the furnaces), never toward white.
const ASH_TONES_NIGHT := [[.60, .30], [.48, .40], [.37, .30]]
## Haze over the backdrop per kind (behind the play plane): colour, alpha.
const HAZE := {"ash": Color(.40, .33, .28, .08)}
## Embers carry this offset on their speed factor (UV.x) so the shader can
## tell them apart; the factor itself stays below it.
const EMBER_FLAG := 4.0
var weather: Node2D
var kind := ""
var layers: Array[MeshInstance2D] = []
var haze: Node2D
var shelter_image: Image
var shelter_texture: ImageTexture
var shelter_updates := 0
var _shelter_cache: Dictionary = {}
var _shelter_clock := 1.0
var _cache_clock := 0.0
var _tile := Rect2()
var _environment: Dictionary = {}

func _ready() -> void:
	name = "Precipitation"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	shelter_image = Image.create(SHELTER_COLUMNS, 1, false, Image.FORMAT_RF)
	shelter_image.fill(Color(-100000.0, 0, 0))
	shelter_texture = ImageTexture.create_from_image(shelter_image)

## Kind of falling material for a catalog world; "" for clear skies.
static func kind_for(environment: Dictionary, rain_base: float) -> String:
	var weather_kind := str(environment.get("weather", "storm"))
	if weather_kind in ["rain", "storm"]: return "rain" if rain_base > 0.0 else ""
	if weather_kind in ["snow", "ash", "dust", "mist"]: return weather_kind
	return ""

func configure_environment(environment: Dictionary) -> void:
	_environment = environment
	for layer in layers: layer.queue_free()
	layers.clear()
	_shelter_cache.clear()
	kind = kind_for(environment, float(weather.get("rain_base_strength")) if is_instance_valid(weather) else 0.0)
	if kind.is_empty(): return
	var specs: Array = KINDS[kind]
	var random := RandomNumberGenerator.new()
	random.seed = 50311 + str(environment.get("id", "")).hash() % 1000
	for depth in specs.size():
		layers.append(_build_layer(specs[depth], depth, depth == specs.size() - 1 and specs.size() == 3, random))
	_build_haze()
	_apply_visibility()

## A translucent haze over the backdrop for kinds that thicken the air (ash):
## one rect behind every foreground layer, following the view.
func _build_haze() -> void:
	if is_instance_valid(haze):
		haze.queue_free()
		haze = null
	# A full-view blended layer: left out on the software tier.
	if not HAZE.has(kind) or preload("res://scripts/world_lighting.gd").software_renderer(): return
	haze = Node2D.new()
	haze.name = "WeatherHaze"
	haze.z_as_relative = false
	haze.z_index = FAR_Z - 1
	var flat := CanvasItemMaterial.new()
	flat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	haze.material = flat
	haze.draw.connect(_draw_haze)
	add_child(haze)

func _draw_haze() -> void:
	if not _tile.has_area(): return
	var tint: Color = HAZE.get(kind, Color(0, 0, 0, 0))
	haze.draw_rect(_tile, tint)

func _palette(depth: int, spec: Dictionary) -> Array[Color]:
	# Bright enough against a night sky, never brighter than a lit lamp.
	var sky := Color(str(_environment.get("sky_color", "#808890")))
	var night := 1.0 - smoothstep(.20, .58, sky.r * .299 + sky.g * .587 + sky.b * .114)
	var near := float(depth) / 2.0
	var base: Color
	var accent := Color(0, 0, 0, 0)
	match kind:
		"rain": base = Color(.84, .90, .95).lerp(sky.lightened(.65), .2)
		"snow": base = Color(.97, .98, 1.0).lerp(Color(.80, .85, .96), night * .5)
		"ash":
			base = Color(.80, .77, .73).lerp(Color(.66, .65, .68), night * .3)
			accent = Color(1.0, .64, .26)
		"dust":
			var profile: Dictionary = preload("res://scripts/world_wind.gd").PROFILES.get(str(_environment.get("id", "")), {})
			base = profile.get("tint", Color(.72, .66, .55)) if not profile.is_empty() else Color(.72, .66, .55)
		_: base = Color(.78, .84, .86)
	base = base.lerp(Color.WHITE, near * .12)
	base.a = float(spec.alpha) * lerpf(1.0, 1.15, night)
	if accent.a == 0.0: accent = base
	else: accent.a = minf(1.0, float(spec.alpha) + .2)
	return [base, accent]

## One ash flake's colour: a tone from ASH_TONES picked by `pick`, warm grey,
## a little lighter in the nearer layers, with the layer's alpha.
func _ash_tone(pick: float, base: Color, depth: int) -> Color:
	var sky := Color(str(_environment.get("sky_color", "#808890")))
	var tones: Array = ASH_TONES_NIGHT if sky.r * .299 + sky.g * .587 + sky.b * .114 < .35 else ASH_TONES
	var value := float(tones[0][0])
	var total := 0.0
	for tone: Array in tones:
		total += float(tone[1])
		if pick <= total:
			value = float(tone[0])
			break
	value *= 1.0 + float(depth) * .05
	# Warm grey: soot and cinder, never the cool white of snow.
	return Color(value * 1.10, value * .98, value * .86, base.a)

func _build_layer(spec: Dictionary, depth: int, near: bool, random: RandomNumberGenerator) -> MeshInstance2D:
	var streak := float(spec.get("streak", 0.0))
	var count := int(spec.count)
	var colors := _palette(depth, spec)
	var spread: Array = spec.get("spread", [.85, 1.15])
	var embers := float(spec.get("embers", 0.0))
	var halves := [[0.0, .5, 0.0], [.5, 1.0, 2.0]] if streak > 0.0 else [[0.0, 1.0, 0.0]]
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tints := PackedColorArray()
	for index in count:
		var cell := Vector2(random.randi_range(0, 1023), random.randi_range(0, 1023)) * 8.0
		var factor := random.randf_range(float(spread[0]), float(spread[1]))
		# Seeds are spread evenly, so a partial shower thins out uniformly.
		var seed_value := (float(index) + random.randf_range(.05, .95)) / float(count)
		var ember := random.randf() < embers
		var tint: Color = colors[1] if ember else colors[0]
		tint.a *= random.randf_range(.72, 1.0)
		if kind == "ash" and not ember:
			tint = _ash_tone(random.randf(), tint, depth)
		# Embers rise on the heat: flagged on the speed factor for the shader.
		var packed_factor := factor + (EMBER_FLAG if ember and kind == "ash" else 0.0)
		for half: Array in halves:
			var top := float(half[0])
			var bottom := float(half[1])
			var lower := float(half[2])
			for corner in [Vector2(0, top), Vector2(1, top), Vector2(1, bottom), Vector2(0, top), Vector2(1, bottom), Vector2(0, bottom)]:
				vertices.append(cell + corner + Vector2(lower, 0))
				uvs.append(Vector2(packed_factor, seed_value))
				tints.append(tint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = tints
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader places every particle inside the view; never cull the layer.
	mesh.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	var layer := MeshInstance2D.new()
	layer.name = ["FarFall", "MiddleFall", "NearFall"][depth]
	layer.mesh = mesh
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_as_relative = false
	layer.z_index = NEAR_Z if near else FAR_Z
	var paint := ShaderMaterial.new()
	paint.shader = SHADER
	paint.set_shader_parameter("streak", streak)
	paint.set_shader_parameter("sway", float(spec.get("sway", 0.0)))
	paint.set_shader_parameter("tumble", float(spec.get("tumble", 0.0)))
	paint.set_shader_parameter("fall_speed", float(spec.fall))
	paint.set_shader_parameter("use_shelter", near)
	paint.set_shader_parameter("shelter", shelter_texture)
	paint.set_shader_parameter("shelter_step", SHELTER_STEP)
	layer.material = paint
	layer.set_meta("spec", spec)
	layer.set_meta("count", count)
	add_child(layer)
	return layer

func _active() -> bool:
	if kind.is_empty() or not is_instance_valid(weather) or bool(weather.get("reduced_effects")): return false
	var game: Variant = weather.get("game")
	return not is_instance_valid(game) or not "started" in game or bool(game.started)

func _apply_visibility() -> void:
	var active := _active()
	for layer in layers: layer.visible = active
	if is_instance_valid(haze): haze.visible = active

func set_reduced(_value: bool) -> void:
	_apply_visibility()

func _view() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()

func _amount() -> float:
	if kind == "rain":
		return clampf(float(weather.get("rain_strength")), 0.0, 1.0)
	return 1.0

func _process(delta: float) -> void:
	var active := _active()
	if layers.is_empty() or (not active and not layers[0].visible): return
	if active != layers[0].visible: _apply_visibility()
	if not active or not is_finite(delta): return
	var view := _view()
	if not view.size.is_finite() or view.size.x < 8.0: return
	var size := ((view.size + Vector2(MARGIN, MARGIN) * 2.0) / TILE_STEP).ceil() * TILE_STEP
	var tile := Rect2((view.position - Vector2(MARGIN, MARGIN)).floor(), size)
	if is_instance_valid(haze) and not tile.is_equal_approx(_tile): haze.queue_redraw()
	_tile = tile
	var center := view.get_center()
	var clock := fposmod(float(weather.get("elapsed")), CLOCK_PERIOD)
	var gust: float = weather.wind_at(center).x
	var flash: float = weather.lightning_strength() if weather.has_method("lightning_strength") else 0.0
	var amount := _amount()
	_shelter_clock += delta
	_cache_clock += delta
	if _cache_clock >= 1.0:
		# Hatches, a new flak deck or the dome change the cover only rarely.
		_cache_clock = 0.0
		_shelter_cache.clear()
	if _shelter_clock >= .2:
		_shelter_clock = 0.0
		_update_shelter()
	for layer in layers:
		var spec: Dictionary = layer.get_meta("spec")
		var paint := layer.material as ShaderMaterial
		var wind := gust * float(spec.wind)
		paint.set_shader_parameter("clock", clock)
		paint.set_shader_parameter("tile_origin", _tile.position)
		paint.set_shader_parameter("tile_size", _tile.size)
		paint.set_shader_parameter("parallax_shift", (center * float(spec.parallax)).round())
		paint.set_shader_parameter("wind", wind)
		paint.set_shader_parameter("amount", amount)
		paint.set_shader_parameter("flash", flash)
		if float(spec.get("streak", 0.0)) > 0.0:
			# The lower half of a streak steps sideways with the wind, whole pixels only.
			paint.set_shader_parameter("slant", clampf(roundf(float(spec.streak) * .5 * wind / maxf(1.0, float(spec.fall))), 0.0, 2.0))

func _shelter_at(column: int) -> float:
	if _shelter_cache.has(column): return _shelter_cache[column]
	var x := (float(column) + .5) * SHELTER_STEP
	var cover := minf(weather.rain_surface(x - 3.0), weather.rain_surface(x + 3.0))
	var game: Variant = weather.get("game")
	if is_instance_valid(game) and is_instance_valid(game.get("scenario_bunker")):
		var bunker: Node2D = game.scenario_bunker
		cover = minf(cover, float(bunker.ground_y))
		# Never inside the cut-away rooms: the roof line is the cover there.
		if x >= float(bunker.room_left) - 4.0 and x <= float(bunker.room_right) + 4.0:
			cover = minf(cover, ScenarioBunker.ROOF_Y)
	_shelter_cache[column] = cover
	return cover

func _update_shelter() -> void:
	if not is_instance_valid(weather) or not weather.has_method("rain_surface"): return
	var first := floori(_tile.position.x / SHELTER_STEP)
	var count := mini(SHELTER_COLUMNS, ceili(_tile.size.x / SHELTER_STEP) + 1)
	for index in count:
		shelter_image.set_pixel(index, 0, Color(_shelter_at(first + index), 0, 0))
	shelter_texture.update(shelter_image)
	shelter_updates += 1
	for layer in layers:
		var paint := layer.material as ShaderMaterial
		if not bool(paint.get_shader_parameter("use_shelter")): continue
		paint.set_shader_parameter("shelter_left", float(first) * SHELTER_STEP)
		paint.set_shader_parameter("shelter_count", float(count))
		paint.set_shader_parameter("shelter_width", float(SHELTER_COLUMNS))

func diagnostics() -> Dictionary:
	var instances := 0
	for layer in layers: instances += int(layer.get_meta("count"))
	return {"kind":kind, "layers":layers.size(), "instances":instances, "visible":not layers.is_empty() and layers[0].visible,
		"shelter_updates":shelter_updates, "tile":_tile}
