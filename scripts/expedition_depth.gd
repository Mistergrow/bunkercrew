extends Node2D
## Painted travel plates plus a cached service-wire silhouette. Travel offsets
## derive from the sampled world camera, so guests do not invent another trip.
const SHADER := preload("res://shaders/expedition_depth.gdshader")
const SKY_SHADER := preload("res://shaders/parallax_sky.gdshader")
const Parallax := preload("res://scripts/parallax_catalog.gd")
const PANORAMA_PATH := "res://assets/expedition/road_hinterland_v2.png"
const FOREGROUND_PATH := "res://assets/expedition/road_verge_v2.png"
var game: Node
var controller: Node
var layers: Array[Sprite2D] = []
var depth_gains: Array[float] = [.08,.27,.64]
var tile_sets: Array[Array] = []
var _view := Rect2()
var _last_center := Vector2(INF,INF)
var _last_zoom := Vector2.ZERO
var _wire_layer: Node2D
var _ground_layer: Node2D
var _clock_tick:=-1
var _last_reduced:=false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	process_priority=115
	z_index=-7
	z_as_relative=false
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var environment: String=game.scenario_options.get("environment","ash_foundry")
	var paths: Array=Parallax.paths(environment)
	var climate: Dictionary=Parallax.definition(environment)
	var panorama: Texture2D=_optional(PANORAMA_PATH)
	var foreground: Texture2D=_optional(FOREGROUND_PATH)
	for index in 3:
		var sprite:=Sprite2D.new()
		sprite.name=["RouteHorizon","IndustrialDepth","NearServiceSilhouette"][index]
		sprite.centered=false
		sprite.texture=load(paths[0]) if index==0 else panorama if index==1 and panorama!=null else foreground if index==2 and foreground!=null else load(paths[2])
		if index==2 and foreground!=null:
			sprite.region_enabled=true
			sprite.region_rect=Rect2(0,497,1672,316)
		var painted:=ShaderMaterial.new()
		painted.shader=SKY_SHADER if index==0 else SHADER
		if index==0:
			for parameter: String in Parallax.IMAGE_STYLES[0]: painted.set_shader_parameter(parameter,Parallax.IMAGE_STYLES[0][parameter])
		else:
			painted.set_shader_parameter("top_fade",.42 if index==1 else .005)
			painted.set_shader_parameter("atmosphere_tint",Color(str(climate.get("mist","#607c98"))))
			var cold: bool=environment in ["frozen_rail_yard","radar_highlands"]
			painted.set_shader_parameter("atmospheric_depth",(.28 if cold else .13) if index==1 else (.27 if cold else .04))
			painted.set_shader_parameter("layer_opacity",1.0 if index==1 else .72)
			painted.set_shader_parameter("side_fade",.035 if index==2 else 0.0)
		sprite.material=painted
		add_child(sprite)
		layers.append(sprite)
		var copies: Array=[sprite]
		if index>0:
			for tile in 8:
				var copy:=Sprite2D.new()
				copy.name=sprite.name+"Tile"+str(tile+1)
				copy.centered=false
				copy.texture=sprite.texture
				copy.region_enabled=sprite.region_enabled
				copy.region_rect=sprite.region_rect
				copy.material=painted
				add_child(copy)
				copies.append(copy)
		tile_sets.append(copies)
	_wire_layer=Node2D.new()
	_wire_layer.name="ServiceWires"
	_wire_layer.draw.connect(_draw_service_wires)
	add_child(_wire_layer)
	_ground_layer=Node2D.new()
	_ground_layer.name="RoadEmbankment"
	_ground_layer.z_index=1
	_ground_layer.draw.connect(_draw_embankment)
	add_child(_ground_layer)
	_update_view()

