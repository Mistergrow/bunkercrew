class_name CrewRoster
extends RefCounted
## Local rescued crew records; remote character validity does not depend on these.
const SAVE_PATH := "user://crew_roster.cfg"
const Registry := preload("res://scripts/content_registry.gd")
static var BASE_CREW: Array[String] = _base_crew()
static var LEGACY_RECRUITS: Dictionary = _recruits(true)
static var RECRUITS: Dictionary = _recruits(false)

static func _base_crew() -> Array[String]:
	return Registry.starter_ids()

static func _recruits(legacy_only: bool) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in Registry.entries("characters"):
		if entry.has("unlock_site") and (not legacy_only or bool(entry.get("legacy_auto_unlock",false))): result[str(entry.id)] = str(entry.unlock_site)
	return result

static var save_path := SAVE_PATH
static var persistence_enabled := not "--no-profile-save" in OS.get_cmdline_user_args()
static var _loaded := false
static var unlocked: Dictionary = {}
static var last_error := ""

static func load_records() -> void:
	if _loaded: return
	_loaded = true
	if not persistence_enabled: return
	var records = _read_records(save_path)
	if records == null: records = _read_records(save_path+".bak")
	if records is Dictionary:
		for id: String in records: unlocked[id] = true

static func is_unlocked(id: String) -> bool:
	load_records()
	if not Registry.contains("characters",id): return false
	var entry: Dictionary = Registry.data("characters",id)
	return bool(entry.get("unlocked",not entry.has("unlock_site"))) or unlocked.get(id,false)==true

static func unlock(id: String) -> bool:
	last_error = ""
	if not Registry.contains("characters",id):
		last_error = "invalid_id"
		return false
	load_records()
	if is_unlocked(id): return true
	var proposed := unlocked.duplicate()
	proposed[id] = true
	if persistence_enabled and not _save_records(proposed): return false
	unlocked = proposed
	return true

static func unlock_for_site(site: String) -> Array[String]:
	load_records()
	var result: Array[String] = []
	# Historical secured-site saves keep their old three automatic rewards.
	# Oskar and Rika require the new explicit physical encounter/dialog choice.
	for id: String in LEGACY_RECRUITS:
		if LEGACY_RECRUITS[id] == site and not is_unlocked(id): result.append(id)
	if result.is_empty(): return result
	var proposed := unlocked.duplicate()
	for id: String in result: proposed[id] = true
	last_error = ""
	if persistence_enabled and not _save_records(proposed): return []
	unlocked = proposed
	return result

static func _read_records(path: String) -> Variant:
	var config := ConfigFile.new()
	if config.load(path)!=OK: return null
	var result: Dictionary={}
	if not config.has_section("crew"): return result
	for id: String in config.get_section_keys("crew"):
		var value: Variant = config.get_value("crew",id,false)
		# Removed packs remain inert but retain their record for later reinstall.
		# Malformed current records still trigger the existing backup recovery.
		if not value is bool:
			if Registry.contains("characters",id): return null
			continue
		if value: result[id]=true
	return result

static func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func _save_records(proposed: Dictionary) -> bool:
	var config := ConfigFile.new()
	# Preserve unrelated legacy ConfigFile sections instead of replacing them.
	var previous = _read_records(save_path)
	if previous is Dictionary:
		config.load(save_path)
	elif _read_records(save_path+".bak") is Dictionary:
		config.load(save_path+".bak")
	for entry: Dictionary in Registry.entries("characters"):
		var id := str(entry.id)
		if id in RECRUITS or proposed.has(id): config.set_value("crew",id,proposed.get(id,false)==true)
	var temporary := save_path+".tmp-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	if config.save(temporary)!=OK:
		last_error="write_failed"
		_remove_temporary(temporary)
		return false
	if _read_records(temporary)!=proposed:
		last_error="verify_failed"
		_remove_temporary(temporary)
		return false
	# Recovery must retain a good backup when the primary is corrupt.
	if previous is Dictionary and DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path+".bak"))!=OK:
		last_error="backup_failed"
		_remove_temporary(temporary)
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(save_path))!=OK:
		last_error="rename_failed"
		_remove_temporary(temporary)
		return false
	return true
