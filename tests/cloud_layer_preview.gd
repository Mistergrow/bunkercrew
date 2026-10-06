extends SceneTree
## Fixed normal follow framing of actual matches. Only cloud clocks advance in
## still comparisons; the optional 9s/world clip advances scene atmosphere.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport
var output := "res://artifacts/cloud-layers"
var checks := 0
var failures := 0
var report: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1
	print("CLOUD LAYERS %s: %s"%["PASS" if value else "FAIL",label])
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func redraw(seconds: float) -> Image:
	game.scenery.cloud_motion.reset()
	game.scenery.elapsed=seconds
	game.scenery.offset=Vector2.ZERO
	game.scenery._process(0)
	game.scenery.sky_material.set_shader_parameter("sky_clock",0.0)
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	root.size=Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var before := "--before" in OS.get_cmdline_user_args()
	if before: output+="/before"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var worlds := ["flooded_power_station","sector07","mountain_pass"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--worlds="): worlds=Array(argument.trim_prefix("--worlds=").split(","))
	for environment in worlds:
		game=load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
		game.notice_time=0
		game.set_camera_zoom(1.25)
		game.player_camera.update_view(0,true)
		freeze(game)
		game.weather.hide()
		game.scenery.particle_layer.hide()
		game.scenery.mist_layer.hide()
		game.scenery.lighting_layer.effects_enabled=false
		game.scenery.surface_layer.hide()
		await process_frame
		var camera_start: Vector2=game.camera.position
		for seconds in [0.0,3.0]:
			var full := await redraw(seconds)
			check(full.get_size()==view.size,"%s %.0fs actual QHD"%[environment,seconds])
			full.save_png(output+"/%s-%ds.png"%[environment,int(seconds)])
			for depth in 3:
				game.scenery.cloud_layers[depth].hide()
				var without := await redraw(seconds)
				without.save_png(output+"/%s-%ds-without%d.png"%[environment,int(seconds),depth])
				game.scenery.cloud_layers[depth].show()
		if not before:
			# Isolate the SAME draw callback and texture to measure translation.
			# The main stills retain the fixed skyline; these alpha planes remove
			# that occluder only, so optical flow cannot mistake a tower for a cloud.
			var isolated := SubViewport.new()
			isolated.size=view.size
			isolated.size_2d_override=view.size_2d_override
			isolated.size_2d_override_stretch=true
			isolated.transparent_bg=true
			isolated.world_2d=World2D.new()
			isolated.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(isolated)
			for depth in 3:
				var plane := Node2D.new()
				plane.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
				plane.transform=game.scenery.get_global_transform_with_canvas()
				if game.scenery.cloud_layers[depth].material!=null:
					plane.material=game.scenery.cloud_layers[depth].material.duplicate()
					plane.material.set_shader_parameter("mask_landmarks",false)
				plane.draw.connect(game.scenery._draw_cloud_depth.bind(plane,depth))
				isolated.add_child(plane)
				for seconds in [0.0,3.0]:
					game.scenery.cloud_motion.reset()
					game.scenery.elapsed=seconds
					plane.queue_redraw()
					await RenderingServer.frame_post_draw
					isolated.get_texture().get_image().save_png(output+"/%s-plane%d-%ds.png"%[environment,depth,int(seconds)])
				game.camera.position.x+=100
				game.camera.force_update_scroll()
				game.scenery._process(0)
				plane.transform=game.scenery.get_global_transform_with_canvas()
				plane.queue_redraw()
				await RenderingServer.frame_post_draw
				isolated.get_texture().get_image().save_png(output+"/%s-plane%d-pan.png"%[environment,depth])
				game.camera.position.x-=100
				game.camera.force_update_scroll()
				game.scenery._process(0)
				plane.queue_free()
				await process_frame
			isolated.queue_free()
			await process_frame
		if "--record" in OS.get_cmdline_user_args():
			var directory: String=output+"/"+environment+"-frames"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			game.scenery.elapsed=0
			game.scenery.cloud_motion.reset()
			for frame in 270:
				# Fixed camera and calm weather isolate true normal-speed altitude
				# motion. No time acceleration or moving player/camera disguises it.
				game.scenery.elapsed=float(frame)/30.0
				game.scenery._process(0)
				await RenderingServer.frame_post_draw
				view.get_texture().get_image().save_jpg(directory+"/%04d.jpg"%frame,.95)
		check(game.camera.position==camera_start,"%s camera stays fixed"%environment)
		report.append({"world":environment,"camera":[camera_start.x,camera_start.y],"zoom":game.camera.zoom.x,"speeds":[game.scenery.cloud_speed(0),game.scenery.cloud_speed(1),game.scenery.cloud_speed(2)]})
		await Cleanup.free_scene(game,self)
	view.queue_free()
	await process_frame
	var file := FileAccess.open(output+"/measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("CLOUD LAYER PREVIEW %d/%d"%[checks-failures,checks])
	quit(1 if failures else 0)
