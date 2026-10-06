extends SceneTree
## Actual HUD and menu states at 1440x900. Gameplay captures use prepared
## workers/resources with waves stopped. The online screen opens no connection.
const DESTINATION := "res://artifacts/ui-refinement"
var game
var captures: Array[String] = []
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 6) -> void:
	for frame in count: await process_frame

func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(DESTINATION+"/"+label+".png")!=OK:
		failed = true
		push_error("Could not save "+label)
	captures.append(label)
	print("UI CAPTURE ",label)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use a graphical display and --no-profile-save")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames()
	game.hud._toggle_audio()
	await capture("audio")
	game.hud._close_audio()
	await frames()
	game.hud.overlay = "help"
	game.hud._apply_overlay_pause()
	await capture("help")
	game.hud.overlay = "menu"
	await frames()
	game.hud._open_network()
	await capture("online-lobby")
	if game.network.active or game.network.state!="offline":
		failed = true
		push_error("Opening the lobby unexpectedly activated a connection")
	game.hud.network_panel.leave_button.pressed.emit()
	await frames()
	game.selected_characters[0] = "mara"
	game.selected_characters[1] = "branko"
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.core.hp = 390
	game.players[0].position = Vector2(815,430)
	game.players[0].hp = 83
	game.players[0].inventory = {"ore":3,"steel":2}
	game.players[0].set_physics_process(false)
	game.camera.position = game.camera_target_center
	game.camera.zoom = Vector2.ONE*game.camera_target_zoom
	game.notice = ""
	game.notice_time = 0
	await capture("hud-solo")
	game.join_coop()
	game.players[1].position = Vector2(930,430)
	game.players[1].hp = 108
	game.players[1].inventory = {"sand":4,"concrete":2}
	game.players[1].set_physics_process(false)
	game.notice = ""
	game.notice_time = 0
	await capture("hud-coop")
	game.hud.overlay = "help"
	game.hud._apply_overlay_pause()
	await capture("help-in-game")
	var metadata := FileAccess.open(DESTINATION+"/hud-capture-metadata.json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"captures":captures,"size":[1440,900],"fixture":"Actual main scene. Audio, menu help and online lobby are opened before a match; no room or connection opened. Solo, local coop and in-game help use Ash Foundry, stopped wave progression, Mara/Branko at prepared positions, assigned resources and partially depleted health."},"\t"))
	paused = false
	if not await preload("res://tests/scene_cleanup.gd").free_scene(game,self): failed = true
	quit(1 if failed else 0)
