extends SceneTree
## Persistence fixtures are intentionally isolated under the artifact directory.
## The production user:// sidecar and all profile/campaign saves stay untouched.
const Records := preload("res://scripts/solo_story_state.gd")
const Catalog := preload("res://scripts/solo_story_catalog.gd")
var checks := 0
var failures := 0
var fixture_root := ""

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(detail)

func _data() -> Dictionary:
	return {"version":1,"campaign_id":"state-fixture","events":[],"met":[],"recruited":[],"visited":[]}

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Fixture can write only its dedicated artifact path")
	if file != null:
		file.store_string(text)
		file.close()

func _memory(path: String) -> RefCounted:
	return Records.new(path, false)

func _persistent(path: String) -> RefCounted:
	var result := Records.new(path, true)
	# --no-profile-save remains active for the whole process. The sole exception
	# is this test-owned custom file, deliberately exercising the real writer.
	result.persistence_enabled = true
	return result

func _run() -> void:
	LocaleText.set_locale("de", false)
	fixture_root = ProjectSettings.globalize_path("res://artifacts/solo-story/runtime/state-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(fixture_root) == OK, "Create an isolated state fixture directory")
	_validation()
	_memory_continuity()
	_persistent_recovery()
	_write_rollback()
	print("Solo story state: %d/%d checks passed" % [checks-failures, checks])
	_cleanup(fixture_root)
	quit(1 if failures else 0)

func _validation() -> void:
	var base := _data()
	check(Records.valid(base), "A new empty chapter ledger is valid")
	for malformed in [null, true, 1, "", [], {"version":1}]:
		check(not Records.valid(malformed), "Malformed top-level ledger is refused")
	for version in [null, true, false, "1", "wrong", [], {}, -1, 0, 2, INF, NAN]:
		var data := base.duplicate(true)
		data.version = version
		check(not Records.valid(data), "Malformed or unsupported version is refused")
	check(Records.valid(JSON.parse_string(JSON.stringify(base))), "JSON numeric version survives a real decoder round-trip")
	for campaign in [null, true, 1, [], {}, "", "x".repeat(81)]:
		var data := base.duplicate(true)
		data.campaign_id = campaign
		check(not Records.valid(data), "Missing, oversized or non-string campaign identity is refused")
	var extra := base.duplicate(true)
	extra.unknown_field = true
	check(not Records.valid(extra), "Unrecognized ledger fields cannot carry gameplay state")
	for key: String in ["events", "met", "recruited", "visited"]:
		for malformed in [null, true, 1, "[]", {}, [null], [true], [1], ["unknown"]]:
			var data := base.duplicate(true)
			data[key] = malformed
			check(not Records.valid(data), "Invalid ledger array or identifier is refused: " + key)
		var omitted := base.duplicate(true)
		omitted.erase(key)
		check(not Records.valid(omitted), "All four ledger arrays are mandatory")
	var valid := base.duplicate(true)
	for site: Dictionary in CampaignCatalog.NODES:
		valid.visited.append(str(site.id))
	for person: Dictionary in Catalog.profiles():
		valid.met.append(str(person.id))
		valid.recruited.append(str(person.id))
	valid.events = Catalog.entry_ids()
	check(Records.valid(valid), "All authored sites, people and entries form a valid complete ledger")
	for key: String in ["events", "met", "recruited", "visited"]:
		var duplicate := valid.duplicate(true)
		duplicate[key].append(duplicate[key][0])
		check(not Records.valid(duplicate), "Duplicate ledger IDs are refused: " + key)
	var unmet := base.duplicate(true)
	unmet.visited = ["quarry"]
	unmet.recruited = ["oskar"]
	check(not Records.valid(unmet), "Recruitment requires actual recorded contact")
	unmet.met = ["oskar"]
	check(Records.valid(unmet), "Recruitment is valid after contact at the actual site")
	unmet.visited = ["harbor"]
	check(not Records.valid(unmet), "A person cannot be met or rescued at another location")
	var unread := base.duplicate(true)
	unread.events = ["last_shift:arrival"]
	check(not Records.valid(unread), "Journal entry cannot precede visiting its actual location")
	unread.visited = ["last_shift"]
	check(Records.valid(unread), "Arrival entry is valid at its visited location")

func _memory_continuity() -> void:
	var path := fixture_root.path_join("never-written.json")
	var state := _memory(path)
	check(not state.persistence_enabled and not state.load_records(), "No-profile sessions do not read persistent records")
	check(not state.mark("visited", "last_shift"), "A record cannot precede campaign initialization")
	check(not state.begin("") and not state.begin("x".repeat(81)), "Invalid campaign identities leave the ledger empty")
	check(state.begin("session-a"), "No-profile sessions initialize in memory")
	check(state.matches("session-a") and not state.matches("") and not state.matches("session-b"), "Ledger identity selects only its own campaign")
	for site: Dictionary in CampaignCatalog.NODES:
		check(state.mark("visited", str(site.id)), "Each real visited site can be recorded without saving")
	for person: Dictionary in Catalog.profiles():
		check(state.mark("met", str(person.id)), "Each real NPC contact can be recorded")
		check(state.mark("recruited", str(person.id)), "Each admitted NPC can be recorded after contact")
	for id: String in Catalog.entry_ids():
		check(state.mark("events", id), "Every authored entry is accepted at its visited site")
		check(state.mark("events", id), "Repeated callbacks remain idempotent")
	check(state.events.size() == 89, "Repeated callbacks do not duplicate the journal")
	var snapshot: Dictionary = state.capture()
	check(state.begin("session-a") and state.capture() == snapshot, "Repeated begin preserves same-campaign progress")
	for key: String in ["events", "met", "recruited", "visited", "campaign_id", "unknown"]:
		check(not state.mark(key, "not-real") and state.capture() == snapshot, "Unknown keys or IDs cannot alter the ledger")
	var copy: Dictionary = state.capture()
	copy.events.clear()
	copy.visited.clear()
	check(state.capture() == snapshot, "Capture arrays cannot mutate live state")
	var continued := _memory(fixture_root.path_join("also-never-written.json"))
	check(continued.restore(snapshot) and continued.capture() == snapshot, "No-profile session continues from an in-memory scene snapshot")
	snapshot.met.clear()
	check(continued.met.size() == 5, "Restore copies arrays instead of retaining caller aliases")
	var before: Dictionary = continued.capture()
	check(not continued.restore(_data().merged({"events":["unknown"]}, true)) and continued.capture() == before, "Failed restore leaves valid existing records intact")
	check(continued.begin("session-b") and continued.events.is_empty() and continued.visited.is_empty() and continued.met.is_empty() and continued.recruited.is_empty(), "A different campaign starts an independent narrative ledger")
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak") and not FileAccess.file_exists(continued.save_path), "No-profile continuity never writes a sidecar")

func _persistent_recovery() -> void:
	var path := fixture_root.path_join("atomic.json")
	var state := _persistent(path)
	check(state.begin("persisted-a"), "Atomic writer creates a real isolated sidecar")
	check(state.mark("visited", "last_shift"), "Atomic writer commits the actual site visit")
	var backup_expected: Dictionary = state.capture()
	check(state.mark("events", "last_shift:arrival"), "Atomic writer commits an authored encounter")
	var latest: Dictionary = state.capture()
	var unchanged_file := FileAccess.get_file_as_string(path)
	var unchanged_backup := FileAccess.get_file_as_string(path+".bak")
	check(state.mark("events", "last_shift:arrival") and state.begin("persisted-a"), "Duplicate entry and begin are successful no-ops")
	check(FileAccess.get_file_as_string(path) == unchanged_file and FileAccess.get_file_as_string(path+".bak") == unchanged_backup, "Duplicate events do not rotate backups or rewrite the sidecar")
	var loaded := _persistent(path)
	check(loaded.load_records() and not loaded.recovered_backup and loaded.capture() == latest, "A fresh state loads the last committed primary")
	_write(path, "{broken")
	loaded = _persistent(path)
	check(loaded.load_records() and loaded.recovered_backup and loaded.capture() == backup_expected, "Syntactically damaged primary safely loads its actual previous backup")
	_write(path, JSON.stringify(latest.merged({"events":["unknown"]}, true)))
	loaded = _persistent(path)
	check(loaded.load_records() and loaded.recovered_backup and loaded.capture() == backup_expected, "Semantically invalid primary uses the backup")
	_write(path, "x".repeat(Records.MAX_BYTES+1))
	loaded = _persistent(path)
	check(loaded.load_records() and loaded.recovered_backup and loaded.capture() == backup_expected, "Oversized primary is refused before parsing and falls back")
	check(DirAccess.remove_absolute(path) == OK, "Remove only the isolated primary fixture")
	loaded = _persistent(path)
	check(loaded.load_records() and loaded.recovered_backup and loaded.capture() == backup_expected, "A missing primary safely uses the valid backup")
	check(loaded.restore(latest) and loaded.save(), "A recovered ledger can commit a fresh primary")
	check(FileAccess.get_file_as_string(path+".bak") == unchanged_backup, "Rewriting a damaged or missing primary preserves the last valid backup")
	var stable: Dictionary = loaded.capture()
	_write(path, "{broken")
	_write(path+".bak", "{also broken")
	check(not loaded.load_records() and not loaded.recovered_backup and loaded.capture() == stable, "When both files are bad, loading fails without deleting the live ledger")
	var absent := _persistent(fixture_root.path_join("absent.json"))
	check(not absent.load_records() and absent.campaign_id.is_empty(), "Missing primary and backup produce an empty optional ledger")
	var default_guard := Records.new(path, true)
	check(not default_guard.persistence_enabled, "Process no-profile flag wins even when constructor requests persistence")

func _write_rollback() -> void:
	var missing_path := fixture_root.path_join("missing-parent/state.json")
	var state := _memory(missing_path)
	check(state.begin("rollback-a") and state.mark("visited", "last_shift"), "Prepare valid in-memory state before write failure")
	var previous: Dictionary = state.capture()
	state.persistence_enabled = true
	check(not state.mark("events", "last_shift:arrival") and state.capture() == previous and not state.last_error.is_empty(), "Opening a failed temporary file rolls back event mutation")
	check(not state.begin("rollback-b") and state.capture() == previous, "Failed new-campaign commit restores the prior campaign")
	check(not FileAccess.file_exists(missing_path) and not FileAccess.file_exists(missing_path+".bak"), "Failed writes cannot create partial final or backup files")
	var empty := _persistent(fixture_root.path_join("also-missing/state.json"))
	check(not empty.begin("never-committed") and empty.campaign_id.is_empty() and empty.events.is_empty(), "A failed first begin returns to the truly empty state")
	var copy_path := fixture_root.path_join("backup-blocked.json")
	var copy_failure := _persistent(copy_path)
	check(copy_failure.begin("copy-a") and copy_failure.mark("visited", "last_shift"), "Prepare a committed state before backup-copy failure")
	check(DirAccess.remove_absolute(copy_path+".bak") == OK and DirAccess.make_dir_absolute(copy_path+".bak") == OK, "Test-owned directory obstructs the backup path")
	previous = copy_failure.capture()
	var source_text := FileAccess.get_file_as_string(copy_path)
	check(not copy_failure.mark("events", "last_shift:arrival") and copy_failure.capture() == previous, "Backup-copy failure rolls back the new narrative record")
	check(FileAccess.get_file_as_string(copy_path) == source_text and not FileAccess.file_exists(copy_path+".%d.tmp" % OS.get_process_id()), "Backup-copy failure preserves the primary and removes its temporary file")
	var rename_path := fixture_root.path_join("rename-blocked.json")
	check(DirAccess.make_dir_absolute(rename_path) == OK, "A test-owned directory obstructs the final rename target")
	var rename_failure := _persistent(rename_path)
	check(not rename_failure.begin("rename-a") and rename_failure.campaign_id.is_empty(), "Failed atomic rename rolls back initialization")
	check(not FileAccess.file_exists(rename_path+".%d.tmp" % OS.get_process_id()), "Failed rename removes its temporary file")

func _cleanup(path: String) -> void:
	if not path.begins_with(fixture_root) or fixture_root.is_empty(): return
	var directory := DirAccess.open(path)
	if directory == null: return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname: String in directory.get_directories():
		_cleanup(path.path_join(dirname))
	DirAccess.remove_absolute(path)
