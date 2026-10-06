extends RefCounted
## Fixed native field-kit parts. Continuous bones, cloth states, reloads,
## weapon deployment and muzzle flashes remain driven by the original rig.
const PATH := "res://assets/enemies/infantry_parts_v1.png"
const ROLES := ["rifle_guard","grenadier","scout","heavy_gunner","marksman","combat_medic"]
const SIZE := 64
const COLUMNS := 16
static var texture: Texture2D

static func tile_index(part: String, kind: String, slot: int = 0, sway: float = 0.0) -> int:
	var role := ROLES.find(kind)
	match part:
		"head": return role*35+posmod(slot+1,7)*5+clampi(roundi(sway)+1,0,4)
		"torso": return 210+role
		"rear": return 216+role*5+clampi(roundi(sway)+1,0,4)
		"gun": return 246+role
	return -1

static func origin(part: String) -> Vector2:
	return Vector2(12,16) if part=="gun" else Vector2(32,32)

static func draw_part(canvas: Node2D, transform: Transform2D, part: String, kind: String, slot: int = 0, sway: float = 0.0) -> void:
	if texture==null: texture=load(PATH)
	var index := tile_index(part,kind,slot,sway)
	var region := Rect2(Vector2(index%COLUMNS,floori(float(index)/COLUMNS))*SIZE,Vector2.ONE*SIZE)
	canvas.draw_set_transform_matrix(transform)
	canvas.draw_texture_rect_region(texture,Rect2(-origin(part),Vector2.ONE*SIZE),region)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
