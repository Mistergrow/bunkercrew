extends SceneTree
## Prepared scenes at native desktop resolution and normal animation speed.
## --fixed-fps 30 -- --no-profile-save --record writes 360 temporary JPEGs.
const OUTPUT := "res://artifacts/water-refresh"
var game

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or not "--no-profile-save" in OS.get_cmdline_user_args():
		quit(1)
		return
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var recording := "--record" in OS.get_cmdline_user_args()
	if recording: DirAccess.make_dir_recursive_absolute("/tmp/lastshift-water-frames")
	root.mode = Window.MODE_FULLSCREEN
	for frame in 120:
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().get_size()==DisplayServer.screen_get_size(): break
	var recorded := 0
	for environment in ["abandoned_harbor","flooded_power_station"]:
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"right" if environment=="abandoned_harbor" else "left"})
		game.rounds.set_process(false)
		game.rounds.running = false
		game.notice_time = 0
		game.camera.position = Vector2(720,450)
		game.camera.zoom = Vector2.ONE
		for frame in 180:
			await RenderingServer.frame_post_draw
			if recording:
				root.get_texture().get_image().save_jpg("/tmp/lastshift-water-frames/%04d.jpg"%recorded,.94)
				recorded += 1
			if frame in [0,90,179]:
				root.get_texture().get_image().save_png(OUTPUT+"/qhd-%s-%03d.png"%[environment,frame])
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("WATER PREVIEW: ",recorded," frames; native capture ",root.get_texture().get_image().get_size(),"; normal clock at 30fps")
	quit()
