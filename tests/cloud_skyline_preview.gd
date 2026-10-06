extends SceneTree
## Prepared diagnostic: original panoramas with the authored sky cutoff in gold.
const Skyline = preload("res://scripts/cloud_skyline.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := "res://artifacts/cloud-skyline"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for environment_id: String in Skyline.SKYLINES:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(2048, 683)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = World2D.new()
		root.add_child(viewport)
		var background := Sprite2D.new()
		background.centered = false
		background.texture = load("res://assets/environments/v2/%s.png" % environment_id)
		background.scale = Vector2(viewport.size) / background.texture.get_size()
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(background)
		var outline := Skyline.points(environment_id)
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color("ffd96a")
		for point: Vector2 in outline:
			line.add_point(Vector2(point.x, maxf(0.0, point.y - Skyline.EDGE_MARGIN)) * Vector2(viewport.size))
		viewport.add_child(line)
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("%s/%s.png" % [output, environment_id])
		viewport.queue_free()
		await process_frame
	print("CLOUD SKYLINE PREVIEW: eight untouched panoramas with geometric cutoff lines")
	quit()
