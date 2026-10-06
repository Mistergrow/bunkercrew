extends RefCounted
## Offline v3 masks: white sky, black buildings, mountains and terrain.
const EDGE_MARGIN := 0.0
const Landmarks := preload("res://scripts/panorama_landmarks.gd")
const Layers := preload("res://scripts/parallax_catalog.gd")
static var SKYLINES: Dictionary = _outlines()

static func _outlines() -> Dictionary:
	var result := {}
	for id: String in Landmarks.data.environments:
		var outline := PackedVector2Array()
		for pixel: Array in Landmarks.entry(id).skyline_pixels:
			outline.append(Vector2(float(pixel[0])/1672.0, float(pixel[1])/941.0))
		result[id] = outline
	return result

static var _textures: Dictionary = {}

static func points(environment_id: String) -> PackedVector2Array:
	return PackedVector2Array(SKYLINES.get(Layers.background_id(environment_id), []))

static func texture(environment_id: String) -> Texture2D:
	if _textures.has(environment_id):
		return _textures[environment_id]
	var path := Layers.sky_mask_path(environment_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	# Segmentation is offline asset work. World changes only upload one small
	# cached texture, with no source readback, pixel scan or per-frame mask work.
	var result := load(path) as Texture2D
	_textures[environment_id] = result
	return result
