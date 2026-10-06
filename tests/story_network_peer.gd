extends "res://tests/network_gameplay_peer.gd"
## Separate opt-in socket proof. Existing gameplay integration stays untouched.
const STORY_OPTIONS := {"environment":"mountain_pass","build_type":"bastion","position":"left"}
const TEST_SOUND := Vector2(1120,399)

func host_run() -> void:
	game.hud.story_selected=true
	game.hud.scenario_options=STORY_OPTIONS.duplicate()
	game.network.host_room("")
	if not check(game.network.state=="lobby","story host creates a real direct ENet lobby"):
		await finish(false,"host failed")
		return
	publish("room",{"code":game.network.room_code})
	if not await barrier("story_lobby"):
		await finish(false,"story lobby not received")
		return
	game.network.start_match(STORY_OPTIONS,game.selected_characters)
	if not await wait_for(func():return playing() and game.network.sent_snapshots>=3,"host story starts") or not await barrier("story_started"):
		await finish(false,"story start failed")
		return
	check(game.story_mode and game.story.enabled and game.network._match_story,"host retains selected story mode in the actual started scene")
	game.rounds.running=false
	game.story.set_process(false)
	game.weather.lightning_enabled=false
	game.story.wall.state=DefenseWall.State.HARD
	game.story.wall.hp=100.0
	game.story.wall.max_hp=100.0
	game.story.wall.collider.disabled=false
	game.story._process(.11)
	if not await barrier("prologue_seen"):
		await finish(false,"prologue snapshot absent")
		return
	game.rounds.wave=4
	game.rounds.phase="build"
	game.story._process(.11)
	game.players[1].position=game.story.relay.position
	game.players[1].inventory={"steel":2}
	for tick in 5: game.story.relay.interact(game.players[1],.1)
	publish("relay_partial")
	if not await barrier("relay_partial_seen"):
		await finish(false,"relay progress absent")
		return
	# Work was released during the network barrier; resume a complete hold.
	for tick in 22: game.story.relay.interact(game.players[1],.1)
	game.weather.lightning_enabled=true
	game.story._process(.11)
	check(game.story.stage==3 and game.players[1].inventory.is_empty() and game.weather.storm_events.serial==1,"real relay payment and objective trigger the authoritative tree strike")
	if not await barrier("relay_complete_seen"):
		await finish(false,"completed act absent")
		return
	game.story.say("core_low")
	var event_serial: int=game.story.serial
	var payload := {"id":"core_low","speaker":"san","player":0,"serial":event_serial,"generation":game.network._generation}
	game.network.queue_event("dialogue",payload)
	game.network.queue_event("dialogue",payload)
	game.audio.cooldowns.clear()
	game.sound_at("explosion",TEST_SOUND)
	publish("events_sent",{"serial":event_serial})
	if not await barrier("events_seen"):
		await finish(false,"local presentation events absent")
		return
	var session_id: int=game.network.get_instance_id()
	var scene_id: int=game.get_instance_id()
	var token: String=game.network._guest_token
	var sent: int=game.network.sent_snapshots
	publish("disconnecting")
	game.network.transport.disconnect_guest()
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"real story transport loss"):
		await finish(false,"disconnect not observed")
		return
	if not await wait_for(func():return playing() and game.network.sent_snapshots>=sent+3,"automatic story reconnect",12.0) or not await barrier("story_reconnected"):
		await finish(false,"story reconnect failed")
		return
	check(game.get_instance_id()==scene_id and game.network.get_instance_id()==session_id and game.network._guest_token==token,"reconnect preserves the authoritative story scene and authentication")
	check(game.story.stage==3 and game.players[1].inventory.is_empty(),"reconnect neither resets the act nor refunds the paid relay")
	var generation: int=game.network._generation
	publish("rematch_starting")
	game.network.restart_match()
	if not await wait_for(func():return game.get_instance_id()!=scene_id and playing(),"host story rematch",12.0) or not await barrier("story_rematch_seen",12.0):
		await finish(false,"story rematch failed")
		return
	check(game.story_mode and game.story.enabled and game.story.stage==0 and game.story.wall.state==DefenseWall.State.EMPTY,"a real scene reload starts a fresh story prologue")
	check(game.network.get_instance_id()==session_id and game.network._generation==generation+1,"story rematch keeps the socket and advances its generation")
	game.network.queue_event("dialogue",{"id":"story_victory","speaker":"san","player":0,"serial":999999,"generation":generation})
	publish("stale_line_sent")
	if not await barrier("stale_line_ignored"):
		await finish(false,"stale generation check absent")
		return
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"guest final state absent")
		return
	publish("finish")
	await finish(failures==0,"story lobby, objective snapshots, events, reconnect and rematch")

