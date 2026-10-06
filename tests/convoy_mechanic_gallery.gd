extends SceneTree
## Prepared native presentation review only. Actual input, finite cargo,
## operator handover and defense are verified by the gameplay regressions.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Defender := preload("res://scripts/convoy_defender.gd")
const OUTPUT := "res://artifacts/convoy-quality-v3-20261005/mechanic/"
var game
var truck
var worker
var view: SubViewport
var baseline: GDScript
var escort_before: Node2D
var escort_after: Node2D
var records: Array[Dictionary]=[]
var failures := 0
var frames_written := 0

func _initialize() -> void: _run.call_deferred()

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func prepare(step: String, work: float, clock: float, bolts: int=0, side: float=1.0, before: bool=false) -> void:
	truck.facing=side
	truck.journey_state=Journey.new_state("repair")
	truck.journey_state.repair_step=step
	truck.journey_state.repair_operator=1
	truck.journey_state.repair_work=work
	truck.journey_state.repair_bolts=bolts
	truck.journey_state.repair_cursor=fposmod(clock/Journey.TIMING_PERIOD,1.0)
	truck.journey_state.phase_time=clock
	worker.global_position=truck.global_position+Vector2(-115*side,0)
	worker.facing=side
	worker.focus=truck
	worker._interacting=step!="done"
	truck.sync_replica()
	truck.get_node("ConvoyPresentation").update_state(0)
	truck.get_node("ConvoyPresentation").queue_redraw()
	var visual=worker.get_node("PixelVisual")
	visual._process(0)
	if before and worker._interacting:
		visual.pose_skeleton=baseline.sample(worker)
		visual.special_pose="convoy_service"
	visual.queue_redraw()
	visual.get_node("WorkerIdentity").queue_redraw()
	worker.get_node("WorkerWeapon")._update_origin()
	worker.get_node("WorkerWeapon").queue_redraw()
	game.camera.position=truck.position+Vector2(-25*side,-37)
	game.camera.zoom=Vector2.ONE*3.7
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for node in game.get_children():
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/expedition_road_art.gd":
			node.depth._update_view()
			node.queue_redraw()

func save_picture(path: String) -> void:
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	if view.get_texture().get_image().save_png(OUTPUT+path)!=OK:
		failures+=1
		push_error("Native mechanic review could not write "+path)

