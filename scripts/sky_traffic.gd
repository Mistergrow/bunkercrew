extends Node2D
## Quiet, distant navigation lights between two painted cloud planes. The
## owner supplies camera geometry and its pause-safe clock; no physics/audio,
## image readback, random respawns or per-frame node allocation are involved.
const CLOUDS := preload("res://assets/atmosphere/cloud_depths.png")
const CLOUD_SHADER := preload("res://shaders/sky_traffic_cloud.gdshader")
const LIGHT_SHADER := preload("res://shaders/sky_traffic_light.gdshader")
const Catalog := preload("res://scripts/sky_traffic_catalog.gd")
const LIGHT_RECT := Rect2(-14.0,-9.0,28.0,18.0)
# Cloud contours, flight paths and margins live in the authored sky's source
# pixels. The reference display preserves the existing normal world framing;
# camera zoom only maps that fixed composition to the current WeatherSky rect.
const SOURCE_SIZE := Vector2(1672.0,941.0)
const REFERENCE_WIDTH := 2088.0
const REFERENCE_HEIGHT := REFERENCE_WIDTH*SOURCE_SIZE.y/SOURCE_SIZE.x
const REFERENCE_TOP := 494.0-REFERENCE_HEIGHT
const WORLD_CLOUD_Y := Vector2((-500.0-REFERENCE_TOP)/REFERENCE_HEIGHT,(-300.0-REFERENCE_TOP)/REFERENCE_HEIGHT)
const WORLD_LIGHT_Y := (-230.0-REFERENCE_TOP)/REFERENCE_HEIGHT
var environment_id := "sector07"
var definition: Dictionary
var far_clouds: Node2D
var light_layer: Node2D
var near_clouds: Node2D
var cloud_materials: Array[ShaderMaterial] = []
var light_nodes: Array[Node2D] = []
var light_materials: Array[ShaderMaterial] = []
var cloud_cards: Array[Array] = [[],[]]
var sky_bounds := Rect2()
var scene_clock := 0.0
var _view := Rect2()
var _sky_mask: Texture2D
var _menu_composition := false
var _sky_drift := Vector2.ZERO

func configure(id: String,menu_composition: bool=false) -> void:
	environment_id = id
	definition = Catalog.definition(id)
	_menu_composition = menu_composition

func _ready() -> void:
	name = "SkyTrafficBetweenClouds"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if definition.is_empty(): configure(environment_id)
	far_clouds = _cloud_plane("HighCloudWisps",0)
	light_layer = Node2D.new()
	light_layer.name = "DistantNavigationLights"
	add_child(light_layer)
	for index in int(definition.count):
		var light := Node2D.new()
		light.name = "DistantAircraftLight%d" % index
		var surface := ShaderMaterial.new()
		surface.shader = LIGHT_SHADER
		_set_cloud_uniforms(surface,2.73)
		surface.set_shader_parameter("light_tint",Color(str(definition.light)))
		light.material = surface
		light.draw.connect(func(): light.draw_rect(LIGHT_RECT,Color.WHITE))
		light_layer.add_child(light)
		light_nodes.append(light)
		light_materials.append(surface)
	near_clouds = _cloud_plane("LowCloudOcclusion",1)
	set_process(false)

func _set_cloud_uniforms(surface: ShaderMaterial,phase: float) -> void:
	surface.set_shader_parameter("cloud_atlas",CLOUDS)
	surface.set_shader_parameter("cloud_texel",Vector2.ONE/CLOUDS.get_size())
	surface.set_shader_parameter("cloud_phase",phase)

func _cloud_plane(label: String,depth: int) -> Node2D:
	var plane := Node2D.new()
	plane.name = label
	var surface := ShaderMaterial.new()
	surface.shader = CLOUD_SHADER
	_set_cloud_uniforms(surface,.81 if depth==0 else 2.73)
	var tint := Color(str(definition.cloud))
	tint.a = float(definition.opacity)*(.32 if depth==0 else .62)
	surface.set_shader_parameter("cloud_tint",tint)
	plane.material = surface
	plane.draw.connect(_draw_clouds.bind(plane,depth))
	add_child(plane)
	cloud_materials.append(surface)
	return plane

