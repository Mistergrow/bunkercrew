class_name BackgroundAtmosphere
extends Node2D
## The original skyline's clouds and city are separate alpha textures. Only the
## cloud layers and chimney exhaust move; buildings never scroll with the wind.
const CITY := preload("res://assets/atmosphere/city.png")
const CLOUDS := preload("res://assets/atmosphere/clouds.png")
const CLOUD_DEPTHS := preload("res://assets/atmosphere/cloud_depths.png")
const SIZE := Vector2(3040,670)
const CLOUD_OVERLAP := 320.0
const CLOUD_PERIOD := SIZE.x-CLOUD_OVERLAP
const CHIMNEYS := [Vector2(143,482),Vector2(410,455),Vector2(1299,505),Vector2(1694,497),Vector2(1938,447)]
# Distant painted banks, middle rounded clouds and near wind-torn fragments.
const CLOUD_SPEEDS := [3.3,13.5,42.0]
var game
var elapsed := 0.0
var cloud_layers: Array[Node2D] = []
var smoke_layer: Node2D
var city: Sprite2D
const CloudMotion := preload("res://scripts/cloud_motion.gd")
var cloud_motion := CloudMotion.new()
var _cloud_camera_x := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sky := Node2D.new()
	sky.draw.connect(_draw_gradient.bind(sky))
	add_child(sky)
	for index in 3:
		var layer := Node2D.new()
		layer.name = ["CloudsFar","CloudBanksMiddle","CloudFragmentsNear"][index]
		if index>0:
			var cloud_material := ShaderMaterial.new()
			cloud_material.shader = preload("res://shaders/scenario_cloud.gdshader")
			cloud_material.set_shader_parameter("cloud_tint",Color(.62,.53,.55,.69) if index==1 else Color(.46,.40,.44,.64))
			layer.material = cloud_material
		layer.draw.connect(_draw_clouds.bind(layer,index))
		add_child(layer)
		cloud_layers.append(layer)
	smoke_layer = Node2D.new()
	smoke_layer.name = "ChimneySmoke"
	smoke_layer.draw.connect(_draw_smoke)
	add_child(smoke_layer)
	city = Sprite2D.new()
	city.name = "FixedCity"
	city.texture = CITY
	city.centered = false
	city.scale = SIZE/CITY.get_size()
	city.modulate = Color(0.78,0.82,0.90)
	add_child(city)

func reduced() -> bool:
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

func _process(delta: float) -> void:
	if get_tree().paused: return
	var cloud_delta := delta*(0.35 if reduced() else 1.0)
	elapsed += cloud_delta
	var weather: Node = game.weather if is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) else null
	cloud_motion.advance(cloud_delta,CLOUD_SPEEDS,weather)
	if is_instance_valid(game) and "camera" in game and is_instance_valid(game.camera):
		_cloud_camera_x=game.camera.global_position.x-720.0
	for layer in cloud_layers:
		layer.queue_redraw()
	smoke_layer.queue_redraw()

func cloud_offset(index: int) -> float:
	return fposmod(elapsed*CLOUD_SPEEDS[index]+cloud_motion.wind_distance[index]+[360.0,0.0,630.0][index],cloud_period(index))

func cloud_period(index: int) -> float:
	return CLOUD_PERIOD if index==0 else SIZE.x*(.86 if index==1 else .64)*(1.0-640.0/SIZE.x)

func chimney_anchor(index: int) -> Vector2:
	return CHIMNEYS[index]/Vector2(2048,683)*SIZE

func smoke_sample(emitter: int,index: int) -> Dictionary:
	var life := 10.5+emitter*0.7
	var age := fposmod(elapsed+index*life/22.0,life)
	var progress := age/life
	var anchor := chimney_anchor(emitter)
	var drift := Vector2(age*10.0+sin(age*0.65+emitter)*age*1.15,-age*9.0)
	return {"position":(anchor+drift).round(),"size":3.0+progress*21.0,"alpha":pow(1.0-progress,1.1)*0.68,"phase":index+emitter*7}

