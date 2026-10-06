extends Node2D
## Root-anchored painted trees and batched local details. Reactions own damage;
## this node presents their state without changing gameplay collision.
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const PropArt := preload("res://scripts/scenario_prop_art.gd")
const WIND_SHADER := preload("res://shaders/scenario_prop_wind.gdshader")
const TREE_HEIGHT := 192.0
const TREE_BANDS := 12
var game
var presentation_weather: Node
var environment_id := "sector07"
var bunker_left := 90.0
var bunker_right := 730.0
var entries: Array[Dictionary] = []
var elapsed := 0.0
var tree_nodes: Array[MeshInstance2D] = []
var tree_materials: Dictionary = {}
var reactions: Node
var debris: Node2D
var visible_bounds := Rect2(-100,-100,1640,1000)
var _profile: Dictionary = {}
var _tree_assets: Dictionary = {}
var _draw_clock := 0.0
var _reduced := false
var _motion_scale := 1.0
var _gust_strength := 1.0
var _draw_layer: Node2D
var _tree_by_index: Dictionary = {}
var _material_tick := -1
var uniform_updates := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2
	if is_instance_valid(game) and is_instance_valid(game.get("scenario_bunker")):
		bunker_left = game.scenario_bunker.room_left
		bunker_right = game.scenario_bunker.room_right
	_profile = Catalog.profile(environment_id)
	entries = Catalog.layout(environment_id,bunker_left,bunker_right)
	for entry in entries:
		if entry.kind=="tree": _make_tree(entry)
	_draw_layer = Node2D.new()
	_draw_layer.name = "AnimatedIndustrialDetails"
	var detail_material:=ShaderMaterial.new()
	detail_material.shader=preload("res://shaders/perimeter_pixel.gdshader")
	_draw_layer.material=detail_material
	_draw_layer.draw.connect(_draw_native)
	add_child(_draw_layer)
	reactions = preload("res://scripts/scenery_damage.gd").new()
	reactions.name = "SceneryDamage"
	reactions.props = self
	add_child(reactions)
	debris = preload("res://scripts/scenery_prop_effects.gd").new()
	debris.name = "SceneryPropEffects"
	debris.props = self
	add_child(debris)
	_update_visibility()
	_update_states()
	_update_materials()

func reduced() -> bool:
	return is_instance_valid(game) and is_instance_valid(game.get("weather")) and bool(game.weather.reduced_effects)

func _process(delta: float) -> void:
	if get_tree().paused: return
	_reduced = reduced()
	_motion_scale = .24 if _reduced else 1.0
	_gust_strength = gust_for(Vector2((bunker_left+bunker_right)*.5,430))
	elapsed += delta*(.25 if _reduced else 1.0)
	_draw_clock += delta
	if _draw_clock>=1.0/(12.0 if _reduced else 30.0):
		_draw_clock = 0.0
		_update_visibility()
		_update_states()
		_update_materials()
		_draw_layer.queue_redraw()

func _update_materials() -> void:
	var tick := floori(elapsed*(12.0 if _reduced else 30.0))
	if tick==_material_tick: return
	_material_tick = tick
	for index: int in tree_materials:
		if not bool(entries[index].get("displayed",true)) or bool(entries[index].get("broken",false)): continue
		var wind_material: ShaderMaterial = tree_materials[index]
		var local_gust:=gust_for(entries[index].position)
		wind_material.set_shader_parameter("wind_clock",elapsed)
		wind_material.set_shader_parameter("motion_scale",_motion_scale)
		wind_material.set_shader_parameter("gust_strength",local_gust)
		wind_material.set_shader_parameter("hit_amount",float(entries[index].get("hit_amount",0.0)))
		entries[index].shader_clock = elapsed
		entries[index].shader_motion = _motion_scale
		entries[index].shader_gust = local_gust
		entries[index].shader_hit = float(entries[index].get("hit_amount",0.0))
		uniform_updates += 4

func _update_visibility() -> void:
	visible_bounds = (get_canvas_transform().affine_inverse()*get_viewport_rect()).grow(96)
	for entry in entries:
		entry.displayed = visible_bounds.intersects(entry.bounds) and not (_reduced and entry.optional and int(entry.index)%2==0)
	for tree in tree_nodes:
		var entry := entries[int(tree.get_meta("prop_index"))]
		tree.visible = bool(entry.displayed) and not bool(entry.get("broken",false))

