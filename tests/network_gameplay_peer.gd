class_name BetaNetworkGameplayCheck
extends SceneTree
## Actual game in one of two OS processes. Coordination files contain barriers
## and expected scalar values only; guest gameplay state arrives over ENet.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OPTIONS := {"environment":"sector07","build_type":"workshop","position":"left"}
var game
var role := ""
var prefix := ""
var done := false
var failures := 0
var checks := 0
var started_at := 0
var scenery_index := -1
var overall_timeout_ms := 38000

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	_run.call_deferred()

func _run() -> void:
	role = OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix = OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	if role not in ["host","guest"] or prefix.is_empty() or "--no-upnp" not in OS.get_cmdline_user_args():
		await finish(false,"fixture needs role/path and --no-upnp")
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.hud.overlay = "network"
	if not OS.get_environment("LASTSHIFT_TEST_PORT").is_empty():
		game.network.listen_port = OS.get_environment("LASTSHIFT_TEST_PORT").to_int()
	if not OS.get_environment("LASTSHIFT_TEST_DISCOVERY_PORT").is_empty():
		game.network.lan_discovery_port = OS.get_environment("LASTSHIFT_TEST_DISCOVERY_PORT").to_int()
		game.network.lan_discovery_targets.assign(["127.0.0.1"])
	if role=="host": await host_run()
	else: await guest_run()

func refresh_game() -> void:
	if is_instance_valid(current_scene):
		game = current_scene
	else:
		game = null

func check(value: bool,label: String) -> bool:
	checks += 1
	if value:
		print("GAMEPLAY_CHECK ",role," ",label)
	else:
		failures += 1
		push_error("GAMEPLAY_CHECK_FAILED %s %s"%[role,label])
	return value

func path(stage: String) -> String:
	return prefix+"."+stage+".json"

func publish(stage: String,values: Dictionary={}) -> void:
	var file := FileAccess.open(path(stage)+".tmp",FileAccess.WRITE)
	if file==null:
		check(false,"could not publish "+stage)
		return
	var payload := values.duplicate(true)
	payload.ready = true
	file.store_string(JSON.stringify(payload))
	file.close()
	DirAccess.rename_absolute(path(stage)+".tmp",path(stage))

func read_stage(stage: String) -> Dictionary:
	if not FileAccess.file_exists(path(stage)): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path(stage)))
	return value if value is Dictionary else {}

func delay(seconds: float) -> void:
	var until := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<until and not done:
		await process_frame
		refresh_game()

func capture_world() -> void:
	if OS.get_environment("LASTSHIFT_NETWORK_CAPTURE")!="1": return
	if not check(DisplayServer.get_name()!="headless","requested capture uses an actual renderer"): return
	await process_frame
	await RenderingServer.frame_post_draw
	var destination := "res://artifacts/network/gameplay-%s.png"%role
	check(root.get_texture().get_image().save_png(destination)==OK,"actual %s viewport captures replicated health, cargo and enemy"%role)

func wait_for(predicate: Callable,label: String,timeout: float=8.0) -> bool:
	print("GAMEPLAY_WAIT ",role," ",label)
	var deadline := Time.get_ticks_msec()+int(timeout*1000)
	while not done:
		refresh_game()
		if is_instance_valid(game) and game.network.world!=null and not str(game.network.world.last_error).is_empty():
			check(false,"snapshot rejected while "+label+": "+str(game.network.world.last_error))
			return false
		if is_instance_valid(game) and predicate.call(): return true
		if Time.get_ticks_msec()>deadline or Time.get_ticks_msec()-started_at>overall_timeout_ms:
			var status := str(game.network.state)+"; error="+str(game.network.error_message) if is_instance_valid(game) else "scene unavailable"
			if is_instance_valid(game) and game.network.world!=null and "last_error" in game.network.world:
				status += "; world="+str(game.network.world.last_error)
			check(false,"timeout: "+label+"; state="+status)
			return false
		if is_instance_valid(game) and game.network.state=="error":
			check(false,"session error while "+label+": "+str(game.network.error_message))
			return false
		await process_frame
	return false

