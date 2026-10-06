extends SceneTree
## Genuine menu/world captures and native shader attenuation. Capture readbacks
## occur only here, never in the running SkyTraffic presentation component.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Traffic := preload("res://scripts/sky_traffic.gd")
const OUTPUT := "res://artifacts/sky-traffic/"
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var view: SubViewport

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures+=1;push_error(label)
	print("SKY TRAFFIC %s: %s" % ["PASS" if ok else "FAIL",label])

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func capture(id: String,prepared: String,details: Dictionary={}) -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size()==view.size and picture.save_png(OUTPUT+id+".png")==OK,id+" native capture exports the exact viewport")
	var record := {"id":id,"file":id+".png","prepared":prepared,"resolution":[view.size.x,view.size.y],"renderer":RenderingServer.get_video_adapter_name()}
	record.merge(details)
	captures.append(record)
	return picture

func _world(id: String) -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"center"})
	await frames(7)
	game.rounds.running=false
	game.notice_time=0
	game.players[0].position=Vector2(680,430)
	freeze(game)
	game.camera.position=Vector2(720,150)
	game.camera.zoom=Vector2.ONE*.85
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await frames()
	var scenery: ScenarioScenery=game.scenery
	scenery._visible_rect=scenery.get_global_transform_with_canvas().affine_inverse()*view.get_visible_rect()
	scenery.elapsed=8.0
	scenery._update_background_view(false)
	var sky= scenery.parallax_background.sky_traffic
	sky.hide()
	var before := Image.new()
	var restored := before.load_png_from_buffer(FileAccess.get_file_as_bytes(OUTPUT+"legacy/"+id+"-before.png"))
	check(restored==OK and not before.is_empty(),id+" preserved actual pre-migration capture remains available")
	captures.append({"id":id+"-before","file":"legacy/"+id+"-before.png","prepared":"Actual one-player pre-migration capture: old foreground ash still drawn, same authored world camera and clock8; new sky component hidden","environment":id,"clock":8.0,"view":"world","mode":"before","resolution":[view.size.x,view.size.y]})
	sky.show()
	scenery.particle_layer.queue_redraw()
	var after := await capture(id+"-after","Same genuine mission, camera, clock and foreground; distant lights between original-atlas cloud cutouts, GPU foreground attenuation",{"environment":id,"clock":8.0,"view":"world","mode":"after","visible_lights":sky.light_nodes.filter(func(light):return light.visible).size(),"light_positions":sky.light_nodes.map(func(light):return [light.position.x,light.position.y])})
	check(before.get_data()!=after.get_data(),id+" actual world composition changes through the depth component")
	scenery.elapsed=24.0
	scenery._update_background_view(false)
	var moved := await capture(id+"-motion","Same frozen world at authoritative scene clock24; only background presentation evolves",{"environment":id,"clock":24.0,"view":"world","mode":"motion"})
	check(moved.get_data()!=after.get_data(),id+" native world shows real pixel motion at a held camera")
	check(not game.network.active and not game.microphone.capturing,"Genuine "+id+" scene opens no transport or microphone")
	check(await Cleanup.free_scene(game,self),id+" native world releases every node/audio handle")

func _menu() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	var menu: Control=game.hud.main_menu_panel
	for index in menu.environments.size():
		if str(menu.environments[index].id)=="ash_foundry": menu.environment_index=index
	menu._show_environment()
	await frames()
	freeze(game)
	var scenery: Node2D=menu.preview
	scenery.elapsed=8.0
	scenery._process(1.0)
	var sky=scenery.distant_sky_lights
	sky.hide()
	captures.append({"id":"menu-before","file":"legacy/menu-before.png","prepared":"Actual pre-migration main menu Aschewerk: preview clock8, old foreground ash still drawn, new sky depth hidden","environment":"ash_foundry","clock":8.0,"view":"menu","mode":"before","resolution":[view.size.x,view.size.y]})
	sky.show()
	scenery.atmosphere.queue_redraw()
	await capture("menu-after","Same genuine main menu and clock8; only the two cloud planes and larger attenuated sky lights enabled",{"environment":"ash_foundry","clock":8.0,"view":"menu","mode":"after","visible_lights":sky.light_nodes.filter(func(light):return light.visible).size(),"light_positions":sky.light_nodes.map(func(light):return [light.position.x,light.position.y])})
	check(not game.started and game.players.is_empty() and not game.network.active and not game.microphone.capturing,"Actual menu creates no worker, network or microphone")
	check(await Cleanup.free_scene(game,self),"Native menu fixture releases cleanly")

