extends "res://tests/network_four_peer.gd"
## Four real OS processes; barrier files only coordinate expected scalar state.
## Actual departure, sender-bound input, hostile hits and mid-repair reconnect.
const Journey := preload("res://scripts/convoy_journey.gd")
const NetInput := preload("res://scripts/network_input.gd")
const ROLES: Array[String] = ["driver", "passenger_left", "passenger_right", "gunner"]
var stage_evidence: Dictionary = {}
var damage_records: Array[Dictionary] = []
var cinematic_evidence: Dictionary = {}

func _run() -> void:
	overall_timeout_ms = 85000
	role = OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	slot = int(OS.get_environment("LASTSHIFT_PARTY_SLOT"))
	prefix = OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	relay = OS.get_environment("LASTSHIFT_PARTY_RELAY")
	if slot not in range(1, 5) or prefix.is_empty() or not "--no-upnp" in OS.get_cmdline_user_args() or not "--no-profile-save" in OS.get_cmdline_user_args():
		await finish(false, "safe fixture flags missing"); return
	game = load("res://scenes/main.tscn").instantiate()
	LocaleText.set_locale("en" if slot==3 else "de",false)
	root.add_child(game)
	current_scene = game
	game.hud.overlay = "network"
	game.network.listen_port = 24927
	game.network.lan_discovery_port = 24928
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	if slot == 1: await host_run()
	else: await guest_run()

func guards() -> Array[Node]:
	var result: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		# expedition_guard is host-only targeting metadata, deliberately absent
		# from the wire. Clients identify the actual road enemies in their world.
		if enemy.game == game and not enemy.is_queued_for_deletion() and not enemy.dead and (not game.network.is_host or enemy.get_meta("expedition_guard", false)): result.append(enemy)
	return result

func guard_by_id(id: String) -> Node2D:
	for enemy in get_nodes_in_group("enemies"):
		if enemy.game == game and str(enemy.get_meta("network_entity_id", "")) == id: return enemy
	return null

func mg_total(truck: Node2D) -> int:
	return int(truck.ammo) + int(truck.reserve) + int(truck.open_pack) + 20 * int(truck.cargo.get("ammo", 0))

func credited_damage(enemy_id: int, player_id: int) -> float:
	var amount := 0.0
	for record in damage_records:
		if int(record.get("enemy_id", 0)) == enemy_id and int(record.get("player_id", 0)) == player_id:
			amount += float(record.get("amount", 0))
	return amount

func record_damage(kind: String, data: Dictionary) -> void:
	if kind == "hit": damage_records.append(data.duplicate())

func repair_active() -> bool:
	return loaded() and is_instance_valid(game.expedition.vehicle) and game.expedition.vehicle.journey_state.phase == "repair"

func damage_acknowledged(target_ids: Array) -> bool:
	var acknowledged := true
	for index in 2:
		var player_id := index + 3
		var amount := credited_damage(int(target_ids[index]), player_id)
		if amount <= 0:
			acknowledged = false
		elif read_stage("actual_hit" + str(player_id)).is_empty():
			publish("actual_hit" + str(player_id), {"amount":amount,"physics_tick":Engine.get_physics_frames()})
	return acknowledged

func fire_neutral(frame: Dictionary) -> bool:
	return not frame.is_empty() and float(frame.get("held", {}).get("fire", 0.0)) == 0.0 and not "fire" in frame.get("pressed", [])

func release_applied(player_id: int, sequence: int) -> bool:
	var link: Dictionary = game.network._slots.get(player_id, {})
	return int(link.get("_remote_seq", -1)) >= sequence and fire_neutral(link.get("_pending_remote", {})) and fire_neutral(link.get("remote_input", {})) and link.get("_input_edges", []).is_empty()

func defense_rounds_retired() -> bool:
	for child in game.get_children():
		if (child is WorkerShot or child is BunkerProjectile) and is_instance_valid(child.credit_worker) and child.credit_worker.player_id in [3, 4]:
			return false
	return true

