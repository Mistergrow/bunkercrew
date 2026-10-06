class_name CampaignState
extends RefCounted
## Only victories commit XP, equipment and recovered route data. A mission retry
## restores its departure snapshot; there is no repeatable reward for cleared stops.
signal changed
const VERSION := 2
const MAX_SAVE_BYTES := 131072
# A garage ledger aggregates reachable crates and their refill reserve.
# Individual crates keep their existing 10,000-unit network limit; larger
# totals remain in the ledger without creating overlapping containers. This
# is JSON's exact integer serialization limit, never a gameplay storage cap.
const MAX_STOCK_PER_KIND := 9007199254740991
const SAVE_PATH := "user://campaign_v1.json"
const Registry := preload("res://scripts/content_registry.gd")

var save_path := SAVE_PATH
var persistence_enabled := true
var active := false
var air_raid_intro_seen := false
var campaign_id := ""
var current_node := ""
var pending_node := ""
var options: Dictionary = {}
var character_ids: Array = ["mara", "branko"]
var player_count := 1
var completed: Array = []
var unlocked_routes: Array = []
var blueprints: Array = []
var claimed_missions: Array = []
var banked_salvage := 0
var total_salvage_earned := 0
var snapshots: Dictionary = {}
var shared_personal_upgrades: Array = []
var mission_id := ""
var mission_salvage := 0
var mission_running := false
var last_error := ""
var recovered_backup := false
var expedition: Dictionary = new_expedition()
var _issued: Dictionary = {}
var _collected: Dictionary = {}
var _loaded_requires_migration := false
# Local crew reserve is deliberately absent from checkpoint()/network payloads.
var offline_crew_archive: Dictionary = {}

func _init(path: String = SAVE_PATH, allow_persistence: bool = true) -> void:
	save_path = path
	persistence_enabled = allow_persistence and not "--no-profile-save" in OS.get_cmdline_user_args()

func begin_new(selection: Dictionary, characters: Array, count: int) -> bool:
	if mission_running or count < 1 or count > PartyConfig.MAX_PLAYERS or characters.size() < count or characters.size() > PartyConfig.MAX_PLAYERS:
		return false
	for character in characters:
		if not character is String or not CharacterCatalog.contains(character): return false
	var previous := checkpoint()
	active = true
	air_raid_intro_seen = false
	campaign_id = "%x-%x" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	options = ScenarioCatalog.validate(selection)
	character_ids = characters.duplicate()
	player_count = count
	current_node = ""
	pending_node = CampaignCatalog.ENTRY
	completed.clear()
	unlocked_routes.clear()
	blueprints.clear()
	claimed_missions.clear()
	banked_salvage = 0
	total_salvage_earned = 0
	snapshots.clear()
	shared_personal_upgrades.clear()
	expedition = new_expedition()
	_clear_mission()
	return _commit(previous)

func route_status(id: String) -> Dictionary:
	var entry := CampaignCatalog.node(id)
	if entry.is_empty() or not active:
		return {"state":"invalid", "can_unlock":false, "can_travel":false, "reason":LocaleText.text("KEINE ROUTE"), "cost":0}
	var status := "locked"
	var reason := LocaleText.text("VORHERIGEN ORT SICHERN")
	var parent_done := str(entry.parent).is_empty() or completed.has(entry.parent)
	var bought := int(entry.cost) == 0 or unlocked_routes.has(id)
	if completed.has(id):
		status = "completed"
		reason = LocaleText.text("GESICHERT · WIEDERBESUCH MÖGLICH") if can_revisit(id) else LocaleText.text("GESICHERT")
	elif parent_done and bought:
		status = "available"
		reason = LocaleText.text("REISEBEREIT")
	elif parent_done:
		status = "sealed"
		reason = LocaleText.format("%d BERGUNGSDATEN", int(entry.cost))
	var can_unlock := status == "sealed" and banked_salvage >= int(entry.cost) and not mission_running
	return {"state":status, "can_unlock":can_unlock, "can_travel":(status == "available" and not mission_running) or can_revisit(id), "reason":reason, "cost":int(entry.cost), "parent_done":parent_done, "unlocked":bought, "completed":completed.has(id)}

func can_revisit(id: String) -> bool:
	# A secured location is a safe contact, never another reward-bearing shift.
	# The entry has no inbound journey; no recruit lives there.
	return active and not mission_running and completed.has(id) and id!=current_node and id!=CampaignCatalog.ENTRY and bool(expedition.vehicle.unlocked)

func unlock_route(id: String) -> bool:
	if not expedition.stage in ["defense","preparation","map"]: return false
	if not route_status(id).can_unlock: return false
	var previous := checkpoint()
	banked_salvage -= int(CampaignCatalog.node(id).cost)
	unlocked_routes.append(id)
	return _commit(previous)

func select_destination(id: String, deployment: Dictionary = {}) -> bool:
	if not expedition.stage in ["defense","preparation","map"]: return false
	if not route_status(id).can_travel: return false
	var previous := checkpoint()
	pending_node = id
	if expedition.vehicle.unlocked:
		expedition.selected_stop = ""
		expedition.stage = "map"
	if not deployment.is_empty():
		var valid := ScenarioCatalog.validate(deployment)
		options.build_type = valid.build_type
		options.position = valid.position
	return _commit(previous)

func mission_start() -> Dictionary:
	if expedition.stage!="defense": return {}
	if not active or mission_running or not route_status(pending_node).can_travel: return {}
	# Store the selected departure before the first simulation frame. No combat
	# changes are subsequently saved until a verified twenty-wave victory.
	if not save_checkpoint(): return {}
	mission_id = "%s:%s" % [campaign_id, pending_node]
	if claimed_missions.has(mission_id): return {}
	mission_running = true
	mission_salvage = 0
	_issued.clear()
	_collected.clear()
	var selection := options.duplicate(true)
	if pending_node != CampaignCatalog.ENTRY:
		selection.environment = CampaignCatalog.node(pending_node).environment
	changed.emit()
	return {"node":pending_node, "id":mission_id, "options":selection, "characters":character_ids.duplicate(), "count":player_count, "site_kind":CampaignCatalog.site_kind(pending_node), "objective":CampaignCatalog.objective(pending_node)}

