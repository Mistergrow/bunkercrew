extends SceneTree
## Actual scenario scenes, camera coverage, rendered animation and input fallback.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/parallax_catalog.gd")
const Depths := preload("res://scripts/parallax_landscape.gd")
const Baseline := preload("res://tests/background_preview_baseline.gd")
const OUTPUT := "res://artifacts/all-level-layers"
var checks := 0
var failures := 0
var records: Array = []
var gpu := false
var capture_enabled := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false);node.set_physics_process(false)
	for child in node.get_children():freeze(child)

func view_at(game,at: Vector2,zoom: float,seconds: float,enabled: bool=true) -> void:
	game.camera.position=at;game.camera.zoom=Vector2.ONE*zoom
	game.camera.reset_smoothing();game.camera.force_update_scroll()
	game.scenery.elapsed=seconds
	game.scenery._visible_rect=game.scenery.get_global_transform_with_canvas().affine_inverse()*game.scenery.get_viewport_rect()
	game.scenery.set_layered_enabled(enabled)
	for frame in 3:await process_frame

func capture(path: String) -> void:
	for frame in 2:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func isolated_animation(id: String) -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.disable_3d=true
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var depths:=Depths.new()
	depths.configure(id);viewport.add_child(depths)
	var rect:=Rect2(0,0,640,360)
	depths.update_view(rect,rect,0,false)
	for frame in 2:await RenderingServer.frame_post_draw
	var first:=viewport.get_texture().get_image().get_data()
	depths.update_view(rect,rect,8,false)
	for frame in 2:await RenderingServer.frame_post_draw
	check(first!=viewport.get_texture().get_image().get_data(),id+": independently rendered background moves at a fixed camera")
	depths.update_view(rect,rect,0,true)
	for frame in 2:await RenderingServer.frame_post_draw
	var reduced:=viewport.get_texture().get_image().get_data()
	depths.update_view(rect,rect,8,true)
	for frame in 2:await RenderingServer.frame_post_draw
	check(reduced==viewport.get_texture().get_image().get_data(),id+": F3 freezes every extra background pixel")
	depths.layers[0].hide();depths.layers[2].hide();depths.mist.hide()
	depths.update_view(rect,rect,0,true)
	for frame in 2:await RenderingServer.frame_post_draw
	var architecture:=viewport.get_texture().get_image().get_data()
	depths.update_view(rect,rect,8,true)
	for frame in 2:await RenderingServer.frame_post_draw
	check(architecture==viewport.get_texture().get_image().get_data(),id+": sharper distant architecture stays rigid at a fixed camera")
	await Cleanup.free_scene(viewport,self)

func movie(game,directory: String) -> void:
	var frames_directory:=directory+"/frames"
	DirAccess.make_dir_recursive_absolute(frames_directory)
	for index in 48:
		var t:=float(index)/47.0
		await view_at(game,Vector2(720+520*sin(t*PI),-180),.65,8+t*7)
		for frame in 2:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(frames_directory+"/%04d.jpg"%index,.97)