func aim_and_fire(id: String) -> bool:
	# Headless has no OS mouse. Sample the real held fire key, replace only its
	# pointer with the current rendered enemy's world aim point, and send the
	# normal authenticated input packet. Host physics launches actual bullets.
	game.network.set_physics_process(false)
	Input.action_press("p1_fire")
	var target_aim: Array = []
	var deadline := Time.get_ticks_msec() + 3000
	while read_stage("actual_hit" + str(slot)).is_empty() and Time.get_ticks_msec() < deadline:
		var enemy := guard_by_id(id)
		var frame := NetInput.sample_local(game)
		if is_instance_valid(enemy): target_aim = [enemy.position.x, enemy.position.y - 27]
		if not target_aim.is_empty(): frame.aim = target_aim.duplicate()
		game.network._input_seq += 1
		game.network._send({"kind":"input", "generation":game.network._generation, "seq":game.network._input_seq, "input":frame})
		await delay(.05)
	Input.action_release("p1_fire")
	var released := NetInput.sample_local(game)
	# Native input deliberately uses the latest aim during catch-up. Retain the
	# rendered target instead of replacing it with a nonexistent headless mouse.
	if not target_aim.is_empty(): released.aim = target_aim.duplicate()
	game.network._input_seq += 1
	game.network._send({"kind":"input", "generation":game.network._generation, "seq":game.network._input_seq, "input":released})
	publish("fired" + str(slot), {"release_seq":game.network._input_seq,"aim":target_aim,"hit":read_stage("actual_hit" + str(slot))})
	# Keep a real neutral input stream alive while the other defender's contact
	# and SSH barrier are pending; host input deliberately expires after .5 s.
	deadline = Time.get_ticks_msec() + 5000
	while read_stage("fire_released" + str(slot)).is_empty() and Time.get_ticks_msec() < deadline:
		var neutral := NetInput.sample_local(game)
		if not target_aim.is_empty(): neutral.aim = target_aim.duplicate()
		game.network._input_seq += 1
		game.network._send({"kind":"input", "generation":game.network._generation, "seq":game.network._input_seq, "input":neutral})
		await delay(.05)
	var accepted := check(not read_stage("fire_released" + str(slot)).is_empty(), "Actual host acknowledges this defender's released reliable sequence")
	game.network.set_physics_process(true)
	return accepted and check(not read_stage("actual_hit" + str(slot)).is_empty(), "Actual host attributes a live target hit before this defender releases fire")

