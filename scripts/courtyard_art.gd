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
## World texels over which the open paving end ramps into the ground cover.
const PAVING_BEVEL := 9.0
## The lamp glass in the module atlas (source pixels): the window the lamp
## shader lets flicker.
const LAMP_GLASS := Rect2(260,791,42,64)
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
		lamp.centered = false
		var field_width := Catalog.FENCE_FIELD.size.x * Catalog.FENCE_HEIGHT / Catalog.FENCE.size.y
		lamp.position = Vector2(float(section.edge) + float(section.side) * (field_width + 3.0) - Catalog.module_size(Catalog.LAMP,Catalog.LAMP_HEIGHT).x * .5,float(section.ground) - Catalog.LAMP_HEIGHT)
		lamp.material = lamp_material()
		var baked := _bake(Catalog.LAMP,Catalog.LAMP_HEIGHT)
		if baked != null:
			# The lamp's bake 1:1 on whole world units; the glass window that
			# flickers follows it into the baked atlas.
			lamp.texture = baked
			lamp.position = lamp.position.round()
			var atlas_size := baked.atlas.get_size()
			var glass := Rect2(baked.region.position + (LAMP_GLASS.position - Catalog.LAMP.position) / Catalog.LAMP.size * baked.region.size,LAMP_GLASS.size / Catalog.LAMP.size * baked.region.size)
			lamp_material().set_shader_parameter("glass_rect",Vector4(glass.position.x / atlas_size.x,glass.position.y / atlas_size.y,glass.end.x / atlas_size.x,glass.end.y / atlas_size.y))
		else:
			lamp.texture = Catalog.ATLAS
			lamp.region_enabled = true
			lamp.region_rect = Catalog.LAMP
			lamp.scale = Vector2.ONE * Catalog.LAMP_HEIGHT / Catalog.LAMP.size.y
		lamp.modulate = _tint
		add_child(lamp)
		lamps.append(lamp)
	queue_redraw()

static func lamp_material() -> ShaderMaterial:
	if _lamp_material == null:
		_lamp_material = ShaderMaterial.new()
		_lamp_material.shader = LAMP_SHADER
	return _lamp_material

## Part of one paving slab that starts at slab_x: world span from..to, texel
## rows first_row..first_row+rows of its height, at its own source pitch.
func _slab(slab_x: float, slab_width: float, from: float, to: float, floor_y: float, first_row: int, rows: int) -> void:
	var pitch := Vector2(Catalog.PAVING.size.x / slab_width,Catalog.PAVING.size.y / Catalog.PAVING_HEIGHT)
	var source := Rect2(Catalog.PAVING.position + Vector2((from - slab_x) * pitch.x,float(first_row) * pitch.y),Vector2((to - from) * pitch.x,float(rows) * pitch.y))
	draw_texture_rect_region(Catalog.ATLAS,Rect2(from,floor_y - 1.0 + float(first_row),to - from,float(rows)),source,_tint)

func _module(region: Rect2, anchor: Vector2, height: float, tint: Color) -> void:
	var size := Catalog.module_size(region,height)
	draw_texture_rect_region(Catalog.ATLAS,Rect2(anchor - Vector2(0,size.y),size),region,tint)

## A module's offline bake at its drawn height (one texel per world unit,
## tools/world_density_bake.json), or null.
static func _bake(region: Rect2, height: float, atlas: Texture2D = null) -> AtlasTexture:
	var source: Texture2D = atlas if atlas != null else Catalog.ATLAS
	return WorldTexels.texture(source.resource_path,region,Vector2i(Catalog.module_size(region,height).round()))

static func _field_bake() -> AtlasTexture:
	var mesh_scale := Catalog.FENCE_HEIGHT / Catalog.FENCE.size.y
	return WorldTexels.texture(Catalog.ATLAS.resource_path,Catalog.FENCE_FIELD,Vector2i((Catalog.FENCE_FIELD.size * mesh_scale).round()))

