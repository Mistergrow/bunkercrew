class_name WorldTexels
extends RefCounted
## Playfield art at one texel per world unit (style bible §1, rule 1). Every
## source region the game draws has an offline bake at each world size it is
## drawn at (tools/bake_world_density_art.py, tools/world_density_bake.json).
## Draw sites ask here first and draw the bake 1:1 on whole world units, so a
## station texel is exactly as large as a worker texel. The high-density
## source is only the fallback for a size without a bake; `missing` lists
## those keys so tests catch a new draw size that was never baked.
## Rotating parts (gun barrels) come as baked stances, never as a rotated
## sprite. Presentation only: no size, hitbox or gameplay value reads this.
const Index := preload("res://scripts/world_texel_index.gd")
static var _atlases: Dictionary = {}
static var _textures: Dictionary = {}
static var _stances: Dictionary = {}
static var _sources: Dictionary = {}
static var missing: Dictionary = {}

## The high-density source of a bake for a draw site that falls back to it,
## kept loaded: a draw command holds only the texture's RID, so a loaded
## texture nobody keeps would be freed and read from disk again next frame.
static func fallback_source(path: String) -> Texture2D:
	if not _sources.has(path): _sources[path] = load(path)
	return _sources[path]

static func key(source_path: String, region: Rect2, size: Vector2i) -> String:
	return "%s|%d,%d,%d,%d|%dx%d" % [source_path, roundi(region.position.x), roundi(region.position.y), roundi(region.size.x), roundi(region.size.y), size.x, size.y]

## The bake of `region` of `source_path` at `size` world units, or null.
static func texture(source_path: String, region: Rect2, size: Vector2i) -> AtlasTexture:
	return _entry_texture(key(source_path, region, size))

## The bake of an atlas resource (.tres) at `size`, found by path: the
## resource and its high-density atlas are never loaded for it.
static func resource_texture(resource_path: String, size: Vector2i) -> AtlasTexture:
	var source: Array = Index.RESOURCES.get(resource_path, [])
	if source.is_empty():
		missing[resource_path] = true
		return null
	return texture(str(source[0]), source[1], size)

## An atlas resource at `size`: its bake, else the resource itself (loaded
## only then), to be drawn into a rect of exactly `size` on whole units.
static func resource_or_load(resource_path: String, size: Vector2i) -> Texture2D:
	var baked := resource_texture(resource_path, size)
	return baked if baked != null else load(resource_path) as Texture2D

## Source region size of an atlas resource without loading it (zero if unknown).
static func resource_size(resource_path: String) -> Vector2:
	var source: Array = Index.RESOURCES.get(resource_path, [])
	return (source[1] as Rect2).size if not source.is_empty() else Vector2.ZERO

## A part drawn by hand or kitbashed at world density (manifest "pixels" or
## "composite" items), or null if it was never baked.
static func authored(part_name: String) -> AtlasTexture:
	return _entry_texture("authored:" + part_name)

static func _entry_texture(id: String) -> AtlasTexture:
	if _textures.has(id): return _textures[id]
	var entry: Array = Index.ENTRIES.get(id, [])
	if entry.is_empty():
		missing[id] = true
		return null
	var atlas_index := int(entry[0])
	if not _atlases.has(atlas_index): _atlases[atlas_index] = load(Index.ATLASES[atlas_index])
	var result := AtlasTexture.new()
	result.atlas = _atlases[atlas_index]
	result.region = entry[1]
	result.filter_clip = true
	_textures[id] = result
	return result

## Draws `region` of `source` into `rect` (canvas units are world units): the
## bake at the rounded size on whole units. False when there is no bake; the
## caller then draws the source as before.
static func draw_region(canvas: CanvasItem, source: Texture2D, region: Rect2, rect: Rect2, tint: Color = Color.WHITE) -> bool:
	var baked := texture(source.resource_path, region, Vector2i(rect.size.round()))
	if baked == null: return false
	canvas.draw_texture_rect(baked, Rect2(rect.position.round(), baked.get_size()), false, tint)
	return true

## Baked stance angles (tenths of a degree) of a rotating part, ascending.
static func _stance_angles(base: String) -> PackedInt32Array:
	if _stances.has(base): return _stances[base]
	var angles := PackedInt32Array()
	var prefix := base + "|turn:"
	for id: String in Index.ENTRIES:
		if id.begins_with(prefix): angles.append(int(id.substr(prefix.length())))
	angles.sort()
	_stances[base] = angles
	return angles

## Draws a rotating part from its baked stances. `node` is the turning canvas
## item (rotation, and a y scale of -1 for a mirrored mount as on RoofTurret's
## barrel); `rect` is the part in that node's own space, as for the source
## draw. The nearest stance is drawn axis-aligned on whole world units of the
## parent, so the barrel steps between clean pixel-art poses. False when the
## part has no stances.
static func draw_turned(node: Node2D, source: Texture2D, region: Rect2, rect: Rect2, tint: Color = Color.WHITE) -> bool:
	var base := key(source.resource_path, region, Vector2i(rect.size.round()))
	var angles := _stance_angles(base)
	if angles.is_empty():
		missing[base] = true
		return false
	var mirrored := node.scale.y < 0.0
	# A mirrored mount shows the right-facing pose for -PI - rotation, mirrored.
	var degrees := rad_to_deg(wrapf(-PI - node.rotation if mirrored else node.rotation, -PI, PI))
	var tenths := clampi(roundi(degrees * 10.0), angles[0], angles[angles.size() - 1])
	var nearest := angles[0]
	for angle in angles:
		if absi(angle - tenths) < absi(nearest - tenths): nearest = angle
	var id := "%s|turn:%d" % [base, nearest]
	var stance := _entry_texture(id)
	if stance == null: return false
	var offset: Vector2 = Index.ENTRIES[id][2]
	var top_left := (rect.get_center().rotated(deg_to_rad(nearest / 10.0)) + offset).round()
	var axes := Transform2D(node.rotation, node.scale, 0.0, Vector2.ZERO).affine_inverse()
	if mirrored: axes = axes * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO)
	node.draw_set_transform_matrix(axes)
	node.draw_texture_rect(stance, Rect2(top_left, stance.get_size()), false, tint)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true