func _cards(depth: int,bounds: Rect2,seconds: float) -> Array:
	var result: Array[Rect2] = []
	var source_scale := bounds.size/SOURCE_SIZE
	var size := Vector2(SOURCE_SIZE.x*(.61 if depth==0 else .49),SOURCE_SIZE.x*(.13 if depth==0 else .105))
	var period := size.x*.83
	var travel := (seconds*(4.4 if depth==0 else 10.5)+float(posmod(environment_id.hash(),83))*4.0)*SOURCE_SIZE.x/REFERENCE_WIDTH
	var shift := fposmod(travel,period)
	var top_uv := (.075 if depth==0 else .185) if _menu_composition else WORLD_CLOUD_Y[depth]
	var origin := bounds.position-_sky_drift*bounds.size
	# The atlas cards overlap. Include the left overlap before wrapping as
	# well, so its contour/mask never pops when the periodic phase resets.
	var first := floori((-shift-size.x)/period)+1
	for index in range(first,first+4):
		result.append(Rect2(origin+Vector2(index*period+shift,top_uv*SOURCE_SIZE.y)*source_scale,size*source_scale))
	return result

func light_sample(index: int,seconds: float,bounds: Rect2) -> Dictionary:
	var direction := -1.0 if index%2 else 1.0
	var pixel_scale := SOURCE_SIZE.x/REFERENCE_WIDTH
	var margin := 100.0*pixel_scale
	var period := SOURCE_SIZE.x+margin*2.0
	var seed_value := (.42+float(posmod(environment_id.hash(),83))/83.0*.16+index*.32)*period
	var travel := fposmod(seed_value+seconds*(17.0+index*4.0)*pixel_scale,period)-margin
	if direction<0: travel=SOURCE_SIZE.x-travel
	var altitude_uv := .205+index*.035 if _menu_composition else WORLD_LIGHT_Y+index*45.0/REFERENCE_HEIGHT
	altitude_uv += sin(seconds*.034+index*2.1)*7.0/REFERENCE_HEIGHT
	var point := bounds.position+(Vector2(travel/SOURCE_SIZE.x,altitude_uv)-_sky_drift)*bounds.size
	return {"position":point,"direction":direction,"illumination":.80+sin(seconds*.78+index*4.73)*.12}

func update_view(bounds: Rect2,view: Rect2,seconds: float,reduced: bool,sky_drift: Vector2=Vector2.ZERO) -> void:
	visible = not reduced and bounds.has_area()
	if not visible: return
	sky_bounds = bounds
	_sky_drift = sky_drift
	_view = view
	scene_clock = seconds
	for depth in 2:
		cloud_cards[depth] = _cards(depth,bounds,seconds)
		cloud_materials[depth].set_shader_parameter("cloud_clock",seconds)
		(far_clouds if depth==0 else near_clouds).queue_redraw()
	var foreground: Array[Vector4] = []
	for card: Rect2 in cloud_cards[1]: foreground.append(Vector4(card.position.x,card.position.y,card.size.x,card.size.y))
	for index in light_nodes.size():
		var sample := light_sample(index,seconds,bounds)
		var light: Node2D = light_nodes[index]
		light.position = sample.position
		light.scale = bounds.size/SOURCE_SIZE
		var light_rect := Rect2(light.position+LIGHT_RECT.position*light.scale,LIGHT_RECT.size*light.scale)
		light.visible = view.intersects(light_rect)
		var surface: ShaderMaterial = light_materials[index]
		surface.set_shader_parameter("light_origin",light.position)
		surface.set_shader_parameter("light_scale",light.scale)
		surface.set_shader_parameter("near_clouds",foreground)
		surface.set_shader_parameter("cloud_clock",seconds)
		surface.set_shader_parameter("direction",sample.direction)
		surface.set_shader_parameter("illumination",sample.illumination)
	for surface in cloud_materials+light_materials:
		surface.set_shader_parameter("sky_drift",_sky_drift)
		if _sky_mask!=null: surface.set_shader_parameter("sky_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))

func configure_sky_mask(texture: Texture2D) -> void:
	_sky_mask=texture
	for surface in cloud_materials+light_materials:
		surface.set_shader_parameter("mask_sky",texture!=null)
		if texture!=null: surface.set_shader_parameter("skyline",texture)

func _draw_clouds(plane: Node2D,depth: int) -> void:
	var row := 0 if depth==0 else 2
	var source := Rect2(0,row*CLOUDS.get_height()/3.0,CLOUDS.get_width(),CLOUDS.get_height()/3.0)
	for card: Rect2 in cloud_cards[depth]:
		if card.intersects(_view): plane.draw_texture_rect_region(CLOUDS,card,source)
