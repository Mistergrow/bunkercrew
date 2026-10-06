extends Node2D
## Small effects attached to authored landmarks. Uses only preview time and
## original image pixels; it neither starts machinery nor touches game state.
const Catalog := preload("res://scripts/menu_landmark_catalog.gd")
const PIXEL_EFFECT := preload("res://shaders/menu_landmark.gdshader")
const SMOKE := preload("res://shaders/menu_smoke.gdshader")
const OCTAGON := [Vector2(-1,-.4),Vector2(-.4,-1),Vector2(.4,-1),Vector2(1,-.4),Vector2(1,.4),Vector2(.4,1),Vector2(-.4,1),Vector2(-1,.4)]
var scenery: Node2D
var definition: Dictionary = {}
var patches: Array[Dictionary] = []
var banks: Array[Dictionary] = []
var plumes: Array[MeshInstance2D] = []
var elapsed := 0.0
var reduced := false

func _ready() -> void:
	name = "MenuLandmarkDetails"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	definition = Catalog.details(scenery.environment_id)
	for entry: Array in definition.get("lights",[]):
		var rect := Rect2(float(entry[0])-float(entry[2]),float(entry[1])-float(entry[3]),float(entry[2])*2,float(entry[3])*2)
		_make_patch(rect,0,str(entry[4]))
	for entry: Array in definition.get("flows",[]):
		_make_patch(Rect2(float(entry[0]),float(entry[1]),float(entry[2]),float(entry[3])),1,"water")
	for entry: Array in definition.get("foliage",[]):
		_make_patch(Rect2(float(entry[0]),float(entry[1]),float(entry[2]),float(entry[3])),2,"ivy")
	for entry: Array in definition.get("vapor",[]):
		_make_patch(Rect2(float(entry[0]),float(entry[1]),float(entry[2]),float(entry[3])),3,"vapor")
	for entry: Array in definition.get("banks",[]): _make_bank(entry)
	for entry: Array in definition.get("plumes",[]): _make_plume(entry)
	update_at(float(scenery.elapsed),scenery.reduced(),0.0)

func _make_patch(pixels: Rect2,effect: int,kind: String) -> void:
	var uv := Catalog.region(pixels)
	var sprite := Sprite2D.new()
	sprite.name = "PaintedDetail%d"%patches.size()
	sprite.texture = scenery.panorama.texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(uv.position*sprite.texture.get_size(),uv.size*sprite.texture.get_size())
	sprite.position = scenery.panorama_rect.position+uv.position*scenery.panorama_rect.size
	sprite.scale = scenery.panorama_rect.size/sprite.texture.get_size()
	var pixel_material := ShaderMaterial.new()
	pixel_material.shader = PIXEL_EFFECT
	pixel_material.set_shader_parameter("source_region",Vector4(uv.position.x,uv.position.y,uv.size.x,uv.size.y))
	pixel_material.set_shader_parameter("effect",effect)
	pixel_material.set_shader_parameter("white_light",kind=="white")
	pixel_material.set_shader_parameter("phase",patches.size()*1.73)
	sprite.material = pixel_material
	add_child(sprite)
	patches.append({"sprite":sprite,"effect":effect,"kind":kind,"material":pixel_material,"uv":uv})

func _make_bank(entry: Array) -> void:
	var texture := ScenarioCatalog.texture("res://assets/atmosphere/menu_water_mist_v1.png")
	if texture==null: return
	var sprite := Sprite2D.new()
	sprite.name = "TerrainDrift%d"%banks.size()
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0,texture.get_height()*.5,texture.get_width(),texture.get_height()*.5)
	var uv := Catalog.region(Rect2(float(entry[0]),float(entry[1]),float(entry[2]),float(entry[3])))
	var origin: Vector2 = scenery.panorama_rect.position+uv.position*scenery.panorama_rect.size
	sprite.position = origin
	sprite.scale = uv.size*scenery.panorama_rect.size/sprite.region_rect.size
	var bank_material := ShaderMaterial.new()
	bank_material.shader = preload("res://shaders/menu_water_mist.gdshader")
	bank_material.set_shader_parameter("mist_tint",Color(str(Catalog.BANK_COLORS.get(str(entry[4]),"a5afb3"))))
	sprite.material = bank_material
	add_child(sprite)
	banks.append({"sprite":sprite,"origin":origin,"kind":str(entry[4]),"phase":banks.size()*2.47})

