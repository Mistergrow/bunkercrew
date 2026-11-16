class_name MachineryArt
extends RefCounted
## Independently replaceable atlas modules. Physics and production never depend
## on these texture bounds. Source prompts and regions are kept with the assets.
const ATLAS = preload("res://assets/machinery/components.png")
const REGIONS := {
	"mixer_frame":Rect2(55,198,476,315),
	"mixer_drum":Rect2(609,191,322,282),
	"furnace":Rect2(1021,73,480,431),
	"barrel":Rect2(63,667,549,198),
	"mount":Rect2(583,665,411,279),
	"core":Rect2(1076,556,360,401),
}
static var textures: Dictionary = {}

static func texture(part: String) -> AtlasTexture:
	if not textures.has(part):
		var result := AtlasTexture.new()
		result.atlas = ATLAS
		result.region = REGIONS[part]
		result.filter_clip = true
		textures[part] = result
	return textures[part]

## Corners of a region that hold a neighbouring module's pixels: the barrel's
## muzzle brake reaches into the mount's upper left corner (atlas x 583-609,
## y 732-771) and floated beside every roof gun as a stray dark block.
const FOREIGN := {"mount":Rect2(583,665,27,107)}

## The part as drawn at `size` world units: its world-texel bake (the
## FOREIGN corner is already cleared in it), else the source region.
static func world_texture(part: String, size: Vector2i) -> Texture2D:
	var baked := WorldTexels.texture(ATLAS.resource_path, REGIONS[part], size)
	return baked if baked != null else texture(part)

static func paint(node: CanvasItem, part: String, rect: Rect2, tint: Color=Color.WHITE) -> void:
	# One texel per world unit (tools/bake_world_density_art.py); the source
	# below is only the fallback for a draw size without a bake.
	if WorldTexels.draw_region(node, ATLAS, REGIONS[part], rect, tint):
		return
	if not FOREIGN.has(part):
		node.draw_texture_rect(texture(part),rect,false,tint)
		return
	# Drawn as two bands that leave the foreign corner out: the band beside it,
	# then the full width below it, mapped onto `rect` at the same scale.
	var region: Rect2 = REGIONS[part]
	var foreign: Rect2 = FOREIGN[part]
	var scale_factor := rect.size/region.size
	for source: Rect2 in [Rect2(foreign.end.x,region.position.y,region.end.x-foreign.end.x,foreign.end.y-region.position.y),Rect2(region.position.x,foreign.end.y,region.size.x,region.end.y-foreign.end.y)]:
		node.draw_texture_rect_region(ATLAS,Rect2(rect.position+(source.position-region.position)*scale_factor,source.size*scale_factor),source,tint)

## A turning part (gun barrel) from its baked stances on whole world units;
## `node` carries the aim rotation. Falls back to the rotated source region.
static func paint_turned(node: Node2D, part: String, rect: Rect2, tint: Color=Color.WHITE) -> void:
	if not WorldTexels.draw_turned(node, ATLAS, REGIONS[part], rect, tint):
		paint(node, part, rect, tint)
