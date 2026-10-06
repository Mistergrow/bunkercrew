extends Node2D
## Painted undergrowth: three static meshes, one shared material, four foot
## positions and a bounded presentation tick. It has no gameplay collision.
const CATALOG := preload("res://scripts/living_ecology_catalog.gd")
const WIND_SHADER := preload("res://shaders/living_vegetation.gdshader")
const MESH_BANDS := 6
const UPDATE_HZ := 20.0
const REDUCED_HZ := 8.0
var game: Node
var presentation_weather: Node
var environment_id := "sector07"
var entries: Array[Dictionary] = []
var elapsed := 0.0
var bunker_left := 90.0
var bunker_right := 730.0
var ground_left := CATALOG.GROUND_LEFT
var ground_right := CATALOG.GROUND_RIGHT
var active_count := 0
var visible_count := 0
var tick_us := 0
var material_updates := 0
var _preview_reduced := -1
var _reduced := false
var _clock := 0.0
var _clearance_clock := 0.0
var _profile: Dictionary = {}
var _texture: Texture2D
var _shared_material: ShaderMaterial
var _batches: Array[MeshInstance2D] = []
var _full_meshes: Array[ArrayMesh] = []
var _reduced_meshes: Array[ArrayMesh] = []
var _regions: Dictionary = {}
var outskirts: Node2D

func configure(game_node: Node,environment_key: String) -> void:
	game = game_node
	environment_id = environment_key if CATALOG.PROFILES.has(environment_key) else "sector07"
	_profile = CATALOG.profile(environment_id)
	_read_bunker_bounds()
	if is_inside_tree():
		if is_instance_valid(outskirts): outskirts.configure(game,environment_id)
		_prepare()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prepare()
	outskirts = preload("res://scripts/vegetation_outskirts.gd").new()
	outskirts.name = "VegetationOutskirts"
	outskirts.configure(game,environment_id)
	add_child(outskirts)
	_update_presentation()

func _read_bunker_bounds() -> void:
	if not is_instance_valid(game): return
	var bunker = game.get("scenario_bunker")
	if is_instance_valid(bunker):
		bunker_left = float(bunker.room_left)
		bunker_right = float(bunker.room_right)
		ground_left = CATALOG.GROUND_LEFT
		ground_right = CATALOG.GROUND_RIGHT
		return
	var options = game.get("scenario_options")
	if options is Dictionary and not options.is_empty():
		bunker_left = float({"left":90.0,"center":400.0,"right":710.0}.get(str(options.get("position","left")),90.0))
		bunker_right = bunker_left+640.0
	else:
		# The classical bunker has a wider exterior header than scenario rooms.
		bunker_left = 0.0
		bunker_right = 873.0
		# Its original physical floor is finite at 75..1440, unlike scenarios.
		ground_left = 75.0
		ground_right = 1440.0

func refresh_bunker_clearance() -> void:
	var old := Vector2(bunker_left,bunker_right)
	_read_bunker_bounds()
	if old!=Vector2(bunker_left,bunker_right): _prepare()

func _prepare() -> void:
	for batch: MeshInstance2D in _batches:
		remove_child(batch)
		batch.queue_free()
	_batches.clear()
	_full_meshes.clear()
	_reduced_meshes.clear()
	_profile = CATALOG.profile(environment_id)
	_read_bunker_bounds()
	entries = CATALOG.layout(environment_id,bunker_left,bunker_right,false,ground_left,ground_right)
	_regions = CATALOG.asset_regions()
	_texture = ScenarioCatalog.texture(CATALOG.ATLAS_PATH)
	if _texture==null or _regions.is_empty():
		active_count = 0
		return
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = WIND_SHADER
	_shared_material.set_shader_parameter("wind_strength",float(_profile.wind))
	_shared_material.set_shader_parameter("habitat_tint",Color(_profile.tint))
	_shared_material.set_shader_parameter("ground_extent",Vector2(CATALOG.GROUND_LEFT,CATALOG.GROUND_RIGHT-CATALOG.GROUND_LEFT))
	for depth in 3:
		var batch := MeshInstance2D.new()
		batch.name = ["UnderstoryBehind","GroundCover","LivingGroundEdge"][depth]
		batch.z_index = [1,3,4][depth]
		batch.texture = _texture
		batch.material = _shared_material
		_full_meshes.append(_make_mesh(depth,false))
		_reduced_meshes.append(_make_mesh(depth,true))
		_batches.append(batch)
		add_child(batch)
	_reduced = reduced()
	_apply_reduced()
	_update_presentation()

func reduced() -> bool:
	if _preview_reduced>=0: return _preview_reduced==1
	if is_instance_valid(game):
		var weather = game.get("weather")
		if is_instance_valid(weather): return bool(weather.get("reduced_effects"))
	return false

func set_reduced_preview(value: int=-1) -> void:
	_preview_reduced = clampi(value,-1,1)
	_reduced = reduced()
	_apply_reduced()
	_update_presentation()

