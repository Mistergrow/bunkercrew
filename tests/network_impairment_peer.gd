extends "res://tests/network_gameplay_peer.gd"
## Coordination files carry barriers only. All four input and speech streams
## pass through actual ENet sockets, including native reliable retransmission.
const Codec := preload("res://scripts/voice_codec.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
const NetInput := preload("res://scripts/network_input.gd")
var slot := 1
var phase_seconds := 12.0
var voice_active := false
var voice_next := 0
var voice_sent := 0
var tone := PackedByteArray()
var observer: Node
var monitor_edges := false
var edges: Array[int] = [0, 0, 0, 0]
var weapon_changes: Array[int] = [0, 0, 0, 0]
var actions_blocked_by_hit: Array[int] = [0, 0, 0, 0]
var last_weapons: Array[String] = ["rifle", "rifle", "rifle", "rifle"]
var movement_span: Array[float] = [0.0, 0.0, 0.0, 0.0]
var first_positions: Array[float] = [0.0, 0.0, 0.0, 0.0]
var max_decode_queue := 0
var max_voice_queue := 0
var max_transport_backlog := 0
var transport_backlog_started_usec := 0
var max_transport_backlog_seconds := 0.0
var max_poll_packets := 0
var max_poll_scanned := 0
var max_input_edge_queue := 0
var max_snapshot_sequence_gap := 0
var max_websocket_outbound_bytes := 0
var max_websocket_inbound_packets := 0
var movement_ticks: Array[int] = [0, 0, 0, 0]
var state_events: Array[Dictionary] = []
var initial_voice_played := 0
var hit_counts: Dictionary = {"1": 0, "2": 0, "3": 0, "4": 0}
var prior_state := ""
var relay_url := ""
var transport_errors: Array[Dictionary] = []

class Observer extends Node:
	var fixture
	func _process(_delta: float) -> void:
		fixture.poll_voice()
	func _physics_process(_delta: float) -> void:
		fixture.observe()

func _run() -> void:
	overall_timeout_ms = 155000
	Engine.max_fps = 60
	role = OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	slot = OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	prefix = OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	phase_seconds = OS.get_environment("BUNKERCREW_IMPAIRMENT_PHASE_SECONDS").to_float()
	relay_url = OS.get_environment("BUNKERCREW_IMPAIRMENT_RELAY_URL")
	if slot not in [1, 2, 3, 4] or prefix.is_empty() or "--no-upnp" not in OS.get_cmdline_user_args() or "--no-profile-save" not in OS.get_cmdline_user_args():
		await finish(false, "isolated four-process fixture arguments required")
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.hud.overlay = "network"
	game.audio.set_music_volume(0.0)
	game.audio.set_sfx_volume(0.0)
	game.voice.set_enabled(true)
	game.network.listen_port = OS.get_environment("LASTSHIFT_TEST_PORT").to_int()
	game.network.lan_discovery_port = OS.get_environment("LASTSHIFT_TEST_DISCOVERY_PORT").to_int()
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	observer = Observer.new()
	observer.fixture = self
	observer.process_mode = Node.PROCESS_MODE_ALWAYS
	observer.process_physics_priority = 1000
	root.add_child(observer)
	var samples := PackedFloat32Array()
	for index in Codec.FRAMES:
		samples.append(.18 * sin(TAU * float(300 + slot * 110) * index / Codec.RATE))
	tone = Codec.encode(samples)
	if slot == 1:
		game.network.host_room(relay_url)
		if is_instance_valid(game.network.transport):
			game.network.transport.peer_error.connect(func(id: int, message: String): transport_errors.append({"wire": id, "message": message, "at_ms": Time.get_ticks_msec() - started_at}))
		if not await wait_for(func(): return game.network.state == "lobby", "host lobby", 20): await fail_fixture("host"); return
		publish("room", {"invite": game.network._invite_secret, "code": game.network.room_code})
		for id in [2, 3, 4]:
			if not await barrier("joined" + str(id), 30): await fail_fixture("joins"); return
		check(game.network.connected_player_count() == 4, "All four independently authenticated participants join through separate fault proxies")
		game.network.start_match({"environment": "ash_foundry", "build_type": "bastion", "position": "left"}, game.selected_characters)
	else:
		var invitation := JoinCode.invite("127.0.0.1", OS.get_environment("BUNKERCREW_IMPAIRMENT_PROXY_PORT").to_int(), str(read_stage("room").invite))
		if relay_url.is_empty(): game.network.join_room("", invitation)
		else: game.network._join_room(relay_url, str(read_stage("room").code), true)
		if not await wait_for(func(): return game.network.state == "lobby" and game.network._authenticated, "proxy-authenticated lobby", 25): await fail_fixture("join"); return
		check(game.network.local_player_id == slot, "Authenticated sender owns the expected independent player slot")
		publish("joined" + str(slot), {"player_id": game.network.local_player_id})
	if not await wait_for(playing, "actual shared game starts", 40): await fail_fixture("start"); return
	if slot == 1:
		prepare_combat()
		publish("prepared")
	else:
		if not await barrier("prepared", 20) or not await wait_for(func(): return game.players.size() == 4 and game.players[slot - 1].hp >= 900000 and game.upgrades.has_upgrade("shotgun"), "prepared authoritative fixture replicated", 20): await fail_fixture("prepared state"); return
	voice_active = true
	voice_next = Time.get_ticks_usec()
	check(game.players.size() == 4, "Four genuine live worker nodes are present")
	publish("started" + str(slot))
	if not await barrier("phase_run", 25): await fail_fixture("workload barrier"); return
	initial_voice_played = voice_frames_played()
	reset_observation()
	await input_workload(phase_seconds, 10)
	await delay(3.0)
	publish("phase_done" + str(slot))
	if slot == 1:
		for id in [2, 3, 4]:
			if not await barrier("phase_done" + str(id), 20): await fail_fixture("workload completion"); return
		verify_actions(10, "delayed/jittered input with 0.5/2-second blackouts" + (" and seeded UDP loss" if relay_url.is_empty() else " through FIFO TCP"))
		publish("phase_verified", {"edges": edges, "weapon_changes": weapon_changes, "actions_blocked_by_hit": actions_blocked_by_hit, "movement_span": movement_span, "hits": hit_counts})
	if not await barrier("phase_verified", 25): await fail_fixture("host input audit"); return
	check(voice_frames_played() - initial_voice_played >= 80, "Actual encoded remote voice reaches bounded AudioStreamGenerator playback while movement and action inputs run")
	check(game.network.state == "playing" and not paused, "Short 0.5/2-second packet blackouts recover without permanent pause or participant loss")
	if not await barrier("outage_run", 25): await fail_fixture("cut barrier"); return
	var cut_deadline := Time.get_ticks_msec() + 12000
	var detected := false
	while Time.get_ticks_msec() < cut_deadline:
		if paused and game.network.match_paused and (game.network.state == "reconnecting" if slot in [1, 3] else game.network.state == "playing" and game.network.peer_connected):
			detected = true
			break
		await process_frame
	check(detected, "Seven-second silent cut pauses the world while healthy guests retain their playing connection")
	if not detected: await fail_fixture("no reconnect"); return
	if slot == 1:
		check(game.network.is_player_connected(2) and game.network.is_player_connected(4) and not game.network.is_player_connected(3), "Only the disconnected guest loses its authenticated link; both healthy guests stay connected")
		publish("cut_detected", {"state": game.network.state, "connected_slots": game.network._connected_slots, "error": game.network.error_message})
	if not await wait_for(playing, "real native transport reconnect and ready resume", 35): await fail_fixture("recovery"); return
	check(game.network.local_player_id == slot and game.players.size() == 4, "Recovered guest retains its own slot and exactly four world actors")
	if slot == 1:
		check(game.network.connected_player_count() == 4, "Recovered connection restores the complete authenticated crew")
	check(not game.network.match_paused and not paused, "Automatic reconnect wait releases its own pause")
	publish("recovered" + str(slot))
	if not await barrier("pause_run", 25): await fail_fixture("shared pause barrier"); return
	if slot == 2: game.network.pause_match(true)
	if not await wait_for(func(): return paused and game.network.match_paused, "guest requests a real shared pause", 15): await fail_fixture("shared pause"); return
	publish("paused" + str(slot))
	if not await barrier("resume_run", 25): await fail_fixture("resume barrier"); return
	if slot == 4: game.network.pause_match(false)
	if not await wait_for(playing, "different guest resumes shared pause", 15): await fail_fixture("shared resume"); return
	publish("resumed" + str(slot))
	if not await barrier("post_run", 25): await fail_fixture("post recovery workload"); return
	publish("input_diagnostic_before" + str(slot), input_diagnostic())
	var post_voice := voice_frames_played()
	reset_observation()
	await input_workload(4, 3)
	await delay(2)
	publish("input_diagnostic_after" + str(slot), input_diagnostic())
	publish("post_done" + str(slot))
	if slot == 1:
		for id in [2, 3, 4]:
			if not await barrier("post_done" + str(id), 20): await fail_fixture("post recovery completion"); return
		verify_actions(3, "fresh post-reconnect and post-pause actions")
		publish("post_verified", {"edges": edges, "weapon_changes": weapon_changes, "actions_blocked_by_hit": actions_blocked_by_hit})
	if not await barrier("post_verified", 20): await fail_fixture("post recovery audit"); return
	check(voice_frames_played() - post_voice >= 50, "Fresh real speech playback resumes after reconnection and shared pause")
	check(max_decode_queue <= 64 and max_voice_queue <= 10, "Actual concurrent decode and per-speaker playback queues stay within production bounds")
	if relay_url.is_empty():
		# Native ENet aggregates three independent host links. The production
		# 128-packet guard applies to a single link remaining overloaded for 1 s;
		# a transient aggregate peak is recorded alongside its measured drain.
		check(max_transport_backlog_seconds < 1.0 and max_poll_packets <= game.network.transport.MAX_POLL_PACKETS and max_poll_scanned <= game.network.transport.MAX_POLL_SCANNED, "Real ENet catch-up drains below the sustained-overload deadline with bounded per-poll work")
	else: check(max_websocket_outbound_bytes <= game.network.Protocol.MAX_PACKET * 2 and max_websocket_inbound_packets <= 64, "Actual WebSocket send and receive buffers stay within production allocation limits")
	check(max_input_edge_queue <= game.network.MAX_PENDING_INPUT_EDGES, "Each actual authenticated input FIFO remains within its production bound")
	check(game.network._voice_sources.size() == 3 and game.voice.played_frames >= 20 and game.voice._receivers.size() == 2 and game.voice._receivers.values().all(func(receiver): return receiver.played_frames >= 20), "Each of the three remote participants retains its own received sequence and actual playback stream")
	check(not game.microphone.capturing, "Simultaneous voice fixture leaves physical microphones closed")
	check(game.network.error_message.is_empty() and game.network.world.last_error.is_empty(), "Accepted snapshots and transport contain no hidden error")
	if slot in [2, 4]: check(state_events.all(func(event): return event.state not in ["reconnecting", "error"]), "Healthy guest never loses its own connection during another guest's faults")
	publish("report" + str(slot), {"slot": slot, "checks": checks, "failures": failures, "voice_sent": voice_sent, "voice_played": voice_frames_played(), "max_decode_queue": max_decode_queue, "max_voice_queue": max_voice_queue, "max_transport_backlog": max_transport_backlog, "max_transport_backlog_seconds": max_transport_backlog_seconds, "max_poll_packets": max_poll_packets, "max_poll_scanned": max_poll_scanned, "max_input_edge_queue": max_input_edge_queue, "max_snapshot_sequence_gap": max_snapshot_sequence_gap, "max_websocket_outbound_bytes": max_websocket_outbound_bytes, "max_websocket_inbound_packets": max_websocket_inbound_packets, "state_events": state_events, "transport_errors": transport_errors, "edges": edges, "weapon_changes": weapon_changes, "actions_blocked_by_hit": actions_blocked_by_hit, "movement_ticks": movement_ticks, "hits": hit_counts, "network_error": game.network.error_message, "microphone_open": game.microphone.capturing})
	if not await barrier("finish_run", 25): await fail_fixture("finish barrier"); return
	voice_active = false
	observer.queue_free()
	await process_frame
	print("NETWORK_IMPAIRMENT_PASS ", role, " checks=", checks, " failures=", failures)
	await finish(failures == 0, "real ENet seeded latency, jitter, loss, simultaneous input/voice and reconnect")

func prepare_combat() -> void:
	game.rounds.running = false
	game.rounds.wave = 1
	game.rounds.phase = "attack"
	game.upgrades.owned.shotgun = true
	game.core.max_hp = 1000000
	game.core.hp = 1000000
	for wall in get_nodes_in_group("walls"):
		# Exterior sites retain their catalogue HP and real destruction state.
		if wall is DefenseWall and wall.game == game and wall.max_hp > 0: wall.max_hp = 1000000; wall.hp = 1000000
	for index in 4:
		var worker = game.players[index]
		worker.progression.level = PlayerProgression.MAX_LEVEL
		worker.max_hp = 1000000
		worker.hp = 1000000
		worker.global_position = Vector2(980 + index * 24, 430)
		worker.inventory.clear()
		worker.get_node("WorkerWeapon").loaded.shotgun = 6
	game.combat_events.event.connect(func(kind: String, data: Dictionary):
		if kind == "hit" and int(data.get("player_id", 0)) in [1, 2, 3, 4]:
			var key := str(data.player_id)
			hit_counts[key] = int(hit_counts.get(key, 0)) + 1)
	for index in 4:
		var enemy = game._entity("enemy", Vector2(1350 + index * 28, 430), {"kind": "strider", "wave": 1})
		enemy.max_hp = 500000
		enemy.hp = 500000

func poll_voice() -> void:
	if not voice_active or done or not is_instance_valid(game): return
	var now := Time.get_ticks_usec()
	var packets := 0
	while now >= voice_next and packets < 2:
		if game.network.send_voice(tone): voice_sent += 1
		voice_next += 20000
		packets += 1
	if now - voice_next > 40000: voice_next = now + 20000

func voice_frames_played() -> int:
	var count: int = game.voice.played_frames
	for receiver in game.voice._receivers.values(): count += int(receiver.played_frames)
	return count

func observe() -> void:
	if done or not is_instance_valid(game) or not game.started: return
	var state: String = game.network.state
	if state != prior_state:
		state_events.append({"at_ms": Time.get_ticks_msec() - started_at, "state": state, "paused": paused, "connected": game.network.peer_connected})
		prior_state = state
	if is_instance_valid(game.network.transport) and game.network.transport.peer != null:
		var backlog: int = game.network.transport.peer.get_available_packet_count()
		max_transport_backlog = maxi(max_transport_backlog, backlog)
		var now := Time.get_ticks_usec()
		if backlog > game.network.transport.MAX_BACKLOG_PACKETS:
			if transport_backlog_started_usec == 0: transport_backlog_started_usec = now
			max_transport_backlog_seconds = maxf(max_transport_backlog_seconds, float(now - transport_backlog_started_usec) / 1000000.0)
		else: transport_backlog_started_usec = 0
		max_poll_packets = maxi(max_poll_packets, game.network.transport.last_poll_packets)
		max_poll_scanned = maxi(max_poll_scanned, game.network.transport.last_poll_scanned)
	else: transport_backlog_started_usec = 0
	max_input_edge_queue = maxi(max_input_edge_queue, game.network._input_edges.size())
	for link: Dictionary in game.network._peers.values():
		max_input_edge_queue = maxi(max_input_edge_queue, link._input_edges.size())
	if game.network._decoder != null:
		game.network._decoder._mutex.lock()
		max_decode_queue = maxi(max_decode_queue, game.network._decoder._pending.size() + game.network._decoder._completed.size())
		game.network._decoder._mutex.unlock()
	if game.network._websocket != null:
		max_websocket_outbound_bytes = maxi(max_websocket_outbound_bytes, game.network._websocket.get_current_outbound_buffered_amount())
		max_websocket_inbound_packets = maxi(max_websocket_inbound_packets, game.network._websocket.get_available_packet_count())
	for receiver in [game.voice] + game.voice._receivers.values():
		max_voice_queue = maxi(max_voice_queue, receiver._queue.size())
	if slot != 1: return
	for link: Dictionary in game.network._peers.values():
		max_snapshot_sequence_gap = maxi(max_snapshot_sequence_gap, int(link._snapshot_seq) - int(link._snapshot_ack))
	if not monitor_edges or paused: return
	for index in mini(4, game.players.size()):
		var worker = game.players[index]
		if NetInput.axis(worker, "left", "right") != 0: movement_ticks[index] += 1
		var edge := NetInput.just_pressed(worker, "cycle_weapon")
		if edge: edges[index] += 1
		var kind: String = worker.get_node("WorkerWeapon").weapon_kind
		if kind != last_weapons[index]:
			weapon_changes[index] += 1
			last_weapons[index] = kind
		elif edge and not worker.can_act():
			# A genuine enemy's damage stun intentionally blocks weapon use.
			# This is recorded separately from a lost transport action.
			actions_blocked_by_hit[index] += 1
		movement_span[index] = maxf(movement_span[index], absf(worker.global_position.x - first_positions[index]))

func reset_observation() -> void:
	edges = [0, 0, 0, 0]
	weapon_changes = [0, 0, 0, 0]
	actions_blocked_by_hit = [0, 0, 0, 0]
	movement_span = [0.0, 0.0, 0.0, 0.0]
	movement_ticks = [0, 0, 0, 0]
	for index in 4:
		last_weapons[index] = game.players[index].get_node("WorkerWeapon").weapon_kind
		first_positions[index] = game.players[index].global_position.x
	monitor_edges = true

func set_action(action: String, held: bool) -> void:
	var key := "p1_" + action
	if held:
		if not Input.is_action_pressed(key): Input.action_press(key)
	elif Input.is_action_pressed(key): Input.action_release(key)

func input_workload(seconds: float, count: int) -> void:
	var began := Time.get_ticks_msec()
	var sent := 0
	var tap_at := 0
	var tap_spacing := .9 if seconds >= 12 else .6
	while Time.get_ticks_msec() - began < int(seconds * 1000):
		var elapsed := (Time.get_ticks_msec() - began) / 1000.0
		var right := int(elapsed / .7) % 2 == 0
		set_action("right", right)
		set_action("left", not right)
		set_action("fire", true)
		var worker = game.players[slot - 1]
		var point: Vector2 = worker.global_position + Vector2(380, -35)
		var nearest := INF
		for enemy in get_nodes_in_group("enemies"):
			if enemy.game != game or enemy.dead: continue
			var distance: float = worker.global_position.distance_squared_to(enemy.global_position)
			if distance < nearest:
				nearest = distance
				point = enemy.global_position - Vector2(0, float(enemy.profile.get("center_y", 30)))
		var event := InputEventMouseMotion.new()
		event.position = root.get_final_transform() * (game.get_global_transform_with_canvas() * point)
		event.global_position = event.position
		Input.parse_input_event(event)
		if tap_at > 0 and Time.get_ticks_msec() - tap_at >= 80:
			set_action("cycle_weapon", false)
			tap_at = 0
		if sent < count and tap_at == 0 and elapsed >= .8 + sent * tap_spacing:
			set_action("cycle_weapon", true)
			tap_at = Time.get_ticks_msec()
			sent += 1
		await process_frame
	publish("input_diagnostic_held" + str(slot), input_diagnostic())
	for action in ["right", "left", "fire", "cycle_weapon"]: set_action(action, false)
	check(sent == count, "Local sampled input issued exactly %d separate weapon-switch actions" % count)

func verify_actions(expected: int, context: String) -> void:
	for index in 4:
		check(edges[index] == expected, "P%d: exactly %d authoritative consumed action edges under %s" % [index + 1, expected, context])
		check(weapon_changes[index] + actions_blocked_by_hit[index] == expected, "P%d: each action changes its real weapon exactly once or has an observed native damage stun" % (index + 1))
		check(movement_ticks[index] > 10 and (movement_span[index] > 25 or expected == 3), "P%d: held movement reaches its own authoritative worker, independently of native hit knockback" % (index + 1))
		# Native enemy attacks may still cause knockback; input release must clear
		# the authoritative movement axis, independently of external forces.
		check(NetInput.axis(game.players[index], "left", "right") == 0, "P%d: released movement clears its authoritative input without a stuck action" % (index + 1))
		check(game.players[index].get_node("WorkerWeapon")._shot_index > 0, "P%d: actual sampled fire launches real projectiles alongside voice" % (index + 1))
	monitor_edges = false

func fail_fixture(reason: String) -> void:
	voice_active = false
	if is_instance_valid(observer): observer.queue_free()
	await process_frame
	await finish(false, reason)

func input_diagnostic() -> Dictionary:
	var data := {"local_id": game.network.local_player_id, "state": game.network.state, "paused": paused, "hud": game.hud.overlay, "input_blocked": NetInput._blocked(game), "input_seq": game.network._input_seq, "generation": game.network._generation, "physics_processing": game.network.is_physics_processing(), "physics_mode": game.network.process_mode, "sample": NetInput.sample_local(game)}
	if slot == 1:
		data.links = {}
		for id in game.network._slots:
			var link: Dictionary = game.network._slots[id]
			data.links[str(id)] = {"wire": link.wire, "connected": link.connected, "authenticated": link._authenticated, "ready": link._ready_for_snapshots, "remote_seq": link._remote_seq, "last_input_age": game.network._clock - link._last_input_at, "pending": link._pending_remote, "published": link.remote_input}
	return data
