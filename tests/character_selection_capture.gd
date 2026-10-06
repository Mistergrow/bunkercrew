extends SceneTree
## Captures the actual selectable cards, including their runtime worker atlases.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1440,900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud._open_character_selection(2)
	for frame in 8:
		await process_frame
	if not is_instance_valid(game.hud.character_panel) or game.hud.character_panel.cards.size()!=CharacterCatalog.CHARACTERS.size():
		push_error("Character selection failed to create all eight character choices")
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	await RenderingServer.frame_post_draw
	var directory := "res://artifacts/character-identities"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var result := root.get_texture().get_image().save_png(directory+"/selection.png")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit(0 if result==OK else 1)
