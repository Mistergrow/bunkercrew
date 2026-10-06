extends SceneTree
const Outskirts := preload("res://scripts/frozen_outskirts.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"frozen_rail_yard","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	game.player_camera.set_process(false)
	for frame in 4: await process_frame
	var outskirts = game.scenery.frozen_outskirts
	check(outskirts.enabled and outskirts.layers.size()==2,"Winter world loads both generated extension layers")
	for depth in 2:
		var texture: Texture2D = outskirts.textures[depth]
		check(texture!=null and Rect2(Vector2.ZERO,texture.get_size()).encloses(Outskirts.REGIONS[depth]),"Raster region is inside the imported image")
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		check(image.get_pixel(100,100).a<.05,"Generated sky is transparent")
		var fixed: Rect2 = outskirts.block_rect(depth,3)
		check(is_equal_approx(fixed.end.y,430),"Both layers join the real surface")
		var wide := Rect2(-2500,-1200,6500,3600)
		outskirts.update_view(wide)
		var span: Vector2i = outskirts.visible_blocks(depth,wide)
		check(outskirts.block_rect(depth,span.x).position.x<=wide.position.x and outskirts.block_rect(depth,span.y).end.x>=wide.end.x,"Outskirts cover both sides of the widest supported view")
		outskirts.update_view(Rect2(1300,-700,3200,1800))
		check(outskirts.block_rect(depth,3)==fixed,"Camera movement keeps scenery anchored")
		var below: Vector2i = outskirts.visible_blocks(depth,Rect2(-2500,600,6500,900))
		check(below.y<below.x,"Underground view culls outdoor decoration")
		var huge: Vector2i = outskirts.visible_blocks(depth,Rect2(-100000,-1000,200000,3000))
		check(huge.y-huge.x+1<=Outskirts.MAX_BLOCKS,"Extreme bounds preserve the draw budget")
	var material: ShaderMaterial = outskirts.layers[1].material
	check(float(material.get_shader_parameter("clear_left"))<=game.scenario_bunker.room_left-80 and float(material.get_shader_parameter("clear_right"))>=game.scenario_bunker.room_right+80,"Foreground vegetation leaves bunker and doors clear")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		root.size = Vector2i(1440,900)
		game.camera.position = Vector2(1700,390)
		game.camera.zoom = Vector2.ONE*.45
		game.notice_time = 0
		game.scenery._process(0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/frozen-outskirts-wide.png")
	await Cleanup.free_scene(game,self)
	var other := Outskirts.new()
	var fixture := Node2D.new()
	fixture.set_script(load("res://scripts/scenario_scenery.gd"))
	fixture.environment_id = "ash_foundry"
	other.configure(fixture)
	check(not other.enabled and other.layers.is_empty(),"Other biomes do not load winter decoration")
	other.free()
	fixture.free()
	print("FROZEN OUTSKIRTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
