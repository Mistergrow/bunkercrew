class_name PickupArt
extends RefCounted
## Grounded salvage silhouettes shared by world drops and their inventory icons.

const CUTOUT_SHADER = preload("res://shaders/pickup_cutout.gdshader")
const ATLAS = preload("res://assets/loot/salvage_atlas.png")
# Tight bounds match assets/loot/source.json. Each source silhouette keeps its
# own aspect ratio; its bottom edge is the ground anchor.
const SALVAGE_REGIONS := [Rect2(70,196,385,253), Rect2(564,210,408,230), Rect2(1079,205,401,244), Rect2(53,654,411,213), Rect2(590,587,357,280), Rect2(1080,672,401,194)]
const SALVAGE_WIDTHS := [32.0, 30.0, 32.0, 28.0, 28.0, 28.0]
const INDICATOR_POINTS := [Vector2(6,-7), Vector2(-1,-7), Vector2(-2,-8)]
static var _cutout_material: ShaderMaterial


static func variant_for(kind: String, world_x: float) -> int:
	# X stays fixed while a pickup falls. Neither random state nor instance IDs
	# participate, so host and clients draw the same recovered machine part.
	return posmod(floori(world_x / 7.0) + (1 if kind == "core" else 0), 3)


static func footprint(kind: String) -> Rect2:
	if kind in ["core", "scrap"]:
		return Rect2(-17,-24,34,25)
	return Rect2(-16,-27,32,28)


static func cutout_material() -> ShaderMaterial:
	if _cutout_material == null:
		_cutout_material = ShaderMaterial.new()
		_cutout_material.shader = CUTOUT_SHADER
	return _cutout_material


static func indicator_state(age: float, variant: int) -> int:
	var phase := fposmod(age + float(variant) * 2.37, 7.4 + float(variant) * 1.3)
	if phase < 0.22 or (phase > 0.54 and phase < 0.68):
		return 2
	return 1 if phase < 1.0 else 0


static func draw_world(node: CanvasItem, kind: String, variant: int, origin: Vector2 = Vector2.ZERO, settle: int = 0, indicator: int = 0) -> void:
	var shadow_width := 30.0 if kind in ["scrap", "core"] else 22.0
	node.draw_rect(Rect2(origin + Vector2(-shadow_width * 0.5,-1),Vector2(shadow_width,2)),Color(0.035,0.05,0.045,0.35))
	if kind in ["scrap", "core"]:
		var atlas := _atlas()
		if atlas != null:
			var index := clampi(variant,0,2) + (3 if kind == "core" else 0)
			var source: Rect2 = SALVAGE_REGIONS[index]
			var width: float = SALVAGE_WIDTHS[index]
			var height := roundf(width * source.size.y / source.size.x)
			var rect := Rect2(origin + Vector2(-roundf(width * 0.5),-height + settle),Vector2(width,height - settle))
			node.draw_texture_rect_region(atlas,rect,source)
			if kind == "core":
				_draw_indicator(node,origin + INDICATOR_POINTS[clampi(variant,0,2)],indicator)
			return
	_draw_material(node,kind,origin + Vector2(0,settle))


static func draw_icon(node: CanvasItem, kind: String, at: Vector2, size: float = 32, tint: Color = Color.WHITE) -> void:
	var atlas := _atlas()
	if atlas == null or not kind in ["core", "scrap"]:
		return
	var source: Rect2 = SALVAGE_REGIONS[3 if kind == "core" else 0]
	var scale_factor := (size - 2.0) / maxf(source.size.x,source.size.y)
	var icon_size := (source.size * scale_factor).round()
	var rect := Rect2((at + (Vector2.ONE * size - icon_size) * 0.5).round(),icon_size)
	node.draw_texture_rect_region(atlas,rect,source,tint)


static func _atlas() -> Texture2D:
	return ATLAS


static func _draw_material(node: CanvasItem, kind: String, origin: Vector2) -> void:
	if ItemCatalog.draw_world(node,kind,origin): return
	# These shapes are also used for the worker's carried load and stockpile UI.
	var base_y := 11.0 if kind in ["jaw_trap", "blast_trap", "sentry_kit"] else (12.0 if kind == "tungsten" else 13.0)
	MaterialArt.draw_material(node,kind,origin - Vector2(0,base_y))


static func _draw_indicator(node: CanvasItem, at: Vector2, state: int) -> void:
	var lamp_color := Color("776343") if state == 0 else (Color("b78b47") if state == 1 else Color("e0b46d"))
	node.draw_rect(Rect2(at.round(),Vector2(2,1)),lamp_color)