func exercise(entry: Dictionary) -> void:
	var id:=str(entry.id)
	check(Catalog.available(id),id+": all three authored plates are imported")
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game);current_scene=game
	game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
	game.rounds.running=false;game.notice="";game.notice_time=0
	game.players[0].position=Vector2(630,430)
	freeze(game)
	var scenery: ScenarioScenery=game.scenery
	check(is_instance_valid(scenery.parallax_background),id+": scenario enables real depth layers by default")
	if not is_instance_valid(scenery.parallax_background):
		await Cleanup.free_scene(game,self);return
	var depths=scenery.parallax_background
	check(depths.environment_id==id and depths.layers.size()==3,id+": each scene uses its own three depth plates")
	for index in 3:
		var size: Vector2=depths.layers[index].texture.get_size()
		check(size.x>=1600 and size.y>=900 and absf(size.x/size.y-1672.0/941)<.003,id+": source keeps its original high-resolution 16:9 canvas")
		check(depths.layers[index].texture.resource_path==Catalog.paths(id)[index],id+": texture belongs to this location")
	var architecture_uniforms: Array = depths.layers[1].material.shader.get_shader_uniform_list().map(func(uniform):return uniform.name)
	check(not "scene_clock" in architecture_uniforms,id+": distant architecture has no animation clock")
	check(depths.image_materials.size()==3 and depths.image_materials.all(func(surface):return surface.get_shader_parameter("pixel_clarity")==1.0),id+": all three plates preserve crisp texel interiors")
	# A desktop window manager can clamp a 2560px window to the monitor width.
	# Render the actual complete scene in its own viewport for every aspect.
	var scenario_view:=SubViewport.new()
	scenario_view.disable_3d=true;scenario_view.world_2d=World2D.new()
	scenario_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(scenario_view)
	game.reparent(scenario_view)
	game.camera.make_current()
	for screen in [Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1280,960)]:
		scenario_view.size=screen
		for frame in 3:await process_frame
		check(scenario_view.size==screen and scenario_view.get_visible_rect().size==Vector2(screen),id+": requested aspect uses the actual scenario viewport")
		if gpu:
			for frame in 2:await RenderingServer.frame_post_draw
			check(scenario_view.get_texture().get_image().get_size()==screen,id+": actual rendered texture uses the requested pixel dimensions")
		for camera in [Vector3(720,-180,.6),Vector3(1300,-180,.6),Vector3(380,-220,1),Vector3(1100,120,2.2),Vector3(-500,-420,.6)]:
			await view_at(game,Vector2(camera.x,camera.y),camera.z,6.7)
			var visible: Rect2=scenery._visible_rect
			visible.size.y=minf(visible.size.y,430-visible.position.y)
			for bounds: Rect2 in depths.layer_rects:
				check(bounds.encloses(visible),id+": coverage at "+str(screen)+" / "+str(camera))
			check(not scenery.panorama.visible and not scenery.surface_layer.visible and not scenery.lighting_layer.visible and not scenery.mist_layer.visible,id+": old panorama emitters cannot overlap the moving plates")
			check(scenery.smoke_nodes.all(func(node):return not node.visible),id+": old chimney anchors are hidden")
	game.reparent(root)
	game.camera.make_current()
	await Cleanup.free_scene(scenario_view,self)
	root.size=Vector2i(1920,1080)
	await view_at(game,Vector2(1200,-180),.65,8)
	check(absf(depths.layer_rects[0].position.x-depths.layer_rects[1].position.x)>10 and absf(depths.layer_rects[1].position.x-depths.layer_rects[2].position.x)>10,id+": camera motion separates all three depths")
	var directory:=OUTPUT+"/"+id
	if capture_enabled:
		DirAccess.make_dir_recursive_absolute(directory)
		await view_at(game,Vector2(720,450),1.0,8)
		var magnification: float=scenery.get_global_transform_with_canvas().get_scale().x
		Baseline.show_previous(depths,scenery.panorama_rect,scenery._visible_rect,magnification,8)
		await capture(directory+"/normal-previous.png")
		Baseline.show_current(depths,scenery.panorama_rect,scenery._visible_rect,8)
		await capture(directory+"/layers-normal.png")
		await view_at(game,Vector2(720,-180),.65,0,false)
		await capture(directory+"/original.png")
		await view_at(game,Vector2(720,-180),.65,0)
		await capture(directory+"/layers-t0.png")
		await view_at(game,Vector2(720,-180),.65,8)
		await capture(directory+"/layers-t8.png")
		await view_at(game,Vector2(1200,-180),.65,8)
		await capture(directory+"/layers-pan.png")
		await view_at(game,Vector2(630,330),2.2,8)
		await capture(directory+"/layers-close.png")
		if "--video" in OS.get_cmdline_user_args():await movie(game,directory)
	depths.update_view(scenery.panorama_rect,scenery._visible_rect,8,true)
	check(not depths.mist.visible and depths.materials.all(func(surface):return surface.get_shader_parameter("motion_gain")==0.0),id+": reduced-effects mode disables extra mist and animation")
	if gpu:await isolated_animation(id)
	scenery.set_layered_enabled(false)
	check(scenery.panorama.visible and scenery.surface_layer.visible and scenery.lighting_layer.visible and scenery.mist_layer.visible and scenery.smoke_nodes.all(func(node):return node.visible),id+": comparison restores every original emitter")
	for enabled in [true,false]:
		var key:=InputEventKey.new();key.keycode=KEY_F8;key.physical_keycode=KEY_F8;key.pressed=true
		Input.parse_input_event(key)
		for frame in 3:await process_frame
		check(scenery.layered_enabled==enabled,id+": real F8 input toggles comparison")
		key=InputEventKey.new();key.keycode=KEY_F8;key.physical_keycode=KEY_F8;key.pressed=false
		Input.parse_input_event(key);await process_frame
	scenery.set_layered_enabled(true)
	scenery.set_process(true)
	paused=true
	var before:=scenery.elapsed
	for frame in 3:await process_frame
	check(scenery.elapsed==before,id+": pause stops the background transport")
	paused=false;scenery.set_process(false)
	records.append({"id":id,"title":entry.title,"plates":Catalog.paths(id),"screens":["1920x1080","2560x1080","1280x960"],"captures":capture_enabled})
	await Cleanup.free_scene(game,self)
	print("PARALLAX LOCATION: "+id)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():quit(2);return
	AudioServer.set_bus_mute(0,true)
	gpu=DisplayServer.get_name()!="headless"
	capture_enabled=gpu and "--capture" in OS.get_cmdline_user_args()
	if gpu:
		root.mode=Window.MODE_WINDOWED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var entries:=ScenarioCatalog.environments(true)
	check(entries.size()==13,"All thirteen campaign and free-play locations are covered")
	for entry: Dictionary in entries:await exercise(entry)
	var report:={"checks":checks,"failures":failures,"gpu":gpu,"prepared":"Actual single-player scenario scenes; one stationary character, waves and other presentation frozen. Three screen aspects, five camera states each. Isolated GPU animation/F3 comparison, actual F8 and pause.","locations":records}
	var output:=FileAccess.open(OUTPUT+"/verification-"+("rendered" if gpu else "headless")+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "));output.close()
	print("ALL LEVEL PARALLAX: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