func _apply_reduced() -> void:
	active_count = 0
	for entry: Dictionary in entries:
		if _regions.has(str(entry.species)) and (not _reduced or bool(entry.reduced_visible)): active_count += 1
	for depth in _batches.size():
		_batches[depth].mesh = _reduced_meshes[depth] if _reduced else _full_meshes[depth]
		_batches[depth].visible = _batches[depth].mesh.get_surface_count()>0

func _make_mesh(depth: int,low_detail: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var texture_size := _texture.get_size()
	for entry: Dictionary in entries:
		if int(entry.depth)!=depth or (low_detail and not bool(entry.reduced_visible)): continue
		if not _regions.has(str(entry.species)): continue
		var asset: Dictionary = _regions[str(entry.species)]
		var rect: Rect2 = asset.rect
		var anchor: Vector2 = asset.root
		var size: Vector2 = entry.size
		var root_ratio := clampf((anchor.x-rect.position.x)/rect.size.x,0,1)
		var mirror := -1.0 if bool(entry.mirror) else 1.0
		var start := vertices.size()
		for band in MESH_BANDS+1:
			var v := float(band)/MESH_BANDS
			for side in 2:
				var x := (float(side)-root_ratio)*size.x*mirror
				var y := lerpf(-size.y,0.0,v)
				var point: Vector2 = Vector2(entry.position)+Vector2(x,y)
				vertices.append(Vector3(point.x,point.y,0))
				uvs.append(Vector2(lerpf(rect.position.x,rect.end.x,float(side))/texture_size.x,lerpf(rect.position.y,minf(anchor.y,rect.end.y),v)/texture_size.y))
				var packed := (float(depth)+.35+float(entry.stiffness)*.5)/3.0
				colors.append(Color(float(entry.phase)/TAU,(float(entry.position.x)-CATALOG.GROUND_LEFT)/(CATALOG.GROUND_RIGHT-CATALOG.GROUND_LEFT),1.0-v,packed))
			if band<MESH_BANDS:
				var at := start+band*2
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

func _process(delta: float) -> void:
	if get_tree().paused or not is_finite(delta) or delta<=0.0 or not is_visible_in_tree(): return
	elapsed += delta
	_clock += delta
	_clearance_clock += delta
	if _clearance_clock>=1.0:
		_clearance_clock = 0.0
		refresh_bunker_clearance()
	var next_reduced := reduced()
	if next_reduced!=_reduced:
		_reduced = next_reduced
		_apply_reduced()
		_clock = 1.0
	if _clock<1.0/(REDUCED_HZ if _reduced else UPDATE_HZ): return
	_clock = 0.0
	_update_presentation()

func _gust() -> float:
	var center := to_global(Vector2((bunker_left+bunker_right)*.5,CATALOG.GROUND_Y))
	if is_instance_valid(presentation_weather) and presentation_weather.has_method("gust_at"):
		return clampf(float(presentation_weather.gust_at(center)),0,1)
	if is_instance_valid(game):
		var weather = game.get("weather")
		if is_instance_valid(weather):
			if weather.has_method("gust_at"): return clampf(float(weather.gust_at(center)),0,1)
			if weather.has_method("wind_strength"): return clampf(float(weather.wind_strength()),0,1)
	return .2

func _actor_feet() -> PackedVector4Array:
	var result := PackedVector4Array([Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
	if _reduced or not is_instance_valid(game): return result
	var players = game.get("players")
	if not players is Array: return result
	var index := 0
	for actor in players:
		if index>=4: break
		if not is_instance_valid(actor) or not actor is Node2D: continue
		var point := to_local(actor.global_position)
		if absf(point.y-CATALOG.GROUND_Y)>32 or point.x>bunker_left-20 and point.x<bunker_right+20: continue
		result[index] = Vector4(point.x,point.y,1,0)
		index += 1
	return result

func _update_presentation() -> void:
	var started := Time.get_ticks_usec()
	if not is_instance_valid(_shared_material): return
	var bounds := get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()
	visible_count = 0
	for entry: Dictionary in entries:
		if _reduced and not bool(entry.reduced_visible): continue
		if bounds.grow(12).intersects(entry.bounds): visible_count += 1
	_shared_material.set_shader_parameter("ecology_clock",elapsed)
	var gust := _gust()
	_shared_material.set_shader_parameter("gust_strength",gust)
	_shared_material.set_shader_parameter("motion_scale",.24 if _reduced else 1.0)
	_shared_material.set_shader_parameter("nearby_actors",_actor_feet())
	if is_instance_valid(outskirts): outskirts.update_view(bounds,_reduced,elapsed,gust)
	material_updates += 4
	tick_us = Time.get_ticks_usec()-started

func diagnostics() -> Dictionary:
	return {"environment":environment_id,"biome":str(_profile.get("biome","")),"entries":entries.size(),"active_count":active_count,"visible_count":visible_count,"mesh_batches":_batches.size(),"materials":1 if is_instance_valid(_shared_material) else 0,"tick_us":tick_us,"reduced":_reduced,"elapsed":elapsed,"material_updates":material_updates,"atlas_loaded":_texture!=null and not _regions.is_empty(),"outskirts":outskirts.diagnostics() if is_instance_valid(outskirts) else {}}

func debug_stats() -> Dictionary:
	return diagnostics()
