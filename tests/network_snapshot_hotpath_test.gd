extends SceneTree
## Authentic four-player snapshots retain field/graph boundaries in the hot path.
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Excavation := preload("res://tests/scenario_excavation_fixture.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/code-optimization-20261004/network/"
var checks := 0
var failures := 0
var measurements: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SNAPSHOT HOTPATH ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func scene() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(4, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	game.rounds.wave = 20
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
	return game

func entity(snapshot: Dictionary, id: String) -> Dictionary:
	for record: Dictionary in snapshot.entities:
		if record.id == id:
			return record
	return {}

func reject(replica: RefCounted, snapshot: Dictionary, label: String) -> void:
	var saved_health: float = replica.game.core.hp
	var saved_stats: Dictionary = replica.game.stats.duplicate(true)
	check(not replica.apply(snapshot, true), label)
	check(replica.game.core.hp == saved_health and replica.game.stats == saved_stats, "Rejected state cannot partially mutate authoritative health/counters")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var host := scene()
	var authority := World.new()
	var worker = host.players[0]
	for index in 3:
		check(await Excavation.build_room(host, index, worker), "Real mining, paid supports and curing complete room %d" % index)
	check(host.scenario_bunker.prepare_excavation(3), "The fourth excavation still contains its real unmined cells")
	host.view_stage = 4
	host.update_scenario_camera()
	for index in 40:
		var enemy = host._entity("enemy", Vector2(1000 + index * 12, 430), {"kind":"strider", "wave":16})
		enemy.set_physics_process(false)
	authority.bind(host)
	var captured: Dictionary = authority.capture()
	var packet := {"kind":"snapshot", "seq":1, "generation":1, "paused":false, "world":captured, "achievements":[]}
	if is_instance_valid(host.audio.live_music): packet.music = host.audio.live_music.get_music_state()
	var encoded := Protocol.encode_trusted(packet)
	var decoded := Protocol.decode(encoded)
	check(preload("res://scripts/network_messages.gd").valid(decoded, false) and not decoded.is_empty() and decoded.world == captured, "The authentic compressed wire preserves every entity state")
	var snapshot: Dictionary = decoded.get("world", {})
	var fields := 0
	for record: Dictionary in snapshot.get("entities", []):
		fields += record.state.size()
	measurements.entities = snapshot.get("entities", []).size()
	measurements.state_fields = fields
	measurements.compressed_bytes = encoded.size()
	await Cleanup.free_scene(host, self)
	var guest := scene()
	var replica := World.new()
	replica.bind(guest)
	check(replica.apply(snapshot, true), "The guest reconstructs four players, forty machines and four excavation levels: " + replica.last_error)
	if not replica.last_error.is_empty():
		await Cleanup.free_scene(guest, self)
		quit(1)
		return
	check(guest.players.size() == 4 and guest.scenario_bunker.excavation_depths == 4 and guest.scenario_bunker.open_depths == 3, "Actual reconstructed world retains the complete mixed structure")
	check(guest.scenario_bunker.fields[3].blocks.size() == 30, "Unexcavated earth remains present in the open fourth shaft")
	var immutable := snapshot.duplicate(true)
	for _iteration in 5:
		replica._validate(snapshot, true)
	var validation_times: Array[int] = []
	for _iteration in 80:
		var started := Time.get_ticks_usec()
		var accepted: bool = replica._validate(snapshot, true)
		validation_times.append(Time.get_ticks_usec() - started)
		if not accepted:
			check(false, "Repeated full validation accepts the unchanged authentic state")
	validation_times.sort()
	measurements.validation_median_usec = validation_times[40]
	measurements.validation_p95_usec = validation_times[76]
	var apply_times: Array[int] = []
	for _iteration in 30:
		var started := Time.get_ticks_usec()
		var accepted: bool = replica.apply(snapshot, true)
		apply_times.append(Time.get_ticks_usec() - started)
		if not accepted:
			check(false, "Repeated actual application accepts the unchanged authentic state")
	apply_times.sort()
	measurements.apply_median_usec = apply_times[15]
	measurements.apply_p95_usec = apply_times[28]
	check(snapshot == immutable, "Repeated validation/application never changes the original decoded input")
	check(guest.players.all(func(player): return not player.is_physics_processing()), "Replica workers remain unable to simulate duplicate gameplay")
	var malformed := snapshot.duplicate(true)
	entity(malformed, "player:1").state.unlisted_property = 1
	reject(replica, malformed, "Unknown player fields are rejected even after the type table is warm")
	malformed = snapshot.duplicate(true)
	entity(malformed, "player:1").state.visible = 1
	reject(replica, malformed, "A common boolean transform cannot become an integer")
	malformed = snapshot.duplicate(true)
	entity(malformed, "player:1").state.rotation = Vector2.ZERO
	reject(replica, malformed, "A common float transform cannot become a vector")
	malformed = snapshot.duplicate(true)
	entity(malformed, "player:1").state.erase("z_index")
	reject(replica, malformed, "The required fourth common transform remains mandatory")
	malformed = snapshot.duplicate(true)
	entity(malformed, "player:1").state.hp = "healthy"
	reject(replica, malformed, "Declared actor health type remains validated independently of its value")
	var machine_id := ""
	for record: Dictionary in snapshot.entities:
		if record.type=="enemy":
			machine_id=record.id
			break
	check(not machine_id.is_empty(), "The warmed guest contains an actual reconstructed machine")
	malformed = snapshot.duplicate(true)
	entity(malformed, machine_id).state.erase("gait")
	reject(replica, malformed, "A cached machine type still requires its declared gait field")
	malformed = snapshot.duplicate(true)
	entity(malformed, machine_id).state.gait = Vector2.ZERO
	reject(replica, malformed, "A cached declared float still rejects a finite vector")
	malformed = snapshot.duplicate(true)
	entity(malformed, machine_id).state.profile.speed += 1.0
	reject(replica, malformed, "Warmed field tables cannot accept a modified machine profile")
	malformed = snapshot.duplicate(true)
	entity(malformed, "fixed:scenario_room_site:3").state.support_materials = {"steel":1}
	reject(replica, malformed, "The fourth shaft cannot receive construction before its own earth is excavated")
	malformed = snapshot.duplicate(true)
	entity(malformed, "fixed:scenario_room_site:2").state.position += Vector2(1, 0)
	reject(replica, malformed, "A finished room cannot move after the graph cache is warm")
	var valid := snapshot.duplicate(true)
	entity(valid, "player:1").state.rotation = 0
	check(replica.apply(valid, true), "An integer remains compatible with a declared float transform")
	valid = snapshot.duplicate(true)
	entity(valid, machine_id).state.gait = 0
	check(replica.apply(valid, true), "An integer remains compatible with a cached declared machine float")
	check(replica.apply(snapshot, true), "Valid authoritative state still recovers immediately after malformed candidates")
	await Cleanup.free_scene(guest, self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var suffix := "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var report := FileAccess.open(OUTPUT + "snapshot-hotpath-" + suffix + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks, "failures":failures, "measurements":measurements, "prepared_state":"Real four-player scenario, fixture-supplied construction cargo paid through native interaction, three physically excavated/cured rooms, fourth shaft with thirty real earth cells, forty frozen strider machines. Protocol compression/decode precedes guest validation and actual application. Headless script timings are comparative and exclude rendering/network/microphone."}, "\t") + "\n")
	print("SNAPSHOT HOTPATH: %d/%d passed; %s" % [checks - failures, checks, JSON.stringify(measurements)])
	quit(1 if failures else 0)
