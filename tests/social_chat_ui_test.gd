extends SceneTree
## Real routed UI with explicit service/session probes; never opens a socket.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/social-ui/"
var game
var session: SessionProbe
var service: SocialProbe
var actual_network: Node
var actual_social: Node
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var view: SubViewport
var requested_screens := PackedStringArray()

class SessionProbe extends Node:
	var game: Node
	signal changed
	signal chat_changed
	signal chat_received(row: Dictionary)
	signal chat_send_completed(text: String,accepted: bool)
	var active := false
	var is_host := true
	var state := "offline"
	var local_player_id := 1
	var peer_connected := false
	var match_paused := false
	var max_players := 4
	var _loading := false
	@warning_ignore("unused_private_class_variable")
	var _authenticated := false
	@warning_ignore("unused_private_class_variable")
	var _generation := 1
	var remote_input: Dictionary = {}
	var relay_url := ""
	var advertised_address := ""
	var room_code := "CREW42"
	var lan_code := ""
	var direct_code := ""
	var internet_code := ""
	var connection_hint := ""
	var error_message := ""
	var chat_error := ""
	var chat_pending := false
	var chat_pending_text := ""
	var chat_pending_draft := ""
	var chat_draft := ""
	var chat_history: Array[Dictionary] = []
	var calls: Array = []
	var count := 2
	var reject := false
	func connected_player_count() -> int: return count
	func is_player_connected(id: int) -> bool: return id>=1 and id<=count
	func character_owner(id: String,excluding_player: int=0) -> int:
		if not is_instance_valid(game): return 0
		for slot in mini(count,game.selected_characters.size()):
			if slot+1 != excluding_player and game.selected_characters[slot]==id: return slot+1
		return 0
	func chat_available() -> bool: return active and state in ["lobby","playing"]
	func send_chat(text: String) -> bool:
		calls.append(["chat",text])
		if reject:
			chat_error="Nachricht konnte nicht gesendet werden."
			return false
		chat_pending=true
		chat_pending_text=text.strip_edges()
		chat_pending_draft=text
		return true
	func complete(accepted: bool) -> void:
		chat_pending=false
		chat_error="" if accepted else "Nachricht wurde nicht bestätigt. Entwurf bleibt erhalten."
		chat_send_completed.emit(chat_pending_text,accepted)
		chat_pending_text=""
		chat_pending_draft=""
		chat_changed.emit()
	func send_chat_preset(id: String) -> bool:
		calls.append(["preset",id])
		return true
	func row(text: String,id: int = 0,preset: String = "",author: String = "[b]Crew Ω[/b]") -> void:
		var value := {"id":id if id>0 else chat_history.size()+1,"player_id":2,"name":author,"text":text,"preset":preset,"time":145.0}
		chat_history.append(value)
		while chat_history.size()>80: chat_history.pop_front()
		chat_received.emit(value)
		chat_changed.emit()
	func join_room(url: String,code: String) -> void: calls.append(["join",url,code])
	func leave() -> void:
		calls.append(["leave"]); active=false; state="offline"; changed.emit()
	func pause_match(value: bool) -> void:
		calls.append(["pause",value])
		match_paused=value
	func send_command(kind: String,args: Dictionary) -> void: calls.append([kind,args])

