extends SceneTree
## Requires a deliberately invalid manifest in the disposable copied project.
const Content := preload("res://scripts/content_registry.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--expect-invalid-content" not in OS.get_cmdline_user_args(): quit(2); return
	check(not Content.diagnostics().is_empty(),"Fixture contains a real invalid startup pack, not a mocked catalog")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var error_ui: Node = game.get_node_or_null("ContentStartupError")
	check(error_ui!=null and error_ui is CanvasLayer,"Invalid content produces a readable existing-style startup error")
	check(game.campaign==null and game.hud==null and game.audio==null and game.network==null and game.players.is_empty(),"Failed startup stops before save, audio, lobby and world services are created")
	check(not game.is_processing() and not game.is_physics_processing(),"Partially initialized game never runs logic or physics")
	if error_ui!=null:
		var detail := error_ui.find_child("ContentDiagnostics",true,false) as Label
		var close := error_ui.find_child("QuitContentError",true,false) as Button
		check(detail!=null and not detail.text.is_empty(),"Bounded content diagnostics explain the actual installation problem")
		check(close!=null and close.has_focus() and not close.disabled,"Keyboard/controller focus remains on the usable quit action")
	paused = false
	check(await Cleanup.free_scene(game,self),"Failed startup safely tears down without requiring initialized game services")
	print("CONTENT STARTUP GUARD: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