func barrier(stage: String,timeout: float=8.0) -> bool:
	return await wait_for(func(): return not read_stage(stage).is_empty(),stage,timeout)

func playing() -> bool:
	return is_instance_valid(game) and game.started and game.network.state=="playing" and game.network.peer_connected and not game.network._loading and not paused

func host_run() -> void:
	game.hud.scenario_options = OPTIONS.duplicate()
	game.network.host_room("")
	if not check(game.network.state=="lobby","direct host opens without UPnP"):
		await finish(false,"host creation failed")
		return
	game.network.send_command("character",{"id":"branko"})
	publish("room",{"code":game.network.room_code})
	if not await wait_for(func(): return game.network.peer_connected and game.selected_characters.slice(0,2)==["branko","ivo"],"guest authentication and identity"):
		await finish(false,"lobby failed")
		return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(func(): return playing() and game.network.sent_snapshots>=3,"host started and snapshots sent") or not await barrier("guest_started"):
		await finish(false,"start failed")
		return
	check(game.players.size()==2 and game.players[0].character_id=="branko" and game.players[1].character_id=="ivo","both actual selected workers spawn")
	game.rounds.running = false
	game.players[0].global_position = Vector2(850,430)
	game.players[1].global_position = Vector2(1030,430)
	for worker in game.players:
		worker.velocity = Vector2.ZERO
		worker.inventory.clear()
	await delay(0.25)
	var host_x: float = game.players[0].global_position.x
	var guest_x: float = game.players[1].global_position.x
	publish("baseline",{"host_x":host_x,"guest_x":guest_x})
	if not await barrier("movement_released"):
		await finish(false,"guest input missing")
		return
	await delay(0.25)
	var moved_x: float = game.players[1].global_position.x
	check(moved_x-guest_x>35.0,"guest WASD moves authoritative P2 more than 35 pixels")
	check(absf(game.players[0].global_position.x-host_x)<1.0,"guest WASD never moves authoritative P1")
	await delay(0.25)
	check(absf(game.players[1].global_position.x-moved_x)<1.0 and absf(game.players[1].velocity.x)<0.1,"released guest input stops the authoritative worker")
	publish("movement_verified",{"guest_x":game.players[1].global_position.x})
	if not await barrier("guest_paused") or not await wait_for(func(): return paused and game.network.match_paused,"shared pause on host"):
		await finish(false,"pause failed")
		return
	var elapsed_before: float = game.elapsed
	await delay(0.2)
	check(is_equal_approx(game.elapsed,elapsed_before),"guest pause freezes the host simulation clock")
	publish("host_paused")
	if not await barrier("guest_resumed") or not await wait_for(func(): return not paused and not game.network.match_paused,"host resumes"):
		await finish(false,"resume failed")
		return
	publish("fire_ready")
	if not await barrier("guest_fired"):
		await finish(false,"firing input missing")
		return
	await delay(0.2)
	var host_weapon = game.players[0].get_node("WorkerWeapon")
	var guest_weapon = game.players[1].get_node("WorkerWeapon")
	check(guest_weapon.current_ammo()<30 and guest_weapon.current_ammo()>=27,"guest mouse fire spends finite P2 ammunition on the host")
	check(host_weapon.current_ammo()==30,"guest fire cannot spend P1 ammunition")
	publish("fire_verified",{"ammo":guest_weapon.current_ammo()})
	if not await barrier("guest_ammo_seen"):
		await finish(false,"ammo replication failed")
		return
	game.players[1].hp = 67.0
	game.players[1].inventory = {"ore":3,"steel":2}
	game.players[1].selected_kind = "ore"
	game.players[0].progression.skill_points = 1
	game.players[1].progression.skill_points = 2
	var enemy = game.ENEMY.instantiate()
	enemy.kind = "runner"
	enemy.game = game
	enemy.position = Vector2(1400,430)
	game.add_child(enemy)
	enemy.hp = 77.0
	enemy.max_hp = 77.0
	enemy.set_physics_process(false)
	var props = game.scenery.props_layer
	for entry in props.entries:
		if entry.kind=="tree" and entry.initial_state=="intact":
			scenery_index = int(entry.index)
			break
	check(scenery_index>=0 and props.reactions.damage_entry(scenery_index,200.0,"arcgun",props.reactions.target_point(scenery_index),Vector2.RIGHT),"host creates a charred broken tree through the actual damage controller")
	publish("mutation_prepared",{"prop_index":scenery_index})
	if not await barrier("mutation_seen"):
		await finish(false,"world replication failed")
		return
	await capture_world()
	if not await barrier("skills_sent") or not await wait_for(func(): return int(game.players[1].progression.skills.engineering)==1,"owned skill command"):
		await finish(false,"world/skill replication failed")
		return
	check(game.players[0].progression.skill_points==1 and int(game.players[0].progression.skills.combat)==0,"host rejects guest spending P1's personal skill point")
	check(game.players[1].progression.skill_points==1,"guest spends exactly one of their own skill points")
	publish("skills_verified")
	if not await barrier("guest_skills_seen"):
		await finish(false,"skill replication missing")
		return
	var session_id: int = game.network.get_instance_id()
	var scene_id: int = game.get_instance_id()
	var token: String = game.network._guest_token
	var sent_before: int = game.network.sent_snapshots
	publish("disconnecting")
	game.network.transport.disconnect_guest()
	if not await wait_for(func(): return game.network.state=="reconnecting" and paused,"real transport loss pauses host"):
		await finish(false,"disconnect did not pause")
		return
	check(game.network.remote_input.is_empty(),"real disconnect clears held remote actions")
	publish("host_disconnected")
	if not await wait_for(func(): return playing() and game.network.sent_snapshots>=sent_before+3,"automatic authenticated reconnect",12.0) or not await barrier("guest_reconnected"):
		await finish(false,"reconnect failed")
		return
	check(game.get_instance_id()==scene_id and game.network.get_instance_id()==session_id,"reconnection preserves the host's actual world and session")
	check(game.players[1].hp==67 and int(game.players[1].inventory.get("ore",0))==3 and int(game.players[1].progression.skills.engineering)==1,"reconnect retains authoritative health, cargo and progress")
	check(game.network._guest_token==token,"reconnect retains the authenticated guest identity")
	check(bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("broken",false)),"reconnection preserves authoritative scenery damage")
	enemy.queue_free()
	publish("enemy_removed")
	if not await barrier("enemy_removal_seen"):
		await finish(false,"despawn replication failed")
		return
	var generation: int = game.network._generation
	publish("rematch_starting")
	game.network.restart_match()
	if not await wait_for(func(): return is_instance_valid(game) and game.get_instance_id()!=scene_id and playing() and game.network.sent_snapshots>=sent_before+6,"host rematch after real scene reload",12.0) or not await barrier("guest_rematch_seen",12.0):
		await finish(false,"rematch failed")
		return
	game.rounds.running = false
	check(game.network.get_instance_id()==session_id and game.network._guest_token==token and game.network._generation==generation+1,"rematch keeps the authenticated session and advances its generation")
	check(game.players.size()==2 and game.players[1].hp==90 and game.players[1].inventory.is_empty() and int(game.players[1].progression.skills.engineering)==0,"rematch starts two fresh workers with the chosen identities")
	check(not bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("broken",true)),"rematch rebuilds previously damaged scenery")
	publish("host_passed",{"checks":checks,"failures":failures})
	if not await barrier("guest_passed"):
		await finish(false,"guest final verification missing")
		return
	publish("finish")
	await finish(failures==0,"authoritative movement, combat, snapshots, reconnect and rematch")

