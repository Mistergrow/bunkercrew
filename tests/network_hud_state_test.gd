extends SceneTree
## Full HUD/session integration with an arranged active host; no socket opens.
var game
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func frames(count: int=2) -> void:
	for frame in count: await process_frame
func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start(2)
	game.rounds.running = false
	game.network.active = true
	game.network.is_host = true
	game.network.local_player_id = 1
	game.network.state = "playing"
	game.hud._toggle_personnel()
	await frames()
	check(game.hud.overlay=="personal" and not paused,"Online personal menu leaves the simulation running")
	game.network.pause_match(true)
	check(paused and game.hud.overlay=="personal","Shared pause preserves the currently inspected local menu")
	game.hud._close_personnel()
	check(paused and game.hud.overlay=="pause","Closing a local menu shows a pause received while it was open")
	game.hud._toggle_personnel()
	await frames()
	game.network.pause_match(false)
	check(not paused and game.hud.overlay=="personal","Partner resume restarts simulation while local menu stays open")
	game.hud._close_personnel()
	check(not paused and game.hud.overlay.is_empty(),"Closing a menu does not restore an obsolete pause screen")
	game.hud._toggle_audio()
	await frames()
	check(game.hud.overlay=="audio" and not paused,"Online audio menu also stays local")
	game.network.pause_match(true)
	game.hud._close_audio()
	check(paused and game.hud.overlay=="pause","Audio menu returns to the current shared pause")
	game.network.pause_match(false)
	game.hud._toggle_personnel()
	await frames()
	var panel = game.hud.personal_panel
	game.players[0].progression.skill_points = 1
	game.players[1].progression.skill_points = 1
	panel.select_player(1)
	panel.purchase("combat")
	check(game.players[1].progression.skills.combat==0 and game.players[1].progression.skill_points==1,"Online host cannot spend the guest's personal skill point through UI")
	panel.select_player(0)
	panel.purchase("combat")
	check(game.players[0].progression.skills.combat==1 and game.players[0].progression.skill_points==0,"Host's own UI purchase routes through the real authoritative session")
	game.network.state = "error"
	game.network.error_message = "Verbindung für diesen Test beendet."
	game.hud._process(0)
	await frames()
	check(game.hud.overlay=="network" and is_instance_valid(game.hud.network_panel),"A failed live session displays connection state")
	var lobby = game.hud.network_panel
	check(not lobby.create_button.visible and not lobby.join_button.visible,"An ended live connection cannot create a new room over its stale game world")
	lobby._host()
	check(game.network.transport==null and game.network.state=="error","Stale focused create action cannot reopen a socket after a live-session failure")
	game.network.leave()
	paused = false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Arranged session and actual main scene release cleanly")
	print("NETWORK HUD STATE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
