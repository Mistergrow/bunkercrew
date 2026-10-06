class_name ScenarioCatalog
extends RefCounted
## Session choices are data; selecting a card never mutates the running world.
const Registry := preload("res://scripts/content_registry.gd")
const BUILD_TYPES := [
	{"id":"bastion","title":"BETONBASTION","detail":"Verstärkter Kern: +120 LP","wall":"res://assets/environments/wall_bastion.png"},
	{"id":"workshop","title":"STAHLWERK","detail":"Startvorrat +6 Stahl und +2 Beton","wall":"res://assets/environments/wall_workshop.png"},
	{"id":"stronghold","title":"FELSENFESTE","detail":"Rohstoffadern: +2 Ertrag je Zelle","wall":"res://assets/environments/wall_stronghold.png"},
]
const POSITIONS := [
	{"id":"left","title":"WESTRAND","detail":"Bodenangriffe von rechts","arrows":"BUNKER  ← ←  MASCHINEN"},
	{"id":"center","title":"MITTELLAGE","detail":"Bodenangriffe von beiden Seiten","arrows":"MASCHINEN  →  BUNKER  ←  MASCHINEN"},
	{"id":"right","title":"OSTRAND","detail":"Bodenangriffe von links","arrows":"MASCHINEN  → →  BUNKER"},
]
static var last_selection := {"environment":"ash_foundry","build_type":"bastion","position":"left"}
static var _textures: Dictionary = {}
static var _entries: Array = []
static var _by_id: Dictionary = {}
static var _loaded := false

static func _initialize_catalog() -> void:
	if _loaded: return
	_loaded = true
	_entries = Registry.entries("environments")
	for entry: Dictionary in _entries:
		_by_id[str(entry.id)] = entry

static func environments(include_campaign: bool=false) -> Array:
	_initialize_catalog()
	var result: Array = []
	for entry: Dictionary in _entries:
		if include_campaign or not bool(entry.get("campaign_only",false)): result.append(entry)
	return LocaleText.data(result)

static func environment(id: String) -> Dictionary:
	_initialize_catalog()
	var entry: Dictionary = _by_id.get(id,_entries[0] if not _entries.is_empty() else {})
	return LocaleText.data(entry)

static func texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _textures.has(path): _textures[path]=load(path)
	return _textures[path]

static func validate(options: Dictionary) -> Dictionary:
	var selected := environment(str(options.get("environment","ash_foundry")))
	var result := {"environment":str(selected.get("id","")),"build_type":"bastion","position":"left"}
	for entry in BUILD_TYPES:
		if entry.id==options.get("build_type"): result.build_type=entry.id
	for entry in POSITIONS:
		if entry.id==options.get("position"): result.position=entry.id
	return result