func reserve_drop(key: String, amount: int) -> bool:
	if not mission_running or key.is_empty() or _issued.has(key) or amount < 1 or amount > 3 or _issued.size() >= 21:
		return false
	_issued[key] = amount
	return true

func collect_salvage(key: String, amount: int) -> bool:
	if not mission_running or not _issued.has(key) or _collected.has(key) or int(_issued[key]) != amount:
		return false
	_collected[key] = true
	mission_salvage += amount
	changed.emit()
	return true

func complete_mission(claim_id: String, wave: int, players: Array, upgrades: Node = null, stock: Dictionary = {}) -> Dictionary:
	if CampaignCatalog.site_kind(pending_node) != "bunker" or wave != Balance.TOTAL_WAVES: return {}
	return _complete_site(claim_id, players, upgrades, stock)

func complete_outpost(claim_id: String, enemies_remaining: int, objective_secured: bool, players: Array, upgrades: Node = null, stock: Dictionary = {}) -> Dictionary:
	if CampaignCatalog.site_kind(pending_node) != "outpost" or enemies_remaining != 0 or not objective_secured: return {}
	return _complete_site(claim_id, players, upgrades, stock)

func _complete_site(claim_id: String, players: Array, upgrades: Node = null, stock: Dictionary = {}) -> Dictionary:
	if not mission_running or claim_id != mission_id or claimed_missions.has(claim_id) or players.size() != player_count:
		return {}
	if not valid_stock(stock): return {}
	var new_snapshots: Dictionary = {}
	for player in players:
		var snapshot := CampaignBonus.snapshot_player(player)
		if snapshot.is_empty(): return {}
		var slot := str(player.player_id)
		if new_snapshots.has(slot) or int(slot) < 1 or int(slot) > player_count or snapshot.character != character_ids[int(slot)-1]: return {}
		new_snapshots[slot] = snapshot
	var previous := checkpoint()
	var prior_mission := {"id":mission_id, "salvage":mission_salvage, "issued":_issued.duplicate(), "collected":_collected.duplicate()}
	var entry := CampaignCatalog.node(pending_node)
	var earned := mission_salvage
	completed.append(pending_node)
	claimed_missions.append(claim_id)
	current_node = pending_node
	banked_salvage += earned
	total_salvage_earned += earned
	snapshots = new_snapshots
	expedition.garage_stock = stock.duplicate()
	if is_instance_valid(upgrades):
		shared_personal_upgrades.clear()
		for upgrade: String in CampaignCatalog.PERSISTENT_UPGRADES:
			if upgrades.has_upgrade(upgrade): shared_personal_upgrades.append(upgrade)
	var blueprint := str(entry.blueprint)
	if not blueprint.is_empty() and not blueprints.has(blueprint): blueprints.append(blueprint)
	_clear_mission()
	_refresh_expedition_snapshot(upgrades)
	if not _commit(previous):
		mission_running = true
		mission_id = prior_mission.id
		mission_salvage = prior_mission.salvage
		_issued = prior_mission.issued
		_collected = prior_mission.collected
		return {}
	return {"node":current_node, "salvage":earned, "banked":banked_salvage, "blueprint":blueprint, "main_complete":CampaignCatalog.main_complete(completed), "all_complete":CampaignCatalog.all_complete(completed), "completion":CampaignCatalog.completion_summary(completed), "site_kind":CampaignCatalog.site_kind(current_node)}

func fail_mission() -> void:
	_clear_mission()
	changed.emit()

func _clear_mission() -> void:
	mission_id = ""
	mission_salvage = 0
	mission_running = false
	_issued.clear()
	_collected.clear()

func checkpoint() -> Dictionary:
	var result := {"version":VERSION, "active":active, "campaign_id":campaign_id, "current_node":current_node, "pending_node":pending_node, "options":options.duplicate(true), "character_ids":character_ids.duplicate(), "player_count":player_count, "completed":completed.duplicate(), "unlocked_routes":unlocked_routes.duplicate(), "blueprints":blueprints.duplicate(), "claimed_missions":claimed_missions.duplicate(), "banked_salvage":banked_salvage, "total_salvage_earned":total_salvage_earned, "snapshots":snapshots.duplicate(true), "shared_personal_upgrades":shared_personal_upgrades.duplicate(), "expedition":expedition.duplicate(true), "air_raid_intro_seen":air_raid_intro_seen}
	var requirements := content_requirements(result)
	if not requirements.is_empty(): result.content_requirements = requirements
	return result

func _restore(data: Dictionary) -> void:
	data = migrate_checkpoint(data)
	for key: String in data:
		if key not in ["version","content_requirements"]: set(key, data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key])
	_clear_mission()
	if not OfflineCampaignArchive.matches(offline_crew_archive,campaign_id): offline_crew_archive={}

func _commit(previous: Dictionary) -> bool:
	if not save_checkpoint():
		_restore(previous)
		return false
	changed.emit()
	return true

func save_checkpoint() -> bool:
	last_error = ""
	if not persistence_enabled: return true
	return _write_checkpoint(checkpoint())

func mark_air_raid_intro_seen() -> bool:
	if not active: return false
	air_raid_intro_seen = true
	if not persistence_enabled: return true
	# Only patch presentation state in the last durable departure. A live siege
	# may already have new inventory, XP, joined players or research in memory.
	var safe := _read_valid(save_path)
	if safe.is_empty(): safe = _read_valid(save_path + ".bak")
	if safe.is_empty() or safe.campaign_id != campaign_id: return false
	safe.air_raid_intro_seen = true
	last_error = ""
	return _write_checkpoint(safe)

