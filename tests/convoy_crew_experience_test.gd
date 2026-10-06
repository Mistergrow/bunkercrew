extends SceneTree
## Prepared four-person road scene. Shots and reloads use actual held actions,
## finite weapons and physical targets; pose sweeps do not claim live input.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const OUTPUT := "res://artifacts/convoy-experience-20261004/crew"
var game
var truck
var view: SubViewport
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var evidence: Dictionary = {}
var capture_enabled := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func pose_for(worker: Node2D, pitch: float, kick: float, progress: float=-1.0) -> Dictionary:
	var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
	weapon.aim_direction=Vector2(worker.facing*cos(pitch),sin(pitch))
	weapon.aiming=true
	weapon.recoil=kick
	weapon.reload_timer=weapon.reload_duration(weapon.weapon_kind)*(1.0-progress) if progress>=0 else 0.0
	weapon._update_origin()
	var visual: WorkerVisual=worker.get_node("PixelVisual")
	visual._process(0)
	return visual.pose_skeleton

func glove_pixels(people: Array, picture: Image, label: String) -> void:
	var poses: Array[Dictionary]=[]
	for person in people:
		var visual: WorkerVisual=person.get_node("PixelVisual")
		poses.append(visual.pose_skeleton.duplicate(true))
		# Only the existing weapon helper consults these live targets. The body
		# has already submitted its cached draw commands and is not redrawn.
		visual.pose_skeleton={}
		person.get_node("WorkerWeapon").queue_redraw()
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var without_gloves:=view.get_texture().get_image()
	var measured: Array[int]=[]
	for person in people:
		var weapon: WorkerWeapon=person.get_node("WorkerWeapon")
		var transform:=weapon.get_global_transform_with_canvas()
		var corner:=transform*Vector2(-34,-36)
		var end:=transform*Vector2(45,36)
		var changed:=0
		for y in range(maxi(0,floori(corner.y)),mini(picture.get_height(),ceili(end.y))):
			for x in range(maxi(0,floori(corner.x)),mini(picture.get_width(),ceili(end.x))):
				if picture.get_pixel(x,y)!=without_gloves.get_pixel(x,y): changed+=1
		measured.append(changed)
	check(measured.all(func(count):return count>10),"Existing native glove overlay reaches framebuffer for "+label)
	evidence[label+"_glove_pixels"]=measured
	for index in people.size():
		people[index].get_node("PixelVisual").pose_skeleton=poses[index]
		people[index].get_node("WorkerWeapon").queue_redraw()
	for unused in 3: await process_frame

func capture(id: String, state: String) -> void:
	if not capture_enabled: return
	# Observe the actual fire serial before pausing; the production presenter
	# intentionally rejects updates while paused and must not invent a casing.
	truck.get_node("ConvoyPresentation").update_state(0)
	paused=true
	truck.sync_replica()
	truck.get_node("ConvoyPresentation").update_state(0)
	truck.get_node("ConvoyPresentation").queue_redraw()
	for worker in game.players:
		worker.get_node("PixelVisual")._process(0)
		worker.get_node("PixelVisual").queue_redraw()
		worker.get_node("WorkerWeapon").queue_redraw()
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.save_png(OUTPUT+"/"+id+".png")==OK,"Native crew frame "+id)
	var presenter: Node2D=truck.get_node("ConvoyPresentation")
	if id=="crew-real-shot": await glove_pixels(game.players.slice(2),picture,"mounted_personal")
	elif id=="crew-ground-grip": await glove_pixels([game.players[1]],picture,"standing_personal")
	if id=="crew-real-shot":
		var actual_casings: Array[Vector4]=presenter._casings.duplicate()
		check(not actual_casings.is_empty(),"Actual fire serial produces a casing before capture pause")
		presenter._casings.clear()
		truck.weapon_visual.queue_redraw()
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		var plain:=view.get_texture().get_image()
		var transform: Transform2D=truck.get_global_transform_with_canvas()
		var corner:=transform*Vector2(-35,-95)
		var end:=transform*Vector2(60,-35)
		var changed:=0
		for y in range(maxi(0,floori(corner.y)),mini(picture.get_height(),ceili(end.y))):
			for x in range(maxi(0,floori(corner.x)),mini(picture.get_width(),ceili(end.x))):
				if picture.get_pixel(x,y)!=plain.get_pixel(x,y): changed+=1
		check(changed>2,"Actual single-shot brass reaches native framebuffer ahead of four riding bodies")
		evidence.mg_casing_pixels=changed
		presenter._casings=actual_casings
		var actual_flash: float=truck.flash
		truck.flash=0
		truck.weapon_visual.queue_redraw()
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		var without_flash:=view.get_texture().get_image()
		var flash_pixels:=0
		for y in range(maxi(0,floori(corner.y)),mini(picture.get_height(),ceili(end.y))):
			for x in range(maxi(0,floori(corner.x)),mini(picture.get_width(),ceili(end.x))):
				if picture.get_pixel(x,y)!=without_flash.get_pixel(x,y): flash_pixels+=1
		check(flash_pixels>20,"Actual MG muzzle flash remains visible when aimed down past front rider helmet")
		evidence.mg_flash_pixels=flash_pixels
		truck.flash=actual_flash
		truck.weapon_visual.queue_redraw()
	captures.append({"id":id,"state":state,"file":id+".png","mg_rounds":truck.ammo,"mg_flash_serial":truck.flash_tick,"mg_flash":truck.flash,"mg_casings":presenter._casings.size(),"rifle_rounds":game.players.slice(2).map(func(worker):return worker.get_node("WorkerWeapon").current_ammo()),"reload_timers":game.players.slice(2).map(func(worker):return worker.get_node("WorkerWeapon").reload_timer)})
	paused=false

