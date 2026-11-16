extends SceneTree
## Ambient, fixture lights, contact shadows and ground cover are presentation
## derived from the catalog: bounded, readable, and without physical effect.

const LIGHTING := preload("res://scripts/world_lighting.gd")
const STRATA := preload("res://scripts/terrain_strata.gd")
const FIRE := preload("res://scripts/scenery_fire_lighting.gd")
const ITEM_LIGHT_LIMIT := 16 # Measured in Compatibility and Forward Mobile.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("WORLD LIGHTING FAIL: ", label)
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var ambients := {}
	var darkest := 1.0
	var brightest := 0.0
	var surfaces := {}
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var id := str(entry.id)
		var data: Dictionary = ScenarioCatalog.environment(id)
		var ambient: Color = LIGHTING.ambient_for(data)
		var light: float = LIGHTING.luminance(ambient)
		ambients[ambient.to_html(false)] = true
		darkest = minf(darkest, light)
		brightest = maxf(brightest, light)
		check(light >= LIGHTING.FLOOR_LUMINANCE - .001 and minf(ambient.r, minf(ambient.g, ambient.b)) >= LIGHTING.FLOOR_CHANNEL - .001, id + " ambient respects the readability floor")
		check(maxf(ambient.r, maxf(ambient.g, ambient.b)) <= 1.0 and is_equal_approx(ambient.a, 1.0), id + " ambient never brightens the authored art")
		surfaces[STRATA.surface_for(data)] = true
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2, {"environment":id, "build_type":"bastion", "position":"center"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.weather.set_reduced_effects(false)
		for frame in 24: await process_frame
		var bunker: ScenarioBunker = game.scenario_bunker
		var lighting: Node2D = bunker.lighting
		check(is_instance_valid(lighting) and lighting.get_parent() == bunker and lighting.environment_id == id, id + " world lighting belongs to the selected bunker")
		if not is_instance_valid(lighting):
			await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
			continue
		var report: Dictionary = lighting.diagnostics()
		check(lighting.ambient.is_equal_approx(ambient), id + " world ambient is the catalog-derived colour")
		# The canvas carries that ambient, darkened only by the storm grade of a rainy world.
		var graded: Color = lighting.graded_ambient()
		var stormy := str(data.get("weather", "storm")) in ["rain", "storm"]
		check(graded.r <= ambient.r + .001 and graded.g <= ambient.g + .001 and graded.b <= ambient.b + .001 and LIGHTING.luminance(graded) >= LIGHTING.luminance(ambient) * .84 - .001 and (stormy or graded.is_equal_approx(ambient)), id + " canvas ambient is the catalog colour with at most the storm grade")
		check(int(report.pool) == LIGHTING.MAX_LIGHTS and int(report.enabled) <= LIGHTING.MAX_LIGHTS and int(report.enabled) >= 3, id + " fixture lights stay inside their pool and light the room")
		check(LIGHTING.MAX_LIGHTS + FIRE.MAX_LIGHTS + 5 <= ITEM_LIGHT_LIMIT, id + " all light pools together fit the per-item limit")
		var ceiling := 0
		var doors := 0
		for fixture: Dictionary in lighting.fixtures:
			if str(fixture.kind) == "ceiling": ceiling += 1
			if str(fixture.kind) in ["door", "alarm"]: doors += 1
		check(ceiling == ScenarioBunkerArt.LAMP_FRACTIONS.size() and doors == 2, id + " every drawn ceiling lamp and both gates carry a fixture")
		for lamp: PointLight2D in lighting.lights:
			check(not lamp.shadow_enabled and lamp.range_z_min == LIGHTING.LIGHT_Z_MIN and lamp.range_layer_max == 0, id + " fixture light is shadowless and excludes the backdrop depth")
		var panorama: Sprite2D = game.scenery.panorama
		check(panorama.material is ShaderMaterial and "render_mode unshaded" in panorama.material.shader.code, id + " panorama ignores ambient and lamps")
		var mist: CanvasItem = game.scenery.particle_layer
		check(mist.material is CanvasItemMaterial and mist.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, id + " plain backdrop layers are excluded")
		check(game.scenery.props_layer.material == null or not game.scenery.props_layer.material is CanvasItemMaterial, id + " foreground props stay shaded with the crew")
		var tag := game.players[0].find_child("WorkerIdentity", true, false) as CanvasItem
		check(tag != null and tag.material is CanvasItemMaterial and tag.material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, id + " player tags stay at interface brightness")
		check(game.hud is CanvasLayer, id + " HUD lives on its own canvas")
		var shadow_report: Dictionary = report.shadows
		check(int(shadow_report["static"]) >= 8 and int(shadow_report.physics_queries) == 0, id + " props, machines and wall feet have contact shadows without physics queries")
		var strata := bunker.get_node("TerrainStrata") as Node2D
		check(strata.surface_kind == STRATA.surface_for(data) and (strata.material.get_shader_parameter("ambient") as Color).is_equal_approx(lighting.graded_ambient()), id + " ground cover and rock follow catalog weather and ambient")
		# Rooms: one shaped light voice per lit room, one multiplied grade per room.
		var rooms := bunker.lit_room_rects().size()
		var room_lights := 0
		for lamp: PointLight2D in lighting.lights:
			if lamp.enabled and str((lamp.get_meta("fixture", {}) as Dictionary).get("kind", "")) == "room": room_lights += 1
		check(room_lights >= 1 and room_lights <= rooms and int(report.room_grades) == rooms, id + " each lit room has one shaped light and one light grade")
		for grade: Node2D in lighting.room_grades:
			if grade.visible: check(grade.z_index == LIGHTING.ROOM_GRADE_Z and not grade.z_as_relative and grade.material is ShaderMaterial, id + " room grade sits between machines and crew")
		# Actors: off the fixture mask, on the actor key, and lifted to the target value.
		lighting.mark_actors()
		var visual := game.players[0].get_node("PixelVisual") as CanvasItem
		check(visual.light_mask == LIGHTING.ACTOR_MASK, id + " worker art is on the actor light mask")
		for lamp: PointLight2D in lighting.lights:
			check(lamp.range_item_cull_mask & LIGHTING.ACTOR_MASK == 0, id + " fixture lights never add to the actor key")
		check(lighting.actor_key.range_item_cull_mask == LIGHTING.ACTOR_MASK and not lighting.actor_key.shadow_enabled, id + " actor key lights actor art only")
		var lifted: Color = lighting.graded_ambient() + LIGHTING.actor_lift(lighting.graded_ambient())
		check(LIGHTING.luminance(lifted) >= LIGHTING.ACTOR_TARGET * .9, id + " actors keep their authored value at night (%.2f)" % LIGHTING.luminance(lifted))
		var fire_lamp: PointLight2D = FIRE.make_lamp("ProbeLamp")
		check(fire_lamp.range_item_cull_mask & LIGHTING.ACTOR_MASK != 0 and fire_lamp.range_item_cull_mask & 1 != 0, id + " fire, gunfire and blast voices light actors and the world")
		fire_lamp.free()
		check(bunker.fields.size() == 1 and bunker.fields[0].remaining_count() == 30 and get_nodes_in_group("mine_blocks").size() == 30, id + " mining cells are untouched")
		# Reduced effects: no fixture lights, steadier and brighter ambient.
		game.weather.set_reduced_effects(true)
		for frame in 3: await process_frame
		lighting.select_lights()
		report = lighting.diagnostics()
		check(int(report.enabled) == 0 and bool(report.reduced), id + " reduced effects switch every fixture light off")
		check(LIGHTING.luminance(lighting.ambient) >= light - .001, id + " reduced effects never darken the world")
		var updates := int(report.updates)
		for frame in 30: await process_frame
		check(int(lighting.diagnostics().updates) == updates, id + " reduced effects stop all flicker updates")
		# Reduced effects: no lightning flash even when the sky would strike.
		game.weather.lightning_age = 0.0
		for frame in 2: await process_frame
		check(float(lighting.flash) == 0.0, id + " reduced effects never flash the scene")
		game.weather.set_reduced_effects(false)
		# Lightning: one short flash per strike, never two within half a second.
		var flashes := int(lighting.flashes)
		var peak := 0.0
		for strike in 3:
			game.weather.lightning_age = 0.0
			for frame in 6:
				await process_frame
				peak = maxf(peak, float(lighting.flash))
		check(int(lighting.flashes) - flashes == 1 and peak > .8, id + " three strikes within 0.3 s give one flash (%d)" % (int(lighting.flashes) - flashes))
		for frame in 50: await process_frame
		check(float(lighting.flash) < .01, id + " the flash is over within a second")
		# Alarm: the gate fixtures change with the replicated round phase.
		game.rounds.phase = "attack"
		lighting.collect_fixtures()
		var alarms := 0
		for fixture: Dictionary in lighting.fixtures:
			if str(fixture.kind) == "alarm": alarms += 1
		check(alarms == 2, id + " gate lights follow the wave phase")
		# The hidden bunker of the road view takes its ambient with it.
		bunker.hide()
		check(not lighting.canvas_modulate.is_visible_in_tree(), id + " ambient leaves with the hidden bunker")
		bunker.show()
		check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), id + " cleans up")
	check(ambients.size() >= 12, "Worlds get individual ambient colours from catalog data (%d)" % ambients.size())
	check(darkest < .75 and brightest > .9, "Night and day worlds differ in level (%.2f / %.2f)" % [darkest, brightest])
	check(surfaces.size() >= 5, "Catalog weather yields at least five ground covers")
	check(LIGHTING.luminance(LIGHTING.ambient_for({"sky_color":"#000000"})) >= LIGHTING.FLOOR_CHANNEL and LIGHTING.luminance(LIGHTING.readable(Color.BLACK)) >= LIGHTING.FLOOR_CHANNEL, "A black sky still yields readable ambient")
	check(LIGHTING.ambient_for({}).a == 1.0, "A world without lighting data gets a neutral derived ambient")
	# Outdoor night grade of the crew and enemies: none by day, a clear step
	# down at night that never darkens them below half their value.
	var day_grade := LIGHTING.exterior_grade_for(0.0, 0.0, Color.WHITE)
	var night_grade := LIGHTING.exterior_grade_for(1.0, 0.0, Color(.6, .7, 1.0))
	check(day_grade.a == 0.0 and night_grade.a > .9, "Actors under a night sky are graded, by day they are not")
	check(LIGHTING.luminance(Color.WHITE.lerp(Color(night_grade.r, night_grade.g, night_grade.b), night_grade.a)) > .5, "The night grade keeps actors above half their authored value")
	print("WORLD LIGHTING RESULT: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