func _write_checkpoint(data: Dictionary) -> bool:
	# Missing packs are not corruption. Never recover over, or overwrite, a
	# durable campaign that becomes usable again when its pack is installed.
	if _reject_unavailable_content(_read_document(save_path)) or _reject_unavailable_content(_read_document(save_path + ".bak")): return false
	if not valid_checkpoint(data):
		last_error = LocaleText.text("Ungültiger Kampagnenstand wurde nicht gespeichert.")
		return false
	var source := ProjectSettings.globalize_path(save_path)
	if DirAccess.dir_exists_absolute(source) or DirAccess.dir_exists_absolute(source+".bak"):
		last_error=LocaleText.format("Kampagne nicht gespeichert: %s",error_string(ERR_CANT_CREATE))
		return false
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = LocaleText.format("Kampagne nicht gespeichert: %s", error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	if _read_valid(temporary).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = LocaleText.text("Kampagnendatei konnte nicht vollständig geschrieben werden.")
		return false
	# Never replace a good backup with a corrupt primary during recovery.
	if not _read_valid(save_path).is_empty():
		var backup_result := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bak"))
		if backup_result != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			last_error = LocaleText.format("Kampagnensicherung fehlgeschlagen: %s", error_string(backup_result))
			return false
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path))
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = LocaleText.format("Kampagne nicht gespeichert: %s", error_string(result))
		return false
	return true

func load_checkpoint() -> bool:
	last_error = ""
	recovered_backup = false
	if not persistence_enabled: return false
	var primary := _read_document(save_path)
	if _reject_unavailable_content(primary): return false
	var data := _validated_document(primary, true)
	if data.is_empty():
		var backup := _read_document(save_path + ".bak")
		if _reject_unavailable_content(backup): return false
		data = _validated_document(backup, true)
		recovered_backup = not data.is_empty()
	if data.is_empty():
		if FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak"):
			last_error = LocaleText.text("Kampagnenstand und Sicherung konnten nicht gelesen werden.")
		return false
	var previous := checkpoint()
	var previous_archive := offline_crew_archive.duplicate(true)
	_restore(data)
	var parked := OfflineCampaignArchive.load_records(save_path,campaign_id)
	if not bool(parked.ok):
		_restore(previous)
		offline_crew_archive=previous_archive
		last_error=LocaleText.text("Kampagnenstand und Sicherung konnten nicht gelesen werden.")
		return false
	offline_crew_archive=parked.data.duplicate(true)
	# Persist the legacy fallback exactly once through the normal atomic writer.
	# A failed migration must not offer a seemingly durable restored campaign.
	if _loaded_requires_migration and not save_checkpoint():
		_restore(previous)
		offline_crew_archive=previous_archive
		return false
	changed.emit()
	return true

func reserved_crew_snapshot(slot: int,character: String,departure: bool=false) -> Dictionary:
	if slot<=player_count or not OfflineCampaignArchive.matches(offline_crew_archive,campaign_id): return {}
	return OfflineCampaignArchive.snapshot(offline_crew_archive,slot,character,departure)

func activate_reserved_crew(slot: int,character: String) -> bool:
	if slot!=player_count+1 or slot>PartyConfig.MAX_PLAYERS: return false
	var parked := reserved_crew_snapshot(slot,character)
	if parked.is_empty(): return false
	var proposed := checkpoint()
	proposed.player_count=slot
	proposed.character_ids=PartyConfig.normalize_characters(character_ids,4)
	proposed.character_ids[slot-1]=character
	if not completed.is_empty(): proposed.snapshots[str(slot)]=parked.duplicate(true)
	if not proposed.expedition.departure.is_empty():
		proposed.expedition.departure.snapshots[str(slot)]=reserved_crew_snapshot(slot,character,true)
	if not valid_checkpoint(proposed):
		last_error=LocaleText.text("Ungültiger Kampagnenstand wurde nicht gespeichert.")
		return false
	if persistence_enabled and not _write_checkpoint(proposed): return false
	# Keep the transient running mission/drop ledger. _restore would clear it.
	player_count=slot
	character_ids=proposed.character_ids.duplicate()
	snapshots=proposed.snapshots.duplicate(true)
	expedition=proposed.expedition.duplicate(true)
	changed.emit()
	return true

static func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text()) != OK: return {}
	var parsed = decoder.data
	return parsed if parsed is Dictionary else {}

func _validated_document(parsed: Dictionary, track_migration: bool = false) -> Dictionary:
	if track_migration: _loaded_requires_migration = false
	if not valid_checkpoint(parsed): return {}
	var normalized := migrate_checkpoint(parsed)
	if track_migration: _loaded_requires_migration = normalized != parsed
	return normalized

func _read_valid(path: String, track_migration: bool = false) -> Dictionary:
	return _validated_document(_read_document(path),track_migration)

func _reject_unavailable_content(data: Dictionary) -> bool:
	var missing := missing_content_ids(data)
	if not missing.is_empty():
		last_error = LocaleText.format("Für diesen Kampagnenstand fehlen Spielinhalte: %s. Installiere die passenden Inhaltspakete; der Spielstand bleibt unverändert.",", ".join(missing.slice(0,3)))
		return true
	var versions := incompatible_content_requirements(data)
	if not versions.is_empty():
		last_error = LocaleText.format("Dieser Kampagnenstand benötigt andere Inhaltspaket-Versionen: %s. Installiere die passenden Versionen; der Spielstand bleibt unverändert.",", ".join(versions.slice(0,3)))
		return true
	return false

