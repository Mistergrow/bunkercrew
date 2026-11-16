extends RefCounted
## A bounded material pool lets wet articulated parts share renderer batches.
const SHADER := preload("res://shaders/actor_wet.gdshader")
## Values of the shader's `team` instance uniform (see actor_wet.gdshader).
const TEAM_NONE := 0.0
const TEAM_CREW := 1.0
const TEAM_HOSTILE := 2.0
static var materials: Dictionary = {}
static var clock := 0.0
static var _clock_frame := -1
## 0 by day, 1 at night: strength of the hostile crest and lamps.
static var team_night := 0.0
## Exterior light (WorldLighting): sky key rim colour and strength, its side,
## the bunker interior where it stops (x0, y0, x1, y1), lightning and its x.
static var sky_rim := Color(1, 1, 1, 0)
static var rim_side := 0.0
static var interior := Vector4.ZERO
static var flash := 0.0
static var flash_x := 0.0
## Night grade of actors under the open sky (rgb multiplier, a strength): the
## actor key keeps every figure at its authored value; outside the bunker at
## night they then sink toward the scene's light and read by their rims.
static var exterior_grade := Color(1, 1, 1, 0)

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
		surface.set_shader_parameter("team_night",team_night)
		_apply_world_light(surface)
		materials[key] = surface
	return materials[key]

static func update_clock(source: Node, delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _clock_frame or source.get_tree().paused: return
	_clock_frame = frame
	clock += delta
	for surface: ShaderMaterial in materials.values():
		surface.set_shader_parameter("wet_clock",clock)

## Presentation only: how strongly the hostile team read shows (WorldLighting).
static func set_team_night(value: float) -> void:
	value = clampf(value,0.0,1.0)
	if is_equal_approx(value,team_night): return
	team_night = value
	for surface: ShaderMaterial in materials.values():
		surface.set_shader_parameter("team_night",team_night)

## Team of an actor whose art carries the wet material: enemies, crew, none.
static func team_of(actor: Node) -> float:
	if not is_instance_valid(actor): return TEAM_NONE
	if actor.is_in_group("enemies") or actor.is_in_group("air_enemies"): return TEAM_HOSTILE
	if actor.is_in_group("players") or actor.is_in_group("medics"): return TEAM_CREW
	return TEAM_NONE

## Presentation only: the sky key and lightning on actors outside the bunker.
static func set_world_light(rim: Color, side: float, inside: Rect2, strength: float, at_x: float) -> void:
	var box := Vector4(inside.position.x, inside.position.y, inside.end.x, inside.end.y)
	if rim.is_equal_approx(sky_rim) and is_equal_approx(side, rim_side) and box.is_equal_approx(interior) and is_equal_approx(strength, flash) and is_equal_approx(at_x, flash_x): return
	sky_rim = rim
	rim_side = side
	interior = box
	flash = strength
	flash_x = at_x
	for surface: ShaderMaterial in materials.values():
		_apply_world_light(surface)

## Presentation only: the night grade of actors outside the bunker.
static func set_exterior_grade(grade: Color) -> void:
	if grade.is_equal_approx(exterior_grade): return
	exterior_grade = grade
	for surface: ShaderMaterial in materials.values():
		surface.set_shader_parameter("exterior_grade",exterior_grade)

static func _apply_world_light(surface: ShaderMaterial) -> void:
	surface.set_shader_parameter("exterior_grade",exterior_grade)
	surface.set_shader_parameter("sky_rim",sky_rim)
	surface.set_shader_parameter("rim_side",rim_side)
	surface.set_shader_parameter("interior",interior)
	surface.set_shader_parameter("flash",flash)
	surface.set_shader_parameter("flash_x",flash_x)