func host_run() -> void:
	game.network.host_room(relay)
	if not await wait_for(func(): return game.network.state == "lobby", "safe local host lobby"): await finish(false, "host"); return
	publish("room", {"code":game.network.room_code})
	if not await each_barrier("joined") or not await wait_for(func(): return game.network.connected_player_count() == 4, "four authenticated humans"): await finish(false, "lobby"); return
	publish("crew_authenticated", {"count":game.network.connected_player_count()})
	game.network.start_match(OPTIONS, game.selected_characters)
	if not await wait_for(loaded, "actual four-human world") or not await each_barrier("started"): await finish(false, "world"); return
	game.rounds.running = false
	game.rounds.wave = 20
	game.upgrades.points = 30
	game.upgrades.owned["convoy_mg"] = true
	game.players[0].inventory = {"ammo":2}
	check(game.expedition.on_victory(), "Prepared wave20 victory commits all four real crew slots")
	check(game.expedition.handle_command("route", {"id":"harbor"}, 1), "Host chooses the actual first road")
	check(game.expedition.handle_command("load", {"kind":"ammo", "amount":2}, 1), "Actual finite warehouse crates supply the mounted MG")
	check(game.expedition.handle_command("depart", {}, 1), "Actual garage begins boarding")
	for id in range(1, 5):
		game.players[id - 1].position = game.expedition.vehicle.position
		check(game.expedition.vehicle.board(game.players[id - 1], ROLES[id - 1]), "Actual garage seat accepts P%d in %s" % [id, ROLES[id - 1]])
	if not await wait_for(func(): return loaded() and game.travel_cinematic.is_presented() and game.travel_cinematic.elapsed()>=.5, "actual shared road cinematic", 15): await finish(false,"cinematic"); return
	var shared_scene: Dictionary=game.travel_cinematic.context()
	check(shared_scene.id=="signal" and shared_scene.destination=="harbor" and game.hud.overlay.is_empty() and not paused,"Actual road presents a signal scene without pausing the four-peer simulation")
	publish("cinematic",{"id":shared_scene.id,"duration":shared_scene.duration,"crew_ids":shared_scene.crew_ids})
	if not await each_barrier("cinematic_seen"): await finish(false,"cinematic replicas"); return
	await delay(.2)
	check(game.travel_cinematic.active and not game.expedition.vehicle.driving_enabled,"Authenticated guest skip command cannot finish the host-owned vignette")
	check(game.players.all(func(person):return person.get_node("WorkerWeapon").total_ammunition()==120) and game.expedition.vehicle.ammo==0 and game.expedition.vehicle.cargo.get("ammo",0)==2,"Actual guest held fire/reload/interact preserves every finite magazine and crate during scene")
	check(game.players.all(func(person):return is_instance_valid(person.mounted_turret)) and game.expedition.vehicle.position.x==game.expedition.ROAD_START,"All actual seats and parked road position remain intact during blocked input")
	cinematic_evidence={"id":shared_scene.id,"duration":shared_scene.duration,"elapsed_before_skip":game.travel_cinematic.elapsed(),"actual_crew_ids":shared_scene.crew_ids,"guest_skip_denied":game.travel_cinematic.active,"host_locale":LocaleText.current_locale()}
	game.travel_cinematic.request_skip()
	check(not game.travel_cinematic.active and game.travel_cinematic.blocks_gameplay() and game.expedition.vehicle.journey_state.phase=="starting","Actual host skip retains the original protected ignition interval")
	if not await wait_for(func(): return loaded() and game.expedition.stage == "travel" and game.expedition.vehicle.journey_state.phase == "driving", "real post-skip ignition", 5) or not await each_barrier("road"): await finish(false, "departure"); return
	var truck: Node2D = game.expedition.vehicle
	# The actual departure replaced the game, including its event bus. Observe
	# the new authoritative world's contacts rather than the destroyed garage.
	game.combat_events.event.connect(record_damage)
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()), "Unchanged strict four-crew departure checkpoint validates")
	check(truck.defenders.is_empty(), "Online travel never creates offline escort children")
	var rounds_before := mg_total(truck)
	publish("reload_mg")
	if not await barrier("reloaded4") or not await wait_for(func(): return truck.ammo == 40 and truck.reload_timer == 0, "actual guest MG reload", 4): await finish(false, "reload"); return
	check(mg_total(truck) == rounds_before and rounds_before == 40, "Reload moves the two paid crates into exactly forty finite MG rounds")
	truck.position.x = 1740.1
	if not await wait_for(repair_active, "production threshold begins tire mission"):
		await finish(false, "puncture"); return
	check(guards().size() >= 3 and not is_instance_valid(game.players[0].mounted_turret), "Actual puncture spawns live guards and places the driver beside the wheel")
	for enemy in guards(): enemy.attack_damage = minf(enemy.attack_damage, 1.0)
	check(truck.dismount(game.players[1]), "A second actual human leaves its own passenger seat")
	for id in [1, 2]:
		var worker: Node2D = game.players[id - 1]
		worker.position = truck.service_point() + Vector2(-49 - (id - 1) * 20, 20)
		worker.velocity = Vector2.ZERO
		worker.preferred_focus = truck
	game.players[0].preferred_focus = truck
	Input.action_press("p1_interact")
	if not await wait_for(func(): return truck.journey_state.repair_operator == 1 and truck.journey_state.repair_work > .03, "driver actual held tool input"): await finish(false, "tool"); return
	var targets := guards()
	var first_target: Node2D = targets[0]
	var second_target: Node2D = targets[1]
	# Prepare independent rear/front sight lines. Spawn-order targets otherwise
	# form one column: the MG correctly hits the nearer guard before its target.
	# Both guards keep native HP, movement, collisions and hostile attacks.
	first_target.position = Vector2(truck.position.x - 300, 430)
	first_target.velocity = Vector2.ZERO
	# Assign IDs through the production registry after preparing positions.
	# Coordination files carry IDs only; replicas must observe actual snapshots.
	game.network.world.capture()
	var target_instance_ids := [first_target.get_instance_id(), second_target.get_instance_id()]
	var before_hp := [float(first_target.hp), float(second_target.hp)]
	var rifle_before: int = game.players[2].get_node("WorkerWeapon").total_ammunition()
	var frame_start := Engine.get_physics_frames()
	var initial_work: float = truck.journey_state.repair_work
	var initial_step: String = truck.journey_state.repair_step
	publish("repair", {"personal_target":str(first_target.get_meta("network_entity_id")), "mg_target":str(second_target.get_meta("network_entity_id"))})
	if not await each_barrier("repair_seen"): await finish(false, "repair snapshots"); return
	publish("defend")
	if not await wait_for(func(): return damage_acknowledged(target_instance_ids), "Actual bullets credit both independently aimed live guards", 3): await finish(false, "actual defense contacts"); return
	if not await barrier("fired3") or not await barrier("fired4"): await finish(false, "actual defense input"); return
	for id in [3, 4]:
		var release_seq := int(read_stage("fired" + str(id)).get("release_seq", -1))
		if not await wait_for(func(): return release_seq > 0 and release_applied(id, release_seq), "Actual host consumes P%d reliable release and pending fire edges" % id, 3): await finish(false, "fire release"); return
		await physics_frame
		check(release_applied(id, release_seq), "P%d remains neutral after a complete authoritative physics tick" % id)
		var link: Dictionary = game.network._slots[id]
		publish("fire_released" + str(id), {"release_seq":release_seq,"host_seq":link._remote_seq,"input":link.remote_input,"pending_edges":link._input_edges.size(),"physics_tick":Engine.get_physics_frames()})
	if not await wait_for(defense_rounds_retired, "All real defender projectiles resolve before stable ammo publication", 1.2): await finish(false, "projectile retirement"); return
	# A real lethal hit may already have queued/freed its victim. Attribution is
	# emitted only after actual HP removal, so retain that production evidence.
	var actual_damage := [credited_damage(target_instance_ids[0], 3), credited_damage(target_instance_ids[1], 4)]
	check(actual_damage[0] > 0, "A guest's real personal rifle removes actual HP from its live puncture guard")
	check(actual_damage[1] > 0, "The other guest's mounted MG removes actual HP from a different live puncture guard")
	var rifle_after: int = game.players[2].get_node("WorkerWeapon").total_ammunition()
	check(rifle_after < rifle_before and rifle_after >= 0, "Actual personal defense spends only its own finite rounds")
	check(mg_total(truck) < rounds_before and mg_total(truck) >= 0, "Mounted defense consumes finite convoy rounds")
	check(game.players[1].get_node("WorkerWeapon").total_ammunition() == 120, "Holding tools cannot spend the second mechanic's personal ammunition")
	check(truck.journey_state.repair_operator == 1 and truck.journey_state.phase == "repair", "Two held mechanic inputs retain one operator while two teammates defend")
	var ticks := Engine.get_physics_frames() - frame_start
	# WAN acknowledgement takes real time; validate the actual elapsed tool
	# stages rather than requiring the same phase as a fast same-host run.
	var elapsed := float(ticks + 2) / Engine.physics_ticks_per_second
	var current_step: String = truck.journey_state.repair_step
	check(current_step in ["jack", "remove", "fit", "tighten"], "Concurrent E inputs cannot complete the full three-bolt tightening stage inside this bounded defense window")
	if current_step == initial_step:
		check(truck.journey_state.repair_work - initial_work <= elapsed / float(Journey.HOLD_TIMES[initial_step]), "Authenticated simultaneous E keys cannot double tool work per tick")
	else:
		var minimum_time := (1.0 - initial_work) * float(Journey.HOLD_TIMES[initial_step])
		for index in range(Journey.STEPS.find(initial_step) + 1, Journey.STEPS.find(current_step)):
			minimum_time += float(Journey.HOLD_TIMES.get(Journey.STEPS[index], 0.0))
		if current_step == "tighten":
			minimum_time += (float(truck.journey_state.repair_bolts) + float(truck.journey_state.repair_work)) * Journey.BOLT_HOLD_TIME
			check(truck.journey_state.events.filter(func(event): return event.kind == "bolt").all(func(event): return event.quality == "assisted"), "Untapped held tools use only actual timed assisted bolts")
		else:
			minimum_time += float(truck.journey_state.repair_work) * float(Journey.HOLD_TIMES.get(current_step, 0.0))
		check(elapsed >= minimum_time, "Actual completed tool stages each consume their full single-operator physics time")
	var actual_hp_after := [float(first_target.hp) if is_instance_valid(first_target) else 0.0, float(second_target.hp) if is_instance_valid(second_target) else 0.0]
	stage_evidence = {"guard_hp_before":before_hp, "guard_hp_after":actual_hp_after, "attributed_real_hp_removal":actual_damage, "personal_rounds_before":rifle_before, "personal_rounds_after":rifle_after, "mg_rounds_before":rounds_before, "mg_rounds_after":mg_total(truck), "operator":truck.journey_state.repair_operator, "guards_live":guards().size(), "physics_ticks":ticks}
	stage_evidence.fire_release_acknowledgements = [read_stage("fire_released3"), read_stage("fire_released4")]
	publish("defense_verified", {"rifle":game.players[2].get_node("WorkerWeapon").current_ammo(), "mg":truck.ammo})
	if not await each_barrier("defense_seen"): await finish(false, "spent ammo snapshot"); return
	Input.action_release("p1_interact")
	if not await wait_for(func(): return truck.journey_state.repair_operator == 2, "guest takeover after driver releases E"): await finish(false, "lease"); return
	publish("takeover2")
	if not await each_barrier("takeover_seen"): await finish(false, "lease replication"); return
	publish("release2")
	if not await barrier("released2") or not await wait_for(func(): return truck.journey_state.repair_operator == 0, "released guest lease clears"): await finish(false, "release"); return
	publish("claim2")
	if not await barrier("claimed2") or not await wait_for(func(): return truck.journey_state.repair_operator == 2, "returning guest actual tool input"): await finish(false, "reclaim"); return
	publish("reconnect")
	if relay.is_empty(): game.network.transport.disconnect_guest(int(game.network._slots[2].wire))
	else: publish("drop2")
	if not await wait_for(func(): return paused and game.network.state == "reconnecting", "owning mechanic disconnect pauses everyone"): await finish(false, "disconnect"); return
	check(not truck.can_service(game.players[1]), "A truly disconnected repair slot immediately fails connectivity guard")
	var paused_work: float = truck.journey_state.repair_work
	var paused_phase: String = truck.journey_state.repair_step
	publish("missing_owner")
	if not await each_barrier("pause_seen"): await finish(false, "pause snapshots"); return
	await delay(.15)
	check(paused_phase == truck.journey_state.repair_step and is_equal_approx(paused_work, truck.journey_state.repair_work), "Reconnect pause performs no stale repair work")
	if not await barrier("rejoined2", 15) or not await wait_for(loaded, "same authenticated mechanic returns", 15): await finish(false, "reconnect"); return
	if not await wait_for(func(): return truck.journey_state.repair_operator == 0, "released rejoin input cannot retain old tools"): await finish(false, "post-rejoin lease"); return
	check(game.network.connected_player_count() == 4 and truck.defenders.is_empty(), "Same four human slots return without solo helper or duplicate truck")
	check(get_nodes_in_group("convoy_vehicles").filter(func(node): return node.game == game).size() == 1, "Reconnect retains one actual existing chassis")
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()), "Save checkpoint retains the valid complete four-person departure after roadside reconnect")
	stage_evidence.cinematic=cinematic_evidence
	stage_evidence.cinematic.guests=[]
	for id in range(2,5): stage_evidence.cinematic.guests.append(read_stage("cinematic_seen"+str(id)))
	publish("final", stage_evidence)
	if not await each_barrier("passed"): await finish(false, "final clients"); return
	await finish(failures == 0, "live four-person tire defense and reconnect")

