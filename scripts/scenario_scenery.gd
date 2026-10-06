class_name ScenarioScenery
extends Node2D
## Fixed painted landmarks with independently animated, pause-safe atmosphere.
static var _panorama_edges: Dictionary = {}
const PANORAMA_RECT := Rect2(-304,-253,2048,683)
const MIN_PANORAMA_WIDTH := 1728.0
const ATMOSPHERE_BOUNDS := Rect2(-1450,-500,4340,930)
const SMOKE_PUFF_COUNT := 28
const WaterArt := preload("res://scripts/water_surface_art.gd")
const CLOUD_WIDTH := 2240.0
const CLOUD_OVERLAP := 480.0
const CLOUD_PERIOD := CLOUD_WIDTH-CLOUD_OVERLAP
const CLOUD_DEPTHS := [
	{"name":"HighCirrus","speed":.22,"width":2240.0,"height":240.0,"top":-75.0,"alpha":.64,"shade":1.12,"parallax":.10},
	{"name":"MiddleCloudBanks","speed":.90,"width":1792.0,"height":235.0,"top":-10.0,"alpha":.72,"shade":.93,"parallax":.28},
	{"name":"LowWindFragments","speed":2.80,"width":1344.0,"height":170.0,"top":55.0,"alpha":.66,"shade":.78,"parallax":.52},
]
const CLOUD_COLORS := {
	"storm_dam":"#647985","sulfur_refinery":"#b7a06e","radar_highlands":"#9b96c8","buried_megafactory":"#a97677",
	"sector07":"#a28b8d","ash_foundry":"#526d85","abandoned_harbor":"#6793a1",
	"basalt_quarry":"#a698b8","overgrown_steelworks":"#9fa78e","frozen_rail_yard":"#95b9d0",
	"iron_canyon":"#c19d87","flooded_power_station":"#8ea69b","mountain_pass":"#7181ad",
}
const CLOUD_SKY_SCALE := {"storm_dam":.82,"sulfur_refinery":.72,"radar_highlands":.64,"buried_megafactory":.55,"mountain_pass":.60,"flooded_power_station":.60,"abandoned_harbor":.90,"frozen_rail_yard":.72,"iron_canyon":.80,"basalt_quarry":.80,"overgrown_steelworks":.90}
# Each climate gets a different canopy composition, not just a color swap.
# Horizontal phase, altitude offset, opacity of wisps / banks / fragments.
const UPPER_CLOUD_LAYOUTS := {
	"storm_dam":[-540.0,-80.0,Vector3(.38,.83,.58)],
	"sulfur_refinery":[680.0,-120.0,Vector3(.27,.51,.26)],
	"radar_highlands":[-170.0,-250.0,Vector3(.45,.35,.19)],
	"buried_megafactory":[1240.0,-40.0,Vector3(.37,.55,.35)],
	"sector07":[210.0,-300.0,Vector3(.36,.63,.32)],
	"ash_foundry":[-270.0,0.0,Vector3(.33,.67,.39)],
	"abandoned_harbor":[710.0,-100.0,Vector3(.35,.72,.36)],
	"basalt_quarry":[-650.0,-170.0,Vector3(.33,.58,.27)],
	"overgrown_steelworks":[130.0,50.0,Vector3(.38,.42,.20)],
	"frozen_rail_yard":[1360.0,-210.0,Vector3(.44,.46,.22)],
	"iron_canyon":[-1180.0,90.0,Vector3(.38,.31,.20)],
	"flooded_power_station":[980.0,-70.0,Vector3(.33,.78,.42)],
	"mountain_pass":[200.0,-30.0,Vector3(.25,.86,.56)],
}
const OCTAGON := [Vector2(1,0),Vector2(.707107,.707107),Vector2(0,1),Vector2(-.707107,.707107),Vector2(-1,0),Vector2(-.707107,-.707107),Vector2(0,-1),Vector2(.707107,-.707107)]
const PROFILES := {
	"storm_dam":{"kind":"water_spray","wind":24.0,"cloud_speed":25.0,"cloud_tint":"#7995a8","haze":"#8a9da9","haze_alpha":.16,"haze_y":315.0,"particles":48},
	"sulfur_refinery":{"kind":"sand","wind":14.0,"cloud_speed":18.0,"cloud_tint":"#baa064","haze":"#b8a05d","haze_alpha":.13,"haze_y":320.0,"particles":46},
	"radar_highlands":{"kind":"snow","wind":18.0,"cloud_speed":21.0,"cloud_tint":"#9e9bbd","haze":"#888eae","haze_alpha":.12,"haze_y":325.0,"particles":65},
	"buried_megafactory":{"kind":"grit","wind":12.0,"cloud_speed":17.0,"cloud_tint":"#ac8385","haze":"#a07969","haze_alpha":.12,"haze_y":320.0,"particles":42},
	"sector07":{"kind":"soot","wind":8.0,"cloud_speed":14.0,"cloud_tint":"#8295aa","haze":"#647584","haze_alpha":0.10,"haze_y":300.0,"particles":34},
	"ash_foundry":{"kind":"embers","wind":13.0,"cloud_speed":16.0,"cloud_tint":"#9a8b81","haze":"#9c735e","haze_alpha":0.13,"haze_y":285.0,"particles":58},
	"abandoned_harbor":{"kind":"sea_spray","wind":17.0,"cloud_speed":19.0,"cloud_tint":"#809cad","haze":"#759dac","haze_alpha":0.18,"haze_y":340.0,"particles":34},
	"basalt_quarry":{"kind":"grit","wind":10.0,"cloud_speed":15.0,"cloud_tint":"#979494","haze":"#9a9080","haze_alpha":0.13,"haze_y":320.0,"particles":48},
	"overgrown_steelworks":{"kind":"leaves","wind":11.0,"cloud_speed":14.0,"cloud_tint":"#9ba78c","haze":"#819881","haze_alpha":0.11,"haze_y":315.0,"particles":42},
	"frozen_rail_yard":{"kind":"snow","wind":9.0,"cloud_speed":17.0,"cloud_tint":"#a2b8d0","haze":"#acbed0","haze_alpha":0.15,"haze_y":350.0,"particles":105},
	"iron_canyon":{"kind":"sand","wind":22.0,"cloud_speed":22.0,"cloud_tint":"#bb9983","haze":"#b78c65","haze_alpha":0.16,"haze_y":290.0,"particles":68},
	"flooded_power_station":{"kind":"water_spray","wind":8.0,"cloud_speed":15.0,"cloud_tint":"#87a6b4","haze":"#89b5b8","haze_alpha":0.19,"haze_y":325.0,"particles":40},
	"mountain_pass":{"kind":"storm_mist","wind":26.0,"cloud_speed":24.0,"cloud_tint":"#8b9fb8","haze":"#8295aa","haze_alpha":0.22,"haze_y":245.0,"particles":38},
}
var game
var environment_id := "ash_foundry"
var offset := Vector2.ZERO
var elapsed := 0.0
var data: Dictionary
var profile: Dictionary
var continuous_background := false
var parallax_background: Node2D
var layered_enabled := true
var adaptive_background := true
var panorama_rect := PANORAMA_RECT
var panorama: Sprite2D
var mist_layer: Node2D
var sky_material: ShaderMaterial
var cloud_layer: Node2D
var cloud_layers: Array[Node2D] = []
var cloud_depth_texture: Texture2D
var cloud_texture: Texture2D
var particle_layer: Node2D
var surface_layer: Node2D
var props_layer: Node2D
var vegetation_layer: Node2D
var fauna_layer: Node2D
var lighting_layer: Node2D
var edge_colors: Array[PackedColorArray] = []
var _visible_rect := ATMOSPHERE_BOUNDS
var _sector_cloud_texture: Texture2D
var smoke_nodes: Array[MeshInstance2D] = []
var _smoke_materials: Array[ShaderMaterial] = []
var _wind := 8.0
var _haze := Color.WHITE
var _has_surface := false
var _last_reduced := false
var _last_edge_fade := -1.0
const CloudMotion := preload("res://scripts/cloud_motion.gd")
var cloud_motion := CloudMotion.new()
var _cloud_camera_x := 0.0
var upper_sky: Node2D
var distant_horizon: Node2D
var distant_water: Node2D
var frozen_outskirts: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# PlayerCamera settles its transform at priority 100. Frame the panorama
	# afterwards so a moving/zooming camera never exposes the previous frame.
	process_priority = 110
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	data = ScenarioCatalog.environment(environment_id)
	continuous_background = bool(data.get("continuous_background",false))
	profile = PROFILES.get(environment_id,PROFILES.sector07).duplicate()
	_wind = float(profile.wind)
	_haze = Color(profile.haze)
	_has_surface = not data.get("water_regions",[]).is_empty() or not data.get("waterfall_regions",[]).is_empty()
	_last_reduced = reduced()
	if data.has("city_path"):
		_sector_cloud_texture = ScenarioCatalog.texture(str(data.get("cloud_path","res://assets/atmosphere/clouds.png")))
	panorama = Sprite2D.new()
	panorama.name = "SelectedPanorama"
	panorama.centered = false
	panorama.texture = ScenarioCatalog.texture(str(data.get("city_path",data.path)))
	if continuous_background:
		panorama.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if panorama.texture != null:
		# Keep source proportions. Per-image framing can place calm lower art
		# behind terrain so tall mountain peaks remain visible above the bunker.
		# A QHD window exposes 1600 logical world pixels. Keep the initial
		# 3.5% edge blend beyond that view, with the authored bottom unchanged.
		var width := maxf(MIN_PANORAMA_WIDTH,float(data.get("framing_width",2048.0)))
		var bottom := float(data.get("framing_bottom",430.0))
		var height := width*panorama.texture.get_height()/panorama.texture.get_width()
		panorama_rect = Rect2(720-width*.5,bottom-height,width,height)
		panorama.scale = Vector2.ONE*(width/panorama.texture.get_width())
	panorama.position = panorama_rect.position
	_prepare_edge_colors()
	upper_sky = preload("res://scripts/sky_vault.gd").new()
	upper_sky.configure(self)
	add_child(upper_sky)
	distant_water = preload("res://scripts/distant_water.gd").new()
	distant_water.configure(self)
	add_child(distant_water)
	distant_horizon = preload("res://scripts/distant_horizon.gd").new()
	distant_horizon.name = "ExtendedLandscape"
	distant_horizon.configure(self)
	add_child(distant_horizon)
	frozen_outskirts = preload("res://scripts/frozen_outskirts.gd").new()
	frozen_outskirts.name = "ExtendedWinterOutskirts"
	frozen_outskirts.configure(self)
	add_child(frozen_outskirts)
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/scenario_sky.gdshader")
	sky_material.set_shader_parameter("sky_cutoff",float(data.get("sky_cutoff",.32)))
	var water_regions: Array = data.get("water_regions",[])
	if not water_regions.is_empty():
		var water: Array = water_regions[0]
		sky_material.set_shader_parameter("water_bounds",Vector4(float(water[0]),float(water[1]),float(water[2]),float(water[3])))
	sky_material.set_shader_parameter("water_amplitude",.45 if _last_reduced else 4.5)
	sky_material.set_shader_parameter("water_glint",.012 if _last_reduced else .070)
	sky_material.set_shader_parameter("water_turbulence",.85 if environment_id=="flooded_power_station" else .45)
	sky_material.set_shader_parameter("edge_fade",0.0 if continuous_background else .035)
	if continuous_background: sky_material.set_shader_parameter("top_fade",0.0)
	panorama.material = sky_material
	add_child(panorama)
	cloud_texture = ScenarioCatalog.texture("res://assets/environments/cloud_wisps.png")
	cloud_depth_texture = ScenarioCatalog.texture("res://assets/atmosphere/cloud_depths.png")
	cloud_layer = Node2D.new()
	cloud_layer.name = "MovingCloudDepths"
	add_child(cloud_layer)
	if data.has("city_path"):
		# Upper sky is opaque; the original sunset clouds belong above it and
		# behind both the extended landscape and transparent city silhouette.
		move_child(cloud_layer,1)
	for depth in CLOUD_DEPTHS.size():
		var definition: Dictionary = CLOUD_DEPTHS[depth]
		var layer := Node2D.new()
		layer.name = definition.name
		if data.has("city_path") and depth==0:
			layer.name = "DistantSunsetBanks"
			var painted_cloud := ShaderMaterial.new()
			painted_cloud.shader = preload("res://shaders/scenario_cloud.gdshader")
			painted_cloud.set_shader_parameter("preserve_painted_color",true)
			painted_cloud.set_shader_parameter("cloud_tint",Color.WHITE)
			layer.material = painted_cloud
		else:
			var cloud_material := ShaderMaterial.new()
			cloud_material.shader = preload("res://shaders/scenario_cloud.gdshader")
			var tint := Color(CLOUD_COLORS.get(environment_id,"#83919f"))*float(definition.shade)
			tint.a = float(definition.alpha)
			if environment_id=="sector07": tint.a *= .88
			cloud_material.set_shader_parameter("cloud_tint",tint)
			cloud_material.set_shader_parameter("cloud_phase",depth*3.71+float(posmod(environment_id.hash(),13))*.37)
			cloud_material.set_shader_parameter("panorama_bounds",Vector4(panorama_rect.position.x,panorama_rect.position.y,panorama_rect.size.x,panorama_rect.size.y))
			cloud_material.set_shader_parameter("mask_landmarks",not data.has("city_path"))
			if not data.has("city_path"):
				cloud_material.set_shader_parameter("skyline",preload("res://scripts/cloud_skyline.gd").texture(environment_id))
				distant_horizon.configure_cloud_mask(cloud_material)
			layer.material = cloud_material
		layer.draw.connect(_draw_cloud_depth.bind(layer,depth))
		cloud_layer.add_child(layer)
		cloud_layers.append(layer)
	lighting_layer = preload("res://scripts/scenario_lighting.gd").new()
	lighting_layer.name = "AuthoredWorldLighting"
	lighting_layer.scenery = self
	add_child(lighting_layer)
	surface_layer = Node2D.new()
	surface_layer.name = "DistantWater"
	var water_sprite_material := ShaderMaterial.new()
	water_sprite_material.shader = preload("res://shaders/water_sprite.gdshader")
	surface_layer.material = water_sprite_material
	surface_layer.draw.connect(_draw_water)
	add_child(surface_layer)
	mist_layer = Node2D.new()
	mist_layer.name = "HorizonMistAndExhaust"
	mist_layer.draw.connect(_draw_mist)
	add_child(mist_layer)
	_prepare_smoke()
	particle_layer = Node2D.new()
	particle_layer.name = "BiomeParticles"
	particle_layer.draw.connect(_draw_particles)
	add_child(particle_layer)
	props_layer = preload("res://scripts/scenario_props.gd").new()
	props_layer.name = "AnimatedBiomeProps"
	props_layer.game = game
	props_layer.environment_id = environment_id
	add_child(props_layer)
	vegetation_layer = preload("res://scripts/living_vegetation.gd").new()
	vegetation_layer.name = "LivingVegetation"
	vegetation_layer.configure(game,environment_id)
	add_child(vegetation_layer)
	fauna_layer = preload("res://scripts/living_fauna.gd").new()
	fauna_layer.name = "LivingFauna"
	fauna_layer.configure(game,environment_id)
	add_child(fauna_layer)
	_visible_rect = (get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()).grow(64)
	if adaptive_background and continuous_background and preload("res://scripts/parallax_catalog.gd").available(environment_id):
		parallax_background=preload("res://scripts/parallax_landscape.gd").new()
		parallax_background.name="LandscapeDepths"
		parallax_background.configure(environment_id)
		add_child(parallax_background)
		move_child(parallax_background,get_children().find(panorama)+1)
		layered_enabled=not "--flat-backgrounds" in OS.get_cmdline_user_args()
		if environment_id=="mountain_pass" and "--flat-mountain-pass" in OS.get_cmdline_user_args():layered_enabled=false
	_update_background_view(_last_reduced)
	queue_redraw()

