extends SceneTree
## Real selected worlds: independent air motion, unchanged painted geometry,
## actual paused frames, F3 density, and authored surface effect boundaries.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("SCENERY %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func frames(count := 3) -> void:
	for index in count:
		await process_frame
		await physics_frame

func check_rendered_water(scenery: ScenarioScenery) -> void:
	# Isolate the real panorama shader from rain, UI and workers so a pixel
	# comparison can prove that reflection motion leaves the architecture alone.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024,342)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var art := Sprite2D.new()
	art.centered = false
	art.texture = scenery.panorama.texture
	art.scale = Vector2(viewport.size)/art.texture.get_size()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := scenery.sky_material.duplicate() as ShaderMaterial
	art.material = material
	viewport.add_child(art)
	material.set_shader_parameter("sky_clock",1.0)
	material.set_shader_parameter("water_amplitude",2.25)
	await RenderingServer.frame_post_draw
	var first_image := viewport.get_texture().get_image()
	first_image.convert(Image.FORMAT_RGBA8)
	var first := first_image.get_data()
	material.set_shader_parameter("sky_clock",5.7)
	await RenderingServer.frame_post_draw
	var second_image := viewport.get_texture().get_image()
	second_image.convert(Image.FORMAT_RGBA8)
	var second := second_image.get_data()
	var water: Array = scenery.data.water_regions[0]
	var land_top := int((float(scenery.data.get("sky_cutoff",.35))+.02)*viewport.size.y)
	var water_top := int(float(water[1])*viewport.size.y)
	var land_changes := 0
	var water_changes := 0
	for y in range(land_top,viewport.size.y-3):
		for x in range(32,viewport.size.x-32):
			var index := (y*viewport.size.x+x)*4
			var changed := first[index]!=second[index] or first[index+1]!=second[index+1] or first[index+2]!=second[index+2]
			if changed:
				if y<water_top-2: land_changes += 1
				elif y>water_top+3: water_changes += 1
	check(land_changes==0,"%s rendered reflection animation leaves all solid architecture pixels unchanged"%scenery.environment_id)
	check(water_changes>1000,"%s rendered water reflections visibly change across more than1000 pixels"%scenery.environment_id)
	viewport.queue_free()
	await process_frame