func _optional(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _process(_delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.camera): return
	visible=is_instance_valid(controller) and controller.stage in ["travel","stop","failed"]
	if not visible: return
	if game.camera.position!=_last_center or game.camera.zoom!=_last_zoom: _update_view()
	var weather=game.get("weather")
	var reduced: bool=is_instance_valid(weather) and weather.get("reduced_effects")==true
	var truck=controller.get("vehicle")
	var seconds: float=float(truck.animation_time) if is_instance_valid(truck) else 0.0
	var tick:=floori(seconds*20)
	if tick!=_clock_tick or reduced!=_last_reduced:
		_clock_tick=tick
		_last_reduced=reduced
		layers[0].material.set_shader_parameter("scene_clock",seconds)
		layers[0].material.set_shader_parameter("motion_gain",0.0 if reduced else 1.0)

func _update_view() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.camera): return
	_last_center=game.camera.position
	_last_zoom=game.camera.zoom
	var size: Vector2=get_viewport_rect().size/game.camera.zoom
	_view=Rect2(game.camera.position-size*.5,size)
	var road_distance: float=maxf(0.0,_view.get_center().x-900.0)
	for index in layers.size():
		var sprite:=layers[index]
		# Industrial detail has fixed world scale and repeats outside the view;
		# zooming therefore never stretches a small panorama into huge buildings.
		var width: float=maxf(2200.0,_view.size.x*1.24) if index==0 else 1250.0 if index==1 else 1100.0
		var ratio: float=width/sprite.texture.get_width()
		var source_height: float=sprite.region_rect.size.y if sprite.region_enabled else float(sprite.texture.get_height())
		var height: float=source_height*ratio
		var bottom: float=[438.0,442.0,444.0][index]
		var center_x: float=_view.get_center().x-road_distance*depth_gains[index]
		if index==0:
			center_x=clampf(center_x,_view.end.x-width*.5-24.0,_view.position.x+width*.5+24.0)
			sprite.scale=Vector2.ONE*ratio
			sprite.position=Vector2(center_x-width*.5,bottom-height)
		else:
			var origin: float=center_x-width*.5
			var first_index:=floori((_view.position.x-origin)/width)
			var first: float=origin+float(first_index)*width
			var count: int=mini(9,ceili(_view.size.x/width)+2)
			for tile in tile_sets[index].size():
				var copy: Sprite2D=tile_sets[index][tile]
				copy.visible=tile<count
				# The original painting is not a tileable texture. Joining identical
				# edge columns removes cuts; the independent nearer plate and service
				# wires keep repeated industrial structure from locking together.
				copy.flip_h=posmod(first_index+tile,2)==1
				copy.scale=Vector2.ONE*ratio
				copy.position=Vector2(first+tile*width,bottom-height)
	_wire_layer.position.x=_view.get_center().x-road_distance*.76
	_ground_layer.queue_redraw()

func _draw_embankment() -> void:
	var left: float=floorf(_view.position.x/64.0)*64.0-128
	var width: float=ceilf(_view.size.x/64.0)*64.0+256
	var bottom: float=maxf(620.0,_view.end.y+64)
	# Travel has a shallow road section, not the excavation cross-section of a
	# defended bunker. This only covers paint: the collision plane is unchanged.
	_ground_layer.draw_rect(Rect2(left,430,width,bottom-430),Color("192422"))
	_ground_layer.draw_rect(Rect2(left,430,width,7),Color("687163"))
	_ground_layer.draw_rect(Rect2(left,430,width,2),Color("a4ab91"))
	_ground_layer.draw_rect(Rect2(left,440,width,13),Color("354237"))
	_ground_layer.draw_rect(Rect2(left,454,width,19),Color("26332b"))
	_ground_layer.draw_rect(Rect2(left,475,width,25),Color("202e27"))
	for x in range(int(left),int(left+width),64):
		_ground_layer.draw_line(Vector2(x,431),Vector2(x+3,453),Color("26302a"),1,false)
		_ground_layer.draw_rect(Rect2(x+8,442,45,6),Color("485244"))
		_ground_layer.draw_rect(Rect2(x+15,464+posmod(x,7),22,3),Color("39473a"))

func _draw_service_wires() -> void:
	# The wires pass behind combatants and have no collisions. Native material
	# colors, interrupted spans and sparse braces match the bunker's machinery.
	var shadow:=Color("27322f")
	var edge:=Color("596158")
	for index in range(-7,8):
		var x:=float(index*250)
		var top:=Vector2(x,202.0+float(posmod(index,3))*11.0)
		_wire_layer.draw_line(top,Vector2(x,430),shadow,6,false)
		_wire_layer.draw_line(top+Vector2(1,1),Vector2(x+1,430),edge,1,false)
		_wire_layer.draw_line(top+Vector2(-17,6),top+Vector2(17,6),edge,3,false)
		if posmod(index,4)==2: continue
		var next:=Vector2(x+250,202+float(posmod(index+1,3))*11)
		var wire:=PackedVector2Array()
		for step in 9:
			var phase:=float(step)/8.0
			wire.append(top.lerp(next,phase)+Vector2(0,6+sin(phase*PI)*14))
		_wire_layer.draw_polyline(wire,shadow,1,false)
