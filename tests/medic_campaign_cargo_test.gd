extends SceneTree
## Actual victory callback with one previously debited finite SAN-1 unit.
## The durable checkpoint is isolated in artifacts; no player profile is saved.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const World = preload("res://scripts/network_world.gd")
const Schema = preload("res://scripts/network_replication_schema.gd")
var game
var medic
var crate
var mixer
var host_world: RefCounted
var checks := 0
var failures := 0
var isolated_path := "res://artifacts/san-logistics/campaign-cargo-%d.json" % OS.get_process_id()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CAMPAIGN CARGO ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)
func frames(count := 3):
	for index in count: await physics_frame
func reader(path: String) -> CampaignState:
	var state := CampaignState.new(path, false)
	state.persistence_enabled = true # This explicit path belongs only to this test.
	return state
func replication_probe():
	var snapshot: Dictionary = host_world.capture()
	var dynamic_stores: Array = snapshot.entities.filter(func(record): return record.type == "convoy_supply")
	check(dynamic_stores.size() == 5 and dynamic_stores.all(func(record): return record.id.begins_with("dynamic:") and record.state.amount == 0), "Research provisions five empty stores using audited dynamic network identities")
	var guest = load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	await process_frame
	guest.selected_characters.assign(["mara", "branko"])
	guest.network.set_physics_process(false)
	guest.network.active = true
	guest.network.is_host = false
	guest.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	guest.rounds.set_process(false)
	var guest_world := World.new()
	guest_world.bind(guest)
	var base_stores := get_nodes_in_group("supplies").filter(func(depot): return depot.game == guest)
	check(base_stores.size() == 5 and not guest.upgrades.has_upgrade("medic_collection"), "Fresh authenticated guest starts with only the five initial physical crates")
	var captured_ids: Dictionary = {}
	for record in snapshot.entities: captured_ids[record.id] = true
	for id: String in guest_world.entities:
		var node = guest_world.entities[id]
		if not captured_ids.has(id) and not Schema.kind(node) in Schema.DYNAMIC:
			print("SNAPSHOT PERMANENT DIFFERENCE ",id," ",Schema.kind(node))
	check(guest_world.apply(snapshot), "Normal host snapshot constructs the newly researched guest storage: "+guest_world.last_error)
	var replicated_stores := get_nodes_in_group("supplies").filter(func(depot): return depot.game == guest)
	check(replicated_stores.size() == 10 and guest.upgrades.has_upgrade("medic_collection") and guest.upgrades.has_upgrade("medic_logistics"), "Guest receives both independent research unlocks and exactly ten physical stores")
	check(guest.medic.logistics_cargo == "sand" and guest.medic.logistics_phase == "deliver" and not guest.medic.is_physics_processing(), "Carried SAN-1 unit and phase replicate without running guest-side inventory authority")
	for record in dynamic_stores:
		var depot = guest_world.entities.get(record.id)
		check(is_instance_valid(depot) and Schema.kind(depot) == "convoy_supply" and depot.kind == record.state.kind and depot.amount == 0 and depot.position == record.state.position, "Guest reconstructs the exact empty "+str(record.state.kind)+" storage at its stable dynamic ID")
	check(guest_world.apply(snapshot) and get_nodes_in_group("supplies").filter(func(depot): return depot.game == guest).size() == 10, "Repeated snapshot cannot create duplicate research stores")
	var guest_stock_before: Dictionary = guest.expedition._capture_stock()
	var original_cargo: String = guest.medic.logistics_cargo
	guest.medic.logistics.tick(1.25)
	guest.medic._physics_process(1.25)
	check(guest.medic.logistics_cargo == original_cargo and guest.expedition._capture_stock() == guest_stock_before, "Applying a real guest tick cannot duplicate or remotely deposit replicated SAN-1 cargo")
	await Cleanup.free_scene(guest,self)
	host_world = null
	guest_world = null

func remove_isolated_files() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(isolated_path+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_path+suffix))