func _update_states() -> void:
	if not is_instance_valid(reactions): return
	for entry in entries:
		var state: Dictionary = reactions.state_for(int(entry.index))
		if state.is_empty(): continue
		var serial := int(state.get("serial",0))
		if serial!=int(entry.get("state_serial",-1)):
			if entry.has("state_serial"):
				entry.hit_clock = elapsed
				entry.hit_direction = signf(Vector2(state.get("direction",Vector2.RIGHT)).x)
			entry.state_serial = serial
		entry.broken = bool(state.get("broken",false))
		entry.burning = bool(state.get("burning",false))
		entry.charred = bool(state.get("charred",false))
		var age := maxf(0.0,elapsed-float(entry.get("hit_clock",-10.0)))
		entry.hit_amount = sin(age*24.0)*exp(-age*7.0)*float(entry.get("hit_direction",1.0))*3.0
		if _tree_by_index.has(int(entry.index)):
			var tree: MeshInstance2D = _tree_by_index[int(entry.index)]
			tree.visible = bool(entry.displayed) and not entry.broken
			var tint: Color = entry.tint
			if entry.optional: tint = tint.darkened(.13)
			if entry.charred: tint = tint.darkened(.52)
			elif entry.burning: tint = tint.darkened(.28)
			tree.modulate = tint

func sync_replica(first_snapshot: bool) -> void:
	# A joining peer sees the current wound/char state immediately, without
	# replaying the old hit that produced the host's existing serial number.
	if first_snapshot and is_instance_valid(reactions):
		for entry in entries:
			var state: Dictionary = reactions.state_for(int(entry.index))
			if state.is_empty(): continue
			entry.state_serial = int(state.get("serial",0))
			entry.hit_clock = -10.0
			entry.hit_direction = 0.0
	_update_visibility()
	_update_states()
	_material_tick = -1
	_update_materials()
	_draw_layer.queue_redraw()

