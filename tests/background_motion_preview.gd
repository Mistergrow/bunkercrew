extends SceneTree
## Real normal-camera scenes; waves stopped. Clock runs normally at 30 fps.
## Record: godot --path . --fixed-fps 30 --write-movie artifacts/background-motion.avi --script tests/background_motion_preview.gd -- --no-profile-save
var game
func _initialize(): call_deferred("run")
func run():
	AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(1440,900)
	for id in ["sector07","ash_foundry"]:
		game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.rounds.running=false
		game.notice_time=0
		game.camera.position=Vector2(720,450)
		game.camera.zoom=Vector2.ONE
		for frame in 300:
			await RenderingServer.frame_post_draw
			if frame in [0,90,299]:
				root.get_texture().get_image().save_png("res://artifacts/background-visible-%s-%03d.png"%[id,frame])
			await process_frame
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("BACKGROUND MOTION: two actual normal-camera scenes, 300 frames each, waves stopped")
	quit()
