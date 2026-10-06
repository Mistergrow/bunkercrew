extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/mountain-pass-layers"
var checks := 0
var failures := 0
var records: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false);node.set_physics_process(false)
	for child in node.get_children():freeze(child)
func frame(game, at: Vector2, zoom: float, seconds: float, enabled: bool) -> void:
	game.camera.position=at;game.camera.zoom=Vector2.ONE*zoom
	game.camera.reset_smoothing();game.camera.force_update_scroll()
	game.scenery.elapsed=seconds
	game.scenery._visible_rect=game.scenery.get_global_transform_with_canvas().affine_inverse()*game.scenery.get_viewport_rect()
	game.scenery.set_layered_enabled(enabled)
	for wait_frame in 3:await process_frame
func capture(name: String) -> Image:
	for wait_frame in 3:await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image()
	result.save_png(OUTPUT+"/"+name+".png")
	return result
func movie(game) -> void:
	var directory:=OUTPUT+"/frames"
	DirAccess.make_dir_recursive_absolute(directory)
	for index in 120:
		var seconds:=float(index)/24.0
		var pan:=720.0+480.0*sin(PI*float(index)/119.0)
		game.camera.position=Vector2(pan,-180)
		game.camera.zoom=Vector2.ONE*.65
		game.camera.reset_smoothing();game.camera.force_update_scroll()
		game.scenery.elapsed=seconds
		game.scenery._visible_rect=game.scenery.get_global_transform_with_canvas().affine_inverse()*game.scenery.get_viewport_rect()
		game.scenery.set_layered_enabled(true)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/%04d.png"%index)
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():quit(2);return
	var gpu:=DisplayServer.get_name()!="headless"
	if gpu:
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1920,1080)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game);current_scene=game
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	game.rounds.running=false;game.notice="";game.notice_time=0
	game.players[0].position=Vector2(630,430)
	freeze(game)
	var scenery: ScenarioScenery=game.scenery
	check(is_instance_valid(scenery.parallax_background),"Bergpass creates three real depth plates")
	check(scenery.parallax_background.layers.size()==3,"Sky, ridges and valley have separate sprite transforms")
	for layer in scenery.parallax_background.layers:
		check(layer.texture.get_size()==Vector2(1672,941),layer.name+" retains the full generated source resolution")
	for camera in [Vector3(720,-180,.6),Vector3(1300,-180,.6),Vector3(380,-220,1),Vector3(1100,120,2.2),Vector3(-500,-420,.6)]:
		await frame(game,Vector2(camera.x,camera.y),camera.z,6.7,true)
		var view: Rect2=scenery._visible_rect
		view.size.y=minf(view.size.y,430-view.position.y)
		for rect in scenery.parallax_background.layer_rects:
			check(rect.encloses(view),"Each layer covers visible above-ground world at "+str(camera))
		check(not scenery.panorama.visible and not scenery.lighting_layer.effects_enabled,"Flat emitters are disabled for the regenerated layer composition")
		records.append({"camera":camera,"bounds":scenery.parallax_background.layer_rects.duplicate()})
	await frame(game,Vector2(1200,-180),.65,0,true)
	var layers = scenery.parallax_background.layer_rects
	check(absf(layers[0].position.x-layers[1].position.x)>10 and absf(layers[1].position.x-layers[2].position.x)>10,"Camera movement separates the three depths")
	if gpu:
		await frame(game,Vector2(720,-180),.65,0,false)
		await capture("original")
		await frame(game,Vector2(720,-180),.65,0,true)
		var first:=await capture("layers-t0")
		await frame(game,Vector2(720,-180),.65,8,true)
		var later:=await capture("layers-t8")
		check(first.get_data()!=later.get_data(),"Fixed-camera cloud, mist, water and signal animation changes rendered pixels")
		await frame(game,Vector2(1200,-180),.65,8,true)
		await capture("layers-pan")
		await frame(game,Vector2(630,330),2.2,8,true)
		await capture("layers-close")
		if "--video" in OS.get_cmdline_user_args():await movie(game)
	scenery.parallax_background.update_view(scenery.panorama_rect,scenery._visible_rect,8,true)
	check(not scenery.parallax_background.mist.visible and scenery.parallax_background.materials.all(func(surface):return surface.get_shader_parameter("motion_gain")==0.0),"F3 removes extra mist and freezes material animation")
	scenery.set_layered_enabled(false)
	check(scenery.panorama.visible and not scenery.parallax_background.visible and scenery.lighting_layer.effects_enabled,"Comparison restores original art and matching emitters")
	for enabled in [true,false]:
		var key:=InputEventKey.new();key.keycode=KEY_F8;key.physical_keycode=KEY_F8;key.pressed=true
		Input.parse_input_event(key)
		for wait_frame in 3:await process_frame
		check(scenery.layered_enabled==enabled,"Actual F8 input toggles the in-game comparison")
		key=InputEventKey.new();key.keycode=KEY_F8;key.physical_keycode=KEY_F8;key.pressed=false
		Input.parse_input_event(key)
		await process_frame
	var output:=FileAccess.open(OUTPUT+"/verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"prepared":"Actual mountain_pass game, one stationary player, combat and other presentation frozen, 1920x1080 captures, background t=0/t=8 and camera pan/zoom.","records":records},"  "))
	output.close()
	await Cleanup.free_scene(game,self)
	print("PARALLAX LANDSCAPE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