func guest_run() -> void:
	game.network.join_room(relay, str(read_stage("room").get("code", "")))
	if not await wait_for(func(): return game.network._authenticated and game.network.state == "lobby", "guest authenticates own human slot"): await finish(false, "join"); return
	check(game.network.local_player_id == slot, "Real host binds this client to its own slot")
	publish("joined" + str(slot))
	if not await barrier("crew_authenticated", 25): await finish(false, "crew start readiness"); return
	if not await wait_for(loaded, "all four replica humans"): await finish(false, "start"); return
	check(game.players.size() == 4, "Replica receives four actual human workers")
	publish("started" + str(slot))
	if not await barrier("cinematic") or not await wait_for(func():return loaded() and game.travel_cinematic.is_presented(),"Actual starting scene reaches this authenticated client",5): await finish(false,"cinematic"); return
	var shared_scene: Dictionary=game.travel_cinematic.context()
	var expected_scene:=read_stage("cinematic")
	check(shared_scene.id==expected_scene.id and shared_scene.duration==expected_scene.duration and shared_scene.crew_ids==expected_scene.crew_ids,"Actual mixed-language replica derives identical event, cast and fixed shared duration")
	check(not game.travel_cinematic.can_skip() and not game.travel_cinematic.skip(slot) and game.travel_cinematic.blocks_gameplay(),"Actual guest controls cannot skip host-owned scene")
	for action in ["p1_fire","p1_reload","p1_interact"]: Input.action_press(action)
	await delay(.15)
	var blocked_frame:=NetInput.sample_local(game)
	check(blocked_frame.held.is_empty() and blocked_frame.pressed.is_empty(),"Real held guest keys sample neutral gameplay while cinematic owns input")
	for action in ["p1_fire","p1_reload","p1_interact"]: Input.action_release(action)
	if slot==2: game.network.send_command("expedition",{"action":"cinematic_skip","data":{}})
	publish("cinematic_seen"+str(slot),{"locale":LocaleText.current_locale(),"duration":shared_scene.duration,"elapsed":game.travel_cinematic.elapsed()})
	if not await wait_for(func(): return loaded() and game.expedition.stage == "travel" and game.expedition.vehicle.journey_state.phase == "driving", "actual replicated garage-to-road generation", 20): await finish(false, "road"); return
	var truck: Node2D = game.expedition.vehicle
	check(game.players[slot - 1].mounted_turret == truck.seats[truck.SEAT_ROLES.find(ROLES[slot - 1])], "Actual boarding handoff preserves this client's assigned seat")
	check(truck.defenders.is_empty(), "Guest never manufactures offline escorts")
	publish("road" + str(slot))
	if slot == 4:
		if not await barrier("reload_mg"): await finish(false, "reload signal"); return
		Input.action_press("p1_reload")
		await delay(.15)
		Input.action_release("p1_reload")
		if not await wait_for(func(): return truck.ammo == 40 and truck.reload_timer == 0, "actual sender-bound MG reload"): await finish(false, "reload"); return
		check(truck.cargo.get("ammo", 0) == 0, "Finite loaded crates are consumed into actual MG magazine")
		publish("reloaded4")
	if not await barrier("repair") or not await wait_for(func(): return repair_active() and guards().size() >= 3 and truck.journey_state.repair_operator == 1, "live guards and one tool operator arrive in snapshot"): await finish(false, "repair"); return
	var repair_targets := read_stage("repair")
	if not await wait_for(func():
		var rear := guard_by_id(str(repair_targets.personal_target))
		var front := guard_by_id(str(repair_targets.mg_target))
		return is_instance_valid(rear) and is_instance_valid(front) and rear.position.x < truck.position.x - 160 and front.position.x > truck.position.x + 160,
		"Actual rear and front targets arrive through world snapshots"):
		await finish(false, "independent sight lines"); return
	var before_work: float = truck.journey_state.repair_work
	check(not truck.service_action(game.players[slot - 1], 1.0 / 60, true, true) and truck.journey_state.repair_work == before_work, "A replica cannot advance host-owned repair through direct mutation")
	check(truck.defenders.is_empty() and truck.active_defenders() == 0, "Four-human repair stays free of offline helper state")
	if slot == 2: Input.action_press("p1_interact")
	publish("repair_seen" + str(slot))
	if not await barrier("defend"): await finish(false, "defense"); return
	if slot in [3, 4]:
		if not await aim_and_fire(str(read_stage("repair").get("personal_target" if slot == 3 else "mg_target", ""))): await finish(false, "real hit and release acknowledgement"); return
	if not await barrier("defense_verified"): await finish(false, "damage"); return
	var expected := read_stage("defense_verified")
	if not await wait_for(func(): return truck.ammo == int(expected.mg) and game.players[2].get_node("WorkerWeapon").current_ammo() == int(expected.rifle), "real spent rifle and MG ammo replicate"): await finish(false, "ammo"); return
	check(truck.journey_state.repair_operator == 1, "Actual guest snapshot retains one mechanic during two shooting teammates")
	check(game.players[3].mounted_turret == truck.gunner_seat and game.players[2].mounted_turret == truck.passenger_right_seat, "MG and personal-cover roles stay attached to their exact humans")
	publish("defense_seen" + str(slot))
	if not await barrier("takeover2") or not await wait_for(func(): return truck.journey_state.repair_operator == 2, "new real tool owner replicates"): await finish(false, "takeover"); return
	check(truck.journey_state.repair_operator == 2, "Driver release transfers the replicated tool operator to actual P2")
	publish("takeover_seen" + str(slot))
	if slot == 2:
		if not await barrier("release2"): await finish(false, "release signal"); return
		Input.action_release("p1_interact")
		publish("released2")
		if not await barrier("claim2"): await finish(false, "claim signal"); return
		Input.action_press("p1_interact")
		if not await wait_for(func(): return truck.journey_state.repair_operator == 2, "own real retapped repair input"): await finish(false, "claim"); return
		publish("claimed2")
	if not await barrier("reconnect"): await finish(false, "reconnect signal"); return
	if slot == 2:
		Input.action_release("p1_interact")
		if not relay.is_empty():
			if not await barrier("drop2"): await finish(false, "drop signal"); return
			game.network._websocket.close(1000, "Isolated tire fixture reconnect")
		if not await wait_for(func(): return game.network.state == "reconnecting", "own mechanic link dropped"): await finish(false, "own disconnect"); return
		# Keep one bounded observation window before the normal same-token retry,
		# so file barriers cannot race the other clients' actual pause packets.
		game.network._retry_at = game.network._clock + 3.0
	if not await barrier("missing_owner"): await finish(false, "pause signal"); return
	if not await wait_for(func(): return paused and game.network.match_paused, "actual shared reconnect pause reaches this client", 3): await finish(false, "pause packet"); return
	check(paused and game.network.match_paused, "Real missing mechanic pauses this client's simulation")
	publish("pause_seen" + str(slot))
	if slot == 2:
		if not await wait_for(loaded, "existing mechanic resumes same world", 15): await finish(false, "rejoin"); return
		check(game.network.local_player_id == 2 and not is_instance_valid(game.players[1].mounted_turret), "Rejoined mechanic retains its own outside worker rather than taking a seat")
		publish("rejoined2")
	if not await barrier("final", 20) or not await wait_for(loaded, "final repaired-world replicas"): await finish(false, "final"); return
	check(game.players.size() == 4 and truck.defenders.is_empty() and game.expedition.stage == "travel", "Four live human replicas retain the same mid-repair road after reconnection")
	check(game.network.world.last_error.is_empty(), "Unchanged world schema accepts every live repair and combat snapshot")
	publish("passed" + str(slot))
	await finish(failures == 0, "actual guest tool/cover/reconnect")
