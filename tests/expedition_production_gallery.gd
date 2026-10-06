extends SceneTree
## Prepared native journey shots; all progress remains in an isolated profile.
const OUTPUT:="res://artifacts/expedition-production"
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const Journey:=preload("res://scripts/convoy_journey.gd")
var game
var view: SubViewport
var manifest: Array=[]

func _initialize() -> void: run.call_deferred()

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func prepare(environment: String,count: int=2) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(count,{"environment":environment,"position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	game.expedition.on_victory()
	game.campaign.select_destination("harbor")
	game.campaign.select_stop("harbor:fuel")
	game.campaign.begin_journey()
	game.expedition._start_road()
	game.hud.overlay=""
	# This gallery freezes the real scene immediately. Let the production HUD
	# reconcile menu controls and dock placement before its process is stopped.
	game.hud.chat_panel._process(0.0)
	game.hud._process(0.0)
	freeze(game)
	game.notice_time=0
	game.hud.combat_overlay.banners.clear()
	game.dialogue.pending.clear()
	game.dialogue.active.clear()
	game.dialogue.voice.stop()
	var truck=game.expedition.vehicle
	truck.position=Vector2(2000,430)
	truck.has_mg=true
	truck.driving_enabled=true
	truck.velocity.x=90
	truck.wheel_phase=2.4
	truck.journey_state=Journey.new_state("driving")
	truck.sync_replica()
	game.medic.hide()

func road() -> Node2D:
	for child in game.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd": return child
	return null

func shot(name: String, zoom: float, phase: String="driving", step: String="none", work: float=.5, solo: bool=false,empty: bool=false) -> void:
	var truck=game.expedition.vehicle
	truck.journey_state=Journey.new_state(phase)
	truck.journey_state.repair_step=step
	truck.journey_state.repair_work=work
	truck.journey_state.repair_bolts=2 if step=="tighten" else 3 if step in ["lower","done"] else 0
	truck.journey_state.repair_cursor=.72
	truck.journey_state.repair_operator=1 if phase=="repair" else 0
	truck.journey_state.phase_time=2.3
	truck.journey_state.solo_assist=solo
	truck.velocity.x=90 if phase=="driving" else 0
	var worker=game.players[0]
	if phase=="repair":
		truck.dismount(worker)
		worker.global_position=truck.service_point()+Vector2(-26,20)
		worker.facing=1
		worker.focus=truck
		worker._interacting=true
	else:
		worker._interacting=false
		worker.focus=null
		if empty:
			for crew in game.players:
				truck.dismount(crew)
				crew.global_position=truck.global_position-Vector2(400+crew.player_id*30,0)
		elif not is_instance_valid(worker.mounted_turret):
			worker.global_position=truck.global_position
			truck.board(worker,"driver")
	if solo:
		game.medic.show()
		game.medic.position=truck.service_point()+Vector2(-60,20)
		game.medic.facing=1
	else: game.medic.hide()
	truck.sync_replica()
	var presentation=truck.get_node("ConvoyPresentation")
	presentation.update_state(.4)
	presentation.queue_redraw()
	for actor in game.players:
		actor.get_node("PixelVisual")._process(.02)
		actor.get_node("PixelVisual").queue_redraw()
		actor.get_node("WorkerWeapon").queue_redraw()
	game.medic.queue_redraw()
	game.camera.position=truck.position+Vector2(145 if zoom<2 else 0,-190 if zoom<2 else -55)
	game.camera.zoom=Vector2.ONE*zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	road().depth._update_view()
	if game.weather.rain_base_strength>0.0:
		# Warm actual weather in the captured camera bounds, rather than leaving
		# the prepared drops over the earlier garage viewport.
		for unused in 36:
			game.weather._process(1.0/30)
			await process_frame
	game.expedition.progress=(truck.position.x-900.0)/2400.0
	game.expedition._sync_vehicle()
	game.hud.chat_panel._process(0.0)
	game.hud._process(0.0)
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path:=OUTPUT+"/"+name+".png"
	var error:=view.get_texture().get_image().save_png(path)
	manifest.append({"file":name+".png","environment":game.scenario_options.environment,"phase":phase,"step":step,"work":work,"zoom":zoom,"solo_assist":solo,"capture_error":error,"vehicle_x":truck.position.x,"wheel_phase":truck.wheel_phase,"rain_strength":game.weather.rain_strength,"reduced_effects":game.weather.reduced_effects})

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"/frames"))
	root.size=Vector2i(1600,900)
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	prepare("ash_foundry")
	await shot("road-normal",1.25)
	await shot("truck-close",3.0)
	await shot("boarding",3.0,"boarding")
	for phase in ["departure","starting","reboarding","complete","failed"]:
		await shot("phase-"+phase,1.6,phase)
	for step in ["jack","remove","fit","tighten","lower"]:
		await shot("service-"+step,3.0,"repair",step,.55)
	game.weather.set_reduced_effects(true)
	await shot("road-reduced",1.25)
	game.weather.set_reduced_effects(false)
	await shot("paused-reference",1.25)
	var pause_reference:=view.get_texture().get_image().get_data()
	paused=true
	for unused in 6: await process_frame
	await RenderingServer.frame_post_draw
	var pause_same: bool=pause_reference==view.get_texture().get_image().get_data()
	paused=false
	manifest.append({"check":"paused_pixels_stable","passed":pause_same})
	if not pause_same: push_error("Paused journey pixels unexpectedly changed")
	for frame in 24:
		var truck=game.expedition.vehicle
		truck.position.x=1770+frame*7
		truck.wheel_phase=float(frame)*.38
		await shot("frames/drive-%03d"%frame,1.6)
	await Cleanup.free_scene(game,self)
	prepare("ash_foundry",1)
	await shot("service-san",2.5,"repair","tighten",.65,true)
	await Cleanup.free_scene(game,self)
	prepare("ash_foundry",4)
	await shot("crew-four-close",3.0)
	await shot("crew-four-road",1.25)
	await shot("empty-seats",3.0,"garage","none",.5,false,true)
	await Cleanup.free_scene(game,self)
	for environment in ["mountain_pass","frozen_rail_yard"]:
		prepare(environment)
		await shot("route-"+environment,1.25)
		await Cleanup.free_scene(game,self)
	var output:=FileAccess.open(OUTPUT+"/gallery.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"fixture":"Actual wave20 victory, selected harbor fuel route, cosmetic prepared drive/service snapshots; no profile writes.","renderer":RenderingServer.get_video_adapter_name(),"captures":manifest},"\t"))
	output.close()
	view.free()
	await process_frame
	var capture_count: int=manifest.filter(func(entry):return entry.has("file")).size()
	print("EXPEDITION PRODUCTION GALLERY: %d native shots; paused pixels stable: %s"%[capture_count,str(pause_same)])
	quit(0)
