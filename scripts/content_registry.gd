class_name ContentRegistry
extends RefCounted
## Immutable, indexed content loaded once before catalogs initialize. This leaf
## deliberately depends on no gameplay, localization or presentation scripts.
const MANIFEST := "res://assets/content/packs.json"
const CORE := "bunkercrew.core"
const KINDS := ["items", "characters", "workshop_recipes", "station_recipes", "environments"]
const CHARACTER_PROFILES := ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]
const ENVIRONMENT_PROFILES := ["sector07", "ash_foundry", "abandoned_harbor", "basalt_quarry", "overgrown_steelworks", "frozen_rail_yard", "iron_canyon", "flooded_power_station", "mountain_pass", "storm_dam", "sulfur_refinery", "radar_highlands", "buried_megafactory"]
const MAX_FILE_BYTES := 2097152
const MAX_TOTAL_BYTES := 16777216
const MAX_PACKS := 64
const MAX_ENTRIES := 4096
const PROCEDURAL_ITEMS := ["limestone","glass","tungsten","alloy","jaw_trap","blast_trap","sentry_kit"]
const FIELDS := {
	"characters":["id","title","detail","special","hp","speed","damage","work","capacity","accent","visual_profile","motion_profile","dance_profile","voice_profile","reload_multiplier","medical_speed","unlocked","unlock_site","legacy_auto_unlock","starter_slot"],
	"items":["id","label","color","inventory_order","storage","cargo","art"],
	"workshop_recipes":["id","kind","label","cost","time","note","amount","armor","art"],
	"station_recipes":["id","label","inputs","output","amount","time","binder","alternates"],
	"environments":["id","title","detail","sky_color","earth_tint","path","size","continuous_background","framing_width","framing_bottom","sky_cutoff","smoke_anchors","light_anchors","water_regions","waterfall_regions","water_outlets","water_extend","palette","weather","animated_sky","rain_strength","lightning","campaign_only","surface_profile","background_profile","layer_paths"],
}
static var _loaded := false
static var _state: Dictionary = {}
static var _reads := 0
static var _manifest_paths: Array[String] = []
static var _texture_sizes: Dictionary = {}
static var _base_messages: Dictionary = {}
static var _json_cache: Dictionary = {}
static var _bytes_read := 0

static func _initialize() -> void:
	if _loaded: return
	_loaded = true
	var base_locale = JSON.parse_string(FileAccess.get_file_as_string("res://locales/de.json"))
	if base_locale is Dictionary: _base_messages = base_locale
	var errors: Array[String] = []
	var manifest := _read_json(MANIFEST, errors)
	var documents: Array = []
	if manifest.get("schema") != 1 or not manifest.get("packs") is Array or manifest.packs.size() > MAX_PACKS:
		errors.append("Invalid content manifest: " + MANIFEST)
	else:
		var seen: Dictionary = {}
		for path in manifest.packs:
			if not resource_path(path, ".json") or seen.has(path):
				errors.append("Invalid or repeated pack path: " + str(path))
				continue
			seen[path] = true
			_manifest_paths.append(path)
			var descriptor := _read_json(path, errors)
			var document := descriptor.duplicate(true)
			document["entries"] = {}
			if not descriptor.get("catalogs") is Dictionary:
				errors.append("Missing catalogs: " + str(path))
				continue
			for kind in descriptor.catalogs:
				var source = descriptor.catalogs[kind]
				if kind not in KINDS or not source is Dictionary or source.size() != 2 or not source.get("field") is String or not resource_path(source.get("path"), ".json"):
					errors.append("Invalid catalog source: " + str(path) + " / " + str(kind))
					document.entries[kind] = null
					continue
				var parsed := _read_json(source.path, errors)
				document.entries[kind] = parsed.get(source.field)
			documents.append(document)
	_state = build_index(documents)
	errors.append_array(_state.errors)
	_state.errors = errors

