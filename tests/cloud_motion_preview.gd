extends SceneTree
## Prepared matches: normal animation speed, no waves, no saved progression.
## godot --path . --fixed-fps 30 --script tests/cloud_motion_preview.gd
## -- --no-profile-save
var game
func _initialize() -> void: run.call_deferred()
func run() -> void:
	AudioServer.set_bus_mute(0,true)
	var directory := "res://artifacts/cloud-depths"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var recording := "--record" in OS.get_cmdline_user_args()
	if recording: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	root.mode = Window.MODE_FULLSCREEN
	# Native window changes arrive asynchronously from the window manager.
	# Do not record the initial 1440x900 frame as part of the QHD sequence.
	for frame in 120:
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().get_size()==DisplayServer.screen_get_size(): break
	var recorded := 0
	var worlds := PackedStringArray(["sector07","ash_foundry","frozen_rail_yard","mountain_pass"])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--worlds="): worlds = argument.trim_prefix("--worlds=").split(",")
	for environment in worlds:
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
		game.set_process(false)
		game.player_camera.set_process(false)
		game.rounds.set_process(false)
		game.rounds.running = false
		game.notice_time = 0
		game.camera.position = Vector2(720,450)
		game.camera.zoom = Vector2.ONE
		game.camera.force_update_scroll()
		for frame in 270:
			await RenderingServer.frame_post_draw
			if recording:
				root.get_texture().get_image().save_jpg(directory+"/frames/%04d.jpg"%recorded,.94)
				recorded += 1
			if frame in [0,135,269]:
				root.get_texture().get_image().save_png(directory+"/qhd-%s-%03d.png"%[environment,frame])
		if not await preload("res://tests/scene_cleanup.gd").free_scene(game,self):
			quit(1)
			return
	print("CLOUD PREVIEW: ",recorded," frames, ",root.get_texture().get_image().get_size()," pixels; fixed 30fps normal scene clocks")
	quit()
