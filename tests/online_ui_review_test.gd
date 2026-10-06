extends SceneTree
## Actual routed panels and native controls with explicit offline roster/service probes.
const Base := preload("res://tests/social_chat_ui_test.gd")
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/online-ui/"
const PENDING_OUTPUT := "res://artifacts/hardening-20261003/ui-verbindung/"
var game
var actual_network: Node
var actual_social: Node
var session: CrewSession
var service: Base.SocialProbe
var view: SubViewport
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []

class CrewSession extends Base.SessionProbe:
	var disconnected: Array[int] = []
	var muted: Dictionary = {}
	var blocked: Dictionary = {}
	var verified_code := "ABCDEFGH2345"
	var identity_pending := false
	var identity_status := "verified"
	var member_keys := {"1":"111111111111111111111111111111111111111111111111","2":"222222222222222222222222222222222222222222222222","3":"333333333333333333333333333333333333333333333333","4":"444444444444444444444444444444444444444444444444"}
	var display_name := "Mara Ω"
	var short_room_code := ""
	var ping_ms := 42
	@warning_ignore("unused_private_class_variable")
	var _short_resolution := ""
	var chat_names := {"1":"Mara Ω","2":"Alex Ω","3":"Mika","4":"Rae"}
	func is_player_connected(id: int) -> bool: return active and id >= 1 and id <= count and id not in disconnected
	func connected_player_count() -> int:
		var connected := 0
		for id in range(1,count+1):
			if is_player_connected(id): connected+=1
		return connected
	func crew_members() -> Array[Dictionary]:
		var rows: Array[Dictionary] = []
		if not active: return rows
		for id in range(1,count+1):
			rows.append({"player_id":id,"name":chat_names[str(id)],"character_id":["mara","ivo","branko","mara"][id-1],"friend_code":verified_code if id==2 else "","friend_service":"wss://relay.example/social","identity_pending":identity_pending if id==2 else false,"identity_status":"pending" if identity_pending else identity_status if id==2 else "unavailable","member_key":member_keys[str(id)],"is_local":id==local_player_id,"is_host":id==1,"connected":is_player_connected(id)})
		return rows
	func is_player_muted(slot: int) -> bool: return muted.has(slot)
	func is_player_blocked(slot: int) -> bool: return blocked.has(slot)
	func set_player_muted(slot: int,value: bool) -> bool:
		calls.append(["mute",slot,value])
		if value: muted[slot]=true
		else: muted.erase(slot)
		changed.emit();return true
	func set_player_blocked(slot: int,value: bool) -> bool:
		calls.append(["block_player",slot,value])
		if value: blocked[slot]=true
		else: blocked.erase(slot)
		changed.emit();return true
	func private_chat_available(slot: int) -> bool: return chat_available() and slot!=local_player_id and is_player_connected(slot) and not is_player_blocked(slot)
	func send_private_chat(slot: int,text_value: String) -> bool:
		calls.append(["private",slot,text_value])
		if not private_chat_available(slot): chat_error="Diese Person ist nicht mehr erreichbar.";return false
		chat_pending=true;chat_pending_text=text_value.strip_edges();chat_pending_draft=text_value;return true
	func set_capacity(value: int) -> bool:
		calls.append(["capacity",value]);max_players=value;changed.emit();return true
	func host_room(url: String="") -> void:
		calls.append(["host",url]);active=true;is_host=true;state="lobby";peer_connected=false;count=1;changed.emit()

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1;push_error(label)
func frames(count: int=4) -> void:
	for unused in count: await process_frame
func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down
		view.push_input(event,true);await process_frame
	await frames()
