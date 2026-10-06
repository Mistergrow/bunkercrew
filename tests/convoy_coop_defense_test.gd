extends SceneTree
## Two actual workers hold their own bindings on a physical roadside vehicle.
## Prepared victory/route and positions isolate tool ownership, never fake work.
const Journey := preload("res://scripts/convoy_journey.gd")
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-defense-20261004/network"
var game: Node
var checks := 0
var failures := 0
var evidence: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("COOP REPAIR %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for _frame in count:
		await physics_frame
		await process_frame

func release_inputs() -> void:
	for id in range(1, 5):
		for action in ["interact", "fire", "left", "right", "reload"]:
			Input.action_release("p%d_%s" % [id, action])

func prepare_road(count: int) -> Node2D:
	release_inputs()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(count, {"environment":"ash_foundry", "position":"center", "build_type":"bastion"})
	game.rounds.running = false
	game.rounds.wave = 20
	check(game.expedition.on_victory(), "Prepared real victory opens %d-person garage" % count)
	check(game.campaign.select_destination("harbor") and not game.campaign.begin_journey().is_empty(), "Actual campaign selects a valid finite departure checkpoint")
	game.expedition._start_road()
	game.expedition.set_physics_process(false)
	game.medic.set_physics_process(false)
	game.set_process(false)
	game.hud.overlay = ""
	var truck: Node2D = game.expedition.vehicle
	truck.position.x = 1740.0
	Journey.change_phase(truck.journey_state, "driving")
	check(truck.begin_breakdown(), "Real driving vehicle enters its actual wheel job")
	for person in game.players:
		if is_instance_valid(person.mounted_turret): truck.dismount(person)
		person.inventory.clear()
		person.global_position = truck.service_point() + Vector2(-49 - (person.player_id - 1) * 20, 20)
		person.velocity = Vector2.ZERO
		person.preferred_focus = truck
	await frames(4)
	return truck

func tool_trace(truck: Node2D, label: String) -> void:
	evidence.append({"case":label, "physics_frame":Engine.get_physics_frames(), "operator":truck.journey_state.repair_operator, "step":truck.journey_state.repair_step, "work":truck.journey_state.repair_work})

func fresh_job(truck: Node2D) -> void:
	# Reset the scenario fixture to a fresh real breakdown; do not manufacture a
	# service frame, private lease, completion or operator in the production job.
	Journey.change_phase(truck.journey_state, "driving")
	truck.journey_state.breakdown_done = false
	truck.begin_breakdown()
	for person in game.players:
		if is_instance_valid(person.mounted_turret): truck.dismount(person)
		person.global_position = truck.service_point() + Vector2(-49 - (person.player_id - 1) * 20, 20)
		person.velocity = Vector2.ZERO
		person.preferred_focus = truck

func coop_tools() -> void:
	var truck: Node2D = await prepare_road(2)
	var first: Node2D = game.players[0]
	var second: Node2D = game.players[1]
	check(truck.can_service(first) and truck.can_service(second), "Both actual workers stand in tool range outside the chassis")
	check(truck.defenders.is_empty() and truck.active_defenders() == 0, "Two registered humans never receive solo escorts")
	Input.action_press("p1_interact")
	await frames(5)
	check(truck.journey_state.repair_operator == 1 and truck.journey_state.repair_work > 0, "P1's actual held E claims the live tool job")
	Input.action_press("p2_interact")
	var before: float = truck.journey_state.repair_work
	var frame_before := Engine.get_physics_frames()
	await frames(24)
	var elapsed := float(Engine.get_physics_frames() - frame_before) / Engine.physics_ticks_per_second
	var work_delta: float = truck.journey_state.repair_work - before
	check(truck.journey_state.repair_operator == 1, "A second continuously held E cannot steal an active repairer")
	check(work_delta > 0 and work_delta <= (elapsed + 2.0 / Engine.physics_ticks_per_second) / Journey.HOLD_TIMES.jack, "Two held keys advance tools no faster than one real-time work stream")
	tool_trace(truck, "two-held-keys")
	Input.action_release("p1_interact")
	await frames(6)
	check(truck.journey_state.repair_operator == 2, "Releasing E relinquishes the lease to the other held key")
	tool_trace(truck, "key-release-takeover")
	release_inputs()
	await frames(5)
	check(truck.journey_state.repair_operator == 0, "No held repair input clears the visible tool operator")
	before = truck.journey_state.repair_work
	await frames(8)
	check(is_equal_approx(before, truck.journey_state.repair_work), "A stale lease cannot continue work after both keys release")
	fresh_job(truck)
	await frames(4)
	Input.action_press("p2_interact")
	await frames(4)
	Input.action_press("p1_interact")
	await frames(4)
	check(truck.journey_state.repair_operator == 2, "The second actual worker can acquire a new job first")
	second.invulnerability = 0
	second.take_damage(second.hp + 1)
	check(second.is_downed(), "Actual lethal damage incapacitates the repair owner")
	await frames(6)
	check(truck.journey_state.repair_operator == 1 and not truck.can_service(second), "A real KO releases tools to the living teammate")
	check(truck.defenders.is_empty(), "A downed second human still cannot turn coop into solo escort mode")
	tool_trace(truck, "ko-takeover")
	release_inputs()
	await frames(5)
	check(await Cleanup.free_scene(game, self), "KO and real worker channels clean up with the first world")
	truck = await prepare_road(2)
	first = game.players[0]
	second = game.players[1]
	Input.action_press("p1_interact")
	await frames(4)
	check(truck.board(first, "driver"), "A real Seat.enter mounts the current tool owner")
	Input.action_press("p2_interact")
	await frames(6)
	check(truck.journey_state.repair_operator == 2 and not truck.can_service(first), "Mounting relinquishes the service lease to the outside worker")
	tool_trace(truck, "mount-takeover")
	release_inputs()
	await frames(4)
	fresh_job(truck)
	await frames(4)
	Input.action_press("p2_interact")
	await frames(4)
	second.set_meta("network_departed", true)
	Input.action_press("p1_interact")
	await frames(6)
	check(not truck.can_service(second) and truck.journey_state.repair_operator == 1, "Departed slot cannot retain the tool lease even with its old held key")
	tool_trace(truck, "departed-takeover")
	release_inputs()
	await frames(4)
	check(await Cleanup.free_scene(game, self), "Mount/disconnect fixture releases all scene resources")

func offline_snapshot() -> void:
	var truck: Node2D = await prepare_road(1)
	await frames(8)
	check(truck.defenders.size() == 2 and truck.active_defenders() == 2, "Actual offline singleton owns two physically deployed transient escorts")
	var guard: Node2D = game._entity("enemy", truck.position + Vector2(390, 0), {"kind":"strider", "wave":1})
	guard.attack_damage = 1.0
	var deadline := Time.get_ticks_msec() + 4000
	while truck.defenders.all(func(escort): return escort.shots_fired == 0) and Time.get_ticks_msec() < deadline:
		await frames(1)
	check(truck.defenders.any(func(escort): return escort.shots_fired > 0), "A real deployed escort launches its own finite rifle projectile")
	var world := World.new()
	world.bind(game)
	var snapshot := world.capture()
	check(world._validate(snapshot), "Snapshot validator accepts offline road with actual unreplicated escorts and their shots")
	var envelope := Protocol.decode(Protocol.encode({"kind":"snapshot", "generation":1, "sequence":1, "world":snapshot}))
	check(not envelope.is_empty(), "Current wire encoder still accepts the unchanged schema graph")
	check(snapshot.entities.filter(func(record): return record.type == "player").size() == 1, "Offline escorts never become extra human snapshot slots")
	check(snapshot.entities.all(func(record): return not "Escort" in str(record.id) and not "convoy_defender" in str(record.type)), "Neither escort nor presentation children enter the replication type graph")
	var recognized_ids: Dictionary = {}
	for record in snapshot.entities: recognized_ids[record.id] = true
	check(snapshot.entities.all(func(record): return record.refs.values().all(func(id): return str(id).is_empty() or recognized_ids.has(id))), "Escort-owned projectiles contain only recognized or safely empty object references")
	evidence.append({"case":"offline-snapshot", "humans":game.players.size(), "escorts":truck.defenders.size(), "entities":snapshot.entities.size(), "escort_shots":truck.defenders.map(func(escort): return escort.shots_fired)})
	check(await Cleanup.free_scene(game, self), "Offline escort scene and nested presentation clean up safely")

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	InputSetup.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await coop_tools()
	await offline_snapshot()
	release_inputs()
	var file := FileAccess.open(OUTPUT + "/coop-tools.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "passed":checks-failures, "failures":failures, "prepared_states":["wave20 prepared victory and paid-valid campaign boundary", "x1740 road and outside service stances", "fresh breakdown reset between independent lease cases", "medic disabled only in focused tool tests", "offline guard attack_damage reduced to1; actual physics and shots"], "evidence":evidence}, "\t"))
	file.close()
	print("CONVOY COOP DEFENSE CHECKS: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
