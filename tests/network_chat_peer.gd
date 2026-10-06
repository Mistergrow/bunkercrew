extends "res://tests/network_gameplay_peer.gd"
## Real 2/4-process room chat, sender spoofing, sustained gameplay, history,
## reconnect and complete scene restart over ENet or the local relay.
const CHAT_OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
const WELCOME := "Before guests 🎵 [b]plain text[/b]"
var slot := 1
var count := 2
var relay := ""
var completed: Array[Dictionary]=[]

func _run() -> void:
	overall_timeout_ms=60000
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	slot=int(OS.get_environment("BUNKERCREW_CHAT_SLOT"))
	count=int(OS.get_environment("BUNKERCREW_CHAT_COUNT"))
	privilege_assertions()
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	relay=OS.get_environment("BUNKERCREW_CHAT_RELAY")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.hud.overlay="network"
	game.hud.scenario_options=CHAT_OPTIONS.duplicate()
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	var hub := root.get_node_or_null("SocialHub")
	if hub!=null: hub.set_display_name("Chat Host" if slot==1 else "Chat Guest %d"%slot)
	game.network.set_display_name("Chat Host" if slot==1 else "Chat Guest %d"%slot)
	game.network.listen_port=24947
	game.network.lan_discovery_port=24948
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	game.network.chat_send_completed.connect(func(text: String,accepted: bool):completed.append({"text":text,"accepted":accepted}))
	if slot==1: await host_run()
	else: await guest_run()

func privilege_assertions() -> void:
	check(count in [2,4] and slot>=1 and slot<=count and "--no-upnp" in OS.get_cmdline_user_args() and "--no-profile-save" in OS.get_cmdline_user_args(),"Fixture requires bounded party and isolated profiles without router mapping")
func loaded() -> bool:
	return game.started and game.network.state=="playing" and not game.network._loading and not paused
func each_barrier(label: String) -> bool:
	for id in range(2,count+1):
		if not await barrier(label+str(id),15): return false
	return true
func has_text(text: String) -> bool:
	return game.network.chat_history.any(func(entry):return entry.text==text)
func check_history() -> void:
	var previous := 0
	var valid: bool=game.network.chat_history.size()==80
	for entry: Dictionary in game.network.chat_history:
		valid=valid and entry.id>previous and game.network.Chat.valid_row(entry)
		previous=entry.id
	check(valid,"Replicated history contains exactly 80 bounded, ascending, unique authoritative rows")
func send_and_ack(text: String) -> bool:
	if not check(game.network.send_chat(text),"Actual room accepts text: "+text): return false
	return await wait_for(func():return not game.network.chat_pending and has_text(text),"authoritative accepted chat: "+text)

