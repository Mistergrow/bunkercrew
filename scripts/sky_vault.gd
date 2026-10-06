extends Node2D
## A world-anchored sky. The horizon joins the authored biome sky colors;
## opening the camera reveals altitude, rather than a larger flat color fill.
const PROFILES := {
	"storm_dam":{"zenith":"182a3b","glow":"bfc4c3","light":Vector2(-350,-720),"strength":.11},
	"sulfur_refinery":{"zenith":"5e5843","glow":"ebca6d","light":Vector2(1330,-510),"strength":.23},
	"radar_highlands":{"zenith":"191e40","glow":"aaa7da","light":Vector2(-290,-720),"strength":.16,"stars":.22},
	"buried_megafactory":{"zenith":"302330","glow":"d39168","light":Vector2(1340,-640),"strength":.19},
	"sector07":{"zenith":"152334","glow":"c39a87","light":Vector2(-260,-570),"strength":.12},
	"ash_foundry":{"zenith":"0b172b","glow":"92a9bd","light":Vector2(1550,-720),"strength":.13,"stars":.48},
	"abandoned_harbor":{"zenith":"081d30","glow":"99c5d2","light":Vector2(-390,-640),"strength":.16,"stars":.27},
	"basalt_quarry":{"zenith":"554f73","glow":"ebc9ac","light":Vector2(-360,-490),"strength":.24},
	"overgrown_steelworks":{"zenith":"536f83","glow":"e0d3a7","light":Vector2(1390,-660),"strength":.26},
	"frozen_rail_yard":{"zenith":"36739d","glow":"dfe8d7","light":Vector2(-260,-690),"strength":.27},
	"iron_canyon":{"zenith":"6f617c","glow":"f4c79d","light":Vector2(1560,-520),"strength":.30},
	"flooded_power_station":{"zenith":"46666d","glow":"c4d7b5","light":Vector2(-500,-690),"strength":.20},
	"mountain_pass":{"zenith":"121c38","glow":"8f9cbf","light":Vector2(1560,-810),"strength":.12,"stars":.10},
}
var sky_material: ShaderMaterial
var horizon_y := 0.0
var bounds := Rect2()

func configure(scenery: Node2D) -> void:
	name = "UpperSky"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	horizon_y = scenery.panorama_rect.position.y
	var profile: Dictionary = PROFILES.get(scenery.environment_id,PROFILES.sector07)
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky_vault.gdshader")
	sky_material.set_shader_parameter("horizon_y",horizon_y)
	# Image edges can contain cliffs/forest already at the top. Sampling those
	# as air produces broad dark rectangular bands beyond the panorama.
	var sky := Color(str(scenery.data.get("sky_color","#25303d")))
	sky_material.set_shader_parameter("horizon_left",sky)
	sky_material.set_shader_parameter("horizon_right",sky)
	sky_material.set_shader_parameter("zenith",Color(profile.zenith))
	sky_material.set_shader_parameter("light_color",Color(profile.glow))
	sky_material.set_shader_parameter("light_position",profile.light)
	sky_material.set_shader_parameter("light_strength",float(profile.strength))
	sky_material.set_shader_parameter("star_strength",float(profile.get("stars",0)))
	material = sky_material

func update_view(view: Rect2) -> void:
	# The shader is static: only a camera crossing this padded grid rebuilds the
	# single quad. No full-screen CPU texture generation or per-frame noise.
	var start := (view.position/128.0).floor()*128.0-Vector2(128,128)
	var end := (view.end/128.0).ceil()*128.0+Vector2(128,128)
	end.y = minf(end.y,430.0)
	visible = end.y>start.y
	if not visible: return
	var next := Rect2(start,end-start)
	if next==bounds: return
	bounds = next
	queue_redraw()

func _draw() -> void:
	if bounds.has_area(): draw_rect(bounds,Color.WHITE)
