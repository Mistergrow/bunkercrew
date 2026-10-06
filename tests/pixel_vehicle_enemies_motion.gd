extends "res://tests/pixel_vehicle_enemies_gallery.gd"
## Matched, sampled native motion sequences. Authority is frozen and explicit
## clocks advance at 30 fps. Movies are therefore presentation review footage.
const FPS := 30
var sequences: Array[Dictionary] = []

func _frame(id: String, frame: int, state: Dictionary) -> void:
	for unused in 2: await process_frame
	await RenderingServer.frame_post_draw
	var filename:="motion/%s/%04d.png"%[id,frame]
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==Vector2i(1440,900) and picture.save_png(OUTPUT+phase+"/"+filename)==OK,"Actual native motion frame "+filename)
	sequences.append({"file":filename,"frame":frame,"sample_time":float(frame)/FPS,"state":state,"prepared_state":true})

func _motion_guns() -> void:
	plate=Plate.new()
	plate.caption="Anticipation / actual shot mouth / recoil recovery / explicitly sampled 30 fps"
	view.add_child(plate)
	actors.clear()
	var kinds: Array[String]=["scout_car","mortar_carrier","battle_tank","gunship","pulse_fighter","sky_fortress","bomber"]
	for index in kinds.size():
		actors.append(_make_actor(kinds[index],Vector2(230+index*440,354) if index<3 else Vector2(180+(index-3)*360,672),-1))
	for frame in 78:
		var seconds:=float(frame)/FPS
		var states: Array[Dictionary]=[]
		for actor in actors:
			var flying:=AirEnemyCatalog.is_air(actor.kind)
			var shot_time:=float(actor.profile.windup)
			var age:=seconds-shot_time
			var duration:=.22 if actor.kind=="sky_fortress" else (.10 if flying else .13)
			actor.windup=minf(seconds,shot_time) if age<0 else 0.0
			actor.muzzle_flash=maxf(0,duration-age) if age>=0 else 0.0
			actor.attack_count=7 if age>=0 else 6
			actor.weapon_recoil=2*exp(-maxf(0,age)*18) if age>=0 else 0.0
			actor.age=1.17+seconds
			if flying:
				actor.flight_presentation.clock=actor.age
				actor.burst_remaining=1 if actor.kind=="bomber" and age>=0 and age<.20 else 0
			actor._pose_parts()
			for child in actor.get_children():
				if child is CanvasItem: child.queue_redraw()
			states.append({"id":actor.kind,"windup":actor.windup,"remaining_flash":actor.muzzle_flash,"shot_time":shot_time,"recoil":actor.weapon_recoil})
		await _frame("weapons",frame,{"actors":states})
	check(await Cleanup.free_scene(plate,self),"Motion weapon rigs release delegates")
	plate=null
	actors.clear()

func _motion_road() -> void:
	await _prepare_road(1,false)
	game.camera.zoom=Vector2.ONE*ZOOM
	game.camera.position=truck.position+Vector2(70,-140)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for child in game.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
			child.depth._update_view()
			child.queue_redraw()
	var presentation=truck.get_node("ConvoyPresentation")
	presentation._casings.clear()
	truck.journey_state=Journey.new_state("driving")
	truck.hp=180.0
	truck.velocity.x=60
	truck.animation_time=2.17
	truck.flash_tick=0
	truck.flash=0
	presentation.update_state(0)
	for frame in 60:
		var seconds:=float(frame)/FPS
		truck.animation_time=2.17+seconds
		truck.wheel_phase=1.25+seconds*60/12
		var fired:=frame in [6,12,18,24,30]
		if fired:
			truck.flash_tick+=1
			truck.flash=.075
			truck.recoil=2.7
		else:
			truck.flash=maxf(0,truck.flash-1.0/FPS)
			truck.recoil=WeaponEffectArt.recover_recoil(truck.recoil,1.0/FPS)
		truck.sync_replica()
		presentation.update_state(1.0/FPS)
		for worker in game.players:
			worker.get_node("PixelVisual")._process(0)
			worker.get_node("PixelVisual").queue_redraw()
		await _frame("convoy",frame,{"speed":60,"zoom":ZOOM,"hp":truck.hp,"flash":truck.flash,"wheel_phase":truck.wheel_phase,"casings":presentation._casings.size(),"crew":4})
		check(presentation._casings.size()<=5 and truck.ammo==40 and truck.fuel==12 and truck.position==Vector2(1910,430),"Motion feedback keeps original finite budget/authority")
	check(await Cleanup.free_scene(game,self),"Motion road releases scene/audio handles")
	game=null
	truck=null

func _motion_wrecks() -> void:
	plate=Plate.new()
	plate.caption="Detached exact rigs / three material families / finite aftermath / 30 fps"
	view.add_child(plate)
	var kinds: Array[String]=["strider","battle_tank","gunship"]
	for index in 6:
		var actor:=_make_actor(kinds[index%3],Vector2(245+(index%3)*455,360 if index<3 else 675),-1 if index<3 else 1)
		var wreck:=Wreck.spawn(actor,actor.kind,index%3==2)
		freeze(wreck)
		wrecks.append(wreck)
		actor.free()
	for frame in 60:
		var states: Array[Dictionary]=[]
		for wreck in wrecks:
			if not is_instance_valid(wreck) or wreck.is_queued_for_deletion(): continue
			wreck._process(1.0/FPS)
			states.append({"id":wreck.identity,"elapsed":wreck.elapsed,"duration":wreck.duration,"mirror":wreck.mirror})
		await _frame("wrecks",frame,{"wrecks":states})
	check(get_nodes_in_group("enemy_motion_wrecks").is_empty(),"Every original wreck expires within unchanged class lifetime")
	check(await Cleanup.free_scene(plate,self),"Motion aftermath releases delegate rigs")
	plate=null
	wrecks.clear()

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--capture" not in args or DisplayServer.get_name()=="headless": quit(2); return
	for argument in args:
		if argument.begins_with("--phase="): phase=argument.trim_prefix("--phase=")
	if phase not in ["baseline","final"]: quit(2); return
	for id in ["weapons","convoy","wrecks"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+phase+"/motion/"+id))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await _motion_guns()
	await _motion_road()
	await _motion_wrecks()
	view.queue_free()
	await process_frame
	var report: Dictionary={"checks":checks,"passed":checks-failures,"failures":failures,"phase":phase,"fps":FPS,"resolution":[1440,900],"frames":sequences,"fixture":"Original clock durations/mouths/recoil and capped casing/wreck lists; intentionally prepared frozen rigs, exact native render at normal zoom1.25. Wreck expiration real process lifecycle, no real combat authority/input claim."}
	FileAccess.open(OUTPUT+phase+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PIXEL VEHICLE ENEMIES MOTION: %d/%d passed; %d native frames"%[checks-failures,checks,sequences.size()])
	quit(1 if failures else 0)
