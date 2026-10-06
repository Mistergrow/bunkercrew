extends SceneTree
const Migration := preload("res://scripts/profile_migration.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func write(path: String, content: String) -> void:
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(content)
	output.close()

func clean(path: String) -> void:
	for filename: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(filename))
	for directory: String in DirAccess.get_directories_at(path): clean(path.path_join(directory))
	DirAccess.remove_absolute(path)

func _run() -> void:
	var base := OS.get_temp_dir().path_join("lastshift-profile-migration-%d" % OS.get_process_id())
	var source := base.path_join("legacy")
	var target := base.path_join("new")
	DirAccess.make_dir_recursive_absolute(source)
	DirAccess.make_dir_recursive_absolute(target)
	write(source.path_join("language.cfg"), "[language]\nlocale=\"en\"\n")
	write(source.path_join("audio.cfg"), "legacy-audio")
	write(source.path_join("achievements.cfg"), "legacy-achievements")
	write(source.path_join("crew_roster.cfg"), "legacy-crew")
	write(source.path_join("campaign_v1.json"), "legacy-campaign")
	write(source.path_join("campaign_v1.json.bak"), "legacy-backup")
	write(source.path_join("campaign_v1.json.tmp"), "unfinished-checkpoint")
	write(source.path_join("unrelated.txt"), "private unrelated data")
	write(target.path_join("audio.cfg"), "new-audio")
	var first := Migration.copy_missing(source, target)
	check(first.errors.is_empty() and first.copied.size() == 5, "Copies only five missing known settings and saves")
	check(FileAccess.get_file_as_string(target.path_join("audio.cfg")) == "new-audio", "Existing destination preference is never overwritten")
	check(FileAccess.get_file_as_string(source.path_join("campaign_v1.json")) == "legacy-campaign", "Legacy campaign remains intact")
	check(not FileAccess.file_exists(target.path_join("unrelated.txt")) and not FileAccess.file_exists(target.path_join("campaign_v1.json.tmp")), "Unrelated files and incomplete transactions stay in the old directory")
	var language := ConfigFile.new()
	check(language.load(target.path_join("language.cfg")) == OK and language.get_value("language", "locale") == "en", "Migrated language is immediately readable before localization initialization")
	var second := Migration.copy_missing(source, target)
	check(second.copied.is_empty() and second.errors.is_empty(), "Repeated startup is idempotent")
	check(Migration.copy_missing(source, source).copied.is_empty(), "Unchanged project name never copies onto itself")
	check(Migration.copy_missing(base.path_join("absent"), target).errors.is_empty(), "A new player without an old directory needs no migration")
	DirAccess.remove_absolute(target.path_join("campaign_v1.json.bak"))
	var mixed := Migration.copy_missing(source, target)
	check(not FileAccess.file_exists(target.path_join("campaign_v1.json.bak")) and mixed.copied.is_empty(), "An existing new checkpoint cannot acquire an unrelated old backup")
	write(source.path_join("camera.cfg"), "")
	write(source.path_join("display.cfg"), "x".repeat(Migration.MAX_BYTES + 1))
	var bounded := Migration.copy_missing(source, target)
	check(not FileAccess.file_exists(target.path_join("camera.cfg")) and not FileAccess.file_exists(target.path_join("display.cfg")) and bounded.errors.is_empty(), "Empty and oversized files cannot become new preferences")
	clean(base)
	print("Profile migration: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
