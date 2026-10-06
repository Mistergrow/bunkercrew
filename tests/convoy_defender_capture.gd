extends SceneTree
## Native existing gameplay artwork with two actual offline escort actors.
const Defender := preload("res://scripts/convoy_defender.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-defense-20261004/gameplay"
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("ESCORT CAPTURE %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1440,900)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.set_process(false)
	game.set_physics_process(false)
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
		player.get_node("WorkerWeapon").set_physics_process(false)
		player.global_position=Vector2(960,430)
	for _frame in 3: await physics_frame
	var vehicle := Vehicle.new()
	vehicle.game=game
	vehicle.expedition=game.expedition
	game.add_child(vehicle)
	vehicle.set_physics_process(false)
	vehicle.configure_trip(Vector2(1100,430),Vector2(740,3700),{"hp":600.0,"fuel":12.0,"cargo":{},"ammo":0,"reserve":0})
	vehicle.journey_state=Journey.new_state("driving")
	Journey.begin_breakdown(vehicle.journey_state)
	game.players[0].global_position=vehicle.service_point()+Vector2(-50,20)
	var escorts: Array[Node2D]=[]
	for index in 2:
		var escort := Defender.new()
		escort.game=game
		escort.vehicle=vehicle
		escort.character_id="branko" if index==0 else "ivo"
		escort.post_side=-1.0 if index==0 else 1.0
		vehicle.add_child(escort)
		escort.set_physics_process(false)
		escorts.append(escort)
	var enemies: Array[Node2D]=[]
	for index in 2:
		var enemy=load("res://scenes/ground_infantry.tscn").instantiate()
		enemy.game=game
		enemy.kind="rifle_guard"
		enemy.position=Vector2(750 if index==0 else 1500,430)
		enemy.attack_direction=1 if index==0 else -1
		game.add_child(enemy)
		enemy.set_physics_process(false)
		enemies.append(enemy)
	for _frame in 3: await physics_frame
	for index in 2:
		var escort=escorts[index]
		check(escort.deploy(),"Actual gameplay ground accepts escort "+str(index))
		if index==1:
			escort.target=enemies[index]
			escort.aiming=true
			escort.aim_direction=(escort._enemy_point(enemies[index])-escort._gun_origin()).normalized()
			check(escort._fire(),"Prepared real side-view hostile receives escort round "+str(index))
		else:
			check(escort.weapon_visual.visible and escort.shots_fired==0,"Waiting rear escort holds its actual rifle without firing")
		escort._update_art(0.0)
	paused=true
	game.hud._process(0.0)
	game.hud.chat_panel._process(0.0)
	game.camera.zoom=Vector2(1.5,1.5)
	game.camera.global_position=Vector2(1110,300)
	game.camera.force_update_scroll()
	game.notice_time=0
	game.hud.combat_overlay.banners.clear()
	vehicle.visual.queue_redraw()
	vehicle.queue_redraw()
	game.players[0].get_node("PixelVisual")._process(0.0)
	for _frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var picture := root.get_texture().get_image()
	check(picture.save_png(OUTPUT+"/side-view-escort.png")==OK,"Save actual rendered side-view proof")
	check(picture.get_size()==Vector2i(1440,900),"Capture preserves native viewport dimensions")
	var states: Array[Dictionary]=[]
	for escort in escorts:
		states.append({"character_id":escort.character_id,"position":[escort.global_position.x,escort.global_position.y],"hp":escort.hp,"ammo":escort.ammo,"reserve":escort.reserve,"shots_fired":escort.shots_fired,"facing":escort.facing,"actual_terrain_deploy":true,"art":"WorkerPoseArt.draw_identity_pose + WorkerLocomotion; native rifle/glove nodes"})
	var report:={"renderer":RenderingServer.get_video_adapter_name(),"prepared_state":"Actual Aschewerk main scene; vehicle at x1100 with Journey.begin_breakdown. Two real body escorts deploy onto existing road support. Rear escort holds its rifle in readiness without a target/shot; front escort fires BunkerProjectile at actual GroundInfantry. Scene paused immediately after that firing to inspect existing side-view art and attached rifle grips. This isolated actor capture does not claim campaign departure/repair integration.","resolution":[1440,900],"camera_position":[1110,300],"zoom":1.5,"file":"side-view-escort.png","escorts":states,"checks":checks,"passed":checks-failures}
	paused=false
	check(await Cleanup.free_scene(game,self),"Actual gameplay capture releases its scene and audio handles")
	report.checks=checks
	report.passed=checks-failures
	var out := FileAccess.open(OUTPUT+"/capture.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"\t"))
	out.close()
	print("ESCORT CAPTURE RESULTS %d passed, %d failed" % [checks-failures,failures])
	quit(0 if failures==0 else 1)