func reduced() -> bool:
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(parallax_background) or not event.is_action_pressed("parallax_preview"): return
	set_layered_enabled(not layered_enabled)
	get_viewport().set_input_as_handled()
	if is_instance_valid(game) and game.has_method("notify"):
		game.notify(LocaleText.text("Bewegte Tiefenebenen · F8: vergleichen" if layered_enabled else "Ursprüngliches Panorama · F8: vergleichen"))

func set_layered_enabled(value: bool) -> void:
	layered_enabled=value
	_update_background_view(reduced())

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var is_reduced := reduced()
	var cloud_delta := delta*(.25 if is_reduced else 1.0)
	elapsed += cloud_delta
	var weather: Node = game.weather if is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) else null
	cloud_motion.advance(cloud_delta,[cloud_speed(0),cloud_speed(1),cloud_speed(2)],weather)
	var half_view := get_viewport_rect().size*.5
	var mouse := (get_viewport().get_mouse_position()-half_view)/half_view
	var target := Vector2(clampf(mouse.x,-1,1)*12,clampf(mouse.y,-1,1)*5)
	if is_reduced: target = Vector2.ZERO
	offset = offset.lerp(target,1.0-exp(-delta*2.0))
	# Only air follows the pointer. Industrial silhouettes never translate or
	# wrap with cloud UVs, even when the camera opens up for a deeper bunker.
	sky_material.set_shader_parameter("sky_clock",elapsed)
	if is_reduced!=_last_reduced:
		_last_reduced = is_reduced
		sky_material.set_shader_parameter("water_amplitude",.45 if is_reduced else 4.5)
		sky_material.set_shader_parameter("water_glint",.012 if is_reduced else .070)
	var zoom := 1.0
	if is_instance_valid(game) and "camera" in game and is_instance_valid(game.camera):
		zoom = game.camera.zoom.x
		_cloud_camera_x = game.camera.global_position.x-720.0
	var edge_fade := 0.0 if continuous_background else lerpf(.035,.18,clampf((1.0-zoom)/.52,0,1))
	if not is_equal_approx(edge_fade,_last_edge_fade):
		_last_edge_fade = edge_fade
		sky_material.set_shader_parameter("edge_fade",edge_fade)
		lighting_layer.set_edge_fade(edge_fade)
		for layer in cloud_layers:
			if layer.material is ShaderMaterial:
				layer.material.set_shader_parameter("panorama_edge_fade",edge_fade)
	_visible_rect = (get_global_transform_with_canvas().affine_inverse()*get_viewport_rect()).grow(64)
	_update_background_view(is_reduced)
	lighting_layer.update_lighting(elapsed,is_reduced)
	_redraw_clouds()
	mist_layer.queue_redraw()
	particle_layer.queue_redraw()
	if _has_surface and surface_layer.visible: surface_layer.queue_redraw()

