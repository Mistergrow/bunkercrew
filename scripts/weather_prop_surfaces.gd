class_name WeatherPropSurfaces
extends Node2D
## Weather-only outlines of visible equipment. They never change gameplay
## collision. Transparent atlas padding cannot become an invisible rain roof.
var game: Node
var weather: Node
var _frame := -1
var _segments: Array[Dictionary] = []
var _contours: Dictionary = {}
var _polygon_cache: Dictionary = {}
var _polygon_slots: Dictionary = {}
var _collecting := false
var _geometry_generation := 0
var geometry_builds := 0
var geometry_reuses := 0
const SAMPLES := 10
const ALPHA_THRESHOLD := 0.42
const DefenseArt := preload("res://scripts/defense_structure_art.gd")

func rain_segments() -> Array[Dictionary]:
	var frame := Engine.get_process_frames()
	if frame==_frame: return _segments
	_frame = frame
	_segments.clear()
	if not is_inside_tree(): return _segments
	_polygon_slots.clear()
	_collecting = true
	_geometry_generation += 1
	for prop in get_tree().get_nodes_in_group("level_props"):
		if not prop is LevelProp or not _eligible(prop) or not is_instance_valid(prop.artwork): continue
		if prop.global_position.y>450: continue
		var artwork: Sprite2D = prop.artwork
		var texture: Texture2D = artwork.texture
		var surface_material := "wood" if prop.kind_index in [LevelProp.Kind.CRATE,LevelProp.Kind.MINE_BRACE] else ("cloth" if prop.kind_index in [LevelProp.Kind.CEMENT_SACKS,LevelProp.Kind.FLAG] else "metal")
		var rect := Rect2(-texture.get_size()*0.5,texture.get_size())
		_add_texture(artwork,texture,rect,prop,surface_material,artwork.flip_h)
	for supply in get_tree().get_nodes_in_group("supplies"):
		if not _eligible(supply) or supply.global_position.y>450: continue
		_add_polygon(supply,PackedVector2Array([Vector2(-29,-38),Vector2(29,-38),Vector2(29,-1),Vector2(-29,-1)]),supply,"wood")
	for station in get_tree().get_nodes_in_group("flak_stations"):
		if not _eligible(station): continue
		_add_texture(station,DefenseArt.CONSOLE,DefenseArt.FLAK_CONSOLE_BOUNDS,station,"metal")
		_add_polygon(station,PackedVector2Array([Vector2(-25,-9),Vector2(25,-9),Vector2(25,-1),Vector2(-25,-1)]),station,"metal")
	for gun in get_tree().get_nodes_in_group("turrets"):
		if not gun is RoofTurret or not _eligible(gun): continue
		var flak := gun is FlakTurret
		_add_texture(gun,MachineryArt.texture("mount"),Rect2(-33,-46,68,46) if flak else Rect2(-32,-44,65,44),gun,"metal")
		if not is_instance_valid(gun.barrel): continue
		if flak:
			for index in 2:
				var kick: float = gun.recoil if gun.flash_tick%2==index else gun.recoil*0.4
				_add_texture(gun.barrel,MachineryArt.texture("barrel"),Rect2(-20-kick,-17+index*14,84,23),gun,"metal")
		else:
			_add_texture(gun.barrel,MachineryArt.texture("barrel"),Rect2(-25-gun.recoil,-16,95,34),gun,"metal")
	for device in get_tree().get_nodes_in_group("field_defenses"):
		if device is FieldDefense and _eligible(device) and device.kind!="sentry_kit" and not device.spent:
			_add_polygon(device,PackedVector2Array([Vector2(-23,-5),Vector2(-12,-12),Vector2(12,-12),Vector2(23,-5),Vector2(23,0),Vector2(-23,0)]),device,"metal")
	_add_roof_flag()
	_collecting = false
	# Only the current world's visible surfaces retain entries. A deleted or
	# hidden prop cannot leave a stale silhouette or grow a session-long cache.
	for id: int in _polygon_cache.keys():
		if int(_polygon_cache[id].generation) != _geometry_generation:
			_polygon_cache.erase(id)
		else:
			_polygon_cache[id].slots.resize(int(_polygon_slots[id]))
	return _segments