## Attitude of `node` in the world as an unmirrored part shows it (radians):
## a mirrored node (negative determinant) shows the right-facing pose for the
## negated turn, mirrored.
static func attitude(node: Node2D) -> float:
	var world := node.get_global_transform()
	if world.determinant() >= 0.0: return world.get_rotation()
	return -(world * Transform2D(Vector2.LEFT, Vector2.DOWN, Vector2.ZERO)).get_rotation()

## The world-texel frame of `node`: one unit per world texel, axis-aligned in
## the world (x mirrored with the node), its origin on the world texel nearest
## the node's origin, so art drawn on whole frame units lands on the world grid
## whatever the node's turn and scale. Pass it to draw_set_transform_matrix.
static func upright(node: Node2D) -> Transform2D:
	var world := node.get_global_transform()
	return world.affine_inverse() * _frame(world)

## The frame for art that itself carries the attitude `turned` (a baked
## stance, or 0 for level art): the rest of the node's attitude turns the
## frame about `pivot` (node space), as on a tilting or tumbling wreck, whose
## material then rasterises it in world-texel blocks.
static func upright_turned(node: Node2D, pivot: Vector2, turned: float) -> Transform2D:
	var world := node.get_global_transform()
	var frame := _frame(world)
	var result := world.affine_inverse() * frame
	var rest := wrapf(attitude(node) - turned, -PI, PI)
	if absf(rest) > 0.0005:
		var centre := frame.affine_inverse() * (world * pivot)
		result = result * Transform2D(rest, centre) * Transform2D(0.0, -centre)
	return result

## A point of `node` in its world-texel frame (before any rest turn).
static func upright_point(node: Node2D, local: Vector2) -> Vector2:
	var world := node.get_global_transform()
	return _frame(world).affine_inverse() * (world * local)

## Node space to its world-texel frame, for mapping many points at once.
static func to_upright(node: Node2D) -> Transform2D:
	var world := node.get_global_transform()
	return _frame(world).affine_inverse() * world

static func _frame(world: Transform2D) -> Transform2D:
	var axis := Vector2.LEFT if world.determinant() < 0.0 else Vector2.RIGHT
	return Transform2D(axis, Vector2.DOWN, world.origin.round())

## Draws a painted part that turns with its node (an aircraft hull, a walker
## chassis) from its bake at `size` world units: `rect` is where the source
## region was drawn in the node's own space. The baked stance nearest the
## node's attitude is drawn upright on whole world texels (mirrored with the
## node), never the turned or scaled source. Only beyond the baked range does
## the rest turn rigidly (see upright_turned). `shift` moves the art by whole
## world texels of that frame (presentation life such as a hull's bounce).
## False when the size was never baked.
static func draw_stance(node: Node2D, source_path: String, region: Rect2, rect: Rect2, size: Vector2i, tint: Color = Color.WHITE, shift: Vector2 = Vector2.ZERO) -> bool:
	var base := key(source_path, region, size)
	var angles := _stance_angles(base)
	var id := base
	var shown := attitude(node)
	var turned := 0.0
	if not angles.is_empty():
		var tenths := roundi(rad_to_deg(shown) * 10.0)
		var nearest := angles[0]
		for angle in angles:
			if absi(angle - tenths) < absi(nearest - tenths): nearest = angle
		id = "%s|turn:%d" % [base, nearest]
		# Inside the baked range the stance is the attitude (no rest turn).
		turned = clampf(shown, deg_to_rad(angles[0] / 10.0), deg_to_rad(angles[angles.size() - 1] / 10.0))
	var art := _entry_texture(id)
	if art == null: return false
	var centre := upright_point(node, rect.get_center())
	# A stance's offset is its top-left from the turned part's centre.
	var offset: Vector2 = Index.ENTRIES[id][2] if not angles.is_empty() else -Vector2(size) * 0.5
	node.draw_set_transform_matrix(upright_turned(node, rect.get_center(), turned))
	node.draw_texture_rect(art, Rect2((centre + offset).round() + shift.round(), art.get_size()), false, tint)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true

## Moves a counter-transform `local` (node space; its basis maps one drawn
## texel to one world unit, axis-aligned) so that its origin lands on a whole
## world texel: upright art drawn from a fractional mount (weapon pods) then
## shares the world grid with the hull it hangs on.
static func on_grid(node: Node2D, local: Transform2D) -> Transform2D:
	var world := node.get_global_transform()
	var origin := world * local.origin
	local.origin += world.affine_inverse().basis_xform(origin.round() - origin)
	return local

## The upright bake of a part at `size` (its level stance), or null.
static func level(source_path: String, region: Rect2, size: Vector2i) -> AtlasTexture:
	var base := key(source_path, region, size)
	return _entry_texture(base + "|turn:0") if not _stance_angles(base).is_empty() else _entry_texture(base)
