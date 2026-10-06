extends SceneTree
## Real scenario integration, deterministic cosmetic placement, pause/F3 and
## rendered fixed roots/moving crowns. Uses prepared scenes with waves stopped.
const OUTPUT := "res://artifacts/scenery-props/"
const TREE_WORLDS := ["ash_foundry", "overgrown_steelworks", "frozen_rail_yard", "mountain_pass"]
var checks := 0
var failures := 0
var layouts: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SCENERY PROPS %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count := 3) -> void:
	for index in count:
		await process_frame
		await physics_frame

func start_scene(id: String, bunker_position: String):
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1, {"environment": id, "build_type": "bastion", "position": bunker_position})
	game.rounds.set_process(false)
	game.rounds.running = false
	game.notice = ""
	game.notice_time = 0
	# Visibility/F3 comparisons require the same frame, independent of live
	# follow-camera interpolation while newly relocated props approach its edge.
	game.set_process(false)
	game.camera.position = Vector2(720, 450)
	game.camera.zoom = Vector2.ONE
	return game

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(descendants(child))
	return result

func layout_signature(props) -> String:
	var result: Array = []
	for entry: Dictionary in props.entries:
		result.append([entry.kind, entry.position, entry.size, entry.tree, entry.tint, entry.phase])
	return var_to_str(result)

func image_difference(first: Image, second: Image, area: Rect2i) -> int:
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, first.get_size()))
	var a := first.get_data()
	var b := second.get_data()
	var result := 0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var at := (y * first.get_width() + x) * 4
			var difference := 0
			for channel in 4:
				difference = maxi(difference, absi(int(a[at + channel]) - int(b[at + channel])))
			if difference >= 8:
				result += 1
	return result

func alpha_pixels(image: Image, area: Rect2i) -> int:
	var clipped := area.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var count := 0
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			if image.get_pixel(x, y).a > .25:
				count += 1
	return count

func alpha_center(image: Image, area: Rect2i) -> Vector2:
	var weighted := Vector2.ZERO
	var weight := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var alpha := image.get_pixel(x, y).a
			weighted += Vector2(x, y) * alpha
			weight += alpha
	return weighted / maxf(weight, .001)

func image_from(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func rendered_tree(props, id: String) -> void:
	# Reuse the actual imported texture, banded mesh and shader. This viewport
	# excludes cloud/rain motion, so an unchanged base cannot hide drifting roots.
	var source: MeshInstance2D = props.tree_nodes[0]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 320)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var tree := MeshInstance2D.new()
	tree.mesh = source.mesh
	tree.texture = source.texture
	tree.material = source.material.duplicate()
	tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tree.position = Vector2(192, 260)
	viewport.add_child(tree)
	var material := tree.material as ShaderMaterial
	material.set_shader_parameter("wind_clock", 0.0)
	# Reconstruct the former image-bottom anchor with original alpha. The PNG
	# files remain untouched; before/after come from real Godot render meshes.
	var entry: Dictionary = props.entries[int(source.get_meta("prop_index"))]
	var region: Rect2i = props.Catalog.TREE_REGIONS[entry.tree]
	var size: Vector2 = source.texture.get_size()
	var width := 192.0*float(region.size.x)/float(region.size.y)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-width*.5,-192,0),Vector3(width*.5,-192,0),Vector3(-width*.5,0,0),Vector3(width*.5,0,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(region.position)/size,Vector2(region.end.x,region.position.y)/size,Vector2(region.position.x,region.end.y)/size,Vector2(region.end)/size])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,1,3,2])
	var legacy_mesh := ArrayMesh.new()
	legacy_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	tree.mesh = legacy_mesh
	(await image_from(viewport)).save_png(OUTPUT+id+"-roots-before.png")
	tree.mesh = source.mesh
	var first := await image_from(viewport)
	first.save_png(OUTPUT+id+"-roots-after.png")
	material.set_shader_parameter("wind_clock", 2.7)
	var second := await image_from(viewport)
	var anchor := Rect2i(170, 250, 44, 10)
	var crown := Rect2i(12, 50, 360, 154)
	var root_pixels := alpha_pixels(first, anchor)
	var root_changes := image_difference(first, second, anchor)
	var root_shift := alpha_center(first, anchor).distance_to(alpha_center(second, anchor))
	var crown_changes := image_difference(first, second, crown)
	# Very thin exposed roots cover only one pixel in the last image row. Check
	# the entire planted base inside the shader's rigid lower trunk section.
	check(root_pixels >= 15 and root_changes == 0 and root_shift < .01 and crown_changes > 120,
		"%s rendered tree: %d solid base pixels, %d root changes, %.3fpx base shift, %d crown changes after 2.7s" % [id, root_pixels, root_changes, root_shift, crown_changes])
	first.save_png(OUTPUT + id + "-isolated-tree-0s.png")
	second.save_png(OUTPUT + id + "-isolated-tree-2.7s.png")
	viewport.queue_free()
	await process_frame

func rendered_industrial(props, id: String) -> void:
	# Temporarily render only the real props layer at its normal world positions.
	# Compare a native industrial prop, excluding every tree and weather layer.
	var parent: Node = props.get_parent()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	props.reparent(viewport)
	props.set_process(false)
	props.elapsed = 0.0
	props._process(.05)
	var first := await image_from(viewport)
	var changed := 0
	for time: float in [.75, 1.85, 3.0]:
		props.elapsed = time
		props._process(.05)
		var later := await image_from(viewport)
		for entry: Dictionary in props.entries:
			if entry.kind == "tree" or not entry.animated or entry.optional or not entry.displayed:
				continue
			changed = maxi(changed, image_difference(first, later, Rect2i(entry.bounds)))
	check(changed > 12, "%s native machinery/fixtures visibly animate: %d changed pixels" % [id, changed])
	props.reparent(parent)
	props.set_process(true)
	viewport.queue_free()
	await process_frame