func _eligible(item) -> bool:
	if not is_instance_valid(item) or not item is Node2D or item.is_queued_for_deletion() or not item.is_visible_in_tree(): return false
	if item.get_world_2d()!=get_world_2d(): return false
	if not is_instance_valid(game): return true
	return game.is_ancestor_of(item) and (not "game" in item or item.get("game")==game)

func _add_roof_flag() -> void:
	if not is_instance_valid(weather) or not weather is Node2D: return
	if weather.has_method("roof_flag_visible") and not weather.roof_flag_visible(): return
	# Identical articulated cloth panels to ShiftWeather._draw_wind().
	# This small decorative flag has no gameplay collider.
	var offset: Vector2 = weather.flag_offset()
	for panel in 5:
		var corners: PackedVector2Array = weather.flag_panel(panel)
		for index in corners.size(): corners[index] += offset
		_add_polygon(weather,corners,weather,"cloth")
	_add_polygon(weather,PackedVector2Array([Vector2(108,174)+offset,Vector2(112,174)+offset,Vector2(112,244)+offset,Vector2(108,244)+offset]),weather,"metal")

func invalidate() -> void:
	_frame = -1

func _outline(texture: Texture2D) -> PackedVector2Array:
	var id := texture.get_rid().get_id()
	if _contours.has(id): return _contours[id]
	var image := texture.get_image()
	var outline := PackedVector2Array()
	if image==null or image.is_empty(): return outline
	if image.is_compressed(): image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	# Each narrow column picks a real opaque pixel. No image file is changed.
	for index in SAMPLES+1:
		var x := clampi(roundi(float(index)*(width-1)/SAMPLES),0,width-1)
		var first := -1
		var last := -1
		for y in height:
			if image.get_pixel(x,y).a>=ALPHA_THRESHOLD:
				if first<0: first=y
				last=y
		if first>=0:
			top.append(Vector2(float(x)/width,float(first)/height))
			bottom.append(Vector2(float(x)/width,float(last+1)/height))
	outline.append_array(top)
	bottom.reverse()
	outline.append_array(bottom)
	_contours[id] = outline
	return outline

func _add_texture(node: Node2D, texture: Texture2D, rect: Rect2, collider: Node2D, surface_material: String, flip: bool=false) -> void:
	var points := PackedVector2Array()
	for uv: Vector2 in _outline(texture):
		points.append(rect.position+Vector2(1-uv.x if flip else uv.x,uv.y)*rect.size)
	if flip: points.reverse()
	_add_polygon(node,points,collider,surface_material)

func _add_polygon(node: Node2D, polygon: PackedVector2Array, collider: Node2D, surface_material: String) -> void:
	if polygon.size()<3: return
	var cached: Dictionary = {}
	var slot := 0
	var prop_transform := node.global_transform
	if _collecting:
		var id := node.get_instance_id()
		slot = int(_polygon_slots.get(id, 0))
		_polygon_slots[id] = slot + 1
		if not _polygon_cache.has(id):
			_polygon_cache[id] = {"slots":[],"generation":_geometry_generation}
		cached = _polygon_cache[id]
		cached.generation = _geometry_generation
		var entries: Array = cached.slots
		if slot < entries.size():
			var entry: Dictionary = entries[slot]
			if entry.transform == prop_transform and entry.polygon == polygon and entry.collider_id == collider.get_instance_id() and entry.material == surface_material:
				_segments.append_array(entry.segments)
				geometry_reuses += 1
				return
	# Adjacent edges share a vertex. Map the immutable local outline once in
	# native code, retaining current transforms and the original winding.
	var points: PackedVector2Array=prop_transform*polygon
	var mapped: Array[Dictionary] = []
	for index in points.size():
		var a := points[index]
		var b := points[(index+1)%points.size()]
		var edge := b-a
		if edge.length_squared()<0.01: continue
		mapped.append({"from":a,"to":b,"normal":Vector2(edge.y,-edge.x).normalized(),"material":surface_material,"collider":collider,"weather_prop":true})
	_segments.append_array(mapped)
	if _collecting:
		var entry := {"transform":prop_transform,"polygon":polygon,"collider_id":collider.get_instance_id(),"material":surface_material,"segments":mapped}
		if slot < cached.slots.size(): cached.slots[slot] = entry
		else: cached.slots.append(entry)
		geometry_builds += 1
