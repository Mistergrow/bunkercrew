extends SceneTree
## Prepared native road views compare immutable hull pixels and articulated
## service geometry. Gameplay/input transitions are covered by convoy tests.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const OUTPUT := "res://artifacts/convoy-defense-20261004/presentation/"
var game
var truck
var view: SubViewport
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var foreground_pixels := 0

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

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func capture(id: String, step: String, work: float, side: float=1.0, mechanic: bool=false, resolution: Vector2i=Vector2i(1920,1080)) -> void:
	view.size = resolution
	truck.facing = side
	truck.journey_state = Journey.new_state("repair")
	truck.journey_state.repair_step = step
	truck.journey_state.repair_work = work
	truck.journey_state.repair_bolts = 2 if step=="tighten" else 3 if step=="lower" else 0
	truck.journey_state.repair_cursor = .65
	truck.journey_state.repair_operator = 1 if mechanic else 0
	truck.journey_state.phase_time = 2.15
	var worker = game.players[0]
	worker.position = truck.position + Vector2(-114*side,0)
	worker.facing = side
	worker.focus = truck if mechanic else null
	worker._interacting = mechanic
	worker.visible = mechanic
	truck.velocity = Vector2.ZERO
	truck.wheel_phase = 2.4
	truck.suspension = 0
	truck.sync_replica()
	truck.get_node("ConvoyPresentation").update_state(0)
	truck.get_node("ConvoyPresentation").queue_redraw()
	for member in game.players:
		member.get_node("PixelVisual")._process(0.0)
		member.get_node("PixelVisual").queue_redraw()
		member.get_node("WorkerWeapon")._update_origin()
		member.get_node("WorkerWeapon").queue_redraw()
	game.camera.position = truck.position + Vector2(-24*side,-55)
	game.camera.zoom = Vector2.ONE*3.6
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for child in game.get_children():
		if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
			child.depth._update_view()
			child.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size()==resolution and picture.save_png(OUTPUT+id+".png")==OK,"Native capture "+id)
	check(truck.position==Vector2(1910,430) and truck.service_point()==truck.position+Vector2(-65*side,-20),"Drawing preserves real chassis and service anchors "+id)
	if id=="after-tighten":
		var details: Node2D=truck.get_node("ConvoyPresentation/ServiceDetails")
		details.hide()
		await frames()
		await RenderingServer.frame_post_draw
		var covered:=view.get_texture().get_image()
		var screen: Transform2D=truck.get_global_transform_with_canvas()
		var corner: Vector2=screen*Vector2(-78,-60)
		var end: Vector2=screen*Vector2(-51,-44)
		for y in range(floori(corner.y),ceili(end.y)):
			for x in range(floori(corner.x),ceili(end.x)):
				if picture.get_pixel(x,y)!=covered.get_pixel(x,y): foreground_pixels+=1
		check(foreground_pixels>100,"Native tightening timing/bolt cue actually reaches the framebuffer ahead of the painted hull")
		details.show()
		await frames()
	captures.append({"id":id,"file":id+".png","resolution":[resolution.x,resolution.y],"step":step,"work":work,"bolts":truck.journey_state.repair_bolts,"facing":side,"mechanic":mechanic,"camera_zoom":3.6,"vehicle_position":[1910,430],"prepared_state":true})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--capture" not in args or DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	view = SubViewport.new()
	view.size = Vector2i(1920,1080)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	AudioServer.set_bus_mute(0,true)
	game.selected_characters = PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.expedition.state.pending_node = "harbor"
	game.expedition.state.expedition.stage = "travel"
	game.expedition.ensure_road()
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	truck = load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game = game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	truck.has_mg = true
	truck.aim_angle = -.12
	truck.flash = .055
	truck.flash_tick = 7
	var gunner = game.players[1]
	gunner.position = truck.position
	check(truck.board(gunner,"gunner"),"Real second worker occupies actual vehicle weapon seat")
	game.players[2].position = truck.position+Vector2(-165,0)
	game.players[3].position = truck.position+Vector2(180,0)
	for index in [2,3]:
		var worker = game.players[index]
		worker.facing = -1 if index==2 else 1
		var weapon = worker.get_node("WorkerWeapon")
		weapon.aiming = true
		weapon.aim_direction = Vector2(worker.facing,0)
		weapon._aim_hold = 1.0
	freeze(truck)
	truck.get_node("ConvoyPresentation").headlight_gain = 1
	if "--before-only" in args:
		for step in ["jack","remove","tighten"]:
			await capture("before-"+step,step,.55)
	else:
		for step in ["jack","remove","fit","tighten","lower"]:
			await capture("after-"+step,step,.55)
		await capture("after-jack-flat","jack",0.0)
		await capture("after-remove-ground","remove",1.0)
		await capture("after-fit-ground","fit",0.0)
		await capture("after-tighten-left","tighten",.55,-1.0)
		await capture("after-mechanic-defense","tighten",.65,1.0,true)
		await capture("after-720p","jack",.55,1.0,true,Vector2i(1280,720))
		await capture("after-qhd","tighten",.55,1.0,true,Vector2i(2560,1440))
	check(not game.network.active and not game.microphone.capturing,"Native gallery keeps sockets and microphone closed")
	check(AudioServer.is_bus_mute(0),"Native gallery keeps its own output muted")
	check(await Cleanup.free_scene(game,self),"Native gallery releases actual scene and audio handles")
	view.queue_free()
	await process_frame
	var suffix := "before" if "--before-only" in args else "after"
	FileAccess.open(OUTPUT+"gallery-"+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"foreground_timing_pixels":foreground_pixels,"captures":captures,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Prepared real four-worker ash_foundry road at physical y430; actual vehicle, service anchors and second-worker gunner seat. Journey fields and weapon flash are fixed solely for art review; waves/process held. Independent native SubViewport, small off-screen host window, no profile writes, sockets or mic, master muted. Input/defense gameplay is verified separately."},"  "))
	print("CONVOY REPAIR ART GALLERY: %d/%d passed; %d captures" % [checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
