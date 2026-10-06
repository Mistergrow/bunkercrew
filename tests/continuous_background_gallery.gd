extends SceneTree
## Prepared solo scenes with a frozen camera; captures both normal and wide zoom.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/backgrounds-v3/"
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	LocaleText.set_locale("de",false)
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"center"})
		game.rounds.set_process(false)
		game.set_process(false)
		game.notice_time = 0
		for index in 4: await physics_frame
		for zoom in [1.0,.45]:
			game.camera.zoom = Vector2.ONE*zoom
			game.camera.position = Vector2(720,450)
			game.camera.force_update_scroll()
			game.scenery._process(0)
			for index in 3: await process_frame
			var view: Rect2 = game.scenery.get_global_transform_with_canvas().affine_inverse()*root.get_visible_rect()
			var above := Rect2(view.position,Vector2(view.size.x,maxf(0,430-view.position.y)))
			if not game.scenery.panorama_rect.encloses(above):
				failures += 1
				push_error(entry.id+" camera exposes a panorama edge")
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT+entry.id+("-normal" if zoom==1.0 else "-wide")+".png")
		await Cleanup.free_scene(game,self)
	print("CONTINUOUS BACKGROUNDS: thirteen locations, two camera views, %d failures"%failures)
	quit(1 if failures else 0)
