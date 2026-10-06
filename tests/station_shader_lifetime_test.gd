extends SceneTree
## Same-frame scenario teardown must own the notifier before deferred attach.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	for path: String in ["res://scenes/station.tscn","res://scenes/glass_furnace.tscn","res://scenes/alloy_furnace.tscn","res://scenes/ammo_press.tscn"]:
		var fixture := Node2D.new()
		root.add_child(fixture)
		var station = load(path).instantiate()
		if path.ends_with("/station.tscn"): station.kind="furnace"
		fixture.add_child(station)
		station.set_process(false)
		var effects = station.get_node("MaterialEffects")
		var pending: WeakRef = weakref(effects.screen_notifier)
		check(pending.get_ref() != null and pending.get_ref().get_parent() == null,path+" prepares one pending notifier")
		fixture.remove_child(station)
		check(pending.get_ref() == null,path+" synchronous teardown releases the unowned pending notifier")
		station.queue_free()
		await process_frame
		await process_frame
		check(pending.get_ref() == null,path+" cancelled deferred attachment cannot resurrect a notifier")
		await Cleanup.free_scene(fixture,self)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.started=false # Reproduce a menu/rematch rebuild before deferred attach.
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	check(game.scenario_options.environment == "mountain_pass","Actual immediate scenario rebuild completes before deferred notifier ownership")
	check(await Cleanup.free_scene(game,self),"Actual game rebuild releases audio and all render notifiers")
	print("STATION SHADER LIFETIME: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
