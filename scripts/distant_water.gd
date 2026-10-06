extends Node2D
## Extends the two authored water surfaces under the distant banks. One cached
## quad reuses the panorama's water detail; no landmarks or CPU particles repeat.

const WATER_SHADER := preload("res://shaders/distant_water.gdshader")
const GROUND_Y := 430.0
var enabled := false
var water_top := GROUND_Y
var bounds := Rect2()
var water_material: ShaderMaterial
var _last_clock := -1.0
var _last_reduced := false

func configure(scenery: Node2D) -> void:
	name = "ExtendedWater"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var regions: Array = scenery.data.get("water_regions", [])
	enabled = not regions.is_empty() and bool(scenery.data.get("water_extend",true))
	visible = false
	if not enabled:
		material = null
		water_material = null
		return
	var region: Array = regions[0]
	water_top = scenery.panorama_rect.position.y + float(region[1]) * scenery.panorama_rect.size.y
	enabled = water_top < GROUND_Y - 1.0
	if not enabled:
		return
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("water_top", water_top)
	water_material.set_shader_parameter("water_height", GROUND_Y - water_top)
	water_material.set_shader_parameter("panorama_water", scenery.panorama.texture)
	var source_bottom: float = (GROUND_Y - scenery.panorama_rect.position.y) / scenery.panorama_rect.size.y
	water_material.set_shader_parameter("source_water", Vector2(float(region[1]), source_bottom))
	water_material.set_shader_parameter("source_pixel", Vector2.ONE / scenery.panorama.texture.get_size())
	# Sample safely below the bank. Both outer sides retain their painted color
	# and blend only across the same central span used by the sky extension.
	var top_sample := minf(water_top + 12.0, GROUND_Y)
	water_material.set_shader_parameter("top_left", scenery._edge_color(top_sample, 0))
	water_material.set_shader_parameter("top_right", scenery._edge_color(top_sample, 1))
	water_material.set_shader_parameter("bottom_left", scenery._edge_color(GROUND_Y, 0))
	water_material.set_shader_parameter("bottom_right", scenery._edge_color(GROUND_Y, 1))
	water_material.set_shader_parameter("turbulence", 0.85 if scenery.environment_id == "flooded_power_station" else 0.45)
	material = water_material
	_last_clock = -1.0
	_last_reduced = false

func update_view(view: Rect2, elapsed: float, reduced := false) -> void:
	visible = enabled and view.end.y > water_top and view.position.y < GROUND_Y
	if not visible:
		return
	if elapsed != _last_clock:
		water_material.set_shader_parameter("water_clock", elapsed)
		_last_clock = elapsed
	if reduced != _last_reduced:
		water_material.set_shader_parameter("motion_strength", 0.25 if reduced else 1.0)
		_last_reduced = reduced
	var left := floorf(view.position.x / 256.0) * 256.0 - 256.0
	var right := ceilf(view.end.x / 256.0) * 256.0 + 256.0
	var next := Rect2(left, water_top, right - left, GROUND_Y - water_top)
	if next == bounds:
		return
	bounds = next
	queue_redraw()

func _draw() -> void:
	if enabled and bounds.has_area():
		draw_rect(bounds, Color.WHITE)
