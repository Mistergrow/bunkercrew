extends SceneTree
## Deterministic contact fixtures exercise allocation, support and splash travel.
## Rendering is checked separately in the running-game weather preview.

class WeatherFixture extends Node2D:
	var reduced_effects := false
	var covered := false
	var support_enabled := true
	var left := 0.0
	var right := 1000.0
	var ground_y := 100.0
	var surface_kind := "soil"
	var support: Node2D
	var intercepting_actor: Node2D
	var actor_y := 65.0
	func trace_rain(from: Vector2, to: Vector2, include_actors: bool = true, exclude_actor: Node = null) -> Dictionary:
		if include_actors and is_instance_valid(intercepting_actor) and intercepting_actor != exclude_actor and to.y >= from.y and from.y <= actor_y and to.y >= actor_y:
			var actor_fraction := inverse_lerp(from.y, to.y, actor_y)
			return {"position": from.lerp(to, actor_fraction), "normal": Vector2.UP, "material": "actor", "collider": intercepting_actor}
		if not support_enabled or to.y < from.y or from.y > ground_y + 0.001 or to.y < ground_y:
			return {}
		var fraction := inverse_lerp(from.y, to.y, ground_y) if not is_equal_approx(from.y, to.y) else 0.0
		var point := from.lerp(to, fraction)
		if point.x < left or point.x > right:
			return {}
		return {"position": point, "normal": Vector2.UP, "material": surface_kind, "collider": support}

var checks := 0
var failures := 0
var weather: WeatherFixture
var effects: SurfaceWeather

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func hit(point: Vector2 = Vector2(200, 100)) -> Dictionary:
	return {"position": point, "normal": Vector2.UP, "material": weather.surface_kind, "collider": weather.support}

func advance(seconds: float) -> void:
	for frame in ceili(seconds * 60.0):
		effects.advance(1.0 / 60.0)

func material_sample(kind: String) -> Dictionary:
	effects.particles.clear()
	effects.splashes.clear()
	effects._rng.seed = 91507
	weather.surface_kind = kind
	var contact := hit()
	contact.weather_prop = true
	for drop in 40:
		effects.on_rain_hit(contact, Vector2(24, 340), 1.0)
	var speed := 0.0
	var all_mud := not effects.particles.is_empty()
	var all_water := not effects.particles.is_empty()
	for particle in effects.particles:
		speed += Vector2(particle.velocity).length()
		all_mud = all_mud and particle.kind == "mud"
		all_water = all_water and particle.kind == "water"
	return {"drops": effects.particles.size(), "contacts": effects.splashes.size(),
		"speed": speed / maxf(1.0, effects.particles.size()), "all_mud": all_mud, "all_water": all_water}