func _make_plume(entry: Array) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var tint := Color(str(Catalog.PLUME_COLORS.get(str(entry[3]),"c1ccd0")),.50)
	for puff in 28:
		for cluster in 5:
			var first := vertices.size()
			for direction: Vector2 in OCTAGON:
				vertices.append(Vector3(direction.x,direction.y,0))
				uvs.append(Vector2(puff,cluster))
				colors.append(tint)
			for triangle in range(1,7): indices.append_array(PackedInt32Array([first,first+triangle,first+triangle+1]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.custom_aabb=AABB(Vector3(-760,-290,-1),Vector3(1520,390,2))
	var node := MeshInstance2D.new()
	node.name="LocalizedVapor%d"%plumes.size()
	node.mesh=mesh
	node.position=scenery.panorama_rect.position+Catalog.point(Vector2(float(entry[0]),float(entry[1])))*scenery.panorama_rect.size
	node.scale=Vector2.ONE*float(entry[2])
	var plume_material := ShaderMaterial.new()
	plume_material.shader=SMOKE
	plume_material.set_shader_parameter("smoke_origin",Vector2.ZERO)
	plume_material.set_shader_parameter("emitter_index",float(plumes.size()))
	plume_material.set_shader_parameter("wind_phase",float(scenery.atmosphere.phase))
	plume_material.set_shader_parameter("base_wind",float(scenery.atmosphere.base_wind))
	plume_material.set_shader_parameter("gust_strength",float(scenery.atmosphere.weather_profile.get("gust",1.0)))
	node.material=plume_material
	add_child(node)
	plumes.append(node)

func lamp_level(index: int,at: float) -> float:
	var kind := str(patches[index].kind)
	var phase := index*1.73+float(posmod(str(scenery.environment_id).hash(),17))*.21
	if kind in ["beacon","white"]:
		var pulse := fposmod(at+phase,6.4+index*.17)
		return .40+smoothstep(.3,.7,pulse)*(1.0-smoothstep(1.2,1.7,pulse))*.95
	if kind=="furnace": return 1.10+sin(at*.71+phase)*.17+sin(at*1.21+phase*1.3)*.07
	return 1.05+sin(at*.47+phase)*.10-smoothstep(.82,.98,sin(at*.23+phase))*.22

func update_at(at: float,is_reduced: bool,wind: float) -> void:
	elapsed=at
	reduced=is_reduced
	for index in patches.size():
		var patch: Dictionary=patches[index]
		var sprite: Sprite2D=patch.sprite
		sprite.visible=not is_reduced or int(patch.effect)==1
		if not sprite.visible: continue
		patch.material.set_shader_parameter("landmark_clock",at)
		patch.material.set_shader_parameter("motion_strength",.14 if is_reduced else 1.0)
		if int(patch.effect)==0: patch.material.set_shader_parameter("illumination",lamp_level(index,at))
	for index in banks.size():
		var bank: Dictionary=banks[index]
		var sprite: Sprite2D=bank.sprite
		var wave:=.5+.5*sin(at*.21+float(bank.phase))
		var gust:=clampf(absf(wind)/72.0,.05,1.0)
		var strength:=.035+wave*.055+gust*.045
		if bank.kind=="mist": strength*=1.35
		sprite.modulate.a=strength*(.30 if is_reduced else 1.0)
		sprite.position=Vector2(bank.origin)+Vector2(sin(at*.14+float(bank.phase))*18.0+wind*.14,sin(at*.19+float(bank.phase))*2.0)
	for plume in plumes:
		plume.material.set_shader_parameter("smoke_clock",at)
		plume.material.set_shader_parameter("reduced_effects",is_reduced)
