extends SceneTree
const CameraRig := preload("res://scripts/player_camera.gd")
const World := preload("res://scripts/network_world.gd")
var game
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("CAMERA %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1
func frames(count: int=4) -> void:
	for frame in count: await process_frame
func wheel(button: MouseButton) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=button
	event.factor=1
	event.pressed=true
	event.position=Vector2(850,450)
	root.push_input(event)
	await process_frame
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames()
	var initial:float=game.camera_settings().zoom
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.camera_settings().zoom==initial,"Main menu wheel cannot change the world camera")
	game.start_scenario(1,{"environment":"abandoned_harbor","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.players[0].set_physics_process(false)
	await frames()
	check(game.camera_settings().mode=="follow","New games follow the worker by default")
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.camera_settings().zoom>initial,"Real unhandled mouse wheel zooms in during gameplay")
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.camera_settings().zoom,initial),"One wheel step back restores the requested magnification")
	game.players[0].global_position=Vector2(1100,430)
	game.player_camera.update_view(1,true)
	check(game.camera.position.distance_to(Vector2(1160,335))<.1,"Follow camera tracks the worker with room to see ahead")
	var previous:Vector2=game.camera.position
	game.players[0].global_position=Vector2(650,800)
	game.player_camera.update_view(.016)
	check(game.camera.position!=previous and game.camera.position.distance_to(game.player_camera.desired_view().center)>1,"Ladder/depth movement eases instead of teleporting the camera")
	game.set_camera_zoom(100)
	check(game.camera_settings().zoom==CameraRig.MAX_ZOOM,"Wheel and options share an upper zoom bound")
	game.set_camera_zoom(-100)
	check(game.camera_settings().zoom==CameraRig.MIN_ZOOM,"Zoom cannot invert or disappear")
	game.set_camera_zoom(NAN)
	check(game.camera_settings().zoom==CameraRig.MIN_ZOOM,"Non-finite settings cannot corrupt camera transforms")
	game.reset_camera_view()
	game.hud._toggle_audio()
	await frames()
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.camera_settings().zoom==initial,"Options consume scrolling without zooming the paused world")
	game.set_camera_zoom(1.7)
	check(game.camera_settings().zoom==1.7,"Options can set a zoom while paused")
	game.hud._close_audio()
	await frames()
	game.set_camera_mode("overview")
	game.player_camera.update_view(1,true)
	check(game.camera.position.is_equal_approx(game.camera_target_center) and is_equal_approx(game.camera.zoom.x,game.camera_target_zoom),"Overview uses the current bunker framing")
	game.set_camera_mode("unknown")
	check(game.camera_settings().mode=="overview","Unknown modes are ignored")
	game.reset_camera_view()
	game.join_coop()
	game.rounds._process(0) # Round process is stopped in this fixture.
	for worker in game.players: worker.set_physics_process(false)
	game.players[0].global_position=Vector2(80,245)
	game.players[1].global_position=Vector2(1450,800)
	game.player_camera.update_view(1,true)
	for worker in game.players:
		var point:Vector2=root.get_canvas_transform()*worker.global_position
		check(root.get_visible_rect().grow(-65).has_point(point),"Shared couch camera keeps P%d inside the screen"%worker.player_id)
	var authority:=World.new()
	authority.bind(game)
	var snapshot:Dictionary=authority.capture()
	game.set_camera_zoom(1.7)
	var replica:=World.new()
	replica.bind(game)
	var accepted:bool=replica.apply(snapshot)
	check(accepted,"Valid authoritative snapshot applies: "+replica.last_error)
	replica.interpolate(.05)
	check(game.camera_settings().zoom==1.7 and game.camera_settings().mode=="follow","World replication preserves local camera preferences")
	game.network.set_process(false)
	game.network.active=true
	game.network.is_host=false
	game.network.local_player_id=2
	game.player_camera.update_view(1,true)
	check(game.player_camera.follow_players()==[game.players[1]],"Guest follows only its own player")
	check(game.camera.position.distance_to(game.players[1].global_position+Vector2(60,-95))<.1,"Frozen client simulation still supports local camera framing")
	game.players[1].position+=Vector2(60,20)
	var before:Vector2=game.camera.position
	await frames(6)
	check(game.camera.position!=before,"Guest camera continues processing after freeze_client")
	game.network.active=false
	game.network.is_host=true
	var display=game.hud.display_settings
	check(not display.restart_with_renderer("invalid"),"Renderer rejects unknown modes without quitting")
	check(not display.renderer_status().can_restart and not display.restart_with_renderer("vulkan"),"An active round cannot be lost to a renderer restart")
	var args:PackedStringArray=display.renderer_arguments("vulkan")
	check(args.has("mobile") and args.has("vulkan") and args.has("Dummy"),"Vulkan restart explicitly chooses Mobile/Vulkan and preserves silent audio")
	check(not args.has("--script") and args.has("--no-profile-save"),"Restart drops test/editor hooks and preserves no-save mode")
	var temp:=CameraRig.new()
	temp.settings_path="user://camera-regression.cfg"
	temp.mode="overview"
	temp.view_zoom=1.83
	temp.save_settings()
	var restored:=CameraRig.new()
	restored.settings_path=temp.settings_path
	restored.load_settings()
	check(restored.mode=="overview" and restored.view_zoom==1.83,"Local camera settings survive loading")
	var bad:=ConfigFile.new()
	bad.set_value("camera","mode",["follow"])
	bad.set_value("camera","zoom",NAN)
	bad.save(temp.settings_path)
	restored.load_settings()
	check(restored.mode=="overview" and restored.view_zoom==1.83,"Malformed settings leave the last valid values intact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp.settings_path))
	temp.free()
	restored.free()
	paused=false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Camera and world release cleanly")
	print("PLAYER CAMERA: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
