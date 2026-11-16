extends Node2D
## Pays the renderer's one-time costs while the scenario loads instead of in
## the middle of the first fight.
##
## The Compatibility renderer prepares a canvas shader variant the first time
## something draws with it under the same lighting. The scenery, bunker and
## crew are drawn from the first frame on; wrecks, remains, pickups and grid
## effects are not. The first wreck used to stall its frame for about half a
## second (perf.wave_night probe, frame 152, an aircraft shot down). The first
## shadow-casting light (blast and fire lamps; fixtures never cast shadows) has
## a first-use cost of its own.
##
## For a few drawn frames this node draws each of those materials once per
## command kind, one design pixel at an alpha nobody can see, lit by a shadowed
## lamp set up like a blast lamp, then removes itself. Presentation only: no
## simulation, network or saved state is touched.
##
## The variant also depends on whether any lamp reaches the item's z: impact
## bursts draw above the lamps' z range (ImpactBurst at 24, its glow at 25), and
## their unlit and additive layers stalled the first ground explosion of a
## session by 200-300 ms (perf.kills_bright, frame 59) although the same
## materials had been drawn at z 0. Every probe is therefore drawn twice: once
## inside the lamps' range and once above it.

const FIRE_LIGHTING := preload("res://scripts/scenery_fire_lighting.gd")
const PIXEL_EFFECT_ART := preload("res://scripts/pixel_effect_art.gd")
const FRAMES := 4
## Shaders whose event draws sample an actor atlas (wrecks, infantry remains,
## pickups). The software rasteriser builds a variant per texture as well (its
## size class and format are part of the key), so after the world-texel atlases
## replaced the power-of-two sources the first corpse and the first wreck
## stalled software frames for 140-260 ms although the shaders were warm.
const TEXTURED_SHADERS := ["res://shaders/actor_wreck.gdshader", "res://shaders/ground_infantry_remains.gdshader", "res://shaders/pickup_cutout.gdshader"]
## The atlases those draws use. Missing files are skipped.
const EVENT_TEXTURES := [
	"res://assets/enemies/infantry_parts_world.png", "res://assets/enemies/infantry_limbs_world.png",
	"res://assets/enemies/infantry_turns_world.png", "res://assets/enemies/infantry_living_turns_world.png",
	"res://assets/enemies/infantry_gun_turns_world.png", "res://assets/enemies/aircraft_hulls_world.png",
	"res://assets/enemies/chassis_world.png", "res://assets/enemies/vehicle_hulls_world.png",
	"res://assets/enemies/machine_weapons_world.png", "res://assets/enemies/vehicle_guns_world.png",
	"res://assets/enemies/aircraft_pods_v2.png", "res://assets/enemies/shield_bubble_world.png",
]
## Absolute z of the second probe set: above every lamp's z range
## (scenery_fire_lighting: -8..20), where impact bursts draw.
const ABOVE_LAMPS_Z := 24

var game: Node2D

## The materials first drawn by combat events: shared instances where the game
## keeps one, otherwise the shader itself.
static func event_materials() -> Array[Material]:
	var lighting := FIRE_LIGHTING.WorldLighting
	var found: Array[Material] = [
		PIXEL_EFFECT_ART.grid_material(PIXEL_EFFECT_ART.GRID_LIT),
		PIXEL_EFFECT_ART.grid_material(PIXEL_EFFECT_ART.GRID_UNLIT),
		PIXEL_EFFECT_ART.grid_material(PIXEL_EFFECT_ART.GRID_ADD),
		PIXEL_EFFECT_ART.additive_material(),
		PIXEL_EFFECT_ART.unlit_material(),
		lighting.unshaded_material(),
		lighting.additive_material(),
		preload("res://scripts/enemy_motion_wreck.gd").wreck_material(),
		preload("res://scripts/pickup_art.gd").cutout_material(),
	]
	var remains := ShaderMaterial.new()
	remains.shader = preload("res://shaders/ground_infantry_remains.gdshader")
	found.append(remains)
	return found

## The event atlases, loaded here so the first wreck or corpse neither waits on
## the file nor on its first draw.
static func event_textures() -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for path: String in EVENT_TEXTURES:
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture != null: found.append(texture)
	return found

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Inside the lamps' z range (scenery_fire_lighting: -8..20): a probe outside
	# it compiles only the unlit variant, which the effects never use.
	z_index = 0
	var lamp := FIRE_LIGHTING.make_lamp("WarmupLight", FIRE_LIGHTING.WorldLighting.shadows_allowed())
	lamp.texture = FIRE_LIGHTING.surface_texture()
	lamp.energy = 0.01
	add_child(lamp)
	_textures = event_textures()
	for prepared in event_materials():
		for above in [false, true]:
			var probe := Node2D.new()
			probe.material = prepared
			probe.modulate = Color(1, 1, 1, 0.02)
			probe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if above:
				probe.z_as_relative = false
				probe.z_index = ABOVE_LAMPS_Z
			probe.draw.connect(_draw_probe.bind(probe))
			add_child(probe)
	_follow(lamp)
	lamp.enabled = true
	for frame in FRAMES:
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		_follow(lamp)
	queue_free()

func _draw_probe(probe: Node2D) -> void:
	# Each command kind is its own variant, and so is a batch of one quad
	# versus several: textured quads in a run, a polygon, a lone quad and a
	# primitive (the grid effects draw primitives).
	probe.draw_texture_rect(_sprite_texture(), Rect2(0, 0, 1, 1), false)
	probe.draw_texture_rect(_sprite_texture(), Rect2(0, 0, 1, 1), false)
	probe.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), Color.WHITE)
	probe.draw_rect(Rect2(0, 0, 1, 1), Color.WHITE)
	probe.draw_primitive(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), PackedVector2Array())
	# The grid effects' own quads (four points with an encoded shape UV), as
	# the effect layers draw them.
	PIXEL_EFFECT_ART.grid_fire(probe, Vector2(2, 2), 2.0, 1.0)
	PIXEL_EFFECT_ART.grid_halo(probe, Vector2(2, 2), 2.5, Color.WHITE)
	PIXEL_EFFECT_ART.grid_line(probe, Vector2(0, 0), Vector2(3, 1), Color.WHITE)
	# The atlas-sampling event shaders once more with every real atlas, as a run
	# of regions the way the wreck and corpse rigs draw their parts.
	var shaded := probe.material as ShaderMaterial
	if shaded != null and shaded.shader != null and TEXTURED_SHADERS.has(shaded.shader.resource_path):
		for texture in _textures:
			probe.draw_texture_rect_region(texture, Rect2(0, 0, 1, 1), Rect2(0, 0, 1, 1))
			probe.draw_texture_rect_region(texture, Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1))

var _textures: Array[Texture2D] = []
var _sprite: ImageTexture

## A texture in the sprites' own format: the software rasteriser prepares
## code per texture format as well.
func _sprite_texture() -> ImageTexture:
	if _sprite == null:
		_sprite = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	return _sprite

func _follow(lamp: PointLight2D) -> void:
	# Centred on what the camera shows, so the probes are inside the view and
	# the lamp reaches every visible receiver.
	var view := get_viewport_rect().size
	var camera: Camera2D = game.get("camera") if is_instance_valid(game) else null
	var centre: Vector2 = camera.get_screen_center_position() if is_instance_valid(camera) else view * 0.5
	lamp.global_position = centre
	lamp.texture_scale = maxf(view.x, view.y) * 1.5 / float(lamp.texture.get_width())
	for child in get_children():
		if child != lamp and child is Node2D: child.global_position = centre.floor()