func run_checks() -> void:
	weather = WeatherFixture.new()
	root.add_child(weather)
	weather.support = StaticBody2D.new()
	weather.add_child(weather.support)
	effects = SurfaceWeather.new()
	effects.weather = weather
	weather.add_child(effects)
	effects.set_physics_process(false)
	check(effects.surface_state_at(Vector2(200, 100)).wetness == 0.0, "Dry ground has no invented standing water")
	for contact in 12:
		effects.on_rain_hit(hit(), Vector2(24, 340), 1.0)
	var muddy := effects.surface_state_at(Vector2(200, 100))
	check(muddy.wetness > 0.9 and muddy.mud > 0.9 and muddy.material == "soil", "Repeated real earth contacts accumulate damp mud")
	check(effects.surface_state_at(Vector2(200, 95)).distance == 5.0 and muddy.distance == 0.0, "Lifted feet retain surface sampling but expose an exact planting distance")
	check(effects.patches.size() == 1, "Rain reuses the existing surface cell")
	check(effects.surface_state_at(Vector2(200, 145)).wetness == 0, "Wet roof cannot affect a sheltered floor below it")
	check(effects.surface_state_at(Vector2(200, 50)).wetness == 0, "Actors high above a wet surface do not acquire ground mud")
	weather.surface_kind = "concrete"
	for contact in 9:
		effects.on_rain_hit(hit(Vector2(350, 100)), Vector2(24, 340), 1.0)
	var stone := effects.surface_state_at(Vector2(350, 100))
	check(stone.wetness > 0.5 and stone.mud == 0, "Wet concrete produces water, never earth mud")
	var patch_count := effects.patches.size()
	weather.surface_kind = "glass"
	effects.on_rain_hit(hit(Vector2(450, 100)), Vector2(24, 340), 1.0)
	check(effects.patches.size() == patch_count, "Glass sheds droplets without horizontal mud or puddle decals")
	weather.surface_kind = "metal"
	var prop_hit := hit(Vector2(480, 100))
	prop_hit.weather_prop = true
	effects.on_rain_hit(prop_hit, Vector2(24, 340), 1.0)
	check(effects.patches.size() == patch_count, "Gun barrels and prop contours do not receive world-fixed puddle decals")
	var wall_hit := hit(Vector2(550, 100))
	wall_hit.normal = Vector2.LEFT
	effects.on_rain_hit(wall_hit, Vector2(24, 340), 1.0)
	check(effects.patches.size() == patch_count, "Vertical steel does not accumulate a floating puddle")
	var actor := CharacterBody2D.new()
	weather.add_child(actor)
	var actor_hit := hit(Vector2(120, 65))
	actor_hit.collider = actor
	actor_hit.material = "actor"
	for contact in 8:
		effects.on_rain_hit(actor_hit, Vector2(24, 340), 1.0)
	check(effects.patches.size() == patch_count, "Moving actor contacts never leave static patches")
	var attached_splash: Dictionary = {}
	for splash in effects.splashes:
		if splash.attachment != null and splash.attachment.get_ref() == actor:
			attached_splash = splash
			break
	var old_point: Vector2 = attached_splash.get("point", Vector2.ZERO)
	actor.position.x += 14.0
	effects.advance(1.0 / 60.0)
	check(not attached_splash.is_empty() and Vector2(attached_splash.point).is_equal_approx(old_point + Vector2(14, 0)), "First contact crown remains attached while an actor moves")
	actor.free()
	effects.advance(1.0 / 60.0)
	var stale_attachment := false
	for splash in effects.splashes:
		if splash.attachment != null and splash.attachment.get_ref() == null:
			stale_attachment = true
	check(not stale_attachment, "Despawned actors remove attached splashes without stale object access")
	# Reset supports: one real soil patch creates footfall effects, empty interiors do not.
	effects.patches.clear()
	effects.particles.clear()
	effects.splashes.clear()
	weather.surface_kind = "soil"
	for contact in 12:
		effects.on_rain_hit(hit(), Vector2(24, 340), 1.0)
	effects.particles.clear()
	effects.footstep(Vector2(200, 100), 1.0)
	check(effects.footprints.size() == 1 and effects.particles.size() >= 2, "A grounded wet-earth footfall leaves a short print and kicks mud")
	var steps := effects.footstep_count
	effects.footstep(Vector2(200, 430), 1.0)
	check(effects.footstep_count == steps, "A sheltered underground footfall cannot reuse surface mud")
	weather.support_enabled = false
	effects.footstep(Vector2(200, 100), 1.0)
	check(effects.footstep_count == steps, "A removed support cannot emit mud from stale wetness")
	advance(0.2)
	check(effects.patches.is_empty() and effects.footprints.is_empty(), "Unsupported puddles and prints are removed after geometry destruction")
	weather.support_enabled = true
	weather.left = 197
	weather.right = 203
	effects.on_rain_hit(hit(), Vector2(24, 340), 1.0)
	check(effects.patches.size() == 1 and float(effects.patches[0].width) <= 2.0, "Narrow support clips a wet strip instead of spanning open air")
	weather.left = 0
	weather.right = 1000
	effects.particles.clear()
	effects.splashes.clear()
	effects.emit_drip(Vector2(200, 92), Vector2(0, 45), 1.0)
	advance(0.15)
	check(effects.particles.is_empty() and not effects.splashes.is_empty(), "A helmet drip stops at the first ground hit and creates one ripple")
	advance(0.7)
	check(effects.particles.is_empty() and effects.splashes.is_empty(), "Secondary impacts terminate instead of recursively spawning water")
	var body := CharacterBody2D.new()
	weather.add_child(body)
	weather.intercepting_actor = body
	weather.actor_y = 65.0
	effects.emit_drip(Vector2(200, 64), Vector2(0, 80), 1.0, body)
	advance(0.03)
	check(effects.particles.size() == 1 and effects.splashes.is_empty(), "A new drip briefly excludes its source body rather than colliding inside its own helmet")
	effects.particles.clear()
	effects.emit_drip(Vector2(200, 60), Vector2(0, 80), 1.0)
	advance(0.10)
	var attached_to_other_body: bool = not effects.splashes.is_empty() and effects.splashes[0].attachment != null and effects.splashes[0].attachment.get_ref() == body
	check(effects.particles.is_empty() and attached_to_other_body, "Secondary water is intercepted by another body before reaching the ground")
	body.free()
	weather.intercepting_actor = null
	var cloth := material_sample("cloth")
	var wood := material_sample("wood")
	var soil := material_sample("soil")
	var stone_response := material_sample("concrete")
	var metal := material_sample("metal")
	check(cloth.drops == 0 and cloth.contacts > 0, "Cloth absorbs rain with tiny damp contacts and no hard-surface crown spray")
	check(wood.drops < stone_response.drops and wood.speed < stone_response.speed, "Wood gives fewer, slower rebounds than concrete under the same rain")
	check(soil.all_mud and soil.drops < stone_response.drops, "Earth impacts lift sparse brown mud instead of steel-colored water spray")
	check(stone_response.all_water and metal.all_water and metal.speed > stone_response.speed, "Concrete throws water while metal has a sharper physical rebound")
	weather.surface_kind = "soil"
	effects.particles.clear()
	effects.splashes.clear()
	# Long play cannot grow particles, decals or footprints without bound.
	weather.right = 100000
	for contact in 600:
		effects.on_rain_hit(hit(Vector2(20 + contact * 30, 100)), Vector2(24, 340), 1.0)
		effects.emit_drip(Vector2(200, 60))
	check(effects.particles.size() <= SurfaceWeather.MAX_PARTICLES and effects.splashes.size() <= SurfaceWeather.MAX_SPLASHES, "Heavy rain respects secondary particle and contact-crown budgets")
	check(effects.patches.size() <= SurfaceWeather.MAX_PATCHES, "Surface wetness storage remains bounded across arbitrarily wide levels")
	for contact in 12:
		effects.on_rain_hit(hit(), Vector2(24, 340), 1.0)
	for step in 200:
		effects.footstep(Vector2(200, 100))
	check(effects.footprints.size() <= SurfaceWeather.MAX_FOOTPRINTS, "Repeated movement cannot accumulate permanent footprints")
	weather.reduced_effects = true
	effects.advance(1.0 / 60.0)
	effects.emit_drip(Vector2(200, 60))
	effects.footstep(Vector2(200, 100))
	check(effects.particles.is_empty() and effects.splashes.is_empty(), "Reduced weather removes spray and suppresses new dripping motion")
	weather.reduced_effects = false
	advance(2.0)
	check(effects.particles.is_empty() and effects.splashes.is_empty(), "All transient water and mud particles expire after rain stops")
	advance(120.0)
	check(effects.patches.is_empty() and effects.footprints.is_empty(), "Stopped rain eventually dries all remaining supported wetness and tracks")
	weather.free()
	await process_frame
	print("SURFACE WEATHER CHECKS: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
