extends SceneTree
## Real, unstarted main menu. Only presentation preview buttons are changed.
## --movie captures a six-second, 30 fps normal-time segment with --fixed-fps 30.

var game
var captures: Array[Dictionary] = []
var movie_seconds := 0.0
const DESTINATION := "res://artifacts/main-menu"

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 3) -> void:
	for frame in count:
		await process_frame

func capture(label: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(DESTINATION+"/"+label+".png")
	captures.append({"file":label+".png","window":[root.size.x,root.size.y],"rendered_viewport":[image.get_width(),image.get_height()]})
	print("MENU CAPTURE ",label," ",image.get_size(),"; actual paused main scene, no active match")

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Menu preview requires a graphical renderer and --no-profile-save")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames(8)
	if not "main_menu_panel" in game.hud or not is_instance_valid(game.hud.main_menu_panel):
		push_error("Redesigned menu did not load")
		await _finish(1)
		return
	await capture("main-menu-1440")
	if "--movie" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION+"/frames"))
		var start_seconds: float = game.hud.main_menu_panel.elapsed
		for frame in 180:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(DESTINATION+"/frames/%04d.jpg"%frame,0.92)
		movie_seconds = game.hud.main_menu_panel.elapsed-start_seconds
		print("MENU MOVIE: 180 consecutive frames; actual menu-clock duration ",movie_seconds," seconds")
	var panel = game.hud.main_menu_panel
	for index in 9:
		var world: Dictionary = ScenarioCatalog.environments()[panel.environment_index]
		await capture("world-"+str(world.id))
		panel.preview_next.pressed.emit()
		await frames(5)
	root.size = Vector2i(1280,720)
	await frames(8)
	await capture("main-menu-1280x720")
	var metadata := FileAccess.open(DESTINATION+"/capture-metadata.json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"fixture":"Actual scenes/main.tscn, paused before starting a match; only preview buttons and window size changed","captures":captures,"movie":{"frames":180 if movie_seconds>0 else 0,"menu_clock_seconds":movie_seconds,"fps":30},"widescreen":"Godot expands the logical viewport to 1600x900 in the 1280x720 window, centers the authored UI, and renders the entire 1280x720 output without letterboxing."},"\t"))
	await _finish(0)

func _finish(code: int) -> void:
	paused = false
	var clean: bool = await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit(code if clean else 1)
