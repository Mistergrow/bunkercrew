extends SceneTree
## Native keyboard/controller routes through the real pause menu. A prepared
## offline match and session-role fixture never open sockets or save progress.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index=code
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func _submenus() -> void:
	for id: String in ["options","personnel","research","help","friends"]:
		var button: Button=game.hud.pause_buttons[id]
		button.grab_focus()
		await key(KEY_ENTER)
		var expected: String={"options":"audio","personnel":"personal","research":"upgrades","help":"help","friends":"friends"}[id]
		check(game.hud.overlay==expected,"Enter opens the chosen pause action: "+id)
		await joy(JOY_BUTTON_B)
		check(game.hud.overlay=="pause" and paused,"Controller Back returns to the paused shift: "+id)
		check(game.hud.pause_buttons[id].has_focus(),"Return restores the action that opened the submenu: "+id)

func _confirmation() -> void:
	for id: String in ["restart","main_menu"]:
		game.hud.pause_buttons[id].grab_focus()
		await key(KEY_ENTER)
		check(game.hud.has_session_action() and game.hud.restart_dialog.cancel_button.has_focus(),"Destructive action starts with Cancel selected: "+id)
		await key(KEY_ESCAPE)
		check(not game.hud.has_session_action() and game.hud.overlay=="pause" and paused,"Escape cancels without resuming or leaving: "+id)
		check(game.hud.pause_buttons[id].has_focus(),"Cancelling restores the original action: "+id)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(5)
	game.audio.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.story.set_process(false)
	await frames()
	var music: float=game.audio.music_volume
	var initial_stock: Dictionary=game.campaign.expedition.garage_stock.duplicate(true)
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		game.hud.overlay=""
		game.hud._apply_overlay_pause()
		await frames()
		await key(KEY_ESCAPE)
		check(game.hud.overlay=="pause" and paused,"Escape pauses the actual match: "+locale)
		check(game.hud.pause_buttons.continue_match.has_focus(),"New pauses select Continue: "+locale)
		check(not game.hud.friends_dock.visible,"Pause has one friends action with no duplicate focus target")
		var seen: Dictionary={}
		for unused in 8:
			var focus := root.gui_get_focus_owner()
			if is_instance_valid(focus): seen[focus.get_instance_id()]=true
			await joy(JOY_BUTTON_DPAD_DOWN)
		check(seen.size()==8 and game.hud.pause_buttons.continue_match.has_focus(),"Controller traverses every pause action exactly once")
		seen.clear()
		for unused in 8:
			var focus := root.gui_get_focus_owner()
			if is_instance_valid(focus): seen[focus.get_instance_id()]=true
			await key(KEY_TAB)
		check(seen.size()==8 and game.hud.pause_buttons.continue_match.has_focus(),"Tab traverses every pause action exactly once")
		await _submenus()
		await _confirmation()
		game.hud.pause_buttons.continue_match.grab_focus()
		await key(KEY_ENTER)
		check(game.hud.overlay.is_empty() and not paused,"Continue resumes the real match")
		check(is_equal_approx(game.audio.music_volume,music) and game.campaign.expedition.garage_stock==initial_stock,"Navigation preserves audio settings and saved resources")
	# Role presentation uses the actual session with processing disabled. It
	# never authenticates, joins or starts a transport, and remains paused.
	game.hud.overlay="pause"
	game.hud._apply_overlay_pause()
	await frames()
	game.network.set_process(false)
	game.network.active=true
	game.network.is_host=false
	game.network.state="playing"
	game.network.match_paused=true
	game.hud.last_overlay="!"
	await frames()
	check(game.hud.pause_buttons.restart.disabled,"An online guest cannot request a restart")
	check(game.hud._pause_action_hint("main_menu")=="Du verlässt den Online-Raum. Die übrige Crew spielt weiter.","Guest leave text describes only their own departure")
	game.hud.pause_buttons.continue_match.grab_focus()
	var guest_focus: Dictionary={}
	for unused in 7:
		var focus := root.gui_get_focus_owner()
		if is_instance_valid(focus): guest_focus[focus.get_instance_id()]=true
		await key(KEY_TAB)
	check(guest_focus.size()==7 and game.hud.pause_buttons.continue_match.has_focus(),"Guest focus traversal skips the unavailable restart")
	await key(KEY_F5)
	check(not game.hud.has_session_action(),"Guest restart shortcut cannot bypass the disabled action")
	game.network.is_host=true
	game.hud.last_overlay="!"
	await frames()
	check(not game.hud.pause_buttons.restart.disabled,"The host retains the restart action")
	check(game.hud._pause_action_hint("main_menu")=="Du beendest den Online-Raum für die gesamte Crew.","Host leave text describes ending the room for everyone")
	game.network.active=false
	check(not game.microphone.capturing,"Pause navigation never acquires the microphone")
	await Cleanup.free_scene(game,self)
	print("PAUSE NAVIGATION FOLLOWUP: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
