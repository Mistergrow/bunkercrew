extends "res://tests/online_ui_review_test.gd"
## Actual controls, popup and session transitions; all network/service nodes are
## offline probes. Native captures use the unchanged game art and HUD routes.
const FOLLOWUP_OUTPUT := "res://artifacts/hardening-followup/online-ui/"
const FRIEND := "ABCDEFGH2345"
var replacements: Array[Node] = []

func prepare(state: String="offline") -> Control:
	game.network=session
	game.hud.chat_panel.bind_network(session)
	game.hud.chat_panel.close()
	session.active=state!="offline";session.is_host=state=="offline";session.state=state;session.local_player_id=1 if state=="offline" else 2
	session.peer_connected=false;session._authenticated=false;session.count=2;session.disconnected=[];session._short_resolution=""
	session.muted.clear();session.blocked.clear()
	session.room_code="CACHED-ROOM";session.short_room_code="";session.relay_url="";session.connection_hint="Direkte Verbindung zum Gastgeber wird aufgebaut."
	session.error_message="Der Gastgeber konnte nicht kontaktiert werden." if state=="error" else ""
	session.chat_pending=false;session.chat_pending_text="";session.chat_pending_draft="";session.chat_error="";session.chat_draft="";session.chat_history=[]
	service.connection_state="online";service.server_url="wss://relay.example/social";service.error_message=""
	service.friends=[{"code":FRIEND,"name":"Alex Ω","status":"menu","environment":""}]
	service.requests=[];service.outgoing_requests=[];service.pending_friend_requests={};service.blocked=[];service.invitations=[]
	var panel: Control=await lobby()
	panel.code_field.text="ABC234";panel._refresh();await frames()
	return panel

func snapshot(id: String) -> void:
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless": await capture(id,false,FOLLOWUP_OUTPUT)

func type_text(field: LineEdit,value: String) -> void:
	field.grab_focus();await frames()
	for character in value:
		for down in [true,false]:
			var event := InputEventKey.new()
			event.keycode=character.unicode_at(0) as Key;event.physical_keycode=event.keycode
			event.unicode=character.unicode_at(0);event.pressed=down
			view.push_input(event,true);await process_frame
	await frames()

