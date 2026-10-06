extends Node2D
## Camera-visible, world-anchored growth on the existing cosmetic terrain.
## Chunk changes rebuild at most nine shared surfaces, never actor collisions.
const CATALOG := preload("res://scripts/living_ecology_catalog.gd")
const TREE_CATALOG := preload("res://scripts/scenario_prop_catalog.gd")
const WIND_SHADER := preload("res://shaders/living_vegetation.gdshader")
const STRATA := preload("res://scripts/terrain_strata.gd")
const BANDS := 6
const VIEW_PADDING := 420.0
var environment_id := "sector07"
var landscape: Array[Rect2] = []
var occupied := Vector2(CATALOG.GROUND_LEFT,CATALOG.GROUND_RIGHT)
var plants: Array[Dictionary] = []
var trees: Array[Dictionary] = []
var rebuilds := 0
var tick_us := 0
var _span := Vector2i(0,-1)
var _reduced := false
var _batches: Array[MeshInstance2D] = []
var _full_meshes: Array[ArrayMesh] = []
var _reduced_meshes: Array[ArrayMesh] = []
var _materials: Array[ShaderMaterial] = []
var _textures: Dictionary = {}
var _ground_material: ShaderMaterial
var _tree_material: ShaderMaterial
var _last_clock := -1.0
var _last_gust := -1.0

func configure(game: Node,id: String) -> void:
	environment_id = id
	landscape.clear()
	_span = Vector2i(0,-1)
	_ground_material = null
	_tree_material = null
	_materials.clear()
	_textures.clear()
	_last_clock = -1.0
	_last_gust = -1.0
	# Reconfiguration may also turn a live level into a panorama-only preview.
	_rebuild()
	if not is_instance_valid(game): return
	var bunker = game.get("scenario_bunker")
	if is_instance_valid(bunker):
		landscape.append(Rect2(STRATA.FIELD.position.x,CATALOG.GROUND_Y,STRATA.FIELD.size.x,1.0))
		occupied = Vector2(CATALOG.GROUND_LEFT,CATALOG.GROUND_RIGHT)
	else:
		# The classic western hillside has a different, visibly drawn elevation.
		# Its eastern road is drawn to x2400, although actors stop at x1440.
		landscape.append(Rect2(-960.0,245.0,930.0,1.0))
		landscape.append(Rect2(1440.0,CATALOG.GROUND_Y,960.0,1.0))
		occupied = Vector2(0.0,1440.0)

func update_view(rect: Rect2,reduced: bool,clock: float,gust: float) -> void:
	if landscape.is_empty(): return
	var started := Time.get_ticks_usec()
	var left := landscape[0].position.x
	var right := landscape[-1].end.x
	var span := Vector2i(0,-1)
	if rect.end.x>left and rect.position.x<right and _vertical_overlap(rect):
		span.x = floori(maxf(left,rect.position.x-VIEW_PADDING)/CATALOG.OUTSKIRT_CHUNK_WIDTH)
		span.y = floori(minf(right-1.0,rect.end.x+VIEW_PADDING)/CATALOG.OUTSKIRT_CHUNK_WIDTH)
		span.y = mini(span.y,span.x+CATALOG.MAX_OUTSKIRT_CHUNKS-1)
	if span!=_span:
		_span = span
		_rebuild()
	var presentation_changed := _reduced!=reduced
	if presentation_changed:
		_reduced = reduced
		_apply_reduced()
	if clock!=_last_clock or gust!=_last_gust or presentation_changed:
		_last_clock = clock
		_last_gust = gust
		for wind_material: ShaderMaterial in _materials:
			wind_material.set_shader_parameter("ecology_clock",clock)
			wind_material.set_shader_parameter("gust_strength",gust)
			wind_material.set_shader_parameter("motion_scale",.24 if reduced else 1.0)
	tick_us = Time.get_ticks_usec()-started

func _vertical_overlap(rect: Rect2) -> bool:
	for slab: Rect2 in landscape:
		if rect.position.y<slab.position.y+12.0 and rect.end.y>slab.position.y-CATALOG.MAX_OUTSKIRT_HEIGHT-12.0: return true
	return false