func cloud_offset(depth: int) -> float:
	return fposmod(elapsed*cloud_speed(depth)+cloud_motion.wind_distance[depth]+depth*410.0,cloud_period(depth))

func cloud_speed(depth: int) -> float:
	return float(profile.cloud_speed)*float(CLOUD_DEPTHS[depth].speed)

func cloud_camera_offset(depth: int) -> float:
	return CloudMotion.camera_offset(depth,_cloud_camera_x)

func cloud_period(depth: int) -> float:
	return float(CLOUD_DEPTHS[depth].width)*(CLOUD_PERIOD/CLOUD_WIDTH)

func _redraw_clouds() -> void:
	update_cloud_shape(elapsed, reduced())
	for layer in cloud_layers: layer.queue_redraw()

func update_cloud_shape(at: float, is_reduced: bool, wind: float = -1.0) -> void:
	if wind < 0.0:
		wind = float(game.weather.wind_strength()) if is_instance_valid(game) and is_instance_valid(game.get("weather")) and game.weather.has_method("wind_strength") else 0.0
	for layer in cloud_layers:
		var cloud_material: ShaderMaterial = layer.material
		if cloud_material == null: continue
		cloud_material.set_shader_parameter("cloud_clock", at)
		cloud_material.set_shader_parameter("cloud_morph_strength", .16 if is_reduced else 1.0)
		cloud_material.set_shader_parameter("cloud_wind", clampf(wind, 0, 1))