func _attenuation() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(192,128)
	viewport.transparent_bg=true
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var plane := Node2D.new()
	plane.position=Vector2(96,64)
	var material := ShaderMaterial.new()
	material.shader=Traffic.LIGHT_SHADER
	material.set_shader_parameter("near_clouds",[Vector4(0,0,192,128),Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
	material.set_shader_parameter("cloud_texel",Vector2(1.0/48,1.0/36))
	material.set_shader_parameter("illumination",1.0)
	material.set_shader_parameter("light_origin",plane.position)
	plane.material=material
	plane.draw.connect(func():plane.draw_rect(Rect2(-14,-9,28,18),Color.WHITE))
	viewport.add_child(plane)
	var samples: Array[float] = []
	for density: float in [0.0,.36,.95]:
		var source := Image.create(48,36,false,Image.FORMAT_RGBA8)
		source.fill(Color(1,1,1,density))
		material.set_shader_parameter("cloud_atlas",ImageTexture.create_from_image(source))
		await frames()
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var alpha: float=picture.get_pixel(96,64).a
		samples.append(alpha)
		picture.save_png(OUTPUT+"attenuation-"+str(roundi(density*100))+".png")
	check(samples[0]>.95 and samples[1]>.1 and samples[1]<samples[0]*.8 and samples[2]<.005,"Actual GPU shader keeps clear core, dims thin cloud and fully hides dense cloud: "+str(samples))
	# The original cutout, not merely synthetic alpha, must contain working
	# transparent gaps, thin edges and dense volumes after its real deformation.
	var atlas: Image=Traffic.CLOUDS.get_image()
	# Authored soft edge at this source coordinate remains a thin fringe under
	# the production phase/clock deformation, verified by the GPU below.
	var targets: Dictionary={"wisp":Vector2i(625,710)}
	for y in range(730,960,4):
		for x in range(280,1250,4):
			var alpha: float=atlas.get_pixel(x,y).a
			var kind := "gap" if alpha<.002 else ("dense" if alpha>.95 else ("wisp" if alpha>.30 and alpha<.45 else ""))
			if kind.is_empty() or targets.has(kind): continue
			var stable := true
			for dy in [-4,0,4]:
				for dx in [-4,0,4]:
					var neighbor: float=atlas.get_pixel(x+dx,y+dy).a
					if (kind=="gap" and neighbor>.005) or (kind=="dense" and neighbor<.80) or (kind=="wisp" and absf(neighbor-alpha)>.15): stable=false
			if stable: targets[kind]=Vector2i(x,y)
	check(targets.size()==3,"Original imported PNG contains coherent native gap, wisp and dense samples")
	material.set_shader_parameter("cloud_atlas",Traffic.CLOUDS)
	material.set_shader_parameter("cloud_texel",Vector2.ONE/Traffic.CLOUDS.get_size())
	material.set_shader_parameter("cloud_phase",2.73)
	material.set_shader_parameter("cloud_clock",8.0)
	var actual_samples: Dictionary={}
	for kind: String in ["gap","wisp","dense"]:
		if not targets.has(kind): continue
		var texel: Vector2i=targets[kind]
		var row_height := Traffic.CLOUDS.get_height()/3.0
		material.set_shader_parameter("near_clouds",[Vector4(96-texel.x,64-(texel.y-row_height*2),Traffic.CLOUDS.get_width(),row_height),Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
		await frames()
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var alpha: float=picture.get_pixel(96,64).a
		actual_samples[kind]={"alpha":alpha,"source_alpha":atlas.get_pixelv(texel).a,"texel":[texel.x,texel.y]}
		picture.save_png(OUTPUT+"actual-atlas-"+kind+".png")
	check(actual_samples.size()==3 and actual_samples.gap.alpha>.95 and actual_samples.wisp.alpha>.05 and actual_samples.wisp.alpha<.90 and actual_samples.dense.alpha<.005,"Genuine shader and original PNG preserve a clear gap, attenuate the wisp and fully hide dense cloud: "+str(actual_samples))
	FileAccess.open(OUTPUT+"occlusion.json",FileAccess.WRITE).store_string(JSON.stringify({"controlled_alpha":samples,"original_atlas":actual_samples,"source":Traffic.CLOUDS.resource_path,"source_clock":8.0,"phase":2.73},"  "))
	viewport.queue_free()
	await frames()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled=false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view=SubViewport.new()
	view.size=Vector2i(1440,810)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for id: String in ["ash_foundry","mountain_pass","overgrown_steelworks","frozen_rail_yard"]: await _world(id)
	await _menu()
	await _attenuation()
	var report := {"checks":checks,"failures":failures,"captures":captures,"fixture":"Actual Godot Compatibility scenes, frozen one-player missions and real main-menu preview, matching camera and scene clock. Master muted, unsaved isolated profiles, no network/microphone. Small native host, exact1440×810 SubViewport. Controlled uniform atlas-alpha shader probes complement real-cloud native views. This is pixel/composition evidence, not a FPS benchmark."}
	FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var html := "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Bunkercrew · Himmelstiefe</title><style>body{max-width:1460px;margin:30px auto;padding:0 20px;background:#11191d;color:#e2dec9;font:17px system-ui}p{line-height:1.5;color:#a8b3af}img{width:100%}figure{margin:36px 0}a{color:#dabb79}</style><h1>Bunkercrew · Lichtpunkte zwischen Wolken</h1><p>Echte Godot-Szenen bei gleicher Kamera und gleichem Takt. Vorbereitete Soloansichten mit angehaltenen Wellen und stummem Master; keinerlei Profiländerungen. <a href='gallery.json'>Prüfzustände</a>.</p>"
	for entry: Dictionary in captures: html+="<figure><img loading='lazy' src='%s'><figcaption>%s<br>%s</figcaption></figure>" % [entry.file,entry.id,entry.prepared]
	FileAccess.open(OUTPUT+"index.html",FileAccess.WRITE).store_string(html)
	view.queue_free()
	await frames()
	print("SKY TRAFFIC GALLERY: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