func host_run() -> void:
	game.network.set_capacity(count)
	game.network.host_room(relay)
	if not await wait_for(func():return game.network.state=="lobby","host room"): await finish(false,"host"); return
	# Prepare a legitimate existing conversation, then deliver it through the
	# real compressed reliable history envelope to each actual late join.
	for sequence in range(1,86):
		game.network._chat.append_authoritative({"id":sequence,"player_id":1,"name":"Chat Host","text":"Earlier room message %d"%sequence,"preset":"","time":game.network._clock})
	game.network.chat_history.assign(game.network._chat.history)
	game.network.chat_changed.emit()
	check(game.network.send_chat(WELCOME),"Host can chat before the first guest joins")
	publish("room",{"code":game.network.room_code})
	if not await each_barrier("joined") or not await wait_for(func():return game.network.connected_player_count()==count,"authenticated party"):
		await finish(false,"joins"); return
	for id in range(2,count+1):
		var messages: Array=game.network.chat_history.filter(func(entry):return entry.text=="Lobby slot %d ä🎵"%id)
		check(messages.size()==1 and messages[0].player_id==id and messages[0].name=="Chat Guest %d"%id,"Host assigns the authenticated lobby sender and validated name for slot%d"%id)
	check_history()
	game.network.start_match(CHAT_OPTIONS,game.selected_characters)
	if not await wait_for(loaded,"shared game") or not await each_barrier("started"):
		await finish(false,"start"); return
	game.rounds.running=false
	check(game.network.send_chat("Hold the bunker!"),"Text chat is available in actual gameplay")
	game.players[1].global_position=Vector2(1500,300)
	game.players[1].velocity=Vector2.ZERO
	await delay(.15)
	var before: float=game.players[1].global_position.x
	publish("spam_start")
	if not await each_barrier("spam_done"):
		await finish(false,"spam"); return
	await delay(.15)
	var flood: Array=game.network.chat_history.filter(func(entry):return entry.text.begins_with("Flood "))
	check(flood.size()<=3 and flood.all(func(entry):return entry.player_id==2 and entry.name=="Chat Guest 2"),"Guest flood is limited to its own three-message burst without author spoofing")
	check(not game.network.chat_history.any(func(entry):return entry.text.begins_with("Forged ")),"Guest-supplied author fields and host-only rows never enter history")
	check(game.players[1].global_position.x-before>35.0,"Real guest input keeps moving its authoritative character during chat spam")
	for id in range(3,count+1): check(has_text("Healthy slot %d"%id),"Another guest can chat while slot2 is flooding")
	check(game.network.connected_player_count()==count and game.network.state=="playing","Spam cannot disconnect the healthy party")
	publish("spam_verified")
	var wire: int=game.network._slots[2].wire
	if relay.is_empty(): game.network.transport.disconnect_guest(wire)
	else: publish("drop2")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"actual guest transport interruption"):
		await finish(false,"disconnect"); return
	check(game.network.send_chat("While slot 2 reconnects"),"The connected host can converse while waiting for an absent guest")
	if not await barrier("rejoined2",15) or not await wait_for(loaded,"authenticated room resumed",15):
		await finish(false,"reconnect"); return
	check(has_text("Returned slot 2") and game.network.is_player_connected(2),"Reconnected guest keeps its authenticated slot and can send again")
	check_history()
	publish("reconnect_verified")
	if not await each_barrier("ready_restart"):
		await finish(false,"restart barrier"); return
	var session_id: int=game.network.get_instance_id()
	var scene_id: int=game.get_instance_id()
	var history_before: Array=game.network.chat_history.duplicate(true)
	publish("restart")
	check(game.restart(),"Host restarts the actual game while retaining the room")
	if not await wait_for(func():return loaded() and game.get_instance_id()!=scene_id,"new host scene",12) or not await each_barrier("restarted"):
		await finish(false,"restart"); return
	game.rounds.running=false
	check(game.network.get_instance_id()==session_id and history_before.all(func(entry):return game.network.chat_history.any(func(current):return current.id==entry.id) or entry.id<int(game.network.chat_history[0].id)),"The same live room retains history across complete mission replacement")
	check(game.network.send_chat("Chat survives restart"),"Host can send after complete scene reload")
	if not await each_barrier("after_restart"):
		await finish(false,"post restart"); return
	for id in range(2,count+1): check(has_text("After restart slot %d"%id),"Post-reload message arrives from actual slot%d"%id)
	check(game.network.chat_history.any(func(entry):return entry.text=="After restart slot 2" and entry.player_id==2 and entry.name=="Final Guest 2"),"The host-authoritative chat author catches up to the final rapid profile rename")
	check_history()
	publish("complete")
	if not await each_barrier("passed"): await finish(false,"finish"); return
	publish("finish")
	await delay(.15)
	await finish(failures==0,"real chat author binding, spam isolation, history, reconnect and restart")