func _load_tree(kind: String) -> Dictionary:
	if _tree_assets.has(kind): return _tree_assets[kind]
	var path := str(Catalog.TREE_PATHS.get(kind,""))
	if not ResourceLoader.exists(path): return {}
	var texture := load(path) as Texture2D
	if texture==null: return {}
	# Authored alpha>=64 regions exclude the generator's almost transparent
	# fringe. Metadata avoids a texture readback and alpha scan on scene entry.
	var texture_size := texture.get_size()
	var crop: Rect2i = Catalog.TREE_REGIONS.get(kind,Rect2i(Vector2i.ZERO,Vector2i(texture_size)))
	if crop.size.x<=0 or crop.size.y<=0: return {}
	var anchor: Vector2 = Catalog.TREE_ROOTS[kind]
	var source_scale := TREE_HEIGHT/(anchor.y-float(crop.position.y))
	var width := source_scale*float(crop.size.x)
	# Keep the source trunk foot at local(0,0), not the crop's horizontal middle.
	# Mesh ends at the burial line, so dangling illustrated roots never render.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for band in TREE_BANDS+1:
		var v := float(band)/TREE_BANDS
		for side in 2:
			var source_x := float(crop.position.x)+float(side)*crop.size.x
			var source_y := lerpf(float(crop.position.y),anchor.y+2.0,v)
			vertices.append(Vector3((source_x-anchor.x)*source_scale,(source_y-anchor.y)*source_scale,0))
			uvs.append(Vector2(source_x/texture_size.x,source_y/texture_size.y))
		if band<TREE_BANDS:
			var index := band*2
			indices.append_array(PackedInt32Array([index,index+1,index+2,index+1,index+3,index+2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_tree_assets[kind] = {"texture":texture,"mesh":mesh,"width":width,"crop":crop,"anchor":anchor,"source_scale":source_scale}
	return _tree_assets[kind]

func _make_tree(entry: Dictionary) -> void:
	var asset := _load_tree(str(entry.tree))
	if asset.is_empty():
		entry.fallback = true
		return
	var tree := MeshInstance2D.new()
	tree.name = "WindTree%02d" % int(entry.index)
	tree.mesh = asset.mesh
	tree.texture = asset.texture
	var wind_material := ShaderMaterial.new()
	wind_material.shader = WIND_SHADER
	wind_material.set_shader_parameter("wind_strength",float(_profile.wind))
	wind_material.set_shader_parameter("stiffness",float(entry.stiffness))
	wind_material.set_shader_parameter("tree_phase",float(entry.phase))
	wind_material.set_shader_parameter("tree_rate",float(entry.wind_rate))
	tree.material = wind_material
	tree_materials[int(entry.index)] = wind_material
	tree.position = entry.position
	var scale_y: float = entry.size.y/TREE_HEIGHT
	# Keep branch silhouettes varied without squashing a tall pine into a bush.
	var mirror := -1.0 if int(entry.index)%4==2 else 1.0
	tree.scale = Vector2(mirror*scale_y*(.86 if int(entry.index)%3==0 else 1.0),scale_y)
	tree.modulate = entry.tint
	if entry.optional: tree.modulate = tree.modulate.darkened(.13)
	tree.set_meta("prop_index",entry.index)
	add_child(tree)
	tree_nodes.append(tree)
	_tree_by_index[int(entry.index)] = tree
	entry.size.x = float(asset.width)*absf(tree.scale.x)
	entry.tree_scale = tree.scale*float(asset.source_scale)
	entry.mesh_scale = tree.scale
	entry.mesh_source_scale = float(asset.source_scale)
	entry.root_pixel = asset.anchor
	entry.source_crop = asset.crop
	var left := (float(asset.crop.position.x)-float(asset.anchor.x))*float(entry.tree_scale.x)
	var right := (float(asset.crop.end.x)-float(asset.anchor.x))*float(entry.tree_scale.x)
	entry.bounds = Rect2(entry.position+Vector2(minf(left,right)-18,-entry.size.y-3),Vector2(absf(right-left)+36,entry.size.y+6))
	entry.emit_points = PackedVector2Array()
	for point: Vector2 in Catalog.canopy_points(str(entry.tree)):
		entry.emit_points.append(entry.position+(point-Vector2(asset.anchor))*Vector2(entry.tree_scale))
	entry.trunk_points = PackedVector2Array()
	entry.damage_segments = []
	for point: Vector2 in Catalog.TREE_TRUNKS[entry.tree]:
		entry.trunk_points.append(entry.position+(point-Vector2(asset.anchor))*Vector2(entry.tree_scale))
	for index in entry.trunk_points.size()-1:
		var source_radius := float(Catalog.tree_metadata(str(entry.tree)).get("trunk_radius",48.0))
		entry.damage_segments.append({"from":entry.trunk_points[index]-entry.position,"to":entry.trunk_points[index+1]-entry.position,"radius":maxf(2,source_radius*absf(entry.tree_scale.x)*(1.0-index*.15))})

func _draw_native() -> void:
	for entry in entries:
		if not bool(entry.get("displayed",true)): continue
		if bool(entry.get("broken",false)): continue
		if entry.kind=="tree" and not bool(entry.get("fallback",false)): continue
		PropArt.draw(_draw_layer,entry,elapsed*float(entry.wind_rate),_motion_scale,float(_profile.wind)*gust_for(entry.position)/float(entry.stiffness))

func gust_for(point: Vector2) -> float:
	if is_instance_valid(presentation_weather):
		return .06 + clampf(float(presentation_weather.gust_at(to_global(point))), 0, 1) * .94
	if is_instance_valid(game) and is_instance_valid(game.get("weather")):
		if game.weather.has_method("gust_at"):
			return .06+clampf(float(game.weather.gust_at(to_global(point))),0,1)*.94
		if game.weather.has_method("wind_strength"):
			return .06+clampf(float(game.weather.wind_strength()),0,1)*.94
	return .06

func canopy_point(entry: Dictionary,index: int,at_time: float=-1.0) -> Vector2:
	var points: PackedVector2Array = entry.get("emit_points",PackedVector2Array())
	if points.is_empty(): return entry.position-Vector2(0,float(entry.size.y)*.6)
	var point := points[posmod(index,points.size())]
	var pixel := (point-Vector2(entry.position))/Vector2(entry.tree_scale)+Vector2(entry.root_pixel)
	var crop: Rect2i = entry.source_crop
	var source_scale := float(entry.mesh_source_scale)
	var u := clampf((pixel.x-float(crop.position.x))/float(crop.size.x),0,1)
	var band_position := clampf((pixel.y-float(crop.position.y))/(float(entry.root_pixel.y)+2.0-float(crop.position.y))*TREE_BANDS,0,TREE_BANDS-.0001)
	var band := floori(band_position)
	var v := band_position-band
	var time := float(entry.get("shader_clock",elapsed)) if at_time<0 else at_time
	var x0 := (float(crop.position.x)-float(entry.root_pixel.x))*source_scale
	var x1 := (float(crop.end.x)-float(entry.root_pixel.x))*source_scale
	var y0 := lerpf(-TREE_HEIGHT,2.0*source_scale,float(band)/TREE_BANDS)
	var y1 := lerpf(-TREE_HEIGHT,2.0*source_scale,float(band+1)/TREE_BANDS)
	# Interpolate the same triangle vertices Godot renders, not a different
	# analytical sway applied directly to an interior image point.
	var a := _tree_vertex(entry,Vector2(x0,y0),time)
	var b := _tree_vertex(entry,Vector2(x1,y0),time)
	var c := _tree_vertex(entry,Vector2(x0,y1),time)
	var local: Vector2
	if u+v<=1.0:
		local = a*(1.0-u-v)+b*u+c*v
	else:
		var d := _tree_vertex(entry,Vector2(x1,y1),time)
		local = b*(1.0-v)+d*(u+v-1.0)+c*(1.0-u)
	return Vector2(entry.position)+local*Vector2(entry.mesh_scale)

func _tree_vertex(entry: Dictionary,vertex: Vector2,time: float) -> Vector2:
	var height := clampf(-vertex.y/TREE_HEIGHT,0,1)
	var clock := time*float(entry.wind_rate)
	var phase := float(entry.phase)
	var world_x := to_global(entry.position).x
	var gust := sin(clock*.73+phase)*.52+sin(clock*1.41+phase*1.73)*.23+sin(time*.91-world_x*.011)*.25
	var bend := pow(clampf((height-.18)/.82,0,1),2)
	var direction := signf(float(entry.mesh_scale.x)*global_transform.x.x)
	var branch := sin(clock*2.17+height*8.3+vertex.x*.037+phase)*height*height
	var motion := float(entry.get("shader_motion",_motion_scale))
	var strength := float(_profile.wind)*float(entry.get("shader_gust",_gust_strength))*motion/float(entry.stiffness)
	var result := vertex
	result.x += ((2.0+gust*6.5)*bend+branch*.8*bend)*strength*direction
	result.x += float(entry.get("shader_hit",0.0))*bend
	# The shader reads VERTEX.x after its horizontal displacement for this term.
	result.y += sin(clock*1.13+phase+result.x*.041)*.45*bend*motion*clampf(float(entry.get("shader_gust",_gust_strength)),0,1)
	return result

func sample(index: int,at_time: float=-1.0) -> Dictionary:
	if index<0 or index>=entries.size(): return {}
	var entry := entries[index]
	var time := elapsed if at_time<0 else at_time
	var motion := PropArt.wind(time*float(entry.wind_rate),float(entry.phase),_motion_scale*float(_profile.wind)*gust_for(entry.position)/float(entry.stiffness))
	return {"kind":entry.kind,"root":entry.position,"tip":entry.position+Vector2(motion*8.0,-float(entry.size.y)),"animated":entry.animated,"displayed":entry.get("displayed",true)}

func diagnostics() -> Dictionary:
	var animated := 0
	var displayed := 0
	for entry in entries:
		if entry.animated: animated += 1
		if entry.get("displayed",true): displayed += 1
	return {"environment":environment_id,"entries":entries.size(),"trees":tree_nodes.size(),"animated":animated,"visible":displayed,"materials":tree_materials.size(),"bands":TREE_BANDS,"reduced":_reduced,"elapsed":elapsed,"uniform_updates":uniform_updates}
