extends Node2D
## Local painted emitters and sky-only light shafts. No screen readback.
const EMISSION := preload("res://shaders/scenario_emission.gdshader")
const SHAFTS := preload("res://shaders/scenario_light_shafts.gdshader")
const SKYLINE := preload("res://scripts/cloud_skyline.gd")
const SHAFT_LAYOUTS := {
	"abandoned_harbor":[Vector4(.16,.035,.32,.50),Color(.42,.65,.76,.085)],
	"basalt_quarry":[Vector4(.22,.02,.44,.58),Color(.89,.64,.36,.085)],
	"overgrown_steelworks":[Vector4(.39,.005,.38,.57),Color(.89,.83,.51,.10)],
	"flooded_power_station":[Vector4(.48,.01,.32,.48),Color(.64,.77,.63,.085)],
}
var scenery: Node2D
var emission_nodes: Array[Sprite2D] = []
var emission_materials: Array[ShaderMaterial] = []
var shaft_layer: Node2D
var shaft_material: ShaderMaterial
var _shaft_rect := Rect2()
var _shaft_color := Color.WHITE
var _geometry_bounds := Rect2()
var _last_tick := -1
var _last_reduced := false
var _last_edge_fade := -1.0
var uniform_updates := 0
var edge_uniform_updates := 0
var effects_enabled := true:
	set(value):
		if effects_enabled==value: return
		effects_enabled = value
		_last_tick = -1
		visible = value and (not is_instance_valid(scenery) or not scenery.reduced())

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var texture: Texture2D = scenery.panorama.texture
	if texture==null: return
	var bounds: Rect2 = scenery.panorama_rect
	var source_size := texture.get_size()
	for anchor: Array in scenery.data.get("light_anchors",[]):
		var center := Vector2(float(anchor[0]),float(anchor[1]))
		var radius := Vector2(25,22)/bounds.size
		var region := Rect2((center-radius)*source_size,radius*source_size*2).intersection(Rect2(Vector2.ZERO,source_size))
		var emitter := Sprite2D.new()
		emitter.name = "PaintedEmitter%d"%emission_nodes.size()
		emitter.texture = texture
		emitter.region_enabled = true
		emitter.region_rect = region
		emitter.centered = false
		emitter.position = bounds.position+region.position/source_size*bounds.size
		emitter.scale = bounds.size/source_size
		var glow := ShaderMaterial.new()
		glow.shader = EMISSION
		glow.set_shader_parameter("source_center",center)
		glow.set_shader_parameter("source_radius",radius)
		glow.set_shader_parameter("phase",emission_nodes.size()*2.37)
		glow.set_shader_parameter("allow_white",scenery.environment_id=="abandoned_harbor")
		glow.set_shader_parameter("strength",.44 if scenery.environment_id=="ash_foundry" else .32)
		emitter.material = glow
		add_child(emitter)
		emission_nodes.append(emitter)
		emission_materials.append(glow)
	if SHAFT_LAYOUTS.has(scenery.environment_id):
		var layout: Array = SHAFT_LAYOUTS[scenery.environment_id]
		var placement: Vector4 = layout[0]
		var size := Vector2(placement.z,placement.w)*bounds.size
		_shaft_rect = Rect2(bounds.position+Vector2(placement.x,placement.y)*bounds.size-Vector2(size.x*.34,0),size)
		_shaft_color = layout[1]
		shaft_layer = Node2D.new()
		shaft_layer.name = "FilteredSkyLight"
		shaft_material = ShaderMaterial.new()
		shaft_material.shader = SHAFTS
		shaft_material.set_shader_parameter("sky_mask",SKYLINE.texture(scenery.environment_id))
		shaft_material.set_shader_parameter("panorama_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		shaft_layer.material = shaft_material
		shaft_layer.draw.connect(_draw_shaft)
		add_child(shaft_layer)
		move_child(shaft_layer,0)
	set_edge_fade(float(scenery.sky_material.get_shader_parameter("edge_fade")))
	update_lighting(float(scenery.elapsed),scenery.reduced())

func sync_geometry() -> void:
	var bounds: Rect2 = scenery.panorama_rect
	if bounds == _geometry_bounds: return
	_geometry_bounds = bounds
	var source_size: Vector2 = scenery.panorama.texture.get_size()
	for emitter in emission_nodes:
		emitter.position = bounds.position + emitter.region_rect.position/source_size*bounds.size
		emitter.scale = bounds.size/source_size
	if is_instance_valid(shaft_layer):
		var placement: Vector4 = SHAFT_LAYOUTS[scenery.environment_id][0]
		var size := Vector2(placement.z,placement.w)*bounds.size
		_shaft_rect = Rect2(bounds.position+Vector2(placement.x,placement.y)*bounds.size-Vector2(size.x*.34,0),size)
		shaft_material.set_shader_parameter("panorama_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
		shaft_layer.queue_redraw()

func update_lighting(seconds: float,reduced: bool) -> void:
	sync_geometry()
	visible = effects_enabled and not reduced
	if not visible:
		_last_reduced = true
		return
	var tick := floori(seconds*12.0)
	var clock_changed := tick != _last_tick or _last_reduced
	_last_tick = tick
	_last_reduced = false
	var view := get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()
	for index in emission_nodes.size():
		var emitter := emission_nodes[index]
		var rect := Rect2(emitter.position,emitter.region_rect.size*emitter.scale)
		emitter.visible = rect.intersects(view)
		if emitter.visible and clock_changed:
			emission_materials[index].set_shader_parameter("light_clock",tick/12.0)
			uniform_updates += 1
	if is_instance_valid(shaft_layer):
		shaft_layer.visible = _shaft_rect.intersects(view)
		if shaft_layer.visible and clock_changed:
			shaft_material.set_shader_parameter("light_clock",tick/12.0)
			uniform_updates += 1

func set_edge_fade(value: float) -> void:
	if is_equal_approx(value, _last_edge_fade):
		return
	_last_edge_fade = value
	for emission_material in emission_materials:
		emission_material.set_shader_parameter("edge_fade", value)
		edge_uniform_updates += 1
	if is_instance_valid(shaft_material):
		shaft_material.set_shader_parameter("edge_fade", value)
		edge_uniform_updates += 1

func _draw_shaft() -> void:
	var at := _shaft_rect.position
	var size := _shaft_rect.size
	shaft_layer.draw_polygon(PackedVector2Array([at,at+Vector2(size.x,0),at+size,at+Vector2(0,size.y)]),
		PackedColorArray([_shaft_color,_shaft_color,_shaft_color,_shaft_color]),
		PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]))
