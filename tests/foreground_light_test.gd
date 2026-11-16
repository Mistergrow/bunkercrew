extends SceneTree
## The foreground belongs to each painted world: light measured from the real
## panorama (never stale), an ambient and sky-key rim per world, weather settled
## on the exterior's upward faces, per-world ground, and lightning that lights
## only what stands under the sky. Presentation only: no collision, no state.

const LIGHTING := preload("res://scripts/world_lighting.gd")
const KEYS := preload("res://scripts/backdrop_light_keys.gd")
const STRATA := preload("res://scripts/terrain_strata.gd")
const ACCUMULATION := preload("res://scripts/weather_accumulation.gd")
const GRADE := preload("res://scripts/backdrop_grade.gd")
const WET := preload("res://scripts/actor_wet_materials.gd")
const PERIMETER := preload("res://scripts/perimeter_art.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FOREGROUND LIGHT FAIL: ", label)
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	_check_measured_keys()
	_check_static_derivation()
	for id: String in ["frozen_rail_yard", "storm_dam", "ash_foundry", "overgrown_steelworks"]:
		await _check_world(id)
	print("FOREGROUND LIGHT RESULT: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The table is measured from the panoramas that ship (hash-pinned): a
## repainted world must be measured again (tools/generate_backdrop_light.py).
func _check_measured_keys() -> void:
	var measured := 0
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var data: Dictionary = ScenarioCatalog.environment(str(entry.id))
		var path := str(data.get("path", ""))
		if not KEYS.KEYS.has(str(entry.id)) or not FileAccess.file_exists(path): continue
		var key: Dictionary = KEYS.KEYS[str(entry.id)]
		check(str(key.source) == path and FileAccess.get_sha256(path) == str(key.sha256), str(entry.id) + " light key matches its shipped panorama")
		check(key.sky is Color and key.land is Color and key.key is Color and absf(float(key.key_x)) <= 1.0, str(entry.id) + " light key is complete")
		check(LIGHTING.luminance(key.key) >= LIGHTING.luminance(key.sky), str(entry.id) + " the key light is the brightest part of the sky")
		measured += 1
	check(measured >= 13, "Every catalog panorama is measured (%d)" % measured)

func _check_static_derivation() -> void:
	var rims := {}
	var hues := {}
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var data: Dictionary = ScenarioCatalog.environment(str(entry.id))
		var rim: Color = LIGHTING.sky_rim_for(data)
		check(rim.a > .05 and rim.a <= .32 and maxf(rim.r, maxf(rim.g, rim.b)) <= 1.001, str(entry.id) + " sky rim is a gentle accent")
		check(absf(LIGHTING.key_side_for(data)) <= 1.0, str(entry.id) + " key side is bounded")
		rims[rim.to_html(false)] = true
		hues[LIGHTING.light_hue(data).to_html(false)] = true
		var kind := STRATA.surface_for(data)
		var subsoil := STRATA.subsoil_for(kind, LIGHTING.light_key(data).land)
		check(LIGHTING.luminance(subsoil) > .12 and LIGHTING.luminance(subsoil) < .50, str(entry.id) + " topsoil keeps a ground value")
	check(rims.size() >= 10 and hues.size() >= 10, "Worlds get their own sky key and light hue (%d / %d)" % [rims.size(), hues.size()])
	# Measured worlds: the painted night is night, the painted day is day.
	check(LIGHTING.night_for(ScenarioCatalog.environment("ash_foundry")) > .8 and LIGHTING.night_for(ScenarioCatalog.environment("frozen_rail_yard")) < .2, "Night and day follow the painting")
	# A world nobody measured falls back to its catalog colours.
	var unknown := {"id":"unmeasured_test_world", "sky_color":"#304050", "palette":["#101820", "#d0a060"]}
	check(LIGHTING.light_key(unknown).key == Color("#d0a060") and LIGHTING.ambient_for(unknown).a == 1.0, "An unmeasured world derives its light from the catalog")
	var repainted := ScenarioCatalog.environment("frozen_rail_yard").duplicate()
	repainted.path = "res://content/other.png"
	check(not LIGHTING.light_key(repainted).has("sha256"), "A repainted world does not reuse another panorama's measurement")
	check(GRADE.haze_texture().get_width() == GRADE.HAZE_PERIOD and GRADE.haze_texture().get_height() == GRADE.HAZE_HEIGHT, "Ground haze is one small shared texture")

func _check_world(id: String) -> void:
	var data: Dictionary = ScenarioCatalog.environment(id)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2, {"environment":id, "build_type":"bastion", "position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.weather.set_reduced_effects(false)
	for frame in 30: await process_frame
	var bunker: ScenarioBunker = game.scenario_bunker
	var lighting: Node2D = bunker.lighting
	var accumulation: Node2D = lighting.accumulation
	var kind := STRATA.surface_for(data)
	# Weather settled on the roof and the crates outside; rebuilt only on change.
	var report: Dictionary = accumulation.diagnostics()
	check(int(report.kind) == kind and int(report.rects) > 0 and int(report.rects) <= ACCUMULATION.MAX_RECTS, id + " exterior tops carry settled weather or the sky key (%d)" % int(report.rects))
	check(accumulation.get_child_count() == 0 and accumulation.get_groups().is_empty() and not accumulation is CollisionObject2D, id + " settled weather adds no bodies")
	var spans: Array[Vector3] = accumulation.top_spans()
	var crates := 0
	for span in spans:
		if span.z < ScenarioBunker.ROOF_Y - 1.0: crates += 1
	check(crates >= 5, id + " every crate outside gets a lid cap (%d)" % crates)
	var builds := int(report.builds)
	for frame in 40: await process_frame
	check(int(accumulation.diagnostics().builds) == builds, id + " an unchanged layout is not rebuilt")
	var fence: ShaderMaterial = PERIMETER.pixel_material()
	var settle := int(fence.get_shader_parameter("settle_kind"))
	check(settle == (kind if kind in [1, 3, 4, 5] else 0), id + " perimeter tops follow the catalog weather")
	var fence_rim: Color = fence.get_shader_parameter("sky_rim")
	var world_rim: Color = lighting.sky_rim
	check(Color(fence_rim, 1.0).is_equal_approx(Color(world_rim, 1.0)) and fence_rim.a > 0.0 and fence_rim.a <= world_rim.a + .001, id + " perimeter catches the world's sky key (dimmed only by a storm)")
	# Ground: per-world topsoil and an uneven cover over the ground line.
	var strata := bunker.get_node("TerrainStrata") as Node2D
	var ground: ShaderMaterial = strata.material
	check((ground.get_shader_parameter("subsoil_tint") as Color).is_equal_approx(STRATA.subsoil_for(kind, LIGHTING.light_key(data).land)), id + " topsoil is this world's ground")
	check(is_equal_approx(float(ground.get_shader_parameter("cover_rise")), STRATA.COVER_RISE), id + " ground cover may rise above the ground line")
	check(bool(ground.get_shader_parameter("rich")) == not LIGHTING.software_renderer(), id + " software rasterisers get the plain ground tier")
	# Lightning lights only what is under the sky.
	var key_before := LIGHTING.luminance(lighting.actor_key.color)
	var interior: Rect2 = lighting.interior_rect()
	check(interior.position.x == float(bunker.room_left) and interior.end.x == float(bunker.room_right), id + " interior stops at the bunker walls")
	var peak := 0.0
	var canvas_steady := true
	var key_steady := true
	var ground_lit := false
	var actors_lit := false
	game.weather.lightning_enabled = true
	game.weather.lightning_wait = 0.0
	await process_frame
	if float(game.weather.lightning_age) > .1: game.weather.lightning_age = 0.0
	for frame in 4:
		await process_frame
		peak = maxf(peak, float(lighting.flash))
		# The canvas ambient (interior, props, underground) never brightens.
		canvas_steady = canvas_steady and LIGHTING.luminance(lighting.graded_ambient()) <= LIGHTING.luminance(lighting.ambient) + .001
		key_steady = key_steady and LIGHTING.luminance(lighting.actor_key.color) >= key_before * .95 - .001
		ground_lit = ground_lit or float(ground.get_shader_parameter("flash")) > .3
		actors_lit = actors_lit or WET.flash > .3
	check(peak > .8, id + " a strike flashes the exterior (%.2f)" % peak)
	check(canvas_steady and key_steady, id + " the interior, underground and actor key keep their light during a flash")
	check(ground_lit and actors_lit, id + " the exposed ground and outdoor actors take the flash")
	var bolt: PackedVector2Array = game.weather.bolt
	var source := bolt[-1].x if not bolt.is_empty() else float(game.weather.thunder_origin.x)
	check(absf(float(lighting.flash_x) - source) < 1.0, id + " the flash comes from the bolt's side")
	await create_timer(.4).timeout
	await process_frame
	check(float(lighting.flash) < .05, id + " the flash falls off within 0.4 s (%.3f)" % float(lighting.flash))
	# Reduced effects: no flash at all.
	game.weather.set_reduced_effects(true)
	for frame in 3: await process_frame
	game.weather.lightning_age = 0.0
	for frame in 3: await process_frame
	check(float(lighting.flash) == 0.0 and float(ground.get_shader_parameter("flash")) == 0.0, id + " reduced effects never flash")
	game.weather.set_reduced_effects(false)
	# Deeper rooms: dimmer, colder fill than the surface room.
	var energies: Array[float] = []
	for entry: Dictionary in lighting.fixtures:
		if str(entry.kind) == "room": energies.append(float(entry.energy))
	check(energies.size() >= 1 and (energies.size() == 1 or energies[-1] < energies[0]), id + " deeper rooms are lit less")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), id + " cleans up")
