extends SceneTree
## A guest validates the inner contents of replicated containers and string
## enums, not only their outer type, before any world state is applied.
const Schema := preload("res://scripts/network_replication_schema.gd")
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("REPLICA RULES PASS ", label)
	else:
		failures += 1
		push_error(label)

func scene() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(2, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	return game

func record_of(snapshot: Dictionary, kind: String) -> Dictionary:
	for record: Dictionary in snapshot.entities:
		if record.type == kind: return record
	return {}

func test_rules() -> void:
	var listed := {
		"player_progression":["skills"], "upgrade_system":["owned"],
		"station":["transfer"], "deep_station":["transfer", "ingredient_amounts"], "glass_furnace":["transfer", "ingredient_amounts"],
		"supply":["transfer", "deposit_transfer"], "convoy_supply":["transfer", "deposit_transfer"],
		"mine_block":["exposed_sides"], "flak_station":["materials", "transfer"], "dome_controller":["materials", "transfer"],
		"worker_medical":["state", "recovery_kind", "aid_kind"], "wall":["work_action"], "worker_weapon":["_reload_kind"],
	}
	for kind: String in listed:
		for field: String in listed[kind]:
			check(Schema.rules(kind).has(field) and field in Schema.fields(kind), "A replicated field has an inner rule: %s.%s" % [kind, field])
	check(Schema.rules("core").is_empty() and Schema.rules("unknown").is_empty(), "Kinds without containers carry no rule")
	var skills: Array = Schema.rules("player_progression").skills
	check(Schema.satisfies({"vitality":0, "combat":5, "engineering":2}, skills), "Real skill ranks are accepted")
	# A campaign checkpoint read from JSON restores ranks as whole-number floats.
	check(Schema.satisfies({"vitality":1.0, "combat":0.0, "engineering":5.0}, skills), "Skill ranks restored from a saved checkpoint are accepted")
	var restored: Dictionary = JSON.parse_string(JSON.stringify({"vitality":2, "combat":1, "engineering":0}))
	check(restored.vitality is float and Schema.valid_state("player_progression", {"level":4, "xp":12.5, "kills":0, "combo":0, "combo_time":0.0, "skill_points":0, "skills":restored, "armor_tier":1}), "A progression state restored through JSON passes the replica validator")
	for wrong in [{"vitality":0, "combat":0}, {"vitality":0, "combat":0, "engineering":6}, {"vitality":0, "combat":0, "engineering":-1}, {"vitality":0, "combat":0, "engineering":1.5}, {"vitality":0, "combat":0, "engineering":INF}, {"vitality":0, "combat":0, "engineering":"1"}, {"vitality":0, "combat":0, "luck":1}, [], "x"]:
		check(not Schema.satisfies(wrong, skills), "Invalid skill ranks are refused: " + str(wrong))
	var owned: Array = Schema.rules("upgrade_system").owned
	check(Schema.satisfies({}, owned) and Schema.satisfies({"boots":true, "weapon_pouches":true}, owned), "Purchased research is accepted")
	for id: String in CampaignCatalog.PERSISTENT_UPGRADES: check(Schema.satisfies({id:true}, owned), "Portable campaign research is a known node: " + id)
	for wrong in [{"jetpack":true}, {"boots":false}, {"boots":1}, {1:true}, []]:
		check(not Schema.satisfies(wrong, owned), "Invalid research is refused: " + str(wrong))
	var timers: Array = Schema.rules("supply").transfer
	check(Schema.satisfies({}, timers) and Schema.satisfies({1:0.2, "@player:2":0, 3:Balance.TRANSFER_TIME}, timers), "Hold timers keyed by player are accepted")
	for wrong in [{1:"x"}, {1:-0.1}, {1:[0.1]}, {"owner":0.1}, {[1]:0.1}, {1.5:0.1}, {"@player:" + "9".repeat(20):0.1}, []]:
		check(not Schema.satisfies(wrong, timers), "Invalid hold timers are refused: " + str(wrong))
	var crowded := {}
	for index in Schema.MAX_TIMERS + 1: crowded[index] = 0.0
	check(not Schema.satisfies(crowded, timers), "More timers than any crew can hold are refused")
	var stock: Array = Schema.rules("flak_station").materials
	check(Schema.satisfies({"steel":3, "concrete":2, "ammo":1}, stock) and Schema.satisfies({}, stock), "Paid construction materials are accepted")
	for wrong in [{"gold":1}, {"steel":-1}, {"steel":1.5}, {"steel":"3"}, {"steel":10001}, "steel"]:
		check(not Schema.satisfies(wrong, stock), "Invalid material buffers are refused: " + str(wrong))
	var sides: Array = Schema.rules("mine_block").exposed_sides
	check(Schema.satisfies({Vector2i.LEFT:true, Vector2i.RIGHT:false, Vector2i.UP:true, Vector2i.DOWN:false}, sides) and Schema.satisfies({}, sides), "Exposed earth faces are accepted")
	for wrong in [{Vector2i(2, 0):true}, {Vector2i.LEFT:1}, {"left":true}, {Vector2.LEFT:true}]:
		check(not Schema.satisfies(wrong, sides), "Invalid earth faces are refused: " + str(wrong))
	for value: String in ["healthy", "wounded", "downed", "critical"]: check(Schema.satisfies(value, Schema.rules("worker_medical").state), "Medical state is accepted: " + value)
	for value: String in ["", "bandage", "splint", "revive", "resuscitate"]: check(Schema.satisfies(value, Schema.rules("worker_medical").aid_kind) and Schema.satisfies(value, Schema.rules("worker_medical").recovery_kind), "Aid kind is accepted: " + value)
	for value: String in ["", "form", "reinforce", "pour", "repair", "upgrade"]: check(Schema.satisfies(value, Schema.rules("wall").work_action), "Wall work is accepted: " + value)
	for value: String in WorkerWeapon.WEAPONS: check(Schema.satisfies(value, Schema.rules("worker_weapon")._reload_kind), "Reloading weapon is accepted: " + value)
	check(Schema.satisfies("", Schema.rules("worker_weapon")._reload_kind), "No reload in progress is accepted")
	for pair in [["worker_medical", "state"], ["worker_medical", "aid_kind"], ["wall", "work_action"], ["worker_weapon", "_reload_kind"]]:
		for wrong in ["zombie", "Healthy", 0, null, ["healthy"]]:
			check(not Schema.satisfies(wrong, Schema.rules(pair[0])[pair[1]]), "An unknown %s.%s is refused: %s" % [pair[0], pair[1], str(wrong)])

func test_world() -> void:
	var host := scene()
	var worker = host.players[0]
	worker.progression.skills.combat = 2
	worker.medical.bleeding = 1
	worker.medical.state = "wounded"
	worker.medical.recovery_kind = "revive"
	worker.medical.recovery_time = 0.4
	worker.get_node("WorkerWeapon")._reload_kind = "rifle"
	host.upgrades.owned = {"boots":true, "bunker_workshop":true}
	host.flak_station.materials = {"steel":2, "concrete":1}
	host.flak_station.transfer = {1:0.1}
	host.dome.materials = {"glass":3}
	host.dome.transfer = {worker.get_instance_id():0.2}
	var authority := World.new()
	authority.bind(host)
	var captured: Dictionary = authority.capture()
	for kind: String in ["supply", "station", "wall", "mine_block"]:
		var source: Node = authority.entities[record_of(captured, kind).id]
		if kind == "supply":
			source.transfer = {1:0.15}
			source.deposit_transfer = {2:0.05}
		elif kind == "station": source.transfer = {host.players[1].get_instance_id():0.25}
		elif kind == "wall": source.work_action = "form"
	captured = authority.capture()
	var snapshot: Dictionary = Protocol.decode(Protocol.encode_trusted({"kind":"snapshot", "seq":1, "generation":1, "paused":false, "world":captured, "achievements":[]})).get("world", {})
	check(record_of(snapshot, "dome_controller").state.transfer == {"@player:1":0.2} and record_of(snapshot, "station").state.transfer == {"@player:2":0.25}, "Hold timers cross the wire keyed by player, not by a host object ID")
	await Cleanup.free_scene(host, self)
	var guest := scene()
	var replica := World.new()
	replica.bind(guest)
	var mutations := [
		["player_progression", "skills", {"vitality":0, "combat":0}], ["player_progression", "skills", {"vitality":0, "combat":9, "engineering":0}],
		["upgrade_system", "owned", {"jetpack":true}], ["upgrade_system", "owned", {"boots":0}],
		["station", "transfer", {"@player:1":"soon"}], ["station", "transfer", {"@player:1":-1.0}],
		["supply", "transfer", {1:{}}], ["supply", "deposit_transfer", {"anyone":0.1}],
		["mine_block", "exposed_sides", {Vector2i(9, 9):true}], ["mine_block", "exposed_sides", {Vector2i.LEFT:"open"}],
		["flak_station", "materials", {"gold":1}], ["flak_station", "transfer", {1:[1]}],
		["dome_controller", "materials", {"steel":"4"}], ["dome_controller", "transfer", {"@player:1":-0.5}],
		["worker_medical", "state", "zombie"], ["worker_medical", "recovery_kind", "nap"], ["worker_medical", "aid_kind", "hug"],
		["wall", "work_action", "explode"], ["worker_weapon", "_reload_kind", "bazooka"],
	]
	var core_hp: float = guest.core.hp
	for mutation in mutations:
		var copy: Dictionary = snapshot.duplicate(true)
		var record := record_of(copy, mutation[0])
		check(not record.is_empty() and record.state.has(mutation[1]), "The real world replicates %s.%s" % [mutation[0], mutation[1]])
		if record.is_empty(): continue
		record.state[mutation[1]] = mutation[2]
		check(not replica.apply(copy, true) and replica.last_error.begins_with("Invalid entity values"), "A guest refuses %s.%s = %s (%s)" % [mutation[0], mutation[1], str(mutation[2]), replica.last_error])
	check(guest.core.hp == core_hp and not replica._applied, "Refused snapshots change nothing on the guest")
	check(replica.apply(snapshot, true), "The unmodified host world, with real non-default contents, is accepted: " + replica.last_error)
	var mirrored = guest.players[0]
	check(mirrored.progression.skills == {"vitality":0, "combat":2, "engineering":0} and mirrored.medical.state == "wounded" and mirrored.medical.recovery_kind == "revive" and mirrored.get_node("WorkerWeapon")._reload_kind == "rifle", "Player containers and enums arrive unchanged")
	check(guest.upgrades.owned == {"boots":true, "bunker_workshop":true} and guest.flak_station.materials == {"steel":2, "concrete":1} and guest.dome.materials == {"glass":3}, "Research and construction buffers arrive unchanged")
	check(guest.dome.transfer == {mirrored.get_instance_id():0.2} and guest.flak_station.transfer == {1:0.1}, "Hold timers are mapped back to the guest's own player objects")
	paused = false
	check(await Cleanup.free_scene(guest, self), "The replica fixture releases its scene and audio handles")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	test_rules()
	await test_world()
	print("REPLICA RULES: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