func particle_count() -> int:
	return floori(int(profile.particles)/3.0) if reduced() else int(profile.particles)

func particle_sample(index: int) -> Dictionary:
	var particle_seed := float(index)*137.50776
	var depth := .45+fposmod(particle_seed*.017,.55)
	var kind := str(profile.kind)
	var speed := _wind*depth
	var x := ATMOSPHERE_BOUNDS.position.x+fposmod(particle_seed*29.0+elapsed*speed,ATMOSPHERE_BOUNDS.size.x)
	var y := -100.0+fposmod(particle_seed*7.0+elapsed*(14.0+depth*16.0),525.0)
	var color := _haze
	var size := 1.0 if index%3 else 2.0
	match kind:
		"embers", "soot":
			y = -100.0+fposmod(particle_seed*7.0-elapsed*(9.0+depth*10.0),525.0)
			color = Color("e3a169") if kind=="embers" and index%4==0 else Color("99978c")
		"snow":
			x += sin(elapsed*1.2+particle_seed)*8.0*depth
			color = Color("c5d5e2")
		"leaves":
			x += sin(elapsed*1.6+particle_seed)*10.0
			y += sin(elapsed*2.0+particle_seed)*4.0
			color = Color("94a477") if index%2 else Color("b0a66c")
			size = 2.0
		"grit", "sand":
			y = 240.0+fposmod(particle_seed*7.0,180.0)+sin(elapsed*.65+particle_seed)*7.0
			color = Color("bba382") if kind=="sand" else Color("a5a093")
		_:
			y = 230.0+fposmod(particle_seed*7.0,185.0)+sin(elapsed*.7+particle_seed)*7.0
	var edge := smoothstep(-100.0,-60.0,y)*(1.0-smoothstep(390.0,430.0,y))
	color.a = (.20+depth*.25)*edge
	if kind in ["embers","soot"] and is_instance_valid(parallax_background) and layered_enabled and parallax_background.sky_traffic.visible:
		# Remote lights belong between sky depths. Ground-level ash remains in
		# front of the scene; rain, snow, leaves and grit keep their own paths.
		color.a*=smoothstep(170.0,240.0,y)
	return {"position":Vector2(x-offset.x*depth*.2,y).round(),"size":size,"color":color,"phase":particle_seed+elapsed*2.4}

