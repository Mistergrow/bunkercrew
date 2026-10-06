class_name SoloStoryState
extends RefCounted
## Local narrative records never amend the shared campaign or its resource ledger.
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const SAVE_PATH := "user://solo_story_v1.json"
const MAX_BYTES := 65536
var save_path := SAVE_PATH
var persistence_enabled := true
var recovered_backup := false
var last_error := ""
var campaign_id := ""
var events: Array[String] = []
var met: Array[String] = []
var recruited: Array[String] = []
var visited: Array[String] = []

func _init(path: String = SAVE_PATH, allow_persistence: bool = true) -> void:
	save_path = path
	persistence_enabled = allow_persistence and "--no-profile-save" not in OS.get_cmdline_user_args()

func capture() -> Dictionary:
	return {"version":1,"campaign_id":campaign_id,"events":events.duplicate(),"met":met.duplicate(),"recruited":recruited.duplicate(),"visited":visited.duplicate()}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=6: return false
	var version: Variant = data.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version)!=1.0: return false
	if not data.get("campaign_id") is String or data.campaign_id.is_empty() or data.campaign_id.length()>80: return false
	var sites: Array[String] = []
	for entry: Dictionary in CampaignCatalog.NODES: sites.append(str(entry.id))
	var people: Array[String] = []
	for entry: Dictionary in Catalog.profiles(): people.append(str(entry.id))
	for key: String in ["events","met","recruited","visited"]:
		var allowed: Array = Catalog.entry_ids() if key=="events" else sites if key=="visited" else people
		var value: Variant = data.get(key)
		if not value is Array or value.size()>allowed.size(): return false
		var seen: Dictionary = {}
		for id: Variant in value:
			if not id is String or id not in allowed or seen.has(id): return false
			seen[id] = true
	for id: String in data.recruited:
		if id not in data.met or str(Catalog.profile(id).site) not in data.visited: return false
	for id: String in data.met:
		if str(Catalog.profile(id).site) not in data.visited: return false
	for id: String in data.events:
		if str(Catalog.entry(id).site) not in data.visited: return false
	return true

func restore(data: Dictionary) -> bool:
	if not valid(data): return false
	campaign_id = str(data.campaign_id)
	events.assign(data.events)
	met.assign(data.met)
	recruited.assign(data.recruited)
	visited.assign(data.visited)
	return true

func matches(id: String) -> bool:
	return not id.is_empty() and campaign_id==id

func begin(id: String) -> bool:
	if id.is_empty() or id.length()>80: return false
	if matches(id): return true
	var previous := capture()
	campaign_id = id
	events.clear()
	met.clear()
	recruited.clear()
	visited.clear()
	if save(): return true
	_restore_previous(previous)
	return false

func mark(key: String,id: String) -> bool:
	if key not in ["events","met","recruited","visited"] or campaign_id.is_empty(): return false
	var values: Array = get(key)
	if values.has(id): return true
	var previous := capture()
	values.append(id)
	if valid(capture()) and save(): return true
	_restore_previous(previous)
	return false

func _restore_previous(data: Dictionary) -> void:
	if valid(data):
		restore(data)
	else:
		campaign_id = ""
		events.clear()
		met.clear()
		recruited.clear()
		visited.clear()

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
		last_error = LocaleText.text("Das Logbuch konnte nicht gespeichert werden. Der Kampagnenstand bleibt erhalten.")
		return false
	file.store_string(JSON.stringify(capture(),"\t"))
	file.flush()
	file.close()
	if _read(temporary).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = LocaleText.text("Das Logbuch konnte nicht gespeichert werden. Der Kampagnenstand bleibt erhalten.")
		return false
	var source := ProjectSettings.globalize_path(save_path)
	if DirAccess.dir_exists_absolute(source) or DirAccess.dir_exists_absolute(source+".bak") or (not _read(save_path).is_empty() and DirAccess.copy_absolute(source,source+".bak")!=OK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = LocaleText.text("Das Logbuch konnte nicht gespeichert werden. Der Kampagnenstand bleibt erhalten.")
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),source)!=OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = LocaleText.text("Das Logbuch konnte nicht gespeichert werden. Der Kampagnenstand bleibt erhalten.")
		return false
	return true