func _rebuild() -> void:
	for batch: MeshInstance2D in _batches:
		remove_child(batch)
		batch.queue_free()
	_batches.clear()
	_full_meshes.clear()
	_reduced_meshes.clear()
	if _span.y<_span.x:
		plants.clear()
		trees.clear()
		return
	var layout := CATALOG.outskirts_layout(environment_id,_span,landscape,occupied)
	plants.assign(layout.plants)
	trees.assign(layout.trees)
	_prepare_materials()
	var atlas := ScenarioCatalog.texture(CATALOG.ATLAS_PATH)
	var regions := CATALOG.asset_regions()
	for depth in 3:
		var members: Array[Dictionary] = []
		for plant: Dictionary in plants:
			if int(plant.depth)==depth: members.append(plant)
		_add_batch("OutskirtsGround%d"%depth,atlas,_ground_material,members,regions,[1,3,4][depth])
	var kinds: Array[String] = []
	for kind: String in TREE_CATALOG.TREE_MIX.get(environment_id,TREE_CATALOG.TREE_MIX.sector07):
		if kind not in kinds: kinds.append(kind)
	for depth in 2:
		for kind: String in kinds:
			var members: Array[Dictionary] = []
			for tree: Dictionary in trees:
				if str(tree.species)==kind and int(tree.depth)==depth: members.append(tree)
			if members.is_empty(): continue
			if not _textures.has(kind): _textures[kind] = ScenarioCatalog.texture(str(TREE_CATALOG.TREE_PATHS[kind]))
			var tree_regions := {kind:{"rect":Rect2(TREE_CATALOG.TREE_REGIONS[kind]),"root":TREE_CATALOG.TREE_ROOTS[kind]}}
			_add_batch("OutskirtsTree_%s_%d"%[kind,depth],_textures[kind],_tree_material,members,tree_regions,1+depth)
	_apply_reduced()
	rebuilds += 1

func _prepare_materials() -> void:
	if is_instance_valid(_ground_material): return
	var habitat := CATALOG.profile(environment_id)
	for tint: Color in [Color(habitat.tint),Color(TREE_CATALOG.profile(environment_id).tree_tint)]:
		var wind_material := ShaderMaterial.new()
		wind_material.shader = WIND_SHADER
		wind_material.set_shader_parameter("wind_strength",float(habitat.wind))
		wind_material.set_shader_parameter("habitat_tint",tint)
		wind_material.set_shader_parameter("ground_extent",Vector2(STRATA.FIELD.position.x,STRATA.FIELD.size.x))
		wind_material.set_shader_parameter("nearby_actors",PackedVector4Array([Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO]))
		_materials.append(wind_material)
	_ground_material = _materials[0]
	_tree_material = _materials[1]

func _add_batch(label: String,texture: Texture2D,wind_material: ShaderMaterial,members: Array[Dictionary],regions: Dictionary,depth: int) -> void:
	if texture==null or members.is_empty(): return
	var batch := MeshInstance2D.new()
	batch.name = label
	batch.z_index = depth
	batch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	batch.texture = texture
	batch.material = wind_material
	_full_meshes.append(_make_mesh(members,regions,texture.get_size(),false))
	_reduced_meshes.append(_make_mesh(members,regions,texture.get_size(),true))
	_batches.append(batch)
	add_child(batch)

func _make_mesh(members: Array[Dictionary],regions: Dictionary,texture_size: Vector2,reduced: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for entry: Dictionary in members:
		if reduced and not bool(entry.reduced_visible): continue
		if not regions.has(str(entry.species)): continue
		var region: Dictionary = regions[str(entry.species)]
		var rect: Rect2 = region.rect
		var anchor: Vector2 = region.root
		var size: Vector2 = entry.size
		var root_ratio := (anchor.x-rect.position.x)/rect.size.x
		var mirror := -1.0 if bool(entry.mirror) else 1.0
		var first := vertices.size()
		for band in BANDS+1:
			var fraction := float(band)/BANDS
			for side in 2:
				var point := Vector2(entry.position)+Vector2((float(side)-root_ratio)*size.x*mirror,lerpf(-size.y,0,fraction))
				vertices.append(Vector3(point.x,point.y,0))
				uvs.append(Vector2(lerpf(rect.position.x,rect.end.x,float(side))/texture_size.x,lerpf(rect.position.y,minf(anchor.y,rect.end.y),fraction)/texture_size.y))
				var packed := (float(entry.depth)+.35+float(entry.stiffness)*.5)/3.0
				colors.append(Color(float(entry.phase)/TAU,(float(entry.position.x)-STRATA.FIELD.position.x)/STRATA.FIELD.size.x,1.0-fraction,packed))
			if band<BANDS:
				var at := first+band*2
				indices.append_array(PackedInt32Array([at,at+1,at+2,at+1,at+3,at+2]))
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _apply_reduced() -> void:
	for index in _batches.size():
		var mesh := _reduced_meshes[index] if _reduced else _full_meshes[index]
		_batches[index].mesh = mesh
		_batches[index].visible = mesh.get_surface_count()>0

func diagnostics() -> Dictionary:
	var active_plants := 0
	var active_trees := 0
	for plant: Dictionary in plants:
		if not _reduced or bool(plant.reduced_visible): active_plants += 1
	for tree: Dictionary in trees:
		if not _reduced or bool(tree.reduced_visible): active_trees += 1
	return {"plants":plants.size(),"trees":trees.size(),"active_plants":active_plants,"active_trees":active_trees,"mesh_batches":_batches.size(),"materials":_materials.size(),"rebuilds":rebuilds,"tick_us":tick_us,"chunk_first":_span.x,"chunk_last":_span.y,"reduced":_reduced,"cosmetic":true}