func spawn_target(x: float) -> Node2D:
	var target: Node2D=load("res://scripts/ground_infantry.gd").new()
	target.game=game
	target.kind="rifle_guard"
	target.position=Vector2(x,430)
	game.add_child(target)
	freeze(target)
	target._pose_parts()
	return target

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--no-upnp" not in args or AudioServer.get_driver_name()!="Dummy": quit(2); return
	capture_enabled="--capture" in args and DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.expedition.state.pending_node="harbor"
	game.expedition.state.expedition.stage="travel"
	game.expedition.ensure_road()
	await physics_frame
	freeze(game)
	game.hud.hide()
	game.audio.menu_music.stop()
	game.audio.live_music.end_session()
	AudioServer.set_bus_mute(0,true)
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":40,"cargo":{"steel":4}})
	truck.has_mg=true
	truck.driving_enabled=false
	truck.set_physics_process(false)
	truck.set_process(false)
	for worker in game.players:
		worker.position=truck.position
		check(truck.board_any(worker),"Actual crew P%d takes one distinct seat"%worker.player_id)
	check(truck.z_index+truck.weapon_visual.z_index>game.players[1].z_index,"Actual MG layer stays ahead of riding worker bodies and helmets")
	game.camera.position=truck.position+Vector2(0,-65)
	game.camera.zoom=Vector2.ONE*3.1
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await physics_frame
	var stable_feet: Array=[]
	var max_reach:=0.0
	var max_grip_error:=0.0
	var reload_excursion:=0.0
	for side in [1.0,-1.0]:
		truck.facing=side
		truck.sync_replica()
		for worker in game.players.slice(2):
			worker.facing=side
			var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
			var total:=weapon.total_ammunition()
			stable_feet=pose_for(worker,0,0).feet.duplicate()
			for pitch in [-1.1,-.55,0.0,.55,1.05]:
				for kick in [0.0,3.5,6.0]:
					var pose:=pose_for(worker,pitch,kick)
					var body:=PoseArt.torso_transform(pose)
					var grip_ok:=true
					var reachable:=true
					var direction:=Vector2(weapon.aim_direction)*Vector2(worker.facing,1)
					for hand in 2:
						var expected: Vector2=Vector2(10,-30)+direction*((13.0 if hand==0 else -2.0)-kick)
						var error:=Vector2(pose.hands[hand]).distance_to(expected)
						var reach: float=(body*Vector2(-6 if hand==0 else 3,0)).distance_to(pose.hands[hand])
						max_grip_error=maxf(max_grip_error,error)
						max_reach=maxf(max_reach,reach)
						grip_ok=grip_ok and error<.001
						reachable=reachable and reach<=22.9
					check(grip_ok and reachable and pose.feet==stable_feet,"Both mounted gloves follow recoiling rifle with reachable arms, grounded feet and mirror")
			var resting: Array=pose_for(worker,.35,0).hands.duplicate()
			for progress in [.0,.25,.5,.75,.99]:
				var pose:=pose_for(worker,.35,0,progress)
				reload_excursion=maxf(reload_excursion,Vector2(pose.hands[1]).distance_to(resting[1]))
				var body:=PoseArt.torso_transform(pose)
				check((body*Vector2(3,0)).distance_to(pose.hands[1])<=22.9 and pose.feet==stable_feet,"Real mounted reload reaches ammunition pouch without detached hand or sliding feet")
			check(weapon.total_ammunition()==total,"Visual pose sampling neither consumes nor creates ammunition")
	check(reload_excursion>12,"Personal reload visibly leaves receiver for ammunition pouch")
	evidence.pose_sweep={"max_arm_reach":max_reach,"max_rifle_grip_error":max_grip_error,"reload_excursion":reload_excursion}
	truck.facing=1
	truck.aim_angle=0
	truck.sync_replica()
	for worker in game.players.slice(2):
		worker.facing=-1 if worker.player_id==3 else 1
		var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
		weapon.cancel_actions()
		weapon.recoil=0
		weapon.cooldown=0
		weapon.set_physics_process(true)
	truck.set_process(true)
	truck.set_physics_process(true)
	var rear:=spawn_target(1640)
	var front:=spawn_target(2180)
	var truck_hp: float=truck.hp
	var personal_before: Array=game.players.slice(2).map(func(worker):return worker.get_node("WorkerWeapon").total_ammunition())
	for id in [2,3,4]: Input.action_press("p%d_aim_down"%id)
	for unused in 10: await physics_frame
	for id in [2,3,4]: Input.action_release("p%d_aim_down"%id)
	await capture("crew-ready","Actual finite crew seats; aim adjusted by real held action, no shot yet")
	for id in [2,3,4]: Input.action_press("p%d_fire"%id)
	var deadline:=Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<deadline and (truck.flash_tick<1 or game.players[2].get_node("WorkerWeapon")._shot_index<1 or game.players[3].get_node("WorkerWeapon")._shot_index<1): await physics_frame
	for id in [2,3,4]: Input.action_release("p%d_fire"%id)
	check(truck.flash_tick>0 and truck.ammo<40,"Actual gunner action fires finite MG and drives its presentation serial")
	check(game.players.slice(2).all(func(worker):return worker.get_node("WorkerWeapon")._shot_index>0),"Both separate passenger fire actions launch actual rifles")
	await capture("crew-real-shot","Actual first rifle and MG input shot; recoil, muzzle and gloves refreshed from unchanged live state")
	for unused in 25: await physics_frame
	check(rear.hp<rear.max_hp and front.hp<front.max_hp,"Actual rear and front defense rounds collide with opposing native infantry")
	check(truck.hp==truck_hp and game.players.all(func(worker):return worker.hp==worker.max_hp),"Mounted friendly fire clears own chassis and real crew")
	await capture("crew-recovered","Actual recoil recovered after 25 physics frames; earlier rounds remain spent")
	for id in [2,3,4]: Input.action_press("p%d_reload"%id)
	await physics_frame
	await physics_frame
	for id in [2,3,4]: Input.action_release("p%d_reload"%id)
	check(truck.reload_timer>0 and game.players.slice(2).all(func(worker):return worker.get_node("WorkerWeapon").reload_timer>0),"Actual simultaneous reload actions keep MG and each personal weapon independent")
	for unused in 17: await physics_frame
	await capture("crew-reload-fetch","Actual reload after 17 physics frames: support hand holds rifle while free hand fetches ammunition")
	for unused in 22: await physics_frame
	await capture("crew-reload-seat","Actual reload after another 22 physics frames: ammunition returns to receiver")
	for unused in 70: await physics_frame
	check(truck.reload_timer==0 and truck.ammo==40 and truck.reserve<40,"MG actual reload finishes from finite separate convoy reserve")
	for index in 2:
		var weapon: WorkerWeapon=game.players[index+2].get_node("WorkerWeapon")
		check(weapon.reload_timer==0 and weapon.total_ammunition()<int(personal_before[index]) and weapon.current_ammo()==weapon.magazine_size(),"Passenger reload finishes from its own finite personal reserve")
	await capture("crew-reload-finished","Actual independent finite reloads completed; hands return to controls")
	evidence.combat={"mg_shots":truck.flash_tick,"mg_ammo":truck.ammo,"mg_reserve":truck.reserve,"rear_hp":rear.hp,"front_hp":front.hp,"personal_before":personal_before,"personal_after":game.players.slice(2).map(func(worker):return worker.get_node("WorkerWeapon").total_ammunition()),"network_active":game.network.active,"vehicle_hp":truck.hp}
	var grounded: Node2D=game.players[1]
	check(truck.dismount(grounded),"Actual former MG operator can resume independent ground weapon use")
	grounded.position=Vector2(1730,430)
	grounded.facing=-1
	var ground_weapon: WorkerWeapon=grounded.get_node("WorkerWeapon")
	ground_weapon.set_physics_process(true)
	Input.action_press("p2_fire")
	await physics_frame
	await physics_frame
	Input.action_release("p2_fire")
	grounded.get_node("PixelVisual")._process(0)
	var ground_visual: WorkerVisual=grounded.get_node("PixelVisual")
	check(not ground_visual.pose_skeleton.is_empty() and not ground_visual.locomotion_pose.is_empty() and not ground_visual.weapon_pose().is_empty(),"Normal ground rifle retains original locomotion and weapon-pose overlay guards")
	await capture("crew-ground-grip","Actual former gunner dismounts; existing ground-rifle helper retains glove overlay after normal input fire")
	check(not game.network.active and not game.microphone.capturing,"Local native review keeps network and microphone closed")
	check(await Cleanup.free_scene(game,self),"Actual road crew, weapons, convoy and audio clean up")
	view.queue_free()
	await process_frame
	FileAccess.open(OUTPUT+("/native-crew.json" if capture_enabled else "/crew-regression.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"captures":captures,"evidence":evidence,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Actual main-scene four local workers in independent world. Prepared fixed Aschewerk road, finite truck/MG/rounds and stationary native enemy targets. Pose-angle sweep is controlled; firing, damage, recoil recovery and reload captures use actual held P2/P3/P4 action processing. No timeline, damage, ammo or flash overrides in live combat stage. Own off-screen rendering window, Dummy audio, no network/profile writes."},"\t"))
	print("CONVOY CREW EXPERIENCE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
