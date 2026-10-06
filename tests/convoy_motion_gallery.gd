extends SceneTree
## Native temporal art samples use a real prepared four-player road scene;
## this gallery does not claim live driving/input or campaign traversal.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const OUTPUT := "res://artifacts/convoy-experience-20261004/motion/"
var game
var truck
var presentation
var view: SubViewport
var checks:=0
var failures:=0
var captures: Array[Dictionary]=[]
var casing_pixels:=0
var rupture_pixels:=0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func capture(id: String, label: String, resolution: Vector2i=Vector2i(1920,1080)) -> void:
	view.size=resolution
	truck.sync_replica()
	presentation.queue_redraw()
	presentation.get_node("ServiceDetails").queue_redraw()
	game.camera.position=truck.position+Vector2(-20*truck.facing,-50)
	game.camera.zoom=Vector2.ONE*3.6
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for child in game.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
			child.depth._update_view()
			child.queue_redraw()
	for member in game.players:
		member.get_node("PixelVisual")._process(0.0)
		member.get_node("PixelVisual").queue_redraw()
		member.get_node("WorkerWeapon")._update_origin()
		member.get_node("WorkerWeapon").queue_redraw()
	for unused in 4: await process_frame
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==resolution and picture.save_png(OUTPUT+id+".png")==OK,"Native temporal sample "+id)
	check(truck.position==Vector2(1910,430) and truck.service_point()==truck.position+Vector2(-65*truck.facing,-20),"Presentation preserves axle/chassis/service anchors "+id)
	if id in ["mg-brass","rupture-035"]:
		var old_burst: float=presentation.burst_remaining
		var old_casings: Array[Vector4]=presentation._casings.duplicate()
		if id=="mg-brass": presentation._casings.clear()
		else: presentation.burst_remaining=0
		truck.weapon_visual.queue_redraw()
		presentation.get_node("ServiceDetails").queue_redraw()
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		var plain:=view.get_texture().get_image()
		var transform: Transform2D=truck.get_global_transform_with_canvas()
		var corner: Vector2=transform*(Vector2(-35,-95) if id=="mg-brass" else Vector2(-130,-30))
		var end: Vector2=transform*(Vector2(30,-25) if id=="mg-brass" else Vector2(-35,3))
		var changed:=0
		for y in range(maxi(0,floori(corner.y)),mini(resolution.y,ceili(end.y))):
			for x in range(maxi(0,floori(corner.x)),mini(resolution.x,ceili(end.x))):
				if picture.get_pixel(x,y)!=plain.get_pixel(x,y): changed+=1
		check(changed>8,"Actual native "+id+" transient reaches framebuffer above crew/hull")
		if id=="mg-brass": casing_pixels=changed
		else: rupture_pixels=changed
		presentation.burst_remaining=old_burst
		presentation._casings=old_casings
	captures.append({"id":id,"file":id+".png","label":label,"resolution":[resolution.x,resolution.y],"phase":truck.journey_state.phase,"phase_time":truck.journey_state.phase_time,"speed":truck.velocity.x,"pitch":presentation.body_pitch,"heave":presentation.body_heave,"burst_remaining":presentation.burst_remaining,"rubber_collapse":presentation.tyre_collapse(),"casings":presentation._casings.size(),"facing":truck.facing,"prepared_state":true})

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--capture" not in args or DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	AudioServer.set_bus_mute(0,true)
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.expedition.state.pending_node="harbor"
	game.expedition.state.expedition.stage="travel"
	game.expedition.ensure_road()
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	truck.has_mg=true
	truck.aim_angle=-.1
	for member in game.players: member.visible=false
	for seat_role in ["driver","gunner","passenger_left","passenger_right"]:
		var index: int=["driver","gunner","passenger_left","passenger_right"].find(seat_role)
		var member=game.players[index]
		member.position=truck.position
		member.visible=true
		check(truck.board(member,seat_role),"Real prepared worker occupies actual "+seat_role+" seat")
	freeze(truck)
	presentation=truck.get_node("ConvoyPresentation")
	presentation.headlight_gain=1
	truck.journey_state=Journey.new_state("driving")
	for frame in 60:
		truck.velocity.x=(frame+1)*3.0
		truck.wheel_phase+=truck.velocity.x/60/12
		presentation.update_state(1.0/60)
	await capture("load-acceleration","Beschleunigung: begrenzte Lastverlagerung, echte Radphase")
	for frame in 30:
		truck.velocity.x=180.0-(frame+1)*4.0
		truck.wheel_phase+=truck.velocity.x/60/12
		presentation.update_state(1.0/60)
	await capture("load-braking","Verzögerung: Gewicht nach vorn und Bremsleuchte")
	for frame in 240:
		truck.velocity=Vector2.ZERO
		presentation.update_state(1.0/60)
	await capture("load-settled","Stillstand: Federung ruht, keine künstliche Schaukel")
	truck.velocity.x=180
	presentation.update_state(.05)
	truck.journey_state=Journey.new_state("repair")
	truck.journey_state.repair_step="jack"
	truck.velocity=Vector2.ZERO
	presentation.update_state(0)
	var driver=truck.driver_seat.occupant
	truck.driver_seat.exit()
	driver.position=truck.position+Vector2(-115,0)
	driver.visible=true
	await capture("rupture-000","Reifenpanne 0,00 s: Hinterrad beginnt einzufallen")
	for sample in [.1,.35,.7,1.1]:
		var elapsed: float=float(truck.journey_state.phase_time)
		truck.journey_state.phase_time=sample
		presentation.update_state(sample-elapsed)
		await capture("rupture-%03d"%roundi(sample*100),"Reifenpanne %.2f s: Luft/Rubber bleiben an der Hinterachse"%sample)
	truck.journey_state=Journey.new_state("driving")
	presentation.update_state(.05)
	for unused in 3:
		truck.flash_tick+=1
		truck.flash=.06
		presentation.update_state(.13)
	truck.recoil=2.7
	truck.flash=.06
	await capture("mg-brass","MG-Feuer: tatsächlicher Schusszähler, Rückstoß und begrenzte Hülsen")
	game.weather.reduced_effects=true
	presentation.update_state(.01)
	await capture("mg-reduced","Reduzierte Effekte: MG-Blitz bleibt, Hülsen entfallen",Vector2i(1280,720))
	game.weather.reduced_effects=false
	truck.facing=-1
	truck.journey_state=Journey.new_state("driving")
	presentation.update_state(.05)
	truck.journey_state=Journey.new_state("repair")
	truck.journey_state.repair_step="jack"
	truck.journey_state.phase_time=.1
	presentation.update_state(0)
	await capture("rupture-left","Gespiegelte Reifenpanne: selbe feste Achse und Bodenkontakt",Vector2i(2560,1440))
	check(not game.network.active and not game.microphone.capturing,"Art review never opens network or microphone")
	check(AudioServer.is_bus_mute(0),"Own native capture audio stays muted")
	var adapter:=RenderingServer.get_video_adapter_name()
	check(await Cleanup.free_scene(game,self),"Native prepared road releases scene/audio resources")
	view.queue_free()
	await process_frame
	FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"casing_pixels":casing_pixels,"rupture_pixels":rupture_pixels,"captures":captures,"renderer":adapter,"fixture":"Prepared actual four-worker Aschewerk road and actual four occupied vehicle seats, camera3.6, position1910/430. Journey phase/velocity/clock and shot counter are explicitly sampled for temporal art review; original physics/input are frozen. No profile writes, sockets, microphone or audible output. This is visual proof, not live-input/campaign proof."},"  "))
	print("CONVOY MOTION GALLERY: %d/%d passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
