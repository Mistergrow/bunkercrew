extends SceneTree
## The scenario warm-up (scripts/render_warmup.gd) covers the materials combat
## events draw first, is wired into the scenario start, and leaves nothing
## behind where nothing is rendered.
const Warmup := preload("res://scripts/render_warmup.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var materials := Warmup.event_materials()
	check(materials.size() >= 10, "Every event material is warmed (%d)" % materials.size())
	var shaders := {}
	for material in materials:
		if material is ShaderMaterial:
			var shader: Shader = material.shader
			check(shader != null and shader.get_mode() == Shader.MODE_CANVAS_ITEM, "Warm-up shaders are canvas shaders")
			if shader != null: shaders[shader.resource_path.get_file()] = true
		else:
			check(material is CanvasItemMaterial, "Warm-up materials are canvas materials")
	for name in ["actor_wreck.gdshader", "pickup_cutout.gdshader", "ground_infantry_remains.gdshader", "pixel_effect_grid.gdshader", "pixel_effect_grid_add.gdshader", "pixel_effect_grid_unlit.gdshader"]:
		check(shaders.has(name), "The first wreck, pickup, remains and grid effects are prepared: " + name)
	# The wreck uses one shared material; warming a copy would not be the same.
	check(materials.has(preload("res://scripts/enemy_motion_wreck.gd").wreck_material()), "The shared wreck material itself is warmed")
	check(FileAccess.get_file_as_string("res://scripts/game.gd").contains("res://scripts/render_warmup.gd"), "The scenario start adds the warm-up")
	var holder := Node2D.new()
	root.add_child(holder)
	var warmup := Warmup.new()
	holder.add_child(warmup)
	await process_frame
	await process_frame
	check(holder.get_child_count() == 0, "Without a display the warm-up removes itself at once and adds no lamp")
	holder.queue_free()
	print("RENDER WARMUP: %d failures" % failures)
	quit(1 if failures else 0)
