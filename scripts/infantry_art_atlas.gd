extends RefCounted
## Fixed native field-kit parts. Continuous bones, cloth states, reloads,
## weapon deployment and muzzle flashes remain driven by the original rig.
## v2 is hand-pixelled per role (tools/generate_infantry_parts_v2.py) in the
## v1 layout; v1 stays the bake target of tools/bake_infantry_art.gd.
const PATH := "res://assets/enemies/infantry_parts_v2.png"
const LEGACY_PATH := "res://assets/enemies/infantry_parts_v1.png"
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

## The kit at its drawn size (style bible §1): tools/bake_infantry_world.py
## reduces the v2 tiles to the 0.82 human factor of EnemyCatalog.profile, one
## texel per world unit, bakes their turned keys at that density and authors
## the limbs there. GroundInfantryArt draws them 1:1 on whole world texels in
## an "art frame" whose unit is one rig unit times ART_SCALE.
const ART_SCALE := 0.82
const WORLD_PATH := "res://assets/enemies/infantry_parts_world.png"
const LIVING_WORLD_PATH := "res://assets/enemies/infantry_living_turns_world.png"
const GUN_WORLD_PATH := "res://assets/enemies/infantry_gun_turns_world.png"
const TURNS_WORLD_PATH := "res://assets/enemies/infantry_turns_world.png"
const LIMBS_WORLD_PATH := "res://assets/enemies/infantry_limbs_world.png"
const LimbIndex := preload("res://scripts/infantry_limb_index.gd")
const WORLD_SIZE := 54
const WORLD_BODY := Vector2(27,27)
const WORLD_GUN := Vector2(10,13)
const LIVING_BODY_CELL := 60
const LIVING_HEAD_CELL := 40
const GUN_CELL := 86
const TURN_BODY_CELL := 60
## Loaded with the script, so the first corpse or limb never waits on a load.
const SHEETS := {
	WORLD_PATH: preload(WORLD_PATH), LIVING_WORLD_PATH: preload(LIVING_WORLD_PATH), GUN_WORLD_PATH: preload(GUN_WORLD_PATH),
	TURNS_WORLD_PATH: preload(TURNS_WORLD_PATH), LIMBS_WORLD_PATH: preload(LIMBS_WORLD_PATH),
}

static func sheet(path: String) -> Texture2D:
	return SHEETS.get(path)

## An upright tile of the reduced kit with its anchor on `at` (art frame).
static func draw_world_part(canvas: CanvasItem, at: Vector2, part: String, kind: String, slot: int = 0, sway: float = 0.0) -> void:
	var index := tile_index(part,kind,slot,sway)
	var region := Rect2(Vector2(index%COLUMNS,floori(float(index)/COLUMNS))*WORLD_SIZE,Vector2.ONE*WORLD_SIZE)
	canvas.draw_texture_rect_region(sheet(WORLD_PATH),Rect2(at-(WORLD_GUN if part=="gun" else WORLD_BODY),region.size),region)

static func _role(kind: String) -> int:
	return maxi(0,ROLES.find(kind))

static func _side(kind: String, front: bool) -> int:
	return (_role(kind)*2+(0 if front else 1))*LimbIndex.PER_SIDE

static func _sprite(canvas: CanvasItem, id: int, at: Vector2) -> void:
	var data: Array[int] = LimbIndex.DATA
	var i := id*6
	var size := Vector2(data[i+2],data[i+3])
	canvas.draw_texture_rect_region(sheet(LIMBS_WORLD_PATH),Rect2(at+Vector2(data[i+4],data[i+5]),size),Rect2(Vector2(data[i],data[i+1]),size))

## One limb segment from its anchor joint (art frame, unrounded) towards the
## other joint, in the nearest of the authored direction keys.
static func draw_limb(canvas: CanvasItem, segment: String, kind: String, front: bool, anchor: Vector2, toward: Vector2) -> void:
	var index := LimbIndex.SEGMENTS.find(segment)
	var key := posmod(roundi((toward-anchor).angle()/TAU*LimbIndex.KEYS),LimbIndex.KEYS)
	var at := (anchor-Vector2(0.5,0.5)).round() if LimbIndex.CENTRED[index] else anchor.round()
	_sprite(canvas,_side(kind,front)+index*LimbIndex.KEYS+key,at)

## Knee and elbow caps and gloves on the joint's texel.
static func draw_single(canvas: CanvasItem, piece: String, kind: String, front: bool, at: Vector2) -> void:
	_sprite(canvas,_side(kind,front)+LimbIndex.SEGMENTS.size()*LimbIndex.KEYS+LimbIndex.SINGLES.find(piece),at.round())

## The boot in the nearest baked roll (radians, the rig's foot angle).
static func draw_boot(canvas: CanvasItem, kind: String, front: bool, at: Vector2, roll: float) -> void:
	var degrees := rad_to_deg(roll)
	var nearest := 0
	for index in LimbIndex.BOOT_KEYS.size():
		if absf(LimbIndex.BOOT_KEYS[index]-degrees) < absf(LimbIndex.BOOT_KEYS[nearest]-degrees): nearest = index
	_sprite(canvas,_side(kind,front)+LimbIndex.SEGMENTS.size()*LimbIndex.KEYS+LimbIndex.SINGLES.size()+nearest,at.round())
