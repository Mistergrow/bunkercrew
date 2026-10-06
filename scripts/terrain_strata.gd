extends Node2D
## Static geological backing. Rooms and real mining cells draw above this field.
## One cached draw replaces repeated tiles; shader coordinates stay in the world.

const ROCK := preload("res://assets/rock.png")
const STRATA_SHADER := preload("res://shaders/terrain_strata.gdshader")
const FIELD := Rect2(-8192, 430, 17824, 8192)
const PROFILES := {
	"storm_dam": [Color("859aa6"),Color("596975"),Color("a7b1ad"),-.11],
	"sulfur_refinery": [Color("b2a878"),Color("887844"),Color("cfbc76"),.17],
	"radar_highlands": [Color("9c9dbb"),Color("6d7498"),Color("c0bed0"),-.22],
	"buried_megafactory": [Color("b0938c"),Color("885e53"),Color("c29d83"),.32],
	"sector07": [Color("aaa797"), Color("756b59"), Color("b5aa89"), 0.12],
	"ash_foundry": [Color("a8a19a"), Color("827466"), Color("ac977c"), 0.21],
	"abandoned_harbor": [Color("849fa6"), Color("577d79"), Color("a7b7a4"), 0.07],
	"basalt_quarry": [Color("a7a2b7"), Color("817b94"), Color("c1b6b2"), -0.14],
	"overgrown_steelworks": [Color("a0ac88"), Color("63754e"), Color("aaa980"), 0.10],
	"frozen_rail_yard": [Color("9bafc1"), Color("778e9c"), Color("c6d8de"), -0.07],
	"iron_canyon": [Color("c2a18d"), Color("ae755c"), Color("d8b78b"), 0.26],
	"flooded_power_station": [Color("8fa89c"), Color("577c70"), Color("afc0a2"), -0.04],
	"mountain_pass": [Color("a0a4bf"), Color("727b93"), Color("b4b7c6"), -0.19],
}

var environment_id := "sector07"

func _ready() -> void:
	name = "TerrainStrata"
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var spec: Array = PROFILES.get(environment_id, PROFILES.sector07)
	var strata_material := ShaderMaterial.new()
	strata_material.shader = STRATA_SHADER
	strata_material.set_shader_parameter("rock_tint", spec[0])
	strata_material.set_shader_parameter("seam_tint", spec[1])
	strata_material.set_shader_parameter("soil_tint", spec[2])
	strata_material.set_shader_parameter("inclination", spec[3])
	material = strata_material

func _draw() -> void:
	draw_texture_rect(ROCK, FIELD, true)
