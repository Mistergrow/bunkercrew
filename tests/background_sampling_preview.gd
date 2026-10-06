extends SceneTree
## Identical foreground: bilinear, point, previous framing and current style.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Baseline := preload("res://tests/background_preview_baseline.gd")
const OUTPUT := "res://artifacts/all-level-layers/sharpness"
func _initialize() -> void: run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false);node.set_physics_process(false)
	for child in node.get_children():freeze(child)
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():quit(2);return
	AudioServer.set_bus_mute(0,true)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1440,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var records: Array=[]
	for id in ["mountain_pass","ash_foundry","abandoned_harbor"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game);current_scene=game
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.running=false;game.notice="";game.notice_time=0
		freeze(game)
		for zoom: float in [1.0,2.2]:
			game.camera.position=Vector2(720,450) if zoom==1.0 else Vector2(600,330)
			game.camera.zoom=Vector2.ONE*zoom
			game.camera.reset_smoothing();game.camera.force_update_scroll()
			for frame in 3:await process_frame
			var scenery: ScenarioScenery=game.scenery
			scenery._visible_rect=scenery.get_global_transform_with_canvas().affine_inverse()*scenery.get_viewport_rect()
			scenery.elapsed=8;scenery.set_layered_enabled(true)
			var depths=scenery.parallax_background
			for mode in ["linear","point","previous","crisp"]:
				var bounds: Rect2=scenery.panorama_rect
				if mode=="previous":
					var transform: Transform2D=scenery.get_global_transform_with_canvas()
					bounds=Baseline.frame(scenery._visible_rect,1672.0/941.0,transform.get_scale().x)
				depths.update_view(bounds,scenery._visible_rect,8,false)
				depths.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST if mode=="point" else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				for index in depths.image_materials.size():
					var surface: ShaderMaterial=depths.image_materials[index]
					var style: Dictionary=preload("res://scripts/parallax_catalog.gd").IMAGE_STYLES[index]
					surface.set_shader_parameter("pixel_clarity",1.0 if mode in ["previous","crisp"] else 0.0)
					surface.set_shader_parameter("detail_strength",float(style.detail_strength) if mode=="crisp" else (.3 if mode=="previous" else 0.0))
					surface.set_shader_parameter("sample_radius",float(style.sample_radius) if mode=="crisp" else 1.0)
					surface.set_shader_parameter("contour_strength",float(style.contour_strength) if mode=="crisp" else 0.0)
				for frame in 2:await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT+"/%s-%s-%.1f.png"%[id,mode,zoom])
				records.append({"id":id,"zoom":zoom,"mode":mode,"source_texel_screen_width":depths.layers[2].scale.x*scenery.get_global_transform_with_canvas().get_scale().x})
		await Cleanup.free_scene(game,self)
	var output:=FileAccess.open(OUTPUT+"/framing.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"prepared":"Same frozen 1440x900 scene, camera, background clock and foreground. Previous mode reproduces former 3000/2200 framing and mild shader; other modes share current 1800/1600 framing.","records":records},"  "));output.close()
	print("BACKGROUND SAMPLING: three locations, two zooms, four modes captured")
	quit()
