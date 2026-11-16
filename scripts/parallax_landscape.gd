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
const LIGHTING := preload("res://scripts/world_lighting.gd")
const PixelGrid := preload("res://scripts/pixel_grid.gd")
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
var plate_smoke: Node2D
var _smoke_seconds := 0.0
## Aerial perspective at night (depth_grade_for): a thin veil of the world's
## measured sky light inside the far plate's own shader (no extra full-screen
## layer), and the near plate taken a step darker and toward neutral, so the
## plates separate by depth instead of sharing one saturated night colour.
## Static; none by day.
var depth_veil := Color(0, 0, 0, 0)
var smoke_tone := Color(.3, .3, .3)
var _software := LIGHTING.software_renderer()
var steam_tone := Color(.8, .8, .8)
var near_grade := Color.WHITE
var layer_rects: Array[Rect2] = []
var _clock_tick := -1
var _last_reduced := false
var sky_uv_drift := Vector2.ZERO
var _world_block := Vector2.ZERO
var _soft := false

func configure(id: String) -> void:
	environment_id=id
	definition=Catalog.definition(id)

func _ready() -> void:
	if definition.is_empty(): configure(environment_id)
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var paths := Catalog.paths(environment_id)
	var soft := "--soft-backgrounds" in OS.get_cmdline_user_args()
	_soft=soft
	surface_mask=Surfaces.texture(environment_id)
	surface_mask_bounds=Surfaces.bounds(environment_id)
	_prepare_depth_grade()
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
		if index==1: surface.set_shader_parameter("veil",depth_veil)
		layer.material=surface
		image_materials.append(surface)
		if index!=1:materials.append(surface)
		if index==2: layer.modulate=near_grade
		add_child(layer);layers.append(layer)
		if index==2 and Catalog.STACKS.has(Catalog.background_id(environment_id)):
			plate_smoke=Node2D.new()
			plate_smoke.name="PlateStackSmoke"
			plate_smoke.material=preload("res://scripts/pixel_effect_art.gd").grid_material("unlit")
			plate_smoke.draw.connect(_draw_plate_smoke)
			add_child(plate_smoke)
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

## Night depth grade of a world from its measured backdrop light: the veil
## colour and alpha over the far plates (x) and the near plate's multiplier
## (y). A violet night key loses most of its tint on the nearest plate, and
## every night world's nearest plate sinks a step below the veiled far
## plates; daylight worlds keep their plates as painted.
static func depth_grade_for(data: Dictionary) -> Array[Color]:
	var night := LIGHTING.night_for(data)
	var key: Dictionary = LIGHTING.light_key(data)
	var sky: Color = key.sky
	var grey := LIGHTING.luminance(sky)
	var veil := Color(sky.r, sky.g, sky.b).lerp(Color(grey, grey, grey), .6).lightened(.14)
	veil.a = (.06 + .08 * night) * smoothstep(.15, .6, night)
	var hue := LIGHTING.light_hue(data)
	var low := minf(hue.r, minf(hue.g, hue.b))
	var chroma := maxf(hue.r, maxf(hue.g, hue.b)) - low
	# A violet cast (red and green balanced under a dominant blue) reads as an
	# unnatural purple that flattens the plates; a blue moonlit one does not.
	var violet := smoothstep(.80, .97, hue.r / maxf(hue.g, .01)) * (1.0 if hue.b >= maxf(hue.r, hue.g) else 0.0)
	var counter := .70 * night * smoothstep(.2, .5, chroma) * violet
	var value := 1.0 - (.05 + .10 * violet) * night
	var near := Color((1.0 - (hue.r - low) * counter) * value, (1.0 - (hue.g - low) * counter) * value, (1.0 - (hue.b - low) * counter) * value)
	return [veil, near]

func _prepare_depth_grade() -> void:
	var data: Dictionary = preload("res://scripts/content_registry.gd").data("environments", environment_id)
	var grade := depth_grade_for(data if not data.is_empty() else {"id":environment_id})
	depth_veil = grade[0]
	near_grade = grade[1]
	# Stack smoke reads against its sky: dark charcoal against a day sky,
	# lit from below by the works (lighter than the sky) at night.
	var night := LIGHTING.night_for(data if not data.is_empty() else {"id":environment_id})
	var air := Color(str(definition.get("mist","#808890")))
	smoke_tone = air.lerp(Color(.24,.23,.22),.7).lerp(air.lerp(Color(.72,.60,.52),.4).lightened(.08),night)
	steam_tone = air.lightened(.18).lerp(air.lerp(Color(.80,.74,.70),.5),night*.5)

