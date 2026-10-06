class_name CharacterCatalog
extends RefCounted
## Personal starting preferences; every worker can mine, build and use all weapons.
const Roster := preload("res://scripts/crew_roster.gd")
const Registry := preload("res://scripts/content_registry.gd")
# Compatibility surface for existing menus; the registry owns the definitions.
static var _characters: Array = _definitions()
static var CHARACTERS: Array:
	get: return _characters
static var _presentation_profiles: Dictionary = _presentation_map()

static func _definitions() -> Array:
	var result := Registry.entries("characters")
	_freeze(result)
	return result

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: _freeze(child)
		value.make_read_only()

static func _presentation_map() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in CHARACTERS:
		var profiles: Dictionary = {}
		for kind: String in ["visual", "motion", "dance", "voice"]:
			profiles[kind] = str(entry.get(kind+"_profile",entry.id))
		result[str(entry.id)] = profiles
	_freeze(result)
	return result

static func presentation_id(id: String,kind: String) -> String:
	# Profile aliases change authored presentation only, never actor identity.
	return str(_presentation_profiles.get(id,{}).get(kind,id))

static func starter_ids() -> Array[String]:
	return Registry.starter_ids()

static func data(id: String) -> Dictionary:
	var entry: Dictionary = Registry.data("characters",id)
	if entry.is_empty(): entry = Registry.data("characters","mara")
	return LocaleText.data(entry)

static func contains(id: String) -> bool:
	return Registry.contains("characters",id)

static func is_unlocked(id: String) -> bool:
	return contains(id) and Roster.is_unlocked(id)

static func unlock_for_site(site: String) -> Array[String]:
	return Roster.unlock_for_site(site)

static func unlock_hint(id: String) -> String:
	var entry := data(id)
	if not entry.has("unlock_site"): return ""
	return LocaleText.text("Auf der Reise entdecken.")

static func reload_multiplier(id: String) -> float:
	return float(data(id).get("reload_multiplier",1.0))

static func medical_speed(id: String) -> float:
	return float(data(id).get("medical_speed",1.0))

static func selection_title(id: String) -> String:
	return LocaleText.text(str(data(id).title)).capitalize() if is_unlocked(id) else LocaleText.text("VERMISST")

static func selection_detail(id: String) -> String:
	return str(data(id).detail) if is_unlocked(id) else LocaleText.text("Identität unbekannt. Halte auf der Reise Ausschau.")
