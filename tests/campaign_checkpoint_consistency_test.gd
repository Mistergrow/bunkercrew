extends SceneTree
## Structurally valid but inconsistent primary saves must use the good backup,
## rather than restoring initial crew or an impossible continuation route.
var checks := 0
var failures := 0
var fixture_root := ""

class CrewProbe extends Node:
	var player_id: int
	var character_id: String
	var progression := PlayerProgression.new()
	func _init(slot: int, character: String) -> void:
		player_id = slot
		character_id = character
		add_child(progression)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	fixture_root = ProjectSettings.globalize_path("res://artifacts/final-hardening-20261004/persistence/schema-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(fixture_root)==OK, "Semantic recovery uses only disposable artifact files")
	var path := fixture_root.path_join("campaign.json")
	var state := CampaignState.new(path, false)
	var crew: Array = [CrewProbe.new(1,"mara"), CrewProbe.new(2,"branko")]
	crew[1].progression.level = 3
	crew[1].progression.skill_points = 2
	check(state.begin_new({"environment":"ash_foundry", "build_type":"bastion", "position":"left"}, ["mara","branko"], 2), "Real campaign initializes two distinct crew slots")
	var mission := state.mission_start()
	check(not state.complete_mission(mission.id, Balance.TOTAL_WAVES, crew).is_empty(), "Real victory owns the second crew member's earned progression")
	check(state.select_destination("harbor") and not state.begin_journey().is_empty(), "Real departure creates a complete retry boundary")
	var valid := state.checkpoint()
	state.persistence_enabled = true
	check(state.save_checkpoint() and state.save_checkpoint(), "Real atomic writer establishes equal valid primary and backup")
	var cases: Dictionary = {}
	var invalid := valid.duplicate(true)
	invalid.current_node = ""
	cases.missing_current_site = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.departure.snapshots = {}
	cases.empty_departure_crew = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.departure.snapshots.erase("2")
	cases.missing_departure_crew = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.departure.snapshots["2"].character = "ivo"
	cases.wrong_departure_character = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.departure.destination = "quarry"
	cases.wrong_departure_destination = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.selected_stop = "harbor:fuel"
	cases.wrong_departure_stop = invalid
	invalid = valid.duplicate(true)
	invalid.expedition.selected_stop = "quarry:fuel"
	cases.foreign_selected_stop = invalid
	for label: String in cases:
		var malformed: Dictionary = cases[label]
		check(not CampaignState.valid_checkpoint(malformed), label+": semantic mismatch is refused before restoration")
		var file := FileAccess.open(path, FileAccess.WRITE)
		check(file!=null, "Write only the disposable semantic-corruption fixture")
		file.store_string(JSON.stringify(malformed))
		file.close()
		var reader := CampaignState.new(path, false)
		reader.persistence_enabled = true
		check(reader.load_checkpoint() and reader.recovered_backup, label+": reader chooses the actual good backup")
		check(JSON.parse_string(JSON.stringify(reader.checkpoint()))==JSON.parse_string(JSON.stringify(valid)), label+": recovered campaign retains all finite departure crew and route ownership")
	for member: Node in crew: member.free()
	for filename: String in DirAccess.get_files_at(fixture_root): DirAccess.remove_absolute(fixture_root.path_join(filename))
	DirAccess.remove_absolute(fixture_root)
	print("CHECKPOINT CONSISTENCY: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
