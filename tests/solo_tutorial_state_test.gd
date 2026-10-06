extends SceneTree
## Local tutorial records are bounded, validated, and separate from save games.
const Records := preload("res://scripts/solo_tutorial_state.gd")
const Catalog := preload("res://scripts/solo_tutorial_catalog.gd")
const OUTPUT := "res://artifacts/solo-tutorial-20261005/state-verification.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	print("SOLO TUTORIAL STATE %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var path := "res://artifacts/solo-tutorial-20261005/state-never-saved.json"
	var records := Records.new(path)
	check(not records.persistence_enabled,"The no-profile-save flag disables both record reads and writes")
	check(Records.valid(records.capture()),"Fresh record has the exact bounded schema")
	check(records.enabled and not records.completed(),"Fresh solo guidance starts enabled and unfinished")
	var bad: Array = [null,[],{},true,{"version":2,"enabled":true,"learned":[],"skipped":[]},{"version":true,"enabled":true,"learned":[],"skipped":[]},{"version":NAN,"enabled":true,"learned":[],"skipped":[]},{"version":1,"enabled":1,"learned":[],"skipped":[]},{"version":1,"enabled":true,"learned":["unknown"],"skipped":[]},{"version":1,"enabled":true,"learned":["move","move"],"skipped":[]},{"version":1,"enabled":true,"learned":["move"],"skipped":["move"]},{"version":1,"enabled":true,"learned":[],"skipped":[],"campaign":{"resources":100}},{"version":1,"enabled":true,"learned":{},"skipped":[]}]
	for item: Variant in bad:
		var before := records.capture()
		check(not Records.valid(item) and not records.restore(item) and records.capture()==before,"Malformed or foreign state cannot mutate the local tutorial")
	check(records.mark("production") and records.mark("wall"),"Confirmed actions are recorded out of display order")
	check(not records.mark("production") and not records.mark("unknown"),"Repeated or unknown lessons are no-ops")
	check(records.mark("move",true) and "move" in records.skipped and "move" not in records.learned,"A manual skip is distinguished from demonstrated learning")
	check(records.mark("move") and "move" in records.learned and "move" not in records.skipped,"A later actual action replaces its manual skip")
	var saved := records.capture()
	records.enabled = false
	var stopped := records.capture()
	var restored := Records.new(path,false)
	check(restored.restore(stopped) and not restored.enabled and restored.learned==records.learned,"Stop and learned actions survive validated session restoration")
	var copy := restored.capture()
	copy.learned.clear()
	check(restored.learned==records.learned,"Captured arrays cannot alter live records")
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))),"JSON round trips preserve the version and finite lesson IDs")
	for id: String in Catalog.IDS: restored.mark(id)
	check(restored.completed() and restored.learned.size()==Catalog.IDS.size(),"Every demonstrated lesson finishes the local guide")
	restored.reset()
	check(restored.enabled and restored.learned.is_empty() and restored.skipped.is_empty() and not restored.completed(),"Restart resets only tutorial state")
	check(restored.save() and not FileAccess.file_exists(path),"No-profile-save never creates the explicit test record")
	var directory := ProjectSettings.globalize_path(OUTPUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var oversized := path+".oversized"
	FileAccess.open(oversized,FileAccess.WRITE).store_string(" ".repeat(Records.MAX_BYTES+1))
	check(restored._read(oversized).is_empty(),"An oversized record is rejected before JSON decoding")
	FileAccess.open(oversized,FileAccess.WRITE).store_string("{broken")
	check(restored._read(oversized).is_empty(),"Malformed JSON cannot become a tutorial entitlement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(oversized))
	# This explicit private-project artifact is the only persistence override;
	# the normal no-profile-save record above remains unwritable throughout.
	var disk_path := "res://artifacts/solo-tutorial-20261005/state-disk-test.json"
	var disk := Records.new(disk_path,false)
	disk.persistence_enabled = true
	check(disk.save() and FileAccess.file_exists(disk_path),"An explicitly owned scratch record is committed atomically")
	disk.mark("move")
	disk.mark("gather")
	disk.enabled = false
	check(disk.save(),"Enabled preference and real lesson IDs are written together")
	var disk_loaded := Records.new(disk_path,false)
	disk_loaded.persistence_enabled = true
	check(disk_loaded.load_records() and disk_loaded.capture()==disk.capture(),"A separate state instance reloads the complete persisted schema")
	var backed_up := disk_loaded._read(disk_path+".bak")
	var expected_backup := Records.new(disk_path,false)
	check(expected_backup.restore(backed_up),"The backup contains a separately validated prior record")
	FileAccess.open(disk_path,FileAccess.WRITE).store_string("{corrupt")
	var recovered := Records.new(disk_path,false)
	recovered.persistence_enabled = true
	check(recovered.load_records() and recovered.recovered_backup and recovered.capture()==expected_backup.capture(),"A malformed main file recovers the last validated backup")
	var blocked_path := disk_path+".directory"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_path))
	var blocked := Records.new(blocked_path,false)
	blocked.persistence_enabled = true
	blocked.enabled = false
	check(not blocked.save() and not blocked.enabled and not blocked.last_error.is_empty(),"A failed atomic replacement preserves the usable in-memory stop preference")
	check(not FileAccess.file_exists(blocked_path+".%d.tmp" % OS.get_process_id()),"A failed replacement retires its exact temporary file")
	for scratch: String in [disk_path,disk_path+".bak",blocked_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"profile_written":false,"fixture":"Memory-only no-save records plus explicitly owned private-project scratch files for malformed/oversized records, atomic persistence, a second reader, backup recovery and replacement failure. No actual player profile, campaign, roster or network state is written."},"  "))
	quit(1 if failures else 0)