func clear_text(field: LineEdit) -> void:
	field.grab_focus();field.caret_column=field.text.length();await frames()
	for unused in field.text.length(): await key(KEY_BACKSPACE)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	AudioServer.set_bus_mute(0,true);L.set_locale("de",false)
	view=SubViewport.new();view.size=Vector2i(1440,900);view.size_2d_override=Vector2i(1440,900);view.size_2d_override_stretch=true;view.gui_embed_subwindows=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate();view.add_child(game);await frames(6)
	actual_network=game.network;actual_social=game.social
	check(not actual_network.active and not game.microphone.capturing,"Fresh actual scene opens neither transport nor microphone")
	session=CrewSession.new();service=Base.SocialProbe.new();view.add_child(session);view.add_child(service)
	game.network=session;game.social=service;game.hud.chat_panel.bind_network(session)
	for resolution in [Vector2i(960,600),Vector2i(1440,900)]:
		view.size=resolution
		for language in ["de","en"]:
			L.set_locale(language,false);game.hud._locale_changed(language);await frames()
			var label := "%d-%s" % [resolution.x,language]
			var panel: Control=await prepare()
			check(not panel.start_button.visible and panel._member_count()==0,label+" fresh offline room has no match-start or pending-join claim")
			await snapshot("offline-room")
			panel=await prepare("error")
			check(panel.start_button.visible and not panel.start_button.disabled and panel.start_button.text==L.text("Erneut beitreten"),label+" terminal join error offers an enabled localized retry")
			check(panel.chat_button.disabled and panel.scene_button.disabled and panel._member_count()==0,label+" retry cannot grant player or host actions")
			await snapshot("failed-join-retry")
			var before: int=session.calls.size()
			await click(panel.start_button)
			check(session.calls.slice(before)==[["join","wss://bunkercrew.vibechain.rocks/ws","ABC234"]],label+" actual retry click submits the preserved invitation exactly once")
			await clear_text(panel.code_field)
			check(panel.start_button.disabled,label+" an empty retry cannot be submitted")
			panel.start_button.pressed.emit();check(session.calls.size()==before+1,label+" empty retry callback has no transport action")
			panel=await prepare("connecting")
			before=session.calls.size();panel._host();panel._join();panel._primary_action();panel._change_capacity()
			check(session.calls.size()==before and panel.start_button.disabled,label+" active connection callbacks cannot replace an in-progress transport")
			host(2);panel._refresh();before=session.calls.size();panel._host();panel._join()
			check(session.calls.size()==before,label+" live lobby callbacks cannot replace an authenticated room")
			check(not panel._connection_hint_text().contains(L.text("Direkte Verbindung zum Gastgeber wird aufgebaut.")) and panel._connection_hint_text().begins_with(L.text("Direkte Verbindung")),label+" a confirmed welcome replaces a stale direct-connection progress hint with the actual route")
			await open_member(panel)
			session.muted[2]=true;session.blocked[2]=true;session.changed.emit();await frames()
			check(panel.member_menu.visible and panel.member_menu.get_item_text(menu_item(panel,1))==L.text("Stummschaltung aufheben") and panel.member_menu.get_item_text(menu_item(panel,2))==L.text("Blockierung aufheben"),label+" an open player popup updates current mute/block actions")
			check(panel.member_menu.is_item_disabled(menu_item(panel,3)) and panel.member_menu.is_item_disabled(menu_item(panel,4)),label+" blocking immediately removes stale chat and friend access from the open player popup")
			await snapshot("player-popup-blocked")
			session.disconnected=[2];session.changed.emit();await frames()
			check(not panel.member_menu.visible and panel.leave_button.has_focus(),label+" a departed player closes the old popup and restores a live focus target")
			session.disconnected=[];session.muted.clear();session.blocked.clear();session.changed.emit();await frames();await open_member(panel)
			var original_key: String=session.member_keys["2"]
			session.member_keys["2"]="replacement-player";session.changed.emit();await frames()
			check(not panel.member_menu.visible,label+" replacing the player in a crew slot closes that previous identity's actions")
			session.member_keys["2"]=original_key
			panel=await prepare("error")
			service.invitations=[{"id":"a12b34c56d78e90f1234567890abcdef","name":"Alex Ω","from_code":FRIEND,"room_code":"CREW42","relay_url":"wss://relay.example/ws","expires":Time.get_unix_time_from_system()+120.0}]
			var social: Control=await friends();social.select_tab("invitations");await frames()
			check(social._can_join() and not social.row_buttons[service.invitations[0].id][0].disabled,label+" terminal join error does not prevent a new friend invitation")
			await snapshot("invitation-after-failure")
			before=session.calls.size();await click(social.row_buttons[service.invitations[0].id][0])
			check(session.calls.slice(before)==[["join","wss://relay.example/ws","CREW42"]],label+" actual invitation click joins its correct destination exactly once")
			panel=await prepare();host(2)
			social=await friends();social.friend_field.text="";await frames()
			check(social.add_button.disabled,label+" empty friend code cannot create a request")
			var service_before: int=service.calls.size();social._add_friend()
			check(service.calls.size()==service_before,label+" empty add-friend callback has no service action")
			await type_text(social.friend_field,FRIEND);check(social.friend_field.text==FRIEND and not social.add_button.disabled,label+" typing a friend code enables its explicit request action")
			await clear_text(social.friend_field)
			await click(social.contact_buttons[FRIEND]);social.contact_menu.id_pressed.emit(3);social.contact_menu.hide();await frames()
			check(social.confirmation.visible,label+" friend removal remains an explicit confirmation")
			service.friends[0].status="playing";service.changed.emit();await frames()
			await snapshot("friend-confirm-after-update")
			await key(KEY_ESCAPE)
			check(not social.confirmation.visible and social.contact_buttons[FRIEND].has_focus(),label+" cancel after async friend-row replacement restores the current contact focus")
			check(service.calls.size()==service_before,label+" cancel after row replacement does not remove the friend")
			await snapshot("friend-focus-restored")
			await click(social.contact_buttons[FRIEND]);service.connection_state="offline";service.changed.emit();await frames()
			check(social.contact_menu.visible and social.contact_menu.is_item_disabled(social.contact_menu.get_item_index(1)) and social.contact_menu.is_item_disabled(social.contact_menu.get_item_index(3)),label+" an open popup updates invite/remove access after service loss")
			check(not social.contact_menu.is_item_disabled(social.contact_menu.get_item_index(2)),label+" confirmed crew-private chat survives an unrelated friend-service outage")
			await snapshot("friend-popup-offline")
			service.connection_state="online";service.friends[0].status="offline";service.changed.emit();await frames()
			service_before=service.calls.size();social._contact_action(1)
			check(service.calls.size()==service_before and social.contact_menu.is_item_disabled(social.contact_menu.get_item_index(1)),label+" a newly offline contact cannot receive a stale enabled invite action")
			service.server_url="wss://different.example/social";service.changed.emit();await frames()
			check(not social.contact_menu.visible and social._crew_slot_for_friend(FRIEND)==0,label+" changing friend service closes old context and cannot identify a crew friend from another service")
			social._contact_action(3);check(not social.confirmation.visible,label+" stale old-service popup action cannot open a destructive confirmation")
			service.server_url="wss://relay.example/social";service.friends[0].status="menu";service.changed.emit();await frames()
			social.contact_buttons[FRIEND].grab_focus();social._confirm("remove",FRIEND);await frames();service.friends=[];service.changed.emit();await frames()
			await key(KEY_ESCAPE)
			check(social.tab_buttons[social.tab].has_focus(),label+" removing a contact while its confirmation is open falls back to the current tab")
			service.friends=[{"code":FRIEND,"name":"Alex Ω","status":"menu"}];service.changed.emit();await frames()
			social._confirm("block",FRIEND);await frames();service_before=service.calls.size()
			service.server_url="wss://different.example/social";service.changed.emit();await frames()
			await click(social.confirmation.confirm_button)
			check(not social.confirmation.visible and service.calls.size()==service_before,label+" a confirmed action from the old service cannot block a contact in the new service")
			panel=await prepare();host(2);panel=await lobby()
			var chat: Control=game.hud.chat_panel
			var row := {"id":1,"player_id":2,"name":"Alex Ω","text":"Nur für dich Ω","preset":"","time":125.0,"private":true}
			session.chat_history.append(row);session.chat_received.emit(row);await frames()
			check(chat.unread==1 and chat._feed_heading(row).contains(L.text("Privat")),label+" private unread feed carries a localized private marker")
			var long_author := row.duplicate();long_author.name="ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMN"
			check(chat._feed_heading(long_author).find(L.text("Privat"))<chat._feed_heading(long_author).find(long_author.name),label+" long player names cannot push the private marker out of the visible heading")
			await snapshot("private-feed")
			chat.open_private(2);await frames();chat.input_field.text="Pending from old room Ω";chat.send_message();await frames()
			check(chat._pending() and session.chat_pending,label+" prepared old room genuinely has an unacknowledged private send")
			var replacement:=CrewSession.new();replacements.append(replacement);view.add_child(replacement)
			replacement.active=true;replacement.is_host=true;replacement.state="lobby";replacement.local_player_id=1;replacement.peer_connected=true;replacement._authenticated=true
			game.network=replacement;chat.bind_network(replacement);await frames()
			check(not chat._pending() and chat._feed.is_empty() and chat.unread==0,label+" another session discards old receipt/feed state without carrying it to the new room")
			check(session.chat_draft=="Pending from old room Ω",label+" old session retains its exact unsent draft")
			session.chat_send_completed.emit("Pending from old room Ω",true);session.chat_received.emit(row);await frames()
			check(not chat._pending() and chat._feed.is_empty(),label+" late old-room receipts and feed cannot affect the newly bound chat")
			chat.open();await frames();chat.input_field.text="New room message Ω";await frames();await click(chat.send_button)
			check(replacement.calls.has(["chat","New room message Ω"]) and replacement.chat_pending,label+" actual new-room send works despite the old pending receipt")
			await snapshot("new-session-chat")
	game.network=actual_network;game.social=actual_social;game.hud.chat_panel.bind_network(actual_network)
	check(not actual_network.active and not game.microphone.capturing,"Full follow-up keeps actual transport and microphone inactive")
	check(await Cleanup.free_scene(game,self),"Actual scene and all audio resources release cleanly")
	view.queue_free();await frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLLOWUP_OUTPUT))
	var result := {"checks":checks,"failures":failures,"prepared_states":"Real MainScene and native routed HUD; explicit offline service/session probes. No sockets or profile writes.","display_server":DisplayServer.get_name(),"engine_args":Array(OS.get_cmdline_args()),"captures":captures}
	var report := "native-verification.json" if "--capture" in OS.get_cmdline_user_args() else "headless-verification.json"
	FileAccess.open(FOLLOWUP_OUTPUT+report,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ONLINE UI FOLLOWUP: %d/%d checks passed" % [checks-failures,checks]);quit(1 if failures else 0)
