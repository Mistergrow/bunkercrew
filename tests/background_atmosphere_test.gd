extends SceneTree
## Current main-scene depth plates and the preserved legacy cloud helper.
## Rendering capture is optional. No gameplay state advances.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,message: String) -> void:
	checks+=1
	print("ATMOSPHERE %s: %s" % ["PASS" if value else "FAIL",message])
	if not value:
		failures+=1
		push_error(message)

func check_rendered_motion() -> void:
	# Render the real background at the initial camera framing. Weather, actors
	# and HUD cannot make this comparison pass by changing unrelated pixels.
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1440,900)
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sky := BackgroundAtmosphere.new()
	sky.position=Vector2(-670,-220)
	viewport.add_child(sky)
	sky.set_process(false)
	sky.elapsed=0
	sky._process(0)
	await RenderingServer.frame_post_draw
	var first := viewport.get_texture().get_image()
	first.save_png("res://artifacts/atmosphere-sky-0s.png")
	sky._process(3)
	await RenderingServer.frame_post_draw
	var second := viewport.get_texture().get_image()
	second.save_png("res://artifacts/atmosphere-sky-3s.png")
	var visible_changes := 0
	for y in range(150,310):
		for x in range(800,1400):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.03:
				visible_changes+=1
	check(visible_changes>15000,"Three seconds of background motion visibly change %d exposed sky pixels below the HUD"%visible_changes)
	var source := sky.CITY.get_image()
	var fixed_pixels := 0
	var changed_city := 0
	for y in range(345,430):
		for x in range(880,1400):
			var uv := (Vector2(x,y)-sky.position)/sky.SIZE
			var sample := Vector2i(uv*Vector2(source.get_size()))
			# Imagegen's solid city pixels have alpha 253/255, so sky motion can
			# change a composite channel by one 8-bit step without moving the city.
			if source.get_pixelv(sample).a>=253.0/255.0:
				fixed_pixels+=1
				var a := first.get_pixel(x,y)
				var b := second.get_pixel(x,y)
				if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>1.01/255.0: changed_city+=1
	check(fixed_pixels>10000 and changed_city==0,"Cloud and smoke animation preserve %d solid city pixels within their one-step alpha-compositing tolerance"%fixed_pixels)
	viewport.queue_free()
	await process_frame

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	game.rounds.set_process(false)
	var depth_plates: Node2D = game.scenery.parallax_background
	check(is_instance_valid(depth_plates) and depth_plates.layers.size()==3,"Main scene uses three independent painted depth plates")
	check(depth_plates.layers[0].texture!=depth_plates.layers[2].texture,"Moving sky and landmark geometry use different real textures")
	# The original cloud helper remains independently usable, but the current
	# Scenery extends ScenarioScenery and no longer exposes a legacy layers array.
	var atmosphere := BackgroundAtmosphere.new()
	atmosphere.game=game
	atmosphere.position=Vector2(-670,-220)
	atmosphere.visible=false
	game.add_child(atmosphere)
	atmosphere.set_process(false)
	check(atmosphere.cloud_layers.size()==3,"Preserved legacy helper builds three independent cloud layers")
	check(atmosphere.city.texture!=atmosphere.CLOUDS,"Stationary buildings and moving clouds use different real textures")
	var original_transform: Transform2D = atmosphere.city.transform
	var original_sky_position: Vector2 = atmosphere.position
	game.scenery.offset=Vector2(13,5)
	game.scenery._process(0.0)
	check(atmosphere.position==original_sky_position,"Mouse parallax leaves the entire distant skyline fixed in world space")
	atmosphere.elapsed=0
	var first_offset: float = atmosphere.cloud_offset(0)
	var second_offset: float = atmosphere.cloud_offset(1)
	atmosphere._process(10.0)
	check(atmosphere.cloud_offset(0)-first_offset>=33.0 and atmosphere.cloud_offset(0)-first_offset<=35.65 and atmosphere.cloud_offset(1)-second_offset>=135.0 and atmosphere.cloud_offset(1)-second_offset<=159.4,"Distant and near clouds advance at their configured distinct speeds")
	check(atmosphere.CLOUD_SPEEDS[0]*3.0>=9.0 and atmosphere.CLOUD_SPEEDS[1]>atmosphere.CLOUD_SPEEDS[0]*3.0 and atmosphere.CLOUD_SPEEDS[2]>atmosphere.CLOUD_SPEEDS[1]*3.0,"Both cloud depths visibly travel across the exposed sky within three seconds")
	check(atmosphere.city.transform==original_transform,"Wind does not translate, scale or rotate city buildings")
	atmosphere.cloud_motion.reset()
	atmosphere.elapsed=atmosphere.cloud_period(1)/atmosphere.CLOUD_SPEEDS[1]-0.01
	var before_wrap: float = atmosphere.cloud_offset(1)
	atmosphere._process(0.02)
	check(before_wrap>atmosphere.cloud_period(1)-1 and atmosphere.cloud_offset(1)<1,"Cloud translation wraps into the overlapping copy at the panorama boundary")
	check(atmosphere.CLOUD_PERIOD+atmosphere.CLOUD_OVERLAP==atmosphere.SIZE.x and atmosphere.CLOUD_OVERLAP>=300,"Cloud copies overlap through broad alpha ramps instead of a hard rectangular edge")
	game.set_view_stage(4)
	game.camera.position=game.camera_target_center
	game.camera.zoom=Vector2.ONE*game.camera_target_zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.scenery._process(0.0)
	var above_ground: Rect2 = game.scenery._visible_rect
	above_ground.size.y=minf(above_ground.size.y,430-above_ground.position.y)
	check(depth_plates.layer_rects.all(func(rect):return rect.encloses(above_ground)),"All current depth plates cover both edges of the actual widest expansion view")
	atmosphere.elapsed=0
	var puff: Dictionary = atmosphere.smoke_sample(2,0)
	var anchor: Vector2 = atmosphere.chimney_anchor(2)
	check(puff.position.distance_to(anchor)<1,"New smoke begins at its real chimney anchor")
	atmosphere._process(4.0)
	var grown: Dictionary = atmosphere.smoke_sample(2,0)
	check(grown.position.y<puff.position.y and grown.position.x>puff.position.x and grown.size>puff.size and grown.alpha<puff.alpha,"Smoke rises, follows the same wind as rain/flags, expands and fades")
	check(atmosphere.city.transform==original_transform,"Rising exhaust leaves chimney and building geometry fixed")
	game.weather.set_reduced_effects(true)
	var before_reduced: float = atmosphere.elapsed
	atmosphere._process(2.0)
	check(is_equal_approx(atmosphere.elapsed-before_reduced,0.7),"F3 reduces atmospheric motion using the same weather preference")
	game.weather.set_reduced_effects(false)
	atmosphere.set_process(true)
	await process_frame
	paused=true
	var before_pause: float = atmosphere.elapsed
	await create_timer(0.16,true,false,true).timeout
	check(is_equal_approx(atmosphere.elapsed,before_pause),"Pause freezes cloud drift and plume animation")
	paused=false
	check(BunkerArchitecture.REAR==load("res://assets/bunker_wall.png"),"Underground lining shares the exact upstairs rear-wall asset")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await check_rendered_motion()
		# The coverage check opened later floors. Restore the initial camera for
		# these prepared gameplay captures so the exposed sky is judged at 1:1.
		game.camera_target_center=Vector2(720,450)
		game.camera_target_zoom=1.0
		game.camera.position=game.camera_target_center
		game.camera.zoom=Vector2.ONE
		game.notice_time=0
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/atmosphere-start.png")
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/atmosphere-moving.png")
	print("ATMOSPHERE: %d passed, %d failed" % [checks-failures,failures])
	if not await preload("res://tests/scene_cleanup.gd").free_scene(game, self):
		failures += 1
	quit(1 if failures else 0)
