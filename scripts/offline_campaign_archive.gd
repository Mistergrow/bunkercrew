class_name OfflineCampaignArchive
extends RefCounted
## Local parked crew data. It never adds a field to the shared checkpoint.
## Active checkpoint slots own their supplies; archive copies cannot be spawned
## twice and garage-banked materials are never restored into another pair of hands.
const MAX_BYTES := 131072

static func path_for(campaign_path: String,campaign_id: String) -> String:
	return campaign_path+".offline-crew-"+campaign_id.sha256_text().substr(0,20)+".json"

static func empty(campaign_id: String) -> Dictionary:
	return {"version":1,"campaign_id":campaign_id,"slots":{}}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=3: return false
	var version: Variant = data.get("version")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version)!=1.0: return false
	if not data.get("campaign_id") is String or data.campaign_id.is_empty() or data.campaign_id.length()>80: return false
	if not data.get("slots") is Dictionary or data.slots.size()>3: return false
	for slot: Variant in data.slots:
		if not slot is String or slot not in ["2","3","4"]: return false
		var people: Variant = data.slots[slot]
		if not people is Dictionary or people.is_empty() or people.size()>CharacterCatalog.CHARACTERS.size(): return false
		for character: Variant in people:
			if not character is String or not CharacterCatalog.contains(character): return false
			var record: Variant = people[character]
			if not record is Dictionary or record.size()!=3: return false
			if not record.get("cargo_in_warehouse") is bool: return false
			if not CampaignBonus.valid_snapshot(record.get("snapshot")) or record.snapshot.character!=character: return false
			var departure: Variant = record.get("departure")
			if not departure is Dictionary or (not departure.is_empty() and (not CampaignBonus.valid_snapshot(departure) or departure.character!=character)): return false
	return true

static func matches(data: Dictionary, campaign_id: String) -> bool:
	return valid(data) and str(data.campaign_id)==campaign_id

static func _initial(character: String) -> Dictionary:
	return {"character":character,"level":1,"xp":0.0,"skill_points":0,"skills":{"vitality":0,"combat":0,"engineering":0},"armor_tier":0,"weapon_kind":"rifle","ammunition":WorkerWeapon.initial_ammunition(),"inventory":{}}

static func park(checkpoint: Dictionary, previous: Dictionary = {}) -> Dictionary:
	if not CampaignState.valid_checkpoint(checkpoint): return {}
	var result := previous.duplicate(true) if matches(previous,str(checkpoint.campaign_id)) else empty(str(checkpoint.campaign_id))
	var warehouse: bool = str(checkpoint.expedition.stage) in ["preparation","map"]
	for slot in range(2,int(checkpoint.player_count)+1):
		var key := str(slot)
		var character := str(checkpoint.character_ids[slot-1])
		var crew_snapshot: Dictionary = checkpoint.snapshots.get(key,_initial(character)).duplicate(true)
		var departure: Dictionary = checkpoint.expedition.departure.get("snapshots",{}).get(key,{}).duplicate(true)
		if not result.slots.has(key): result.slots[key]={}
		result.slots[key][character]={"snapshot":crew_snapshot,"departure":departure,"cargo_in_warehouse":warehouse}
	return result if valid(result) else {}

static func snapshot(data: Dictionary, slot: int, character: String, departure: bool = false) -> Dictionary:
	if not valid(data) or slot not in [2,3,4]: return {}
	var people: Dictionary = data.slots.get(str(slot),{})
	var record: Dictionary = people.get(character,{})
	if record.is_empty(): return {}
	var source: Dictionary = record.departure if departure and not record.departure.is_empty() else record.snapshot
	var result := source.duplicate(true)
	if bool(record.cargo_in_warehouse):
		for kind: String in CampaignCatalog.CARGO_KINDS:
			if result.get("inventory") is Dictionary: result.inventory.erase(kind)
	return result

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text())!=OK or not valid(decoder.data): return {}
	return decoder.data

static func load_records(campaign_path: String, campaign_id: String) -> Dictionary:
	var path := path_for(campaign_path,campaign_id)
	var data := _read(path)
	if data.is_empty(): data=_read(path+".bak")
	if data.is_empty():
		return {"ok":not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak"),"data":empty(campaign_id)}
	return {"ok":true,"data":data if matches(data,campaign_id) else empty(campaign_id)}

static func save_records(campaign_path: String, data: Dictionary) -> bool:
	if not valid(data): return false
	var path := path_for(campaign_path,str(data.campaign_id))
	var source := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(source) or DirAccess.dir_exists_absolute(source+".bak"): return false
	var temporary := path+".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	file.close()
	var temporary_absolute := ProjectSettings.globalize_path(temporary)
	if _read(temporary).is_empty():
		DirAccess.remove_absolute(temporary_absolute)
		return false
	if not _read(path).is_empty() and DirAccess.copy_absolute(source,source+".bak")!=OK:
		DirAccess.remove_absolute(temporary_absolute)
		return false
	if DirAccess.rename_absolute(temporary_absolute,source)!=OK:
		DirAccess.remove_absolute(temporary_absolute)
		return false
	return true
