extends SceneTree
## Six seconds of the actual scene at the normal camera; waves are stopped.
## Run with --fixed-fps 30 --write-movie <path.avi> and --wind-world=<id>.
var frame := -1
var game: Node
var world_id := "iron_canyon"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--wind-world="): world_id = argument.trim_prefix("--wind-world=")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":world_id,"build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.rounds.running = false
	game.notice = ""
	game.notice_time = 0
	game.camera.position = Vector2(720,450)
	game.camera.zoom = Vector2.ONE
	await process_frame
	frame = 0

func _process(_delta: float) -> bool:
	if frame<0: return false
	frame += 1
	if frame>=180:
		print("WIND PREVIEW: ",world_id," ",game.weather.world_wind.diagnostics())
		frame = -1
		finish.call_deferred()
	return false

func finish() -> void:
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit()
