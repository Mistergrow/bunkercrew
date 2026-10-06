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

static func paint(node: CanvasItem, part: String, rect: Rect2, tint: Color=Color.WHITE) -> void:
	node.draw_texture_rect(texture(part),rect,false,tint)