func prepare_escort(progress: float, before: bool) -> void:
	worker.hide()
	escort_before.visible=before
	escort_after.visible=not before
	var escort: Node2D=escort_before if before else escort_after
	escort.active=true
	escort.global_position=truck.global_position+Vector2(165,0)
	escort.facing=1
	escort.aim_direction=Vector2.RIGHT
	escort.reload_timer=Defender.RELOAD_SECONDS*(1.0-progress)
	escort._update_art(0)
	game.camera.position=truck.position+Vector2(48,-38)
	game.camera.zoom=Vector2.ONE*3.1
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--no-upnp" not in args or "--capture" not in args or DisplayServer.get_name()=="headless" or AudioServer.get_driver_name()!="Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	baseline=GDScript.new()
	baseline.source_code=FileAccess.get_file_as_string(OUTPUT+"baseline_convoy_mechanic_pose.txt")
	if baseline.reload()!=OK: quit(3); return
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.expedition.state.pending_node="harbor"
	game.expedition.state.expedition.stage="travel"
	game.expedition.ensure_road()
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	game.audio.menu_music.stop()
	game.audio.live_music.end_session()
	AudioServer.set_bus_mute(0,true)
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	freeze(truck)
	worker=game.players[0]
	worker.hurt_stun=0
	worker.get_node("WorkerWeapon").aiming=false
	var prior_defender := GDScript.new()
	prior_defender.source_code=FileAccess.get_file_as_string(OUTPUT+"baseline_convoy_defender.txt")
	if prior_defender.reload()!=OK: quit(3); return
	escort_before=prior_defender.new()
	escort_after=Defender.new()
	for escort in [escort_before,escort_after]:
		escort.game=game
		escort.vehicle=truck
		escort.character_id="branko"
		truck.add_child(escort)
		freeze(escort)
	for before in [true,false]:
		for step: String in ["jack","remove","fit","tighten","lower"]:
			worker.character_id="mara"
			prepare(step,.55,.8,2 if step=="tighten" else 3 if step=="lower" else 0,1.0,before)
			var id: String=("before-" if before else "after-")+step
			await save_picture(id+".png")
			records.append({"id":id,"file":id+".png","character":"mara","step":step,"work":.55,"clock":.8,"facing":1.0})
	for character: Dictionary in CharacterCatalog.CHARACTERS:
		worker.character_id=character.id
		prepare("tighten",.65,1.0,1)
		var id: String="identity-"+str(character.id)
		await save_picture(id+".png")
		records.append({"id":id,"file":id+".png","character":character.id,"step":"tighten","work":.65,"clock":1.0,"facing":1.0})
	worker.character_id="mara"
	prepare("fit",.6,1.2,0,-1)
	await save_picture("after-fit-mirrored.png")
	if "--sequence" in args:
		view.size=Vector2i(1280,720)
		for before in [true,false]:
			var directory: String="frames-"+("before" if before else "after")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+directory))
			var serial:=0
			for step: String in ["jack","remove","fit","tighten","lower"]:
				var duration: float=Journey.BOLT_HOLD_TIME*3 if step=="tighten" else Journey.HOLD_TIMES[step]
				for tick in ceili(duration*20):
					var clock: float=float(tick)/20.0
					var work: float=fposmod(clock,Journey.BOLT_HOLD_TIME)/Journey.BOLT_HOLD_TIME if step=="tighten" else clock/duration
					var bolts: int=mini(2,floori(clock/Journey.BOLT_HOLD_TIME)) if step=="tighten" else 3 if step=="lower" else 0
					prepare(step,work,clock,bolts,1.0,before)
					await save_picture(directory+"/frame-%04d.png"%serial)
					serial+=1
					frames_written+=1
			prepare("done",0,0,3)
			for tick in 10:
				await save_picture(directory+"/frame-%04d.png"%serial)
				serial+=1
				frames_written+=1
	view.size=Vector2i(1920,1080)
	prepare("tighten",.55,1.0,1)
	for before in [true,false]:
		for progress in [.05,.35,.48,.68,.86,1.0]:
			prepare_escort(progress,before)
			var id: String=("escort-before-" if before else "escort-after-")+str(roundi(progress*100))
			await save_picture(id+".png")
			records.append({"id":id,"file":id+".png","character":"branko","reload_progress":progress,"ammo":escort_after.ammo,"reserve":escort_after.reserve,"facing":1.0})
	if "--sequence" in args:
		view.size=Vector2i(1280,720)
		for before in [true,false]:
			var directory: String="escort-frames-"+("before" if before else "after")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+directory))
			for tick in ceili((Defender.RELOAD_SECONDS+.6)*20):
				prepare_escort(clampf((float(tick)/20.0-.2)/Defender.RELOAD_SECONDS,0,1),before)
				await save_picture(directory+"/frame-%04d.png"%tick)
				frames_written+=1
	var clean: bool=await Cleanup.free_scene(game,self)
	if not clean: failures+=1
	view.queue_free()
	await process_frame
	FileAccess.open(OUTPUT+"native-review.json",FileAccess.WRITE).store_string(JSON.stringify({"captures":records,"failures":failures,"frames":frames_written,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Prepared native single-worker Aschewerk road at physical y430. Real truck/worker rig and side-view identity; repair work and clock sampled at fixed stages solely for presentation review. Before swaps only saved previous mechanic source; hull, scene and camera identical. Silent Dummy audio, no network/profile writes. Gameplay, ownership, inventory and defense validated separately."},"\t"))
	print("CONVOY MECHANIC NATIVE REVIEW: %d images, %d video frames, %d failures"%[records.size()+1,frames_written,failures])
	quit(1 if failures else 0)