static func _valid_content_requirements(value: Variant) -> bool:
	if not value is Array or value.size()>Registry.MAX_PACKS: return false
	var seen: Dictionary = {}
	for requirement in value:
		if not requirement is Dictionary or requirement.size()!=2: return false
		if not Registry.valid_id(requirement.get("id")) or not requirement.get("version") is String or requirement.version.is_empty() or requirement.version.length()>64: return false
		if seen.has(requirement.id): return false
		seen[requirement.id] = true
	return true

static func incompatible_content_requirements(data: Dictionary) -> Array[String]:
	var mismatched: Array[String] = []
	if not _integer(data.get("version"),1,VERSION) or data.get("active")!=true or not data.has("content_requirements") or not _valid_content_requirements(data.content_requirements): return mismatched
	var versions: Dictionary = {}
	for pack: Dictionary in Registry.packs(): versions[pack.id] = pack.version
	for requirement: Dictionary in data.content_requirements:
		if versions.get(requirement.id)!=requirement.version: mismatched.append(requirement.id + " " + requirement.version)
	return mismatched

static func _saved_registry_ids(data: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var selection: Variant = data.get("options")
	if selection is Dictionary and selection.get("environment") is String: ids.append(selection.environment)
	var crew: Variant = data.get("character_ids")
	if crew is Array:
		for id in crew:
			if id is String: ids.append(id)
	var saved: Array = [data.get("snapshots",{})]
	var item_maps: Array = []
	var journey: Variant = data.get("expedition")
	if journey is Dictionary:
		item_maps.append(journey.get("garage_stock",{}))
		item_maps.append(journey.get("deployment_cargo",{}))
		var vehicle: Variant = journey.get("vehicle")
		if vehicle is Dictionary: item_maps.append(vehicle.get("cargo",{}))
		var departure: Variant = journey.get("departure")
		if departure is Dictionary:
			saved.append(departure.get("snapshots",{}))
			var previous_vehicle: Variant = departure.get("vehicle")
			if previous_vehicle is Dictionary: item_maps.append(previous_vehicle.get("cargo",{}))
	for group in saved:
		if not group is Dictionary: continue
		for snapshot in group.values():
			if not snapshot is Dictionary: continue
			if snapshot.get("character") is String: ids.append(snapshot.character)
			item_maps.append(snapshot.get("inventory",{}))
	for inventory in item_maps:
		if inventory is Dictionary:
			for id in inventory:
				if id is String: ids.append(id)
	return ids

static func content_requirements(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Dictionary = {}
	var packs := Registry.packs()
	for id: String in _saved_registry_ids(data):
		# Pack IDs may themselves contain a colon. Match the longest installed
		# namespace, never an opaque campaign/mission identifier.
		var owner: Dictionary = {}
		for pack: Dictionary in packs:
			if pack.id!=Registry.CORE and id.begins_with(str(pack.id)+":") and str(pack.id).length()>str(owner.get("id","")).length(): owner = pack
		if not owner.is_empty(): used[owner.id] = owner.version
	var sorted: Array = used.keys()
	sorted.sort()
	for id: String in sorted: result.append({"id":id,"version":used[id]})
	return result

static func _missing_id(value: Variant, known: bool, missing: Array[String]) -> void:
	if value is String and ":" in value and Registry.valid_id(value) and not known and value not in missing:
		missing.append(value)

static func _missing_saved_items(value: Variant, missing: Array[String]) -> void:
	if not value is Dictionary: return
	for kind in value:
		_missing_id(kind,Registry.contains("items",str(kind)),missing)

static func _missing_saved_snapshots(value: Variant, missing: Array[String]) -> void:
	if not value is Dictionary: return
	for snapshot in value.values():
		if not snapshot is Dictionary: continue
		_missing_id(snapshot.get("character"),Registry.contains("characters",str(snapshot.get("character",""))),missing)
		_missing_saved_items(snapshot.get("inventory"),missing)
		_missing_id(snapshot.get("weapon_kind"),WorkerWeapon.WEAPONS.has(snapshot.get("weapon_kind")),missing)

static func missing_content_ids(data: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	# Corrupt/foreign files retain the existing bounded backup-recovery path.
	if not _integer(data.get("version"),1,VERSION) or data.get("active")!=true or not data.get("campaign_id") is String: return missing
	var selection: Variant = data.get("options")
	if selection is Dictionary:
		_missing_id(selection.get("environment"),Registry.contains("environments",str(selection.get("environment",""))),missing)
	var crew: Variant = data.get("character_ids")
	if crew is Array:
		for id in crew: _missing_id(id,Registry.contains("characters",str(id)),missing)
	for field: String in ["current_node","pending_node"]:
		_missing_id(data.get(field),CampaignCatalog.contains(str(data.get(field,""))),missing)
	for field: String in ["completed","unlocked_routes"]:
		var ids: Variant = data.get(field)
		if ids is Array:
			for id in ids: _missing_id(id,CampaignCatalog.contains(str(id)),missing)
	for field: String in ["blueprints","shared_personal_upgrades"]:
		var ids: Variant = data.get(field)
		if ids is Array:
			var known: Array = CampaignCatalog.BLUEPRINTS.keys() if field=="blueprints" else CampaignCatalog.PERSISTENT_UPGRADES
			for id in ids: _missing_id(id,id in known,missing)
	_missing_saved_snapshots(data.get("snapshots"),missing)
	var journey: Variant = data.get("expedition")
	if not journey is Dictionary: return missing
	for field: String in ["garage_stock","deployment_cargo"]: _missing_saved_items(journey.get(field),missing)
	_missing_id(journey.get("selected_stop"),not CampaignCatalog.stop(str(journey.get("selected_stop",""))).is_empty(),missing)
	var vehicle: Variant = journey.get("vehicle")
	if vehicle is Dictionary:
		_missing_saved_items(vehicle.get("cargo"),missing)
		if vehicle.get("upgrades") is Array:
			for id in vehicle.upgrades: _missing_id(id,id in CampaignCatalog.VEHICLE_UPGRADES,missing)
	for field: String in ["claimed_stops","epic_weapons"]:
		if not journey.get(field) is Array: continue
		for id in journey[field]:
			_missing_id(id,not CampaignCatalog.stop(str(id)).is_empty() if field=="claimed_stops" else id in CampaignCatalog.EPIC_WEAPONS,missing)
	var departure: Variant = journey.get("departure")
	if departure is Dictionary:
		_missing_saved_snapshots(departure.get("snapshots"),missing)
		_missing_id(departure.get("destination"),CampaignCatalog.contains(str(departure.get("destination",""))),missing)
		if departure.get("shared_personal_upgrades") is Array:
			for id in departure.shared_personal_upgrades: _missing_id(id,id in CampaignCatalog.PERSISTENT_UPGRADES,missing)
		var previous_vehicle: Variant = departure.get("vehicle")
		if previous_vehicle is Dictionary: _missing_saved_items(previous_vehicle.get("cargo"),missing)
	return missing

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _unique_ids(value: Variant, allowed: Array) -> bool:
	if not value is Array or value.size() > allowed.size(): return false
	var seen: Dictionary = {}
	for id in value:
		if not id is String or not allowed.has(id) or seen.has(id): return false
		seen[id] = true
	return true

static func valid_checkpoint(data: Dictionary) -> bool:
	if data.get("version") == 1:
		if data.has("expedition"): return false
		data = migrate_checkpoint(data)
	var required := ["version", "active", "campaign_id", "current_node", "pending_node", "options", "character_ids", "player_count", "completed", "unlocked_routes", "blueprints", "claimed_missions", "banked_salvage", "total_salvage_earned", "snapshots", "shared_personal_upgrades", "expedition"]
	if data.has("air_raid_intro_seen"):
		if not data.air_raid_intro_seen is bool: return false
		required.append("air_raid_intro_seen")
	if data.has("content_requirements"):
		if not _valid_content_requirements(data.content_requirements) or not incompatible_content_requirements(data).is_empty(): return false
		required.append("content_requirements")
	if data.size() != required.size(): return false
	for key: String in required:
		if not data.has(key): return false
	if data.version != VERSION or data.active != true or not data.campaign_id is String or data.campaign_id.is_empty() or data.campaign_id.length() > 80: return false
	if not data.current_node is String or not data.pending_node is String or not CampaignCatalog.contains(data.pending_node): return false
	if not data.current_node.is_empty() and not CampaignCatalog.contains(data.current_node): return false
	if not data.options is Dictionary or data.options.size() != 3: return false
	for key: String in ["environment", "build_type", "position"]:
		if not data.options.get(key) is String: return false
	if ScenarioCatalog.validate(data.options) != data.options: return false
	if not _integer(data.player_count, 1, PartyConfig.MAX_PLAYERS) or not data.character_ids is Array or data.character_ids.size() < int(data.player_count) or data.character_ids.size() > PartyConfig.MAX_PLAYERS: return false
	for character in data.character_ids:
		if not character is String or not CharacterCatalog.contains(character): return false
	var ids: Array = []
	var side_ids: Array = []
	for entry: Dictionary in CampaignCatalog.NODES:
		ids.append(entry.id)
		if int(entry.cost) > 0: side_ids.append(entry.id)
	if not _unique_ids(data.completed, ids) or not _unique_ids(data.unlocked_routes, side_ids) or not _unique_ids(data.blueprints, CampaignCatalog.BLUEPRINTS.keys()) or not _unique_ids(data.shared_personal_upgrades, CampaignCatalog.PERSISTENT_UPGRADES): return false
	if not CampaignCatalog.valid_medic_research(data.shared_personal_upgrades): return false
	if not _integer(data.banked_salvage, 0, 100000) or not _integer(data.total_salvage_earned, 0, 100000): return false
	var spent := 0
	var expected_blueprints: Array = []
	for id: String in data.unlocked_routes:
		var entry := CampaignCatalog.node(id)
		if not data.completed.has(entry.parent): return false
		spent += int(entry.cost)
	for id: String in data.completed:
		var entry := CampaignCatalog.node(id)
		if not str(entry.parent).is_empty() and not data.completed.has(entry.parent): return false
		if int(entry.cost) > 0 and not data.unlocked_routes.has(id): return false
		if not str(entry.blueprint).is_empty(): expected_blueprints.append(entry.blueprint)
	if data.total_salvage_earned - spent != data.banked_salvage or data.blueprints.size() != expected_blueprints.size(): return false
	for blueprint: String in expected_blueprints:
		if not data.blueprints.has(blueprint): return false
	var expected_claims: Array = []
	for id: String in data.completed: expected_claims.append("%s:%s" % [data.campaign_id, id])
	if not _unique_ids(data.claimed_missions, expected_claims) or data.claimed_missions.size() != expected_claims.size(): return false
	if data.current_node.is_empty()!=data.completed.is_empty(): return false
	if not data.current_node.is_empty() and not data.completed.has(data.current_node): return false
	var pending := CampaignCatalog.node(data.pending_node)
	if not str(pending.parent).is_empty() and not data.completed.has(pending.parent): return false
	if int(pending.cost) > 0 and not data.unlocked_routes.has(pending.id): return false
	if not data.snapshots is Dictionary or data.snapshots.size() != (0 if data.completed.is_empty() else int(data.player_count)): return false
	for slot in data.snapshots:
		if not slot is String or not slot in ["1", "2", "3", "4"] or int(slot) > int(data.player_count): return false
		if not CampaignBonus.valid_snapshot(data.snapshots[slot]) or data.snapshots[slot].character != data.character_ids[int(slot)-1]: return false
	if not valid_expedition(data.expedition): return false
	# A departure is a complete rewind for this exact party and selected route.
	# Individual snapshot validity cannot detect missing crew or mismatched
	# identities; accepting such a primary would bypass a good backup and restore
	# default supplies or a destination the saved party never selected.
	if not data.expedition.selected_stop.is_empty() and CampaignCatalog.stop(data.expedition.selected_stop).destination!=data.pending_node: return false
	if not data.expedition.departure.is_empty():
		var departure: Dictionary=data.expedition.departure
		if departure.destination!=data.pending_node or departure.stop!=data.expedition.selected_stop or departure.snapshots.size()!=int(data.player_count): return false
		for slot: String in departure.snapshots:
			if int(slot)>int(data.player_count) or departure.snapshots[slot].character!=data.character_ids[int(slot)-1]: return false
	for stop_id: String in data.expedition.claimed_stops:
		var destination: String = CampaignCatalog.stop(stop_id).destination
		if not data.completed.has(CampaignCatalog.node(destination).parent): return false
	for snapshot: Dictionary in data.snapshots.values():
		if snapshot.weapon_kind in CampaignCatalog.EPIC_WEAPONS and not data.expedition.epic_weapons.has(snapshot.weapon_kind): return false
		if not CampaignBonus.valid_ammunition_research(snapshot,data.shared_personal_upgrades,data.expedition.epic_weapons): return false
	return true

static func new_expedition() -> Dictionary:
	return {"stage":"defense", "vehicle":{"unlocked":false,"hp":600.0,"fuel":0.0,"cargo":{},"upgrades":[],"ammo":0,"reserve":0,"open_pack":0}, "tech_points":0, "selected_stop":"", "claimed_stops":[], "epic_weapons":[], "departure":{}, "deployment_cargo":{}, "garage_stock":{}}

static func migrate_checkpoint(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	if not result.has("air_raid_intro_seen"): result.air_raid_intro_seen = false
	if int(result.get("version",0)) == 1 and not result.has("expedition"):
		result.version = VERSION
		result.expedition = new_expedition()
		if result.get("completed",[]) is Array and not result.completed.is_empty():
			result.expedition.stage = "preparation"
			result.expedition.vehicle.unlocked = true
			result.expedition.vehicle.fuel = 12.0
	# Version1 and older version2 saves lacked round counts. Normalize once so
	# subsequent checkpoints always carry finite magazines and opened packages.
	var saved_snapshots: Variant=result.get("snapshots",{})
	if saved_snapshots is Dictionary:
		for value in saved_snapshots.values():
			if value is Dictionary and not value.has("ammunition"): value.ammunition=WorkerWeapon.initial_ammunition()
	var trip: Variant=result.get("expedition",{})
	if trip is Dictionary:
		var vehicle: Variant=trip.get("vehicle",{})
		if vehicle is Dictionary and not vehicle.has("open_pack"): vehicle.open_pack=0
		var departure: Variant=trip.get("departure",{})
		if departure is Dictionary and not departure.is_empty():
			vehicle=departure.get("vehicle",{})
			if vehicle is Dictionary and not vehicle.has("open_pack"): vehicle.open_pack=0
			var departing: Variant=departure.get("snapshots",{})
			if departing is Dictionary:
				for value in departing.values():
					if value is Dictionary and not value.has("ammunition"): value.ammunition=WorkerWeapon.initial_ammunition()
	return result

static func valid_vehicle(value: Variant) -> bool:
	if not value is Dictionary or value.size() not in [7,8]: return false
	if value.size()==8 and not value.has("open_pack"): return false
	if not _integer(value.get("open_pack",0),0,39): return false
	for key: String in ["unlocked","hp","fuel","cargo","upgrades","ammo","reserve"]:
		if not value.has(key): return false
	if not _integer(value.ammo,0,40) or not _integer(value.reserve,0,240): return false
	if not value.unlocked is bool or not _unique_ids(value.upgrades,CampaignCatalog.VEHICLE_UPGRADES): return false
	if not CampaignCatalog.valid_vehicle_research(value.upgrades): return false
	var stats := CampaignCatalog.vehicle_stats(value.upgrades)
	for key: String in ["hp","fuel"]:
		if not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or float(value[key])<0: return false
	if float(value.hp)>float(stats.max_hp) or float(value.fuel)>float(stats.fuel_capacity): return false
	if not value.cargo is Dictionary or value.cargo.size()>CampaignCatalog.CARGO_KINDS.size(): return false
	for kind in value.cargo:
		if not kind is String or not CampaignCatalog.CARGO_KINDS.has(kind) or not _integer(value.cargo[kind],1,int(stats.cargo_capacity)): return false
	return CampaignCatalog.cargo_count(value.cargo)<=int(stats.cargo_capacity)

static func valid_expedition(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=9: return false
	for key: String in ["stage","vehicle","tech_points","selected_stop","claimed_stops","epic_weapons","departure","deployment_cargo","garage_stock"]:
		if not value.has(key): return false
	if not value.stage is String or not CampaignCatalog.STAGES.has(value.stage) or not valid_vehicle(value.vehicle): return false
	if not _integer(value.tech_points,0,100000) or not value.selected_stop is String: return false
	if not value.selected_stop.is_empty() and CampaignCatalog.stop(value.selected_stop).is_empty(): return false
	var all_stops: Array = []
	for entry: Dictionary in CampaignCatalog.NODES:
		if entry.id != CampaignCatalog.ENTRY: all_stops.append_array(CampaignCatalog.journey(entry.id).stops)
	if not _unique_ids(value.claimed_stops,all_stops) or not _unique_ids(value.epic_weapons,CampaignCatalog.EPIC_WEAPONS): return false
	var earned_weapons: Array = []
	for stop_id: String in value.claimed_stops:
		var weapon: String = CampaignCatalog.stop(stop_id).weapon
		if not weapon.is_empty() and not earned_weapons.has(weapon): earned_weapons.append(weapon)
	if value.epic_weapons.size()!=earned_weapons.size(): return false
	for weapon: String in earned_weapons:
		if not value.epic_weapons.has(weapon): return false
	if not valid_stock(value.garage_stock): return false
	if not value.deployment_cargo is Dictionary: return false
	var delivery: Dictionary = value.vehicle.duplicate(true)
	delivery.cargo = value.deployment_cargo
	if not valid_vehicle(delivery): return false
	if not value.departure is Dictionary: return false
	if not value.departure.is_empty():
		var start: Dictionary = value.departure
		if start.size()!=6: return false
		for key: String in ["vehicle","tech_points","snapshots","shared_personal_upgrades","destination","stop"]:
			if not start.has(key): return false
		if not valid_vehicle(start.vehicle) or not _integer(start.tech_points,0,100000): return false
		if not start.destination is String or CampaignCatalog.journey(start.destination).is_empty() or not start.stop is String: return false
		if not start.stop.is_empty() and not CampaignCatalog.journey(start.destination).stops.has(start.stop): return false
		if not _unique_ids(start.shared_personal_upgrades,CampaignCatalog.PERSISTENT_UPGRADES) or not start.snapshots is Dictionary or start.snapshots.size()>PartyConfig.MAX_PLAYERS: return false
		if not CampaignCatalog.valid_medic_research(start.shared_personal_upgrades): return false
		for slot in start.snapshots:
			if not slot is String or not slot in ["1","2","3","4"] or not CampaignBonus.valid_snapshot(start.snapshots[slot]): return false
			if start.snapshots[slot].weapon_kind in CampaignCatalog.EPIC_WEAPONS and not value.epic_weapons.has(start.snapshots[slot].weapon_kind): return false
			if not CampaignBonus.valid_ammunition_research(start.snapshots[slot],start.shared_personal_upgrades,value.epic_weapons): return false
	if value.stage in ["travel","stop","occupation","failed"] and value.departure.is_empty(): return false
	return true

func _refresh_expedition_snapshot(upgrades: Node = null, reset_route: bool = true) -> void:
	if not expedition.vehicle.unlocked:
		expedition.vehicle.unlocked = true
		expedition.vehicle.hp = 600.0
		# The recovered truck contains one finite departure supply.
		expedition.vehicle.fuel = 12.0
	if is_instance_valid(upgrades):
		expedition.tech_points = int(upgrades.points)
		expedition.vehicle.upgrades.clear()
		for id: String in CampaignCatalog.VEHICLE_UPGRADES:
			if upgrades.has_upgrade(id): expedition.vehicle.upgrades.append(id)
	if not reset_route: return
	expedition.stage = "preparation"
	expedition.deployment_cargo = {}
	expedition.selected_stop = ""
	expedition.departure = {}

func prepare_expedition(players: Array, upgrades: Node = null) -> bool:
	if not expedition.stage in ["preparation","map"]: return false
	if not active or mission_running or current_node.is_empty() or not completed.has(current_node): return false
	var previous := checkpoint()
	if not _capture_crew(players,upgrades): return false
	return _commit(previous)

func _capture_crew(players: Array, upgrades: Node = null) -> bool:
	# Only safe boundaries call this. Ordinary road ticks keep the original
	# departure/secured-stop rewind instead of silently advancing its supplies.
	var prepared: Dictionary = {}
	for player in players:
		var snapshot := CampaignBonus.snapshot_player(player)
		if snapshot.is_empty() or prepared.has(str(player.player_id)): return false
		var slot := int(player.player_id)
		if slot<1 or slot>player_count or snapshot.character!=character_ids[slot-1]: return false
		prepared[str(player.player_id)] = snapshot
	if prepared.size()!=player_count: return false
	snapshots = prepared
	if is_instance_valid(upgrades):
		shared_personal_upgrades.clear()
		for id: String in CampaignCatalog.PERSISTENT_UPGRADES:
			if upgrades.has_upgrade(id): shared_personal_upgrades.append(id)
	_refresh_expedition_snapshot(upgrades,false)
	return true

func update_vehicle(value: Dictionary, persist: bool = false) -> bool:
	if not valid_vehicle(value): return false
	if persist and not expedition.stage in ["preparation","map"]: return false
	var previous := checkpoint()
	expedition.vehicle = value.duplicate(true)
	if persist: return _commit(previous)
	changed.emit()
	return true

func select_stop(id: String) -> bool:
	if not expedition.stage in ["preparation","map"] or mission_running: return false
	if not id.is_empty():
		if completed.has(pending_node): return false
		var halt := CampaignCatalog.stop(id)
		if halt.is_empty() or halt.destination!=pending_node or expedition.claimed_stops.has(id): return false
	var previous := checkpoint()
	expedition.selected_stop = id
	expedition.stage = "map"
	return _commit(previous)

func begin_journey(destination: String = "") -> Dictionary:
	if destination.is_empty(): destination = pending_node
	if not active or mission_running or not expedition.stage in ["preparation","map"] or not expedition.vehicle.unlocked: return {}
	if not route_status(destination).can_travel or destination == CampaignCatalog.ENTRY: return {}
	var cost := CampaignCatalog.route_fuel(destination,expedition.selected_stop,expedition.vehicle.upgrades)
	if cost<1 or expedition.vehicle.hp<=0 or expedition.vehicle.fuel<float(cost): return {}
	var previous := checkpoint()
	pending_node = destination
	expedition.departure = {"vehicle":expedition.vehicle.duplicate(true), "tech_points":expedition.tech_points, "snapshots":snapshots.duplicate(true), "shared_personal_upgrades":shared_personal_upgrades.duplicate(), "destination":destination, "stop":expedition.selected_stop}
	expedition.stage = "travel"
	if not _commit(previous): return {}
	var route := CampaignCatalog.journey(destination)
	route.fuel_cost = cost
	route.stop = expedition.selected_stop
	return route

func reach_stop() -> bool:
	if expedition.stage!="travel" or expedition.selected_stop.is_empty() or expedition.claimed_stops.has(expedition.selected_stop): return false
	expedition.stage = "stop"
	changed.emit()
	return true

func secure_stop(players: Array = [], upgrades: Node = null) -> Dictionary:
	var id: String = expedition.selected_stop
	var halt := CampaignCatalog.stop(id)
	if expedition.stage!="stop" or halt.is_empty() or expedition.claimed_stops.has(id): return {}
	var previous := checkpoint()
	if not players.is_empty() and not _capture_crew(players,upgrades): return {}
	var stats := CampaignCatalog.vehicle_stats(expedition.vehicle.upgrades)
	var delivered: Dictionary = {}
	for kind: String in halt.cargo:
		var room := int(stats.cargo_capacity)-CampaignCatalog.cargo_count(expedition.vehicle.cargo)
		var amount := mini(room,int(halt.cargo[kind]))
		if amount>0:
			expedition.vehicle.cargo[kind] = int(expedition.vehicle.cargo.get(kind,0))+amount
			delivered[kind] = amount
	var fuel_before := float(expedition.vehicle.fuel)
	expedition.vehicle.fuel = minf(float(stats.fuel_capacity),fuel_before+float(halt.fuel))
	var weapon := str(halt.weapon)
	if not weapon.is_empty() and not expedition.epic_weapons.has(weapon): expedition.epic_weapons.append(weapon)
	expedition.claimed_stops.append(id)
	expedition.stage = "travel"
	# A secured stop becomes the retry boundary. Its claimed reward and the
	# remaining supplies are committed together, so reloading cannot duplicate it.
	expedition.departure.vehicle = expedition.vehicle.duplicate(true)
	expedition.departure.snapshots = snapshots.duplicate(true)
	expedition.departure.tech_points = expedition.tech_points
	expedition.departure.shared_personal_upgrades = shared_personal_upgrades.duplicate()
	if not _commit(previous): return {}
	return {"id":id,"fuel":float(expedition.vehicle.fuel)-fuel_before,"cargo":delivered,"weapon":weapon}

func arrive_at_destination(players: Array = [], upgrades: Node = null) -> bool:
	if expedition.stage!="travel": return false
	if not expedition.selected_stop.is_empty() and not expedition.claimed_stops.has(expedition.selected_stop): return false
	var previous := checkpoint()
	if not players.is_empty() and not _capture_crew(players,upgrades): return false
	expedition.stage = "occupation"
	return _commit(previous)

func secure_destination(players: Array = [], upgrades: Node = null) -> bool:
	if expedition.stage!="occupation" or not route_status(pending_node).can_travel: return false
	var previous := checkpoint()
	if not players.is_empty() and not _capture_crew(players,upgrades): return false
	if completed.has(pending_node):
		# The departure warehouse belongs to the previous bunker. Only real
		# vehicle cargo and carried hands arrive at a revisited location. The
		# normal preparation mirror transfers these hands exactly once.
		var delivered: Dictionary = expedition.vehicle.cargo.duplicate()
		for snapshot: Dictionary in snapshots.values():
			for kind: String in CampaignCatalog.CARGO_KINDS:
				var amount := int(snapshot.get("inventory",{}).get(kind,0))
				if amount>0: delivered[kind]=int(delivered.get(kind,0))+amount
		if not valid_stock(delivered):
			_restore(previous)
			return false
		current_node=pending_node
		expedition.stage="preparation"
		expedition.garage_stock=delivered
		expedition.deployment_cargo={}
		expedition.vehicle.cargo.clear()
		expedition.selected_stop=""
		expedition.departure={}
		return _commit(previous)
	expedition.stage = "defense"
	expedition.garage_stock = {}
	expedition.deployment_cargo = expedition.vehicle.cargo.duplicate()
	expedition.vehicle.cargo.clear()
	expedition.selected_stop = ""
	expedition.departure = {}
	return _commit(previous)

func fail_journey() -> void:
	if not expedition.stage in ["travel","stop","occupation"]: return
	expedition.stage = "failed"
	changed.emit()

func retry_journey() -> Dictionary:
	if not expedition.stage in ["failed","travel","stop","occupation"] or expedition.departure.is_empty(): return {}
	var start: Dictionary = expedition.departure
	expedition.vehicle = start.vehicle.duplicate(true)
	expedition.tech_points = int(start.tech_points)
	snapshots = start.snapshots.duplicate(true)
	shared_personal_upgrades = start.shared_personal_upgrades.duplicate()
	pending_node = start.destination
	expedition.selected_stop = start.stop
	expedition.stage = "travel"
	changed.emit()
	var route := CampaignCatalog.journey(pending_node)
	route.fuel_cost = CampaignCatalog.route_fuel(pending_node,expedition.selected_stop,expedition.vehicle.upgrades)
	route.stop = "" if expedition.claimed_stops.has(expedition.selected_stop) else expedition.selected_stop
	route.resumed_after_stop = not expedition.selected_stop.is_empty() and expedition.claimed_stops.has(expedition.selected_stop)
	return route

func take_cargo() -> Dictionary:
	# Apply once to each freshly constructed bunker; the durable value remains
	# available when retrying that mission from its original deployment.
	if expedition.stage!="defense": return {}
	return expedition.deployment_cargo.duplicate()

static func valid_stock(value: Variant) -> bool:
	if not value is Dictionary or value.size()>CampaignCatalog.CARGO_KINDS.size(): return false
	for kind in value:
		if not kind is String or not CampaignCatalog.CARGO_KINDS.has(kind) or not _integer(value[kind],0,MAX_STOCK_PER_KIND): return false
	return true
