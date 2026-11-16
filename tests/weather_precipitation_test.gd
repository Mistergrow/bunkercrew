extends SceneTree
## Falling weather layers (rain, snow, ash, dust, mist): derived from catalog
## weather, bounded fixed meshes, clipped to the open sky, gated by reduced
## effects and absent outside a match. Presentation only.

const PRECIPITATION := preload("res://scripts/weather_precipitation.gd")
const MAX_INSTANCES := 1600
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("PRECIPITATION FAIL: ", label)
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	# Catalog mapping: every non-clear weather gets a visible kind.
	var kinds := {}
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var data: Dictionary = ScenarioCatalog.environment(str(entry.id))
		var weather_kind := str(data.get("weather", "storm"))
		var rain := clampf(float(data.get("rain_strength", 1.0 if weather_kind in ["rain", "storm"] else 0.0)), 0.0, 1.0)
		var kind := PRECIPITATION.kind_for(data, rain)
		kinds[kind] = true
		check(kind != "" or weather_kind == "clear", str(entry.id) + " weather '" + weather_kind + "' falls visibly")
	check(kinds.has("rain") and kinds.has("snow") and kinds.has("ash"), "Rain, snow and ash worlds exist in the catalog")
	for kind: String in PRECIPITATION.KINDS:
		var total := 0
		for spec: Dictionary in PRECIPITATION.KINDS[kind]: total += int(spec.count)
		check(total <= MAX_INSTANCES, "%s stays within a fixed pool (%d)" % [kind, total])
	# The menu world: nothing falls before a match starts.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 4: await process_frame
	var menu_layer: Node = game.weather.get("precipitation") if is_instance_valid(game.weather) else null
	if is_instance_valid(menu_layer):
		check(not bool(menu_layer.diagnostics().visible), "No falling weather behind the menu")
	await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	for id: String in ["storm_dam", "frozen_rail_yard", "ash_foundry", "overgrown_steelworks"]:
		var data: Dictionary = ScenarioCatalog.environment(id)
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(2, {"environment":id, "build_type":"bastion", "position":"left"})
		game.rounds.running = false
		game.weather.set_reduced_effects(false)
		for frame in 30: await process_frame
		var layer: Node2D = game.weather.precipitation
		var report: Dictionary = layer.diagnostics()
		var expected := PRECIPITATION.kind_for(data, float(game.weather.rain_base_strength))
		check(str(report.kind) == expected, id + " falls as " + expected)
		if expected.is_empty():
			check(int(report.layers) == 0, id + " clear sky has no falling layer")
			await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
			continue
		check(bool(report.visible) and int(report.layers) == (PRECIPITATION.KINDS[expected] as Array).size(), id + " layers are visible in a match")
		check(int(report.instances) <= MAX_INSTANCES and int(report.shelter_updates) >= 1, id + " bounded pool with a live shelter line")
		var bunker: ScenarioBunker = game.scenario_bunker
		for child: Node in layer.layers:
			var mesh_layer := child as MeshInstance2D
			check(mesh_layer.material is ShaderMaterial and "render_mode unshaded" in (mesh_layer.material as ShaderMaterial).shader.code, id + " " + str(child.name) + " is unlit and readable at night")
			check(mesh_layer.mesh is ArrayMesh and mesh_layer.mesh.get_surface_count() == 1, id + " " + str(child.name) + " is one static mesh")
			var near := bool((mesh_layer.material as ShaderMaterial).get_shader_parameter("use_shelter"))
			if near: check(mesh_layer.z_index > 15 and not mesh_layer.z_as_relative, id + " near layer falls in front of the crew")
			else: check(mesh_layer.z_index < bunker.z_index and not mesh_layer.z_as_relative, id + " far layers sit behind the bunker and the rock")
		if expected == "ash":
			# Ash is not snow: several flake tones (pale, grey, charcoal), rising
			# embers flagged for the shader, and a haze behind the bunker.
			var tones := {}
			var embers := 0
			for child: Node in layer.layers:
				var arrays: Array = (child as MeshInstance2D).mesh.surface_get_arrays(0)
				var tints: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				for index in range(0, tints.size(), 6):
					if uvs[index].x > PRECIPITATION.EMBER_FLAG - 1.0: embers += 1
					else: tones[snappedf(tints[index].v, .05)] = true
			check(tones.size() >= 3 and embers > 0, id + " ash falls in several grey tones with rising embers (%d tones, %d embers)" % [tones.size(), embers])
			check(is_instance_valid(layer.haze) and layer.haze.z_index < bunker.z_index and not layer.haze.z_as_relative, id + " ash haze lies behind the bunker and the rock")
		# Shelter: never inside the rooms, never below the ground.
		var inside: float = layer._shelter_at(floori((float(bunker.room_left) + 300.0) / PRECIPITATION.SHELTER_STEP))
		var outside: float = layer._shelter_at(floori((float(bunker.room_right) + 400.0) / PRECIPITATION.SHELTER_STEP))
		check(inside <= ScenarioBunker.ROOF_Y + .01, id + " the roof shelters the rooms (%.0f)" % inside)
		check(outside <= float(bunker.ground_y) + .01 and outside > ScenarioBunker.ROOF_Y, id + " open ground ends the fall at the surface (%.0f)" % outside)
		# Reduced effects hide every layer; switching back restores them.
		game.weather.set_reduced_effects(true)
		await process_frame
		check(not bool(layer.diagnostics().visible), id + " reduced effects remove falling weather")
		game.weather.set_reduced_effects(false)
		await process_frame
		await process_frame
		check(bool(layer.diagnostics().visible), id + " falling weather returns after reduced effects")
		await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	print("PRECIPITATION RESULT: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
