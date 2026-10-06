extends RefCounted
## Offline-reviewed masks share the original plate UVs. No image readback or
## segmentation occurs during loading or gameplay.
const Registry := preload("res://scripts/content_registry.gd")
const Layers := preload("res://scripts/parallax_catalog.gd")
const REGIONS_PATH := "res://assets/environments/background_surface_regions.json"
const MASK_ROOT := "res://assets/environments/surface_masks/"
static var _definitions: Dictionary = {}
static var _loaded := false
static var _textures: Dictionary = {}
static var _masks: Dictionary = {}
static var _aliases: Dictionary = {}

static func _initialize_catalog() -> void:
	if not _loaded:
		_loaded=true
		_definitions=_read_environments(REGIONS_PATH)
		_masks=_read_environments(MASK_ROOT+"catalog.json")

static func _surface_id(id: String) -> String:
	_initialize_catalog()
	if id.is_valid_identifier() and _definitions.has(id): return id
	if not _aliases.has(id):
		var environment := Registry.data("environments",id)
		var alias := str(environment.get("surface_profile",""))
		var source: Variant = _definitions.get(alias,{})
		var panorama := str(environment.get("city_path",environment.get("path","")))
		var layers := Layers.paths(id)
		# An existing mask is reusable only over the exact reviewed panorama.
		_aliases[id] = alias if alias.is_valid_identifier() and source is Dictionary and not panorama.is_empty() and panorama==str(source.get("reference_path",source.get("source_path",""))) and layers.size()==3 and layers[2]==source.get("source_path") else ""
	return str(_aliases[id])

static func definition(id: String) -> Dictionary:
	var source_id := _surface_id(id)
	var entry = _definitions.get(source_id,{})
	return entry if entry is Dictionary else {}

static func _read_environments(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var contents := FileAccess.get_file_as_string(path)
	if contents.is_empty(): return {}
	var document := JSON.new()
	if document.parse(contents)!=OK: return {}
	var parsed = document.data
	if not parsed is Dictionary: return {}
	var entries = parsed.get("environments",{})
	if not entries is Dictionary: return {}
	var result: Dictionary={}
	for id in entries:
		if id is String and entries[id] is Dictionary:
			result[id]=entries[id]
	return result

static func mask_path(id: String) -> String:
	var source_id := _surface_id(id)
	return MASK_ROOT+source_id+".png" if not source_id.is_empty() else ""

static func available(id: String) -> bool:
	if _surface_id(id).is_empty(): return false
	var source := definition(id)
	var mask := mask_definition(id)
	# A cropped mask without its matching UV metadata would be stretched over
	# the whole plate and could animate banks or buildings. Fail closed instead.
	if source.is_empty() or not source.get("regions") is Array or mask.is_empty(): return false
	if not _valid_bounds(mask.get("bounds")) or not _valid_dimensions(source.get("source_dimensions")): return false
	if not source.get("source_path") is String or str(source.source_path).is_empty(): return false
	if not source.get("source_sha256") is String or str(source.source_sha256).length()!=64: return false
	if mask.get("source_path")!=source.source_path or mask.get("source_sha256")!=source.source_sha256: return false
	if not mask.get("original_dimensions") is Array or mask.original_dimensions!=source.source_dimensions: return false
	return ResourceLoader.exists(mask_path(id))

static func texture(id: String) -> Texture2D:
	if not available(id): return null
	if not _textures.has(id):
		var resource = load(mask_path(id))
		if not resource is Texture2D: return null
		_textures[id]=resource
	var cached = _textures[id]
	return cached if cached is Texture2D else null

static func enabled(id: String) -> bool:
	if not available(id): return false
	var regions = definition(id).get("regions",[])
	return regions is Array and not regions.is_empty()

static func mask_definition(id: String) -> Dictionary:
	var source_id := _surface_id(id)
	var entry = _masks.get(source_id,{})
	return entry if entry is Dictionary else {}

static func _valid_bounds(value) -> bool:
	if not value is Array or value.size()!=4: return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)): return false
		if component<0.0 or component>1.000001: return false
	return value[0]>=0.0 and value[1]>=0.0 and value[2]>0.0 and value[3]>0.0 and value[0]+value[2]<=1.000001 and value[1]+value[3]<=1.000001

static func _valid_dimensions(value) -> bool:
	if not value is Array or value.size()!=2: return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)) or component<=0.0 or component!=floorf(float(component)): return false
	return true

static func bounds(id: String) -> Vector4:
	var value = mask_definition(id).get("bounds")
	if not _valid_bounds(value): return Vector4(0.0,0.0,1.0,1.0)
	return Vector4(float(value[0]),float(value[1]),float(value[2]),float(value[3]))
