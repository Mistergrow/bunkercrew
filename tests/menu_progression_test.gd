extends SceneTree
## Prepared production campaign transitions; no played-through campaign claim.
const Preview := preload("res://scripts/menu_progression.gd")
var checks := 0
var failures := 0
var manifest: Dictionary = {}
var output := OS.get_environment("BUNKERCREW_MENU_FIXTURES")

class CrewProbe extends Node:
	var player_id := 1
	var character_id := "mara"
	var progression := PlayerProgression.new()
	func _init() -> void: add_child(progression)

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func record(id: String, state: CampaignState, expected: String) -> void:
	var data := state.checkpoint()
	check(CampaignState.valid_checkpoint(data), "Prepared checkpoint validates: " + id)
	check(Preview.environment_for(data) == expected, "Current reached world is used: " + id)
	manifest[id] = {"checkpoint":data, "environment":expected, "has_campaign":true}

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or output.is_empty():
		push_error("Use the isolated tests/menu_progression_restart_test.py runner")
		quit(2)
		return
	var crew := CrewProbe.new()
	var state := CampaignState.new("user://unused-menu-progression.json", false)
	check(state.begin_new({"environment":"ash_foundry"}, ["mara"], 1), "Prepared first campaign begins normally")
	record("first_defense", state, "ash_foundry")
	var custom := CampaignState.new("user://unused-menu-custom.json", false)
	check(custom.begin_new({"environment":"frozen_rail_yard"}, ["mara"], 1), "Custom first bunker keeps its selected world")
	record("custom_first", custom, "frozen_rail_yard")
	var sequence := ["last_shift", "harbor", "dam_vault", "quarry", "refinery_archive", "steelworks", "rail_yard", "radar_archive", "canyon", "buried_archive", "power_station", "mountain_pass"]
	for index in sequence.size():
		var id: String = sequence[index]
		var world: String = CampaignCatalog.node(id).environment
		if index > 0:
			if int(CampaignCatalog.node(id).cost) > 0: check(state.unlock_route(id), "Prepared strategic route unlocks: " + id)
			var origin: String = CampaignCatalog.node(state.current_node).environment
			check(state.select_destination(id), "Destination selection is valid: " + id)
			record(id + "_map", state, origin)
			if id == "quarry": check(state.select_stop("quarry:salvage"), "Prepared optional stop belongs to current journey")
			check(not state.begin_journey().is_empty(), "Journey has a durable departure: " + id)
			record(id + "_travel", state, origin)
			if id == "quarry":
				check(state.reach_stop(), "Optional stop can be reached")
				record("quarry_stop", state, origin)
				check(not state.secure_stop().is_empty(), "Finite optional reward can be secured")
				record("quarry_after_stop", state, origin)
			check(state.arrive_at_destination(), "Actual approach enters occupation: " + id)
			record(id + "_occupation", state, world)
			if id == "quarry":
				state.fail_journey()
				record("quarry_failed", state, origin)
				check(not state.retry_journey().is_empty() and state.arrive_at_destination(), "Failed approach restores its durable route")
			check(state.secure_destination(), "Secured approach permits defense: " + id)
			record(id + "_defense", state, world)
		var mission := state.mission_start()
		check(not mission.is_empty(), "Prepared mission starts: " + id)
		check(state.reserve_drop(id, 3) and state.collect_salvage(id, 3), "Prepared finite salvage funds strategic branches")
		var result := state.complete_outpost(mission.id, 0, true, [crew]) if CampaignCatalog.site_kind(id) == "outpost" else state.complete_mission(mission.id, 20, [crew])
		check(not result.is_empty(), "Prepared completion is accepted: " + id)
		record(id + "_preparation", state, world)
	# Reject structurally invalid JSON and preserve old formats without rewriting.
	var legacy: Dictionary = manifest.harbor_preparation.checkpoint.duplicate(true)
	legacy.version = 1
	legacy.erase("expedition")
	for snapshot: Dictionary in legacy.snapshots.values(): snapshot.erase("ammunition")
	check(CampaignState.valid_checkpoint(legacy), "Existing V1 checkpoint remains valid")
	manifest.legacy = {"checkpoint":legacy, "environment":"abandoned_harbor", "has_campaign":true}
	manifest.missing = {"environment":"ash_foundry", "has_campaign":false}
	manifest.corrupt = {"raw":"{broken-json", "environment":"ash_foundry", "has_campaign":false}
	manifest.oversized = {"raw":" ".repeat(CampaignState.MAX_SAVE_BYTES+1), "environment":"ash_foundry", "has_campaign":false}
	var invalid: Dictionary = legacy.duplicate(true)
	invalid.pending_node = "not_a_real_place"
	manifest.invalid = {"checkpoint":invalid, "environment":"ash_foundry", "has_campaign":false}
	manifest.backup_only = {"backup":legacy, "environment":"abandoned_harbor", "has_campaign":true}
	manifest.backup_corrupt_primary = {"raw":"{partial", "backup":manifest.radar_archive_preparation.checkpoint, "environment":"radar_highlands", "has_campaign":true}
	manifest.primary_preferred = {"checkpoint":manifest.rail_yard_preparation.checkpoint, "backup":legacy, "environment":"frozen_rail_yard", "has_campaign":true}
	manifest.disabled_reads = {"checkpoint":manifest.rail_yard_preparation.checkpoint, "environment":"ash_foundry", "has_campaign":false, "disabled":true}
	var directory_result := DirAccess.make_dir_recursive_absolute(output)
	check(directory_result == OK, "Isolated fixture folder is writable")
	var path := output.path_join("manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Prepared checkpoint manifest opens")
	if file != null:
		file.store_string(JSON.stringify(manifest))
		file.close()
	crew.free()
	print("MENU PROGRESSION: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