class SocialProbe extends Node:
	signal changed
	signal invite_received(invite: Dictionary)
	var connection_state := "offline"
	var error_message := ""
	var display_name := "Crew Ω"
	var friend_code := "7K42Q9P6AMNZ"
	var server_url := ""
	var friends: Array[Dictionary] = []
	var requests: Array[Dictionary] = []
	var outgoing_requests: Array[Dictionary] = []
	var pending_friend_requests: Dictionary = {}
	var invitations: Array[Dictionary] = []
	var blocked: Array[Dictionary] = []
	var calls: Array = []
	func set_display_name(value: String) -> bool:
		calls.append(["name",value]); display_name=value; changed.emit(); return true
	func configure_server(value: String) -> bool:
		calls.append(["server",value]); server_url=value; return true
	func connect_service() -> bool:
		calls.append(["connect"]); connection_state="connecting"; changed.emit(); return true
	func disconnect_service() -> void: calls.append(["disconnect"]); connection_state="offline"; pending_friend_requests.clear();changed.emit()
	func add_friend(code: String) -> bool:
		calls.append(["add",code]);pending_friend_requests[code]=true;changed.emit();return true
	func is_friend_request_pending(code: String) -> bool: return pending_friend_requests.has(code)
	func complete_friend_request(code: String,accepted: bool) -> void:
		pending_friend_requests.erase(code)
		if accepted: outgoing_requests.append({"code":code,"name":"Alex Ω"})
		else: error_message="Anfrage konnte nicht gesendet werden."
		changed.emit()
	func set_presence(_data: Dictionary) -> void: pass
	func deliver_invite(value: Dictionary) -> void:
		invitations.append(value); invite_received.emit(value); changed.emit()
	func accept_friend(code: String) -> bool: calls.append(["accept",code]); return true
	func decline_friend(code: String) -> bool: calls.append(["decline",code]); return true
	func remove_friend(code: String) -> bool: calls.append(["remove",code]); return true
	func block_friend(code: String) -> bool: calls.append(["block",code]); return true
	func unblock_friend(code: String) -> bool: calls.append(["unblock",code]); return true
	func invite_friend(code: String) -> bool: calls.append(["invite",code]); return true
	func decline_invite(id: String) -> bool: calls.append(["decline_invite",id]); return true
	func take_invite(id: String) -> Dictionary:
		calls.append(["take",id])
		for value in invitations:
			if value.id==id and float(value.expires)>Time.get_unix_time_from_system(): return value.duplicate()
		return {}

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(label)
func frames(count: int = 4) -> void:
	for unused in count: await process_frame
func press(action: String) -> void:
	for down in [true,false]:
		var event := InputEventAction.new(); event.action=action; event.pressed=down
		view.push_input(event,true); await process_frame
	await frames()
func enter() -> void:
	for down in [true,false]:
		var event := InputEventKey.new(); event.keycode=KEY_ENTER; event.physical_keycode=KEY_ENTER; event.pressed=down
		view.push_input(event,true); await process_frame
	await frames()
func social_panel() -> Control:
	game.hud._open_social()
	await frames()
	var panel: Control=game.hud.social_panel
	panel.bind_social(service)
	return panel
