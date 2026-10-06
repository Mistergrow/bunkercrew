extends SceneTree
## Uninstalled content is recoverable installation state, not save corruption.
const Content := preload("res://scripts/content_registry.gd")
var checks := 0
var failures := 0
var fixture_root := ""

class CrewProbe extends Node:
	var player_id: int
	var character_id: String
	var progression := PlayerProgression.new()
	func _init(slot: int,character: String) -> void:
		player_id = slot
		character_id = character
		add_child(progression)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func write_document(path: String,data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"Only the isolated fixture file is writable")
	if file!=null:
		file.store_string(JSON.stringify(data,"\t"))
		file.close()

func preserves_content(path: String,document: Dictionary,good: Dictionary,label: String) -> void:
	write_document(path,document)
	write_document(path+".bak",good)
	var primary_hash := FileAccess.get_sha256(path)
	var backup_hash := FileAccess.get_sha256(path+".bak")
	var reader := CampaignState.new(path,false)
	reader.persistence_enabled = true
	check(not reader.load_checkpoint() and not reader.recovered_backup and not reader.active,label+": unavailable primary stops before fallback or partial restore")
	check(not reader.last_error.is_empty() and "Spielstand bleibt unverändert" in reader.last_error,label+": error explains installation recovery and preservation")
	check(FileAccess.get_sha256(path)==primary_hash and FileAccess.get_sha256(path+".bak")==backup_hash,label+": load preserves primary and backup bytes")
	check(not reader.begin_new({"environment":"sector07"},["mara"],1) and not reader.active,label+": new campaign cannot implicitly replace this content-dependent save")
	check(FileAccess.get_sha256(path)==primary_hash and FileAccess.get_sha256(path+".bak")==backup_hash and not FileAccess.file_exists(path+".tmp"),label+": failed commit preserves both files without a temporary replacement")
	var direct := CampaignState.new(path,false)
	check(direct.begin_new({"environment":"sector07"},["mara"],1),label+": in-memory fixture initializes independently")
	direct.persistence_enabled = true
	check(not direct.save_checkpoint() and not direct.mark_air_raid_intro_seen(),label+": ordinary save and intro patch both respect durable content ownership")
	check(FileAccess.get_sha256(path)==primary_hash and FileAccess.get_sha256(path+".bak")==backup_hash,label+": every writer retains the original bytes")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	LocaleText.set_locale("de",false)
	fixture_root = ProjectSettings.globalize_path("res://artifacts/content-registry-20261005/save-fixture-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(fixture_root)==OK,"Save compatibility uses a disposable directory inside the copied project")
	var path := fixture_root.path_join("campaign.json")
	var state := CampaignState.new(path,false)
	var crew: Array = [CrewProbe.new(1,"mara"),CrewProbe.new(2,"branko")]
	check(state.begin_new({"environment":"ash_foundry"},["mara","branko"],2),"Current core campaign starts normally")
	var mission := state.mission_start()
	check(not state.complete_mission(mission.id,Balance.TOTAL_WAVES,crew).is_empty(),"Actual victory supplies valid durable snapshots")
	check(state.select_destination("harbor") and not state.begin_journey().is_empty(),"Actual departure supplies retry crew and vehicle cargo")
	var good := state.checkpoint()
	check(CampaignState.valid_checkpoint(good) and not good.has("content_requirements"),"Core-only checkpoint remains byte-schema compatible without optional add-on metadata")
	var cases: Dictionary = {}
	var changed := good.duplicate(true)
	changed.options.environment = "missing.pack:yard"
	cases.environment = changed
	changed = good.duplicate(true)
	changed.character_ids[1] = "missing.pack:worker"
	cases.character = changed
	changed = good.duplicate(true)
	changed.snapshots["1"].inventory["missing.pack:copper"] = 3
	cases.inventory = changed
	changed = good.duplicate(true)
	changed.expedition.garage_stock["missing.pack:copper"] = 7
	cases.garage_stock = changed
	changed = good.duplicate(true)
	changed.expedition.vehicle.cargo["missing.pack:copper"] = 2
	cases.vehicle_cargo = changed
	changed = good.duplicate(true)
	changed.expedition.departure.snapshots["2"].character = "missing.pack:worker"
	cases.departure_character = changed
	changed = good.duplicate(true)
	changed.expedition.departure.vehicle.cargo["missing.pack:copper"] = 5
	cases.departure_cargo = changed
	changed = good.duplicate(true)
	changed.pending_node = "missing.pack:chapter"
	cases.unsupported_future_route = changed
	for label: String in cases:
		check(not CampaignState.missing_content_ids(cases[label]).is_empty(),label+": unavailable namespace has an explicit diagnostic")
		preserves_content(path,cases[label],good,label)
	# Namespaced base stop IDs are not external pack IDs or opaque claim IDs.
	check(CampaignState.missing_content_ids(good).is_empty(),"Known colon-separated stop/mission IDs are not mislabeled as missing add-on content")
	var corrupt := good.duplicate(true)
	corrupt.options.environment = "misspelled_core_environment"
	write_document(path,corrupt)
	write_document(path+".bak",good)
	var recovered := CampaignState.new(path,false)
	recovered.persistence_enabled = true
	check(recovered.load_checkpoint() and recovered.recovered_backup,"Ordinary malformed core selection retains the existing valid backup-recovery path")
	check(JSON.parse_string(JSON.stringify(recovered.checkpoint()))==JSON.parse_string(JSON.stringify(good)),"Backup recovery retains exact durable route and crew state")
	var missing_backup: Dictionary = cases.environment
	write_document(path,{"corrupt":true})
	write_document(path+".bak",missing_backup)
	var backup_hash := FileAccess.get_sha256(path+".bak")
	var blocked := CampaignState.new(path,false)
	blocked.persistence_enabled = true
	check(not blocked.load_checkpoint() and not blocked.recovered_backup and FileAccess.get_sha256(path+".bak")==backup_hash,"Unavailable content in the recovery backup is diagnosed and preserved too")
	for requirement: Variant in [null,{},[{"id":"missing.pack","version":"1"},{"id":"missing.pack","version":"1"}],[{"id":"missing.pack","version":1}]]:
		changed = good.duplicate(true)
		changed.content_requirements = requirement
		check(not CampaignState.valid_checkpoint(changed),"Malformed optional requirement metadata is refused without widening the checkpoint schema")
	changed = good.duplicate(true)
	changed.content_requirements = [{"id":"missing.pack","version":"1"}]
	preserves_content(path,changed,good,"missing_used_pack_version")
	if "--expect-addon" in OS.get_cmdline_user_args():
		check(Content.contains("environments","beta.fixture:yard"),"Add-on probe runs with the actual installed fixture")
	if "--expect-addon" in OS.get_cmdline_user_args() and Content.contains("environments","beta.fixture:yard"):
		var addon := CampaignState.new(path,false)
		check(addon.begin_new({"environment":"beta.fixture:yard"},["mara"],1),"Registered scenario can start an actual new campaign")
		var saved := addon.checkpoint()
		check(saved.options.environment=="beta.fixture:yard" and saved.get("content_requirements",[]).size()==1 and saved.content_requirements[0].id=="beta.fixture","Only the used add-on namespace is recorded in a new checkpoint")
		check(CampaignState.valid_checkpoint(saved),"Current installed used-pack version is valid")
		var older := saved.duplicate(true)
		older.erase("content_requirements")
		check(CampaignState.valid_checkpoint(older),"Older add-on checkpoints without optional requirement metadata remain accepted")
		changed = saved.duplicate(true)
		changed.content_requirements[0].version = "different-version"
		preserves_content(path,changed,good,"changed_used_pack_version")
	for member: Node in crew: member.free()
	for filename: String in DirAccess.get_files_at(fixture_root): DirAccess.remove_absolute(fixture_root.path_join(filename))
	DirAccess.remove_absolute(fixture_root)
	print("CAMPAIGN CONTENT COMPATIBILITY: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
