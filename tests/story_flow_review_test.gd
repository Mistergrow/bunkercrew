extends SceneTree
## Prepared hardened prologue; real round transitions/spawns for waves 1–3.
## Enemy removal represents a won fight, not a complete combat playthrough.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("STORY FLOW %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func frames(count: int) -> void:
	for frame in count: await physics_frame
func scan() -> void:
	game.story._scan_clock=.1
	game.story._process(.001)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.hud._open_story_selection(2)
	game.hud._rebuild_buttons()
	check(game.hud.story_selected and game.hud.selection_count==2,"Story selection keeps two local players")
	game.hud.scenario_panel._toggle_story()
	check(not game.hud.story_selected,"Scenario button switches back to a free shift")
	game.hud.scenario_panel._toggle_story()
	game.hud.scenario_panel.confirm()
	game.hud._rebuild_buttons()
	game.hud.character_panel.begin_session()
	freeze(game)
	paused=false
	await frames(2)
	check(game.story_mode and game.story.enabled and game.players.size()==2,"Actual character confirmation starts the selected cooperative story")
	game.story.wall.state=DefenseWall.State.HARD
	scan()
	check(game.story.stage==1,"Prepared hardened wall releases the first defense objective")
	for wave in range(1,4):
		game.rounds.begin_warning()
		scan()
		check(game.rounds.phase=="warning" and game.rounds.wave==wave,"Normal warning begins for wave %d" % wave)
		game.rounds._process(Balance.WARNING_TIME+.1)
		scan()
		check(game.rounds.phase=="attack","Normal warning timer starts attack %d" % wave)
		for spawned in game.rounds.wave_total:
			game.rounds._process(10.0)
			for enemy in get_nodes_in_group("enemies"):
				check(enemy.wave==wave,"Actual enemy spawn belongs to wave %d" % wave)
				enemy.queue_free()
			await process_frame
		game.rounds._process(.01)
		scan()
		check(game.rounds.phase=="salvage" and game.story.stage==1,"Cleared wave %d enters salvage without unlocking its next objective early" % wave)
		game.rounds._process(Balance.SALVAGE_TIME+.1)
		if wave==3:
			var before: float=game.rounds.time_left
			game.rounds.begin_warning()
			game.rounds._process(1.0)
			check(game.rounds.phase=="build" and game.rounds.time_left==before,"Wave4 guard blocks N/timer even before the next story scan")
		scan()
	check(game.story.stage==2 and game.story.blocks_build(),"Normal third-wave completion activates and gates the antenna objective")
	var relay=game.story.relay
	relay.set_physics_process(true)
	for index in game.players.size():
		var worker=game.players[index]
		worker.position=Vector2(relay.position.x-12+index*24,430)
		worker.preferred_focus=null
		worker._update_interaction(0)
		check(game.valid_focus(worker,relay) and worker.focus==relay,"P%d default E focus reaches the active radio beside the workbench" % (index+1))
	game.players[1].medical.incapacitate()
	check(game.get_focus(game.players[0]).is_in_group("medical_targets"),"A fallen partner takes precedence over the radio objective")
	game.players[1].medical.state="healthy"
	game.players[0].inventory={"steel":2}
	relay.interact(game.players[0],.2)
	var before_pause: float=relay.progress
	paused=true
	await frames(14)
	check(relay.progress==before_pause,"Pause freezes partial radio work")
	paused=false
	relay.interact(game.players[0],.1)
	check(relay.progress>before_pause,"Resuming a held radio action preserves completed work")
	await frames(12)
	check(relay.progress==0 and game.players[0].inventory.steel==2,"Releasing radio work clears its partial channel without spending steel")
	game.players[0].configure_character("ivo")
	game.players[0].preferred_focus=relay
	Input.action_press("p1_interact")
	game.players[0]._update_interaction(.01)
	check(is_equal_approx(relay.progress,.01*game.players[0].work_multiplier()/2.0),"Ivo's work bonus still applies to antenna assembly")
	Input.action_release("p1_interact")
	game.players[0]._update_interaction(0)
	# Final send must use elapsed work time, independent of character or helpers.
	game.story.stage=6
	relay.progress=0
	for worker in game.players:
		worker.preferred_focus=relay
		worker._interaction_held=false
	Input.action_press("p1_interact")
	Input.action_press("p2_interact")
	for tick in 168:
		await physics_frame
		for worker in game.players: worker._update_interaction(1.0/60.0)
	check(game.story.stage==6 and relay.progress<.6,"Two workers including Ivo cannot finish a five-second send after 2.8 seconds")
	for tick in 133:
		await physics_frame
		for worker in game.players: worker._update_interaction(1.0/60.0)
	check(game.story.stage==7,"The shared send completes after five real unscaled work seconds")
	Input.action_release("p1_interact")
	Input.action_release("p2_interact")
	check(await Cleanup.free_scene(game,self),"Review scene and audio handles clean up")
	paused=false
	print("STORY FLOW REVIEW: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
