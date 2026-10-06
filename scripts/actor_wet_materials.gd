extends RefCounted
## A bounded material pool lets wet articulated parts share renderer batches.
const SHADER := preload("res://shaders/actor_wet.gdshader")
static var materials: Dictionary = {}
static var clock := 0.0
static var _clock_frame := -1

static func get_material(metal: bool, top: float, opaque_only: bool, cutoff: float) -> ShaderMaterial:
	var key := Vector4(1.0 if metal else 0.0,top,1.0 if opaque_only else 0.0,cutoff)
	if not materials.has(key):
		var surface := ShaderMaterial.new()
		surface.shader = SHADER
		surface.set_shader_parameter("metal",key.x)
		surface.set_shader_parameter("art_top",top)
		surface.set_shader_parameter("opaque_only",opaque_only)
		surface.set_shader_parameter("sprite_alpha_cutoff",cutoff)
		surface.set_shader_parameter("wet_clock",clock)
		materials[key] = surface
	return materials[key]

static func update_clock(source: Node, delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _clock_frame or source.get_tree().paused: return
	_clock_frame = frame
	clock += delta
	for surface: ShaderMaterial in materials.values():
		surface.set_shader_parameter("wet_clock",clock)
