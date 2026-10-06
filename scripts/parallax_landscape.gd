extends Node2D
## Three painted depth plates and climate-tinted mist. Cosmetic, pause-safe
## shader motion; geometry and textures are prepared once at scene creation.
const Catalog := preload("res://scripts/parallax_catalog.gd")
const SKY_SHADER := preload("res://shaders/parallax_sky.gdshader")
const VALLEY_SHADER := preload("res://shaders/parallax_valley.gdshader")
const MIST_SHADER := preload("res://shaders/parallax_mist.gdshader")
const SAMPLING_SHADER := preload("res://shaders/background_sampling.gdshader")
const Surfaces := preload("res://scripts/background_surface_catalog.gd")
const GAINS := Catalog.GAINS
var environment_id := "mountain_pass"
var definition: Dictionary
var layers: Array[Sprite2D] = []
var materials: Array[ShaderMaterial] = []
var image_materials: Array[ShaderMaterial] = []
var surface_mask: Texture2D
var surface_mask_bounds := Vector4(0.0,0.0,1.0,1.0)
var mist: Node2D
var sky_traffic: Node2D
var mist_rect := Rect2()
var layer_rects: Array[Rect2] = []
var _clock_tick := -1
var _last_reduced := false
var sky_uv_drift := Vector2.ZERO

func configure(id: String) -> void:
	environment_id=id
	definition=Catalog.definition(id)

func _ready() -> void:
	if definition.is_empty(): configure(environment_id)
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var paths := Catalog.paths(environment_id)
	var soft := "--soft-backgrounds" in OS.get_cmdline_user_args()
	surface_mask=Surfaces.texture(environment_id)
	surface_mask_bounds=Surfaces.bounds(environment_id)
	for index in 3:
		var layer := Sprite2D.new()
		layer.name=["WeatherSky","FarLandscape","ScenicLandmarks"][index]
		layer.centered=false
		layer.texture=load(paths[index])
		var surface := ShaderMaterial.new()
		surface.shader=[SKY_SHADER,SAMPLING_SHADER,VALLEY_SHADER][index]
		surface.set_shader_parameter("pixel_clarity",0.0 if soft else 1.0)
		for parameter: String in Catalog.IMAGE_STYLES[index]:
			surface.set_shader_parameter(parameter,0.0 if soft and parameter!="sample_radius" else Catalog.IMAGE_STYLES[index][parameter])
		if index==2:
			surface.set_shader_parameter("surface_mask",surface_mask)
			surface.set_shader_parameter("surface_bounds",surface_mask_bounds)
			surface.set_shader_parameter("surface_enabled",surface_mask!=null and Surfaces.enabled(environment_id))
			surface.set_shader_parameter("light_gain",float(definition.lights))
		if index==0: surface.set_shader_parameter("use_sky_drift",true)
		layer.material=surface
		image_materials.append(surface)
		if index!=1:materials.append(surface)
		add_child(layer);layers.append(layer)
		if index==0:
			sky_traffic=preload("res://scripts/sky_traffic.gd").new()
			sky_traffic.configure(environment_id)
			add_child(sky_traffic)
		if index==1:
			mist=Node2D.new()
			mist.name="DriftingLandscapeMist"
			var mist_material:=ShaderMaterial.new()
			mist_material.shader=MIST_SHADER
			mist_material.set_shader_parameter("mist_color",Color(str(definition.mist)))
			mist_material.set_shader_parameter("mist_opacity",float(definition.opacity))
			mist.material=mist_material;materials.append(mist_material)
			mist.draw.connect(func():mist.draw_rect(mist_rect,Color.WHITE))
			add_child(mist)

func update_view(bounds: Rect2, view: Rect2, seconds: float, reduced: bool) -> void:
	var size := bounds.size*1.16
	var origin := Vector2(bounds.get_center().x-size.x*.5,bounds.end.y-size.y)
	var camera_delta := view.get_center().x-720.0
	layer_rects.clear()
	for index in layers.size():
		var shift := clampf(camera_delta*GAINS[index],view.end.x+32.0-size.x-origin.x,view.position.x-32.0-origin.x)
		var layer := layers[index]
		layer.position=origin+Vector2(shift,0)
		layer.scale=size/layer.texture.get_size()
		layer_rects.append(Rect2(layer.position,size))
	var region := layer_rects[1]
	if mist_rect!=region:
		mist_rect=region
		mist.queue_redraw()
	var tick := floori(seconds*30)
	if tick!=_clock_tick or reduced!=_last_reduced:
		_clock_tick=tick;_last_reduced=reduced
		# WeatherSky sampling and both cloud/light planes use one UV transform.
		# A camera change never changes its phase, nor the source-space masks.
		sky_uv_drift = Vector2(sin(seconds*.022)*.014,sin(seconds*.017)*.004) if not reduced else Vector2.ZERO
		image_materials[0].set_shader_parameter("sky_drift",sky_uv_drift)
		for surface in materials:
			surface.set_shader_parameter("scene_clock",seconds)
			surface.set_shader_parameter("motion_gain",0.0 if reduced else 1.0)
	sky_traffic.update_view(layer_rects[0],view,seconds,reduced,sky_uv_drift)
	mist.visible=not reduced
