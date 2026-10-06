extends SceneTree
## Captures the real rendered UI. Grants points only to inspect varied tree states.
var game

func _initialize() -> void:
	run.call_deferred()

func snapshot(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/ui-%s.png" % label)

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await snapshot("menu")
	await press("start")
	game.hud.character_panel.begin_button.pressed.emit()
	await process_frame
	await snapshot("hud")
	game.players[0].add_item("steel",2)
	game.players[0].add_item("concrete",2)
	game.players[0].add_item("glass",1)
	game.players[0].add_item("limestone",1)
	await press("join")
	await snapshot("inventory")
	await press("upgrades")
	game.upgrades.add_points(12)
	game.upgrades.purchase("bunker_workshop")
	game.upgrades.purchase("boots")
	await snapshot("tech")
	game.hud.upgrade_panel._select("bunker_fortress")
	await snapshot("tech-locked")
	await press("upgrades")
	await press("audio_settings")
	await snapshot("audio")
	await press("pause")
	await press("help")
	await snapshot("help")
	await press("help")
	game.rounds.defeat()
	await snapshot("defeat")
	paused = false
	await load("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("Captured actual rendered menu, HUD, inventory, technology tree, audio, help and defeat panels")
	quit()
