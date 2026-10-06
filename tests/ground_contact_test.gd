extends SceneTree
## Actual physics support and RainCollision; no background image can be stepped on.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/ground_surface_catalog.gd")

class GameFixture extends Node2D:
	var scenario_options := {"environment": "sector07"}
	var scenario_bunker: ScenarioBunker

class WeatherFixture extends Node2D:
	var game: GameFixture
	var reduced_effects := false
	var prop_surfaces: Node2D
	var collision := RainCollision.new()
	func _ready() -> void:
		collision.weather = self
	func wind_speed() -> float:
		return 0.0
	func trace_rain(from: Vector2, to: Vector2, actors := true, exclude_actor: Node = null) -> Dictionary:
		return collision.trace(from, to, actors, exclude_actor)
	func exposure_at(point: Vector2, excluded: Node = null) -> float:
		return collision.exposure_at(point, excluded)

var checks := 0
var failures := 0
var fixture: GameFixture
var weather: WeatherFixture
var effects: SurfaceWeather

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("GROUND %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func floor_body(rect: Rect2, surface_kind: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("weather_material", surface_kind)
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	fixture.add_child(body)
	return body

func wait_physics() -> void:
	await physics_frame
	await process_frame
	weather.collision.invalidate()

func run() -> void:
	fixture = GameFixture.new()
	root.add_child(fixture)
	fixture.scenario_bunker = ScenarioBunker.new()
	fixture.scenario_bunker.room_left = 90.0
	fixture.scenario_bunker.room_right = 730.0
	var terrain := floor_body(Rect2(-400, 430, 2300, 24), "soil")
	floor_body(Rect2(90, 245, 640, 18), "concrete")
	floor_body(Rect2(1180, 200, 70, 12), "metal")
	weather = WeatherFixture.new()
	weather.game = fixture
	fixture.add_child(weather)
	effects = SurfaceWeather.new()
	effects.weather = weather
	weather.add_child(effects)
	effects.set_physics_process(false)
	await wait_physics()
	for environment in Catalog.PROFILES:
		fixture.scenario_options.environment = environment
		effects.ground.prepare()
		var dry := effects.sample_contact(Vector2(1050, 430))
		check(dry.supported and dry.point.is_equal_approx(Vector2(1050, 430)) and dry.normal == Vector2.UP and is_zero_approx(float(dry.distance)), "%s uses the actual supported point and normal" % environment)
		var lifted := effects.sample_contact(Vector2(1050, 424))
		check(lifted.supported and is_equal_approx(float(lifted.distance), 6.0), "%s lifted sole reports positive exact distance" % environment)
		check(not effects.sample_contact(Vector2(1050, 413)).supported and not effects.sample_contact(Vector2(1050, 360)).supported, "%s air/background water never counts as support" % environment)
		var indoor := effects.sample_contact(Vector2(400, 430))
		var roof := effects.sample_contact(Vector2(400, 245))
		var metal := effects.sample_contact(Vector2(1205, 200))
		check(indoor.kind == "dry" and roof.kind == "dry" and metal.kind == "metal", "%s bunker, roof and raised metal remain distinct from outdoor deposits" % environment)
		var clear := true
		var positions: Array[Vector2] = []
		for field in effects.ground.fields:
			positions.append(field.point)
			clear = clear and (field.point.x < 78 or field.point.x > 742) and not (field.point.x >= 1180 and field.point.x <= 1250)
			var contact := effects.sample_contact(field.point)
			clear = clear and contact.supported and contact.kind == field.kind
		check(clear, "%s visible deposits occupy only exposed, walkable outdoor support" % environment)
		effects.ground._configured = false
		effects.ground.prepare()
		var rebuilt: Array[Vector2] = []
		for field in effects.ground.fields:
			rebuilt.append(field.point)
		check(positions == rebuilt, "%s deposits are deterministic across reconstruction" % environment)
		if environment in ["abandoned_harbor", "flooded_power_station", "frozen_rail_yard"]:
			check(not positions.is_empty(), "%s presents real visible surface patches" % environment)
	fixture.scenario_options.environment = "ash_foundry"
	effects.ground.prepare()
	effects.ground.chips.clear()
	effects.ground.plumes.clear()
	var dry_state := effects.sample_contact(Vector2(1050, 430))
	effects.contact_event(Vector2(1050, 430), 0.75, null, dry_state)
	var light_count: int = effects.ground.chips.size()
	var light_spread: float = effects.ground.plumes[-1].spread
	effects.ground.chips.clear()
	effects.ground.plumes.clear()
	effects.contact_event(Vector2(1050, 430), 2.2, null, dry_state)
	check(effects.ground.chips.size() > light_count and float(effects.ground.plumes[-1].spread) > light_spread, "Heavy supported machines lift more local grit and broader dust than light steps")
	var actor := Node2D.new()
	fixture.add_child(actor)
	var before := effects.footstep_count
	for foot in 8:
		effects.contact_event(Vector2(1050, 430), 2.0, actor, dry_state)
	check(effects.footstep_count == before + 1, "Multiple machine feet share one bounded 0.12-second VFX impulse")
	before = effects.footstep_count
	effects.footstep(Vector2(1050, 424))
	check(effects.footstep_count == before, "A near-ground but airborne sole cannot emit a contact effect")
	fixture.scenario_options.environment = "flooded_power_station"
	effects.ground.prepare()
	var water_point: Vector2 = effects.ground.fields[0].point
	effects.particles.clear()
	effects.splashes.clear()
	var water := effects.footstep(water_point, 1.0)
	var ring := false
	var fan := false
	for splash in effects.splashes:
		ring = ring or splash.kind == "ripple"
		fan = fan or splash.kind == "foot_fan"
	check(water.kind == "water" and effects.particles.size() >= 2 and ring and fan, "Real puddle footfall produces local water fan, drops and a short ring")
	var clean_fan := false
	for splash in effects.splashes:
		clean_fan = clean_fan or (splash.kind == "foot_fan" and splash.material != "soil")
	check(clean_fan, "A clear puddle on soil keeps the fan water-colored")
	for drop in 12:
		effects.on_rain_hit({"position": water_point, "normal": Vector2.UP, "material": "soil", "collider": terrain}, Vector2(0, 300))
	effects.splashes.clear()
	effects.footstep(water_point)
	var muddy_fan := false
	for splash in effects.splashes:
		muddy_fan = muddy_fan or (splash.kind == "foot_fan" and splash.material == "soil")
	check(muddy_fan, "Actually rain-soaked earth retains its muddy contact fan")
	fixture.scenario_options.environment = "frozen_rail_yard"
	effects.ground.prepare()
	var ice_point: Vector2 = effects.ground.fields[0].point
	effects.ground.chips.clear()
	effects.footstep(ice_point, 1.0)
	check(not effects.ground.tracks.is_empty() and not effects.ground.chips.is_empty() and effects.ground.chips[-1].ice, "Frozen outdoor support sheds ice/snow crumbs and a temporary sole trace")
	var saved_clock := effects.elapsed
	var saved_tracks: Array = effects.ground.tracks.duplicate(true)
	paused = true
	effects.advance(0.5)
	check(effects.elapsed == saved_clock and effects.ground.tracks == saved_tracks, "Pause freezes dust, deposits and sole marks")
	paused = false
	weather.reduced_effects = true
	effects.advance(0.01)
	var quiet_state := effects.footstep(ice_point)
	check(quiet_state.kind == "ice" and quiet_state.supported and effects.ground.chips.is_empty() and effects.ground.plumes.is_empty() and effects.particles.is_empty(), "F3 retains material feedback for audio while suppressing moving VFX")
	weather.reduced_effects = false
	for step in 250:
		effects.footstep(ice_point, 2.2)
	check(effects.ground.chips.size() <= effects.ground.MAX_CHIPS and effects.ground.plumes.size() <= effects.ground.MAX_PLUMES and effects.ground.tracks.size() <= effects.ground.MAX_TRACKS and effects.ground.fields.size() <= effects.ground.MAX_FIELDS, "Ground debris, dust, marks and visible deposits have fixed storage limits")
	terrain.queue_free()
	await wait_physics()
	check(not effects.sample_contact(ice_point).supported, "Destroyed physical ground invalidates contact immediately")
	for tick in 20:
		effects.advance(0.1)
	check(effects.ground.fields.is_empty() and effects.ground.tracks.is_empty() and effects.ground.chips.is_empty() and effects.ground.plumes.is_empty(), "Destroyed floors leave no floating ground deposits, traces or debris")
	fixture.scenario_bunker.free()
	check(await Cleanup.free_scene(fixture, self), "Ground contact fixture releases cleanly")
	print("GROUND CONTACTS: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