func run() -> void:
	var kinds: Dictionary = {}
	for entry: Dictionary in ScenarioCatalog.environments():
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		var scenery: ScenarioScenery = game.scenery
		await frames()
		var initial_time := scenery.elapsed
		await frames(4)
		check(scenery.elapsed>initial_time,"%s advances animation through actual scene processing"%entry.id)
		game.set_process(false)
		game.player_camera.set_process(false)
		game.camera.position=Vector2(720,450)
		game.camera.zoom=Vector2.ONE
		game.camera.force_update_scroll()
		scenery.set_process(false)
		scenery._process(0)
		var fixed_transform := scenery.panorama.transform
		var near_before := scenery.cloud_offset(1)
		var far_before := scenery.cloud_offset(0)
		var front_before := scenery.cloud_offset(2)
		var particle_before := scenery.particle_sample(0)
		scenery._process(4.0)
		var far_distance := fposmod(scenery.cloud_offset(0)-far_before,scenery.cloud_period(0))
		var near_distance := fposmod(scenery.cloud_offset(1)-near_before,scenery.cloud_period(1))
		var front_distance := fposmod(scenery.cloud_offset(2)-front_before,scenery.cloud_period(2))
		check(scenery.cloud_layers.size()==3 and far_distance>8 and near_distance>far_distance*1.8 and front_distance>near_distance*1.6,"%s has three independent cloud depths with clearly separated speeds"%entry.id)
		check(scenery.particle_sample(0).position!=particle_before.position,"%s local biome particles move independently"%entry.id)
		check(scenery.panorama.transform==fixed_transform,"%s wind and mouse parallax keep architecture fixed"%entry.id)
		var bottom: float=float(entry.get("framing_bottom",430))+64.0 if scenery.continuous_background else float(entry.get("framing_bottom",430))
		check(is_equal_approx(scenery.panorama.scale.x,scenery.panorama.scale.y) and is_equal_approx(scenery.panorama_rect.end.y,bottom),"%s preserves painted aspect ratio with a buried lower margin"%entry.id)
		var visible_view: Rect2=scenery.get_global_transform_with_canvas().affine_inverse()*root.get_visible_rect()
		var above_ground:=Rect2(visible_view.position,Vector2(visible_view.size.x,maxf(0,430-visible_view.position.y)))
		check(scenery.panorama_rect.encloses(above_ground),"%s covers the actual above-ground viewport without a side fade"%entry.id)
		var top_uv := (visible_view.position.y-scenery.panorama_rect.position.y)/scenery.panorama_rect.size.y
		var ground_uv := (430-scenery.panorama_rect.position.y)/scenery.panorama_rect.size.y
		check(top_uv<.82 and ground_uv>.82,"%s initial view includes the continuous image's landscape landmarks"%entry.id)
		check(scenery.CLOUD_OVERLAP>=400 and scenery.CLOUD_PERIOD+scenery.CLOUD_OVERLAP==scenery.CLOUD_WIDTH,"%s non-seamless cloud texture has a broad alpha overlap"%entry.id)
		var near_speed := scenery.cloud_speed(1)
		scenery.cloud_motion.reset()
		scenery.elapsed = (scenery.cloud_period(1)-410.0)/near_speed-.01
		var before_wrap := scenery.cloud_offset(1)
		scenery._process(.02)
		check(before_wrap>scenery.cloud_period(1)-1.0 and scenery.cloud_offset(1)<1.0,"%s clouds wrap through their overlapping copy"%entry.id)
		kinds[str(scenery.profile.kind)] = true
		for emitter in entry.get("smoke_anchors",[]).size():
			scenery.elapsed = 0
			var fresh := scenery.smoke_sample(emitter,0)
			scenery._process(4.0)
			var older := scenery.smoke_sample(emitter,0)
			check(fresh.position.distance_to(scenery.smoke_anchor(emitter))<1 and older.position.y<fresh.position.y and older.size>fresh.size,"%s exhaust grows upward from its fixed authored chimney"%entry.id)
		var full_count := scenery.particle_count()
		game.weather.set_reduced_effects(true)
		var before_reduced := scenery.elapsed
		scenery._process(4.0)
		check(is_equal_approx(scenery.elapsed-before_reduced,1.0) and scenery.particle_count()<=floori(full_count/2.0),"%s F3 reduces animation speed and particle density"%entry.id)
		check(is_equal_approx(float(scenery.sky_material.get_shader_parameter("water_amplitude")),.45),"%s F3 reduces reflection displacement below one texel"%entry.id)
		game.weather.set_reduced_effects(false)
		scenery.set_process(true)
		paused = true
		var paused_time := scenery.elapsed
		var paused_particle := scenery.particle_sample(0)
		await create_timer(.07,true,false,true).timeout
		check(is_equal_approx(scenery.elapsed,paused_time) and scenery.particle_sample(0)==paused_particle,"%s pause freezes clocks and particle samples"%entry.id)
		paused = false
		await frames(2)
		check(scenery.elapsed>paused_time,"%s animation resumes after pause"%entry.id)
		for field: String in ["water_regions","waterfall_regions"]:
			for region: Array in entry.get(field,[]):
				var rect := scenery.region_rect(region)
				check(scenery.panorama_rect.encloses(rect) and rect.size.x>18 and rect.size.y>8,"%s %s stays inside an authored image region"%[entry.id,field])
		if not entry.get("water_regions",[]).is_empty():
			var bounds: Vector4 = scenery.sky_material.get_shader_parameter("water_bounds")
			var water: Array = entry.water_regions[0]
			check(bounds==Vector4(float(water[0]),float(water[1]),float(water[2]),float(water[3])),"%s reflection displacement is masked to the authored water region"%entry.id)
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
			if not entry.get("water_regions",[]).is_empty():
				await check_rendered_water(scenery)
			game.notice_time = 0
			game.camera.position = game.camera_target_center
			game.camera.zoom = Vector2.ONE*game.camera_target_zoom
			scenery.set_process(false)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/scenery-motion-%s-a.png"%entry.id)
			scenery._process(8.0)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/scenery-motion-%s-b.png"%entry.id)
			# Prepared camera only: this inspects the complete late-view backdrop
			# without claiming that the bunker was expanded through gameplay.
			game.view_stage = 4
			game.update_scenario_camera()
			game.camera.position = game.camera_target_center
			game.camera.zoom = Vector2.ONE*game.camera_target_zoom
			scenery._process(0)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/scenery-motion-%s-wide.png"%entry.id)
			var wide_view: Rect2=scenery.get_global_transform_with_canvas().affine_inverse()*root.get_visible_rect()
			var wide_above:=Rect2(wide_view.position,Vector2(wide_view.size.x,maxf(0,430-wide_view.position.y)))
			check(scenery.panorama_rect.encloses(wide_above),"%s widest camera keeps the complete landscape covered"%entry.id)
		if not await preload("res://tests/scene_cleanup.gd").free_scene(game,self): failures += 1
	check(kinds.size()==9,"All nine environments have their own atmospheric identity")
	print("SCENERY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