func joy(button: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new();event.button_index=button;event.pressed=down
		view.push_input(event,true);await process_frame
	await frames()
func click(control: Control) -> void:
	var center := control.get_global_transform_with_canvas()*(control.size*.5)
	for down in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=center;event.pressed=down
		view.push_input(event,true);await process_frame
	await frames()
func lobby() -> Control:
	game.hud._open_network();await frames()
	return game.hud.network_panel
func friends() -> Control:
	game.hud._open_social();await frames()
	game.hud.social_panel.bind_social(service)
	return game.hud.social_panel
func host(count: int=2) -> void:
	session.active=true;session.is_host=true;session.local_player_id=1;session.state="lobby";session.peer_connected=count>1;session.count=count;session.max_players=4
	session._authenticated=true
	session.error_message="";session.disconnected.clear();session.changed.emit()
func menu_item(panel: Control,id: int) -> int: return panel.member_menu.get_item_index(id)
func open_member(panel: Control,slot: int=2) -> void:
	panel.crew_buttons[slot-1].grab_focus();await key(KEY_ENTER);await frames()
func close_popup(panel: Control) -> void:
	panel.member_menu.hide();await frames()
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	AudioServer.set_bus_mute(0,true);L.set_locale("de",false)
	view=SubViewport.new();view.size=Vector2i(1440,900);view.size_2d_override=Vector2i(1440,900);view.size_2d_override_stretch=true;view.gui_embed_subwindows=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate();view.add_child(game);await frames(6)
	check(not game.network.active and not game.microphone.capturing,"The actual fresh menu is offline and does not capture microphone audio")
	actual_network=game.network;actual_social=game.social
	session=CrewSession.new();service=Base.SocialProbe.new();view.add_child(session);view.add_child(service)
	service.connection_state="online";service.server_url="wss://relay.example/social";service.display_name="Mara Ω"
	game.network=session;game.social=service;game.hud.chat_panel.bind_network(session)
	var panel: Control=await lobby()
	check(panel.character_buttons.size()==CharacterCatalog.CHARACTERS.size() and panel.crew_buttons.size()==4,"All authored character IDs and four crew slots retain their public index order")
	check(panel.character_scroll.get_rect().end.y<panel.start_button.position.y,"Scrolling character choices remain above scene/start controls")
	for index in CharacterCatalog.CHARACTERS.size():
		check(panel.character_buttons[index].text==CharacterCatalog.selection_title(str(CharacterCatalog.CHARACTERS[index].id)),"Lobby preserves catalog order and anonymous locked title for slot "+str(index+1))
	panel.character_scroll.scroll_vertical = roundi(panel.character_scroll.get_v_scroll_bar().max_value)
	await frames()
	check(panel.character_scroll.get_global_rect().encloses(panel.character_buttons[-1].get_global_rect()),"Last authored character remains completely accessible through native lobby scrolling")
	check(panel._landscape.preview!=null and panel._landscape.clip.clip_contents,"The lobby uses the actual existing landscape and clips it to the full visible screen")
	check(panel.join_button.disabled and panel.start_button.disabled,"An empty offline room cannot join or start")
	if "--capture-failure-only" in OS.get_cmdline_user_args():
		await failed_join_gallery(panel)
		await finish_review()
		return
	panel=await pending_join_review(panel)
	host();panel._refresh();await frames()
	check(not panel.start_button.disabled and panel.crew_buttons[0].text=="Mara Ω" and panel.crew_buttons[1].text=="Alex Ω","The host sees actual roster names and can start a connected room")
	check(panel.crew_buttons[2].disabled and panel.crew_buttons[3].disabled,"Empty crew slots are explicit and cannot open member actions")
	session.short_room_code="ABC234";session.direct_code="FULL-DIRECT-CODE";panel._refresh()
	check(panel._primary_code()=="ABC234" and panel._primary_code_label()=="Raumcode" and not panel.copy_direct_button.visible,"A confirmed short server code is the shared primary code and keeps long fallback actions quiet")
	panel.show_server_options=true;panel._refresh()
	check(panel.copy_direct_button.visible,"Advanced server options retain the full direct-code fallback")
	panel.show_server_options=false;session.short_room_code="";session.direct_code="";panel._refresh()
	await click(panel.crew_buttons[1])
	check(panel.member_menu.visible,"A physical mouse click opens the same selected member's menu")
	await close_popup(panel)
	panel.crew_buttons[0].grab_focus();await key(KEY_ENTER)
	check(not panel.member_menu.visible and panel.character_buttons[0].has_focus(),"Activating your own crew row focuses your current character instead of remote actions")
	await open_member(panel)
	check(panel.member_menu.visible and panel.member_menu.get_item_text(0)=="Alex Ω","Actual keyboard activation opens the selected remote person's native context menu")
	check(not panel.member_menu.is_item_disabled(menu_item(panel,1)) and not panel.member_menu.is_item_disabled(menu_item(panel,2)),"Remote audio mute and block are real enabled member actions")
	check(not panel.member_menu.is_item_disabled(menu_item(panel,4)),"A verified online non-friend offers an explicit friend request")
	panel.member_menu.set_focused_item(menu_item(panel,1));await key(KEY_ENTER);await close_popup(panel)
	check(session.calls.count(["mute",2,true])==1 and session.is_player_muted(2),"Native popup Enter mutes the selected remote slot exactly once")
	await open_member(panel);panel.member_menu.id_pressed.emit(1);await close_popup(panel)
	check(session.calls.has(["mute",2,false]) and not session.is_player_muted(2),"The same member can explicitly restore their audio")
	await open_member(panel);panel.member_menu.id_pressed.emit(2);await close_popup(panel)
	check(session.calls.has(["block_player",2,true]),"Block reaches the selected remote session member")
	await open_member(panel)
	check(panel.member_menu.is_item_disabled(menu_item(panel,3)),"A blocked member cannot open a private composer")
	panel.member_menu.id_pressed.emit(2);await close_popup(panel)
	check(not session.is_player_blocked(2),"Unblock restores the same remote member's access")
	await open_member(panel);panel.member_menu.id_pressed.emit(4);await close_popup(panel)
	check(service.calls.count(["add","ABCDEFGH2345"])==1,"Friend request uses only the verified selected member's canonical code")
	check(service.is_friend_request_pending("ABCDEFGH2345") and panel._add_member_reason(panel.crew_rows[2])=="Freundesanfrage wird gesendet …","Sending is transient service state, not a claimed confirmed outgoing request")
	service.complete_friend_request("ABCDEFGH2345",true);panel._refresh();await frames()
	check(panel._add_member_reason(panel.crew_rows[2])=="Freundesanfrage offen.","Only a server-confirmed outgoing request becomes open")
	check(panel._notice=="Freundesanfrage gesendet." and panel._friend_request_code.is_empty(),"A server acknowledgement replaces the sending notice immediately")
	panel=await lobby()
	check(not panel._can_add_member(panel.crew_rows[2]),"A confirmed outgoing request survives lobby recreation through hub state")
	service.outgoing_requests=[]
	await open_member(panel);panel.member_menu.id_pressed.emit(4);await close_popup(panel)
	service.complete_friend_request("ABCDEFGH2345",false);panel._refresh();await frames()
	check(panel._notice==service.error_message and panel._friend_request_code.is_empty() and panel._can_add_member(panel.crew_rows[2]),"A server refusal immediately replaces sending with its actual error and allows a deliberate retry")
	service.error_message="";await open_member(panel);panel.member_menu.id_pressed.emit(4);await close_popup(panel)
	service.disconnect_service();panel._refresh();await frames()
	check(panel._notice=="Freundesdienst nicht verbunden." and panel._friend_request_code.is_empty() and not panel._can_add_member(panel.crew_rows[2]),"Losing the friend service ends the sending notice immediately and disables requests")
	service.connection_state="online";service.error_message="";service.pending_friend_requests={};panel._refresh()
	for condition in ["pending","unknown","offline","friend","request","blocked","sending","outgoing","other_service"]:
		session.identity_pending=condition=="pending";session.verified_code="" if condition=="unknown" else "ABCDEFGH2345"
		session.identity_status="other_service" if condition=="other_service" else "verified"
		service.server_url="wss://different.example/social" if condition=="other_service" else "wss://relay.example/social"
		service.connection_state="offline" if condition=="offline" else "online"
		service.friends.assign([{"code":"ABCDEFGH2345","name":"Alex Ω"}] if condition=="friend" else [])
		service.requests.assign([{"code":"ABCDEFGH2345","name":"Alex Ω"}] if condition=="request" else [])
		service.blocked.assign([{"code":"ABCDEFGH2345","name":"Alex Ω"}] if condition=="blocked" else [])
		service.pending_friend_requests={"ABCDEFGH2345":true} if condition=="sending" else {}
		service.outgoing_requests.assign([{"code":"ABCDEFGH2345","name":"Alex Ω"}] if condition=="outgoing" else [])
		panel._refresh();await open_member(panel)
		check(panel.member_menu.is_item_disabled(menu_item(panel,4)),"Friend request remains unavailable for state: "+condition)
		var before := service.calls.size();panel.member_menu.id_pressed.emit(4);await close_popup(panel)
		check(service.calls.size()==before,"A disabled friend action has no service side effect: "+condition)
	session.identity_pending=false;session.identity_status="verified";session.verified_code="ABCDEFGH2345";service.server_url="wss://relay.example/social";service.connection_state="online";service.friends=[];service.requests=[];service.outgoing_requests=[];service.pending_friend_requests={};service.blocked=[];panel._refresh()
	await open_member(panel);session.disconnected.append(2);session.changed.emit();await frames()
	var before_calls := service.calls.size();panel.member_menu.id_pressed.emit(4);await close_popup(panel)
	check(service.calls.size()==before_calls,"An open context menu cannot request friendship from a disconnected slot")
	session.disconnected.clear();panel._refresh();await open_member(panel)
	var old_member_key: String=session.member_keys["2"]
	session.member_keys["2"]="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";session.changed.emit();await frames()
	before_calls=service.calls.size();panel.member_menu.id_pressed.emit(4);await close_popup(panel)
	check(service.calls.size()==before_calls and not panel.member_menu.visible,"A same-name replacement cannot receive an action from the previous person's popup")
	session.member_keys["2"]=old_member_key;panel._refresh()
	session.disconnected.clear();panel._refresh();await open_member(panel);await key(KEY_ESCAPE)
	check(not panel.member_menu.visible and game.hud.overlay=="network" and panel.crew_buttons[1].has_focus(),"Escape dismisses only member actions and restores the crew-row focus")
	await open_member(panel);panel.member_menu.id_pressed.emit(3);await close_popup(panel);await frames()
	var chat: Control=game.hud.chat_panel
	check(chat.composing and chat.private_target==2 and chat.input_field.has_focus(),"Write message opens a private composer for the actual selected member")
	check(chat.input_field.placeholder_text==L.text("Nachricht an %s …") % "Alex Ω","The private input names the pinned recipient, including when its draft is empty")
	chat.input_field.text="  Hallo Alex Ω  ";chat.send_message();await frames()
	check(session.calls.has(["private",2,"  Hallo Alex Ω  "]) and not session.calls.has(["chat","  Hallo Alex Ω  "]),"The private draft reaches the selected recipient without a public-room send")
	session.complete(false);await frames()
	check(chat.input_field.text=="  Hallo Alex Ω  " and not chat._error.is_empty(),"A refused private delivery keeps the exact Unicode draft and shows its failure")
	chat.send_message();session.complete(true);await frames()
	check(chat.input_field.text.is_empty(),"An acknowledged unchanged private draft clears only after delivery")
	chat.input_field.text="Draft while recipient leaves";session.disconnected.append(2);session.changed.emit();await frames()
	check(chat.send_button.disabled and chat.input_field.text=="Draft while recipient leaves","An unavailable private recipient disables sending without deleting the draft")
	var calls_before_disconnect := session.calls.size();chat.send_message();chat.send_preset("help");await frames()
	check(session.calls.size()==calls_before_disconnect,"A disconnected private draft never falls back to public chat or quick phrases")
	chat.close();session.disconnected.clear();await frames()
	chat.open_private(2);await frames();chat.input_field.text="Same name, different person Ω"
	session.member_keys["2"]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";session.changed.emit();await frames()
	check(chat.send_button.disabled and chat.input_field.text=="Same name, different person Ω","A private draft stays pinned to its original member identity after slot reuse")
	var calls_before_replace := session.calls.size();chat.send_message();chat.send_preset("help");await frames()
	check(session.calls.size()==calls_before_replace,"Slot reuse cannot send the original private draft to a replacement occupant")
	chat.close();chat.open_private(2);await frames()
	check(not chat.send_button.disabled and chat.private_target==2,"An explicit new conversation can select the replacement occupant")
	chat.close();session.member_keys["2"]=old_member_key;session.changed.emit()
	panel=await lobby();panel.crew_buttons[1].grab_focus();await frames()
	var before_joy_calls := session.calls.size()
	await joy(JOY_BUTTON_A)
	var focused: Control=view.gui_get_focus_owner()
	check(panel.member_menu.visible,"A gamepad confirm opens the same real member context menu (slot=%d, composing=%s, crewfocus=%s, overlay=%s, match=%s, calls=%s)" % [panel._context_slot,chat.composing,focused==panel.crew_buttons[1],game.hud.overlay,panel._context_matches(panel.crew_rows[2]),str(session.calls.slice(before_joy_calls))])
	await close_popup(panel)
	var social: Control=await friends()
	service.requests=[{"code":"CDEFGHJK4567","name":"Mika"}]
	service.outgoing_requests=[{"code":"ABCDEFGH2345","name":"Alex Ω"}]
	social.select_tab("requests");await frames()
	check(social.row_buttons["CDEFGHJK4567"].size()==2 and social.row_buttons["outgoing/ABCDEFGH2345"].size()==1,"Incoming requests expose mutual confirmation while outgoing requests expose only cancellation")
	social._action("accept","ABCDEFGH2345")
	check(not service.calls.has(["accept","ABCDEFGH2345"]),"An outgoing request cannot be accepted through the incoming action path")
	social.row_buttons["outgoing/ABCDEFGH2345"][0].pressed.emit();await frames()
	check(service.calls.has(["remove","ABCDEFGH2345"]),"Canceling an outgoing request uses the confirmed canonical code")
	service.outgoing_requests=[];service.pending_friend_requests={};service.error_message=""
	social.friend_field.text="ABCDEFGH2345";social.add_button.pressed.emit();await frames()
	check(social._notice=="Freundesanfrage wird gesendet …" and social._rows("requests").size()==1,"Queued sending creates no fictional outgoing row")
	service.complete_friend_request("ABCDEFGH2345",false);await frames()
	check(social._notice==service.error_message and social._rows("requests").size()==1,"Server rejection clears sending state and keeps a precise failure instead of a false open request")
	social.friend_field.text="ABCDEFGH2345";social.add_button.pressed.emit();await frames()
	service.complete_friend_request("ABCDEFGH2345",true);await frames()
	check(social._notice=="Freundesanfrage gesendet." and social.row_buttons.has("outgoing/ABCDEFGH2345"),"Server-confirmed outgoing state updates the live requests list")
	service.outgoing_requests=[];service.requests=[];service.pending_friend_requests={};service.error_message="";game.hud._close_social();await frames()
	if "--capture" in OS.get_cmdline_user_args(): await gallery()
	await finish_review()

func finish_review() -> void:
	game.network=actual_network;game.social=actual_social;game.hud.chat_panel.bind_network(actual_network)
	check(not actual_network.active and not game.microphone.capturing,"The full UI review leaves actual transport and microphone inactive")
	check(await Cleanup.free_scene(game,self),"The actual menu scene and audio release cleanly after UI review")
	view.queue_free();await frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var result := {"checks":checks,"failures":failures,"prepared_states":"Real MainScene and routed HUD; explicit offline service/session roster probes, muted audio, no sockets, no profile saves.","captures":captures}
	var output: String=PENDING_OUTPUT if "--capture-pending" in OS.get_cmdline_user_args() or "--capture-failure-only" in OS.get_cmdline_user_args() else OUTPUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report := "failure-verification.json" if "--capture-failure-only" in OS.get_cmdline_user_args() else "review-verification.json" if "--capture" in OS.get_cmdline_user_args() or "--capture-pending" in OS.get_cmdline_user_args() else "review-headless-verification.json"
	FileAccess.open(output+report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ONLINE UI REVIEW: %d/%d checks passed" % [checks-failures,checks]);quit(1 if failures else 0)

func inspect_controls(label: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pending: Array[Node] = [game.hud.canvas]
	while not pending.is_empty():
		var node: Node=pending.pop_back();pending.append_array(node.get_children())
		if not node is Button or not node.is_visible_in_tree(): continue
		var available: float=node.size.x-node.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)-node.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT)
		if node.icon!=null: available-=node.icon.get_width()+node.get_theme_constant("h_separation")
		var width: float=node.get_theme_font("font").get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x
		check(width<=available+1,"Button label fits "+label+": "+node.text)
		var transform: Transform2D=view.get_stretch_transform()*node.get_global_transform_with_canvas()
		var a: Vector2=transform*Vector2.ZERO
		var b: Vector2=transform*node.size
		check(a.x>=-1 and a.y>=-1 and b.x<=view.size.x+1 and b.y<=view.size.y+1,"Visible button remains within the native output: "+label+" "+node.text)
		entries.append({"label":node.text,"width":width,"available":available,"disabled":node.disabled})
	return entries
func capture(id: String,baseline: bool=false,output: String=OUTPUT) -> void:
	await frames(5)
	var label := "%d-%s-%s" % [view.size.x,L.current_locale(),id]
	var controls := [] if baseline else inspect_controls(label)
	# Explicitly finish this real GPU frame even when the disposable test window
	# has lost focus or is minimized; never wait forever for an OS draw event.
	RenderingServer.force_draw(false)
	var picture := view.get_texture().get_image()
	check(picture.get_size()==view.size,"Screenshot retains native output resolution: "+label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+"captures"))
	var path := output+"captures/"+label+".png";picture.save_png(path)
	print("CAPTURE: "+label)
	captures.append({"id":id,"locale":L.current_locale(),"resolution":[view.size.x,view.size.y],"baseline":baseline,"path":path.trim_prefix("res://"),"controls":controls})

