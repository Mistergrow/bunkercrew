class_name DistantHorizon
extends Node2D
## Textured, world-anchored scenery beyond the unique central panorama.
## Only visible atlas blocks are submitted; camera movement never moves land.
const ATLAS_PATH := "res://assets/environments/distant_horizon.png"
const ATLAS_REGIONS := [Rect2(0,90,1774,180),Rect2(0,356,1774,146),Rect2(0,548,1774,131),Rect2(0,726,1774,161)]
const LAND_BASE := 430.0
const MAX_BLOCKS_PER_DEPTH := 16
const DEPTH_WIDTHS := [2100.0,1740.0,1460.0]
const DEPTH_OFFSETS := [-417.0,193.0,-631.0]
const PROFILES := {
	"storm_dam":{"rows":[0,0,1],"heights":[306.0,237.0,144.0],"shadow":"#1e2c37","light":"#415563","mist":"#637b8d"},
	"sulfur_refinery":{"rows":[3,3,2],"heights":[214.0,162.0,91.0],"shadow":"#403827","light":"#7b6940","mist":"#b3a062"},
	"radar_highlands":{"rows":[0,0,0],"heights":[329.0,237.0,136.0],"shadow":"#242942","light":"#535b80","mist":"#828bae"},
	"buried_megafactory":{"rows":[3,2,3],"heights":[253.0,187.0,121.0],"shadow":"#392c30","light":"#704b45","mist":"#98766d"},
	"sector07":{"rows":[0,2,2],"heights":[225.0,153.0,86.0],"shadow":"#1b2632","light":"#374757","mist":"#4f5265"},
	"ash_foundry":{"rows":[0,2,2],"heights":[227.0,179.0,104.0],"shadow":"#101b26","light":"#263b4f","mist":"#32485c"},
	"abandoned_harbor":{"rows":[1,0,2],"heights":[182.0,127.0,70.0],"shadow":"#082732","light":"#254b59","mist":"#366574"},
	"basalt_quarry":{"rows":[0,3,0],"heights":[294.0,226.0,145.0],"shadow":"#30354b","light":"#656181","mist":"#908298"},
	"overgrown_steelworks":{"rows":[1,1,1],"heights":[256.0,197.0,118.0],"shadow":"#273e34","light":"#667b5a","mist":"#9ba68c"},
	"frozen_rail_yard":{"rows":[0,1,2],"heights":[242.0,161.0,97.0],"shadow":"#325b7a","light":"#75b3e0","mist":"#acd0e6"},
	"iron_canyon":{"rows":[3,3,3],"heights":[325.0,239.0,144.0],"shadow":"#63333b","light":"#a76246","mist":"#ca967f"},
	"flooded_power_station":{"rows":[0,1,1],"heights":[251.0,169.0,91.0],"shadow":"#234b47","light":"#628977","mist":"#99b1a0"},
	"mountain_pass":{"rows":[0,0,1],"heights":[405.0,295.0,165.0],"shadow":"#202e50","light":"#435779","mist":"#596891"},
}
const HORIZON_SHADER := preload("res://shaders/distant_horizon.gdshader")
var environment_id := "sector07"
var profile: Dictionary = PROFILES.sector07
var baseline := LAND_BASE
var atlas: Texture2D
var layers: Array[Node2D] = []
var visible_rect := Rect2(-2000,-800,5440,1230)
var _block_ranges: Array[Vector2i] = []

