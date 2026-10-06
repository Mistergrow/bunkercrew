extends SceneTree
## Full production scenes on the requested renderer; all cameras remain local.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
var failures:=0
var captures:Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func frames(count:int=6) -> void:
	for frame in count: await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var driver:=RenderingServer.get_current_rendering_driver_name()
	var output:="res://artifacts/ui-camera-troops/"+driver
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var view:=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	for entry in ScenarioCatalog.environments():
		var game=load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.players[0].set_physics_process(false)
		game.notice_time=0
		for magnification in [1.25,2.1]:
			game.set_camera_zoom(magnification)
			game.player_camera.update_view(0,true)
			await frames(10)
			await RenderingServer.frame_post_draw
			var image:=view.get_texture().get_image()
			var filename:="%s-%.2f.png"%[entry.id,magnification]
			if image.get_size()!=view.size or image.save_png(output+"/"+filename)!=OK: failures+=1
			captures.append({"file":filename,"environment":entry.id,"zoom":magnification,"player":[game.players[0].position.x,game.players[0].position.y],"camera":[game.camera.position.x,game.camera.position.y]})
			print("RENDERER_CAPTURE ",driver," ",filename)
		await Cleanup.free_scene(game,self)
	view.queue_free()
	await frames()
	var file:=FileAccess.open(output+"/captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"driver":driver,"resolution":[2560,1440],"fixture":"Real nine scenarios, solo left/bastion, stopped wave/player physics, live atmosphere, local follow camera.","captures":captures,"failures":failures},"\t"))
	print("RENDERER_CAMERA_PASS ",driver," captures=",captures.size()," failures=",failures)
	quit(1 if failures else 0)
