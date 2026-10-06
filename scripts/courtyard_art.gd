extends Node2D
## A service court behind the playable approach lane. Fixed modules draw once;
## the lamp's small intensity variation needs no process or physics callback.
const Catalog = preload("res://scripts/courtyard_art_catalog.gd")
const PerimeterArt = preload("res://scripts/perimeter_art.gd")
const LAMP_SHADER = preload("res://shaders/courtyard_lamp.gdshader")
var controller: Node2D
var sections: Array[Dictionary] = []
var lamps: Array[Sprite2D] = []
var _environment := "sector07"
var _tint := Color.WHITE
static var _lamp_material: ShaderMaterial

func configure(perimeter_controller: Node2D) -> void:
	controller = perimeter_controller
	name = "ServiceCourtyard"
	if is_instance_valid(controller.game) and "scenario_options" in controller.game:
		_environment = str(controller.game.scenario_options.get("environment","sector07"))
	_tint = Catalog.habitat_tint(_environment)
	sections.clear()
	for site in controller.sites:
		if site.role != "fence": continue
		var edge: float = controller.layout.bunker_right if site.side > 0 else controller.layout.bunker_left
		var front: float = site.position.x
		# The rear fence joins the bunker at one end and overlaps the fixed
		# outer gate's heel at the other. No unguarded end gaps are left.
		var start: float = edge if site.side > 0 else front + 13.0
		var end: float = front - 13.0 if site.side > 0 else edge
		if end <= start: continue
		sections.append({"side":site.side,"edge":edge,"front":front,"start":start,"end":end,"ground":controller.layout.ground_y})

func _ready() -> void:
	z_index = -4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = PerimeterArt.pixel_material()
	for section in sections:
		var lamp := Sprite2D.new()
		lamp.name = "EastWorkLamp" if int(section.side) > 0 else "WestWorkLamp"
		lamp.texture = Catalog.ATLAS
		lamp.region_enabled = true
		lamp.region_rect = Catalog.LAMP
		lamp.centered = false
		lamp.scale = Vector2.ONE * Catalog.LAMP_HEIGHT / Catalog.LAMP.size.y
		var field_width := Catalog.FENCE_FIELD.size.x * Catalog.FENCE_HEIGHT / Catalog.FENCE.size.y
		lamp.position = Vector2(float(section.edge) + float(section.side) * (field_width + 3.0) - Catalog.module_size(Catalog.LAMP,Catalog.LAMP_HEIGHT).x * .5,float(section.ground) - Catalog.LAMP_HEIGHT)
		lamp.modulate = _tint
		lamp.material = lamp_material()
		add_child(lamp)
		lamps.append(lamp)
	queue_redraw()

static func lamp_material() -> ShaderMaterial:
	if _lamp_material == null:
		_lamp_material = ShaderMaterial.new()
		_lamp_material.shader = LAMP_SHADER
	return _lamp_material

func _module(region: Rect2, anchor: Vector2, height: float, tint: Color) -> void:
	var size := Catalog.module_size(region,height)
	draw_texture_rect_region(Catalog.ATLAS,Rect2(anchor - Vector2(0,size.y),size),region,tint)

func _draw() -> void:
	for section in sections:
		var start: float = section.start
		var end: float = section.end
		var floor_y: float = section.ground
		# The walkable surface remains at the physical floor, with the pavement
		# underside below it. Neither feet nor slabs move when the camera zooms.
		var slab_size := Catalog.module_size(Catalog.PAVING,Catalog.PAVING_HEIGHT)
		var cursor := start
		while cursor < end:
			var width := minf(slab_size.x,end - cursor)
			var source := Rect2(Catalog.PAVING.position,Vector2(Catalog.PAVING.size.x * width / slab_size.x,Catalog.PAVING.size.y))
			draw_texture_rect_region(Catalog.ATLAS,Rect2(cursor,floor_y - 1.0,width,Catalog.PAVING_HEIGHT),source,_tint)
			cursor += slab_size.x
		# Mesh and both rails share a continuous run. Only the last field is
		# cropped; pixel pitch stays fixed and adjacent fields share one post.
		# This avoids the gaps and paired posts of repeated standalone panels.
		var mesh_scale := Catalog.FENCE_HEIGHT / Catalog.FENCE.size.y
		var field_size := Catalog.FENCE_FIELD.size * mesh_scale
		var field_y := floor_y - Catalog.FENCE_HEIGHT + (Catalog.FENCE_FIELD.position.y - Catalog.FENCE.position.y) * mesh_scale
		cursor = start
		var posts: Array[float] = [start]
		while cursor < end:
			var width := minf(field_size.x,end - cursor)
			var field_source := Rect2(Catalog.FENCE_FIELD.position,Vector2(width / mesh_scale,Catalog.FENCE_FIELD.size.y))
			draw_texture_rect_region(Catalog.ATLAS,Rect2(cursor,field_y,width,field_size.y),field_source,_tint.darkened(.13))
			cursor += width
			posts.append(cursor)
		var post_width := Catalog.FENCE_POST.size.x * mesh_scale
		for post_x in posts:
			_module(Catalog.FENCE_POST,Vector2(post_x - post_width * .5,floor_y),Catalog.FENCE_HEIGHT,_tint.darkened(.08))
		var dressing_x: float = float(section.edge) + float(section.side) * 165.0
		var dressing_size := Catalog.module_size(Catalog.BOLLARDS,Catalog.BOLLARD_HEIGHT)
		_module(Catalog.BOLLARDS,Vector2(dressing_x - dressing_size.x * .5,floor_y),Catalog.BOLLARD_HEIGHT,_tint)
		# A closed service case and cable station make the inner court read as
		# a maintained work area. They are stored equipment, not resource piles.
		var case_size := Catalog.module_size(Catalog.SERVICE_CASE,22.0)
		var case_x: float = float(section.edge) + float(section.side) * 126.0
		draw_texture_rect_region(Catalog.SERVICE_ATLAS,Rect2(Vector2(case_x - case_size.x * .5,floor_y - case_size.y),case_size),Catalog.SERVICE_CASE,_tint)

func diagnostics() -> Dictionary:
	return {"fronts":sections.size(),"lamps":lamps.size(),"physics_bodies":0,"process_enabled":is_processing(),"physics_process_enabled":is_physics_processing(),"shared_materials":2,"environment":_environment}
