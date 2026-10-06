extends Node2D
## World-anchored winter outskirts extend the unique station at wide zoom.
const PATHS := ["res://assets/environments/frozen_rail_outskirts_v1.png", "res://assets/environments/frozen_vegetation_v1.png"]
const REGIONS := [Rect2(0,125,2172,525), Rect2(0,125,2172,515)]
const WIDTHS := [1700.0,850.0]
const OFFSETS := [-640.0,110.0]
const MAX_BLOCKS := 20
const BASELINE := 430.0
const EDGE_SHADER := preload("res://shaders/frozen_outskirts.gdshader")
var layers: Array[Node2D] = []
var textures: Array[Texture2D] = []
var spans: Array[Vector2i] = []
var enabled := false

func configure(scenery: Node) -> void:
	enabled = scenery.environment_id == "frozen_rail_yard"
	if not enabled: return
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shader := EDGE_SHADER
	for depth in 2:
		textures.append(load(PATHS[depth]) as Texture2D)
		var layer := Node2D.new()
		layer.name = "RailOutskirts" if depth == 0 else "WinterUndergrowth"
		layer.z_index = 0 if depth == 0 else 1
		var blend := ShaderMaterial.new()
		blend.shader = shader
		blend.set_shader_parameter("foreground",depth == 1)
		var left: float = scenery.panorama_rect.position.x+scenery.panorama_rect.size.x*.16
		var right: float = scenery.panorama_rect.end.x-scenery.panorama_rect.size.x*.16
		if is_instance_valid(scenery.game) and is_instance_valid(scenery.game.get("scenario_bunker")):
			left = minf(left,scenery.game.scenario_bunker.room_left-80.0)
			right = maxf(right,scenery.game.scenario_bunker.room_right+80.0)
		blend.set_shader_parameter("clear_left",left)
		blend.set_shader_parameter("clear_right",right)
		layer.material = blend
		layer.draw.connect(_draw_depth.bind(layer,depth))
		add_child(layer)
		layers.append(layer)

func block_rect(depth: int,index: int) -> Rect2:
	var width: float = WIDTHS[depth]
	var height: float = width*REGIONS[depth].size.y/REGIONS[depth].size.x
	return Rect2(roundf(index*width*.78+OFFSETS[depth]),BASELINE-height,width,height)

func visible_blocks(depth: int,rect: Rect2) -> Vector2i:
	var sample := block_rect(depth,0)
	if rect.end.y<sample.position.y or rect.position.y>BASELINE: return Vector2i(0,-1)
	var period: float = WIDTHS[depth]*.78
	var first := floori((rect.position.x-OFFSETS[depth]-WIDTHS[depth])/period)+1
	var last := floori((rect.end.x-OFFSETS[depth])/period)
	return Vector2i(first,mini(last,first+MAX_BLOCKS-1))

func update_view(rect: Rect2) -> void:
	if not enabled: return
	var next: Array[Vector2i] = [visible_blocks(0,rect),visible_blocks(1,rect)]
	if next == spans: return
	spans = next
	for layer in layers: layer.queue_redraw()

func _draw_depth(layer: Node2D,depth: int) -> void:
	if spans.size()!=2 or textures[depth]==null: return
	var span := spans[depth]
	for index in range(span.x,span.y+1):
		var destination := block_rect(depth,index)
		var mirrored := posmod(index+depth,2)==1
		var origin := destination.position+Vector2(destination.size.x if mirrored else 0.0,0)
		layer.draw_set_transform(origin,0,Vector2(-1 if mirrored else 1,1))
		layer.draw_texture_rect_region(textures[depth],Rect2(Vector2.ZERO,destination.size),REGIONS[depth])
	layer.draw_set_transform(Vector2.ZERO)