func pending_join_review(panel: Control) -> Control:
	# The probe deliberately claims cached crew_members/count and exposes chat
	# before welcome, reproducing the misleading screenshot at the UI boundary.
	for resolution in [Vector2i(960,600),Vector2i(1440,900)]:
		view.size=resolution;await frames()
		for locale in ["de","en"]:
			L.set_locale(locale,false);game.hud._locale_changed(locale);await frames()
			panel=game.hud.network_panel
			session.active=false;session.is_host=true;session.local_player_id=1;session.state="offline";session.peer_connected=false;session._authenticated=false
			session._short_resolution="";session.connection_hint="";session.error_message="";session.relay_url=""
			panel.restore_connection_preferences({"server":""});panel.show_server_options=true;panel._refresh()
			check(panel.connection_mode_button.visible and not panel.connection_mode_button.disabled and not panel.direct_mode and panel.server_field.text=="wss://bunkercrew.vibechain.rocks/ws","%d-%s online options expose the default relay and explicit mode" % [resolution.x,locale])
			if "--capture-pending" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless": await capture("online-options",false,PENDING_OUTPUT)
			await click(panel.connection_mode_button)
			check(panel.direct_mode and panel.server_field.text.is_empty() and panel.public_address_field.editable,"%d-%s physical mode click selects direct LAN and router settings" % [resolution.x,locale])
			if "--capture-pending" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless": await capture("direct-options",false,PENDING_OUTPUT)
			panel.connection_mode_button.grab_focus();await key(KEY_ENTER)
			check(not panel.direct_mode and not panel.server_field.text.is_empty(),"%d-%s keyboard mode confirmation returns to online relay" % [resolution.x,locale])
			panel.show_server_options=false;panel._refresh()
			for phase in ["lookup","direct","relay-seat","retry","failed"]:
				session.active=true;session.is_host=false;session.local_player_id=2
				session._authenticated=false;session.peer_connected=phase in ["relay-seat","retry"]
				session.state="lobby" if phase=="relay-seat" else "reconnecting" if phase=="retry" else "error" if phase=="failed" else "connecting"
				session.count=2;session.room_code="CACHED-ROOM";session.short_room_code="ABC234"
				session._short_resolution="lookup-pending" if phase=="lookup" else ""
				session.relay_url="wss://bunkercrew.vibechain.rocks/ws" if phase=="relay-seat" else ""
				session.connection_hint="Raumcode wird über den Freundeserver aufgelöst …" if phase=="lookup" else "Verbindung über den gewählten Vermittlungsserver." if phase=="relay-seat" else "Direkte Verbindung zum Gastgeber wird aufgebaut."
				session.error_message="Der Gastgeber konnte nicht kontaktiert werden." if phase=="failed" else ""
				panel.code_field.text="ABC234";panel.server_field.text="wss://stale-preference.example/ws";panel._refresh();await frames()
				var label := "%d-%s-%s" % [resolution.x,locale,phase]
				check(panel._member_count()==0 and panel.crew_buttons.all(func(button):return button.disabled),label+" no provisional or stale host is connected")
				check(panel.chat_button.disabled and panel.character_buttons.all(func(button):return button.disabled) and panel.scene_button.disabled,label+" all unauthenticated player actions remain disabled")
				check(panel.start_button.disabled==(phase!="failed") and (phase!="failed" or panel.start_button.text==L.text("Erneut beitreten")),label+" terminal failure offers a retry instead of waiting for an ended attempt")
				check(not panel.copy_button.visible and panel.crew_buttons[0].tooltip_text.is_empty(),label+" no cached sharing code or member actions appear")
				check(not panel._connection_hint_text().contains("42"),label+" cached ping is absent before authentication")
				var commands_before: int=session.calls.size()
				panel._select("ivo");panel._open_member(1)
				check(commands_before==session.calls.size() and not panel.member_menu.visible,label+" direct callbacks cannot act on a provisional slot")
				check(panel.crew_status()==L.text("Kein aktiver Raum" if phase=="failed" else "Verbindung noch nicht bestätigt"),label+" status matches the actual handshake outcome")
				check(panel.character_heading_text()==L.text("Deine Figur · Platz noch offen"),label+" provisional player ID does not become an assigned seat")
				check(UiArt.FONT.get_string_size(panel.character_heading_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x<=306,label+" unassigned character heading fits the existing right column")
				if phase=="failed":
					check(panel.connection_route_text()==L.text("Direkte Verbindung"),label+" failed direct attempt retains its actual route")
					check(panel._connection_hint_text()==L.text("Der Gastgeber kann einen neuen Online-Raum über Relay erstellen. Direkte Internetverbindungen benötigen eine Router-Freigabe."),label+" failure explains a new relay room instead of claiming an ongoing direct attempt")
				if phase!="failed":
					check(panel.connection_route_text()==L.text("Verbindungsweg wird ermittelt …" if phase=="lookup" else "Verbindung über Relay" if phase=="relay-seat" else "Direkte Verbindung"),label+" route follows actual lookup/transport rather than the saved preference")
					check(panel.leave_button.text==L.text("Abbrechen") and not panel.code_field.editable,label+" pending join is cancellable and cannot be edited underneath the transport")
				if "--capture-pending" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless": await capture("join-"+phase,false,PENDING_OUTPUT)
	# A successful welcome, including a new assigned seat, is the sole guest
	# transition to a live roster. Host reconnection still retains healthy peers.
	session.active=true;session.state="lobby";session._authenticated=true;session.peer_connected=true;session.local_player_id=3;session.count=3
	panel._refresh()
	check(panel._member_count()==3 and not panel.crew_buttons[0].disabled and not panel.chat_button.disabled,"The real welcome exposes confirmed peers and its actual assigned third seat")
	session.is_host=true;session.local_player_id=1;session.state="reconnecting";session._authenticated=false;session.disconnected=[2];panel._refresh()
	check(panel._member_count()==2 and not panel.crew_buttons[0].disabled and not panel.crew_buttons[2].disabled and panel.crew_buttons[1].disabled,"A host waiting for a lost guest retains the remaining authenticated crew rows")
	session.active=false;session.is_host=true;session.local_player_id=1;session.state="offline";session.peer_connected=false;session._authenticated=false
	session.count=2;session.disconnected=[];session.room_code="CREW42";session.short_room_code="";session.relay_url="";session.connection_hint="";session.error_message=""
	view.size=Vector2i(1440,900);L.set_locale("de",false);game.hud._locale_changed("de");await frames();panel=game.hud.network_panel
	panel.code_field.text="";panel.restore_connection_preferences({"server":""});panel._refresh()
	# Exercise the actual HUD RAM-draft lifecycle, including legacy migration.
	panel.show_server_options=true;panel._toggle_connection_mode()
	await friends();panel=await lobby()
	check(panel.direct_mode and panel.server_field.text.is_empty() and panel.show_server_options,"An explicit Direct choice survives a real lobby→friends→lobby rebuild")
	panel._toggle_connection_mode();await friends();panel=await lobby()
	check(not panel.direct_mode and not panel.server_field.text.is_empty(),"An explicit Online choice survives a real lobby→friends→lobby rebuild")
	panel.server_field.text="wss://custom.example/ws";await friends();panel=await lobby()
	check(panel.server_field.text=="wss://custom.example/ws" and not panel.direct_mode,"A custom relay draft survives real navigation")
	game.hud._network_ui_draft.erase("connection_mode");game.hud._network_ui_draft.server=""
	game.hud._open_social();await frames();game.hud._network_ui_draft.erase("connection_mode");game.hud._network_ui_draft.server=""
	panel=await lobby()
	check(not panel.direct_mode and not panel.server_field.text.is_empty(),"An actual legacy empty HUD draft migrates when the lobby is rebuilt")
	session.active=true;session.state="lobby";session.is_host=true;session.relay_url="";panel._refresh()
	await friends();panel=await lobby()
	check(panel.direct_mode and panel.server_field.text.is_empty() and session.relay_url.is_empty(),"A friends excursion cannot switch a live direct host to the new relay default")
	session.active=false;session.state="offline";panel.show_server_options=false;panel.restore_connection_preferences({"server":""});panel._refresh()
	return panel

func failed_join_gallery(panel: Control) -> void:
	for resolution in [Vector2i(960,600),Vector2i(1440,900)]:
		view.size=resolution;await frames()
		for locale in ["de","en"]:
			L.set_locale(locale,false);game.hud._locale_changed(locale);await frames();panel=game.hud.network_panel
			session.active=true;session.is_host=false;session.local_player_id=2;session.state="error";session.peer_connected=false;session._authenticated=false
			session.count=2;session.room_code="CACHED-ROOM";session.short_room_code="";session.relay_url=""
			session.connection_hint="Direkte Verbindung zum Gastgeber wird aufgebaut.";session.error_message="Der Gastgeber konnte nicht kontaktiert werden."
			panel.code_field.text="ABC234";panel.server_field.text="wss://bunkercrew.vibechain.rocks/ws";panel._refresh()
			check(panel._member_count()==0 and panel.crew_status()==L.text("Kein aktiver Raum"),locale+" terminal failure never claims an active room or host")
			check(panel.crew_buttons.all(func(button):return button.disabled) and panel.character_buttons.all(func(button):return button.disabled) and panel.chat_button.disabled,locale+" failed unauthenticated seats have no player actions")
			check(panel.connection_route_text()==L.text("Direkte Verbindung") and panel.character_heading_text()==L.text("Deine Figur · Platz noch offen"),locale+" terminal failure retains its actual attempted route and unassigned seat")
			check(panel._connection_hint_text()==L.text("Der Gastgeber kann einen neuen Online-Raum über Relay erstellen. Direkte Internetverbindungen benötigen eine Router-Freigabe."),locale+" terminal failure gives a truthful new-relay-room alternative")
			check(not panel._connection_hint_text().contains(L.text("Direkte Verbindung zum Gastgeber wird aufgebaut.")),locale+" terminal failure removes the stale connecting claim")
			check(not panel.connection_mode_button.disabled and panel.server_field.editable,locale+" terminal failure unlocks the next attempt's connection settings")
			check(panel.start_button.visible and not panel.start_button.disabled and panel.start_button.text==L.text("Erneut beitreten"),locale+" terminal failure exposes the actual retry action")
			if DisplayServer.get_name()!="headless": await capture("join-failed",false,PENDING_OUTPUT)

func capture_baseline(id: String,current: Control,kind: String) -> void:
	var baseline: Control=load(OUTPUT+"baseline_"+kind+"_panel.gd").new()
	baseline.game=game;baseline.hud=game.hud
	current.hide();game.hud.canvas.add_child(baseline)
	if kind=="social": baseline.bind_social(service)
	await capture(id,true)
	game.hud.canvas.remove_child(baseline);baseline.queue_free();current.show();await frames()

func gallery() -> void:
	service.friends=[];service.requests=[];service.outgoing_requests=[];service.pending_friend_requests={};service.blocked=[]
	for index in 8: session.row("Wir halten zusammen!",index+1,"","Ivo")
	for resolution in [Vector2i(960,600),Vector2i(1920,1080)]:
		view.size=resolution;view.size_2d_override=Vector2i(1600,900) if resolution.x>=1920 else Vector2i(1440,900);await frames(6)
		for language in ["de","en"]:
			L.set_locale(language,false);game.hud._locale_changed(language);await frames()
			service.connection_state="online";service.server_url="wss://relay.example/social";service.friends=[];service.requests=[];service.outgoing_requests=[];service.blocked=[];service.error_message=""
			var panel: Control=await lobby();session.active=false;session.state="offline";session.peer_connected=false;panel._refresh();await capture("lobby-offline")
			session.active=true;session.state="connecting";panel._refresh();await capture("lobby-connecting")
			session.active=false;session.state="error";session.error_message="Bitte den vollständigen Beitrittscode eingeben.";panel._refresh();await capture("lobby-error")
			host(2);panel._refresh();await capture("lobby-host")
			session.short_room_code="ABC234";panel._refresh();await capture("lobby-short-code");session.short_room_code="";panel._refresh()
			session.is_host=false;session.local_player_id=2;panel._refresh();await capture("lobby-guest")
			host(4);panel._refresh();await capture("lobby-full")
			if resolution.x==1920: await capture_baseline("before-lobby-full",panel,"network")
			await open_member(panel);await capture("crew-actions");await close_popup(panel)
			panel._open_member(2);panel.member_menu.id_pressed.emit(3);await close_popup(panel);game.hud.chat_panel.input_field.text="Wir halten zusammen! Ω";await capture("private-chat");game.hud.chat_panel.close()
			game.hud.chat_panel.open();game.hud.chat_panel.input_field.text="Grüße an die Crew Ω";await capture("crew-chat");game.hud.chat_panel.close()
			service.friends=[{"code":"ABCDEFGH2345","name":"Alex Ω","status":"playing","environment":"mountain_pass","joinable":false},{"code":"BCDEFGHJ3456","name":"Rae","status":"offline","environment":"","joinable":false}]
			service.requests=[{"code":"CDEFGHJK4567","name":"Mika"}];service.outgoing_requests=[{"code":"EFGHJKLM6789","name":"Tessa"}];service.blocked=[{"code":"DEFGHJKL5678","name":"Blocked"}]
			service.invitations=[{"id":"a12b34c56d78e90f1234567890abcdef","name":"Alex Ω","from_code":"ABCDEFGH2345","room_code":"CREW42","relay_url":"wss://relay.example/ws","expires":Time.get_unix_time_from_system()+120.0}]
			var social: Control=await friends();service.connection_state="offline";service.server_url="";social.server_field.text="";social._signature="";social._refresh();await capture("friends-offline")
			service.connection_state="online";service.server_url="wss://relay.example/social";social.server_field.text=service.server_url;social._signature="";social._refresh();await capture("friends-online")
			if resolution.x==1920: await capture_baseline("before-friends-online",social,"social")
			social.contact_buttons["ABCDEFGH2345"].pressed.emit();await capture("friend-actions");social.contact_menu.hide();await frames()
			social.select_tab("requests");await capture("friend-requests")
			social.select_tab("invitations");await capture("friend-invitations")
			social.select_tab("blocked");await capture("friend-blocked")
			social.select_tab("friends");social._confirm("remove","ABCDEFGH2345");await capture("friend-remove-confirm");social._cancel_confirmation();game.hud._close_social();await frames()