func guest_run() -> void:
	var room := read_stage("room")
	game.network.join_room("",str(room.get("code","")))
	if not await wait_for(func(): return game.network.state=="lobby" and game.network.peer_connected,"guest joins"):
		await finish(false,"join failed")
		return
	game.network.send_command("character",{"id":"ivo"})
	if not await wait_for(func(): return playing() and game.network.received_snapshots>=3,"guest receives live world",12.0):
		await finish(false,"world start failed")
		return
	check(game.players.size()==2 and game.players[0].character_id=="branko" and game.players[1].character_id=="ivo","guest sees both selected live identities")
	check(not game.players[0].is_physics_processing() and not game.players[1].is_physics_processing(),"guest player replicas do not run a second authoritative simulation")
	publish("guest_started")
	if not await barrier("baseline"):
		await finish(false,"host baseline missing")
		return
	var baseline := read_stage("baseline")
	if not await wait_for(func(): return absf(game.players[1].global_position.x-float(baseline.guest_x))<3.0,"initial host position replicated"):
		await finish(false,"initial player replication failed")
		return
	Input.action_press("p1_right")
	await delay(0.55)
	Input.action_release("p1_right")
	publish("movement_released")
	if not await barrier("movement_verified"):
		await finish(false,"movement verification missing")
		return
	var movement := read_stage("movement_verified")
	if not await wait_for(func(): return absf(game.players[1].global_position.x-float(movement.guest_x))<3.0,"authoritative movement returned to guest"):
		await finish(false,"moved replica missing")
		return
	check(game.players[1].global_position.x-float(baseline.guest_x)>35 and absf(game.players[0].global_position.x-float(baseline.host_x))<2,"guest sees their own input result and the unchanged host")
	game.network.pause_match(true)
	if not await wait_for(func(): return paused and game.network.match_paused,"guest receives shared pause"):
		await finish(false,"pause acknowledgement missing")
		return
	publish("guest_paused")
	if not await barrier("host_paused"):
		await finish(false,"host pause missing")
		return
	game.network.pause_match(false)
	if not await wait_for(func(): return not paused and not game.network.match_paused,"shared resume"):
		await finish(false,"resume acknowledgement missing")
		return
	publish("guest_resumed")
	if not await barrier("fire_ready"):
		await finish(false,"fire phase missing")
		return
	Input.action_press("p1_fire")
	await delay(0.18)
	Input.action_release("p1_fire")
	publish("guest_fired")
	if not await barrier("fire_verified"):
		await finish(false,"host firing check missing")
		return
	var ammo := int(read_stage("fire_verified").ammo)
	if not await wait_for(func(): return game.players[1].get_node("WorkerWeapon").current_ammo()==ammo,"ammo snapshot"):
		await finish(false,"ammo snapshot missing")
		return
	check(game.players[0].get_node("WorkerWeapon").current_ammo()==30 and ammo<30,"guest receives only their own authoritative ammunition expenditure")
	publish("guest_ammo_seen")
	if not await barrier("mutation_prepared") or not await wait_for(func(): return game.players[1].hp==67 and int(game.players[1].inventory.get("ore",0))==3 and int(game.players[1].inventory.get("steel",0))==2 and get_nodes_in_group("enemies").any(func(actor):return actor.kind=="runner" and actor.hp==77),"health/cargo/enemy snapshots"):
		await finish(false,"prepared state failed to replicate")
		return
	check(game.players[1].selected_kind=="ore" and get_nodes_in_group("enemies").size()==1,"real host-created cargo selection and enemy appear without local creation")
	scenery_index = int(read_stage("mutation_prepared").get("prop_index",-1))
	if not await wait_for(func(): return bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("broken",false)),"scenery damage arrives over ENet"):
		await finish(false,"scenery state failed to replicate")
		return
	check(bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("charred",false)) and game.scenery.props_layer.reactions.replica_only,"guest receives the charred tree and retains presentation-only authority")
	await capture_world()
	publish("mutation_seen")
	game.network.send_command("skill",{"id":"combat","player_id":1})
	game.network.send_command("skill",{"id":"engineering","player_id":2})
	publish("skills_sent")
	if not await barrier("skills_verified") or not await wait_for(func(): return int(game.players[1].progression.skills.engineering)==1,"owned skill replicated"):
		await finish(false,"skill state missing")
		return
	check(int(game.players[0].progression.skills.combat)==0 and game.players[0].progression.skill_points==1,"rejected foreign purchase never changes guest's view of P1")
	publish("guest_skills_seen")
	var session_id: int = game.network.get_instance_id()
	var scene_id: int = game.get_instance_id()
	var token: String = game.network._client_token
	var received_before: int = game.network.received_snapshots
	if not await barrier("disconnecting") or not await wait_for(func(): return game.network.state=="reconnecting" and paused,"guest detects real transport loss"):
		await finish(false,"real disconnect not observed")
		return
	check(game.network._client_token==token and not token.is_empty(),"guest retains its resume token across actual transport loss")
	if not await wait_for(func(): return playing() and game.network.received_snapshots>=received_before+3,"guest automatic reconnect",12.0):
		await finish(false,"guest reconnect failed")
		return
	check(game.get_instance_id()==scene_id and game.network.get_instance_id()==session_id,"guest reconnect preserves local scene/session identity")
	check(game.players[1].hp==67 and int(game.players[1].inventory.get("ore",0))==3 and int(game.players[1].progression.skills.engineering)==1,"resumed snapshots preserve the existing run")
	check(bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("broken",false)) and bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("charred",false)),"guest reconnect preserves the broken charred tree")
	publish("guest_reconnected")
	if not await barrier("enemy_removed") or not await wait_for(func(): return get_nodes_in_group("enemies").is_empty(),"host despawn"):
		await finish(false,"enemy removal not replicated")
		return
	check(get_nodes_in_group("enemies").is_empty(),"host deleting an enemy removes its client replica")
	publish("enemy_removal_seen")
	if not await barrier("rematch_starting"):
		await finish(false,"rematch phase missing")
		return
	received_before = game.network.received_snapshots
	if not await wait_for(func(): return is_instance_valid(game) and game.get_instance_id()!=scene_id and playing() and game.network.received_snapshots>=received_before+3,"guest full scene rematch",12.0):
		await finish(false,"guest rematch failed")
		return
	check(game.network.get_instance_id()==session_id and game.network._client_token==token,"guest rematch retains its socket session and authenticated identity")
	check(game.players.size()==2 and game.players[1].character_id=="ivo" and game.players[1].hp==90 and game.players[1].inventory.is_empty() and int(game.players[1].progression.skills.engineering)==0,"guest receives a fresh rematch with both existing identity choices")
	check(not bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("broken",true)) and not bool(game.scenery.props_layer.reactions.state_for(scenery_index).get("charred",true)),"guest rematch receives fresh scenery without old burns")
	publish("guest_rematch_seen")
	if not await barrier("host_passed"):
		await finish(false,"host final verification missing")
		return
	publish("guest_passed",{"checks":checks,"failures":failures})
	if not await barrier("finish"):
		await finish(false,"completion barrier missing")
		return
	await finish(failures==0,"replicas follow authoritative simulation through reconnect and rematch")

func finish(success: bool,detail: String) -> void:
	if done: return
	done = true
	Input.action_release("p1_right")
	Input.action_release("p1_fire")
	print("NETWORK_GAMEPLAY_PASS " if success else "NETWORK_GAMEPLAY_FAIL ",role," checks=",checks," failures=",failures," ",detail)
	refresh_game()
	if is_instance_valid(game):
		game.network.leave()
		paused = false
		if not await CLEANUP.free_scene(game,self): success = false
	quit(0 if success else 1)
