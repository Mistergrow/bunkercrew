extends SceneTree
## Prepared post-wave20 road. Real camera, seats, wheel motion and runtime atlas.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const Journey:=preload("res://scripts/convoy_journey.gd")
const Controller:=preload("res://scripts/expedition_controller.gd")
var game
var view: SubViewport
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	root.size=Vector2i(1600,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	game.upgrades.points=30
	game.players[0].inventory={"ammo":2,"steel":4}
	check(game.expedition.on_victory(),"Prepared wave20 victory commits")
	check(game.upgrades.purchase("convoy_mg"),"Vehicle MG uses actual research")
	check(game.expedition.handle_command("prepare",{},1),"Actual garage exposes its truck")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Select harbor route through host command")
	check(game.expedition.handle_command("stop",{"id":"harbor:fuel"},1),"Select roadside depot through host command")
	check(game.expedition.handle_command("load",{"kind":"ammo","amount":2},1) and game.expedition.handle_command("load",{"kind":"steel","amount":4},1),"Finite garage cargo transfers into the actual vehicle")
	for person in game.players: person.set_physics_process(false)
	var old: int=game.get_instance_id()
	check(game.expedition.handle_command("depart",{},1),"Valid finite-fuel departure begins visible boarding")
	for person in game.players:
		person.position=game.expedition.vehicle.position+Vector2(-100+person.player_id*20,0)
		check(game.expedition.vehicle.board(person,game.expedition.vehicle.SEAT_ROLES[person.player_id-1]),"Crew uses its actual seat before countdown")
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old:
			game=current_scene
			if game.started and game.expedition.stage=="travel" and game.expedition.vehicle.journey_state.phase=="driving": break
	check(is_instance_valid(game) and game.get_instance_id()!=old and game.expedition.vehicle.journey_state.phase=="driving","Production countdown, scene handoff and engine start complete")
	print("DRIVE PREPARED ",game.get_instance_id()," old=",old," stage=",game.expedition.stage," phase=",game.expedition.vehicle.journey_state.phase," time=",game.expedition.vehicle.journey_state.phase_time," paused=",paused)
	for person in game.players: person.set_physics_process(false)
	game.expedition.vehicle.position.x=Controller.ROAD_START+(Controller.ROAD_END-Controller.ROAD_START)*Journey.BREAKDOWN_PROGRESS+.1
	deadline=Time.get_ticks_msec()+3000
	while game.expedition.vehicle.journey_state.phase!="repair" and Time.get_ticks_msec()<deadline: await process_frame
	check(game.expedition.vehicle.journey_state.phase=="repair","Actual route threshold triggers its tire mission")
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.dead: enemy.take_damage(enemy.hp+1)
	var repairer=game.players[0]
	repairer.global_position=game.expedition.vehicle.service_point()+Vector2(-48,20)
	deadline=Time.get_ticks_msec()+18000
	while game.expedition.vehicle.journey_state.phase=="repair" and Time.get_ticks_msec()<deadline:
		await physics_frame
		var state: Dictionary=game.expedition.vehicle.journey_state
		var tightening: bool=state.repair_step=="tighten"
		var timed: bool=tightening and float(state.repair_cursor)>=Journey.TIMING_START and float(state.repair_cursor)<=Journey.TIMING_END
		game.expedition.vehicle.service_action(repairer,1.0/60.0,timed,not tightening)
	check(game.expedition.vehicle.journey_state.phase=="reboarding" and game.expedition.vehicle.journey_state.repair_bolts==3,"Actual jack, wheel replacement, three timed bolts and lowering complete")
	check(game.expedition.vehicle.board(repairer,"driver"),"Driver really reboards after repair")
	deadline=Time.get_ticks_msec()+3000
	while game.expedition.vehicle.journey_state.phase!="driving" and Time.get_ticks_msec()<deadline: await process_frame
	check(game.expedition.vehicle.driving_enabled,"Reboarding and engine restart return the real crew to driving")
	game.reparent(view)
	game.expedition.set_physics_process(false)
	game.expedition.vehicle.set_physics_process(false)
	game.expedition.vehicle.position.x=2010
	game.expedition.vehicle.velocity.x=100
	game.expedition.vehicle.aim_angle=-.09
	# Moving the completed prepared scene into its capture viewport calls the
	# chassis exit hook. Restore seats through the actual boarding API there.
	for person in game.players:
		person.global_position=game.expedition.vehicle.global_position+Vector2(-100+person.player_id*20,0)
		check(game.expedition.vehicle.board(person,game.expedition.vehicle.SEAT_ROLES[person.player_id-1]),"Prepared capture viewport restores real seats after its tree relocation")
	game.expedition.vehicle.sync_replica()
	game.hud.overlay=""
	game.notice_time=0
	game.hud.combat_overlay.banners.clear()
	game.hud.combat_overlay.set_process(false)
	game.dialogue.pending.clear()
	game.dialogue.active.clear()
	game.dialogue.voice.stop()
	game.dialogue.set_process(false)
	game.expedition.progress=(2010.0-900)/2400
	game.player_camera.set_zoom(1.25)
	for unused in 8: await physics_frame
	var target: Dictionary=game.player_camera.desired_view()
	check(float(target.center.x)>game.expedition.vehicle.position.x+100,"Travel camera looks ahead of moving truck")
	game.player_camera.update_view(0,true)
	var visible:=Rect2(game.camera.position-Vector2(1600,900)/game.camera.zoom*.5,Vector2(1600,900)/game.camera.zoom)
	for worker in game.players: check(visible.has_point(worker.global_position),"Both crew fit the driving camera")
	check(game.players[0].mounted_turret==game.expedition.vehicle.driver_seat,"Driver remains seated")
	check(game.players[1].mounted_turret==game.expedition.vehicle.gunner_seat,"Gunner remains seated")
	var depot: Array=game.get_children().filter(func(n):return n.get_script()!=null and n.get_script().resource_path=="res://scripts/expedition_road_art.gd")
	check(depot.size()==1 and depot[0].get_children().filter(func(node):return node is Sprite2D).size()==8 and is_instance_valid(depot[0].depth),"Road uses eight dedicated landmark sprites and its new depth layer")
	for locale in ["de","en"]:
		LocaleText.set_locale(locale,false)
		game.expedition._sync_vehicle()
		for unused in 5: await process_frame
		# Deferred research notifications from setup must not cover this road capture.
		game.hud.combat_overlay.banners.clear()
		game.hud.combat_overlay.queue_redraw()
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		if "--capture" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/convoy-drive/regression"))
			view.get_texture().get_image().save_png("res://artifacts/convoy-drive/regression/drive-"+locale+"-2560.png")
	var wheel_before: float=game.expedition.vehicle.wheel_phase
	game.expedition.vehicle.advance_motion(.15,1)
	check(game.expedition.vehicle.wheel_phase!=wheel_before,"Wheel animation follows actual driven distance")
	game.expedition.vehicle.dismount(game.players[1])
	game.players[1].position.x=game.expedition.vehicle.position.x-570
	var shared: Dictionary=game.player_camera.desired_view()
	check(float(shared.zoom)<=1.25,"Shared local camera accommodates dismounted partner")
	await Cleanup.free_scene(game,self)
	view.queue_free()
	for unused in 3: await process_frame
	print("EXPEDITION DRIVE VIEW: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