func smoke_anchor(index: int) -> Vector2:
	var anchor: Array = data.get("smoke_anchors",[])[index]
	return panorama_rect.position+Vector2(float(anchor[0]),float(anchor[1]))*panorama_rect.size

func smoke_sample(emitter: int,index: int) -> Dictionary:
	var life := 12.0+emitter*.7
	var age := fposmod(elapsed+index*life/SMOKE_PUFF_COUNT,life)
	var progress := age/life
	var point := smoke_anchor(emitter)+Vector2(age*_wind*.48+sin(age*.7+emitter)*age*.7,-age*13.0)
	return {"position":point.round(),"size":4.0+progress*25.0,"alpha":smoothstep(0.0,.035,progress)*pow(1.0-progress,1.1)*.58,"phase":index+emitter*7}

func _prepare_smoke() -> void:
	var emitter_count: int = data.get("smoke_anchors",[]).size()
	if emitter_count==0: return
	# Keep all 28 puffs and five pixel-rounded octagons per puff in a shared
	# immutable mesh. Animation changes five uniforms, not 700 draw polygons.
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var base := Color("abb6bb") if environment_id=="frozen_rail_yard" else _haze.darkened(.28)
	for puff in SMOKE_PUFF_COUNT:
		for cluster in 5:
			var first := vertices.size()
			for direction: Vector2 in OCTAGON:
				vertices.append(Vector3(direction.x,direction.y,0))
				uvs.append(Vector2(puff,cluster))
				colors.append(base.lightened(.03*(cluster%3)))
			for triangle in range(1,7):
				indices.append_array(PackedInt32Array([first,first+triangle,first+triangle+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	# Vertex motion can leave the unit mesh. Include the complete plume in its
	# culling bounds so chimneys just outside the viewport still emit smoke.
	var max_life := 12.0+(emitter_count-1)*.7
	var drift := max_life*_wind*.48
	var margin := max_life*.7+40.0
	mesh.custom_aabb = AABB(Vector3(minf(0,drift)-margin,-max_life*13.0-40,-1),Vector3(absf(drift)+margin*2,max_life*13.0+80,2))
	for emitter in emitter_count:
		var smoke := MeshInstance2D.new()
		smoke.name = "ChimneySmoke%d"%emitter
		smoke.mesh = mesh
		smoke.position = smoke_anchor(emitter)
		var smoke_material := ShaderMaterial.new()
		smoke_material.shader = preload("res://shaders/scenario_smoke.gdshader")
		smoke_material.set_shader_parameter("smoke_origin",smoke.position)
		smoke_material.set_shader_parameter("smoke_wind",_wind)
		smoke_material.set_shader_parameter("emitter_index",float(emitter))
		smoke.material = smoke_material
		mist_layer.add_child(smoke)
		smoke_nodes.append(smoke)
		_smoke_materials.append(smoke_material)

func region_rect(region: Array) -> Rect2:
	return Rect2(panorama_rect.position+Vector2(float(region[0]),float(region[1]))*panorama_rect.size,Vector2(float(region[2]),float(region[3]))*panorama_rect.size)

func _prepare_edge_colors() -> void:
	if _panorama_edges.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/panorama_edges.json"))
		if parsed is Dictionary: _panorama_edges=parsed.get("environments",{})
	edge_colors.clear()
	var prepared: Dictionary=_panorama_edges.get(environment_id,{})
	for side: Array in prepared.get("colors",[]):
		var colors:=PackedColorArray()
		for rgba: Array in side: colors.append(Color(float(rgba[0]),float(rgba[1]),float(rgba[2]),float(rgba[3])))
		edge_colors.append(colors)

func _edge_color(y: float,side: int) -> Color:
	if edge_colors.is_empty(): return Color(str(data.get("sky_color","#25303d")))
	var at := clampf((y-panorama_rect.position.y)/panorama_rect.size.y,0,1)*16.0
	var index := mini(int(at),15)
	return edge_colors[side][index].lerp(edge_colors[side][index+1],at-index)

func _draw() -> void:
	var sky := Color(str(data.get("sky_color","#25303d")))
	draw_rect(Rect2(-8192,-8192,17824,8622),sky)

func _draw_cloud_depth(layer: Node2D,depth: int) -> void:
	if cloud_depth_texture == null: return
	_draw_upper_clouds(layer,depth)
	if data.has("city_path") and depth==0:
		_draw_sector_clouds(layer)
		return
	var definition: Dictionary = CLOUD_DEPTHS[depth]
	var band_height := cloud_depth_texture.get_height()/3.0
	var source := Rect2(0,depth*band_height,cloud_depth_texture.get_width(),band_height)
	var period := cloud_period(depth)
	var shift := floorf(cloud_offset(depth)+cloud_camera_offset(depth))-offset.x*float(definition.parallax)
	var vertical_scale := float(CLOUD_SKY_SCALE.get(environment_id,1.0))
	var first_tile := floori((_visible_rect.position.x+900-shift-float(definition.width))/period)
	var last_tile := ceili((_visible_rect.end.x+900-shift)/period)
	for tile in range(first_tile,last_tile+1):
		var rect := Rect2(-900+tile*period+shift,float(definition.top)*vertical_scale-offset.y*float(definition.parallax),float(definition.width),float(definition.height)*vertical_scale)
		if not rect.intersects(_visible_rect): continue
		layer.draw_texture_rect_region(cloud_depth_texture,rect,source)

func upper_cloud_tiles(depth: int,view: Rect2) -> Array[Dictionary]:
	# Cloud canopies occupy altitude as well as the horizon. Unequal spacing,
	# size and phase avoid a repeated stack of identical horizontal bands.
	var result: Array[Dictionary] = []
	var widths := [3100.0,2560.0,1980.0]
	var heights := [390.0,620.0,430.0]
	var intervals := [1120.0,1370.0,1060.0]
	var tops := [-650.0,-980.0,-520.0]
	var layout: Array = UPPER_CLOUD_LAYOUTS.get(environment_id,UPPER_CLOUD_LAYOUTS.sector07)
	var width: float = widths[depth]
	var height: float = heights[depth]
	var interval: float = intervals[depth]
	var period := width*.78
	var camera_drift := cloud_camera_offset(depth)
	var travel := elapsed*cloud_speed(depth)+cloud_motion.wind_distance[depth]
	var base_top: float = tops[depth]+float(layout[1])*(1.0-depth*.25)
	var first_row := maxi(0,floori((base_top-95.0-view.end.y)/interval))
	var last_row := maxi(-1,ceili((base_top+95.0+height-view.position.y)/interval))
	for row in range(first_row,mini(first_row+8,last_row+1)):
		# Keep the unwrapped position: the tile's height must stay attached to
		# that cloud when a full horizontal period passes.
		var shift := travel+row*937.0+depth*529.0+float(layout[0])*(1.0+depth*.34)+camera_drift
		var first_tile := floori((view.position.x-shift-width)/period)
		var last_tile := ceili((view.end.x-shift)/period)
		for tile in range(first_tile,mini(first_tile+12,last_tile+1)):
			var top: float = base_top-row*interval+sin(row*2.3+tile*1.7+depth)*95.0
			var rect := Rect2(Vector2(tile*period+shift,top).floor(),Vector2(width,height))
			if not rect.intersects(view): continue
			var opacity: float = layout[2][depth]
			result.append({"rect":rect,"alpha":opacity,"row":row})
	return result

func _draw_upper_clouds(layer: Node2D,depth: int) -> void:
	var band_height := cloud_depth_texture.get_height()/3.0
	var source := Rect2(0,depth*band_height,cloud_depth_texture.get_width(),band_height)
	for cloud in upper_cloud_tiles(depth,_visible_rect):
		var tint := Color(1,1,1,float(cloud.alpha))
		if data.has("city_path") and depth==0:
			tint = Color("8993a1",float(cloud.alpha))
		layer.draw_texture_rect_region(cloud_depth_texture,cloud.rect,source,tint)

func _draw_sector_clouds(layer: Node2D) -> void:
	var texture := _sector_cloud_texture
	if texture == null: return
	var size := Vector2(CLOUD_WIDTH,panorama_rect.size.y)
	var tint := Color(.83,.88,.95,.90)
	var shift := floorf(cloud_offset(0)+cloud_camera_offset(0))
	var first_tile := floori((_visible_rect.position.x+900-shift-size.x)/CLOUD_PERIOD)
	var last_tile := ceili((_visible_rect.end.x+900-shift)/CLOUD_PERIOD)
	for tile in range(first_tile,last_tile+1):
		var origin := Vector2(-900+tile*CLOUD_PERIOD+shift,panorama_rect.position.y)
		if not Rect2(origin,size).intersects(_visible_rect): continue
		var stops := [0.0,CLOUD_OVERLAP,size.x-CLOUD_OVERLAP,size.x]
		var opacity := [0.0,1.0,1.0,0.0]
		for strip in 3:
			var left: float = stops[strip]
			var right: float = stops[strip+1]
			var points := PackedVector2Array([origin+Vector2(left,0),origin+Vector2(right,0),origin+Vector2(right,size.y),origin+Vector2(left,size.y)])
			var a := Color(tint,tint.a*opacity[strip])
			var b := Color(tint,tint.a*opacity[strip+1])
			var uv := PackedVector2Array([Vector2(left/size.x,0),Vector2(right/size.x,0),Vector2(right/size.x,1),Vector2(left/size.x,1)])
			layer.draw_polygon(points,PackedColorArray([a,b,b,a]),uv,texture)

func _draw_mist() -> void:
	var is_reduced := reduced()
	if cloud_texture != null:
		var tint := Color(_haze,float(profile.haze_alpha))
		if is_reduced: tint.a *= .55
		for band in 2:
			var shift := fposmod(elapsed*_wind*(.24+band*.16),CLOUD_PERIOD)
			for tile in range(-2,3):
				var origin := Vector2(-900+tile*CLOUD_PERIOD+shift,float(profile.haze_y)-band*60.0)
				var size := Vector2(CLOUD_WIDTH,95+band*35)
				if Rect2(origin,size).intersects(_visible_rect): _draw_faded_wisp(origin,size,tint,band)
	for smoke_material in _smoke_materials:
		smoke_material.set_shader_parameter("smoke_clock",elapsed)
		smoke_material.set_shader_parameter("reduced_effects",is_reduced)

func _draw_faded_wisp(origin: Vector2,size: Vector2,tint: Color,band: int) -> void:
	# Adjacent non-seamless image copies crossfade over a broad overlap.
	var stops := [0.0,CLOUD_OVERLAP,size.x-CLOUD_OVERLAP,size.x]
	var opacity := [0.0,1.0,1.0,0.0]
	var texture_height := float(cloud_texture.get_height())
	var top := (0.0 if band==0 else 350.0)/texture_height
	var bottom := minf(1.0,top+340.0/texture_height)
	for strip in 3:
		var a: float = stops[strip]
		var b: float = stops[strip+1]
		var points := PackedVector2Array([origin+Vector2(a,0),origin+Vector2(b,0),origin+Vector2(b,size.y),origin+Vector2(a,size.y)])
		var left := Color(tint,tint.a*opacity[strip])
		var right := Color(tint,tint.a*opacity[strip+1])
		var uv := PackedVector2Array([Vector2(a/size.x,top),Vector2(b/size.x,top),Vector2(b/size.x,bottom),Vector2(a/size.x,bottom)])
		mist_layer.draw_polygon(points,PackedColorArray([left,right,right,left]),uv,cloud_texture)

func _draw_particles() -> void:
	for index in particle_count():
		var sample := particle_sample(index)
		var point: Vector2 = sample.position
		var color: Color = sample.color
		if color.a<.005 or not _visible_rect.has_point(point): continue
		var size: float = sample.size
		if profile.kind=="leaves":
			var width := 1.0+absf(sin(float(sample.phase)))*3.0
			particle_layer.draw_line(point,point+Vector2(width,1),color,1)
			particle_layer.draw_rect(Rect2(point+Vector2(1,-1),Vector2(2,2)),Color(color,color.a*.65))
		else:
			particle_layer.draw_rect(Rect2(point,Vector2(size,size)),color)

func _draw_water() -> void:
	# Reflective swells live in the panorama shader; authored foam and short
	# expanding rain rings add separate near-surface motion at bounded cost.
	var is_reduced := reduced()
	for region: Array in data.get("water_regions",[]):
		var rect := region_rect(region)
		rect.size.y = minf(rect.size.y,430.0-rect.position.y)
		if rect.size.y<4.0: continue
		if not rect.intersects(_visible_rect): continue
		for index in range(0,28,3 if is_reduced else 1):
			var sample := water_crest_sample(rect,index)
			if not sample.rect.intersects(_visible_rect): continue
			var tint := Color("86b5c3") if environment_id=="abandoned_harbor" else Color("b0cbb6")
			tint.a = float(sample.alpha)*(.6 if is_reduced else 1.0)
			WaterArt.draw_effect(surface_layer,sample.rect,0,float(sample.phase),tint)
		# Low outlets break the water immediately below the spillway
		# mouths. The raised masonry and reservoir shoreline remain untouched.
		for source: Array in data.get("water_outlets",[]):
			var anchor := panorama_rect.position+Vector2(float(source[0]),float(source[1]))*panorama_rect.size
			# Foam stays entirely on the selected surface, including when the
			# panorama scales or an annotation is replaced with a new shoreline.
			if not rect.has_point(anchor): continue
			if not _visible_rect.grow(36).has_point(anchor): continue
			var phase := fposmod(elapsed*.68+float(source[0])*3.7,1.0)
			var width := float(source[2])*panorama_rect.size.x
			var tint := Color("b6d3c2",.38 if is_reduced else .68)
			var foam := Rect2(anchor-Vector2(width*.5,10),Vector2(width,21)).intersection(rect)
			WaterArt.draw_effect(surface_layer,foam,1,phase,tint)
			if not is_reduced:
				var wake := Rect2(anchor-Vector2(width*.74,-2),Vector2(width*1.5,15))
				wake = wake.intersection(rect)
				WaterArt.draw_effect(surface_layer,wake,0,fposmod(phase+.4,1.0),Color("bdd5c2",.36))
		if float(data.get("rain_strength",0.0))>0.0:
			for index in range(0,26,4 if is_reduced else 1):
				var sample := water_rain_sample(rect,index)
				if not sample.rect.intersects(_visible_rect): continue
				WaterArt.draw_effect(surface_layer,sample.rect,2,float(sample.phase),Color(.80,.96,.92,float(sample.alpha)*(.5 if is_reduced else 1.0)))
	for region: Array in data.get("waterfall_regions",[]):
		var rect := region_rect(region)
		if not rect.intersects(_visible_rect): continue
		for index in range(0,36,3 if is_reduced else 1):
			var ripple_seed := index*137.50776
			var progress := fposmod(ripple_seed*.13+elapsed*(.27+fposmod(ripple_seed,.2)),1.0)
			var point := rect.position+Vector2(fposmod(ripple_seed*11.0,maxf(1,rect.size.x-2)),progress*maxf(1,rect.size.y-8))
			var alpha := sin(progress*PI)*(.13 if is_reduced else .30)
			if alpha<.005 or not _visible_rect.has_point(point): continue
			surface_layer.draw_rect(Rect2(point.round(),Vector2(1+index%2,3+index%5)),Color(_haze.lightened(.25),alpha))

func water_crest_sample(rect: Rect2,index: int) -> Dictionary:
	var seed_value := float(index)*137.50776
	var depth := .08+fposmod(seed_value*.017,.84)
	var phase := fposmod(elapsed*(.16+depth*.08)+seed_value*.13,1.0)
	var size := Vector2(34+depth*62,9+depth*19)
	var travel := fposmod(seed_value*17.0+elapsed*(5.0+depth*9.0),rect.size.x+size.x)
	var point := rect.position+Vector2(travel-size.x,depth*maxf(1,rect.size.y-size.y))
	var alpha := sin(phase*PI)*(.24+depth*.35)
	alpha *= smoothstep(rect.position.x,rect.position.x+28,point.x)*(1.0-smoothstep(rect.end.x-size.x-28,rect.end.x-size.x,point.x))
	return {"rect":Rect2(point.round(),size),"phase":phase,"alpha":alpha}

func water_rain_sample(rect: Rect2,index: int) -> Dictionary:
	var seed_value := float(index)*97.307
	var cycle := elapsed*.43+seed_value*.13
	var phase := fposmod(cycle,1.0)
	var depth := .10+fposmod(seed_value*.019,.75)
	var width := (10.0+depth*19.0)*(.55+phase*.70)
	var size := Vector2(width,4.0+depth*6.0)
	var point := rect.position+Vector2(16+fposmod(seed_value*17.0+floorf(cycle)*71.0,rect.size.x-width-32.0),depth*(rect.size.y-size.y))
	return {"rect":Rect2(point.round(),size),"phase":phase,"alpha":sin(phase*PI)*.76}

func _update_background_view(is_reduced: bool) -> void:
	if continuous_background:
		for layer in [upper_sky,distant_water,distant_horizon,frozen_outskirts,cloud_layer]: layer.hide()
		if adaptive_background and panorama.texture != null:
			var magnification := get_global_transform_with_canvas().x.length()
			panorama_rect = preload("res://scripts/background_layout.gd").frame(_visible_rect,float(panorama.texture.get_width())/panorama.texture.get_height(),magnification)
			panorama.position = panorama_rect.position
			panorama.scale = Vector2.ONE * panorama_rect.size.x / panorama.texture.get_width()
		if is_instance_valid(parallax_background):
			parallax_background.visible=layered_enabled
			panorama.visible=not layered_enabled
			lighting_layer.effects_enabled=not layered_enabled
			lighting_layer.visible=not layered_enabled and not is_reduced
			surface_layer.visible=not layered_enabled
			mist_layer.visible=not layered_enabled
			for smoke in smoke_nodes:smoke.visible=not layered_enabled
			if layered_enabled: parallax_background.update_view(panorama_rect,_visible_rect,elapsed,is_reduced)
		return
	upper_sky.update_view(_visible_rect)
	distant_water.update_view(_visible_rect,elapsed,is_reduced)
	distant_horizon.update_view(_visible_rect)
	frozen_outskirts.update_view(_visible_rect)
