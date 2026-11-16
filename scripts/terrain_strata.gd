extends Node2D
## Static geological backing. Rooms and real mining cells draw above this field.
## One cached draw replaces repeated tiles; shader coordinates stay in the world.

const ROCK := preload("res://assets/rock.png")
const STRATA_SHADER := preload("res://shaders/terrain_strata.gdshader")
const LIGHTING := preload("res://scripts/world_lighting.gd")
const FIELD := Rect2(-8192, 430, 17824, 8192)
## Texels the drawn ground cover (drifts, tufts, heaps) may rise above the
## ground line. Drawn behind every playable item; it never collides.
const COVER_RISE := 26.0
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

## Catalog weather decides what lies on the ground: the cap is data-driven and
## a world without a weather entry keeps the plain compacted soil.
const SURFACES := {"snow":1, "clear":2, "rain":3, "storm":3, "mist":3, "ash":4, "dust":5}
const CAP_BASE := [Color("b5aa89"), Color("e6eff3"), Color("6f8750"), Color("858f8e"), Color("8d8a86"), Color("cdb98a")]
## Loose ground under the cover, by the same kinds: road gravel, frozen soil,
## loam, mud, cinder, sand. Its hue then leans toward the painted land.
const SUBSOIL_BASE := [Color("5c5246"), Color("4c4c54"), Color("463a2d"), Color("40372f"), Color("3b3735"), Color("8a7552")]

## The rock's own structure per world, so the underground differs by more than
## its tint (terrain_strata.gdshader, same texel grid and rock tile): kind,
## accent colour, strength. 0 rubble, 1 layered sediment, 2 crystal or ice
## veins, 3 columnar basalt, 4 slag and cinder with live embers, 5 roots and
## shell grit in loam, 6 seeping wet rock. A world without a row keeps rubble.
const GEOLOGY := {
	"sector07": [4, Color("b8643a"), .7],
	"ash_foundry": [4, Color("e0762e"), 1.0],
	"abandoned_harbor": [5, Color("c9c2a6"), .6],
	"basalt_quarry": [3, Color("8a86a0"), 1.0],
	"overgrown_steelworks": [5, Color("8a7a52"), 1.0],
	"frozen_rail_yard": [2, Color("cfe6f4"), .9],
	"iron_canyon": [1, Color("c97a4e"), 1.0],
	"flooded_power_station": [1, Color("7fa08e"), .7],
	"mountain_pass": [2, Color("d6d2e6"), .8],
	"storm_dam": [6, Color("9fc0cf"), 1.0],
	"sulfur_refinery": [1, Color("d8c25a"), 1.0],
	"radar_highlands": [2, Color("c8c6e8"), .9],
	"buried_megafactory": [1, Color("a8786a"), .8],
}

var environment_id := "sector07"
var surface_kind := 0

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
	var data: Dictionary = ScenarioCatalog.environment(environment_id)
	surface_kind = surface_for(data)
	strata_material.set_shader_parameter("surface_kind", surface_kind)
	strata_material.set_shader_parameter("cap_tint", cap_tint_for(data, surface_kind, spec[2]))
	strata_material.set_shader_parameter("accent_tint", accent_for(data, spec[1]))
	strata_material.set_shader_parameter("world_seed", float(posmod(environment_id.hash(), 977)))
	# The painted land along the ground line and the world's daylight decide
	# the topsoil hue and how light the first rooms' ground is.
	var key: Dictionary = LIGHTING.light_key(data)
	strata_material.set_shader_parameter("land_tint", key.land)
	strata_material.set_shader_parameter("subsoil_tint", subsoil_for(surface_kind, key.land))
	strata_material.set_shader_parameter("daylight", 1.0 - LIGHTING.night_for(data))
	strata_material.set_shader_parameter("ground_line", FIELD.position.y)
	strata_material.set_shader_parameter("cover_rise", COVER_RISE)
	strata_material.set_shader_parameter("rich", not LIGHTING.software_renderer())
	var geology: Array = GEOLOGY.get(environment_id, [0, spec[1], 0.0])
	strata_material.set_shader_parameter("geology", int(geology[0]))
	strata_material.set_shader_parameter("vein_tint", geology[1])
	strata_material.set_shader_parameter("geology_strength", float(geology[2]))
	material = strata_material

static func surface_for(data: Dictionary) -> int:
	return int(SURFACES.get(str(data.get("weather", "")), 0))

## The cap keeps its material's own hue and leans toward the world's painted
## mid-tone, so snow in a violet highland differs from snow in a blue rail yard.
static func cap_tint_for(data: Dictionary, kind: int, soil: Color) -> Color:
	if kind == 0: return soil
	var palette: Array = data.get("palette", [])
	var base: Color = CAP_BASE[clampi(kind, 0, CAP_BASE.size() - 1)]
	if palette.size() < 2: return base
	return base.lerp(Color(str(palette[1])), .12 if kind == 1 else .34)

## Loose ground of a kind, its hue leaning a third toward the measured land
## colour along the ground line while it keeps its own value.
static func subsoil_for(kind: int, land: Color) -> Color:
	var base: Color = SUBSOIL_BASE[clampi(kind, 0, SUBSOIL_BASE.size() - 1)]
	var value := LIGHTING.luminance(base)
	var land_value := maxf(.02, LIGHTING.luminance(land))
	var hued := Color(land.r / land_value * value, land.g / land_value * value, land.b / land_value * value)
	return base.lerp(hued, .33)

## The last palette entry is each world's warm or pale accent (embers, lamps).
static func accent_for(data: Dictionary, fallback: Color) -> Color:
	var palette: Array = data.get("palette", [])
	return Color(str(palette[-1])) if not palette.is_empty() else fallback

func set_ambient(color: Color) -> void:
	if material is ShaderMaterial: material.set_shader_parameter("ambient", color)

## Sky key on the exposed surface (rgb colour, a strength) from WorldLighting.
func set_sky_rim(rim: Color) -> void:
	if material is ShaderMaterial: material.set_shader_parameter("sky_rim", rim)

## Lightning on the exposed surface only: strength and the bolt's world x.
func set_flash(strength: float, at_x: float) -> void:
	if not material is ShaderMaterial: return
	material.set_shader_parameter("flash", strength)
	material.set_shader_parameter("flash_x", at_x)

func _draw() -> void:
	draw_texture_rect(ROCK, Rect2(FIELD.position - Vector2(0, COVER_RISE), FIELD.size + Vector2(0, COVER_RISE)), true)
