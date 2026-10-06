extends SceneTree
## Actual wide sky-view depth plates, with other atmosphere and water disabled.
## Three-second painted sky drift must visibly affect broad regions below HUD.
const Plates := preload("res://scripts/parallax_catalog.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	print("VISIBLE SKY %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func frame_image() -> Image:
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func run():
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Visible-background test needs a graphical renderer, --no-profile-save and --no-upnp")
		quit(1)
		return
	root.size=Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	for environment: String in Plates.PROFILES:
		var entry: Dictionary=ScenarioCatalog.environment(environment)
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.notice_time=0
		# Camera and menu helpers use PROCESS_MODE_ALWAYS. Disabling only their
		# parent leaves them running and falsely counts reframing as sky motion.
		freeze(game)
		game.weather.visible=false
		game.weather.set_process(false)
		# The close bunker view legitimately crops the authored sky completely on
		# several V3 plates. Use the actual wide sky overview for cloud visibility.
		game.camera.position=Vector2(720,-180)
		game.camera.zoom=Vector2.ONE*.6
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		for settle in 3: await process_frame
		var scenery=game.scenery
		var depths: Node2D=scenery.parallax_background
		scenery.set_process(false)
		scenery.particle_layer.visible=false
		scenery.mist_layer.visible=false
		scenery.lighting_layer.effects_enabled=false
		scenery.surface_layer.visible=false
		scenery.props_layer.visible=false
		scenery.vegetation_layer.visible=false
		scenery.fauna_layer.visible=false
		scenery.elapsed=0
		scenery.offset=Vector2.ZERO
		scenery._process(0)
		depths.mist.hide()
		depths.image_materials[2].set_shader_parameter("motion_gain",0.0)
		depths.image_materials[2].set_shader_parameter("light_gain",0.0)
		var fixed_landmarks: Transform2D=depths.layers[2].transform
		var first: Image=await frame_image()
		scenery._process(3.0)
		# Updating the production composition normally enables all motion again.
		# Hold landmarks/water and mist explicitly: only the sky plate may change.
		depths.mist.hide()
		depths.image_materials[2].set_shader_parameter("motion_gain",0.0)
		depths.image_materials[2].set_shader_parameter("scene_clock",0.0)
		depths.image_materials[2].set_shader_parameter("light_gain",0.0)
		var second: Image=await frame_image()
		var first_bytes:=first.get_data()
		var second_bytes:=second.get_data()
		var changed:=0
		var blocks: Dictionary={}
		# Include the exposed sky on both sides. Mountains/dams legitimately
		# occupy the old right-hand test rectangle; clouds must stay behind them.
		for y in range(84,320):
			for x in range(16,1424):
				if x<760 and y>=174: continue
				var index: int=(y*1440+x)*4
				var difference:=0
				for channel in 3:
					difference=maxi(difference,absi(int(first_bytes[index+channel])-int(second_bytes[index+channel])))
				if difference>=10:
					changed+=1
					var key:=Vector2i(floori((x-16)/40.0),floori((y-84)/40.0))
					blocks[key]=int(blocks.get(key,0))+1
		var active_blocks:=0
		for count in blocks.values():
			if int(count)>=32: active_blocks+=1
		var minimum_blocks := 18
		check(changed>=5000 and active_blocks>=minimum_blocks,"%s: 3s clouds alone change %d visible pixels by >=10/255 across %d blocks below HUD"%[entry.id,changed,active_blocks])
		check(depths.layers[2].transform==fixed_landmarks,"%s: sky motion leaves landmark geometry fixed"%entry.id)
		if entry.id=="sector07":
			check(depths.layers[0].texture==load(Plates.paths(entry.id)[0]) and depths.layers[2].texture==load(Plates.paths(entry.id)[2]) and depths.layers[0].get_index()<depths.layers[2].get_index(),"sector07 uses its authored sky behind the separate transparent landmark plate")
		first.save_png("res://artifacts/visible-clouds-%s-0s.png"%entry.id)
		second.save_png("res://artifacts/visible-clouds-%s-3s.png"%entry.id)
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("VISIBLE BACKGROUNDS: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
