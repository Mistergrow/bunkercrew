extends SceneTree
## The open session confirmation shares menu controls without exposing the
## paused actions beneath it. Session roles below are socket-free UI fixtures.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0
var _lobby_focus_events := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int=3) -> void:
	for unused in count: await process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func click(at: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func check_presentation(panel: Control,context: String) -> void:
	check(panel.cancel_button.has_focus(),"Cancel is selected on opening: "+context)
	check(panel.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Confirmation keeps the menu pixel sampling: "+context)
	check(Rect2(panel.blocker.position,panel.blocker.size)==game.hud.screen_rect(),"Modal intercepts the complete visible screen: "+context)
	for button: Button in [panel.confirm_button,panel.cancel_button]:
		var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
		check(is_zero_approx(normal.bg_color.a) and normal.get_border_width(SIDE_LEFT)==0 and normal.get_border_width(SIDE_TOP)==0,"Session actions use transparent menu surfaces: "+context)
		check(button.get_theme_font("font")==UiArt.MENU_FONT and button.icon!=null,"Session actions share lobby typography and original glyphs: "+context)
		var text_width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		check(text_width+button.icon.get_width()+32<=button.size.x,"Localized session action remains readable: "+context)
	for entry: Array in [[panel.heading,36,UiArt.TITLE_FONT],[panel.message,20,UiArt.FONT],[panel.detail,15,UiArt.FONT]]:
		var lines := UiArt.wrap_text(str(entry[0]),panel.TEXT_WIDTH,int(entry[1]),entry[2])
		var fits := not lines.is_empty()
		for line: String in lines:
			fits = fits and entry[2].get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,int(entry[1])).x<=panel.TEXT_WIDTH
		check(fits,"Localized confirmation text fits its reading column: "+context)

func prepare_role(role: String) -> void:
	game.network.set_process(false)
	game.network.active = role!="offline"
	game.network.is_host = role=="host"
	game.network.state = "playing" if role!="offline" else "idle"
	game.network.match_paused = role!="offline"
	game.hud.overlay = "pause"
	game.hud.last_overlay = "!"
	game.hud._apply_overlay_pause()
	await frames()

func check_online_transitions() -> void:
	for role: String in ["host","guest"]:
		for state: String in ["reconnecting","lobby","error"]:
			await prepare_role(role)
			game.hud.pause_buttons.main_menu.grab_focus()
			await key(KEY_ENTER)
			await joy(JOY_BUTTON_DPAD_UP)
			var panel: Control = game.hud.restart_dialog
			var context := "%s/playing-to-%s" % [role,state]
			check(panel.confirm_button.has_focus(),"Explicit session choice is selected before the connection changes: "+context)
			game.network.state = state
			await frames(5)
			check(panel.visible and game.hud.overlay=="network", "Connection change preserves the question above the new lobby: "+context)
			check(is_instance_valid(game.hud.network_panel) and not game.hud.network_panel.visible,"The newly created lobby stays hidden behind the question: "+context)
			check(panel.confirm_button.has_focus(),"Deferred native lobby focus cannot steal the selected session action: "+context)
			await key(KEY_TAB)
			check(panel.cancel_button.has_focus(),"Modal navigation remains inside the question after reconnecting: "+context)
			await joy(JOY_BUTTON_B)
			check(not game.hud.has_session_action() and game.hud._session_action.is_empty(),"Cancel clears the pending session action after a connection change: "+context)
			check(game.hud.network_panel.is_visible_in_tree(),"Cancel reveals the current connection screen: "+context)
			check(game.hud.network_panel.leave_button.has_focus() and not game.hud.network_panel.leave_button.disabled,"Cancel supplies native visible lobby focus after the previous opener was retired: "+context)
			check(game.network.active and game.network.state==state and game.players.size()==4,"Cancel preserves the current connection and crew: "+context)
	# Build the lobby synchronously and open the question before its queued
	# initial-focus callback runs. It must not even focus a hidden button briefly.
	await prepare_role("host")
	game.network.state = "reconnecting"
	game.hud.overlay = "network"
	game.hud._rebuild_buttons()
	game.hud.last_overlay = "network"
	_lobby_focus_events = 0
	game.hud.network_panel.leave_button.focus_entered.connect(func(): _lobby_focus_events += 1)
	game.hud._request_main_menu()
	await frames(5)
	check(game.hud.restart_dialog.cancel_button.has_focus() and _lobby_focus_events==0,"A question opened between lobby Ready and its deferred callback prevents transient hidden focus")
	await joy(JOY_BUTTON_B)
	check(game.hud.network_panel.leave_button.has_focus() and _lobby_focus_events==1,"Only cancelling the pending question permits the deferred initial lobby focus")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	await frames()
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		for role: String in ["offline","host","guest"]:
			await prepare_role(role)
			for action: String in ["menu","restart"]:
				if role=="guest" and action=="restart": continue
				var opener: Button = game.hud.pause_buttons["main_menu" if action=="menu" else "restart"]
				opener.grab_focus()
				await key(KEY_ENTER)
				var panel: Control = game.hud.restart_dialog
				var context := "%s/%s/%s" % [locale,role,action]
				check(game.hud.has_session_action() and game.hud._session_action==action,"Enter opens the requested session decision: "+context)
				check_presentation(panel,context)
				if action=="menu" and role!="offline":
					check(panel.message==("Du beendest den Online-Raum für die gesamte Crew." if role=="host" else "Du verlässt den Online-Raum. Die übrige Crew spielt weiter."),"Session consequence distinguishes host and guest: "+context)
				await joy(JOY_BUTTON_DPAD_UP)
				check(panel.confirm_button.has_focus(),"Controller reaches the other session action: "+context)
				await key(KEY_TAB)
				check(panel.cancel_button.has_focus(),"Tab stays in the two-action modal loop: "+context)
				var underlying: Button = game.hud.pause_buttons.continue_match
				await click(underlying.get_global_transform_with_canvas()*Vector2(underlying.size.x*.5,underlying.size.y*.5))
				check(panel.visible and game.hud.overlay=="pause" and game.players.size()==4,"Clicks cannot resume the paused menu beneath the modal: "+context)
				await key(KEY_F4)
				await key(KEY_F5)
				await key(KEY_F7)
				await key(KEY_SPACE)
				check(panel.visible and game.hud._session_action==action and game.hud.overlay=="pause","Menu and gameplay shortcuts preserve the pending decision: "+context)
				await joy(JOY_BUTTON_B)
				check(not panel.visible and game.hud.overlay=="pause" and paused,"Controller Back cancels without changing the paused mission: "+context)
				check(opener.has_focus(),"Cancellation restores the opening action: "+context)
	await check_online_transitions()
	await prepare_role("offline")
	var already_hidden := Control.new()
	already_hidden.hide()
	game.hud.canvas.add_child(already_hidden)
	game.hud.pause_buttons.main_menu.grab_focus()
	await key(KEY_ENTER)
	var inserted := Control.new()
	game.hud.canvas.add_child(inserted)
	await frames()
	check(not inserted.visible and not already_hidden.visible,"Modal hides controls inserted later and retains originally hidden controls")
	await joy(JOY_BUTTON_DPAD_UP)
	check(game.hud.restart_dialog.confirm_button.has_focus(),"Controller selects the explicit action before the underlying menu rebuilds")
	game.hud.last_overlay = "!"
	await frames()
	check(game.hud.pause_buttons.values().all(func(button: Button): return not button.visible),"Rebuilding a paused screen cannot expose its controls behind a pending question")
	check(game.hud.restart_dialog.confirm_button.has_focus(),"Rebuilding the underlying screen preserves the selected action inside the session question")
	await joy(JOY_BUTTON_B)
	check(inserted.visible and not already_hidden.visible,"Modal cancellation restores exact preexisting visibility states")
	var restored_focus := root.gui_get_focus_owner()
	check(is_instance_valid(restored_focus) and restored_focus in game.hud.pause_buttons.values() and restored_focus.is_visible_in_tree(),"Rebuilt pause menu receives visible focus after its old opening button was released")
	already_hidden.queue_free()
	inserted.queue_free()
	await frames()
	game.hud.overlay = ""
	game.hud._apply_overlay_pause()
	await frames()
	await key(KEY_F5)
	check(game.hud.has_session_action() and paused,"Restart from gameplay temporarily pauses the offline world")
	await key(KEY_ESCAPE)
	check(not game.hud.has_session_action() and not paused and game.hud.overlay.is_empty(),"Escape restores the running state when no pause menu opened the confirmation")
	await prepare_role("offline")
	game.hud.pause_buttons.main_menu.grab_focus()
	await key(KEY_ENTER)
	await joy(JOY_BUTTON_DPAD_UP)
	var original_id: int = game.get_instance_id()
	await key(KEY_ENTER)
	for unused in 8: await process_frame
	game = current_scene
	check(game.get_instance_id()!=original_id and not game.started and game.players.is_empty() and game.hud.overlay=="menu","Explicit native confirmation returns to a fresh main menu exactly once")
	await Cleanup.free_scene(game,self)
	print("SESSION ACTION PRESENTATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