static func _read_json(path: String, errors: Array[String]) -> Dictionary:
	if _json_cache.has(path): return _json_cache[path]
	_reads += 1
	if not FileAccess.file_exists(path):
		errors.append("Missing content JSON: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES or _bytes_read + file.get_length() > MAX_TOTAL_BYTES:
		errors.append("Unreadable or oversized content JSON: " + path)
		return {}
	_bytes_read += file.get_length()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary or not _bounded(parser.data):
		errors.append("Invalid bounded content JSON: " + path)
		return {}
	_json_cache[path] = parser.data
	return _json_cache[path]

static func entries(kind: String) -> Array:
	_initialize()
	return _state.rows.get(kind, []).duplicate(true)

static func data(kind: String, id: String) -> Dictionary:
	_initialize()
	return _state.index.get(kind, {}).get(id, {}).duplicate(true)

static func contains(kind: String, id: String) -> bool:
	_initialize()
	return _state.index.get(kind, {}).has(id)

static func fingerprint() -> String:
	_initialize()
	return _state.fingerprint

static func diagnostics() -> Array[String]:
	_initialize()
	var result: Array[String] = []
	result.assign(_state.errors)
	return result

static func packs() -> Array:
	_initialize()
	return _state.packs.duplicate(true)

static func starter_ids() -> Array[String]:
	_initialize()
	var result: Array[String] = []
	for slot in range(1, 5):
		for row in _state.rows.characters:
			if int(row.get("starter_slot", 0)) == slot:
				result.append(str(row.id))
				break
	return result

static func translations(locale: String) -> Dictionary:
	_initialize()
	return _state.translations.get(locale, {}).duplicate(true)

static func read_count() -> int:
	_initialize()
	return _reads

static func enumerated_resources() -> Array[String]:
	_initialize()
	var result: Array[String] = [MANIFEST]
	result.append_array(_manifest_paths)
	_collect_paths(_state.rows, result)
	for pack in _state.packs: _collect_paths(pack, result)
	result.sort()
	return result

static func _collect_paths(value: Variant, result: Array[String]) -> void:
	if value is String and resource_path(value) and value not in result: result.append(value)
	elif value is Array:
		for child in value: _collect_paths(child, result)
	elif value is Dictionary:
		for child in value.values(): _collect_paths(child, result)

static func build_index(documents: Array, check_resources: bool = true) -> Dictionary:
	# Pure construction also permits isolated validation tests. Runtime exposes no
	# registration/reload API: save and network IDs cannot change during a round.
	var state: Dictionary = {"rows":{}, "index":{}, "packs":[], "translations":{"de":{}, "en":{}}, "errors":[]}
	for kind in KINDS:
		state.rows[kind] = []
		state.index[kind] = {}
	var pending: Array = []
	var declared: Dictionary = {}
	for document in documents.slice(0, MAX_PACKS):
		if not document is Dictionary or not _bounded(document) or not valid_id(document.get("id")) or document.get("schema") != 1 or not _short_string(document.get("version"), 64) or not document.get("entries") is Dictionary:
			state.errors.append("Invalid pack descriptor")
			continue
		if declared.has(document.id):
			state.errors.append("Repeated pack ID: " + document.id)
			continue
		declared[document.id] = true
		pending.append(document)
	if documents.size() > MAX_PACKS: state.errors.append("Too many content packs")
	# Core must precede any add-on, regardless of accidental manifest ordering.
	for position in pending.size():
		if pending[position].id == CORE:
			pending.push_front(pending.pop_at(position))
			break
	var accepted: Dictionary = {}
	while not pending.is_empty():
		var advanced := false
		for position in pending.size():
			var document: Dictionary = pending[position]
			var dependencies = document.get("requires", [])
			if not _valid_dependencies(dependencies, document.id):
				state.errors.append("Invalid dependencies: " + document.id)
				pending.remove_at(position)
				advanced = true
				break
			var ready: bool = document.id == CORE or accepted.has(CORE)
			for dependency in dependencies:
				ready = ready and accepted.get(dependency.id) == dependency.version
			if not ready: continue
			pending.remove_at(position)
			advanced = true
			var error := _accept(document, state, check_resources)
			if not error.is_empty(): state.errors.append(document.id + ": " + error)
			else: accepted[document.id] = document.version
			break
		if not advanced:
			for document in pending: state.errors.append("Unavailable/cyclic dependency: " + document.id)
			break
	if not accepted.has(CORE): state.errors.append("Required core content is unavailable")
	var identity: Array = []
	for pack in state.packs: identity.append({"id":pack.id, "version":pack.version})
	state["fingerprint"] = JSON.stringify(_canonical({"packs":identity, "content":state.rows})).sha256_text()
	return state

static func _accept(document: Dictionary, state: Dictionary, check_resources: bool) -> String:
	var staged: Dictionary = {}
	for kind in KINDS: staged[kind] = state.index[kind].duplicate()
	var count := 0
	for kind in document.entries:
		if kind not in KINDS: return "Unsupported category: " + str(kind)
		if not document.entries[kind] is Array: return "Invalid category array: " + kind
		count += document.entries[kind].size()
	if count > MAX_ENTRIES: return "Too many entries"
	var existing_count := 0
	for kind in KINDS: existing_count += state.rows[kind].size()
	if existing_count + count > MAX_ENTRIES: return "Installed content exceeds entry budget"
	if document.id == CORE:
		for kind in KINDS:
			if document.entries.get(kind, []).is_empty(): return "Incomplete core category: " + kind
	for kind in KINDS:
		for row in document.entries.get(kind, []):
			if not row is Dictionary or not valid_id(row.get("id")): return "Invalid entry ID: " + kind
			if document.id != CORE and not str(row.id).begins_with(document.id + ":"): return "Entry ID must use pack namespace: " + row.id
			if staged[kind].has(row.id): return "Entry override is forbidden: " + row.id
			staged[kind][row.id] = row
	if document.id == CORE:
		var slots: Array = []
		for profile in CHARACTER_PROFILES:
			if not staged.characters.has(profile): return "Missing authored character: " + profile
		for character in document.entries.characters:
			if character.has("starter_slot"):
				if not _integer(character.starter_slot, 1, 4): return "Invalid starter slot"
				var slot := int(character.starter_slot)
				if slot in slots: return "Repeated starter slot"
				slots.append(slot)
		slots.sort()
		if slots != [1, 2, 3, 4]: return "Core requires four distinct starter slots"
		for profile in ENVIRONMENT_PROFILES:
			if not staged.environments.has(profile): return "Missing authored background: " + profile
	for kind in KINDS:
		for row in document.entries.get(kind, []):
			var error := _entry_error(kind, row, document.id == CORE, staged, check_resources)
			if not error.is_empty(): return row.id + ": " + error
	var translated = document.get("translations", {})
	if not translated is Dictionary: return "Invalid translations"
	if not translated.is_empty():
		if translated.size() != 2 or not translated.get("de") is Dictionary or not translated.get("en") is Dictionary: return "Translations require de and en"
		if translated.de.size() != translated.en.size(): return "Translation keys differ"
		for key in translated.de:
			if not _short_string(key, 2048) or not _short_string(translated.de[key], 2048) or not _short_string(translated.en.get(key), 2048) or translated.de[key] != key: return "Invalid translated message"
			if state.translations.de.has(key): return "Translated message override: " + key
			if _base_messages.has(key): return "Core message override: " + key
			if _format_signature(key) != _format_signature(translated.en[key]): return "Translation format arguments differ: " + key
	# Commit all categories together only after every reference has been checked.
	state.index = staged
	for kind in KINDS: state.rows[kind].append_array(document.entries.get(kind, []).duplicate(true))
	state.packs.append({"id":document.id, "version":document.version, "catalogs":document.get("catalogs", {}).duplicate(true)})
	for locale in translated: state.translations[locale].merge(translated[locale])
	return ""

static func _entry_error(kind: String, row: Dictionary, core: bool, index: Dictionary, check_resources: bool) -> String:
	for field in row:
		if field not in FIELDS[kind]: return "Unsupported content field: " + str(field)
	match kind:
		"characters":
			if not _short_string(row.get("title"), 80) or not _short_string(row.get("detail"), 512): return "Missing character labels"
			if row.has("special") and not _short_string(row.special, 512): return "Invalid character special description"
			for profile in ["visual_profile", "motion_profile", "dance_profile", "voice_profile"]:
				if row.get(profile) not in CHARACTER_PROFILES: return "Missing authored character profile: " + profile
			for field in ["hp", "speed", "damage", "work"]:
				if not _number(row.get(field), 0.01, 10000.0): return "Invalid character stat: " + field
			if not _integer(row.get("capacity"), 1, 128): return "Invalid carry capacity"
			if not _color(row.get("accent")): return "Invalid character accent"
			for field in ["reload_multiplier", "medical_speed"]:
				if row.has(field) and not _number(row[field], 0.01, 100.0): return "Invalid character multiplier"
			for field in ["unlocked", "legacy_auto_unlock"]:
				if row.has(field) and not row[field] is bool: return "Invalid unlock rule"
			if row.has("unlock_site") and not valid_id(row.unlock_site): return "Invalid unlock site"
			if row.has("starter_slot") and (not core or not _integer(row.starter_slot, 1, 4)): return "Only core defines starter slots"
		"items":
			if not _short_string(row.get("label"), 128) or not _color(row.get("color")): return "Invalid item label/color"
			if not _integer(row.get("inventory_order"), 0, 100000) or not row.get("storage") is bool or not row.get("cargo") is bool: return "Invalid inventory metadata"
			var art = row.get("art")
			if not art is Dictionary: return "Missing item art"
			if art.get("kind") == "procedural":
				if not core or row.id not in PROCEDURAL_ITEMS: return "Item needs explicit sprite art or an authored renderer"
			elif art.get("kind") == "sprite":
				if not _valid_art(art, check_resources): return "Invalid item sprite"
			else: return "Unknown art renderer"
		"workshop_recipes":
			if not _short_string(row.get("label"), 128) or not _short_string(row.get("note"), 1024) or not _number(row.get("time"), 0.05, 3600.0): return "Invalid workshop presentation/time"
			if not _cost(row.get("cost"), index.items): return "Unknown or invalid cost item"
			if row.get("kind") in ["armor_1", "armor_2"]:
				if not _integer(row.get("armor"), 1, 2) or row.kind != "armor_" + str(int(row.armor)): return "Unsupported armor recipe"
			elif not index.items.has(row.get("kind")): return "Unknown output item"
			if row.has("amount") and not _integer(row.amount, 1, 10000): return "Invalid output amount"
			if not row.get("art") is Dictionary or not _valid_art(row.art, check_resources): return "Missing recipe picture"
		"station_recipes":
			if not core: return "New station types require an authored runtime adapter"
			if not _short_string(row.get("label"), 128) or not _cost(row.get("inputs"), index.items) or not index.items.has(row.get("output")) or not _integer(row.get("amount"), 1, 10000) or not _number(row.get("time"), 0.05, 3600.0): return "Invalid station recipe"
			if row.has("binder") and not _integer(row.binder, 0, 10000): return "Invalid binder amount"
			if row.has("alternates"):
				if not row.alternates is Dictionary: return "Invalid alternate inputs"
				for item in row.alternates:
					if not index.items.has(item) or not row.inputs.has(row.alternates[item]): return "Unknown alternate input"
		"environments":
			if not _short_string(row.get("title"), 128) or not _short_string(row.get("detail"), 1024) or not _valid_texture(row.get("path"), check_resources): return "Invalid panorama"
			var dimensions = row.get("size")
			if not dimensions is Array or dimensions.size() != 2 or not _integer(dimensions[0], 1, 32768) or not _integer(dimensions[1], 1, 32768): return "Invalid panorama dimensions"
			if not core and not row.has("layer_paths") and not row.has("background_profile"): return "Missing authored layers/background profile"
			for field in ["surface_profile", "background_profile"]:
				if row.has(field) and row[field] not in ENVIRONMENT_PROFILES: return "Unknown background profile"
				if row.has(field) and not row.has("layer_paths") and row.path != index.environments.get(row[field], {}).get("path"): return "Background alias requires its matching panorama"
			if row.has("layer_paths"):
				if not row.layer_paths is Array or row.layer_paths.size() != 3: return "Expected three parallax layers"
				for path in row.layer_paths:
					if not _valid_texture(path, check_resources): return "Missing parallax layer"
			if row.has("rain_strength") and not _number(row.rain_strength, 0.0, 1.0): return "Invalid rain strength"
			for field in ["sky_cutoff", "framing_width", "framing_bottom"]:
				if row.has(field) and not _number(row[field], 0.0, 100000.0): return "Invalid panorama geometry"
			for field in ["continuous_background","water_extend","animated_sky","lightning","campaign_only"]:
				if row.has(field) and not row[field] is bool: return "Invalid environment flag"
			for field in ["sky_color", "earth_tint"]:
				if row.has(field) and not _color(row[field]): return "Invalid environment color"
			if row.has("weather") and row.weather not in ["clear","rain","storm","snow","ash","mist","dust"]: return "Unsupported weather renderer"
			for field in ["water_regions", "waterfall_regions"]:
				if row.has(field):
					if not row[field] is Array or row[field].size() > 32: return "Invalid water regions"
					for region in row[field]:
						if not region is Array or region.size() != 4: return "Invalid water region"
						for coordinate in region:
							if not _number(coordinate, 0, 1): return "Invalid water coordinate"
						if region[2] <= 0 or region[3] <= 0 or region[0] + region[2] > 1.000001 or region[1] + region[3] > 1.000001: return "Water region exceeds panorama"
			for field in ["smoke_anchors","light_anchors","water_outlets"]:
				if row.has(field):
					if not row[field] is Array or row[field].size() > 32: return "Invalid atmosphere anchors"
					for anchor in row[field]:
						if not anchor is Array or anchor.size() not in [2,3,4]: return "Invalid atmosphere anchor"
						for coordinate in anchor:
							if not _number(coordinate, 0, 1): return "Invalid atmosphere coordinate"
	return ""

static func _valid_art(art: Dictionary, check_resources: bool) -> bool:
	for field in art:
		if field not in ["kind","texture","region","world_region","pour_region","world_width"]: return false
	if not _valid_texture(art.get("texture"), check_resources) or not _region(art.get("region")): return false
	if art.has("world_region") and not _region(art.world_region): return false
	if art.has("pour_region") and not _region(art.pour_region): return false
	if check_resources:
		if not _texture_sizes.has(art.texture):
			var texture := ResourceLoader.load(art.texture, "Texture2D") as Texture2D
			if texture == null: return false
			_texture_sizes[art.texture] = texture.get_size()
		var bounds := Rect2(Vector2.ZERO, _texture_sizes[art.texture])
		for field in ["region", "world_region", "pour_region"]:
			if art.has(field):
				var region: Array = art[field]
				if not bounds.encloses(Rect2(region[0], region[1], region[2], region[3])): return false
	return not art.has("world_width") or _number(art.world_width, 1.0, 256.0)

static func _valid_texture(path: Variant, check_resources: bool) -> bool:
	if not resource_path(path) or str(path).get_extension().to_lower() not in ["png", "webp", "svg"]: return false
	return not check_resources or ResourceLoader.exists(path, "Texture2D")

static func resource_path(path: Variant, suffix: String = "") -> bool:
	if not path is String or path.length() > 512 or not path.begins_with("res://assets/") or path.contains("\\") or path.contains("\n"): return false
	for component in path.trim_prefix("res://").split("/"):
		if component.is_empty() or component in [".", ".."]: return false
	return suffix.is_empty() or path.ends_with(suffix)

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_.:-": return false
	return true

static func _valid_dependencies(value: Variant, owner: String) -> bool:
	if not value is Array or value.size() > MAX_PACKS: return false
	var seen: Dictionary = {}
	for dependency in value:
		if not dependency is Dictionary or dependency.size() != 2 or not valid_id(dependency.get("id")) or dependency.id == owner or seen.has(dependency.id) or not _short_string(dependency.get("version"), 64): return false
		seen[dependency.id] = true
	return true

static func _cost(value: Variant, items: Dictionary) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > 32: return false
	for id in value:
		if not items.has(id) or not _integer(value[id], 1, 10000): return false
	return true

static func _region(value: Variant) -> bool:
	if not value is Array or value.size() != 4: return false
	for component in value:
		if not _integer(component, 0, 32768): return false
	return value[2] > 0 and value[3] > 0

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _short_string(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum

static func _color(value: Variant) -> bool:
	if not value is String: return false
	var raw: String = value.trim_prefix("#")
	if raw.length() != 6: return false
	for character in raw.to_lower():
		if character not in "0123456789abcdef": return false
	return true

static func _bounded(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value is Dictionary:
		if value.size() > MAX_ENTRIES: return false
		for key in value:
			if not key is String or key.length() > 2048 or not _bounded(value[key], depth + 1): return false
	elif value is Array:
		if value.size() > MAX_ENTRIES: return false
		for child in value:
			if not _bounded(child, depth + 1): return false
	elif value is String: return value.length() <= 4096
	elif value is float: return is_finite(value)
	elif not (value == null or value is int or value is bool): return false
	return true

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var sorted: Dictionary = {}
		for key in keys: sorted[key] = _canonical(value[key])
		return sorted
	if value is Array:
		var sorted: Array = []
		for child in value: sorted.append(_canonical(child))
		return sorted
	return value

static func _format_signature(value: String) -> Array[String]:
	var expression := RegEx.new()
	expression.compile("%[-+0-9]*(?:\\.[0-9]+)?([scdiouxXfFeEgGv%])")
	var result: Array[String] = []
	for found in expression.search_all(value):
		if found.get_string(1) != "%": result.append(found.get_string(1))
	return result