## Puffs rising from every stack of Catalog.STACKS on the nearest plate:
## chimney smoke in drifting grey billows, cooling-tower steam in broad pale
## columns. Positions come from the plate's own rect, so they stay on the
## painted stacks however the plate is framed.
func _draw_plate_smoke() -> void:
	var rect: Rect2 = plate_smoke.get_meta("rect",Rect2())
	if not rect.has_area(): return
	var texel := rect.size.x/1672.0
	var stacks: Array = Catalog.STACKS.get(Catalog.background_id(environment_id),[])
	for stack_index in stacks.size():
		var stack: Array = stacks[stack_index]
		var origin := rect.position+Vector2(float(stack[0]),float(stack[1]))*texel
		var tower := int(stack[2])==1
		# The software tier draws half the puffs (every puff is a shaded quad).
		var puffs := (7 if tower else 8) >> (1 if _software else 0)
		var life := (7.0 if tower else 7.0)+float(stack_index%3)*.6
		for puff in puffs:
			var age := fposmod(_smoke_seconds+float(puff)*life/float(puffs)+float(stack_index)*.37,life)
			var progress := age/life
			var rise := age*(6.0 if tower else 5.5)*texel
			var drift := (age*3.2+sin(age*.8+float(stack_index))*age*.5)*texel
			var radius := ((7.0 if tower else 3.5)+progress*(12.0 if tower else 13.0))*texel
			var tone := steam_tone if tower else smoke_tone
			var alpha := smoothstep(0.0,.05,progress)*pow(1.0-progress,1.1)*(.62 if tower else .85)
			preload("res://scripts/pixel_effect_art.gd").grid_smoke(plate_smoke,origin+Vector2(drift,-rise-radius*.4),radius,Color(tone,alpha),puff+stack_index*7,smoothstep(.45,1.0,progress)*.85)

func update_view(bounds: Rect2, view: Rect2, seconds: float, reduced: bool) -> void:
	var size := bounds.size*1.16
	var origin := Vector2(bounds.get_center().x-size.x*.5,bounds.end.y-size.y)
	var camera_delta := view.get_center().x-720.0
	# World texel blocks (style bible §1, rule 5): with the camera on whole
	# pixels per unit, every plate is sampled once per world unit of its own
	# extent, so a plate pixel is a figure pixel. Size stays on whole units;
	# the origin snaps to whole blocks in screen space (the camera's sub-unit
	# phase added back), so a plate that holds still on screen stays still
	# and one that scrolls moves in whole blocks instead of crawling.
	var blocks := _world_blocks()
	var phase := Vector2.ZERO
	if blocks:
		size = size.round()
		var canvas := get_global_transform_with_canvas()
		phase = Vector2(canvas.origin.x/canvas.x.x,canvas.origin.y/canvas.y.y)
	layer_rects.clear()
	for index in layers.size():
		var shift := clampf(camera_delta*GAINS[index],view.end.x+32.0-size.x-origin.x,view.position.x-32.0-origin.x)
		var layer := layers[index]
		layer.position=origin+Vector2(shift,0)
		if blocks: layer.position=(layer.position+phase).round()-phase
		layer.scale=size/layer.texture.get_size()
		layer_rects.append(Rect2(layer.position,size))
	var block := Vector2.ONE/size if blocks else Vector2.ZERO
	if block!=_world_block:
		_world_block=block
		for surface in image_materials: surface.set_shader_parameter("world_block",block)
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
	if is_instance_valid(plate_smoke):
		# Smoke steps at the 30 Hz clock tick; reduced effects hold it still.
		var smoke_at := _smoke_seconds if reduced else seconds
		if not is_equal_approx(smoke_at,_smoke_seconds) or plate_smoke.get_meta("rect",Rect2())!=layer_rects[2]:
			_smoke_seconds=smoke_at
			plate_smoke.set_meta("rect",layer_rects[2])
			plate_smoke.queue_redraw()
	mist.visible=not reduced

## Whether the plates are drawn in world texel blocks: the crisp setting (not
## --soft-backgrounds) on a whole number of physical pixels per world unit, as
## PlayerCamera settles. Below one pixel (bible §1, rule 6) or between whole
## steps no texel grid exists and the plates keep their screen-pixel sampling.
func _world_blocks() -> bool:
	if _soft: return false
	var viewport := get_viewport()
	if viewport == null: return false
	return PixelGrid.is_whole(get_global_transform_with_canvas().x.length()*viewport.get_final_transform().x.length())
