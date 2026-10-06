extends SceneTree
## Actual scene and collision receivers, with optional fixed-clock GPU A/B.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/scenery-fire-lighting"
var checks := 0
var failures := 0
var game: Node2D
var props: Node2D
var effects: Node2D
var lights: Node2D

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("FIRE LIGHT %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func clear_states() -> void:
	for entry: Dictionary in props.entries:
		var state: Dictionary = props.reactions.state_for(int(entry.index))
		if state.is_empty(): continue
		state.burning = false
		state.burn_left = 0.0
		state.broken = false
		state.charred = false
		state.hp = 70.0
	effects.reset()
	props._update_states()
	effects._process(.05)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1, {"environment":"overgrown_steelworks", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(0)
	game.weather.lightning_enabled = false
	for frame in 3: await physics_frame
	freeze(game)
	props = game.scenery.props_layer
	effects = props.debris
	lights = effects.fire_lighting
	props.visible_bounds = Rect2(-500, -200, 2500, 1000)
	for entry: Dictionary in props.entries: entry.displayed = true
	clear_states()
	check(lights.lights.size() == lights.MAX_LIGHTS and lights.MAX_LIGHTS == 4, "Exactly four reusable real PointLight2D voices")
	check(lights.active_entries.is_empty(), "Healthy scenery consumes no enabled lights")
	for lamp: PointLight2D in lights.lights:
		check(lamp.texture == lights.lights[0].texture and lamp.texture.get_size() == Vector2(128, 128), "Lights share one native 128px radial falloff")
		check(lamp.range_z_min == -8 and lamp.range_z_max == 20 and lamp.range_layer_min == 0 and lamp.range_layer_max == 0, "Only foreground world items receive fire, excluding panorama and HUD")
		check(lamp.shadow_enabled and lamp.shadow_item_cull_mask == (lights.OCCLUDER_MASK | 1), "Local fire respects physical blockers on default foreground receivers")
	var trees: Array[int] = []
	for entry: Dictionary in props.entries:
		if entry.kind != "tree": continue
		trees.append(int(entry.index))
		props.reactions.states[int(entry.index)].burning = true
		props.reactions.states[int(entry.index)].burn_left = 8.0
	effects._process(.1)
	check(lights.active_entries.size() == mini(trees.size(), 4), "Simultaneous burning scenery stays within the four-light budget")
	check(lights.occluders.size() >= 5 and lights.occluders.size() <= lights.MAX_OCCLUDERS, "Actual roof, solid headers and defensive walls provide bounded shadows")
	check(lights.occluders[0].occluder.closed and lights.occluders[0].occluder.polygon.size() == 4, "A solid soil shadow volume blocks deep ground without drawing an overlay")
	check(is_equal_approx(lights.occluders[0].to_global(lights.occluders[0].occluder.polygon[0]).y, 433.0), "A three-pixel soil edge can receive the fire")
	var original_energy: float = lights.lights[0].energy
	effects._process(.29)
	check(not is_equal_approx(original_energy, lights.lights[0].energy), "Explicit effect time gently changes light energy")
	var paused_clock: float = lights.clock
	var paused_energy: float = lights.lights[0].energy
	var paused_position: Vector2 = lights.lights[0].position
	paused = true
	effects._process(1)
	lights.update_lighting(1)
	check(lights.clock == paused_clock and lights.lights[0].energy == paused_energy and lights.lights[0].position == paused_position, "Pause holds both fire-light position and flicker")
	paused = false
	game.weather.reduced_effects = true
	effects._process(.001)
	check(lights.active_entries.is_empty() and enabled_count() == 0, "F3 immediately turns off all real fire lights")
	var altered_wall: Node = get_nodes_in_group("walls")[0]
	var before_f3_geometry: int = lights.occluders.size()
	altered_wall.collider.disabled = true
	game.weather.reduced_effects = false
	effects._process(.001)
	check(enabled_count() > 0, "Leaving F3 restores visible fire lighting")
	check(lights.occluders.size() == before_f3_geometry - 1, "Reactivation refreshes changed solid geometry before enabling even its first light frame")
	altered_wall.collider.disabled = false
	lights._sync_occluders()
	props.visible_bounds = Rect2(6000, 6000, 200, 200)
	effects._process(.001)
	check(enabled_count() == 0, "Offscreen sources are disabled before the throttled light update")
	props.visible_bounds = Rect2(-500, -200, 2500, 1000)
	clear_states()
	var selected := -1
	for index in trees:
		if props.entries[index].position.x > 800 and props.entries[index].position.x < 1000: selected = index
	check(selected >= 0, "A real visible tree supplies the measured fire")
	if selected < 0:
		await CLEANUP.free_scene(game, self)
		quit(1)
		return
	var entry: Dictionary = props.entries[selected]
	check(props.reactions.damage_entry(selected, 1, "arcgun", props.reactions.target_point(selected), Vector2.RIGHT), "The real hot-impact path ignites the measured tree")
	effects._process(.05)
	var standing: Vector2 = lights.lights[0].position
	props.reactions.damage_entry(selected, 200, "rifle", props.reactions.target_point(selected), Vector2.RIGHT)
	effects._process(.7)
	check(lights.lights[0].position.distance_to(standing) > 10 and enabled_count() == 1, "Residual light follows the actual falling branch instead of the vanished upright trunk")
	var strong_energy: float = lights.lights[0].energy
	var strong_radius: float = lights.lights[0].texture_scale
	props.reactions.states[selected].burn_left = .3
	effects._process(.05)
	check(lights.lights[0].energy < strong_energy * .3 and lights.lights[0].texture_scale < strong_radius, "Final embers smoothly lose energy and reach before extinction")
	props.reactions.states[selected].burning = false
	effects._process(.001)
	check(enabled_count() == 0, "Extinction disables the light immediately")
	var blockers_before: int = lights.occluders.size()
	var wall: Node = get_nodes_in_group("walls")[0]
	wall.collider.disabled = true
	lights._sync_occluders()
	check(lights.occluders.size() == blockers_before - 1, "A physically removed defensive wall no longer casts an invented solid shadow")
	wall.collider.disabled = false
	lights._sync_occluders()
	effects.sync_replica(true)
	check(enabled_count() == 0 and lights.active_entries.is_empty(), "Replica baseline clears old lights before adopting the present fire state")
	if "--capture" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name() != "headless", "GPU proof uses the real Compatibility renderer")
		if DisplayServer.get_name() != "headless": await capture_pair(selected, entry)
	effects.reset()
	check(enabled_count() == 0 and lights.occluders.is_empty(), "Reset immediately releases all active light and blocker state")
	await CLEANUP.free_scene(game, self)
	print("SCENERY FIRE LIGHTING: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func enabled_count() -> int:
	var count := 0
	for lamp: PointLight2D in lights.lights:
		if lamp.enabled: count += 1
	return count

func frame_image() -> Image:
	for frame in 2: await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func sample(first: Image, second: Image, area: Rect2i) -> Dictionary:
	var box := area.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	var changed := 0
	var maximum := 0.0
	var total := Vector3.ZERO
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var delta := Vector3(b.r-a.r, b.g-a.g, b.b-a.b)
			var extent := maxf(absf(delta.x), maxf(absf(delta.y), absf(delta.z)))
			maximum = maxf(maximum, extent)
			total += delta
			if extent > .005: changed += 1
	return {"changed":changed, "max_rgb_difference":maximum, "rgb_sum":[total.x,total.y,total.z], "pixels":box.get_area()}

func world_box(at: Rect2) -> Rect2i:
	return Rect2i(game.get_global_transform_with_canvas() * at)

func capture_pair(selected: int, entry: Dictionary) -> void:
	clear_states()
	props.reactions.damage_entry(selected, 1, "arcgun", props.reactions.target_point(selected), Vector2.RIGHT)
	effects._process(.4)
	props._update_states()
	game.camera.position = Vector2(entry.position.x - 95, 330)
	game.camera.zoom = Vector2.ONE * 1.7
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.players[0].position = entry.position + Vector2(38, 0)
	game.players[0].get_node("PixelVisual").queue_redraw()
	# Move one real metal fan beside the tree in this prepared fixture.
	var metal_position: Vector2 = entry.position + Vector2(77, 0)
	for prop: Dictionary in props.entries:
		if prop.kind == "fan":
			prop.position = metal_position
			break
	props._draw_layer.queue_redraw()
	effects.elapsed = 2.25
	effects.queue_redraw()
	lights.effects_enabled = false
	lights.update_lighting(.1)
	var before := await frame_image()
	lights.effects_enabled = true
	lights.update_lighting(.1)
	var after := await frame_image()
	before.save_png(OUTPUT + "/fire-unlit.png")
	after.save_png(OUTPUT + "/fire-lit.png")
	var measures := {
		"ground_edge":sample(before, after, world_box(Rect2(entry.position.x-35, 430, 120, 2))),
		"tree_trunk":sample(before, after, world_box(Rect2(entry.position.x-10, 355, 23, 65))),
		"player":sample(before, after, world_box(Rect2(entry.position.x+23, 375, 34, 52))),
		"metal_prop":sample(before, after, world_box(Rect2(metal_position.x-25, 378, 50, 48))),
		"deep_soil":sample(before, after, world_box(Rect2(entry.position.x-90, 445, 210, 65))),
		"bunker_interior":sample(before, after, world_box(Rect2(625, 350, 70, 65))),
		"far_sky":sample(before, after, world_box(Rect2(entry.position.x-150, 180, 280, 70))),
		"hud":sample(before, after, Rect2i(0, 0, 1440, 70)),
	}
	for receiver in ["ground_edge", "tree_trunk", "player", "metal_prop"]:
		check(int(measures[receiver].changed) > 10 and float(measures[receiver].rgb_sum[0]) > 1, receiver + ": actual RGB pixels gain warm fire illumination")
	for excluded in ["deep_soil", "bunker_interior", "far_sky", "hud"]:
		check(int(measures[excluded].changed) == 0, excluded + ": unchanged pixels under identical scene/flame time")
	var repeat := await frame_image()
	check(repeat.get_data() == after.get_data(), "Held effect time produces an identical rendered frame")
	var report := {"renderer":RenderingServer.get_video_adapter_name(), "fixture":"Actual main scene, overgrown steelworks, one hot-hit tree; player and one original metal fan positioned beside it; all simulation held at fixed explicit times", "flame_clock":effects.elapsed, "active_lights":lights.active_entries.size(), "measurements":measures}
	report.wall_control = await capture_wall_control(selected, entry)
	FileAccess.open(OUTPUT + "/pixel-differences.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func capture_wall_control(selected: int, entry: Dictionary) -> Dictionary:
	# A second prepared placement deliberately brings the intact wall inside
	# the real tree light radius; a no-shadow control proves this is not merely
	# a dark sample outside the circle.
	var translation := Vector2(game.scenario_bunker.room_right + 37.0 - entry.position.x, 0)
	entry.position += translation
	entry.bounds.position += translation
	for key in ["emit_points", "trunk_points"]:
		var shifted: PackedVector2Array = entry[key]
		for index in shifted.size(): shifted[index] += translation
		entry[key] = shifted
	props._tree_by_index[selected].position += translation
	effects.queue_redraw()
	lights.update_lighting(.1)
	lights.effects_enabled = false
	lights.update_lighting(.1)
	var unlit := await frame_image()
	lights.effects_enabled = true
	lights.update_lighting(.1)
	var blocked := await frame_image()
	for lamp: PointLight2D in lights.lights: lamp.shadow_enabled = false
	var unblocked := await frame_image()
	for lamp: PointLight2D in lights.lights: lamp.shadow_enabled = true
	var inside := world_box(Rect2(685, 362, 18, 52))
	var shielded := sample(unlit, blocked, inside)
	var control := sample(unlit, unblocked, inside)
	check(int(control.changed) > 100 and float(control.rgb_sum[0]) > 5, "Wall control: without shadows the same fire demonstrably illuminates the near interior")
	check(int(shielded.changed) == 0, "Wall control: the actual intact collision wall removes all interior light leakage")
	unlit.save_png(OUTPUT + "/wall-unlit.png")
	blocked.save_png(OUTPUT + "/wall-shadowed.png")
	unblocked.save_png(OUTPUT + "/wall-unshielded-control.png")
	return {"fixture":"Same scene; the original burning tree and all fire anchors translated beside the intact wall to test a receiver inside its radius", "shielded":shielded, "unshielded_control":control}