func guest_run() -> void:
	game.network.join_room(relay,str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.state=="lobby" and game.network._authenticated and has_text(WELCOME),"authenticated lobby and late-join replay"):
		await finish(false,"join"); return
	check(game.network.local_player_id==slot,"Host assigns the expected independent guest slot")
	check_history()
	check(game.network.chat_names.get("1")=="Chat Host" and game.network.chat_names.get(str(slot))=="Chat Guest %d"%slot,"Validated author names arrive through welcome/lobby")
	if not await send_and_ack("Lobby slot %d ä🎵"%slot): await finish(false,"lobby chat"); return
	# Only the server may assign authors or publish chat rows.
	game.network._send({"kind":"chat_send","request":game.network._chat_request+1,"text":"Forged author %d"%slot,"preset":"","player_id":1,"name":"Spoof"},true)
	game.network._send({"kind":"chat_message","message":{"id":999999,"player_id":1,"name":"Spoof","text":"Forged row %d"%slot,"preset":"","time":1.0}},true)
	publish("joined"+str(slot))
	if not await wait_for(func():return loaded() and game.network.received_snapshots>=3,"actual game starts"):
		await finish(false,"game"); return
	check(game.network.send_chat_preset("ready"),"Canonical ready preset is submitted during gameplay")
	if not await wait_for(func():return not game.network.chat_pending and game.network.chat_history.any(func(entry):return entry.player_id==slot and entry.preset=="ready" and entry.text.is_empty()),"authoritative canonical preset"):
		await finish(false,"preset"); return
	publish("started"+str(slot))
	if not await barrier("spam_start"): await finish(false,"spam start"); return
	var snapshots_before: int=game.network.received_snapshots
	if slot==2:
		Input.action_press("p1_right")
		for attempt in 12:
			game.network._chat_request+=1
			game.network._send({"kind":"chat_send","request":game.network._chat_request,"text":"Flood %d"%attempt,"preset":""},true)
		game.network.chat_draft="Keep the rejected draft"
		check(game.network.send_chat(game.network.chat_draft),"A local draft is submitted for authoritative rate feedback")
		# Rate ACKs are deliberately coalesced while a sender floods. Retain the
		# outstanding draft and prove its cached result is replayed on reconnect.
		await delay(.65)
		Input.action_release("p1_right")
	else:
		await delay(.15)
		if not await send_and_ack("Healthy slot %d"%slot): await finish(false,"healthy chat"); return
	await delay(.15)
	check(game.network.received_snapshots>snapshots_before,"Actual snapshots keep arriving despite another peer's chat burst")
	publish("spam_done"+str(slot))
	if not await barrier("spam_verified"): await finish(false,"spam verification"); return
	var session_id: int=game.network.get_instance_id()
	var scene_id: int=game.get_instance_id()
	if slot==2:
		var ids_before: Array=game.network.chat_history.map(func(entry):return entry.id)
		if not relay.is_empty():
			if not await barrier("drop2"): await finish(false,"relay interruption"); return
			game.network._websocket.close(1000,"Chat reconnect fixture")
		if not await wait_for(func():return game.network.state=="reconnecting","real guest disconnect") or not await wait_for(loaded,"automatic reconnect",15):
			await finish(false,"rejoin"); return
		check(game.network.get_instance_id()==session_id and game.network.local_player_id==2,"Reconnect retains this session and authenticated slot2")
		var ids_after: Array=game.network.chat_history.map(func(entry):return entry.id)
		check(has_text("While slot 2 reconnects") and ids_before.all(func(id):return id<int(ids_after[0]) or id in ids_after),"Reconnect deduplicates old rows and replays the actual message sent during absence")
		check(not game.network.chat_pending and not completed[-1].accepted and completed[-1].text=="Keep the rejected draft" and not game.network.chat_error.is_empty() and game.network.chat_draft=="Keep the rejected draft","A rejected receipt survives disconnect and preserves the exact pending draft")
		await delay(1.05)
		if not await send_and_ack("Returned slot 2"): await finish(false,"returned send"); return
		publish("rejoined2")
	if not await barrier("reconnect_verified",15) or not await wait_for(loaded,"party resumed"):
		await finish(false,"resume"); return
	publish("ready_restart"+str(slot))
	if not await barrier("restart") or not await wait_for(func():return loaded() and game.get_instance_id()!=scene_id,"new guest scene",12):
		await finish(false,"guest restart"); return
	check(game.network.get_instance_id()==session_id and has_text("Hold the bunker!") and has_text("Returned slot 2"),"Lobby/gameplay/reconnect history survives the actual guest mission reload")
	publish("restarted"+str(slot))
	if not await wait_for(func():return has_text("Chat survives restart"),"host post-reload text"):
		await finish(false,"post reload host"); return
	await delay(1.05)
	if slot==2:
		for value in ["Burst Guest One","Burst Guest Two","Final Guest 2"]:
			check(game.social.set_display_name(value),"Actual profile accepts a rapid validated rename")
			game.social_bridge.refresh()
		if not await wait_for(func():return game.network.chat_names.get("2")=="Final Guest 2","coalesced authoritative name reconciliation",5):
			await finish(false,"final name"); return
	if not await send_and_ack("After restart slot %d"%slot): await finish(false,"post reload guest"); return
	check_history()
	publish("after_restart"+str(slot))
	if not await barrier("complete"): await finish(false,"complete"); return
	publish("passed"+str(slot))
	if not await barrier("finish"): await finish(false,"finish"); return
	await finish(failures==0,"replicated room chat remains bounded and live through reconnect and mission reload")