func _draw() -> void:
	var slab := _bake(Catalog.PAVING,Catalog.PAVING_HEIGHT)
	var field := _field_bake()
	var post := _bake(Catalog.FENCE_POST,Catalog.FENCE_HEIGHT)
	var bollards := _bake(Catalog.BOLLARDS,Catalog.BOLLARD_HEIGHT)
	var case_art := _bake(Catalog.SERVICE_CASE,22.0,Catalog.SERVICE_ATLAS)
	if slab != null and field != null and post != null and bollards != null and case_art != null:
		_draw_baked(slab,field,post,bollards,case_art)
		return
	for section in sections:
		var start: float = section.start
		var end: float = section.end
		var floor_y: float = section.ground
		# The walkable surface remains at the physical floor, with the pavement
		# underside below it. Neither feet nor slabs move when the camera zooms.
		var slab_size := Catalog.module_size(Catalog.PAVING,Catalog.PAVING_HEIGHT)
		# The open end toward the approach lane steps down into the ground cover
		# one texel row at a time instead of ending in a vertical cut face.
		var outward := float(section.side)
		var exposed: float = end if outward > 0.0 else start
		var bevel := Rect2(exposed - PAVING_BEVEL if outward > 0.0 else exposed,floor_y - 1.0,PAVING_BEVEL,Catalog.PAVING_HEIGHT)
		var cursor := start
		while cursor < end:
			var width := minf(slab_size.x,end - cursor)
			var solid_from := cursor
			var solid_to := cursor + width
			if outward > 0.0: solid_to = minf(solid_to,bevel.position.x)
			else: solid_from = maxf(solid_from,bevel.end.x)
			if solid_to > solid_from: _slab(cursor,slab_size.x,solid_from,solid_to,floor_y,0,int(Catalog.PAVING_HEIGHT))
			var rows := int(Catalog.PAVING_HEIGHT)
			for row in rows:
				var reach := PAVING_BEVEL * float(row + 1) / float(rows)
				var from := bevel.position.x if outward > 0.0 else bevel.end.x - reach
				var to := bevel.position.x + reach if outward > 0.0 else bevel.end.x
				from = maxf(from,cursor)
				to = minf(to,cursor + width)
				if to > from: _slab(cursor,slab_size.x,roundf(from),roundf(to),floor_y,row,1)
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

## The court from its world-texel bakes: slabs, mesh fields, posts and
## dressing on whole world texels at their baked widths (fields and slabs step
## by whole texels; only the last of a run is cropped), so rust and mesh read
## at the crew's texel size.
func _draw_baked(slab: AtlasTexture, field: AtlasTexture, post: AtlasTexture, bollards: AtlasTexture, case_art: AtlasTexture) -> void:
	var frame := WorldTexels.to_upright(self)
	draw_set_transform_matrix(WorldTexels.upright(self))
	for section in sections:
		var start := roundf((frame * Vector2(float(section.start),0)).x)
		var end := roundf((frame * Vector2(float(section.end),0)).x)
		var floor_y := roundf((frame * Vector2(0,float(section.ground))).y)
		var outward := float(section.side)
		# The open end toward the approach lane steps down into the ground
		# cover one texel row at a time instead of a vertical cut face.
		var rows := int(slab.get_size().y)
		var cursor := start
		while cursor < end:
			var span := minf(slab.get_size().x,end - cursor)
			for row in rows:
				var reach := roundf(PAVING_BEVEL * float(row + 1) / float(rows))
				var from := cursor if outward > 0.0 else maxf(cursor,start + PAVING_BEVEL - reach)
				var to := minf(cursor + span,end - PAVING_BEVEL + reach) if outward > 0.0 else cursor + span
				if to > from: _strip(slab,Rect2(from - cursor,row,to - from,1),Vector2(from,floor_y - 1.0 + row),_tint)
			cursor += slab.get_size().x
		# Mesh and both rails share a continuous run; adjacent fields share a post.
		var mesh_scale := Catalog.FENCE_HEIGHT / Catalog.FENCE.size.y
		var field_y := floor_y - Catalog.FENCE_HEIGHT + roundf((Catalog.FENCE_FIELD.position.y - Catalog.FENCE.position.y) * mesh_scale)
		cursor = start
		var posts: Array[float] = [start]
		while cursor < end:
			var width := minf(field.get_size().x,end - cursor)
			_strip(field,Rect2(0,0,width,field.get_size().y),Vector2(cursor,field_y),_tint.darkened(.13))
			cursor += width
			posts.append(cursor)
		for post_x in posts:
			draw_texture_rect(post,Rect2(Vector2(post_x - floorf(post.get_size().x * .5),floor_y - post.get_size().y),post.get_size()),false,_tint.darkened(.08))
		var dressing_x := roundf((frame * Vector2(float(section.edge) + float(section.side) * 165.0,0)).x)
		draw_texture_rect(bollards,Rect2(Vector2(dressing_x - floorf(bollards.get_size().x * .5),floor_y - bollards.get_size().y),bollards.get_size()),false,_tint)
		var case_x := roundf((frame * Vector2(float(section.edge) + float(section.side) * 126.0,0)).x)
		draw_texture_rect(case_art,Rect2(Vector2(case_x - floorf(case_art.get_size().x * .5),floor_y - case_art.get_size().y),case_art.get_size()),false,_tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _strip(art: AtlasTexture, part: Rect2, at: Vector2, tint: Color) -> void:
	draw_texture_rect_region(art.atlas,Rect2(at,part.size),Rect2(art.region.position + part.position,part.size),tint)

func diagnostics() -> Dictionary:
	return {"fronts":sections.size(),"lamps":lamps.size(),"physics_bodies":0,"process_enabled":is_processing(),"physics_process_enabled":is_physics_processing(),"shared_materials":2,"environment":_environment}
