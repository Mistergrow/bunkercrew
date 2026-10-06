extends RefCounted
## Menu effect positions measured in the current v3 source images.
const SOURCE_SIZE := Vector2(1672,941)
const Landmarks := preload("res://scripts/panorama_landmarks.gd")
const BANK_COLORS := {"dust":"9d9cb1","sand":"bb9378","snow":"b6d0de","mist":"899fb6","rust":"aa7866"}
const PLUME_COLORS := {"steam":"c1ccd0","sulfur":"b2a57a"}

static func details(environment: String) -> Dictionary:
	return Landmarks.entry(environment).get("details",{}).duplicate(true)

static func point(pixels: Vector2) -> Vector2:
	return pixels/SOURCE_SIZE

static func region(pixels: Rect2) -> Rect2:
	return Rect2(pixels.position/SOURCE_SIZE,pixels.size/SOURCE_SIZE)
