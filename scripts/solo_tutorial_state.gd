extends RefCounted
const Catalog := preload("res://scripts/solo_tutorial_catalog.gd")
const SAVE_PATH := "user://solo_tutorial_v1.json"
const MAX_BYTES := 8192
var save_path := SAVE_PATH
var persistence_enabled := true
var enabled := true
var learned: Array[String] = []
var skipped: Array[String] = []
var recovered_backup := false
var last_error := ""

func _init(path: String = SAVE_PATH, allow_persistence: bool = true) -> void:
	save_path = path
	persistence_enabled = allow_persistence and "--no-profile-save" not in OS.get_cmdline_user_args()

func capture() -> Dictionary:
	return {"version":1,"enabled":enabled,"learned":learned.duplicate(),"skipped":skipped.duplicate()}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=4 or not data.get("enabled") is bool: return false
	var version: Variant = data.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version)!=1.0: return false
	var seen: Dictionary = {}
	for key: String in ["learned","skipped"]:
		var values: Variant = data.get(key)
		if not values is Array or values.size()>Catalog.IDS.size(): return false
		for id: Variant in values:
			if not id is String or not Catalog.contains(id) or seen.has(id): return false
			seen[id] = true
	return true

func restore(data: Variant) -> bool:
	if not valid(data): return false
	enabled = bool(data.enabled)
	learned.assign(data.learned)
	skipped.assign(data.skipped)
	return true

func completed() -> bool:
	return learned.size()+skipped.size()==Catalog.IDS.size()

func pending(id: String) -> bool:
	return Catalog.contains(id) and id not in learned and id not in skipped

func mark(id: String, manual_skip: bool = false) -> bool:
	if not Catalog.contains(id): return false
	if manual_skip:
		if not pending(id): return false
		skipped.append(id)
	else:
		if id in learned: return false
		skipped.erase(id)
		learned.append(id)
	save()
	return true

func reset() -> void:
	enabled = true
	learned.clear()
	skipped.clear()
	save()

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text())!=OK or not valid(decoder.data): return {}
	return decoder.data

func load_records() -> bool:
	if not persistence_enabled: return false
	recovered_backup = false
	var data := _read(save_path)
	if data.is_empty():
		data = _read(save_path+".bak")
		recovered_backup = not data.is_empty()
	return not data.is_empty() and restore(data)

func save() -> bool:
	last_error = ""
	if not valid(capture()): return false
	if not persistence_enabled: return true
	var temporary := save_path+".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:
		last_error = "Das Tutorial konnte nicht gespeichert werden. Dein Spielstand bleibt erhalten."
		return false
	file.store_string(JSON.stringify(capture(),"\t"))
	file.flush()
	file.close()
	var source := ProjectSettings.globalize_path(save_path)
	if _read(temporary).is_empty() or DirAccess.dir_exists_absolute(source) or DirAccess.dir_exists_absolute(source+".bak") or (not _read(save_path).is_empty() and DirAccess.copy_absolute(source,source+".bak")!=OK) or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),source)!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "Das Tutorial konnte nicht gespeichert werden. Dein Spielstand bleibt erhalten."
		return false
	return true