func configure(scenery: Node) -> void:
	environment_id = str(scenery.environment_id)
	profile = PROFILES.get(environment_id,PROFILES.sector07)
	baseline = LAND_BASE
	var water_regions: Array = scenery.data.get("water_regions",[])
	if not water_regions.is_empty() and bool(scenery.data.get("water_extend",true)):
		baseline = roundf(scenery.panorama_rect.position.y+float(water_regions[0][1])*scenery.panorama_rect.size.y)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas = load(ATLAS_PATH) as Texture2D
	var shader := HORIZON_SHADER
	for layer in layers:
		remove_child(layer)
		layer.queue_free()
	layers.clear()
	for depth in 3:
		var layer := Node2D.new()
		layer.name = "DistantTerrain%d"%depth
		var layer_material := ShaderMaterial.new()
		layer_material.shader = shader
		layer_material.set_shader_parameter("shadow_tint",Color(profile.shadow))
		layer_material.set_shader_parameter("light_tint",Color(profile.light))
		layer_material.set_shader_parameter("mist_tint",Color(profile.mist))
		layer_material.set_shader_parameter("distance_haze",[.34,.15,.025][depth])
		layer.material = layer_material
		layer.draw.connect(_draw_depth.bind(layer,depth))
		add_child(layer)
		layers.append(layer)
	_block_ranges.clear()
	update_view(visible_rect)

func update_view(rect: Rect2,_zoom: float=1.0) -> void:
	visible_rect = rect
	var ranges: Array[Vector2i] = []
	for depth in 3:
		ranges.append(visible_blocks(depth,rect))
	if ranges==_block_ranges: return
	_block_ranges = ranges
	for layer in layers: layer.queue_redraw()

func configure_cloud_mask(cloud_material: ShaderMaterial) -> void:
	# Both materials use the same atlas, overlap, mirrored blocks and baseline.
	# This avoids clouds being cut by a stretched panorama-edge sky mask.
	cloud_material.set_shader_parameter("mask_extended_land",true)
	cloud_material.set_shader_parameter("extended_land",atlas)
	cloud_material.set_shader_parameter("land_baseline",baseline)
	cloud_material.set_shader_parameter("land_widths",Vector3(DEPTH_WIDTHS[0],DEPTH_WIDTHS[1],DEPTH_WIDTHS[2]))
	cloud_material.set_shader_parameter("land_offsets",Vector3(DEPTH_OFFSETS[0],DEPTH_OFFSETS[1],DEPTH_OFFSETS[2]))
	cloud_material.set_shader_parameter("land_heights",Vector3(profile.heights[0],profile.heights[1],profile.heights[2]))
	for depth in 3:
		var region: Rect2 = ATLAS_REGIONS[int(profile.rows[depth])]
		var origin := region.position/atlas.get_size()
		var size := region.size/atlas.get_size()
		cloud_material.set_shader_parameter("land_region_%d"%depth,Vector4(origin.x,origin.y,size.x,size.y))

func visible_blocks(depth: int,rect: Rect2) -> Vector2i:
	var height := float(profile.heights[depth])
	if rect.end.y<baseline-height or rect.position.y>baseline:
		return Vector2i(0,-1)
	var width := float(DEPTH_WIDTHS[depth])
	var period := width*.74
	var offset := float(DEPTH_OFFSETS[depth])
	var first := floori((rect.position.x-offset-width)/period)+1
	var last := floori((rect.end.x-offset)/period)
	return Vector2i(first,mini(last,first+MAX_BLOCKS_PER_DEPTH-1))

func block_rect(depth: int,index: int) -> Rect2:
	var width := float(DEPTH_WIDTHS[depth])
	var height := float(profile.heights[depth])
	return Rect2(roundf(index*width*.74+float(DEPTH_OFFSETS[depth])),baseline-height,width,height)

func _draw_depth(layer: Node2D,depth: int) -> void:
	if atlas==null or _block_ranges.size()!=3: return
	var span := _block_ranges[depth]
	var source: Rect2 = ATLAS_REGIONS[int(profile.rows[depth])]
	for index in range(span.x,span.y+1):
		var destination := block_rect(depth,index)
		# Alternating whole, generic terrain strips vary slope direction without
		# mirroring or duplicating a landmark from the authored panorama.
		var mirrored := posmod(index+depth,2)==1
		var origin := destination.position+Vector2(destination.size.x if mirrored else 0.0,0)
		layer.draw_set_transform(origin,0,Vector2(-1 if mirrored else 1,1))
		layer.draw_texture_rect_region(atlas,Rect2(Vector2.ZERO,destination.size),source)
	layer.draw_set_transform(Vector2.ZERO)