func _draw_gradient(layer: Node2D) -> void:
	layer.draw_rect(Rect2(-700,-400,SIZE.x+1400,400),Color("202a37"))
	# Low-frequency color field behind the original detailed cloud texture.
	var colors := [Color("26303d"),Color("3f424e"),Color("9a635b"),Color("b66b50"),Color("35434a")]
	var stops := [0.0,0.35,0.63,0.79,1.0]
	for y in range(0,int(SIZE.y),2):
		var t := y/SIZE.y
		var segment := 0
		while segment<3 and t>stops[segment+1]: segment+=1
		var color: Color = colors[segment].lerp(colors[segment+1],inverse_lerp(stops[segment],stops[segment+1],t))
		layer.draw_rect(Rect2(-300,y,SIZE.x+600,2),color*Color(0.85,0.88,0.94))

func _draw_clouds(layer: Node2D,index: int) -> void:
	var offset := floorf(cloud_offset(index)+CloudMotion.camera_offset(index,_cloud_camera_x))
	if index>0:
		var band_height := CLOUD_DEPTHS.get_height()/3.0
		var source := Rect2(0,index*band_height,CLOUD_DEPTHS.get_width(),band_height)
		var band_size := Vector2(SIZE.x*(.86 if index==1 else .64),265.0 if index==1 else 205.0)
		var period := band_size.x*(1.0-640.0/SIZE.x)
		for tile in range(-2,5):
			layer.draw_texture_rect_region(CLOUD_DEPTHS,Rect2(Vector2(tile*period+fposmod(offset,period),215.0 if index==1 else 325.0),band_size),source)
		return
	var size := Vector2(SIZE.x,SIZE.y*(0.82 if index==0 else 1.0))
	var tint := Color(0.78,0.82,0.90,0.90)
	for tile in range(-1,3):
		var origin := Vector2(tile*CLOUD_PERIOD+offset,-10 if index==0 else 18)
		# Alpha ramps overlap adjacent copies. The panorama was not authored as a
		# seamless tile: hard wrapping would otherwise expose a vertical image edge.
		var stops := [0.0,CLOUD_OVERLAP,size.x-CLOUD_OVERLAP,size.x]
		var opacity := [0.0,1.0,1.0,0.0]
		for strip in 3:
			var left: float = stops[strip]
			var right: float = stops[strip+1]
			var vertices := PackedVector2Array([origin+Vector2(left,0),origin+Vector2(right,0),origin+Vector2(right,size.y),origin+Vector2(left,size.y)])
			var a := Color(tint,tint.a*opacity[strip])
			var b := Color(tint,tint.a*opacity[strip+1])
			var uvs := PackedVector2Array([Vector2(left/size.x,0),Vector2(right/size.x,0),Vector2(right/size.x,1),Vector2(left/size.x,1)])
			layer.draw_polygon(vertices,PackedColorArray([a,b,b,a]),uvs,CLOUDS)

func _draw_smoke() -> void:
	# Each plume is anchored to a chimney in the static city. Compact shaded pixel
	# clusters rise, curl downwind, expand and dissolve without moving the skyline.
	for emitter in CHIMNEYS.size():
		for index in range(0,22,2 if reduced() else 1):
			var puff := smoke_sample(emitter,index)
			var base: Color = Color("65717d") if emitter%2==0 else Color("786f70")
			for cluster in 6:
				var angle := cluster*1.047+float(puff.phase)*0.73
				var offset := Vector2(cos(angle),sin(angle))*float(puff.size)*0.43
				var center: Vector2 = (puff.position+offset).round()
				var radius: float = maxf(2,roundf(float(puff.size)*(0.39+float(cluster%3)*0.09)))
				var color := base.lightened(0.035*(cluster%3))
				color.a = float(puff.alpha)*(0.72 if cluster%2 else 1.0)
				var polygon := PackedVector2Array()
				for point in 8:
					polygon.append((center+Vector2.from_angle(point*TAU/8)*radius).round())
				smoke_layer.draw_colored_polygon(polygon,color)
