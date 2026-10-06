extends SceneTree
## Real layouts and construction actions; camera and starting cargo are prepared.
const OUTPUT="res://artifacts/perimeter/"
var game
var view: SubViewport
var checks:=0
var failures:=0
var output:=OUTPUT
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("PERIMETER VISUAL ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames(count: int):
	for index in count: await process_frame
func site(role: String,side: int=1,ordinal: int=0):
	return game.perimeter.sites.filter(func(node):return node.role==role and node.side==side)[ordinal]
func capture(label: String):
	await frames(3)
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==Vector2i(2560,1440),label+" QHD")
	check(picture.save_png(output+label+".png")==OK,label+" saved")
func build(target,tier: int):
	var player=game.players[0]
	player.position=target.global_position-Vector2(25,0)
	while target.tier<tier:
		player.inventory=target.next_spec().cost.duplicate()
		var wanted: int=target.tier+1
		for index in 100:
			if target.tier>=wanted: break
			target.interact(player,.1)
		if target.cure>0: target._physics_process(8)
	player.position=Vector2(game.scenario_combat.core_x,430)
	target._physics_process(1)
func load_ammo(target):
	var player=game.players[0]
	player.position=target.global_position
	player.inventory={"ammo":2}
	for index in 24: target.interact(player,.1)
	player.position=Vector2(game.scenario_combat.core_x,430)
func start_layout(mode: String):
	if is_instance_valid(game):
		check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Previous layout releases before " + mode)
	game=preload("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"sector07","position":mode,"build_type":"workshop"})
	game.set_process(false)
	game.rounds.set_process(false)
	game.rounds.wave=16
	game.story.enabled=false
	game.dialogue.reset()
	game.hud.visible=false
	game.medic.set_physics_process(false)
	game.players[0].set_physics_process(false)
	game.upgrades.owned={"bunker_armor":true,"perimeter_automation":true}
	await frames(3)
	check(game.scenario_combat.position_mode==mode,"Actual layout selects " + mode)
	check(game.perimeter.sites.size()==(6 if mode=="center" else 3),mode+" site count matches active fronts")
func focus(point: Vector2,zoom: float):
	game.camera.position=point
	game.camera.zoom=Vector2.ONE*zoom
	game.camera.force_update_scroll()
func run():
	if not OS.get_environment("LASTSHIFT_PERIMETER_OUTPUT").is_empty(): output=OS.get_environment("LASTSHIFT_PERIMETER_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	var display:=TextureRect.new()
	display.texture=view.get_texture()
	display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.size=Vector2(1440,900)
	root.add_child(display)
	await start_layout("left")
	focus(Vector2(1070,374),2.4)
	build(site("fence"),1)
	await capture("left-wire-fence")
	build(site("fence"),2)
	await capture("left-concrete-fence")
	site("fence").set_physics_process(false)
	site("fence").gate_amount=.5
	site("fence").sync_replica()
	await capture("concrete-retracting")
	site("fence").gate_amount=0
	site("fence").set_physics_process(true)
	site("fence").sync_replica()
	build(site("fence"),3)
	build(site("ground"),1)
	build(site("ground",1,1),1)
	load_ammo(site("ground"))
	load_ammo(site("ground",1,1))
	await capture("left-complete-line")
	focus(site("ground").global_position-Vector2(-45,38),5.0)
	await capture("compact-gun-detail")
	focus(site("fence").global_position-Vector2(0,55),4.0)
	var player=game.players[0]
	player.position=site("fence").global_position-Vector2(115,0)
	player.set_physics_process(true)
	Input.action_press(player.action("right"))
	await frames(40)
	Input.action_release(player.action("right"))
	check(player.global_position.x>site("fence").global_position.x+55,"An actual player physically walks through the auto gate")
	player.set_physics_process(false)
	player.position=site("fence").global_position+Vector2(48,0)
	await frames(8)
	check(site("fence").gate_open and not site("fence").is_blocking(),"Passage has matching visual and collision state")
	await capture("crew-gate-open")
	player.position=Vector2(game.scenario_combat.core_x,430)
	await frames(26)
	check(site("fence").is_blocking(),"Gate returns to solid cover after passage")
	focus(Vector2(1130,376),2.2)
	var machine=preload("res://scenes/enemy.tscn").instantiate()
	machine.game=game
	machine.kind="strider"
	machine.wave=16
	machine.position=site("fence").global_position+Vector2(180,0)
	game.add_child(machine)
	machine.set_physics_process(false)
	await frames(35)
	check(site("ground").ammo<40 and site("ground",1,1).ammo<40,"Both compact autonomous guns fire through the closed barrier and consume stock")
	await capture("active-ground-defense")
	await frames(50)
	site("fence").take_damage(420)
	await capture("damaged-line")
	site("fence").take_damage(10000)
	await capture("destroyed-rebuild-site")
	site("ground").take_damage(10000)
	await capture("destroyed-gun-site")
	await start_layout("right")
	for target in game.perimeter.sites: build(target,3 if target.role=="fence" else 1)
	focus(Vector2(355,374),2.4)
	await capture("right-mirrored-line")
	await start_layout("center")
	for target in game.perimeter.sites: build(target,3 if target.role=="fence" else 1)
	focus(Vector2(720,355),.95)
	await capture("center-both-fronts")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"World preview releases cleanly")
	view.queue_free()
	display.queue_free()
	await process_frame
	print("PERIMETER VISUAL: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