func run():
	if not "--no-profile-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/san-logistics"))
	remove_isolated_files()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.selected_characters.assign(["mara", "branko"])
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	game.rounds.set_process(false)
	game.rounds.running = false
	medic = game.medic
	medic.set_physics_process(false)
	for station in get_nodes_in_group("stations"):
		station.set_process(false)
		if station.kind == "mixer": mixer = station
	for stock in get_nodes_in_group("supplies"):
		if stock.kind == "sand": crate = stock
	await frames()
	var campaign: CampaignState = game.campaign
	var controller = game.expedition
	campaign.save_path = isolated_path
	campaign.persistence_enabled = true
	check(campaign.active and campaign.mission_running and campaign.pending_node == CampaignCatalog.ENTRY, "Actual main scene begins a valid entry mission")
	check(CampaignState.valid_checkpoint(campaign.checkpoint()), "Prepared campaign checkpoint validates before any victory")
	check(campaign.save_checkpoint(), "Initial departure is durably written only to the isolated test path")
	var departure_reader := reader(isolated_path)
	check(departure_reader.load_checkpoint() and departure_reader.completed.is_empty(), "Isolated departure can be loaded before the mission completes")
	game.upgrades.owned = {"bunker_workshop":true, "medic_logistics":true, "medic_collection":true}
	game.upgrades.apply_world_effects()
	host_world = World.new()
	host_world.bind(game) # Bind fixed identities before the prepared carrying pose moves.
	var before: Dictionary = controller._capture_stock()
	var initial_sand: int = int(before.get("sand",0))
	var source_before: int = crate.amount
	medic.position = crate.position+Vector2(-28,0)
	medic.velocity = Vector2.ZERO
	medic.climbing = false
	medic.logistics.source = crate
	medic.logistics.station = mixer
	medic.logistics._resource = "sand"
	medic.logistics._destination = null
	medic.logistics_phase = "collect"
	await frames()
	medic.logistics._visit(crate,medic.logistics.handoff_time())
	check(medic.logistics_cargo == "sand" and crate.amount == source_before-1, "Normal local handoff debits exactly one finite crate unit into SAN-1 cargo")
	check(medic.logistics_phase == "deliver", "Victory fixture carries a real unfinished delivery")
	check(controller._capture_stock() == before, "Campaign stock capture includes the carried unit once without losing material")
	for repeat in 4:
		check(controller._capture_stock() == before and crate.amount == source_before-1 and medic.logistics_cargo == "sand", "Repeated pre-victory capture is read-only and conserves cargo, pass %d" % repeat)
	await replication_probe()
	var claim: String = campaign.mission_id
	var checkpoint_before: Dictionary = campaign.checkpoint()
	game.rounds.wave = Balance.TOTAL_WAVES-1
	check(not controller.on_victory() and medic.logistics_cargo == "sand" and crate.amount == source_before-1, "Unverified wave nineteen cannot bank or consume SAN-1 cargo")
	game.rounds.wave = Balance.TOTAL_WAVES
	game.network.active = true
	game.network.is_host = false
	check(not controller.on_victory() and medic.logistics_cargo == "sand", "A guest cannot commit the host's carried material")
	game.network.active = false
	game.network.is_host = true
	# The checkpoint is valid; the write fails because this owned test directory
	# deliberately does not exist. No production profile path is involved.
	campaign.save_path = "res://artifacts/san-logistics/missing-cargo-%d/never-created/save.json" % OS.get_process_id()
	check(not controller.on_victory(), "An actual failed durable victory commit is rejected")
	check(not campaign.last_error.is_empty(), "Failed disk commit provides the campaign's normal failure message")
	check(campaign.mission_running and campaign.mission_id == claim and campaign.completed.is_empty(), "Rejected commit restores the same still-running mission and claim")
	check(campaign.checkpoint() == checkpoint_before, "Rejected commit rolls the entire durable campaign ledger back")
	check(medic.logistics_cargo == "sand" and medic.logistics_phase == "deliver" and crate.amount == source_before-1, "Rejected commit retains SAN-1's original unit and physical delivery")
	check(controller._capture_stock() == before, "Rejected commit leaves the complete physical material ledger unchanged")
	var failure_reader := reader(isolated_path)
	check(failure_reader.load_checkpoint() and failure_reader.completed.is_empty(), "Failed commit preserves the previously written isolated departure")
	campaign.save_path = isolated_path
	check(controller.on_victory(), "Retrying the verified wave twenty commits the carried unit successfully")
	check(campaign.completed == [CampaignCatalog.ENTRY] and campaign.claimed_missions == [claim] and not campaign.mission_running, "Verified callback records exactly one completed site and claim")
	check(int(campaign.expedition.garage_stock.get("sand",0)) == initial_sand, "Committed garage stock owns exactly the original sand including the carried unit")
	check(medic.logistics_cargo.is_empty() and medic.logistics_phase == "idle" and medic.logistics_progress == 0.0, "Successful mirror clears the old cargo and handoff before materializing its stored unit")
	check(medic.logistics.source == null and medic.logistics.station == null and medic.route.is_empty(), "Successful mirror invalidates the old source, destination and physical route")
	check(crate.amount == source_before and controller._capture_stock() == before, "Victory stores the carried unit once while conserving the original total")
	check(CampaignState.valid_checkpoint(campaign.checkpoint()), "The committed campaign remains valid with the finite cargo stock")
	var success_reader := reader(isolated_path)
	check(success_reader.load_checkpoint() and success_reader.completed == [CampaignCatalog.ENTRY] and int(success_reader.expedition.garage_stock.get("sand",0)) == initial_sand, "The actual durable victory reloads with exactly the conserved cargo quantity")
	for repeat in 4:
		var captured: Dictionary = controller._capture_stock()
		controller._mirror_stock()
		check(captured == before and controller._capture_stock() == before and medic.logistics_cargo.is_empty() and crate.amount == source_before, "Repeated capture/mirror cannot recredit the previous SAN-1 unit, pass %d" % repeat)
	check(not controller.on_victory() and campaign.claimed_missions == [claim] and controller._capture_stock() == before, "Repeated victory cannot duplicate cargo or replay the completed claim")
	await Cleanup.free_scene(game,self)
	remove_isolated_files()
	check(not FileAccess.file_exists(isolated_path) and not FileAccess.file_exists(isolated_path+".bak"), "Isolated checkpoint files are removed without touching player profiles")
	var report := {"checks":checks,"failures":failures,"actual_main_scene":true,"actual_normal_debit":true,"finite_carried_units":1,"actual_durable_write_and_reload":true,"actual_failed_write_and_retry":true,"repeated_capture_and_mirror":4,"profile_saves":false,"actual_host_to_guest_research_and_storage_snapshot":true}
	var output := FileAccess.open("res://artifacts/san-logistics/campaign-cargo-verification.json",FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report,"\t"))
		output.close()
	print("MEDIC CAMPAIGN CARGO: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