func run() -> void:
	root.size = Vector2i(1440, 900)
	AudioServer.set_bus_mute(0, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rendered := DisplayServer.get_name() != "headless"
	for environment: Dictionary in ScenarioCatalog.environments():
		var id: String = environment.id
		for position: String in ["left", "center", "right"]:
			var game = start_scene(id, position)
			await frames(3)
			var props = game.scenery.get("props_layer")
			check(is_instance_valid(props), "%s/%s actual scene includes the prop layer" % [id, position])
			if not is_instance_valid(props):
				await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
				continue
			var diagnostic: Dictionary = props.diagnostics()
			var clear := true
			var footprint := Rect2(game.scenario_bunker.room_left - 18, 245, 676, 185)
			for entry: Dictionary in props.entries:
				clear = clear and not footprint.intersects(entry.bounds)
				if footprint.intersects(entry.bounds): print("OVERLAPPING PROP: ",entry.kind," ",entry.position," ",entry.bounds)
			check(clear and diagnostic.visible >= 6 and diagnostic.trees >= 2,
				"%s/%s visible trees and objects leave the bunker and doorways clear" % [id, position])
			var cosmetic := true
			for node in descendants(props):
				var groups: Array[StringName] = node.get_groups()
				var registered_reactions: bool = node==props.reactions and groups==[&"scenery_damage"]
				cosmetic = cosmetic and not node is CollisionObject2D and (groups.is_empty() or registered_reactions)
				cosmetic = cosmetic and not node.is_processing_input() and not node.is_processing_unhandled_input()
			check(cosmetic and get_nodes_in_group("players").size() == 1 and get_nodes_in_group("stations").size() == 2,
				"%s/%s decoration adds no physics, interactables or input handlers" % [id, position])
			var grounded := true
			var rates: Dictionary = {}
			var phases: Dictionary = {}
			for entry: Dictionary in props.entries:
				if entry.kind not in ["tree","brush","grass","frost_grass","reeds"]: continue
				var point: Vector2 = props.to_global(entry.position)
				var ray := PhysicsRayQueryParameters2D.create(point+Vector2(0,-2),point+Vector2(0,3),1)
				var hit: Dictionary = props.get_world_2d().direct_space_state.intersect_ray(ray)
				grounded = grounded and is_equal_approx(point.y,430.0) and not hit.is_empty() and absf(float(hit.get("position",Vector2.ZERO).y)-430.0)<.1
				if entry.kind=="tree":
					rates[entry.wind_rate] = true
					phases[entry.phase] = true
					grounded = grounded and Vector2(entry.trunk_points[0]).distance_to(entry.position)<.01
			check(grounded,"%s/%s every near/distant tree and plant root touches actual physical ground at y430" % [id,position])
			check(rates.size()==props.tree_nodes.size() and phases.size()==props.tree_nodes.size(),"%s/%s every tree has its own deterministic phase and rate" % [id,position])
			if position == "left":
				props._update_materials()
				var initial_uploads: int = props.uniform_updates
				for update in 20: props._update_materials()
				check(props.uniform_updates==initial_uploads,"%s repeated render ticks skip all tree uniform uploads" % id)
				layouts[id] = layout_signature(props)
				var roots: Array = props.tree_nodes.map(func(tree): return tree.transform)
				var before: float = props.elapsed
				await frames(5)
				check(props.elapsed > before and props.tree_nodes.map(func(tree): return tree.transform) == roots,
					"%s actual processing advances wind while tree roots stay fixed" % id)
				paused = true
				var paused_time: float = props.elapsed
				await create_timer(.06, true, false, true).timeout
				check(is_equal_approx(props.elapsed, paused_time), "%s pause freezes prop animation" % id)
				paused = false
				await frames(2)
				check(props.elapsed > paused_time, "%s props resume with the game" % id)
				var normal_visible := int(props.diagnostics().visible)
				var reduced_key := InputEventKey.new()
				reduced_key.keycode = KEY_F3
				reduced_key.physical_keycode = KEY_F3
				reduced_key.pressed = true
				game.weather._unhandled_input(reduced_key)
				await frames(8)
				var reduced: Dictionary = props.diagnostics()
				check(reduced.reduced and int(reduced.visible) < normal_visible,
					"%s F3 reduces visible decoration work (%d to %d)" % [id, normal_visible, reduced.visible])
				game.weather._unhandled_input(reduced_key)
				await frames(4)
				check(not props.diagnostics().reduced and int(props.diagnostics().visible) == normal_visible,
					"%s F3 restores the full scene" % id)
				if rendered:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT+id+"-rooted-scene.png")
					if id in TREE_WORLDS and not props.tree_nodes.is_empty():
						await rendered_tree(props, id)
					await rendered_industrial(props, id)
			if not await preload("res://tests/scene_cleanup.gd").free_scene(game, self):
				failures += 1
	var distinct: Dictionary = {}
	for id: String in layouts:
		var game = start_scene(id, "left")
		await frames(2)
		var repeated := layout_signature(game.scenery.props_layer)
		check(repeated == layouts[id], "%s a new scene reproduces the same placement for both peers" % id)
		distinct[repeated] = true
		await preload("res://tests/scene_cleanup.gd").free_scene(game, self)
	check(distinct.size() == 9, "All nine biome prop layouts have distinct object and palette choices")
	print("SCENERY PROPS: %d/%d checks passed%s" % [checks - failures, checks, " (GPU pixel checks included)" if rendered else " (headless: GPU checks skipped)"])
	quit(1 if failures else 0)
