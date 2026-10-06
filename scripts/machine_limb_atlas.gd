extends RefCounted
## One texture RID for the painted limbs, bearings, soles and hydraulic rods.
## AtlasTexture preserves each old piece's size and lets adjacent limbs batch.
const PATH := "res://assets/enemies/machine_limbs_v1.png"
const METADATA := "res://assets/enemies/machine_limbs_v1.source.json"
static var texture: Texture2D
static var regions: Dictionary = {}
static var loaded := false
static var parts: Dictionary = {}

static func part(key: String) -> AtlasTexture:
	if not loaded:
		loaded=true
		regions=_read_regions(METADATA)
	if not regions.has(key): return null
	if not parts.has(key):
		if texture==null:
			if not ResourceLoader.exists(PATH): return null
			texture=load(PATH) as Texture2D
		if texture==null: return null
		var region: Variant = regions[key]
		if not _valid_region(region,texture.get_size()): return null
		var result := AtlasTexture.new()
		result.atlas=texture
		result.region=Rect2(region[0],region[1],region[2],region[3])
		parts[key]=result
	return parts[key] as AtlasTexture

static func _read_regions(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK: return {}
	var data: Variant = parser.data
	if not data is Dictionary: return {}
	var source: Variant = data.get("regions",{})
	return source if source is Dictionary else {}

static func _valid_region(region: Variant,size: Vector2) -> bool:
	if not region is Array or region.size()!=4: return false
	for value: Variant in region:
		if not (value is int or value is float) or not is_finite(float(value)): return false
		if value<0 or value!=floorf(float(value)): return false
	return region[2]>0 and region[3]>0 and float(region[0])+float(region[2])<=size.x and float(region[1])+float(region[3])<=size.y