func guest_run() -> void:
	game.network.join_room("",str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.state=="lobby" and game.network.peer_connected and game.hud.story_selected,"story lobby selection"):
		await finish(false,"lobby selection absent")
		return
	check(game.hud.story_selected and game.hud.scenario_options.environment=="mountain_pass","actual lobby packet carries story selection and mountain world")
	publish("story_lobby")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=3,"guest receives story world",12.0):
		await finish(false,"guest story start failed")
		return
	check(game.story_mode and game.story.enabled and game.story.stage==0 and game.network._match_story,"actual start packet creates the guest prologue rather than free play")
	publish("story_started")
	if not await wait_for(func():return game.story.stage==1 and game.story.wall.state==DefenseWall.State.HARD,"guest prologue gate"):
		await finish(false,"host wall absent")
		return
	publish("prologue_seen")
	if not await barrier("relay_partial") or not await wait_for(func():return game.story.stage==2 and game.story.relay.progress>.20 and int(game.players[1].inventory.get("steel",0))==2,"live relay work"):
		await finish(false,"live work absent")
		return
	var progress: float=game.story.relay.progress
	for tick in 30: game.story.relay.interact(game.players[1],.1)
	game.story.complete_relay()
	check(game.story.stage==2 and game.story.relay.progress==progress and game.players[1].inventory.steel==2,"guest cannot finish or pay the radio through local method calls")
	check(not game.weather.storm_events.trigger_tree_strike(),"guest cannot create authoritative lightning")
	game.weather.set_reduced_effects(true)
	game.network.pause_match(true)
	if not await wait_for(func():return paused and game.network.match_paused,"shared story pause"):
		await finish(false,"story pause absent")
		return
	# Drain the final in-flight snapshot after the reliable pause packet.
	await delay(.12)
	var paused_elapsed: float=game.elapsed
	await delay(.15)
	check(game.elapsed==paused_elapsed and game.story.stage==2 and game.story.relay.progress==progress,"guest pause holds the real replicated story preparation")
	game.network.pause_match(false)
	if not await wait_for(func():return playing(),"shared story resume"):
		await finish(false,"story resume absent")
		return
	check(game.weather.reduced_effects,"local F3 remains selected across shared pause")
	publish("relay_partial_seen")
	if not await wait_for(func():return game.story.stage==3 and game.players[1].inventory.is_empty() and game.weather.storm_events.serial==1,"radio completion and storm event"):
		await finish(false,"radio completion absent")
		return
	await delay(.5)
	check(game.weather.storm_events.thunder_count==1,"repeated ENet snapshots present a new strike with exactly one thunder")
	check(game.story.relay.progress==0,"complete radio work resets replicated progress")
	publish("relay_complete_seen")
	if not await barrier("events_sent"):
		await finish(false,"events not queued")
		return
	var event_serial:=int(read_stage("events_sent").serial)
	if not await wait_for(func():return game.dialogue._seen.has(event_serial) and game.audio.voices.any(func(voice):return voice.get_meta("kind","")=="explosion" and voice.get_meta("acoustic_source",Vector2.ZERO)==TEST_SOUND),"reliable dialogue and positioned sound events"):
		await finish(false,"event presentation absent")
		return
	var matching:=0
	if not game.dialogue.active.is_empty() and int(game.dialogue.active.serial)==event_serial: matching+=1
	for line in game.dialogue.pending:
		if int(line.serial)==event_serial: matching+=1
	check(matching==1,"three repeated dialogue events become one active or queued authored line")
	check(game.network._events.is_empty(),"received local sound is not re-broadcast to the host")
	publish("events_seen")
	var session_id:int=game.network.get_instance_id()
	var scene_id:int=game.get_instance_id()
	var received:int=game.network.received_snapshots
	if not await barrier("disconnecting") or not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest detects actual socket loss"):
		await finish(false,"loss not observed")
		return
	if not await wait_for(func():return playing() and game.network.received_snapshots>=received+3,"guest reconnects same story",12.0):
		await finish(false,"guest reconnect absent")
		return
	check(game.get_instance_id()==scene_id and game.network.get_instance_id()==session_id and game.story.stage==3 and game.players[1].inventory.is_empty(),"guest reconnect retains the same paid objective and scene")
	check(game.weather.storm_events.thunder_count==1,"reconnect does not replay historical thunder")
	publish("story_reconnected")
	if not await barrier("rematch_starting") or not await wait_for(func():return game.get_instance_id()!=scene_id and playing() and game.network.received_snapshots>=received+5,"guest story rematch",12.0):
		await finish(false,"guest rematch absent")
		return
	check(game.story_mode and game.story.enabled and game.story.stage==0 and game.story.wall.state==DefenseWall.State.EMPTY,"guest receives a new prologue after actual scene reload")
	check(game.weather.storm_events.serial==0 and game.weather.storm_events.thunder_count==0,"new generation has no old lightning or pending thunder")
	publish("story_rematch_seen")
	if not await barrier("stale_line_sent"):
		await finish(false,"old generation event absent")
		return
	await delay(.2)
	check(not game.dialogue._seen.has(999999) and (game.dialogue.active.is_empty() or game.dialogue.active.id!="story_victory"),"an actual delayed event from the previous generation cannot announce victory in the new prologue")
	publish("stale_line_ignored")
	if not await barrier("host_passed"):
		await finish(false,"host did not finish")
		return
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"completion missing")
		return
	await finish(failures==0,"guest story mode, authority, events and recovery")