func close_social() -> void:
	game.hud._close_social(); await frames()
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	L.set_locale("de",false)
	view=SubViewport.new(); view.size=Vector2i(1440,900); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.size_2d_override_stretch=true; view.size_2d_override=Vector2i(1440,900)
	view.process_mode=Node.PROCESS_MODE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate(); view.add_child(game)
	await frames(6)
	check(is_instance_valid(game.hud.chat_panel.network),"Chat binds after real HUD-ready/session-ready ordering")
	check(not game.network.active and not game.microphone.capturing,"Fresh UI opens no network socket or microphone")
	game.audio.live_music_enabled=false
	actual_network=game.network
	actual_social=game.social
	session=SessionProbe.new(); session.game=game; view.add_child(session)
	service=SocialProbe.new(); view.add_child(service)
	game.social=service
	game.network=session; game.hud.chat_panel.bind_network(session)
	if "--gallery-only" in OS.get_cmdline_user_args():
		service.connection_state="online"
		service.display_name="Mara"
		service.requests=[{"code":"CDEFGHJK4567","name":"Mika"}]
		service.blocked=[{"code":"DEFGHJKL5678","name":"Blocked"}]
		service.invitations=[{"id":"a12b34c56d78e90f1234567890abcdef","name":"Alex Ω","from_code":"ABCDEFGH2345","room_code":"CREW42","relay_url":"wss://relay.example/ws","expires":Time.get_unix_time_from_system()+120.0}]
		for index in 8: session.row("Wir halten zusammen!",index+1,"","Ivo")
		await create_gameplay()
		await gallery()
		game.network=actual_network; game.social=actual_social; game.hud.chat_panel.bind_network(actual_network)
		await Cleanup.free_scene(game,self); view.queue_free(); await frames()
		print("SOCIAL CHAT GALLERY: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
		return
	print("UI stage: friends")
	var chat: Control=game.hud.chat_panel
	check(game.hud.main_menu_panel.friends_button.position==Vector2(552,612),"Friends utility preserves all authored menu coordinates")
	await press("friends")
	var panel: Control=game.hud.social_panel
	panel.bind_social(service)
	check(game.hud.overlay=="friends" and panel.close_button.has_focus(),"F7 opens real friend panel with keyboard focus")
	check(panel.add_button.disabled and not panel._can_invite(),"Disconnected service offers no fake social actions")
	panel.name_field.text="Unsent Ω"; panel.server_field.text="wss://draft.example/social"; panel.friend_field.text="BC-DRAFT"
	service.display_name="Acknowledged name"; service.changed.emit(); await frames()
	check(panel.name_field.text=="Unsent Ω" and panel.server_field.text=="wss://draft.example/social" and panel.friend_field.text=="BC-DRAFT","Async service refresh never overwrites current text drafts")
	panel.name_field.grab_focus(); await press("audio_settings"); await press("restart")
	check(game.hud.overlay=="friends" and game.hud.has_text_entry(),"Text entry suppresses settings and restart hotkeys")
	service.connection_state="online"
	service.friends=[{"code":"ABCDEFGH2345","name":"[b]Alex Ω[/b]","status":"menu","environment":"ash_foundry","joinable":false},{"code":"BCDEFGHJ3456","name":"Rae","status":"offline","environment":"","joinable":false}]
	service.requests=[{"code":"CDEFGHJK4567","name":"Mika"}]
	service.blocked=[{"code":"DEFGHJKL5678","name":"Blocked"}]
	service.invitations=[{"id":"a12b34c56d78e90f1234567890abcdef","name":"Alex Ω","from_code":"ABCDEFGH2345","room_code":"CREW42","relay_url":"wss://relay.example/ws","expires":Time.get_unix_time_from_system()+120.0}]
	service.changed.emit(); await frames()
	check(panel.row_buttons["ABCDEFGH2345"][0].disabled,"Friend invite remains disabled before a real host lobby exists")
	panel.contact_buttons["ABCDEFGH2345"].pressed.emit();panel.contact_menu.id_pressed.emit(3);panel.contact_menu.hide();await frames()
	check(panel.confirmation.cancel_button.has_focus() and game.hud.has_session_action(),"Remove requires styled confirmation with safe default focus")
	await press("pause")
	check(not panel.confirmation.visible and not service.calls.has(["remove","ABCDEFGH2345"]),"Escape cancels removal without contacting service")
	panel.contact_buttons["ABCDEFGH2345"].pressed.emit();panel.contact_menu.id_pressed.emit(4);panel.contact_menu.hide();panel.confirmation.confirmed.emit();await frames()
	check(service.calls.has(["block","ABCDEFGH2345"]),"Explicit block forwards exact friend code")
	panel.tab_buttons.requests.pressed.emit(); panel.row_buttons["CDEFGHJK4567"][0].pressed.emit()
	check(service.calls.has(["accept","CDEFGHJK4567"]),"Accept request uses canonical friend code")
	panel.tab_buttons.blocked.pressed.emit(); panel.row_buttons["DEFGHJKL5678"][0].pressed.emit()
	check(service.calls.has(["unblock","DEFGHJKL5678"]),"Blocked tab restores access only on explicit action")
	panel.tab_buttons.invitations.pressed.emit(); panel.row_buttons["a12b34c56d78e90f1234567890abcdef"][0].pressed.emit(); await frames()
	check(session.calls.has(["join","wss://relay.example/ws","CREW42"]),"Invitation joins only explicitly from inactive session")
	game.hud.network_panel.server_field.text="wss://typed.example/ws"; game.hud.network_panel.code_field.text="CREW42"; game.hud.network_panel.show_server_options=true
	panel=await social_panel(); await close_social()
	check(game.hud.network_panel.server_field.text=="wss://typed.example/ws" and game.hud.network_panel.code_field.text=="CREW42" and game.hud.network_panel.show_server_options,"Friends excursion preserves typed lobby server/code and advanced setting visibility")
	game.hud.overlay="menu"; await frames()
	session.active=true; session.state="lobby"; session.peer_connected=true
	game.hud._open_network(); await frames()
	print("UI stage: lobby")
	var lobby: Control=game.hud.network_panel
	check(not lobby.chat_button.disabled,"Connected lobby exposes native chat entry")
	lobby.leave_button.grab_focus(); await enter()
	check(not chat.composing,"Enter on native lobby button is not stolen by chat")
	# That explicit button leaves the probe room; restore the prepared lobby.
	session.active=true; session.state="lobby"; game.hud.overlay="network"; await frames()
	panel=await social_panel()
	check(panel._can_invite() and not panel.row_buttons["ABCDEFGH2345"][0].disabled,"Host lobby with free space allows an online friend invitation")
	panel.row_buttons["ABCDEFGH2345"][0].pressed.emit()
	check(service.calls.has(["invite","ABCDEFGH2345"]),"Friend invitation forwards actual friend code")
	session.count=4; panel._refresh(); check(not panel._can_invite(),"Full lobby cannot send invitations")
	session.count=2; session._loading=true; panel._refresh(); check(not panel._can_invite(),"Loading session cannot advertise joinable invitations")
	session._loading=false; panel.select_tab("invitations"); await frames()
	check(panel.row_buttons["a12b34c56d78e90f1234567890abcdef"][0].disabled,"Invitation cannot silently replace an active room")
	var calls_before:=session.calls.size(); panel._join("a12b34c56d78e90f1234567890abcdef")
	check(session.calls.size()==calls_before,"Disabled active-room join never calls leave or join")
	await close_social()
	game.hud.network_panel.chat_button.pressed.emit(); await frames()
	print("UI stage: chat")
	check(chat.composing and chat.input_field.has_focus() and game.hud.blocks_gameplay_input(),"Lobby chat opens composer and blocks polled controls")
	chat.input_field.text="  Grüße Ω [b]Crew[/b]  "; await enter()
	check(chat.input_field.text=="  Grüße Ω [b]Crew[/b]  " and session.chat_pending,"Guest-style pending send retains original Unicode draft")
	session.complete(false); check(not chat.input_field.text.is_empty() and not chat._error.is_empty(),"Rejected host ACK retains draft and exposes error")
	chat.send_message(); session.state="reconnecting"; session.changed.emit(); await frames()
	check(not chat.composing and session.chat_draft==chat.input_field.text and not chat._submitted.is_empty(),"Temporary reconnect closes editor but preserves pending draft and receipt identity")
	session.state="lobby"; session.changed.emit(); session.complete(true); await frames()
	check(chat.input_field.text.is_empty() and session.chat_draft.is_empty(),"Accepted receipt after reconnect clears exactly the original draft")
	chat.open(); await frames(); chat.input_field.text="Next message"
	chat.send_message(); chat.input_field.text="New draft while waiting"; session.chat_draft=chat.input_field.text; session.complete(true)
	check(chat.input_field.text=="New draft while waiting","Accepted ACK does not erase text edited while waiting")
	chat.send_message(); session.complete(true)
	check(chat.input_field.text.is_empty() and session.chat_draft.is_empty(),"Accepted unchanged draft clears editor and persistent draft")
	chat.input_field.text="Survive UI rebuild"; session.chat_draft=chat.input_field.text; chat.send_message()
	chat.close(); chat.queue_free(); await frames()
	var replacement: Control=preload("res://scripts/chat_panel.gd").new(); replacement.game=game; replacement.hud=game.hud; game.hud.canvas.add_child(replacement); game.hud.chat_panel=replacement
	chat=replacement; await frames(); session.complete(true)
	check(chat.input_field.text.is_empty() and session.chat_draft.is_empty(),"Recreated UI consumes late ACK through persistent session pending text/draft")
	chat.open(); await frames()
	chat.input_field.text="Preset-safe draft"; session.chat_draft=chat.input_field.text
	for button: Button in chat.preset_buttons: button.pressed.emit()
	check(session.calls.filter(func(entry): return entry[0]=="preset").size()==6 and chat.input_field.text=="Preset-safe draft","All six canonical presets preserve free-text draft")
	check(session.calls.filter(func(entry): return entry[0]=="preset").map(func(entry): return entry[1])==["ready","help","ammo","thanks","nice","defend"],"Native preset buttons bind all six distinct canonical IDs")
	session.chat_error="Nachricht konnte nicht gesendet werden."; session.chat_changed.emit()
	check(chat._error==session.chat_error and chat.input_field.text=="Preset-safe draft","Async preset refusal exposes the real session error without erasing free-text draft")
	chat.close(); chat.open(); await frames()
	check(chat._error==session.chat_error and chat.input_field.text=="Preset-safe draft","Reopening chat retains an asynchronous send failure and its exact draft")
	session.chat_error=""
	for index in 80: session.row("Long plain message Ω " + str(index)+" " + "bounded history ".repeat(8))
	await frames(8)
	check(chat.history_box.get_child_count()==80 and chat._feed.size()<=4,"Native history and transient feed remain bounded")
	check(chat.history_box.get_child(0) is Label and chat.history_box.get_child(0).text.contains("[b]Crew Ω[/b]"),"Names containing BBCode remain literal plain native labels")
	chat.history_scroll.scroll_vertical=90; await frames(); var scroll_before: int=chat.history_scroll.scroll_vertical
	session.row("New message while reading",81); await frames(8)
	check(chat.history_scroll.scroll_vertical<200 and abs(chat.history_scroll.scroll_vertical-scroll_before)<80,"Incoming message preserves older reading position when oldest row rolls off")
	chat._scroll_bottom(); await frames(); session.row("Bottom follows message",82); await frames(8)
	check(chat._at_bottom(),"History follows new messages only when already at bottom")
	chat.close(); await frames(); session.row("Danke!",83); await frames()
	check(chat.unread==1 and chat._plain_lines("Danke!",412,12)==["Danke!"],"Closed chat shows unread count without translating player text")
	chat.open(); await frames(); check(chat.unread==0,"Opening history acknowledges unread messages")
	chat.feed_button.pressed.emit(); check(not chat.feed_visible,"Transient chat feed can be hidden independently")
	await press("pause"); check(not chat.composing and not game.hud.has_text_entry(),"Escape closes composer and releases text focus")
	await create_gameplay()
	print("UI stage: gameplay")
	await enter()
	check(chat.composing and not paused,"Gameplay Enter opens chat without pausing multiplayer")
	Input.action_press("p1_right")
	var sample: Dictionary=preload("res://scripts/network_input.gd").sample_local(game)
	check(sample.held.is_empty() and preload("res://scripts/network_input.gd").strength(game.players[0],"right")==0.0,"Typing suppresses both outgoing network controls and local movement polling")
	Input.action_release("p1_right")
	await press("audio_settings"); await press("restart"); await press("upgrades")
	check(game.hud.overlay.is_empty() and chat.composing and not game.hud.has_session_action(),"Typing cannot trigger F4/F5/research gameplay shortcuts")
	await press("pause"); check(not chat.composing and not paused,"Closing game chat does not pause the match")
	service.invitations.clear(); service.deliver_invite({"id":"a12b34c56d78e90f1234567890abcdef","name":"Alex Ω","from_code":"ABCDEFGH2345","room_code":"CREW42","relay_url":"wss://relay.example/ws","expires":Time.get_unix_time_from_system()+120.0}); await frames()
	check(game.hud.overlay.is_empty() and game.hud.friends_dock.visible and game.hud.social_pending_count()==2,"New invitation updates in-game badge without switching menus or pausing the match")
	session.active=false; session.state="offline"
	await enter(); check(not chat.composing,"Offline Enter remains available to player two instead of opening chat")
	Input.action_press("p2_interact")
	check(preload("res://scripts/network_input.gd").is_pressed(game.players[1],"interact"),"Offline player two keeps the real interaction input mapping")
	Input.action_release("p2_interact"); session.active=true; session.state="playing"
	if "--capture" in OS.get_cmdline_user_args(): await gallery()
	game.network=actual_network; game.social=actual_social; game.hud.chat_panel.bind_network(actual_network)
	check(not actual_network.active and not game.microphone.capturing,"All UI checks preserve offline transport and microphone state")
	await Cleanup.free_scene(game,self); view.queue_free(); await frames()
	print("SOCIAL CHAT UI: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)

func create_gameplay() -> void:
	session.active=false; session.state="offline"
	game.network=actual_network; game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"}); game.rounds.running=false
	game.network=session; session.active=true; session.state="playing"
	game.hud.overlay=""; paused=false
	for child in game.get_children():
		if child==game.hud: continue
		child.set_process(false); child.set_physics_process(false)
	await frames()

func capture(id: String) -> void:
	if not requested_screens.is_empty() and id not in requested_screens: return
	print("CAPTURE ",view.size.x," ",L.current_locale()," ",id)
	await frames(5)
	var label := "%d-%s-%s" % [view.size.x,L.current_locale(),id]
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.get_size()==view.size,"Native capture resolution: "+label)
	var path := OUTPUT+"captures/"+label+".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"captures/")); picture.save_png(path)
	var controls: Array[Dictionary]=[]
	var pending: Array[Node]=[game.hud.canvas]
	while not pending.is_empty():
		var node: Node=pending.pop_back(); pending.append_array(node.get_children())
		if not node is Button or not node.is_visible_in_tree(): continue
		var available: float=node.size.x-node.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)-node.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT)
		var width: float=node.get_theme_font("font").get_string_size(L.text(node.text),HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x
		check(width<=available+1.0,"Button label fits "+label+": "+node.text)
		controls.append({"label":node.text,"width":width,"available":available,"disabled":node.disabled})
	captures.append({"id":id,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"path":path.trim_prefix("res://"),"controls":controls})

func gallery() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): requested_screens=argument.trim_prefix("--only=").split(",",false)
	for resolution in [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080)]:
		view.size=resolution; view.size_2d_override=Vector2i(1600,900) if resolution.x==1920 else Vector2i(1440,900); await frames()
		for language in ["de","en"]:
			L.set_locale(language,false); game.hud._locale_changed(language)
			session.active=false; session.state="offline"; game.started=false; game.hud.overlay="menu"; paused=true; await capture("main-menu")
			var panel: Control=await social_panel(); service.connection_state="offline"; service.server_url=""; service.friends=[]; panel.name_field.text=service.display_name; panel.server_field.text=""; panel._signature=""; panel._refresh(); await capture("friends-disconnected")
			service.connection_state="online"; service.server_url="wss://relay.example/social"; panel.server_field.text=service.server_url; service.friends=[{"code":"ABCDEFGH2345","name":"Alex Ω","status":"playing","environment":"mountain_pass","joinable":false},{"code":"BCDEFGHJ3456","name":"Rae","status":"offline","environment":"","joinable":false}]; panel._signature=""; panel._refresh(); await capture("friends")
			panel._confirm("remove","ABCDEFGH2345"); await capture("friend-remove-confirm"); panel._cancel_confirmation()
			panel.select_tab("requests"); await capture("friend-requests")
			service.invitations[0].expires=Time.get_unix_time_from_system()+120.0; panel.select_tab("invitations"); await capture("friend-invitations")
			panel.select_tab("blocked"); await capture("friend-blocked")
			game.hud._close_social(); session.active=true; session.state="lobby"; game.hud.overlay="network"; await capture("lobby")
			game.hud.chat_panel.open(); game.hud.chat_panel.input_field.text="Grüße an die Crew Ω"; await capture("lobby-chat")
			game.hud.chat_panel._error="Nachricht wurde nicht bestätigt. Entwurf bleibt erhalten."; await capture("chat-rejected-draft"); game.hud.chat_panel.close()
			game.started=true; session.state="playing"; game.hud.overlay=""; paused=false; game.hud.chat_panel.feed_visible=true; session.row("Gut gemacht, Crew!",100+captures.size(),"","Ivo"); await capture("game-chat-feed"); await capture("game-invitation-badge")
			game.hud.chat_panel.open(); await capture("game-chat-composer"); game.hud.chat_panel.close()
	if not requested_screens.is_empty() and FileAccess.file_exists(OUTPUT+"gallery.json"):
		var previous: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"gallery.json"))
		if previous is Dictionary:
			for entry: Dictionary in previous.get("captures",[]):
				if str(entry.get("id","")) not in requested_screens: captures.append(entry)
	var output := FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Real Godot HUD/panels; explicit offline service and session probes, no sockets, audio muted, no profile save.","captures":captures},"\t")); output.close()
